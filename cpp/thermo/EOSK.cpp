// cpp/unitops/column/thermo/EOSK.cpp
#include "EOSK.hpp"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "../../thermo/eos/PR.hpp"
#include "eos/PRSV.hpp"

// ---- EOSK log coalescer -----------------------------------------------------
// Many EOSK call sites emit repeated identical log lines (especially [EOSK_SEED])
// during PH iterations. EOSK coalesces consecutive identical lines and emits a
// "(repeated N times)" summary only when the next *different* line arrives.
//
// Tray boundaries (trayStart/trayEnd) are logged outside EOSK (in AppState).
// Without an explicit flush at those boundaries, the summary line can be delayed
// and appear at the start of the *next* tray, which makes it look like the tray
// number in the first [EOSK_SEED] line of the new tray was "recycled".
//
// AppState can call flushEOSKCoalescer(logger) at tray boundaries to force any
// pending summary to print immediately and to reset state so the next tray starts
// cleanly.

namespace {
   struct EOSKCoalescerState {
      std::string last;
      int repeatCount = 0;
   };

   static thread_local EOSKCoalescerState g_eoskCoalescer;

   static inline void eoskEmitCoalesced(const std::function<void(const std::string&)>& logger,
      const std::string& s)
   {
      const bool critical =
         (s.rfind("[EOSK_WARN]", 0) == 0) ||
         (s.rfind("[FLASH_WARN]", 0) == 0);

      if (!critical && s == g_eoskCoalescer.last) {
         g_eoskCoalescer.repeatCount++;
         return;
      }

      if (!g_eoskCoalescer.last.empty() && g_eoskCoalescer.repeatCount > 0) {
         const std::string summary =
            g_eoskCoalescer.last + "   (repeated " + std::to_string(g_eoskCoalescer.repeatCount) + " times)";
         if (logger)
            logger(summary);
         g_eoskCoalescer.repeatCount = 0;
      }

      if (logger)
         logger(s);
      g_eoskCoalescer.last = s;
   }
} // namespace

void flushEOSKCoalescer(const std::function<void(const std::string&)>& logger)
{
   if (!g_eoskCoalescer.last.empty() && g_eoskCoalescer.repeatCount > 0) {
      const std::string summary =
         g_eoskCoalescer.last + "   (repeated " + std::to_string(g_eoskCoalescer.repeatCount) + " times)";
      if (logger)
         logger(summary);
   }
   g_eoskCoalescer.last.clear();
   g_eoskCoalescer.repeatCount = 0;
}
// Forward declaration (implemented in PRSV.cpp) to allow logging without changing headers.
PRSVResult solvePRSV_withLogger(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& logger,
   bool diag,
   int trayIndex
);

#include "../../thermo/eos/SRK.hpp"

static bool LOG_EOSK = false;

// De-duplicate consecutive identical lines per (tray,eos)
struct LogState { std::string sig; int count = 0; };
static std::map<std::string, LogState> g_logState;

// Per-tray warning throttle
static std::map<int, int> g_warnCounts;

// Per-tray eta-default throttle
static std::map<int, int> g_etaDefaultCounts;

// Per-tray eta-value throttle
static std::map<int, int> g_etaValueCounts;

static inline double clamp(double v, double lo, double hi) {
   return (v < lo) ? lo : ((v > hi) ? hi : v);
}

static inline bool finite(double x) { return std::isfinite(x); }

static inline double clampK(double kv) {
   if (!(finite(kv) && kv > 0.0)) kv = 1.0;
   return clamp(kv, 1e-6, 1e6);
}

static std::vector<double> wilsonKSeed(double T, double P, const std::vector<Component>& comps) {
   const double T_safe = std::max(1e-9, T);
   const double P_safe = std::max(1e-9, P);
   std::vector<double> K;
   K.reserve(comps.size());
   for (const auto& c : comps) {
      if (!(finite(c.Tc) && finite(c.Pc) && c.Tc > 0.0 && c.Pc > 0.0)) {
         K.push_back(1.0);
         continue;
      }
      const double omega = finite(c.omega) ? c.omega : 0.0;
      const double exponent = 5.37 * (1.0 + omega) * (1.0 - (c.Tc / T_safe));
      const double kv = (c.Pc / P_safe) * std::exp(exponent);
      K.push_back(clampK(kv));
   }
   return K;
}

static std::vector<double> wilsonKValues(double T, double P, const std::vector<Component>& comps) {
   const double T_safe = std::max(1e-6, T);
   const double P_safe = std::max(1e-6, P);

   std::vector<double> K;
   K.reserve(comps.size());

   for (const auto& c : comps) {
      const double Tc = c.Tc;
      const double Pc = c.Pc;
      const double omega = finite(c.omega) ? c.omega : 0.0;

      if (!finite(Tc) || !finite(Pc) || Tc <= 0.0 || Pc <= 0.0) {
         K.push_back(1.0);
         continue;
      }

      const double exponent = 5.37 * (1.0 + omega) * (1.0 - (Tc / T_safe));
      const double kv = (Pc / P_safe) * std::exp(exponent);
      K.push_back(clamp(kv, 1e-6, 1e6));
   }

   return K;
}

// ---------- EOS choice per tray ----------
std::string getEOSForTray(
   int trayIndex,
   int trays,
   const std::string& /*crudeName*/,
   const std::string& eosMode,
   const std::string& eosManual
) {
   if (eosMode == "manual" && !eosManual.empty())
      return eosManual;

   const double a = double(trayIndex) / std::max(1, trays - 1);
   if (a > 0.66)
      return "SRK";
   if (a > 0.33)
      return "PR";
   return "PRSV";
}

// ---------- Internal: call right solver and normalize outputs ----------
struct CommonEOSOut {
   bool singlePhase = false;
   double ZL = std::numeric_limits<double>::quiet_NaN();
   double ZV = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> phiL;
   std::vector<double> phiV;
   double hdepL = 0.0;
   double hdepV = 0.0;
   // keep b_mix if present (for warnings)
   double b_mix = std::numeric_limits<double>::quiet_NaN();
};

static CommonEOSOut solveByEOS(
   const std::string& eos,
   double P,
   double T,
   const std::vector<double>& x,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& logger,
   bool diag,
   int trayIndex) {
   CommonEOSOut out;

   if (eos == "PRSV") {
      auto r = solvePRSV_withLogger(P, T, x, comps, kij, logger, diag, trayIndex);
      out.singlePhase = r.singlePhase;
      out.ZL = r.ZL;
      out.ZV = r.ZV;
      out.phiL = r.phiL;
      out.phiV = r.phiV;
      out.hdepL = r.hdepL;
      out.hdepV = r.hdepV;
      out.b_mix = r.b_mix;
      return out;
   }
   if (eos == "SRK") {
      auto r = solveSRK(P, T, x, comps, kij);
      // SRK translator returns ZL/ZV + phi; treat as always two-root unless collapsed.
      out.singlePhase = false;
      out.ZL = r.ZL;
      out.ZV = r.ZV;
      out.phiL = r.phiL;
      out.phiV = r.phiV;
      return out;
   }
   // Default PR
   auto r = solvePR(P, T, x, comps, kij);
   out.singlePhase = r.singlePhase;
   out.ZL = r.ZL;
   out.ZV = r.ZV;
   out.phiL = r.phiL;
   out.phiV = r.phiV;
   out.hdepL = r.hdepL;
   out.hdepV = r.hdepV;
   out.b_mix = r.b_mix;
   return out;
}

// ---------- Public logging control ----------
void setEosKLogging(bool on) { LOG_EOSK = on; }

// ---------- Local Rachford–Rice (bisection) ----------
static double rrV(const std::vector<double>& z, const std::vector<double>& K) {
   auto f = [&](double V) {
      double s = 0.0;
      for (size_t i = 0; i < z.size(); i++) {
         const double Ki = K[i];
         const double denom = 1.0 + V * (Ki - 1.0);
         s += z[i] * (Ki - 1.0) / std::max(1e-16, denom);
      }
      return s;
      };

   const double f0 = f(0.0);
   const double f1 = f(1.0);

   if (f0 > 0.0 && f1 > 0.0) return 1.0;
   if (f0 < 0.0 && f1 < 0.0) return 0.0;

   double lo = 0.0, hi = 1.0;
   double flo = f0, fhi = f1;

   for (int it = 0; it < 60; it++) {
      const double mid = 0.5 * (lo + hi);
      const double fm = f(mid);
      if (std::abs(fm) < 1e-12) return mid;
      if (flo * fm <= 0.0) {
         hi = mid;
         fhi = fm;
      }
      else {
         lo = mid;
         flo = fm;
      }
   }
   return 0.5 * (lo + hi);
}

static void rrEndpoints(const std::vector<double>& z,
   const std::vector<double>& K,
   double& f0,
   double& f1)
{
   auto f = [&](double V) {
      double s = 0.0;
      for (size_t i = 0; i < z.size(); i++) {
         const double Ki = K[i];
         const double denom = 1.0 + V * (Ki - 1.0);
         s += z[i] * (Ki - 1.0) / std::max(1e-16, denom);
      }
      return s;
      };

   f0 = f(0.0);
   f1 = f(1.0);
}

static std::string rrSinglePhaseFromEndpoints(double f0, double f1)
{
   if (f0 > 0.0 && f1 > 0.0) return "V"; // vapor-only
   if (f0 < 0.0 && f1 < 0.0) return "L"; // liquid-only
   return ""; // indicates two-phase root exists
}

// ---------- eosK ----------
EosKResult eosK(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>& comps,
   int trayIndex,
   int trays,
   const std::string& crudeName,
   const std::vector<std::vector<double>>* kij,
   bool log,
   double murphreeEtaV,
   const std::string& eosMode,
   const std::string& eosManual,
   const std::function<void(const std::string&)>& logger
)
{
   auto emitLog = [&](const std::string& s)
      {
         if (!logger)
            return;

         // Use the file-scope coalescer so AppState can flush it at tray boundaries.
         eoskEmitCoalesced(logger, s);
      };

   // Log incoming eta once per tray (proves wiring/runtime value)
   {
      int& c = g_etaValueCounts[trayIndex];
      if (c < 1) {
         c++;
         emitLog("[EOSK_ETA_IN] tray=" + std::to_string(trayIndex + 1) +
            " murphreeEtaV=" + std::to_string(murphreeEtaV) +
            " finite=" + std::string(finite(murphreeEtaV) ? "1" : "0"));
      }
   }

   auto emitEOSKSummary = [&](const EosKResult& out)
      {
         if (!(log || LOG_EOSK))
            return;

         double kmin = std::numeric_limits<double>::infinity();
         double kmax = -std::numeric_limits<double>::infinity();
         for (double k : out.K)
            if (finite(k)) { kmin = std::min(kmin, k); kmax = std::max(kmax, k); }

         auto fmtFixed = [](double v, int prec) -> std::string {
            if (!std::isfinite(v)) return std::string("NaN");
            std::ostringstream ss;
            ss << std::fixed << std::setprecision(prec) << v;
            return ss.str();
            };
         auto fmtExp = [](double v, int prec) -> std::string {
            if (!std::isfinite(v)) return std::string("?");
            std::ostringstream ss;
            ss << std::scientific << std::setprecision(prec) << v;
            return ss.str();
            };

         std::string msg =
            "[EOSK] tray=" + std::to_string(trayIndex + 1) +
            " idx0=" + std::to_string(trayIndex) +
            " eos=" + out.eos +
            " ZL=" + fmtFixed(out.Z_liq, 4) +
            " ZV=" + fmtFixed(out.Z_vap, 4) +
            " Kmin=" + fmtExp(kmin, 2) +
            " Kmax=" + fmtExp(kmax, 2);

         if (out.singlePhase) {
            msg += " singlePhase=1 phase=" + out.phase + " reason=" + out.reason;
         }

         const std::string key = std::to_string(trayIndex) + "|" + out.eos;
         auto& st = g_logState[key];
         if (st.sig != msg) {
            st.sig = msg;
            st.count = 0;
            emitLog(msg);
         }
         else {
            st.count += 1;
            if (st.count % 20 == 0) {
               emitLog(msg + " (x" + std::to_string(st.count + 1) + ")");
            }
         }
      };

   EosKResult out;
   out.eos = getEOSForTray(trayIndex, trays, crudeName, eosMode, eosManual);

   const int n = (int)z.size();
   if (n <= 0)
      return out;

   // normalize composition defensively
   double zsum = 0.0;
   for (double v : z)
      zsum += (finite(v) ? v : 0.0);

   std::vector<double> zn(n, 1.0 / std::max(1, n));
   if (zsum > 0.0) {
      for (int i = 0; i < n; i++)
         zn[i] = (finite(z[i]) ? z[i] / zsum : 1.0 / n);
   }

   // Murphree efficiency is now applied post-flash in CounterCurrentColumnSimulator.
   // murphreeEtaV parameter is intentionally unused here.
   (void)murphreeEtaV;

   // initial K from same-composition φ ratio
   auto sol0 = solveByEOS(out.eos, P, T, zn, comps, kij, logger, log, trayIndex);
   const auto& phiL0 = sol0.phiL;
   const auto& phiV0 = sol0.phiV;

   std::vector<double> K(n, 1.0);
   auto badPhiSeed = [&](const std::vector<double>& a)->bool {
      if ((int)a.size() < n) return true;
      int bad = 0, zero = 0;
      for (int i = 0; i < n; i++) {
         if (!finite(a[i]) || a[i] <= 0.0)
            bad++;
         if (finite(a[i]) && a[i] == 0.0)
            zero++;
      }
      return (bad > 0) || (zero > n / 4);   // tune if needed
      };

   const bool seedPhiBad = badPhiSeed(phiL0) || badPhiSeed(phiV0);

   if (seedPhiBad) {
      // Wilson seed (robust) instead of phi ratio
      std::vector<double> Kw(n, 1.0);
      for (int i = 0; i < n; i++) {
         const auto& c = comps[i];
         if (finite(c.Tc) && finite(c.Pc) && c.Tc > 0 && c.Pc > 0) {
            const double omega = finite(c.omega) ? c.omega : 0.0;
            const double exponent = 5.37 * (1.0 + omega) * (1.0 - (c.Tc / std::max(1e-6, T)));
            Kw[i] = clampK((c.Pc / std::max(1e-6, P)) * std::exp(exponent));
         }
      }
      for (int i = 0; i < n; i++)
         K[i] = clampK(Kw[i]);

      emitLog("[EOSK_SEED] tray=" + std::to_string(trayIndex + 1) + " using Wilson seed (phi0 invalid)");
   }
   else {
      for (int i = 0; i < n; i++) {
         const double keq = clampK(phiL0[i] / std::max(1e-16, phiV0[i]));
         K[i] = clampK(keq);
      }
   }

   auto kminmax = [&]() {
      double mn = +1e300, mx = -1e300;
      for (double v : K)
         if (finite(v))
         {
            mn = std::min(mn, v); mx = std::max(mx, v);
         }
      return std::pair<double, double>(mn, mx);
      };
   auto [kmin0, kmax0] = kminmax();

   const bool allFloor0 =
      finite(kmin0) && finite(kmax0) &&
      kmin0 <= 1.000001e-6 && kmax0 <= 1.000001e-6;

   if (allFloor0) {
      if (logger) logger("[EOSK_SEED] tray=" + std::to_string(trayIndex + 1) + " eos=" + eosManual +
         " EOS seed hit K-floor for all comps (leaving as-is to match React)");
      // leave K as-is
   }

   static std::map<int, int> g_floorCounts;
   int& fc = g_floorCounts[trayIndex];

   if (allFloor0 && fc < 10) {
      fc++;

      auto fmt5 = [&](const std::vector<double>& v)->std::string {
         std::ostringstream os;
         os.setf(std::ios::fixed); os.precision(6);
         for (int i = 0; i < 5; i++) {
            if (i)
               os << ",";
            if (i < (int)v.size() && finite(v[i]))
               os << v[i];
            else os << "nan";
         }
         return os.str();
         };

      // compute first-5 ratios (raw, not clamped)
      std::vector<double> ratio5(5, std::numeric_limits<double>::quiet_NaN());
      for (int i = 0; i < 5 && i < n; i++) {
         const double den = std::max(1e-16, phiV0[i]);
         ratio5[i] = finite(phiL0[i]) && finite(den) ? (phiL0[i] / den) : std::numeric_limits<double>::quiet_NaN();
      }

      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(6);
      os << "[EOSK_KFLOOR] tray=" << trayIndex + 1 << " eos=" << out.eos
         << " T=" << T << " P=" << P
         << " sol0.singlePhase=" << (sol0.singlePhase ? 1 : 0)
         << " ZL0=" << sol0.ZL << " ZV0=" << sol0.ZV
         << " K0(min,max)=(" << kmin0 << "," << kmax0 << ")"
         << " phiL0_0-4=" << fmt5(phiL0)
         << " phiV0_0-4=" << fmt5(phiV0)
         << " ratio0_0-4=" << fmt5(ratio5);
      emitLog(os.str());
   }

   const int maxIter = 6;
   double ZL = sol0.ZL;
   double ZV = sol0.ZV;
   CommonEOSOut lastSolL, lastSolV;
   bool hasLast = false;

   for (int it = 0; it < maxIter; it++) {
      const double V = rrV(zn, K);

      // x,y from K and V
      std::vector<double> x(n), y(n);
      double xsum = 0.0;

      for (int i = 0; i < n; i++) {
         const double denom = 1.0 + V * (K[i] - 1.0);
         x[i] = zn[i] / std::max(1e-16, denom);
         xsum += x[i];
      }
      for (int i = 0; i < n; i++)
         x[i] /= std::max(1e-16, xsum);

      // Recompute y from normalized x to preserve K_i = y_i / x_i
      for (int i = 0; i < n; i++)
         y[i] = K[i] * x[i];

      // φ^L(x) and φ^V(y)
      auto solL = solveByEOS(out.eos, P, T, x, comps, kij, logger, log, trayIndex);
      auto solV = solveByEOS(out.eos, P, T, y, comps, kij, logger, log, trayIndex);
      lastSolL = solL;
      lastSolV = solV;
      hasLast = true;

      // single-phase or collapsed roots => stop and report single-phase
      auto pickZ = [&](const CommonEOSOut& s, bool wantV) {
         if (wantV && finite(s.ZV))
            return s.ZV;
         if (!wantV && finite(s.ZL))
            return s.ZL;
         return wantV ? ZV : ZL;
         };
      // RR endpoint check must be authoritative for phase existence.
      // If RR indicates a two-phase root exists, we must NOT collapse to single-phase,
      // even if an EOS solve reports "singlePhase" (matches JS master behavior).
      double rr_f0 = std::numeric_limits<double>::quiet_NaN();
      double rr_f1 = std::numeric_limits<double>::quiet_NaN();
      rrEndpoints(z, K, rr_f0, rr_f1);
      const std::string rrPhase = rrSinglePhaseFromEndpoints(rr_f0, rr_f1);
      const bool rrSaysSinglePhase = !rrPhase.empty();
      bool rrForcedTwoPhase = false;

      if (solL.singlePhase && solV.singlePhase && rrSaysSinglePhase) {
         // Only collapse to single-phase when BOTH EOS solves agree AND RR endpoints agree.
         const double Zs = pickZ(solL, /*wantV=*/(rrPhase == "V"));

         out.singlePhase = true;
         out.reason = "EOS_SINGLE_PHASE_BOTH";
         out.Z_liq = Zs;
         out.Z_vap = Zs;
         out.Z = Zs;

         // Keep K non-empty even in single-phase (PH may force two-phase RR).
         out.K = K;

         out.phase = rrPhase;
         out.reason = (rrPhase == "V") ? "SINGLEPHASE_V_RR" : "SINGLEPHASE_L_RR";

         emitEOSKSummary(out);
         return out;
      }
      else if (!rrSaysSinglePhase) {
         // RR indicates a two-phase root exists -> force two-phase handling.
         rrForcedTwoPhase = true;
         out.singlePhase = false;
         out.phase.clear();
         out.reason = "RR_TWOPHASE_FORCED";

         auto considerZ = [](double z, double& zmin, double& zmax) {
            if (std::isfinite(z) && z > 0.0) { zmin = std::min(zmin, z); zmax = std::max(zmax, z); }
            };

         double zmin = std::numeric_limits<double>::infinity();
         double zmax = -std::numeric_limits<double>::infinity();
         // Prefer sol0 if it provides distinct roots; otherwise use whatever distinct roots we can find.
         considerZ(sol0.ZL, zmin, zmax);
         considerZ(sol0.ZV, zmin, zmax);
         considerZ(solL.ZL, zmin, zmax);
         considerZ(solL.ZV, zmin, zmax);
         considerZ(solV.ZL, zmin, zmax);
         considerZ(solV.ZV, zmin, zmax);

         // If still degenerate, fall back to the best available (but do not mark single-phase).
         if (!(std::isfinite(zmin) && std::isfinite(zmax)) || zmax <= zmin * (1.0 + 1e-10)) {
            zmin = sol0.ZL;
            zmax = sol0.ZV;
         }

         ZL = zmin;
         ZV = zmax;
         out.Z_liq = ZL;
         out.Z_vap = ZV;
         out.Z = 0.5 * (ZL + ZV);
         out.K = K;
         // Continue on to normal return path (no early return).
      }

      const double relZL = std::abs((solL.ZV - solL.ZL)) / std::max(1e-12, std::abs(solL.ZV));
      const double relZV = std::abs((solV.ZV - solV.ZL)) / std::max(1e-12, std::abs(solV.ZV));

      if (relZL < 1e-8 || relZV < 1e-8) {
         // Roots are numerically collapsing. Only treat as single-phase if RR endpoints
         // also indicate single-phase. If RR indicates two-phase, DO NOT collapse.
         double rr_f0_c = std::numeric_limits<double>::quiet_NaN();
         double rr_f1_c = std::numeric_limits<double>::quiet_NaN();
         rrEndpoints(z, K, rr_f0_c, rr_f1_c);
         const std::string rrPhase_c = rrSinglePhaseFromEndpoints(rr_f0_c, rr_f1_c);

         if (!rrPhase_c.empty() && !rrForcedTwoPhase) {
            const double Zs = (rrPhase_c == "V") ? std::max(ZL, ZV) : std::min(ZL, ZV);
            out.singlePhase = true;
            out.reason = "EOS_COLLAPSED_ROOTS";
            out.Z_liq = Zs;
            out.Z_vap = Zs;
            out.Z = Zs;

            // Keep a non-empty K vector even in single-phase.
            out.K = K;

            out.phase = rrPhase_c;
            out.reason = (rrPhase_c == "V") ? "SINGLEPHASE_V_RR" : "SINGLEPHASE_L_RR";
            emitEOSKSummary(out);
            return out;
         }
         else {
            // RR indicates two-phase; keep distinct Z roots and continue.
            out.singlePhase = false;
            out.phase.clear();
            if (out.reason.empty()) out.reason = "RR_TWOPHASE_FORCED";
         }
      }

      if (!rrForcedTwoPhase) {
         ZL = solL.ZL;
         ZV = solV.ZV;
      }

      const auto& phiL = solL.phiL;
      const auto& phiV = solV.phiV;

      // update K
      // Match the React/JS master implementation (EOSK.js): linear relaxation
      // toward Kv = phiL/phiV with a constant damping factor.
      double maxRel = 0.0;
      const double damp = 0.5; // EOSK.js constant
      std::vector<double> Knew(n, 1.0);

      int clampLo = 0, clampHi = 0, phiBad = 0;
      double phiLmin = +std::numeric_limits<double>::infinity();
      double phiLmax = -std::numeric_limits<double>::infinity();
      double phiVmin = +std::numeric_limits<double>::infinity();
      double phiVmax = -std::numeric_limits<double>::infinity();

      // Debug: inspect phi ranges right before kvEq = phiL/phiV
      if (log && logger) {
         double pLmin = +std::numeric_limits<double>::infinity();
         double pLmax = -std::numeric_limits<double>::infinity();
         double pVmin = +std::numeric_limits<double>::infinity();
         double pVmax = -std::numeric_limits<double>::infinity();
         for (int j = 0; j < n; ++j) {
            const double pL = (j < (int)phiL.size()) ? phiL[j] : std::numeric_limits<double>::quiet_NaN();
            const double pV = (j < (int)phiV.size()) ? phiV[j] : std::numeric_limits<double>::quiet_NaN();
            if (std::isfinite(pL)) { pLmin = std::min(pLmin, pL); pLmax = std::max(pLmax, pL); }
            if (std::isfinite(pV)) { pVmin = std::min(pVmin, pV); pVmax = std::max(pVmax, pV); }
         }
         // Throttle EOSK_PHI spam: log first 2 per tray, then every 200th call per tray.
         static std::unordered_map<int, int> g_phiLogCountByTray;
         int& _phiC = g_phiLogCountByTray[trayIndex];
         const bool _doPhiLog = (_phiC < 2) || ((_phiC % 200) == 0);
         _phiC++;
         if (_doPhiLog) {
            std::ostringstream ossPhi;
            ossPhi.setf(std::ios::fixed);
            ossPhi << std::setprecision(6);
            ossPhi << "[EOSK_PHI] tray=" << (trayIndex + 1)
               << " T=" << T
               << " P=" << P
               << " phiL(min,max)=(" << (std::isfinite(pLmin) ? pLmin : 0.0) << "," << (std::isfinite(pLmax) ? pLmax : 0.0) << ")"
               << " phiV(min,max)=(" << (std::isfinite(pVmin) ? pVmin : 0.0) << "," << (std::isfinite(pVmax) ? pVmax : 0.0) << ")";
            // Print first 5 entries (or fewer) to spot under/overflows quickly
            const int m = std::min(5, n);
            ossPhi << " phiL0_4=";
            for (int j = 0; j < m; ++j)
            {
               ossPhi << (j ? "," : "") << ((j < (int)phiL.size() && std::isfinite(phiL[j])) ? phiL[j] : 0.0);
            }
            ossPhi << " phiV0_4=";
            for (int j = 0; j < m; ++j)
            {
               ossPhi << (j ? "," : "") << ((j < (int)phiV.size() && std::isfinite(phiV[j])) ? phiV[j] : 0.0);
            }
            emitLog(ossPhi.str());
         }
      }

      for (int i = 0; i < n; i++) {
         const double kvEq = clampK(phiL[i] / std::max(1e-16, phiV[i]));
         const double kv = clampK(kvEq);
         Knew[i] = clampK((1.0 - damp) * K[i] + damp * kv);
         const double rel = std::abs(Knew[i] - K[i]) / std::max(1e-12, K[i]);
         maxRel = std::max(maxRel, rel);

         const double pL = phiL[i];
         const double pV = phiV[i];

         if (!finite(pL) || !finite(pV) || pL <= 0.0 || pV <= 0.0) {
            phiBad++;
         }

         if (finite(pL))
         {
            phiLmin = std::min(phiLmin, pL); phiLmax = std::max(phiLmax, pL);
         }
         if (finite(pV))
         {
            phiVmin = std::min(phiVmin, pV); phiVmax = std::max(phiVmax, pV);
         }

         const double kvEq_ = clampK(pL / std::max(1e-16, pV));

         if (kvEq_ <= 1e-6 + 1e-18)
            clampLo++;
         if (kvEq_ >= 1e6 - 1e-12)
            clampHi++;
      }

      static std::unordered_map<int, int> g_kdiagCounts;
      int& kc = g_kdiagCounts[trayIndex];

      const bool mostlyClamped = (clampLo > (int)(0.8 * n)) || (clampHi > (int)(0.8 * n));
      const bool manyBadPhi = (phiBad > (int)(0.2 * n));

      if ((mostlyClamped || manyBadPhi) && kc < 5) {
         kc++;

         std::ostringstream oss;
         oss.setf(std::ios::fixed);
         const double bL = solL.b_mix;
         const double BL = finite(bL) ? (bL * P) / (R * T) : std::numeric_limits<double>::quiet_NaN();
         const double zmbL = (finite(solL.ZL) && finite(BL)) ? (solL.ZL - BL) : std::numeric_limits<double>::quiet_NaN();
         oss << "[EOSK_KDIAG] tray=" << trayIndex + 1
            << " T=" << std::setprecision(3) << T
            << " P=" << std::setprecision(0) << P
            << " ZL=" << (finite(ZL) ? ZL : 0.0)
            << " ZV=" << (finite(ZV) ? ZV : 0.0)
            << " BL=" << (finite(BL) ? BL : 0.0)
            << " (ZL-BL)=" << (finite(zmbL) ? zmbL : 0.0)
            << " clampLo=" << clampLo << "/" << n
            << " clampHi=" << clampHi << "/" << n
            << " phiBad=" << phiBad << "/" << n
            << " phiL(min,max)=(" << (finite(phiLmin) ? phiLmin : 0.0) << "," << (finite(phiLmax) ? phiLmax : 0.0) << ")"
            << " phiV(min,max)=(" << (finite(phiVmin) ? phiVmin : 0.0) << "," << (finite(phiVmax) ? phiVmax : 0.0) << ")";
         emitLog(oss.str());
      }

      K.swap(Knew);

      if (maxRel < 1e-6)
         break;
   }

   // Diagnostics (low-noise) – matches EOSK.js intent
   if (hasLast) {
      const double bL = lastSolL.b_mix;
      const double bV = lastSolV.b_mix;
      const double BL = finite(bL) ? (bL * P) / (R * T) : std::numeric_limits<double>::quiet_NaN();
      const double BV = finite(bV) ? (bV * P) / (R * T) : std::numeric_limits<double>::quiet_NaN();
      const double zmbL = (finite(ZL) && finite(BL)) ? (ZL - BL) : std::numeric_limits<double>::quiet_NaN();

      double kminW = std::numeric_limits<double>::infinity();
      double kmaxW = -std::numeric_limits<double>::infinity();
      for (double k : K) if (finite(k)) { kminW = std::min(kminW, k); kmaxW = std::max(kmaxW, k); }

      const bool nearSingular = finite(zmbL) && zmbL < 1e-6;
      const bool extremeK = (finite(kmaxW) && kmaxW > 1e3) || (finite(kminW) && kminW < 1e-3);

      int& c = g_warnCounts[trayIndex];
      if ((nearSingular || extremeK) && c < 5) {
         c++;
         std::ostringstream oss;
         oss.setf(std::ios::fixed);
         oss << "[EOSK_WARN] tray=" << trayIndex + 1 << " eos=" << out.eos
            << " T=" << std::setprecision(2) << T
            << " P=" << std::setprecision(0) << P
            << std::setprecision(6)
            << " B_L=" << (finite(BL) ? BL : 0.0)
            << " ZL=" << (finite(ZL) ? ZL : 0.0)
            << " ZV=" << (finite(ZV) ? ZV : 0.0)
            << " ZL-B=" << (finite(zmbL) ? zmbL : 0.0)
            << " Kmin=" << (finite(kminW) ? kminW : 0.0)
            << " Kmax=" << (finite(kmaxW) ? kmaxW : 0.0);
         emitLog(oss.str());
      }
   }

   out.K = std::move(K);

   // React parity / robustness: if no finite K values were produced (e.g., EOS log terms blew up),
   // treat this state as single-phase vapor for downstream bracketing / RR-sign diagnostics.
   // (React's sign-test path reports eosSinglePhase=1 and skips RR in this situation.)
   {
      int finiteK = 0;
      for (double kv : out.K) {
         if (std::isfinite(kv)) ++finiteK;
      }
      if (finiteK == 0) {
         out.singlePhase = true;
         if (out.phase.empty()) out.phase = "V";
         out.reason = "K_NONFINITE_ASSUME_SINGLEPHASE";
      }
   }
   out.Z_liq = ZL;
   out.Z_vap = ZV;

   emitEOSKSummary(out);

   return out;
}

// ---------- Public: mixture packages for enthalpy modules ----------
PRSVResult solvePRSV_mixture(
   double P, double T,
   const std::vector<double>& x,
   int trayIndex,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& log)
{
   // comps is a reference; assumed valid
   auto x2 = x;
   auto comps2 = comps;
   return solvePRSV(P, T, x2, trayIndex, comps2, kij, log);
}

PRResult solvePR_mixture(
   double P, double T,
   const std::vector<double>& x,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij
) {
   // comps is a reference; assumed valid
   auto x2 = x;
   auto comps2 = comps;
   return solvePR(P, T, x2, comps2, kij);
}