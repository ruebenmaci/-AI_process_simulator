#include <algorithm>
#include <cmath>
#include <functional>
#include <iomanip>
#include <limits>
#include <mutex>
#include <numeric>
#include <sstream>
#include <unordered_map>

#include "PH_PS_PT_TS_Flash.hpp"
#include "ThermoConfig.hpp"
#include "Enthalpy.hpp"
#include "Entropy.hpp"
#include "EOSK.hpp"
#include "../../thermo/Flash.hpp"
#include <iostream>

static inline bool isFinite(double x) { return std::isfinite(x); }

static std::pair<double, double> minmaxFinite(const std::vector<double>& K) {
   double mn = +1e300, mx = -1e300;
   for (double v : K) if (isFinite(v)) { mn = std::min(mn, v); mx = std::max(mx, v); }
   if (!(mn < 1e299)) mn = std::numeric_limits<double>::quiet_NaN();
   if (!(mx > -1e299)) mx = std::numeric_limits<double>::quiet_NaN();
   return { mn, mx };
}

static std::unordered_map<int, int> g_kdbgCountByTray; // keyed by in.trayIndex

static double clamp(double x, double lo, double hi) {
   return std::max(lo, std::min(hi, x));
}

static std::vector<double> normalize(const std::vector<double>& z) {
   if (z.empty())
      return {};
   double s = 0.0;
   for (double v : z)
      if (isFinite(v))
         s += v;
   if (!isFinite(s) || s <= 0.0)
      return std::vector<double>(z.size(), 1.0 / std::max<size_t>(1, z.size()));
   std::vector<double> out(z.size(), 0.0);
   for (size_t i = 0; i < z.size(); ++i)
      out[i] = isFinite(z[i]) ? (z[i] / s) : 0.0;
   return out;
}

static std::vector<double> wilsonKValues(double T, double P, const std::vector<Component>& comps) {
   const double T_safe = std::max(1e-6, T);
   const double P_safe = std::max(1e-6, P);
   std::vector<double> K;
   K.reserve(comps.size());
   for (const auto& c : comps) {
      const double Tc = c.Tc;
      const double Pc = c.Pc;
      const double omega = isFinite(c.omega) ? c.omega : 0.0;
      if (!isFinite(Tc) || !isFinite(Pc) || Tc <= 0.0 || Pc <= 0.0) {
         K.push_back(1.0);
         continue;
      }
      const double exponent = 5.37 * (1.0 + omega) * (1.0 - (Tc / T_safe));
      const double kv = (Pc / P_safe) * std::exp(exponent);
      K.push_back(clamp(kv, 1e-6, 1e6));
   }
   return K;
}

static void logKDebugIfWanted(const FlashPHInput& in,
   double T,
   const std::string& tag,
   const std::vector<double>& Kraw,
   const std::vector<double>& Kuse,
   const RRAndComp& rr)
{
   // Only print for a few trays so logs don't explode
   const int t1 = in.trayIndex + 1;
   if (!(t1 == 2 || t1 == 8 || t1 == 15 || t1 == 21 || t1 == 30))
      return;

   auto fmt5 = [](const std::vector<double>& K)->std::string {
      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(6);
      for (int i = 0; i < 5; ++i) {
         if (i) os << ",";
         if (i < (int)K.size() && std::isfinite(K[i])) os << K[i];
         else os << "nan";
      }
      return os.str();
      };

   double kmin_raw = 1e300, kmax_raw = -1e300, kmin_use = 1e300, kmax_use = -1e300;
   for (double v : Kraw)
      if (std::isfinite(v))
      {
         kmin_raw = std::min(kmin_raw, v); kmax_raw = std::max(kmax_raw, v);
      }
   for (double v : Kuse)
      if (std::isfinite(v))
      {
         kmin_use = std::min(kmin_use, v); kmax_use = std::max(kmax_use, v);
      }
   if (kmin_raw > 1e200)
      kmin_raw = std::numeric_limits<double>::quiet_NaN();
   if (kmax_raw < -1e200)
      kmax_raw = std::numeric_limits<double>::quiet_NaN();
   if (kmin_use > 1e200)
      kmin_use = std::numeric_limits<double>::quiet_NaN();
   if (kmax_use < -1e200)
      kmax_use = std::numeric_limits<double>::quiet_NaN();

   std::ostringstream os;
   os.setf(std::ios::fixed); os.precision(6);
   os << "[K_DEBUG] " << tag
      << " tray=" << t1
      << " T=" << T
      << " P=" << in.P
      << " force2p=" << (in.forceTwoPhase ? 1 : 0)
      << " disableSP=" << (in.disableSinglePhaseShortCircuit ? 1 : 0)
      << " Kraw(min,max)=(" << kmin_raw << "," << kmax_raw << ")"
      << " Kuse(min,max)=(" << kmin_use << "," << kmax_use << ")"
      << " rrV=" << rr.V
      << " rrPhase=" << rr.phase
      << " Kraw0-4=" << fmt5(Kraw)
      << " Kuse0-4=" << fmt5(Kuse);
   in.log(os.str());
}

static bool shouldLogPHResid(int trayIndex, double dH)
{
   static std::unordered_map<int, int> g_count;
   static std::mutex g_m;

   std::lock_guard<std::mutex> lk(g_m);
   int& c = g_count[trayIndex];
   ++c;

   // Always keep the first few
   if (c <= 6)
      return true;

   const double adH = std::abs(dH);

   // Near convergence: log more often
   if (adH < 1e-3)
      return (c % 5) == 0;
   if (adH < 1e-2)
      return (c % 10) == 0;

   // Otherwise: low rate
   return (c % 25) == 0;
}

#include <cmath>
#include <mutex>
#include <unordered_map>
#include <cstdint>

static bool shouldLogPHKsrc(
   int tray,
   bool singlePhase,
   double T,
   double Kmin,
   double Kmax)
{
   struct Key {
      int tray;
      bool singlePhase;
      bool operator==(const Key& o) const noexcept {
         return tray == o.tray && singlePhase == o.singlePhase;
      }
   };

   struct KeyHash {
      std::size_t operator()(const Key& k) const noexcept {
         // Simple stable hash: tray in low bits, phase in bit 31
         return (static_cast<std::size_t>(static_cast<uint32_t>(k.tray)) << 1) ^
            static_cast<std::size_t>(k.singlePhase ? 1u : 0u);
      }
   };

   static std::mutex m;
   static std::unordered_map<Key, int, KeyHash> count;
   static std::unordered_map<Key, double, KeyHash> lastT;
   static std::unordered_map<Key, double, KeyHash> lastKspan;

   // Also track last phase seen per tray so we can log phase flips once.
   static std::unordered_map<int, bool> lastPhaseByTray;

   // ---- tuning knobs ----
   constexpr int    PERIOD_N = 100;   // was 20 -> too chatty during PH bracketing
   constexpr double DT_THRESHOLD = 10.0;  // was 2.0
   constexpr double DKSPAN_THRESHOLD = 5.0;   // was 0.5

   // Guard against NaN/Inf inputs (don’t spam logs because math blew up)
   if (!std::isfinite(T) || !std::isfinite(Kmin) || !std::isfinite(Kmax)) {
      // Only log the *first* time we encounter non-finite for this key.
      std::lock_guard<std::mutex> lock(m);
      Key key{ tray, singlePhase };
      int& c = count[key];
      c++;
      return (c == 1);
   }

   double Kspan = Kmax - Kmin;

   std::lock_guard<std::mutex> lock(m);

   // Phase-flip logging (tray-level): if we switched singlePhase flag, log once immediately.
   bool phaseFlip = false;
   auto itPhase = lastPhaseByTray.find(tray);
   if (itPhase == lastPhaseByTray.end()) {
      lastPhaseByTray[tray] = singlePhase;
      phaseFlip = true; // first observation
   }
   else if (itPhase->second != singlePhase) {
      itPhase->second = singlePhase;
      phaseFlip = true;
   }

   Key key{ tray, singlePhase };

   int& c = count[key];
   c++;

   const bool first = (c == 1);
   const bool periodic = (c % PERIOD_N == 0);

   // If we haven't logged yet for this key, treat as changed so we emit "first".
   const double prevT = (lastT.find(key) != lastT.end()) ? lastT[key] : T;
   const double prevK = (lastKspan.find(key) != lastKspan.end()) ? lastKspan[key] : Kspan;

   const bool tempChanged = std::abs(T - prevT) > DT_THRESHOLD;
   const bool kChanged = std::abs(Kspan - prevK) > DKSPAN_THRESHOLD;

   const bool log =
      first ||
      phaseFlip ||
      periodic ||
      tempChanged ||
      kChanged;

   if (log) {
      lastT[key] = T;
      lastKspan[key] = Kspan;
   }

   return log;
}

static inline bool isFiniteD(double x) { return std::isfinite(x); }

static std::pair<double, double> rrSignTest_f0_f1(
   const std::vector<double>& z,
   const std::vector<double>& K)
{
   double f0 = 0.0;
   double f1 = 0.0;
   for (size_t i = 0; i < z.size() && i < K.size(); ++i) {
      const double zi = z[i];
      const double Ki = K[i];
      if (!isFiniteD(zi) || !isFiniteD(Ki)) continue;

      // f(0) = Σ z_i (K_i - 1)
      f0 += zi * (Ki - 1.0);

      // f(1) = Σ z_i (1 - 1/K_i)
      // guard Ki ~ 0
      if (std::fabs(Ki) > 1e-300) {
         f1 += zi * (1.0 - 1.0 / Ki);
      }
      else {
         // Ki ~ 0 -> 1/K huge -> term -> -inf (strongly indicates no vapor root)
         f1 += zi * (-1e300);
      }
   }
   return { f0, f1 };
}

static void logRRSignTest(
   const FlashPHInput& in,
   double T,
   const char* tag,
   const std::vector<double>& K,
   double Kmin,
   double Kmax,
   bool eosSinglePhase)
{
   if (!in.log)
      return;

   double f0 = 0.0;
   double f1 = 0.0;
   bool hasRoot = false;

   if (!eosSinglePhase) {
      const auto ff = rrSignTest_f0_f1(in.z, K);
      f0 = ff.first;
      f1 = ff.second;
      hasRoot = (f0 > 0.0 && f1 < 0.0);
   }
   else {
      // React parity: for single-phase evaluations, the RR sign test is skipped and reported as zeros.
      f0 = 0.0;
      f1 = 0.0;
      hasRoot = false;
   }

   // ---- Log only when there is a meaningful change ----
   struct RRSignSnapshot {
      double T = std::numeric_limits<double>::quiet_NaN();
      double f0 = std::numeric_limits<double>::quiet_NaN();
      double f1 = std::numeric_limits<double>::quiet_NaN();
      double Kmin = std::numeric_limits<double>::quiet_NaN();
      double Kmax = std::numeric_limits<double>::quiet_NaN();
      bool eosSinglePhase = false;
      bool hasRoot = false;
      bool initialized = false;
   };

   static std::unordered_map<std::string, RRSignSnapshot> s_last;

   auto changedEnough = [](double a, double b, double absTol, double relTol) -> bool {
      if (!std::isfinite(a) && !std::isfinite(b))
         return false;
      if (!std::isfinite(a) || !std::isfinite(b))
         return true;
      const double diff = std::fabs(a - b);
      const double scale = std::max(std::fabs(a), std::fabs(b));
      return diff > absTol && diff > relTol * std::max(1.0, scale);
      };

   // Key by tray + tag so Kraw/Kuse are tracked independently.
   const std::string key =
      std::to_string(in.trayIndex + 1) + "|" + (tag ? std::string(tag) : std::string(""));

   RRSignSnapshot cur;
   cur.T = T;
   cur.f0 = f0;
   cur.f1 = f1;
   cur.Kmin = eosSinglePhase ? std::numeric_limits<double>::quiet_NaN() : Kmin;
   cur.Kmax = eosSinglePhase ? std::numeric_limits<double>::quiet_NaN() : Kmax;
   cur.eosSinglePhase = eosSinglePhase;
   cur.hasRoot = hasRoot;
   cur.initialized = true;

   bool shouldLog = false;
   auto it = s_last.find(key);
   if (it == s_last.end() || !it->second.initialized) {
      shouldLog = true; // always log first one per tray/tag
   }
   else {
      const RRSignSnapshot& prev = it->second;

      // Always log if phase mode or root existence flips.
      if (prev.eosSinglePhase != cur.eosSinglePhase || prev.hasRoot != cur.hasRoot) {
         shouldLog = true;
      }
      // Or if temperature moved meaningfully.
      else if (changedEnough(prev.T, cur.T, 0.5, 1e-6)) {
         shouldLog = true;
      }
      // Or if RR sign metrics moved meaningfully.
      else if (changedEnough(prev.f0, cur.f0, 0.05, 0.02) ||
         changedEnough(prev.f1, cur.f1, 0.05, 0.02)) {
         shouldLog = true;
      }
      // Or if K-range moved meaningfully.
      else if (!cur.eosSinglePhase &&
         (changedEnough(prev.Kmin, cur.Kmin, 0.01, 0.02) ||
            changedEnough(prev.Kmax, cur.Kmax, 0.10, 0.02))) {
         shouldLog = true;
      }
   }

   if (!shouldLog)
      return;

   s_last[key] = cur;

   std::ostringstream os;
   os.setf(std::ios::fixed);
   os << std::setprecision(6);
   os << "[RR_SIGN] tray=" << (in.trayIndex + 1)
      << " tag=" << tag
      << " T=" << T
      << " P=" << in.P
      << " eosSinglePhase=" << (eosSinglePhase ? 1 : 0)
      << " f0=" << f0
      << " f1=" << f1
      << " root=" << (hasRoot ? 1 : 0)
      << " Kmin=" << (eosSinglePhase ? std::numeric_limits<double>::quiet_NaN() : Kmin)
      << " Kmax=" << (eosSinglePhase ? std::numeric_limits<double>::quiet_NaN() : Kmax);
   in.log(os.str());
}

static RRAndComp rrAndCompositions(const std::vector<double>& z,
   const std::vector<double>& K,
   int tray,
   double T,
   double P,
   const std::function<void(const std::string&)>& log) {
   RRAndComp out;
   RRDiag diag;
   diag.enable = false; // JS uses diag.log; we keep RR's own console prints optional elsewhere
   diag.tray = tray;
   diag.T = T;
   diag.P = P;
   diag.returnObject = true;
   // Track K-value range for diagnostics/UI
   double Kmin = std::numeric_limits<double>::infinity();
   double Kmax = 0.0;
   for (double ki : K) {
      if (std::isfinite(ki)) {
         Kmin = std::min(Kmin, ki);
         Kmax = std::max(Kmax, ki);
      }
   }
   if (!std::isfinite(Kmin))
      Kmin = std::numeric_limits<double>::quiet_NaN();
   if (Kmax <= 0.0 || !std::isfinite(Kmax))
      Kmax = std::numeric_limits<double>::quiet_NaN();
   out.Kmin = Kmin;
   out.Kmax = Kmax;

   RRResult rr = rachfordRice(z, K, &diag, log);

   out.V = clamp(rr.V, 0.0, 1.0);
   out.rrStatus = rr.status;
   out.rrReason = rr.reason;
   out.f0 = rr.f0; out.f1 = rr.f1; out.f0n = rr.f0n; out.f1n = rr.f1n; out.iters = rr.iters;
   out.phase = rr.phase;

   // endpoint single-phase shortcuts
   if (out.V <= 1e-10) {
      auto x = z;
      double sx = std::accumulate(x.begin(), x.end(), 0.0);
      if (sx == 0.0) sx = 1.0;
      for (double& v : x) v /= sx;
      out.V = 0.0;
      out.x = x;
      out.y = x;
      out.singlePhase = true;
      out.phase = "L";
      return out;
   }

   if (out.V >= 1.0 - 1e-10) {
      auto y = z;
      double sy = std::accumulate(y.begin(), y.end(), 0.0);
      if (sy == 0.0) sy = 1.0;
      for (double& v : y) v /= sy;
      out.V = 1.0;
      out.x = y;
      out.y = y;
      out.singlePhase = true;
      out.phase = "V";
      return out;
   }

   auto [x, y] = phaseCompositions(z, K, out.V);

   // Normalize x defensively; y was already computed as K*x in phaseCompositions
   // so independent y renormalization would break K_i = y_i/x_i.
   double sx = std::accumulate(x.begin(), x.end(), 0.0);
   if (sx == 0.0)
      sx = 1.0;
   for (double& v : x)
      v /= sx;
   // Recompute y from normalized x to preserve K = y/x
   for (size_t ii = 0; ii < x.size(); ++ii)
      y[ii] = (ii < K.size()) ? K[ii] * x[ii] : x[ii];

   out.x = std::move(x);
   out.y = std::move(y);
   return out;
}

// Overload that adds a lightweight tagged RR diagnostic line.
// This keeps the core rrAndCompositions() logic unchanged and avoids log spam.
static RRAndComp rrAndCompositions(const std::vector<double>& z,
   const std::vector<double>& K,
   int tray,
   double T,
   double P,
   const std::function<void(const std::string&)>& log,
   const char* tag)
{
   RRAndComp out = rrAndCompositions(z, K, tray, T, P, log);

   if (!log || !tag)
      return out;

   // With your RRResult conventions:
   //   "twoPhase"     => success
   //   "singlePhase"  => success
   //   "fail"         => real problem case to log
   const bool rrFail = (out.rrStatus == "fail");
   if (!rrFail)
      return out;  // ✅ no spam for normal cases

   double Kmin = std::numeric_limits<double>::infinity();
   double Kmax = -std::numeric_limits<double>::infinity();
   for (double Ki : K) {
      if (!std::isfinite(Ki) || Ki <= 0.0) continue;
      Kmin = std::min(Kmin, Ki);
      Kmax = std::max(Kmax, Ki);
   }

   std::ostringstream oss;
   oss.setf(std::ios::fixed);
   oss << std::setprecision(6);
   oss << "[" << tag << "_RR] tray=" << (tray + 1)
      << " T=" << T << " P=" << P
      << " rrStatus=" << out.rrStatus
      << " reason=" << out.rrReason
      << " phase=" << out.phase
      << " f0=" << out.f0 << " f1=" << out.f1
      << " Kmin=" << (std::isfinite(Kmin) ? Kmin : 0.0)
      << " Kmax=" << (std::isfinite(Kmax) ? Kmax : 0.0);
   log(oss.str());

   return out;
}

static void validateSinglePhase(const EosKResult& ek,
   const std::function<void(const std::string&)>& log,
   int tray,
   const char* tag)
{
   if (!log)
      return;
   if (ek.singlePhase && ek.phase != "L" && ek.phase != "V") {
      log(std::string("[BUG] ") + tag + " tray=" + std::to_string(tray) +
         " eosK singlePhase=true but phase='" + ek.phase + "'");
   }
}

FlashPHResult flashPH(const FlashPHInput& in) {
   if (!in.components) {
      throw std::invalid_argument("flashPH: components is null");
   }
   const auto& comps = *in.components;
   FlashPHResult ret;

   // Resolve EOS: prefer thermoConfig.thermoMethodId, fall back to eosManual, then PRSV.
   const std::string resolvedEos = !in.thermoConfig.thermoMethodId.empty()
      ? in.thermoConfig.thermoMethodId
      : (in.eosManual.empty() ? "PRSV" : in.eosManual);

   const double Tmin = 180.0, Tmax = 1200.0;
   const double T0 = clamp(isFinite(in.Tseed) ? in.Tseed : 660.0, Tmin, Tmax);

   auto log = [&](const std::string& s) {
      if (!logEnabled(in.logLevel)) return;
      if (in.log) {
         in.log(s);
      }
      else {
         std::cout << s << "\n";
      }
      };

   // ---- SEED DIAGNOSTIC (matches React PH ENTER detail) ----
   {
      auto ek_seed = eosK(in.P, T0, in.z, comps,
         in.trayIndex, in.trays, in.crudeName,
         in.kij, /*log=*/false,
         in.murphreeEtaV,
         in.eosMode,
         resolvedEos,
         in.log);

      RRAndComp rr_seed;
      if (ek_seed.singlePhase) {
         rr_seed.V = (ek_seed.phase == "V") ? 1.0 : 0.0;
         rr_seed.x = in.z;
         rr_seed.y = in.z;
      }
      else {
         rr_seed = rrAndCompositions(in.z, ek_seed.K,
            in.trayIndex, T0, in.P,
            in.log, "PH_SEED");
      }

      const double Hv_seed = hVap(rr_seed.y, T0, in.trayIndex, comps, in.P);
      const double Hl_seed = hLiq(rr_seed.x, T0, in.trayIndex, comps, in.P);

      if (in.log) {
         std::ostringstream os2;
         os2.setf(std::ios::fixed); os2.precision(6);
         os2 << "[PH_SEED_CHECK] tray=" << in.trayIndex + 1
            << " Hv=" << Hv_seed << " Hl=" << Hl_seed
            << " diff(Hv-Hl)=" << (Hv_seed - Hl_seed);
         log(os2.str());
      }

      const double Heq_seed = rr_seed.V * Hv_seed + (1.0 - rr_seed.V) * Hl_seed;
      const double dHseed = Heq_seed - in.Htarget;

      if (in.log) {
         std::ostringstream os;
         os.setf(std::ios::fixed);
         os.precision(6);
         os << "[PH_ENTER] tray=" << in.trayIndex + 1
            << " idx0=" << in.trayIndex
            << " Tseed=" << T0
            << " Htarget=" << in.Htarget
            << " P=" << in.P
            << " eosManual=" << (in.eosManual.empty() ? "(empty)" : in.eosManual)
            << " Hliq_seed=" << Hl_seed
            << " Hvap_seed=" << Hv_seed
            << " Heq_seed=" << Heq_seed
            << " dHseed=" << dHseed
            << " Vseed=" << rr_seed.V;
         log(os.str());
      }
   }

   bool kdebugPrinted = false;

   // bad target guard
   if (!isFinite(in.Htarget) || std::fabs(in.Htarget) > 1e6) {
      auto ek0 = eosK(in.P, T0, in.z, comps,
         in.trayIndex, in.trays, in.crudeName,
         in.kij, /*log=*/false, in.murphreeEtaV, in.eosMode, resolvedEos, in.log);

      RRAndComp rr;
      if (ek0.singlePhase) {
         rr.V = (ek0.phase == "V") ? 1.0 : 0.0;
         rr.x = in.z;
         rr.y = in.z;
      }
      else {
         rr = rrAndCompositions(in.z, ek0.K, in.trayIndex, T0, in.P, in.log, "PH");
      }

      if (in.log) {
         std::ostringstream os;
         os.setf(std::ios::fixed); os.precision(2);
         const double Hv = hVap(rr.y, T0, in.trayIndex, comps, in.P);
         const double Hl = hLiq(rr.x, T0, in.trayIndex, comps, in.P);
         const double Hcalc = rr.V * Hv + (1.0 - rr.V) * Hl;
         os << "[PH_OUT] tray=" << in.trayIndex + 1
            << " T=" << T0
            << " V=" << rr.V
            << " Hcalc=" << Hcalc
            << " dH=" << (Hcalc - in.Htarget);
         log(os.str());
      }

      ret.T = T0; ret.V = rr.V; ret.x = rr.x; ret.y = rr.y;
      ret.status = "bad-target";
      ret.dH = std::numeric_limits<double>::quiet_NaN();
      ret.Hcalc = std::numeric_limits<double>::quiet_NaN();
      ret.Htarget = in.Htarget;
      {
         const auto& xret = ret.x.empty() ? in.z : ret.x;
         const auto& yret = ret.y.empty() ? in.z : ret.y;
         const double Sv = sVap(yret, ret.T, in.trayIndex, comps, in.P);
         const double Sl = sLiq(xret, ret.T, in.trayIndex, comps, in.P);
         ret.Scalc = ret.V * Sv + (1.0 - ret.V) * Sl;
      }
      return ret;
   }

   // Residual function (ported 1:1)
   auto resid = [&](double T) -> RRAndComp {
      RRAndComp r;
      auto ek = eosK(in.P, T, in.z, comps,
         in.trayIndex, in.trays, in.crudeName,
         in.kij, /*log=*/false, in.murphreeEtaV, in.eosMode, resolvedEos, in.log);

      validateSinglePhase(ek, log, in.trayIndex, "PH_RESID");

      // React parity: treat "single-phase" as:
      //  - EOS explicitly reports singlePhase, OR
      //  - K values are all ~1 (degenerate RR), OR
      //  - EOS produced no finite K values (numerical failure -> behave like single-phase for sign-tests)
      int finiteK = 0;
      int nearOneK = 0;
      for (double kv : ek.K) {
         if (std::isfinite(kv)) {
            ++finiteK;
            if (std::fabs(kv - 1.0) < 0.05)
               ++nearOneK;
         }
      }

      const bool nearAllOnes = (finiteK > 0 && nearOneK == finiteK);
      const bool kAllNonFinite = (finiteK == 0);
      const bool eosSaysSinglePhase = ek.singlePhase || nearAllOnes || kAllNonFinite;

      if (eosSaysSinglePhase && in.log)
         in.log("[PH] eos singlePhase -> using " + std::string(in.disableSinglePhaseShortCircuit ? "Wilson+RR" : "shortcut"));

      std::vector<double> K;
      if (eosSaysSinglePhase) {
         // Decide phase from ek.phase if present, otherwise from Z
         std::string phase = !ek.phase.empty() ? ek.phase : ((isFinite(ek.Z) && ek.Z > 0.3) ? "V" : "L");

         // Compute phase-limit enthalpies at this T
         const double Hl_lim = hLiq(in.z, T, in.trayIndex, comps, in.P);
         const double Hv_lim = hVap(in.z, T, in.trayIndex, comps, in.P);

         // React parity: default behavior is to short-circuit immediately when EOS says single-phase.
         // (Only bypass this when disableSinglePhaseShortCircuit is explicitly enabled.)
         if (!in.disableSinglePhaseShortCircuit) {
            const double Vsp = (phase == "V") ? 1.0 : 0.0;
            const auto xsp = in.z;
            const auto ysp = in.z;
            const double Hsp = (Vsp == 1.0) ? Hv_lim : Hl_lim;

            r.dH = Hsp - in.Htarget;
            r.V = Vsp; r.x = xsp; r.y = ysp;
            r.singlePhase = true;
            r.phase = (Vsp == 1.0) ? "V" : "L";

            // React parity: log RR_SIGN (diagnostic) even when short-circuiting
            if (in.log) {
               // When EOSK reports single-phase (and we shortcut), we never
               // computed a separate "Kuse" vector — RR wasn't invoked. Emit
               // one RR_SIGN line tagged "Kraw" so the diagnostic stream still
               // captures whether the K-field implies a 2-phase root, but do
               // NOT emit a "Kuse" line: it would just duplicate Kraw and
               // pollute the run log with redundant entries.
               const auto [kmin_ss, kmax_ss] = minmaxFinite(ek.K);
               logRRSignTest(in, T, "Kraw", ek.K, kmin_ss, kmax_ss, /*eosSaysSinglePhase=*/true);
            }

            // React parity: even in single-phase shortcut, emit PH_RESID_SUM
            if (in.log && shouldLogPHResid(in.trayIndex, r.dH)) {
               const auto [Kmin, Kmax] = minmaxFinite(ek.K);
               std::ostringstream os;
               os.setf(std::ios::fixed); os << std::setprecision(6);
               os << "[PH_RESID_SUM] tray=" << (in.trayIndex + 1)
                  << " T=" << T
                  << " V=" << r.V
                  << " Hl=" << Hl_lim
                  << " Hv=" << Hv_lim
                  << " H=" << Hsp
                  << " Htarget=" << in.Htarget
                  << " dH=" << r.dH
                  << " Kmin=" << Kmin
                  << " Kmax=" << Kmax;
               in.log(os.str());
            }
            return r;
         }

         // Otherwise: do NOT short-circuit. Fall through to RR using K-values.
         if (in.log)
            log("[PH] eos singlePhase but Htarget inside [Hl,Hv] -> forcing RR");
         // else fall back to Wilson K to attempt two-phase RR
         K = wilsonKValues(T, in.P, comps);
         for (double& kv : K)
            kv = clamp(kv, 1e-8, 1e8);
      }
      else {
         K = ek.K;
      }

      std::vector<double> Kuse = K;
      bool forced2ph = false;

      // React parity:
      // - Only force "two-phase K" up-front when EOS indicates single-phase (and the caller requests it).
      // - If RR cannot establish a split (non-finite V or empty x/y), then as a last resort force two-phase K and retry.
      if (in.forceTwoPhase && eosSaysSinglePhase) {
         Kuse = forceTwoPhaseK(in.z, K); // use RAW K as the base, like React
         forced2ph = true;
      }

      // Try RR with current Kuse
      RRAndComp rr{};
      if (eosSaysSinglePhase && !in.disableSinglePhaseShortCircuit) {
         // React parity: if EOS indicates (or effectively implies) single-phase at this T,
         // skip RR entirely and treat as all-vapor (or all-liquid if EOS says "L").
         rr.V = (!ek.phase.empty() && ek.phase == "L") ? 0.0 : 1.0;
         rr.x = in.z;
         rr.y = in.z;
      }
      else {
         rr = rrAndCompositions(in.z, Kuse, in.trayIndex, T, in.P, in.log, "PH_EVAL");

         // Last-resort: if RR failed, force two-phase K from *raw K* and retry
         if (!isFinite(rr.V) || rr.x.empty() || rr.y.empty()) {
            Kuse = forceTwoPhaseK(in.z, K); // base on raw K, not already-forced
            rr = rrAndCompositions(in.z, Kuse, in.trayIndex, T, in.P, in.log, "PH_EVAL_FORCED2PH");
         }
      }

      // Log sign tests for BOTH sets
      // Compute K min/max for diagnostics (skip non-finite values)
      auto computeKMinMax = [](const std::vector<double>& Kv) {
         double kmin = std::numeric_limits<double>::infinity();
         double kmax = 0.0;
         for (double kv : Kv) {
            if (!std::isfinite(kv))
               continue;
            kmin = std::min(kmin, kv);
            kmax = std::max(kmax, kv);
         }
         if (!std::isfinite(kmin))
         {
            kmin = std::numeric_limits<double>::quiet_NaN(); kmax = std::numeric_limits<double>::quiet_NaN();
         }
         return std::pair<double, double>{kmin, kmax};
         };
      const auto [kmin_raw, kmax_raw] = computeKMinMax(K);
      const auto [kmin_use, kmax_use] = computeKMinMax(Kuse);
      logRRSignTest(in, T, "Kraw", K, kmin_raw, kmax_raw, eosSaysSinglePhase);

      // Emit the Kuse RR_SIGN line only when it actually differs from Kraw.
      // Kuse is a pointwise-modified copy of K (via forceTwoPhaseK) — but it
      // only gets modified when forceTwoPhase fires or RR fails. In the
      // common case Kuse == K pointwise, which means logging both produces
      // byte-identical output lines (apart from the tag) and just pollutes
      // the run log. We compare exactly (not with tolerance) because
      // forceTwoPhaseK either runs and produces different values, or
      // doesn't run and leaves K untouched — there's no near-miss case.
      bool kuseDiffersFromRaw = (Kuse.size() != K.size());
      if (!kuseDiffersFromRaw) {
         for (std::size_t i = 0; i < K.size(); ++i) {
            if (Kuse[i] != K[i]) { kuseDiffersFromRaw = true; break; }
         }
      }
      if (kuseDiffersFromRaw) {
         logRRSignTest(in, T, "Kuse", Kuse, kmin_use, kmax_use, eosSaysSinglePhase);
      }

      const std::string ksrc = eosSaysSinglePhase ? "Wilson" : "EOSK";

      if (in.log && shouldLogPHKsrc(in.trayIndex, eosSaysSinglePhase, T, kmin_use, kmax_use)) {
         std::ostringstream oss;
         oss << "[PH_KSRC] tray=" << (in.trayIndex + 1)
            << " T=" << T
            << " eosSinglePhase=" << (eosSaysSinglePhase ? "1" : "0")
            << " Ksrc=" << ksrc
            << " forced2ph=" << (forced2ph ? 1 : 0)
            << " Kmin_raw=" << kmin_raw
            << " Kmax_raw=" << kmax_raw
            << " Kmin_use=" << kmin_use
            << " Kmax_use=" << kmax_use;
         in.log(oss.str());
      }
      // last-resort fallback if numeric trouble
      if (!isFinite(rr.V) || rr.x.empty() || rr.y.empty()) {
         Kuse = forceTwoPhaseK(in.z, K);
         rr = rrAndCompositions(in.z, Kuse, in.trayIndex, T, in.P, in.log, "PH_EVAL");
      }

      // ---- throttled K_DEBUG when Kraw is all at floor ----
      auto [kminRaw, kmaxRaw] = minmaxFinite(K);
      auto [kminUse, kmaxUse] = minmaxFinite(Kuse);

      const bool rawAllFloor =
         isFinite(kminRaw) && isFinite(kmaxRaw) &&
         kminRaw <= 1.000001e-6 && kmaxRaw <= 1.000001e-6;

      int& dc = g_kdbgCountByTray[in.trayIndex];

      // Print only 10 lines per tray, only when raw K is stuck at floor
      if (rawAllFloor && dc < 10) {
         dc++;
         logKDebugIfWanted(in, T, "resid", K, Kuse, rr);
      }

      // Ensure K-range corresponds to the *actual* K-set used for RR at this T.
      // (rrAndCompositions already computes Kmin/Kmax from its input K; keep it authoritative.)
      // But if RR returned without finite K-range, compute defensively here.
      if (!isFinite(rr.Kmin) || !isFinite(rr.Kmax)) {
         double Kmin = std::numeric_limits<double>::infinity();
         double Kmax = -std::numeric_limits<double>::infinity();
         for (double kv : Kuse)
            if (isFinite(kv))
            {
               Kmin = std::min(Kmin, kv); Kmax = std::max(Kmax, kv);
            }
         rr.Kmin = std::isfinite(Kmin) ? Kmin : std::numeric_limits<double>::quiet_NaN();
         rr.Kmax = (std::isfinite(Kmax) && Kmax > 0.0) ? Kmax : std::numeric_limits<double>::quiet_NaN();
      }

      // two-phase recovery only when EOS flagged singlePhase (and requested)
      if (rr.singlePhase) {
         if (in.disableSinglePhaseShortCircuit && !in.forceTwoPhase && eosSaysSinglePhase) {
            const auto Kforced = forceTwoPhaseK(in.z, Kuse);
            auto rr2 = rrAndCompositions(in.z, Kforced, in.trayIndex, T, in.P, in.log, "PH_RECOVER");
            if (!rr2.singlePhase && isFinite(rr2.V) && rr2.V > 0.0 && rr2.V < 1.0) {
               rr = std::move(rr2);
               Kuse = Kforced;
            }
         }

         if (rr.singlePhase) {
            const std::string phase = !rr.phase.empty() ? rr.phase : ((rr.V == 1.0) ? "V" : "L");
            const double Vsp = (phase == "V") ? 1.0 : 0.0;
            const auto& xsp = rr.x.empty() ? in.z : rr.x;
            const auto& ysp = rr.y.empty() ? in.z : rr.y;
            const double Hv_sp = hVap(ysp, T, in.trayIndex, comps, in.P);
            const double Hl_sp = hLiq(xsp, T, in.trayIndex, comps, in.P);
            const double Hsp = (Vsp == 1.0) ? Hv_sp : Hl_sp;
            rr.dH = Hsp - in.Htarget;
            rr.singlePhase = true;
            rr.phase = phase;

            // React parity: emit PH_RESID_SUM even when RR collapses to single-phase
            if (in.log && shouldLogPHResid(in.trayIndex, rr.dH)) {
               std::ostringstream os;
               os.setf(std::ios::fixed); os << std::setprecision(6);
               os << "[PH_RESID_SUM] tray=" << (in.trayIndex + 1)
                  << " T=" << T
                  << " V=" << rr.V
                  << " Hl=" << Hl_sp
                  << " Hv=" << Hv_sp
                  << " H=" << Hsp
                  << " Htarget=" << in.Htarget
                  << " dH=" << rr.dH
                  << " Kmin=" << rr.Kmin
                  << " Kmax=" << rr.Kmax;
               in.log(os.str());
            }

            return rr;
         }
      }

      const double Hv = hVap(rr.y, T, in.trayIndex, comps, in.P);
      const double Hl = hLiq(rr.x, T, in.trayIndex, comps, in.P);
      const double H = rr.V * Hv + (1.0 - rr.V) * Hl;
      rr.dH = H - in.Htarget;

      if (in.log && shouldLogPHResid(in.trayIndex, rr.dH)) {
         std::ostringstream os;
         os.setf(std::ios::fixed); os << std::setprecision(6);
         os << "[PH_RESID_SUM] tray=" << (in.trayIndex + 1)
            << " T=" << T
            << " V=" << rr.V
            << " Hl=" << Hl
            << " Hv=" << Hv
            << " H=" << H
            << " Htarget=" << in.Htarget
            << " dH=" << rr.dH
            << " Kmin=" << rr.Kmin
            << " Kmax=" << rr.Kmax;
         in.log(os.str());
      }

      return rr;
      };

   // Initial bracket
   double Tlo = clamp(T0 - 40.0, Tmin, Tmax);
   double Thi = clamp(T0 + 40.0, Tmin, Tmax);
   RRAndComp rlo = resid(Tlo);
   RRAndComp rhi = resid(Thi);

   if (in.log) {
      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(1);
      os << "[PH_BRACKET] tray=" << in.trayIndex + 1
         << " Tlo=" << Tlo << " Thi=" << Thi
         << " dHlo=" << std::scientific << std::setprecision(2) << rlo.dH
         << " dHhi=" << std::scientific << std::setprecision(2) << rhi.dH
         << " signs=[" << (rlo.dH > 0 ? 1 : (rlo.dH < 0 ? -1 : 0)) << "," << (rhi.dH > 0 ? 1 : (rhi.dH < 0 ? -1 : 0)) << "]";
      log(os.str());
   }

   int expand = 0;
   while (rlo.dH * rhi.dH > 0.0 && expand < 10) {
      const double span = (Thi - Tlo != 0.0) ? (Thi - Tlo) : 10.0;
      Tlo = clamp(Tlo - 0.5 * span, Tmin, Tmax);
      Thi = clamp(Thi + 1.5 * span, Tmin, Tmax);
      rlo = resid(Tlo);
      rhi = resid(Thi);
      expand++;

      if (in.log) {
         std::ostringstream os;
         os.setf(std::ios::fixed); os.precision(1);
         os << "[PH_BRACKET] tray=" << in.trayIndex + 1
            << " Tlo=" << Tlo << " Thi=" << Thi
            << " dHlo=" << std::scientific << std::setprecision(2) << rlo.dH
            << " dHhi=" << std::scientific << std::setprecision(2) << rhi.dH
            << " signs=[" << (rlo.dH > 0 ? 1 : (rlo.dH < 0 ? -1 : 0)) << "," << (rhi.dH > 0 ? 1 : (rhi.dH < 0 ? -1 : 0)) << "]";
         log(os.str());
      }
   }

   if (rlo.dH * rhi.dH > 0.0) {
      const double T1 = clamp(T0 + 5.0, Tmin, Tmax);
      RRAndComp r0 = resid(T0);
      RRAndComp r1 = resid(T1);
      double dHdT = (r1.dH - r0.dH) / (T1 - T0);
      if (dHdT == 0.0) dHdT = 1e-6;
      const double Tn = clamp(T0 - r0.dH / dHdT, Tmin, Tmax);
      RRAndComp rn = resid(Tn);

      // penalty scoring (ported)
      struct Cand
      {
         double T; RRAndComp r; double score;
      };
      std::vector<Cand> cands;
      cands.push_back({ T0, r0, std::fabs(r0.dH) * 1.0 });
      cands.push_back({ T1, r1, std::fabs(r1.dH) * 0.5 });
      cands.push_back({ Tn, rn, std::fabs(rn.dH) * 0.5 });
      std::sort(cands.begin(), cands.end(), [](const Cand& a, const Cand& b) { return a.score < b.score; });
      const auto best = cands.front();

      if (in.log) {
         std::ostringstream os;
         os.setf(std::ios::fixed); os.precision(2);
         os << "[PH_OUT] tray=" << in.trayIndex + 1
            << " T=" << best.T
            << " V=" << std::fixed << std::setprecision(3) << best.r.V
            << " (no-bracket)";
         log(os.str());
      }

      ret.T = best.T;
      ret.V = best.r.V;
      ret.x = best.r.x;
      ret.y = best.r.y;
      ret.status = "no-bracket-soft";
      ret.dH = best.r.dH;
      ret.Hcalc = isFinite(in.Htarget) ? (in.Htarget + best.r.dH) : std::numeric_limits<double>::quiet_NaN();
      ret.Htarget = in.Htarget;
      {
         const double Sv = sVap(ret.y.empty() ? in.z : ret.y, ret.T, in.trayIndex, comps, in.P);
         const double Sl = sLiq(ret.x.empty() ? in.z : ret.x, ret.T, in.trayIndex, comps, in.P);
         ret.Scalc = ret.V * Sv + (1.0 - ret.V) * Sl;
      }
      ret.singlePhase = best.r.singlePhase;
      ret.phase = best.r.phase;
      return ret;
   }

   // Bisection solve
   double Tmid = T0;
   RRAndComp rmid = rlo;
   for (int it = 0; it < 50; ++it) {
      Tmid = 0.5 * (Tlo + Thi);
      rmid = resid(Tmid);

      if (std::fabs(rmid.dH) < 1e-6 && (rmid.V < 1e-4 || rmid.V > 1.0 - 1e-4)) {
         const double Ttry = clamp(Tmid + 2.0, Tmin, Tmax);
         if (Ttry != Tmid) {
            Tmid = Ttry;
            rmid = resid(Tmid);
         }
      }

      if (std::fabs(rmid.dH) < 1e-6 || std::fabs(Thi - Tlo) < 1e-6) {
         break;
      }

      if (rlo.dH * rmid.dH <= 0.0) {
         Thi = Tmid;
         rhi = rmid;
      }
      else {
         Tlo = Tmid;
         rlo = rmid;
      }
   }

   // ---- Cross-eval sanity check (tray 2 only) ----
   if (in.log && in.trayIndex == 1) { // trayIndex is 0-based; tray=2 => 1
      auto crossEval = [&](double Ttest, const char* tag) {
         RRAndComp r = resid(Ttest);

         // Compute enthalpies from the returned phase compositions
         const double Hv = hVap(r.y, Ttest, in.trayIndex, comps, in.P);
         const double Hl = hLiq(r.x, Ttest, in.trayIndex, comps, in.P);
         const double H = r.V * Hv + (1.0 - r.V) * Hl;
         const double dH = H - in.Htarget;

         std::ostringstream os;
         os.setf(std::ios::fixed);
         os << std::setprecision(6);

         os << "[PH_XEVAL] tray=" << (in.trayIndex + 1)
            << " tag=" << tag
            << " T=" << Ttest
            << " V=" << r.V
            << " Hl=" << Hl
            << " Hv=" << Hv
            << " H=" << H
            << " Htarget=" << in.Htarget
            << " dH=" << dH
            << " Kmin=" << r.Kmin
            << " Kmax=" << r.Kmax;

         log(os.str());
         };

      crossEval(440.354901, "ReactT");
      crossEval(468.837111, "CppT");
   }

   if (in.log) {
      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(2);
      os << "[PH_OUT] tray=" << in.trayIndex + 1
         << " T=" << Tmid
         << " V=" << std::fixed << std::setprecision(3) << rmid.V;
      if (rmid.singlePhase)
         os << " (singlePhase:" << (!rmid.phase.empty() ? rmid.phase : (rmid.V == 1.0 ? "V" : "L")) << ")";
      log(os.str());
   }

   ret.T = Tmid;
   ret.V = rmid.V;
   ret.x = rmid.x;
   ret.y = rmid.y;
   ret.Kmin = rmid.Kmin;
   ret.Kmax = rmid.Kmax;
   ret.status = "ok";
   ret.dH = rmid.dH;
   ret.Hcalc = isFinite(in.Htarget) ? (in.Htarget + rmid.dH) : std::numeric_limits<double>::quiet_NaN();
   ret.Htarget = in.Htarget;
   {
      const double Sv = sVap(ret.y.empty() ? in.z : ret.y, ret.T, in.trayIndex, comps, in.P);
      const double Sl = sLiq(ret.x.empty() ? in.z : ret.x, ret.T, in.trayIndex, comps, in.P);
      ret.Scalc = ret.V * Sv + (1.0 - ret.V) * Sl;
   }
   ret.singlePhase = rmid.singlePhase;
   ret.phase = rmid.phase;
   return ret;
}

// ---------------- Saturated helper (ported) ----------------

static double solveBubblePointT(const FlashPHSatInput& in) {
   if (!in.components) {
      throw std::invalid_argument("solveBubblePointT: components is null");
   }
   const auto& comps = *in.components;
   auto S = [&](double T)->double {
      auto r = eosK(in.P, T, in.z, comps, in.trayIndex, 32, {}, nullptr, /*log=*/false,
         std::numeric_limits<double>::quiet_NaN(), "manual", in.eos, in.log);
      double s = 0.0;
      for (size_t i = 0; i < in.z.size() && i < r.K.size(); ++i) s += in.z[i] * r.K[i];
      return s;
      };

   double Tlo = clamp(isFinite(in.Tseed) ? in.Tseed : 0.5 * (in.Tmin + in.Tmax), in.Tmin, in.Tmax);
   double Thi = Tlo;
   double flo = S(Tlo) - 1.0;
   double fhi = flo;

   for (int k = 0; k < 30 && std::signbit(flo) == std::signbit(fhi); ++k) {
      const double span = std::max(5.0, 0.15 * (k + 1) * (in.Tmax - in.Tmin) / 30.0);
      Tlo = clamp(Tlo - span, in.Tmin, in.Tmax);
      Thi = clamp(Thi + span, in.Tmin, in.Tmax);
      flo = S(Tlo) - 1.0;
      fhi = S(Thi) - 1.0;
      if (Tlo == in.Tmin && Thi == in.Tmax)
         break;
   }

   if (std::signbit(flo) == std::signbit(fhi)) {
      double bestT = clamp(isFinite(in.Tseed) ? in.Tseed : 0.5 * (in.Tmin + in.Tmax), in.Tmin, in.Tmax);
      double bestAbs = std::numeric_limits<double>::infinity();
      const int n = 40;
      for (int j = 0; j <= n; ++j) {
         const double T = in.Tmin + (double(j) / n) * (in.Tmax - in.Tmin);
         const double f = S(T) - 1.0;
         const double a = std::fabs(f);
         if (a < bestAbs)
         {
            bestAbs = a; bestT = T;
         }
      }
      return bestT;
   }

   double a = Tlo, b = Thi, fa = flo, fb = fhi;

   for (int it = 0; it < in.maxIter; ++it) {
      const double m = 0.5 * (a + b);
      const double fm = S(m) - 1.0;

      if (std::fabs(fm) < 1e-6 || std::fabs(b - a) < 1e-4)
         return m;

      if (std::signbit(fm) == std::signbit(fa))
      {
         a = m;
         fa = fm;
      }
      else
      {
         b = m;
         fb = fm;
      }
   }
   return 0.5 * (a + b);
}

static double solveDewPointT(const FlashPHSatInput& in, double Tseed) {
   if (!in.components) {
      throw std::invalid_argument("solveDewPointT: components is null");
   }
   const auto& comps = *in.components;
   auto D = [&](double T)->double {
      auto r = eosK(in.P, T, in.z, comps, in.trayIndex, 32, {}, nullptr, /*log=*/false,
         std::numeric_limits<double>::quiet_NaN(), "manual", in.eos, in.log);
      double s = 0.0;
      for (size_t i = 0; i < in.z.size() && i < r.K.size(); ++i)
         s += in.z[i] / std::max(1e-30, r.K[i]);
      return s;
      };

   double Tlo = clamp(isFinite(Tseed) ? Tseed : 0.5 * (in.Tmin + in.Tmax), in.Tmin, in.Tmax);
   double Thi = Tlo;
   double flo = D(Tlo) - 1.0;
   double fhi = flo;

   for (int k = 0; k < 30 && std::signbit(flo) == std::signbit(fhi); ++k) {
      const double span = std::max(5.0, 0.15 * (k + 1) * (in.Tmax - in.Tmin) / 30.0);
      Tlo = clamp(Tlo - span, in.Tmin, in.Tmax);
      Thi = clamp(Thi + span, in.Tmin, in.Tmax);
      flo = D(Tlo) - 1.0;
      fhi = D(Thi) - 1.0;
      if (Tlo == in.Tmin && Thi == in.Tmax)
         break;
   }

   if (std::signbit(flo) == std::signbit(fhi)) {
      double bestT = clamp(isFinite(Tseed) ? Tseed : 0.5 * (in.Tmin + in.Tmax), in.Tmin, in.Tmax);
      double bestAbs = std::numeric_limits<double>::infinity();
      const int n = 40;
      for (int j = 0; j <= n; ++j) {
         const double T = in.Tmin + (double(j) / n) * (in.Tmax - in.Tmin);
         const double f = D(T) - 1.0;
         const double a = std::fabs(f);
         if (a < bestAbs)
         {
            bestAbs = a; bestT = T;
         }
      }
      return bestT;
   }

   double a = Tlo, b = Thi, fa = flo, fb = fhi;
   for (int it = 0; it < in.maxIter; ++it) {
      const double m = 0.5 * (a + b);
      const double fm = D(m) - 1.0;
      if (std::fabs(fm) < 1e-6 || std::fabs(b - a) < 1e-4)
         return m;
      if (std::signbit(fm) == std::signbit(fa))
      {
         a = m;
         fa = fm;
      }
      else
      {
         b = m;
         fb = fm;
      }
   }
   return 0.5 * (a + b);
}

FlashPHSatResult flashPH_saturated(const FlashPHSatInput& in) {
   FlashPHSatResult out;

   const auto& comps = *in.components;
   const double Tbub = solveBubblePointT(in);
   const double Tdew = solveDewPointT(in, Tbub);

   const double Hbub = hLiq(in.z, Tbub, in.trayIndex, comps, in.P);
   const double Hdew = hVap(in.z, Tdew, in.trayIndex, comps, in.P);

   out.Tbub = Tbub; out.Tdew = Tdew; out.Hbub = Hbub; out.Hdew = Hdew;

   if (!isFinite(in.Htarget)) {
      out.T = Tbub; out.V = 0.0; out.x = in.z; out.y = in.z;
      out.singlePhase = "L";
      out.reason = "bad-target";
      return out;
   }

   if (in.Htarget <= Hbub) {
      auto r = eosK(in.P, Tbub, in.z, comps, in.trayIndex, 32, {}, nullptr, /*log=*/false,
         std::numeric_limits<double>::quiet_NaN(), "manual", in.eos, in.log);
      auto y = normalize([&] {
         std::vector<double> tmp(in.z.size(), 0.0);
         for (size_t i = 0; i < tmp.size() && i < r.K.size(); ++i)
            tmp[i] = in.z[i] * r.K[i];
         return tmp;
         }());
      out.T = Tbub; out.V = 0.0; out.x = in.z; out.y = y;
      out.singlePhase = "L";
      out.reason = "sat-clamp-L";
      return out;
   }

   if (in.Htarget >= Hdew) {
      auto r = eosK(in.P, Tdew, in.z, comps, in.trayIndex, 32, {}, nullptr, /*log=*/false,
         std::numeric_limits<double>::quiet_NaN(), "manual", in.eos, in.log);
      auto x = normalize([&] {
         std::vector<double> tmp(in.z.size(), 0.0);
         for (size_t i = 0; i < tmp.size() && i < r.K.size(); ++i)
            tmp[i] = in.z[i] / std::max(1e-30, r.K[i]);
         return tmp;
         }());
      out.T = Tdew; out.V = 1.0; out.x = x; out.y = in.z;
      out.singlePhase = "V";
      out.reason = "sat-clamp-V";
      return out;
   }

   auto Hresid = [&](double T)->RRAndComp {
      auto r = eosK(in.P, T, in.z, comps, in.trayIndex, 32, {}, nullptr, /*log=*/false,
         std::numeric_limits<double>::quiet_NaN(), "manual", in.eos, in.log);
      std::vector<double> K = r.K;
      if (r.singlePhase) {
         K = forceTwoPhaseK(in.z, K);
      }
      RRAndComp rr = rrAndCompositions(in.z, K, in.trayIndex, T, in.P, in.log, "EQTP");
      const double H = rr.V * hVap(rr.y, T, in.trayIndex, comps, in.P) + (1.0 - rr.V) * hLiq(rr.x, T, in.trayIndex, comps, in.P);
      rr.dH = H - in.Htarget;
      return rr;
      };

   double a = Tbub, b = Tdew;
   RRAndComp ra = Hresid(a);
   RRAndComp rb = Hresid(b);

   if (!isFinite(ra.dH) || !isFinite(rb.dH) || (std::signbit(ra.dH) == std::signbit(rb.dH))) {
      const double m = 0.5 * (a + b);
      RRAndComp rm = Hresid(m);
      out.T = m;
      out.V = rm.V;
      out.x = rm.x;
      out.y = rm.y;
      out.singlePhase.clear();
      out.reason = "sat-fallback";
      return out;
   }

   for (int it = 0; it < in.maxIter; ++it) {
      const double m = 0.5 * (a + b);
      RRAndComp rm = Hresid(m);
      if (std::fabs(rm.dH) < 1e-6 || std::fabs(b - a) < 1e-4) {
         out.T = m;
         out.V = rm.V;
         out.x = rm.x;
         out.y = rm.y;
         out.singlePhase.clear();
         out.reason = rm.rrReason.empty() ? "ok" : rm.rrReason;
         return out;
      }
      if (std::signbit(rm.dH) == std::signbit(ra.dH))
      {
         a = m;
         ra = rm;
      }
      else
      {
         b = m;
         rb = rm;
      }
   }

   const double m = 0.5 * (a + b);
   RRAndComp rm = Hresid(m);
   out.T = m; out.V = rm.V; out.x = rm.x; out.y = rm.y;
   out.singlePhase.clear();
   out.reason = "sat-maxiter";
   return out;
}

FlashPTResult flashPT(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>* components,
   int trayIndex,
   int trays,
   const std::string& crudeHint,
   const std::vector<std::vector<double>>* kij,
   double murphreeEtaV,
   const std::string& eosMode,
   const std::string& eosManual,
   const std::function<void(const std::string&)>& log
)
{
   FlashPTResult out;

   const std::string eos = eosManual.empty() ? "PRSV" : eosManual;

   // Call eosK with the SAME signature/order used by flashPH::resid() above in this file
   auto ek = eosK(
      P, T, z, *components,
      trayIndex, trays, crudeHint,
      kij,
      /*logEnabled=*/(bool)log,
      murphreeEtaV,
      eosMode,
      eos,
      log
   );

   validateSinglePhase(ek, log, trayIndex, "EQTP");

   // Choose K set (respect ek.singlePhase if EOS says so, otherwise use ek.K)
   std::vector<double> Kuse = ek.K;

   // Reuse your existing helper that:
   // - calls RR using the correct signature
   // - normalizes x/y
   // - sets singlePhase + phase based on endpoints
   RRAndComp rr = rrAndCompositions(z, Kuse, trayIndex, T, P, log, "EQTP");

   out.V = rr.V;
   out.x = rr.x;
   out.y = rr.y;
   out.K = std::move(Kuse);
   out.singlePhase = rr.singlePhase;
   out.phase = rr.phase;

   const double Hv = hVap(out.y, T, trayIndex, *components, P);
   const double Hl = hLiq(out.x, T, trayIndex, *components, P);
   out.H = out.V * Hv + (1.0 - out.V) * Hl;
   const double Sv = sVap(out.y.empty() ? z : out.y, T, trayIndex, *components, P);
   const double Sl = sLiq(out.x.empty() ? z : out.x, T, trayIndex, *components, P);
   out.S = out.V * Sv + (1.0 - out.V) * Sl;

   return out;
}

FlashPSResult flashPS(const FlashPSInput& in) {
   FlashPSResult ret;
   ret.Starget = in.Starget;
   if (!in.components) {
      ret.status = "no-components";
      return ret;
   }
   const auto& comps = *in.components;

   // Resolve EOS: prefer thermoConfig.thermoMethodId, fall back to eosManual, then PRSV.
   const std::string resolvedEos = !in.thermoConfig.thermoMethodId.empty()
      ? in.thermoConfig.thermoMethodId
      : (in.eosManual.empty() ? "PRSV" : in.eosManual);

   auto solveAtT = [&](double T) {
      return flashPT(in.P, T, in.z, &comps, in.trayIndex, in.trays, in.crudeName, in.kij, in.murphreeEtaV, in.eosMode, resolvedEos, in.log);
      };
   auto sResid = [&](double T) -> double {
      const auto pt = solveAtT(T);
      if (!std::isfinite(pt.S)) return std::numeric_limits<double>::quiet_NaN();
      return pt.S - in.Starget;
      };
   double lo = 200.0, hi = 1200.0;
   double fLo = sResid(lo), fHi = sResid(hi);
   bool bracketed = std::isfinite(fLo) && std::isfinite(fHi) && fLo * fHi <= 0.0;
   if (!bracketed) {
      double prevT = lo, prevF = fLo;
      for (double T = lo + 25.0; T <= hi; T += 25.0) {
         double f = sResid(T);
         if (std::isfinite(prevF) && std::isfinite(f) && prevF * f <= 0.0) {
            lo = prevT; hi = T; fLo = prevF; fHi = f; bracketed = true; break;
         }
         prevT = T; prevF = f;
      }
   }
   double Tsol = std::numeric_limits<double>::quiet_NaN();
   if (bracketed) {
      for (int i = 0; i < 80; ++i) {
         double mid = 0.5 * (lo + hi);
         double fMid = sResid(mid);
         if (!std::isfinite(fMid)) break;
         Tsol = mid;
         if (std::fabs(fMid) < 1e-6 || (hi - lo) < 1e-6) break;
         if (fLo * fMid <= 0.0) { hi = mid; fHi = fMid; }
         else { lo = mid; fLo = fMid; }
      }
   }
   if (!std::isfinite(Tsol)) {
      Tsol = std::isfinite(in.Tseed) ? std::clamp(in.Tseed, 200.0, 1200.0) : 500.0;
      ret.status = "no-bracket";
   }
   else {
      ret.status = "ok";
   }
   const auto pt = solveAtT(Tsol);
   ret.T = Tsol;
   ret.V = pt.V;
   ret.x = pt.x;
   ret.y = pt.y;
   ret.Hcalc = pt.H;
   ret.Scalc = pt.S;
   ret.dS = std::isfinite(pt.S) ? (pt.S - in.Starget) : std::numeric_limits<double>::quiet_NaN();
   return ret;
}


FlashTSResult flashTS(const FlashTSInput& in) {
   FlashTSResult ret;
   ret.Starget = in.Starget;
   ret.T = in.T;
   if (!in.components) {
      ret.status = "no-components";
      return ret;
   }
   if (!std::isfinite(in.T) || in.T <= 1.0) {
      ret.status = "bad-temperature";
      return ret;
   }
   const auto& comps = *in.components;

   // Resolve EOS: prefer thermoConfig.thermoMethodId, fall back to eosManual, then PRSV.
   const std::string resolvedEos = !in.thermoConfig.thermoMethodId.empty()
      ? in.thermoConfig.thermoMethodId
      : (in.eosManual.empty() ? "PRSV" : in.eosManual);

   auto solveAtP = [&](double P) {
      return flashPT(P, in.T, in.z, &comps, in.trayIndex, in.trays, in.crudeName, in.kij, in.murphreeEtaV, in.eosMode, resolvedEos, in.log);
      };
   auto sResid = [&](double P) -> double {
      const auto pt = solveAtP(P);
      if (!std::isfinite(pt.S)) return std::numeric_limits<double>::quiet_NaN();
      return pt.S - in.Starget;
      };

   const double Pmin = 1.0e3;
   const double Pmax = 5.0e7;
   std::vector<double> grid;
   grid.reserve(17);
   for (int i = 0; i <= 16; ++i) {
      const double f = static_cast<double>(i) / 16.0;
      grid.push_back(std::exp(std::log(Pmin) + f * (std::log(Pmax) - std::log(Pmin))));
   }
   if (std::isfinite(in.Pseed) && in.Pseed >= Pmin && in.Pseed <= Pmax) {
      grid.push_back(in.Pseed);
      grid.push_back(std::clamp(in.Pseed * 0.5, Pmin, Pmax));
      grid.push_back(std::clamp(in.Pseed * 2.0, Pmin, Pmax));
   }
   std::sort(grid.begin(), grid.end());
   grid.erase(std::unique(grid.begin(), grid.end(), [](double a, double b) { return std::fabs(a - b) <= std::max(1.0, 1e-9 * std::max(std::fabs(a), std::fabs(b))); }), grid.end());

   double bestP = std::numeric_limits<double>::quiet_NaN();
   double bestAbs = std::numeric_limits<double>::infinity();
   double lo = std::numeric_limits<double>::quiet_NaN();
   double hi = std::numeric_limits<double>::quiet_NaN();
   double fLo = std::numeric_limits<double>::quiet_NaN();
   double fHi = std::numeric_limits<double>::quiet_NaN();

   double prevP = std::numeric_limits<double>::quiet_NaN();
   double prevF = std::numeric_limits<double>::quiet_NaN();
   bool bracketed = false;
   for (double P : grid) {
      const double f = sResid(P);
      if (!std::isfinite(f))
         continue;
      const double af = std::fabs(f);
      if (af < bestAbs) { bestAbs = af; bestP = P; }
      if (std::isfinite(prevF) && prevF * f <= 0.0) {
         lo = prevP; hi = P; fLo = prevF; fHi = f; bracketed = true; break;
      }
      prevP = P; prevF = f;
   }

   double Psol = std::numeric_limits<double>::quiet_NaN();
   if (bracketed) {
      double logLo = std::log(lo), logHi = std::log(hi);
      for (int i = 0; i < 80; ++i) {
         const double logMid = 0.5 * (logLo + logHi);
         const double mid = std::exp(logMid);
         const double fMid = sResid(mid);
         if (!std::isfinite(fMid)) break;
         Psol = mid;
         if (std::fabs(fMid) < 1e-6 || std::fabs(logHi - logLo) < 1e-8) break;
         if (fLo * fMid <= 0.0) { hi = mid; fHi = fMid; logHi = logMid; }
         else { lo = mid; fLo = fMid; logLo = logMid; }
      }
      ret.status = "ok";
   }

   if (!std::isfinite(Psol)) {
      Psol = std::isfinite(bestP) ? bestP : (std::isfinite(in.Pseed) ? std::clamp(in.Pseed, Pmin, Pmax) : 101325.0);
      ret.status = std::isfinite(bestP) ? "no-bracket" : "failed";
   }

   const auto pt = solveAtP(Psol);
   ret.P = Psol;
   ret.V = pt.V;
   ret.x = pt.x;
   ret.y = pt.y;
   ret.Hcalc = pt.H;
   ret.Scalc = pt.S;
   ret.dS = std::isfinite(pt.S) ? (pt.S - in.Starget) : std::numeric_limits<double>::quiet_NaN();
   return ret;
}

// ThermoConfig-aware overload of flashPT.
// Resolves the EOS string from thermoConfig.thermoMethodId and delegates to the
// primary flashPT signature. The column simulator continues to use the primary
// signature directly and is not affected by this addition.
FlashPTResult flashPT(
   double P,
   double T,
   const std::vector<double>& z,
   const thermo::ThermoConfig& thermoConfig,
   const std::vector<Component>* components,
   const std::vector<std::vector<double>>* kij,
   double murphreeEtaV,
   const std::function<void(const std::string&)>& log)
{
   const std::string eos = thermoConfig.thermoMethodId.empty()
      ? "PRSV" : thermoConfig.thermoMethodId;
   return flashPT(P, T, z, components, -1, 32, /*crudeHint=*/"", kij, murphreeEtaV,
      /*eosMode=*/"manual", eos, log);
}