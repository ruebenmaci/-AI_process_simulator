#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <iomanip>
#include <numeric>
#include <regex>
#include <sstream>

#include "CounterCurrentColumnSimulator.hpp"

#include "../thermo/PHFlash.hpp"
#include "../thermo/Enthalpy.hpp"
#include "../thermo/pseudocomponents/componentData.hpp"

namespace {
   static double mixMW(const std::vector<Component>& comps, const std::vector<double>& z) {
      double mw = 0.0;
      const size_t n = std::min(comps.size(), z.size());
      for (size_t i = 0; i < n; ++i) mw += z[i] * comps[i].MW;
      return mw;
   }

   // Very rough liquid density estimate from SG (kg/m3). If SG is missing, return NaN.
   static double mixRhoL(const std::vector<Component>& comps, const std::vector<double>& z) {
      double sg = 0.0;
      double sum = 0.0;
      const size_t n = std::min(comps.size(), z.size());
      for (size_t i = 0; i < n; ++i) {
         const double wi = z[i];
         if (wi <= 0.0) continue;
         if (!std::isfinite(comps[i].SG) || comps[i].SG <= 0.0) continue;
         sg += wi * comps[i].SG;
         sum += wi;
      }
      if (sum <= 0.0) return std::numeric_limits<double>::quiet_NaN();
      sg /= sum;
      return sg * 1000.0;
   }
} // namespace

// EOS selection helper
std::string getEOSForTray(int trayIndex0, int trays, const std::string& crudeName,
   const std::string& eosMode, const std::string& eosManual);

// ================= helpers (ported from JS) =================

static inline double clampd(double x, double lo, double hi) {
   return std::min(std::max(x, lo), hi);
}

static inline void normalize(std::vector<double>& v) {
   double s = 0.0;
   for (double a : v) s += a;
   if (s <= 0) return;
   for (double& a : v) a = std::max(0.0, a / s);
}

static inline std::string trimLower(std::string s) {
   // trim
   auto isSpace = [](unsigned char c){ return std::isspace(c)!=0; };
   while (!s.empty() && isSpace((unsigned char)s.front())) s.erase(s.begin());
   while (!s.empty() && isSpace((unsigned char)s.back())) s.pop_back();
   for (char& c : s) c = (char)std::tolower((unsigned char)c);
   return s;
}

static inline bool isNoneSpec(const std::string& specRaw) {
   const std::string s = trimLower(specRaw);
   return s.empty() || s == "none" || s.rfind("none", 0) == 0;
}


static inline std::vector<double> blendVec(const std::vector<double>& a,
   const std::vector<double>& b,
   double w) {
   if (a.empty()) return b;
   if (b.empty()) return a;
   const size_t n = std::min(a.size(), b.size());
   std::vector<double> out(n, 0.0);
   const double wa = 1.0 - w;
   for (size_t i = 0; i < n; ++i) out[i] = wa * a[i] + w * b[i];
   normalize(out);
   return out;
}

static inline double etaBySection(int i, int N, int f,
   double etaTop, double etaMid, double etaBot) {
   if (i <= (int)std::floor(f / 2.0)) return clampd(std::isfinite(etaBot) ? etaBot : 1.0, 0.0, 1.0);
   if (i >= (int)std::ceil((f + N - 1) / 2.0)) return clampd(std::isfinite(etaTop) ? etaTop : 1.0, 0.0, 1.0);
   return clampd(std::isfinite(etaMid) ? etaMid : 1.0, 0.0, 1.0);
}

// Solve condenser outlet temperature Tc for a specified duty Qc.
// This is a bracketed bisection on Tc, matching the JS intent.
static double solveCondenserTcFromDuty(const std::vector<double>& y,
   const std::vector<Component>& comps,
   double P,
   int trayIndex,
   double mV_in_kgps,
   double hV_in,
   double Qc_target_kW,
   double Tseed,
   double T_MIN,
   double T_MAX) {
   // Energy balance: Qc = -mV*(hV_in - hL_out(Tc))
   // Want Qc(Tc) - Qc_target = 0
   auto QcAt = [&](double Tc) -> double {
      const double hL_out = hLiq(y, Tc, trayIndex, comps, P);
      const double Qc_HB_kW = -mV_in_kgps * (hV_in - hL_out);
      return Qc_HB_kW;
      };
   auto f = [&](double Tc) -> double { return QcAt(Tc) - Qc_target_kW; };

   double lo = T_MIN, hi = T_MAX;
   double flo = f(lo), fhi = f(hi);

   // If not bracketed, fall back to clamped seed.
   if (!(std::isfinite(flo) && std::isfinite(fhi)) || (flo > 0 && fhi > 0) || (flo < 0 && fhi < 0)) {
      return clampd(Tseed, T_MIN, T_MAX);
   }

   double mid = 0.5 * (lo + hi);
   for (int it = 0; it < 60; ++it) {
      mid = 0.5 * (lo + hi);
      const double fmid = f(mid);
      if (!std::isfinite(fmid)) break;
      if (std::abs(fmid) < 1e-3) break;
      if ((flo <= 0 && fmid <= 0) || (flo >= 0 && fmid >= 0)) { lo = mid; flo = fmid; }
      else { hi = mid; fhi = fmid; }
      if (std::abs(hi - lo) < 1e-6) break;
   }
   return clampd(mid, T_MIN, T_MAX);
}

static std::vector<double> initTrayPressures(int N, double Ptop, double Pdrop) {
   std::vector<double> P(N, 0.0);
   for (int i = 0; i < N; ++i) {
      P[i] = Ptop + (N - 1 - i) * Pdrop;
   }
   return P;
}

static std::vector<double> initTrayTempsTwoSegment(int N, double Ttop, double Tbottom, double Tfeed, int f) {
   std::vector<double> T(N, 0.0);
   // Segment 1: bottom->feed
   for (int i = 0; i <= f; ++i) {
      const double a = (f <= 0) ? 0.0 : double(i) / double(f);
      T[i] = (1.0 - a) * Tbottom + a * Tfeed;
   }
   // Segment 2: feed->top
   for (int i = f; i < N; ++i) {
      const double denom = std::max(1, (N - 1 - f));
      const double a = double(i - f) / double(denom);
      T[i] = (1.0 - a) * Tfeed + a * Ttop;
   }
   return T;
}

// Force temperatures to be monotone: bottom hottest -> top coldest, while preserving the feed tray anchor.
static void projectMonotoneTemps(std::vector<double>& T, int f) {
   const int N = (int)T.size();
   if (N <= 1) return;
   // bottom->feed: enforce non-increasing upward, i.e., T[i] >= T[i+1]
   for (int i = 0; i < f; ++i) {
      if (T[i + 1] > T[i]) T[i + 1] = T[i];
   }
   // feed->top
   for (int i = f; i < N - 1; ++i) {
      if (T[i + 1] > T[i]) T[i + 1] = T[i];
   }
}

// Smooth internal traffic vectors to reduce spikes (simple midpoint smoothing).
static void smoothVectorMidpoint(std::vector<double>& v, int passes, bool keepEnds) {
   const int n = (int)v.size();
   if (n < 3) return;
   std::vector<double> tmp(v);
   for (int p = 0; p < passes; ++p) {
      tmp = v;
      for (int i = 1; i < n - 1; ++i) tmp[i] = 0.25 * v[i - 1] + 0.5 * v[i] + 0.25 * v[i + 1];
      if (keepEnds) { tmp[0] = v[0]; tmp[n - 1] = v[n - 1]; }
      v.swap(tmp);
   }
}

static std::unordered_map<int, std::string> defaultDrawMap() {
   return {
     {32, "C1–C4 Overhead"},
     {30, "Light Naphtha"},
     {27, "Heavy Naphtha"},
     {21, "Kerosene"},
     {15, "LGO"},
     {8, "HGO"},
     { 1, "Residue"},
   };
}

// ================= main solver =================

SimulationResult simulateColumn(const SimulationOptions& opt) {
   // Components are stored by value in SimulationOptions.
   const auto* compsPtr = opt.components;
   if (!compsPtr || compsPtr->empty()) {
      throw std::runtime_error("simulateColumn: components is null/empty");
   }
   const auto& comps = *compsPtr;
   const auto& compsRef = comps;
   const int N = opt.trays;
   const int f = opt.feedTray;
   const double feed_kgps = std::max(1e-12, opt.feedRate_kgph / 3600.0);

   const double T_MIN = 250.0;
   const double T_MAX = 900.0;

   auto pickEOS = [&](int trayIndex0) -> std::string {
      return getEOSForTray(trayIndex0, N, opt.crudeName, opt.eosMode, opt.eosManual);
      };

   // Progress callback wrapper
   auto tick = [&](ProgressEvent ev) {
      if (opt.onProgress) {
         try { opt.onProgress(ev); }
         catch (...) {}
      }
   };

   const int iterPrint = std::max(1, opt.debug_iterPrint);
   const int trayPrint = std::max(0, opt.debug_trayPrint);

   // Initial T and P
   std::vector<double> T = initTrayTempsTwoSegment(N, opt.Ttop, opt.Tbottom, opt.Tfeed, f);
   std::vector<double> P = initTrayPressures(N, opt.Ptop, opt.Pdrop);

   //tick(ProgressEvent{ .stage="init", .iter=0, .tray=-1, .trays=N, .Ttop=T.back(), .Tbot=T.front() });
   ProgressEvent ev;
   ev.stage = "init";
   ev.iter = 0;
   ev.tray = -1;
   ev.trays = N;
   ev.Ttop = T.back();
   ev.Tbot = T.front();
   tick(ev);

   // Disable the PHFlash single-phase short-circuit specifically for WTI (same heuristic as JS).
   const std::string ck = opt.crudeName;
   const bool disableSinglePhaseShortCircuit = (ck == "West Texas Intermediate"); // match React: only force disable for WTI

   std::function<void(const std::string&)> logFn = [&](const std::string& s) {
      if (opt.onLog) {
         opt.onLog(s);
      }
      else {
         std::cout << s << "\n";
      }
   };

   // Helper: optional human-readable draw label for a given 1-based tray number.
   auto drawLabelForTray1 = [&](int tray1) -> std::string {
      auto it = opt.drawLabels.find(tray1);
      if (it != opt.drawLabels.end()) return it->second;
      return std::string();
   };

   // ---- Spec normalization: allow empty/None to remove condenser/reboiler
   const bool noCondenser = isNoneSpec(opt.condenserSpec);
   const bool noReboiler  = isNoneSpec(opt.reboilerSpec);
   const double refluxRatio_eff = noCondenser ? 0.0 : opt.refluxRatio;
   const double reboilRatio_eff = noReboiler ? 0.0 : opt.reboilRatio;

   // ---- [HDR] header line to mirror React run-log (kept stable for cross-impl diffing)
   if (logFn) {
      std::ostringstream oss;
      oss.setf(std::ios::fixed);
      oss << "[HDR] crude=" << opt.crudeName
          << " trays=" << opt.trays
          << " feedRate_kgph=" << opt.feedRate_kgph
          << " feedTray=" << opt.feedTray + 1
          << " Ttop=" << opt.Ttop
          << " Tbottom=" << opt.Tbottom
          << " Tfeed=" << opt.Tfeed
          << " Ptop=" << opt.Ptop
          << " Pdrop=" << opt.Pdrop
          << " condenserSpec=" << opt.condenserSpec
          << " Qc_set_kW=" << opt.Qc_kW_in
          << " reboilerSpec=" << opt.reboilerSpec
          << " Qr_set_kW=" << opt.Qr_kW_in
          << " reboilRatio_set=" << opt.reboilRatio
          << " refluxRatio_set=" << opt.refluxRatio
          << " eosMode=" << opt.eosMode
          << " eosManual=" << opt.eosManual;
      logFn(oss.str());
   }

   // Feed PH flash at tray f
   //const double Hfeed =
   //   0.5 * hVap(opt.feedZ, T[f], comps, P[f]) +
   //   0.5 * hLiq(opt.feedZ, T[f], comps, P[f]);
   const double Pf = P[f];
   const double Tf = T[f];

   // Compute equilibrium enthalpy at the *specified* feed conditions (TP evaluation)
   EqTPResult eq = equilibriumEnthalpy_TP(
      Pf,
      Tf,
      opt.feedZ,
      opt.components,
      f,
      N,
      opt.crudeName,        // or crudeHint string used by eosK
      opt.kij,
      /*murphreeEtaV=*/1.0, // match what you pass to flashPH
      opt.eosMode,
      opt.eosManual,
      logFn               // std::function<void(const std::string&)>
   );

   const double Hfeed = eq.H;

   if (logFn) {
      logFn("[EQTP] tray=" + std::to_string(f + 1) +
         " T=" + std::to_string(T[f]) +
         " P=" + std::to_string(P[f]) +
         " V=" + std::to_string(eq.V) +
         " H=" + std::to_string(eq.H) +
         (eq.singlePhase ? (" (singlePhase:" + eq.phase + ")") : ""));
   }

   // Side-draw specs (typed) + temporary legacy fraction map used by existing logic.
   const auto& drawSpecs = opt.drawSpecs;

   // Side-draw controller/clamp constants (used by map build and PI loop)
   const double SD_KP = 0.60;   // fraction / fraction
   const double SD_KI = 0.10;   // fraction / (fraction*iter)
   const double SD_FRAC_MIN = 0.0;
   const double SD_FRAC_MAX = 0.50; // safety clamp
   const double SD_INT_MIN = -0.50;
   const double SD_INT_MAX = 0.50;

   // Temporary compatibility map: tray -> commanded fraction used by existing draw logic.
   std::unordered_map<int, double> drawFrac_target;
   drawFrac_target.reserve(drawSpecs.size());
   for (const auto& ds : drawSpecs) {
      if (ds.trayIndex0 <= 0 || ds.trayIndex0 >= N) continue; // no boundary side draws
      if (!ds.phase.empty() && ds.phase != "L") continue;      // current implementation: liquid only

      double frac = 0.0;
      if (ds.basis == "stageLiqPct" || ds.basis == "feedPct") {
         frac = ds.value / 100.0;
      }
      else if (ds.basis == "kgph") {
         frac = ds.value / std::max(1e-12, opt.feedRate_kgph); // temporary mapping
      }
      else {
         frac = ds.value / 100.0;
      }

      drawFrac_target[ds.trayIndex0] = clampd(frac, SD_FRAC_MIN, SD_FRAC_MAX);
   }

   FlashPHInput in;
   in.Htarget = Hfeed;
   in.z = opt.feedZ;
   in.P = P[f];
   in.Tseed = T[f];
   in.components = opt.components;
   in.trayIndex = f;
   in.trays = N;
   in.crudeName = opt.crudeName;
   in.eosMode = opt.eosMode;
   in.eosManual = opt.eosManual;
   in.kij = opt.kij;
   in.log = logFn;

   
   in.logLevel = opt.logLevel;
// Feed-tray preflash (PT/EQTP-derived Htarget) must NOT force two-phase.
   // Let RR/no-root logic decide single-phase consistently with PRSV/EQTP.
   const bool hasDrawHere = ([&] {
      auto it = drawFrac_target.find(f);
      return it != drawFrac_target.end() && it->second > 0.0;
   })();
   in.forceTwoPhase = (opt.forceTwoPhase || hasDrawHere);
   in.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
   in.murphreeEtaV = 1.0;

   FlashPHResult feedAns = flashPH(in);

   const double TfeedSolved = feedAns.T;
   const double Vf = feedAns.V;
   const std::vector<double> xf = feedAns.x;
   const std::vector<double> yf = feedAns.y;
   T[f] = TfeedSolved;

   // Internal streams (dimensionless)
   std::vector<double> V_up(N, 0.2);
   std::vector<std::vector<double>> Y_up(N, opt.feedZ);
   std::vector<double> L_dn(N, 0.8);
   std::vector<std::vector<double>> X_dn(N, opt.feedZ);

   // Boundaries
   double L_ref = 0.5; std::vector<double> x_ref = opt.feedZ;
   double V_boil = 0.3; std::vector<double> y_boil = opt.feedZ;

   // Duties
   double Qc_kW = 0.0;
   double Qr_kW = noReboiler ? 0.0 : clampd(opt.Qr_kW_in, 0.0, 80000.0);

   // Integrators
   double ei_top_int = 0.0, ei_bot_int = 0.0;
   double last_Qc_kW = Qc_kW;

   double B_dim_last = 0.7;
   std::vector<double> xB_last = opt.feedZ;
   double Treb_last = clampd(opt.Tbottom, T_MIN, T_MAX);
   double Vfrac_reb_last = 0.0;

   // Diagnostics flags (mirrors JS)
   std::vector<Diagnostic> diagnostics;
   bool rb_hitDutyMax = false, rb_hitDutyMin = false, rb_vfracClamped = false;
   double rb_vfracRaw = NAN, rb_vfracUsed = NAN;
   bool c_tcAtMin = false, c_tcAtMax = false;

   // Condenser outlet temp (may float)
   double Tc = clampd(opt.Ttop, T_MIN, T_MAX);
   const double Tc_set_K = clampd(opt.Ttop, T_MIN, T_MAX);
   const double Qc_set_kW = noCondenser ? 0.0 : clampd(opt.Qc_kW_in, -80000.0, 0.0);
   const double Treb_set_K = clampd(opt.Tbottom, T_MIN, T_MAX);

   // Side draws for current iteration (dimensionless, product basis)
   std::vector<double> sideDraw_dim(N, 0.0);

   // ---------- Side-draw PI controllers (Option A) ----------
   // drawFrac_target is temporary compatibility target in "fraction of tray liquid outflow" space.
   // We maintain mutable drawFrac_current and PI-adjust each outer iteration.
   std::unordered_map<int, double> drawFrac_current = drawFrac_target;
   std::vector<double> sideDraw_dim_last(N, 0.0);
   std::vector<double> sideDraw_intErr(N, 0.0);

   // TEMP parity switch: disable side-draw PI adaptation and keep commanded draw
   // fractions fixed at input targets (drawFrac_current initialized from opt.sideDrawSpecs).
   const bool DISABLE_SIDEDRAW_PI_FOR_PARITY = true;
   const bool DISABLE_TEMP_SHAPING_FOR_PARITY = true;
   const bool USE_SOLVED_STATE_FOR_TRAY_REPORTING_PARITY = !opt.reportTrayFlashDiagnostics;

   // -------- Iterate --------
   // --- Convergence tracking for summary logging ---
   bool didConverge = false;
   int iterFinal = -1;
   double residFinal = 0.0;
   double dTFinal = 0.0;
   double residLast = 0.0;
   double dTLast = 0.0;

   // ---- Internal traffic sanity clamp (dimensionless, feed-anchored) ----
   // If a spec/controller runs away, internal V/L traffic can explode (dimensionless values >> O(1..10))
   // and then all energy and split calculations become meaningless. We hard-cap traffic to keep the
   // iteration numerically sane while we diagnose the root cause.
   const double kMaxTrafficDim = 50.0;
   const double kMinTrafficDim = 1e-12;

   auto maxAbsVec = [&](const std::vector<double>& v) -> double {
      double m = 0.0;
      for (double x : v) {
         if (std::isfinite(x)) m = std::max(m, std::abs(x));
      }
      return m;
   };

   auto clampTrafficDim = [&](const char* where) {
      const double maxAbs = std::max({
         std::abs(V_boil),
         std::abs(L_ref),
         maxAbsVec(V_up),
         maxAbsVec(L_dn),
         kMinTrafficDim
      });

      if (maxAbs > kMaxTrafficDim && std::isfinite(maxAbs)) {
         const double scale = kMaxTrafficDim / maxAbs;
         V_boil *= scale;
         L_ref  *= scale;
         for (auto& v : V_up) v *= scale;
         for (auto& v : L_dn) v *= scale;

         if (logFn) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss << "[TRAFFIC_CLAMP] where=" << where
                << " maxAbsDim=" << maxAbs
                << " scale=" << scale;
            logFn(oss.str());
         }
      }
   };

   for (int iter = 0; iter < opt.maxIter; ++iter) {
      const double Ttop_prev = T[N - 1];
      const double Tbot_prev = T[0];

      // --- Side-draw PI update (uses previous iteration's actual draw in dimensionless units) ---
      // Note: this only has authority if there is enough liquid leaving the tray (L_out).
      // If L_out < target, the controller will push drawFrac_current upward, but the draw will still
      // be limited by available liquid, so hitting targets may require condenser/reboiler adjustments too.
      if (!DISABLE_SIDEDRAW_PI_FOR_PARITY && !drawFrac_current.empty() && iter > 0) {
         for (auto& kv : drawFrac_current) {
            const int tray = kv.first;
            if (tray <= 0 || tray >= N) continue; // never draw from boundaries
            const auto itT = drawFrac_target.find(tray);
            const double target = (itT != drawFrac_target.end()) ? clampd(itT->second, SD_FRAC_MIN, SD_FRAC_MAX) : 0.0;
            const double actual = (tray < (int)sideDraw_dim_last.size()) ? sideDraw_dim_last[tray] : 0.0;
            const double err = target - actual;

            sideDraw_intErr[tray] = clampd(sideDraw_intErr[tray] + err, SD_INT_MIN, SD_INT_MAX);
            const double proposed = kv.second + SD_KP * err + SD_KI * sideDraw_intErr[tray];
            kv.second = clampd(proposed, SD_FRAC_MIN, SD_FRAC_MAX);
         }
      }

      std::fill(sideDraw_dim.begin(), sideDraw_dim.end(), 0.0);

      if (iter % iterPrint == 0) {
         // ---- [ITER] iteration summary (matches React formatting for cross-checking)
         if (logFn) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss << "[ITER] k=" << iter
                << " Tc=" << Tc
                << " Treb_last=" << Treb_last
                << " Qc_kW=" << Qc_kW
                << " Qr_kW=" << Qr_kW
                << " R=" << opt.refluxRatio
                << " Bset=" << opt.reboilRatio
                << " Ttop(trayN)=" << T[N - 1]
                << " Tbot(tray1)=" << T[0];
            logFn(oss.str());
         }

         ProgressEvent ev;
         ev.stage = "iter";
         ev.iter  = iter;
         ev.trays = N;
         ev.Ttop  = T[N - 1];
         ev.Tbot  = T[0];
         ev.Qc_kW = Qc_kW;
         ev.Qr_kW = Qr_kW;
         tick(ev);
      }

      std::vector<double> next_L_dn(N, 0.0);
      std::vector<std::vector<double>> next_X_dn(N);

      // Upward sweep
      double V_in = V_boil;
      std::vector<double> y_in = y_boil;
      double Hvap_carry = hVap(y_in, clampd(T[0], T_MIN, T_MAX), 0, comps, P[0]);

      for (int i = 0; i < N; ++i) {
         // Tray 1 (index 0) = reboiler drum boundary
         if (i == 0) {
            T[i] = clampd(Treb_last, T_MIN, T_MAX);
            V_up[i] = (1.0 - opt.relax) * V_up[i] + opt.relax * V_boil;
            Y_up[i] = blendVec(Y_up[i], y_boil, opt.relax);
            next_L_dn[i] = 0.0;
            next_X_dn[i] = xB_last; // or x_to_reb / reboiler liquid, but xB_last is fine here
            if (trayPrint > 0 && (0 % trayPrint) == 0) {
               ProgressEvent ev;
            	ev.stage = "trayStart"; ev.iter = iter; ev.tray = 1; ev.trays = N;
               tick(ev);
               ProgressEvent ev2;
            	ev2.stage = "trayEnd"; ev2.iter = iter; ev2.tray = 1; ev2.trays = N;
               tick(ev2);
            }
            continue;
         }
         // Tray N (index N-1): top boundary
         if (i == N - 1) {
            if (noCondenser) {
               // Open-top column: no condenser drum and no reflux.
               //
               // To match the React/JS "no condenser" behavior, the top boundary is treated as an
               // open vapor outlet: all vapor from the tray below leaves as distillate, and there is
               // no liquid downflow (no reflux). We do NOT run an additional equilibrium flash at
               // tray N with zero liquid (that can incorrectly collapse to liquid-only).
               //
               // So: top tray state is simply the outgoing vapor at the same conditions as the
               // vapor arriving from below.
               T[i] = clampd(T[i - 1], T_MIN + 5.0, T_MAX - 5.0);

               V_up[i] = std::max(1e-12, V_in);
               Y_up[i] = y_in;

               next_L_dn[i] = 0.0;
               next_X_dn[i] = y_in; // unused (no reflux), but keep sized/finite

               // Keep Tc consistent with the top tray temperature for UI/reporting.
               Tc = T[i];
            } else {
               // Condenser drum boundary (original behavior)
               T[i] = Tc;

               // vapor leaving the tray below is what reaches the condenser drum
               V_up[i] = V_up[i - 1];
               Y_up[i] = Y_up[i - 1];

               // IMPORTANT: reflux is the liquid downflow leaving the top boundary
               next_L_dn[i] = L_ref;     // not 0
               next_X_dn[i] = x_ref;
            }
             if (trayPrint > 0 && ((N - 1) % trayPrint) == 0) {
                ProgressEvent ev; ev.stage = "trayStart"; ev.iter = iter; ev.tray = N; ev.trays = N;
                tick(ev);
                ProgressEvent ev2; ev2.stage = "trayEnd"; ev2.iter = iter; ev2.tray = N; ev2.trays = N;
                tick(ev2);
             }
            continue;
         }

         if (trayPrint > 0 && (i % trayPrint) == 0) {
            ProgressEvent ev; ev.stage = "trayStart"; ev.iter = iter; ev.tray = i + 1; ev.trays = N;
            tick(ev);
         }

         const double L_in = (L_dn[i + 1] > 0 ? L_dn[i + 1] : L_ref);
         const std::vector<double>& x_in = (!X_dn[i + 1].empty() ? X_dn[i + 1] : x_ref);

         const double addV = (i == f) ? Vf : 0.0;
         const double addL = (i == f) ? (1.0 - Vf) : 0.0;

         const double M_raw = V_in + L_in + addV + addL;
         const double M = std::max(1e-12, M_raw);

         // z-mix stays essentially the same, but use M (safe)
         std::vector<double> z(opt.feedZ.size(), 0.0);
         for (size_t k = 0; k < z.size(); ++k) {
            const double num = V_in * y_in[k] + L_in * x_in[k] + addV * yf[k] + addL * xf[k];
            z[k] = std::max(0.0, num / M);
         }
         normalize(z);

         const double Tlin = (i < N - 1) ? T[i + 1] : T[i];
         const double T_liq_in = (i == N - 1) ? Tc : Tlin;

         // Enthalpy numerator
         const double hV_in = hVap(y_in, clampd(T[i - 1], T_MIN, T_MAX), i, comps, P[i]);
         const double hL_in = hLiq(x_in, T_liq_in, i, comps, P[i]);
         const double hV_feed = hVap(yf, TfeedSolved, i, comps, P[i]);
         const double hL_feed = hLiq(xf, TfeedSolved, i, comps, P[i]);

         const double Hnum =
            V_in * hV_in +
            L_in * hL_in +
            addV * hV_feed +
            addL * hL_feed;

         // Hmix with tiny-flow fallback
         double Hmix;
         if (M_raw < 1e-6) {
            if (V_in >= L_in && V_in > 1e-9)
               Hmix = hV_in;
            else if (L_in > 1e-9)
               Hmix = hL_in;
            else
            	Hmix = Hfeed; // make sure Hfeed is in scope in this function
         }
         else {
            Hmix = Hnum / M;
         }

         const double etaV = etaBySection(i, N, f,
            opt.murphree.etaV_top,
            opt.murphree.etaV_mid,
            opt.murphree.etaV_bot);

         FlashPHInput in;
         in.Htarget = Hmix;
         in.z = z;
         in.P = P[i];
         in.Tseed = T[i];
         in.components = opt.components;
         in.trayIndex = i;
         in.trays = N;
         in.crudeName = opt.crudeName;
         in.eosMode = opt.eosMode;
         in.eosManual = opt.eosManual;
         in.log = logFn;
		   in.logLevel = opt.logLevel;
         // inside the main tray sweep (where i is the tray index)
         const bool hasDrawOnThisTray = ([&] {
            auto it = drawFrac_target.find(i);
            return it != drawFrac_target.end() && it->second > 0.0;
            })();
         in.forceTwoPhase = (opt.forceTwoPhase || hasDrawOnThisTray);
         in.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
         in.murphreeEtaV = etaV;
         in.kij = opt.kij;

         if (logFn) {
            const auto [minIt, maxIt] = std::minmax_element(z.begin(), z.end());
            const double sum = std::accumulate(z.begin(), z.end(), 0.0);

            std::ostringstream oss;
            oss.setf(std::ios::fixed);

            oss << "[PH_Z] tray=" << (in.trayIndex + 1);

            const size_t n = std::min(in.components ? in.components->size() : size_t{ 0 }, z.size());
            for (size_t j = 0; j < n; ++j) {
               const Component& c = in.components->at(j);
               oss << " comp[" << j << "]=" << c.name
                  << " z[" << j << "]=" << z[j];
            }

            if (in.kij) {
               oss << " kij.size=" << in.kij->size();
            }
            else {
               oss << " kij.size=null";
            }

            oss << " Zmin=" << *minIt
               << " Zmax=" << *maxIt
               << " Zsum=" << sum;

            logFn(oss.str());
         }

         if (logFn) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss.precision(6);

            const double T_vap_in_used = clampd(T[i - 1], T_MIN, T_MAX);

            oss << "[PH_FLASH_IN] tray=" << (in.trayIndex + 1)
               << " P=" << in.P
               << " Tseed=" << in.Tseed
               << " T_vap_in_used=" << T_vap_in_used
               << " T_liq_in_used=" << T_liq_in
               << " TfeedSolved=" << TfeedSolved
               << " M=" << M
               << " V_in=" << V_in
               << " L_in=" << L_in
               << " addV=" << addV
               << " addL=" << addL
               << " hV_in=" << hV_in
               << " hL_in=" << hL_in
               << " hV_feed=" << hV_feed
               << " hL_feed=" << hL_feed
               << " Hnum=" << Hnum
               << " Hmix=" << Hmix;
            logFn(oss.str());
         }

         if (logFn && in.components) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss.precision(6);

            const size_t n = std::min<size_t>(6, in.components->size());
            for (size_t j = 0; j < n; ++j) {
               const auto& c = in.components->at(j);
               oss << "[PH_COMP] tray=" << (in.trayIndex + 1)
                  << " " << c.name
                  << "(Tc=" << c.Tc
                  << ",Pc=" << c.Pc
                  << ",w=" << c.omega
                  << ",MW=" << c.MW
                  << ",delta=" << c.delta
                  << ")";
            }
            logFn(oss.str());
         }

         FlashPHResult ans = flashPH(in);

         if (!std::isfinite(ans.T) || !std::isfinite(ans.V) || ans.V < -1e-6 || ans.V > 1 + 1e-6 ||
            !std::isfinite(ans.Htarget) || !std::isfinite(ans.Hcalc) || std::fabs(ans.dH) > 1e-2) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed); oss.precision(6);
            oss << "[FLASH_WARN] iter=" << iter << " tray=" << i + 1
               << " T=" << ans.T
               << " V=" << ans.V
               << " Htarget=" << in.Htarget
               << " P=" << in.P
               << " M=" << M
               << " V_in=" << V_in
               << " L_in=" << L_in
               << " addV=" << addV
               << " addL=" << addL;
            logFn(oss.str());
         }

         const double Tnew = ans.T;
         const double Vfrac_eq = ans.V;
         const std::vector<double> x_eq = ans.x;
         const std::vector<double> y_eq = ans.y;

         // Bottom-zone damping (stabilizing relaxation on T near reboiler)
         const bool isBottomZone = (i <= 2);
         const double etaT_bot = DISABLE_TEMP_SHAPING_FOR_PARITY ? 1.0 : 0.6;
         double T_eq_eff = Tnew;
         if (isBottomZone) T_eq_eff = T[i] + etaT_bot * (Tnew - T[i]);

         const double Told = T[i];
         const double Traw = (1.0 - opt.relaxT) * T[i] + opt.relaxT * T_eq_eff;
         T[i] = clampd(Traw, T_MIN + 5.0, T_MAX - 5.0);

         const std::vector<double> y_out = y_eq;
         const std::vector<double> x_eff = x_eq;

         const double epsFlow = 1e-12;
         double V_out = std::max(epsFlow * M, Vfrac_eq * M);
         double L_out = std::max(epsFlow * M, (1.0 - Vfrac_eq) * M);

         // Side draw spec in React is treated as a FRACTION OF THE TRAY LIQUID OUTFLOW (not % of feed).
         // Note: The UI may label draws as "% of feed", but the reference React solver applies:
         //   L_draw_dim = min(fDraw * L_out_dim, L_out_dim - 1e-12)
         // so we match that behavior here for parity.
         double fDraw = 0.0;
         auto itSD = drawFrac_current.find(i);
         if (i != 0 && itSD != drawFrac_current.end()) {
            fDraw = clampd(itSD->second, SD_FRAC_MIN, SD_FRAC_MAX);
         }

         if (fDraw > 0.0) {
            const double L_before_dim = L_out;
            const double V_before_dim = V_out;

            // React parity: draw is a fraction of the available liquid outflow on this tray.
            const double draw_dim = std::min(fDraw * L_before_dim, std::max(0.0, L_before_dim - 1e-12));

            const double L_after_dim = std::max(0.0, L_before_dim - draw_dim);
            L_out = L_after_dim;
            sideDraw_dim[i] = draw_dim;

            // Existing SIDE_DRAW log (React-style), now with correct basis.
            if (iterPrint > 0 && (iter % iterPrint) == 0) {
               double targ = 0.0;
               const auto itT = drawFrac_target.find(i);
               if (itT != drawFrac_target.end()) targ = clampd(itT->second, SD_FRAC_MIN, SD_FRAC_MAX);

               std::ostringstream oss;
               oss.setf(std::ios::fixed);
               oss.precision(6);
               oss << "[SIDE_DRAW] iter=" << iter
                  << " tray=" << i + 1
                  << " targetFrac=" << targ
                  << " cmdFrac=" << fDraw
                  << " basis=L_out"
                  << " L_out_before=" << L_before_dim
                  << " L_draw=" << draw_dim;
               logFn(oss.str());
            }

            // Verbose DRAW log (trayPrint-gated) for basis/debug parity.
            if (trayPrint > 0 && (i % trayPrint) == 0) {
               std::ostringstream oss;
               oss.precision(6);
               oss << "[DRAW] tray=" << (i + 1)
                  << " name=" << drawLabelForTray1(i + 1)
                  << " fDraw=" << fDraw
                  << " basis=L_out"
                  << " L_before_dim=" << L_before_dim
                  << " V_before_dim=" << V_before_dim
                  << " draw_dim=" << draw_dim
                  << " L_after_dim=" << L_after_dim;
               logFn(oss.str());
            }
         }

         V_up[i] = (1.0 - opt.relax) * V_up[i] + opt.relax * V_out;
         Y_up[i] = blendVec(Y_up[i], y_out, opt.relax);
         next_L_dn[i] = L_out;
         next_X_dn[i] = x_eff;

         V_in = V_out;
         y_in = y_out;
         Hvap_carry = hVap(y_out, T[i], i, comps, P[i]);

         if (trayPrint > 0 && (i % trayPrint) == 0) {
            ProgressEvent ev; ev.stage = "trayEnd"; ev.iter = iter; ev.tray = i + 1; ev.trays = N;
            ev.dT = std::abs(T[i] - Told); ev.Vfrac = Vfrac_eq;
            tick(ev);
         }
      }

      if (!DISABLE_TEMP_SHAPING_FOR_PARITY) {
         projectMonotoneTemps(T, f);
         // bottom-zone monotonicity (trays 1–4)
         const int BOT_MONO_TRAYS = std::min(4, N);
         for (int j = 0; j < BOT_MONO_TRAYS - 1; ++j) {
            if (T[j + 1] > T[j]) {
               const double avg = 0.5 * (T[j] + T[j + 1]);
               T[j] = std::max(T[j], avg);
               T[j + 1] = std::min(T[j + 1], avg);
            }
         }
      }
      // Total condenser split (or open-top when condenser removed)
      const double V_top = V_up[N - 2];
      const std::vector<double>& y_top = Y_up[N - 2];
      const double D_dim = noCondenser
         ? V_top
         : (V_top / std::max(1e-6, 1.0 + refluxRatio_eff));
      const double Lref_new = noCondenser ? 0.0 : (refluxRatio_eff * D_dim);
      const std::vector<double> xref_new = y_top;

      const std::string cMode = trimLower(opt.condenserSpec);
      // Condenser energy (skipped when removed)
      if (noCondenser) {
         Qc_kW = 0.0;
         Tc = (std::isfinite(T[N - 1]) ? T[N - 1] : Tc_set_K);
      } else {
         const double mV_in_kgps = V_top * feed_kgps;
         const double hV_in = hVap(y_top, clampd(T[N - 2], T_MIN, T_MAX), 0, comps, P[N - 2]);
         if (cMode == "duty") {
            Qc_kW = Qc_set_kW;
            Tc = solveCondenserTcFromDuty(y_top, comps, 0, P[N - 1], mV_in_kgps, hV_in, Qc_kW, Tc, T_MIN, T_MAX);
            if (Tc <= T_MIN + 1e-6) c_tcAtMin = true;
            if (Tc >= T_MAX - 1e-6) c_tcAtMax = true;
         } else {
            Tc = Tc_set_K;
            const double hL_out = hLiq(y_top, Tc, 0, comps, P[N - 1]);
            const double Qc_HB_kW = -mV_in_kgps * (hV_in - hL_out);
            Qc_kW = clampd(Qc_HB_kW, -80000.0, 0.0);
         }
      }

      // Reboiler (saturated model, duty -> temperature floats) or open-bottom when removed
      const double L_to_reb = std::max(1e-12, (N > 1 ? next_L_dn[1] : next_L_dn[0]));
      const std::vector<double> x_to_reb = (N > 1 && !next_X_dn[1].empty()) ? next_X_dn[1] : (!next_X_dn[0].empty() ? next_X_dn[0] : opt.feedZ);

      double Treb = clampd((N > 1 ? T[1] : T[0]), T_MIN, T_MAX);
      double Vfrac_reb = 0.0;
      double Vboil_new = 0.0;
      double B_new = L_to_reb;
      std::vector<double> yboil_new = x_to_reb;
      std::vector<double> xB_new = x_to_reb;

      if (!noReboiler) {
         const double mL_in_kgps = L_to_reb * feed_kgps;
         const double Hin_reb = hLiq(x_to_reb, clampd((N > 1 ? T[1] : T[0]), T_MIN, T_MAX), 0, comps, P[0]);
         const double Htarget_reb = Hin_reb + Qr_kW / std::max(1e-12, mL_in_kgps);

         FlashPHSatInput in;
         in.Htarget = Htarget_reb;
         in.z = x_to_reb;
         in.P = P[0];
         in.Tseed = clampd((N > 1 ? T[1] : T[0]), T_MIN, T_MAX);
         in.components = opt.components;
         in.trayIndex = 0;
         in.eos = pickEOS(0);
         in.Tmin = T_MIN;
         in.Tmax = T_MAX;
         in.maxIter = 80;
         in.log = logFn;
		 in.logLevel = opt.logLevel;
		 FlashPHSatResult reb = flashPH_saturated(in);

         Treb = clampd(reb.T, T_MIN, T_MAX);

         // Reboiler vapor fraction limiting (partial vs total)
         const std::string rbType = opt.reboilerType;
         const double VFRAC_REB_MAX_USER = (trimLower(rbType) == "total") ? 0.999 : 0.95;
         const double MIN_B_DIM = 1e-4;
         const double maxVByBmin = 1.0 - MIN_B_DIM / std::max(1e-12, L_to_reb);
         const double VFRAC_REB_MAX = std::min(VFRAC_REB_MAX_USER, maxVByBmin);

         const double Vfrac_raw = clampd(reb.V, 0.0, 1.0);
         Vfrac_reb = std::min(VFRAC_REB_MAX, Vfrac_raw);
         rb_vfracRaw = Vfrac_raw;
         rb_vfracUsed = Vfrac_reb;
         if (Vfrac_raw > VFRAC_REB_MAX + 1e-8) rb_vfracClamped = true;
         Vfrac_reb_last = Vfrac_reb;

         Vboil_new = std::max(1e-12, L_to_reb * Vfrac_reb);
         B_new = std::max(1e-12, L_to_reb * (1.0 - Vfrac_reb));
         yboil_new = (!reb.y.empty() ? reb.y : x_to_reb);
         xB_new = (!reb.x.empty() ? reb.x : x_to_reb);
      } else {
         // removed reboiler: open-bottom, no boilup, no duty
         Qr_kW = 0.0;
         rb_vfracRaw = 0.0;
         rb_vfracUsed = 0.0;
         Vfrac_reb_last = 0.0;
      }
      // Reboiler controller
      const std::string rbMode = trimLower(opt.reboilerSpec);
      if (noReboiler)
      {
	      Qr_kW = 0.0;
      }
      else if (rbMode == "temperature") {
         const double eT = Treb_set_K - Treb;
         ei_bot_int += eT;
         const double Qr_proposed = Qr_kW + opt.Kr_Q * eT + opt.Ki_Q * ei_bot_int;
         Qr_kW = clampd(Qr_proposed, 0.0, 80000.0);
         if (Qr_kW <= 1e-9 && Qr_proposed < 0) rb_hitDutyMin = true;
         if (Qr_kW >= 80000.0 - 1e-9 && Qr_proposed > 80000.0) rb_hitDutyMax = true;
      }
      else if (rbMode == "boilup") {
         const double ratio = Vboil_new / std::max(1e-12, B_new);
         const double eR = reboilRatio_eff - ratio;
         ei_bot_int += eR;
         const double K_ratio = 20000.0;
         const double Ki_ratio = 2000.0;
         const double Qr_proposed = Qr_kW + K_ratio * eR + Ki_ratio * ei_bot_int;
         Qr_kW = clampd(Qr_proposed, 0.0, 80000.0);
         if (Qr_kW <= 1e-9 && Qr_proposed < 0) rb_hitDutyMin = true;
         if (Qr_kW >= 80000.0 - 1e-9 && Qr_proposed > 80000.0) rb_hitDutyMax = true;
      }
      else {
         // duty
         Qr_kW = clampd(opt.Qr_kW_in, 0.0, 80000.0);
      }

      // couple tray 1/2 temps
      T[0] = Treb;
      if (N > 1) {
         if (DISABLE_TEMP_SHAPING_FOR_PARITY) {
            T[1] = clampd(T[1], T_MIN, T_MAX);
         }
         else {
            T[1] = clampd(0.85 * T[1] + 0.15 * Treb, T_MIN, T_MAX);
         }
      }

      // push downflow (relax)
      std::vector<double> L_dn_next(N, 0.0);
      std::vector<std::vector<double>> X_dn_next(N);
      for (int i = 0; i < N - 1; ++i) {
         L_dn_next[i] = (1.0 - opt.relax) * (L_dn[i]) + opt.relax * (next_L_dn[i]);
         X_dn_next[i] = (!next_X_dn[i].empty()) ? blendVec(X_dn[i].empty() ? next_X_dn[i] : X_dn[i], next_X_dn[i], opt.relax)
            : X_dn[i];
      }
      L_dn_next[N - 1] = Lref_new;
      X_dn_next[N - 1] = xref_new;
      L_dn.swap(L_dn_next);
      X_dn.swap(X_dn_next);

      // boundary recycles (relaxed)
      L_ref = (1.0 - opt.relax) * L_ref + opt.relax * Lref_new;
      x_ref = blendVec(x_ref, xref_new, opt.relax);
      V_boil = (1.0 - opt.relax) * V_boil + opt.relax * Vboil_new;
      y_boil = blendVec(y_boil, yboil_new, opt.relax);

      // --- Boundary sync ---
      // The boundary recycle variables (L_ref/x_ref and V_boil/y_boil) are already relaxed above,
      // and the per-tray loop uses those values to set the boundary trays.
      // Do NOT hard-overwrite V_up[0]/Y_up[0]/L_dn[N-1]/X_dn[N-1] here: it defeats relaxation and
      // can destabilize convergence and parity vs the React reference.
      clampTrafficDim("post-boundary-sync");

      // store bottoms
      B_dim_last = B_new;
      xB_last = xB_new;
      Treb_last = Treb;

      // Keep a copy of the actual side draws from this iteration for the next PI update.
      sideDraw_dim_last = sideDraw_dim;

      const double residSplit = std::max(std::abs(Lref_new - L_ref), std::abs(Vboil_new - V_boil));

      if (iter % iterPrint == 0) {
         // ---- [UNITS] log after control/unit conversions and split residual evaluation
         if (logFn) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss << "[UNITS] k=" << iter
                << " condenserSpec=" << opt.condenserSpec
                << " cMode=" << cMode
                << " Tc=" << Tc
                << " Qc_kW=" << Qc_kW
                << " reboilerSpec=" << opt.reboilerSpec
                << " rbMode=" << rbMode
                << " Treb=" << Treb
                << " Qr_kW=" << Qr_kW
                << " Vboil_dim=" << V_boil
                << " B_dim_last=" << B_dim_last
                << " resid=" << residSplit;
            logFn(oss.str());
         }

         ProgressEvent ev;
         ev.stage = "units";
         ev.iter  = iter;
         ev.trays = N;
         ev.Tc_K  = Tc;
         ev.Qc_kW = Qc_kW;
         ev.Treb_K = Treb;
         ev.Qr_kW  = Qr_kW;
         ev.resid  = residSplit;
         tick(ev);
      }

      // convergence tests
      const double tolSplit = 1e-4;
      const double tolTemp = 0.3;
      const bool splitOK = (std::abs(Lref_new - L_ref) < tolSplit) && (std::abs(Vboil_new - V_boil) < tolSplit);
      const double dTend = std::max(std::abs(T[N - 1] - Ttop_prev), std::abs(T[0] - Tbot_prev));
      const bool tempOK = (dTend < tolTemp);
      const bool Qstable = (std::abs(Qc_kW - last_Qc_kW) < 50.0);
      last_Qc_kW = Qc_kW;

      // track most recent residuals (even if we don't converge)
      residLast = residSplit;
      dTLast = dTend;

      if (splitOK && tempOK && iter > 10) {
         didConverge = true;
         iterFinal = iter;
         residFinal = residSplit;
         dTFinal = dTend;

         ProgressEvent ev;
         ev.stage = "converged";
         ev.iter = iterFinal;
         ev.trays = N;
         ev.resid = residFinal;
         ev.dT = dTFinal;
         ev.Ttop = T[N - 1];
         ev.Tbot = T[0];
         tick(ev);
         break;
      }
      // JS had a near-converged fallback at iter>200; opt.maxIter defaults 80, so omitted here.
   }

   // If we exited without meeting convergence criteria, publish a final progress event for logging.
   if (!didConverge) {
      iterFinal = (iterFinal < 0) ? opt.maxIter : iterFinal;
      residFinal = residLast;
      dTFinal = dTLast;

      ProgressEvent ev;
      ev.stage = "maxIter";
      ev.iter = iterFinal;
      ev.trays = N;
      ev.resid = residFinal;
      ev.dT = dTFinal;
      ev.Ttop = T[N - 1];
      ev.Tbot = T[0];
      tick(ev);
   }

   // ---------- Dimensionless products ----------
   {
      std::ostringstream oss;
      oss.setf(std::ios::fixed); oss.precision(6);
      oss << "[BASIS_CHECK] L_ref=" << L_ref
         << " V_boil=" << V_boil
         << " V_top_final=" << V_up[N - 2]
         << " B_dim_last=" << B_dim_last
         << " totalSide_dim=" << std::accumulate(sideDraw_dim.begin(), sideDraw_dim.end(), 0.0);
      logFn(oss.str());
   }

   const double V_top_final = V_up[N - 2];
   const double D_dim = noCondenser ? V_top_final : (V_top_final / std::max(1e-6, 1.0 + refluxRatio_eff));
   const double B_dim = std::max(0.0, B_dim_last);

   const double totalSide_dim = std::accumulate(sideDraw_dim.begin(), sideDraw_dim.end(), 0.0);
   const double totalProducts_dim = D_dim + totalSide_dim + B_dim;

   const double mScale_products = (totalProducts_dim > 1e-12) ? (opt.feedRate_kgph / totalProducts_dim) : 0.0;

   // High-impact debug print #2: show scaling and how it maps draw targets/actuals to kg/h.
   {
      std::ostringstream oss;
      oss.setf(std::ios::fixed); oss.precision(6);
      oss << "[SCALE_PRODUCTS]"
         << " D_dim=" << D_dim
         << " B_dim_last=" << B_dim_last
         << " totalSide_dim=" << totalSide_dim
         << " totalProducts_dim=" << totalProducts_dim
         << " mScale_products=" << mScale_products
         << " feedRate_kgph=" << opt.feedRate_kgph;
      logFn(oss.str());

      // Only print rows for trays that have side-draw targets.
      for (const auto& kv : drawFrac_target) {
         const int tray = kv.first;
         if (tray <= 0 || tray >= N)
            continue;
         const double targetFrac = clampd(kv.second, SD_FRAC_MIN, SD_FRAC_MAX);
         const double target_kgph = targetFrac * opt.feedRate_kgph;
         const double actual_dim = (tray < (int)sideDraw_dim.size()) ? sideDraw_dim[tray] : 0.0;
         const double actual_kgph_internalBasis = actual_dim * opt.feedRate_kgph;
         const double actual_kgph_productBasis = actual_dim * mScale_products;
         const double cmdFrac = (drawFrac_current.find(tray) != drawFrac_current.end()) ? drawFrac_current[tray] : targetFrac;

         std::ostringstream oss2;
         oss2.setf(std::ios::fixed); oss2.precision(6);
         oss2 << "[DRAW_CHECK] tray=" << (tray + 1)
            << " targetFrac=" << targetFrac
            << " cmdFrac=" << cmdFrac
            << " target_kgph=" << target_kgph
            << " actual_dim=" << actual_dim
            << " actual_kgph_internalBasis=" << actual_kgph_internalBasis
            << " actual_kgph_productBasis=" << actual_kgph_productBasis;
         logFn(oss2.str());
      }
   }

   const double mScale_internal = opt.feedRate_kgph;
   const double D_kgph = D_dim * mScale_products;
   const double B_kgph = B_dim * mScale_products;

   std::vector<double> sideDraws_kgph(N, 0.0);
   for (int i = 0; i < N; ++i) {
      sideDraws_kgph[i] = sideDraw_dim[i] * mScale_products;
   }

   // Final scaling summary (matches React [SCALE])
   {
      const double totalSide_kgph = std::accumulate(sideDraws_kgph.begin(), sideDraws_kgph.end(), 0.0);
      const double totalProducts_kgph = D_kgph + B_kgph + totalSide_kgph;

      std::ostringstream oss;
      oss.setf(std::ios::fixed);
      oss.precision(6);
      oss << "[SCALE]"
          << " Vtop_dim=" << V_top_final
          << " D_dim=" << D_dim
          << " B_dim=" << B_dim
          << " side_dim=" << totalSide_dim
          << " totalProducts_dim=" << totalProducts_dim
          << " mScale_products=" << mScale_products
          << " mScale_internal=" << mScale_internal
          << " D_kgph=" << D_kgph
          << " B_kgph=" << B_kgph
          << " side_kgph=" << totalSide_kgph
          << " sumProducts_kgph=" << totalProducts_kgph
          << " feedRate_kgph=" << opt.feedRate_kgph;
      logFn(oss.str());
   }

   const double L_ref_kgph = L_ref * mScale_internal;
   const double V_boil_kgph = V_boil * mScale_internal;

   // Boundary temps for UI
   const double T_overhead_cold_K = Tc;
   const double T_reboiler_hot_K = Treb_last;

   // Final tray reporting
   std::vector<TrayResult> traysOut(N);
   for (int i = 0; i < N; ++i) {
      if (i == 0) {
         const double Vreb = clampd(Vfrac_reb_last, 0.0, 1.0);
         const double Freb_kgph = B_kgph / std::max(1e-12, 1.0 - Vreb);
         TrayResult tr;
         tr.i = 1;
         tr.T = clampd(Treb_last, T_MIN, T_MAX);
         tr.T_internal = tr.T;
         tr.P = P[i];
         tr.V = Vreb;
         tr.x = xB_last;
         tr.y = y_boil;
         tr.m_vap_up_kgph = V_boil * mScale_internal;
         tr.m_liq_dn_kgph = B_kgph;
         tr.reboilerFeed_kgph = Freb_kgph;
         tr.bottomsFromSplit_kgph = (1.0 - Vreb) * Freb_kgph;
         traysOut[i] = std::move(tr);
         if (trayPrint > 0 && (0 % trayPrint) == 0) {
            ProgressEvent ev; ev.stage = "trayStart"; ev.iter = iterFinal; ev.tray = 1; ev.trays = N;
            tick(ev);
            ProgressEvent ev2; ev2.stage = "trayEnd"; ev2.iter = iterFinal; ev2.tray = 1; ev2.trays = N;
            tick(ev2);
         }
         continue;
      }
      if (i == N - 1) {
         TrayResult tr;
         tr.i = N;
         tr.P = P[i];

         if (noCondenser) {
            // Open-top: treat the top stage as an equilibrium tray with no reflux and an open vapor outlet.
            // Use the vapor leaving the tray below as the distillate condition/flow.
            const int ib = i - 1; // tray below top boundary
            const double Vtop_dim = std::max(0.0, V_up[ib]);
            const std::vector<double>& ytop = (Y_up[ib].empty() ? opt.feedZ : Y_up[ib]);

            tr.T = clampd(T[i], T_MIN, T_MAX);
            tr.T_internal = tr.T;
            tr.V = 1.0;             // top stage is vapor-only outlet in this mode
            tr.x = ytop;            // unused (no reflux), keep finite
            tr.y = ytop;
            tr.m_vap_up_kgph = Vtop_dim * mScale_internal; // all overhead vapor leaves
            tr.m_liq_dn_kgph = 0.0;                        // no reflux
         } else {
            // Condenser drum boundary (original behavior)
            tr.T = Tc;
            tr.T_internal = Tc;
            tr.V = 0.0;
            tr.x = x_ref;
            tr.y = (Y_up[i - 1].empty() ? opt.feedZ : Y_up[i - 1]);
            tr.m_vap_up_kgph = 0.0;
            tr.m_liq_dn_kgph = L_ref * mScale_internal;
         }

         traysOut[i] = std::move(tr);

         if (trayPrint > 0 && ((N - 1) % trayPrint) == 0) {
            ProgressEvent ev; ev.stage = "trayStart"; ev.iter = iterFinal; ev.tray = N; ev.trays = N;
            tick(ev);
            ProgressEvent ev2; ev2.stage = "trayEnd"; ev2.iter = iterFinal; ev2.tray = N; ev2.trays = N;
            tick(ev2);
         }
         continue;
      }

      const double L_in = (L_dn[i + 1] > 0 ? L_dn[i + 1] : L_ref);
      const std::vector<double>& x_in = (!X_dn[i + 1].empty() ? X_dn[i + 1] : x_ref);
      const double V_in = V_up[i - 1];
      const std::vector<double>& y_in = Y_up[i - 1];

      if (USE_SOLVED_STATE_FOR_TRAY_REPORTING_PARITY) {
         TrayResult tr;
         tr.i = i + 1;
         tr.T_internal = T[i];
         tr.T = clampd(T[i], T_MIN, T_MAX);
         tr.P = P[i];

         const double Vdim = std::max(0.0, V_up[i]);
         const double Ldim = std::max(0.0, L_dn[i]);
         tr.V = clampd(Vdim / std::max(1e-12, Vdim + Ldim), 0.0, 1.0);

         tr.x = (!X_dn[i].empty() ? X_dn[i] : x_in);
         tr.y = (!Y_up[i].empty() ? Y_up[i] : y_in);

         tr.m_vap_up_kgph = V_up[i] * mScale_internal;
         tr.m_liq_dn_kgph = L_dn[i] * mScale_internal;

         // Side draw reporting on product basis
         tr.sideDraw_kgph = sideDraws_kgph[i];
         const double frac = (drawFrac_target.count(i) ? drawFrac_target.at(i) : 0.0);
         tr.sideDraw_target_kgph = frac * opt.feedRate_kgph;
         tr.sideDraw_frac = frac;

         traysOut[i] = std::move(tr);
         continue;
      }

      const double addV = (i == f) ? Vf : 0.0;
      const double addL = (i == f) ? (1.0 - Vf) : 0.0;

      const double M_raw = V_in + L_in + addV + addL;
      const double M = std::max(1e-12, M_raw);

      // z-mix stays essentially the same, but use M (safe)
      std::vector<double> z(opt.feedZ.size(), 0.0);
      for (size_t k = 0; k < z.size(); ++k) {
         const double num = V_in * y_in[k] + L_in * x_in[k] + addV * yf[k] + addL * xf[k];
         z[k] = std::max(0.0, num / M);
      }
      normalize(z);

      const double Tlin = (i < N - 1) ? T[i + 1] : T[i];
      const double T_liq_in = (i == N - 1) ? Tc : Tlin;

      // Enthalpy numerator
      const double hV_in = hVap(y_in, clampd(T[i - 1], T_MIN, T_MAX), i, comps, P[i]);
      const double hL_in = hLiq(x_in, T_liq_in, i, comps, P[i]);
      const double hV_feed = hVap(yf, TfeedSolved, i, comps, P[i]);
      const double hL_feed = hLiq(xf, TfeedSolved, i, comps, P[i]);

      const double Hnum =
         V_in * hV_in +
         L_in * hL_in +
         addV * hV_feed +
         addL * hL_feed;

      // Hmix with tiny-flow fallback
      double Hmix;
      if (M_raw < 1e-6) {
         if (V_in >= L_in && V_in > 1e-9)
            Hmix = hV_in;
         else if (L_in > 1e-9)
            Hmix = hL_in;
         else
         	Hmix = Hfeed; // make sure Hfeed is in scope in this function
      }
      else {
         Hmix = Hnum / M;
      }

      const double etaV = etaBySection(i, N, f,
         opt.murphree.etaV_top,
         opt.murphree.etaV_mid,
         opt.murphree.etaV_bot);

      FlashPHInput in;
      in.Htarget = Hmix;
      in.z = z;
      in.P = P[i];
      in.Tseed = T[i];
      in.components = opt.components;
      in.trayIndex = i;
      in.trays = N;
      in.crudeName = opt.crudeName;
      in.eosMode = opt.eosMode;
      in.eosManual = opt.eosManual;
      in.log = logFn;
      in.logLevel = opt.logLevel;
      // inside final tray reporting loop (second flashPH path)
      const bool hasDrawOnThisTray = ([&] {
         auto it = drawFrac_target.find(i);
         return it != drawFrac_target.end() && it->second > 0.0;
         })();
      in.forceTwoPhase = (opt.forceTwoPhase || hasDrawOnThisTray);
      in.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
      in.murphreeEtaV = etaV;

      FlashPHResult ans = flashPH(in);

      if (!std::isfinite(ans.T) || !std::isfinite(ans.V) || ans.V < -1e-6 || ans.V > 1 + 1e-6 ||
         !std::isfinite(ans.Htarget) || !std::isfinite(ans.Hcalc) || std::fabs(ans.dH) > 1e-2) {
         std::ostringstream oss;
         oss.setf(std::ios::fixed); oss.precision(6);
         oss << "[FLASH_WARN] tray=" << i + 1
            << " T=" << ans.T
            << " V=" << ans.V
            << " Htarget=" << in.Htarget
            << " P=" << in.P
            << " M=" << M
            << " V_in=" << V_in
            << " L_in=" << L_in
            << " addV=" << addV
            << " addL=" << addL;
         logFn(oss.str());
      }

      const double Vfrac = clampd(ans.V, 0.0, 1.0);

      TrayResult tr;
      tr.i = i + 1;
      tr.T_internal = ans.T;
      tr.T = clampd(ans.T, T_MIN, T_MAX);
      tr.P = P[i];
      tr.V = Vfrac;
      tr.x = ans.x;
      tr.y = ans.y;
      tr.m_vap_up_kgph = V_up[i] * mScale_internal;
      tr.m_liq_dn_kgph = L_dn[i] * mScale_internal;

      // Flash diagnostics
      tr.Kmin = ans.Kmin;
      tr.Kmax = ans.Kmax;
      tr.Htarget = ans.Htarget;
      tr.Hcalc = ans.Hcalc;
      tr.dH = ans.dH;

      // Side draw reporting on product basis
      tr.sideDraw_kgph = sideDraws_kgph[i];
      const double frac = (drawFrac_target.count(i) ? drawFrac_target.at(i) : 0.0);
      tr.sideDraw_target_kgph = frac * opt.feedRate_kgph;
      tr.sideDraw_frac = frac;

      traysOut[i] = std::move(tr);
   }

   // Mass balance summary (product basis)
   MassBalance mb;
   mb.feed_kgph = opt.feedRate_kgph;
   mb.overhead_kgph = D_kgph;
   mb.sideDraws_kgph = sideDraws_kgph;
   mb.bottoms_kgph = B_kgph;
   mb.totalProducts_kgph = D_kgph + B_kgph + std::accumulate(sideDraws_kgph.begin(), sideDraws_kgph.end(), 0.0);

   // ---------------- Draw equality + target/actual diagnosis -----------------
   // Helps catch mistakes like:
   //  - two different trays reporting the same draw flow (often indexing/config issue)
   //  - large mismatch between target and actual (often due to scaling or removal location)
   if (logFn) {
      auto labelForTray1 = [&](int tray1) -> std::string {
         auto it = opt.drawLabels.find(tray1);
         return (it != opt.drawLabels.end()) ? it->second : std::string();
         };

      struct DrawInfo {
         int tray1;
         double target;
         double actual;
         std::string label;
      };

      std::vector<DrawInfo> draws;
      draws.reserve(opt.trays);

      for (int i = 0; i < opt.trays; ++i) {
         const double actual = (i < (int)sideDraws_kgph.size()) ? sideDraws_kgph[i] : 0.0;

         // Aggregate target on this tray from typed draw specs.
         double target = 0.0;
         bool hasTarget = false;
         std::string label;

         for (const auto& ds : opt.drawSpecs) {
            if (ds.trayIndex0 != i)
               continue;
            if (!ds.phase.empty() && ds.phase != "L")
               continue; // current side-draw path is liquid

            double t = 0.0;
            if (ds.basis == "kgph") {
               t = std::max(0.0, ds.value);
               hasTarget = true;
            }
            else if (ds.basis == "feedPct") {
               t = std::max(0.0, ds.value) * 0.01 * opt.feedRate_kgph;
               hasTarget = true;
            }
            else if (ds.basis == "stageLiqPct") {
               // Use solved tray liquid downflow as practical target basis for diagnostics.
               const double Ltray = (i < (int)traysOut.size()) ? std::max(0.0, traysOut[i].m_liq_dn_kgph) : 0.0;
               t = std::max(0.0, ds.value) * 0.01 * Ltray;
               hasTarget = true;
            }

            target += t;

            if (!ds.name.empty()) {
               if (!label.empty())
                  label += ", ";
               label += ds.name;
            }
         }

         if (label.empty())
            label = labelForTray1(i + 1);

         if (!hasTarget && !(actual > 0.0))
            continue;

         const int tray1 = i + 1;
         draws.push_back({ tray1, target, actual, label });
      }

      // Target vs actual mismatch warnings
      for (const auto& d : draws) {
         if (!(std::isfinite(d.target) && d.target > 1e-9))
            continue;
         const double relErr = std::abs(d.actual - d.target) / std::max(1.0, d.target);
         if (relErr > 0.05) {
            std::ostringstream oss;
            oss << "[DRAW_MISMATCH] tray=" << d.tray1;
            if (!d.label.empty())
               oss << " (" << d.label << ")";
            oss << "  target=" << std::fixed << std::setprecision(2) << d.target
               << " kg/h  actual=" << d.actual << " kg/h  relErr=" << (100.0 * relErr) << "%";
            logFn(oss.str());
         }
      }

      // Equality/duplication warnings
      const double absTol = 1e-3;         // kg/h
      const double relTol = 1e-6;         // dimensionless
      for (size_t a = 0; a < draws.size(); ++a) {
         for (size_t b = a + 1; b < draws.size(); ++b) {
            const double A = draws[a].actual;
            const double B = draws[b].actual;
            if (!(A > 0.0) || !(B > 0.0))
               continue;
            const double diff = std::abs(A - B);
            const double tol = std::max(absTol, relTol * std::max(std::abs(A), std::abs(B)));
            if (diff <= tol) {
               std::ostringstream oss;
               oss << "[DRAW_EQUALITY] draws have ~identical actual flow: "
                  << "tray " << draws[a].tray1;
               if (!draws[a].label.empty())
                  oss << " (" << draws[a].label << ")";
               oss << " and tray " << draws[b].tray1;
               if (!draws[b].label.empty()) 
                  oss << " (" << draws[b].label << ")";
               oss << "  actual=" << std::fixed << std::setprecision(2) << A << " kg/h";
               logFn(oss.str());
            }
         }
      }
   }

   const double reflux_fraction = clampd(
      (L_ref) / std::max(1e-6, (L_ref + V_up[N - 1])),
      0.0, 1.0
   );

   const double boilup_fraction = clampd(
      (V_boil) / std::max(1e-6, (V_boil + B_dim_last)),
      0.0, 1.0
   );

   // Energy summary
   EnergySpecSummary energy;
   energy.Qc_calc_kW = Qc_kW;
   energy.Qr_calc_kW = Qr_kW;
   energy.Tc_calc_K = T_overhead_cold_K;
   energy.Treb_calc_K = T_reboiler_hot_K;
   energy.condenserSpec = opt.condenserSpec;
   energy.reboilerSpec = opt.reboilerSpec;
   energy.condenserType = opt.condenserType;
   energy.reboilerType = opt.reboilerType;

   energy.Tc_set_K = Tc_set_K;
   energy.Qc_set_kW = Qc_set_kW;
   energy.Treb_set_K = Treb_set_K;
   energy.Qr_set_kW = noReboiler ? 0.0 : clampd(opt.Qr_kW_in, 0.0, 80000.0);

   energy.refluxRatio_set = noCondenser ? 0.0 : opt.refluxRatio;
   energy.refluxRatio_calc = L_ref / std::max(1e-6, D_dim);
   energy.boilupRatio_set = noReboiler ? 0.0 : opt.reboilRatio;
   energy.boilupRatio_calc = V_boil / std::max(1e-6, B_dim);

   energy.mScale_internal = mScale_internal;
   energy.mScale_products = mScale_products;

   energy.D_kgph = D_kgph;
   energy.B_kgph = B_kgph;
   energy.L_ref_kgph = L_ref_kgph;
   energy.V_boil_kgph = V_boil_kgph;
   energy.reflux_fraction = reflux_fraction;
   energy.boilup_fraction = boilup_fraction;
   energy.sideDraws_kgph = sideDraws_kgph;
   energy.massBalance = mb;

   // ---------- UI diagnostics (mirrors React diagnostics panel) ----------
     // Helper matches JS addDiag(level, code, message, meta?)
   auto addDiag = [&](const std::string& level,
      const std::string& code,
      const std::string& msg) {
         diagnostics.push_back(Diagnostic{ level, code, msg });
   };

   // Always add a concise "what is being solved" message (highest severity can be used by UI)
   {
      const std::string cMode = trimLower(opt.condenserSpec);
      const std::string rbMode = trimLower(opt.reboilerSpec);

      const std::string cText =
         noCondenser ? "Condenser removed (open-top, Qc=0, no reflux)" :
         (cMode == "duty")
         ? "Condenser spec: Duty (Tc calculated)"
         : "Condenser spec: Temperature (Qc calculated)";

      const std::string rText =
         noReboiler ? "Reboiler removed (open-bottom, Qr=0, no boilup)" :
         (rbMode == "temperature")
         ? "Reboiler spec: Temperature (Qr calculated)"
         : (rbMode == "boilup")
         ? "Reboiler spec: Boilup ratio (Qr calculated)"
         : "Reboiler spec: Duty (Treb calculated)";

      addDiag("info", "ACTIVE_SPECS", cText + " | " + rText);

      if (rb_vfracClamped) {
         std::ostringstream oss;
         oss.setf(std::ios::fixed); oss.precision(3);
         oss << "Reboiler vapor fraction limited to keep a liquid bottoms draw (V used="
            << (std::isfinite(rb_vfracUsed) ? rb_vfracUsed : 0.0)
            << "; raw=" << (std::isfinite(rb_vfracRaw) ? rb_vfracRaw : 0.0) << ").";
         addDiag("warning", "REB_VFRAC_CLAMP", oss.str());
      }
      if (rb_hitDutyMax) {
         addDiag("warning", "REB_Q_MAX",
            "Reboiler duty hit the upper limit (Qr clamped), so the selected spec may not be fully achievable.");
      }
      if (rb_hitDutyMin) {
         addDiag("warning", "REB_Q_MIN",
            "Reboiler duty hit the lower limit (Qr clamped), so the selected spec may not be fully achievable.");
      }
      if (c_tcAtMin || c_tcAtMax) {
         addDiag("warning", "COND_T_LIMIT",
            "Condenser temperature reached an internal safety limit while solving the duty spec.");
      }
   }

   // Assemble result
   SimulationResult out;
   out.trays = std::move(traysOut);
   out.feedTray = opt.feedTray;
   out.draws = !opt.drawLabels.empty() ? opt.drawLabels : defaultDrawMap();
   out.status = "OK";
   out.diagnostics = std::move(diagnostics);
   out.energy = std::move(energy);
   out.boundary.condenser.T_cold_K = T_overhead_cold_K;
   out.boundary.reboiler.T_hot_K = T_reboiler_hot_K;

   // ---------------- Results snapshots (streams) ----------------
   // Build a compact stream table for the Run Results view.
   // Density is a simple liquid density estimate from SG.
   out.streams.clear();
   out.streams.reserve(N + 2);

   auto addStream = [&](const std::string& name,
      int tray1based,
      double kgph,
      double T_K,
      double P_Pa,
      double Vfrac,
      const std::vector<double>& z) {
         if (!(kgph > 0.0)) return;
         StreamSnapshot s;
         s.name = name;
         s.tray = tray1based;
         s.kgph = kgph;
         s.T = T_K;
         s.P = P_Pa;
         s.Vfrac = Vfrac;
         s.MW = (opt.components ? mixMW(*opt.components, z) : 0.0);
         s.rho = mixRhoL(*opt.components, z);
         out.streams.push_back(std::move(s));
      };

   // Overhead distillate (approx: same liquid composition as reflux)
   const auto& top = out.trays[N - 1];
   if (noCondenser) addStream("Distillate", N, out.energy.D_kgph, top.T, top.P, 1.0, top.y);
   else addStream("Distillate", N, out.energy.D_kgph, top.T, top.P, 0.0, top.x);

   // Side draws (liquid) - use liquid composition leaving tray (X_dn)
   for (int i = N - 1; i >= 0; --i) {
      if (sideDraws_kgph[i] <= 0.0) continue;

      const int tray = i + 1;
      std::string nm;
      auto it = out.draws.find(tray);
      nm = (it != out.draws.end()) ? it->second : ("Draw@" + std::to_string(tray));

      const auto& tr = out.trays[i];
      addStream(nm, tray, sideDraws_kgph[i], tr.T, tr.P, tr.V, tr.x);
   }

   // Bottoms (liquid) - use bottom tray liquid composition
   const auto& bot = out.trays[0];
   // Report bottoms as the liquid product stream (Vfrac = 0) even if the bottom stage is 2-phase.
   addStream("Bottoms", 1, out.energy.B_kgph, bot.T, bot.P, 0.0, bot.x);

   return out;
}