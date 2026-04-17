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
#include "StagedColumnCore.hpp"
#include "ColumnBoundaryModels.hpp"
#include "ColumnDrawModels.hpp"
#include "ColumnReportingModels.hpp"
#include "StagedUnitSolver.hpp"
#include "AttachedStripperModels.hpp"
#include "AttachedStripperSolver.hpp"

#include "../thermo/PH_PS_PT_TS_Flash.hpp"
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

   static inline std::string trimLower(std::string s) {
      auto isSpace = [](unsigned char c) { return std::isspace(c) != 0; };
      while (!s.empty() && isSpace((unsigned char)s.front())) s.erase(s.begin());
      while (!s.empty() && isSpace((unsigned char)s.back())) s.pop_back();
      for (char& c : s) c = (char)std::tolower((unsigned char)c);
      return s;
   }
} // namespace

// EOS selection helper
std::string getEOSForTray(int trayIndex0, int trays, const std::string& crudeName,
   const std::string& eosMode, const std::string& eosManual);

// ================= main solver =================

struct CoupledStripperWorkingState {
   const SimulationAttachedStripperSpec* cfg = nullptr;
   int coupledIterationsCompleted = 0;
   bool maxCoupledIterationsNoticeEmitted = false;
   double currentVaporReturnKgps = 0.0;
   std::vector<double> currentVaporReturnY;
   double currentTopTemperatureK = std::numeric_limits<double>::quiet_NaN();
   double currentBottomsKgph = 0.0;
   std::vector<double> currentBottomsX;
   double currentBottomTemperatureK = std::numeric_limits<double>::quiet_NaN();
   std::string currentStatus = "SKIPPED";
   std::vector<Diagnostic> currentDiagnostics;
   std::string currentSummaryText;
   strippermodels::AttachedStripperSolveResult lastSolveResult;
   SimulationAttachedStripperSummary lastSummary;
};

struct AggregatedReturnState {
   double kgps = 0.0;
   std::vector<double> y;
   double temperatureK = std::numeric_limits<double>::quiet_NaN();
};

static AggregatedReturnState aggregateStripperReturnForTray(
   int trayIndex0,
   const std::vector<CoupledStripperWorkingState>& states)
{
   AggregatedReturnState out;
   for (const auto& st : states) {
      if (!st.cfg) continue;
      if (st.cfg->returnTrayIndex0 != trayIndex0) continue;
      if (st.currentVaporReturnKgps <= 1e-12 || st.currentVaporReturnY.empty()) continue;

      if (out.y.empty()) out.y.assign(st.currentVaporReturnY.size(), 0.0);
      const size_t n = std::min(out.y.size(), st.currentVaporReturnY.size());
      for (size_t k = 0; k < n; ++k) {
         out.y[k] += st.currentVaporReturnKgps * st.currentVaporReturnY[k];
      }
      if (std::isfinite(st.currentTopTemperatureK)) {
         if (!std::isfinite(out.temperatureK) || out.kgps <= 1e-12) {
            out.temperatureK = st.currentTopTemperatureK;
         }
         else {
            out.temperatureK = (out.temperatureK * out.kgps + st.currentTopTemperatureK * st.currentVaporReturnKgps)
               / (out.kgps + st.currentVaporReturnKgps);
         }
      }
      out.kgps += st.currentVaporReturnKgps;
   }
   if (out.kgps > 1e-12 && !out.y.empty()) {
      for (double& v : out.y) v = std::max(0.0, v / out.kgps);
      stagedcore::normalize(out.y);
   }
   return out;
}

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
      // Prefer ThermoConfig-driven EOS when a fluid package is assigned.
      if (!opt.thermoConfig.thermoMethodId.empty() && !opt.thermoConfig.eosName.empty())
         return opt.thermoConfig.eosName;
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

   // Initial reusable staged-column core state
   stagedcore::StagedColumnCoreState coreState = stagedcore::makeInitialCoreState(
      N, f, opt.feedZ, opt.Ttop, opt.Tbottom, opt.Tfeed, opt.Ptop, opt.Pdrop);
   auto& T = coreState.T;
   auto& P = coreState.P;
   auto& V_up = coreState.V_up;
   auto& Y_up = coreState.Y_up;
   auto& L_dn = coreState.L_dn;
   auto& X_dn = coreState.X_dn;

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

   const auto topBoundary = boundarymodels::makeTopBoundarySpec(opt, T_MIN, T_MAX);
   const auto bottomBoundary = boundarymodels::makeBottomBoundarySpec(opt, T_MIN, T_MAX);

   const bool USE_SOLVED_STATE_FOR_TRAY_REPORTING_PARITY = !opt.reportTrayFlashDiagnostics;
   const auto unitSpec = stagedunitsolver::makeMainColumnSolveSpec(
      opt,
      topBoundary,
      bottomBoundary,
      disableSinglePhaseShortCircuit,
      USE_SOLVED_STATE_FOR_TRAY_REPORTING_PARITY,
      /*disableTempShapingForParity=*/true,
      /*disableSideDrawPIForParity=*/true);

   // ---- Spec normalization: allow empty/None to remove condenser/reboiler
   const bool noCondenser = unitSpec.openTop;
   const bool noReboiler = unitSpec.openBottom;
   const double refluxRatio_eff = unitSpec.refluxRatioEff;
   const double reboilRatio_eff = unitSpec.reboilRatioEff;

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
   FlashPTResult eq = opt.thermoConfig.thermoMethodId.empty()
      ? flashPT(Pf, Tf, opt.feedZ, opt.components, f, N, opt.crudeName,
                opt.kij, /*murphreeEtaV=*/1.0, opt.eosMode, opt.eosManual, logFn)
      : flashPT(Pf, Tf, opt.feedZ, opt.thermoConfig, opt.components,
                opt.kij, /*murphreeEtaV=*/1.0, logFn);

   const double Hfeed = eq.H;

   if (logFn) {
      logFn("[EQTP] tray=" + std::to_string(f + 1) +
         " T=" + std::to_string(T[f]) +
         " P=" + std::to_string(P[f]) +
         " V=" + std::to_string(eq.V) +
         " H=" + std::to_string(eq.H) +
         (eq.singlePhase ? (" (singlePhase:" + eq.phase + ")") : ""));
   }

   // Side-draw handling extracted into drawmodels.
   const auto& drawSpecs = opt.drawSpecs;
   auto drawState = drawmodels::makeInitialDrawModelState(drawSpecs, N, opt.feedRate_kgph);
   auto& drawFrac_target = drawState.drawFrac_target;
   auto& drawFrac_current = drawState.drawFrac_current;
   auto& sideDraw_dim = drawState.sideDraw_dim;
   auto& sideDraw_dim_last = drawState.sideDraw_dim_last;
   auto& sideDraw_intErr = drawState.sideDraw_intErr;

   std::vector<CoupledStripperWorkingState> coupledStripperStates;
   coupledStripperStates.reserve(opt.attachedStripperSpecs.size());
   for (const auto& cfg : opt.attachedStripperSpecs) {
      CoupledStripperWorkingState st;
      st.cfg = &cfg;
      coupledStripperStates.push_back(std::move(st));
   }
   double coupledStripperResidLast = 0.0;

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
   in.thermoConfig = opt.thermoConfig;
   in.kij = opt.kij;
   in.log = logFn;
   in.logLevel = opt.logLevel;

   // Feed-tray preflash (PT/EQTP-derived Htarget) must NOT force two-phase.
   // Let RR/no-root logic decide single-phase consistently with PRSV/EQTP.
   const bool hasDrawHere = drawmodels::hasDrawOnTray(drawState, f);
   in.forceTwoPhase = (opt.forceTwoPhase || hasDrawHere);
   in.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
   in.murphreeEtaV = 1.0;

   FlashPHResult feedAns = flashPH(in);

   const double TfeedSolved = feedAns.T;
   const double Vf = feedAns.V;
   const std::vector<double> xf = feedAns.x;
   const std::vector<double> yf = feedAns.y;
   T[f] = TfeedSolved;

   // Boundaries
   double L_ref = 0.5; std::vector<double> x_ref = opt.feedZ;
   double V_boil = 0.3; std::vector<double> y_boil = opt.feedZ;

   // Duties
   double Qc_kW = 0.0;
   double Qr_kW = bottomBoundary.Qr_set_kW;

   // Integrators
   double ei_top_int = 0.0, ei_bot_int = 0.0;
   double last_Qc_kW = Qc_kW;

   double B_dim_last = 0.7;
   std::vector<double> xB_last = opt.feedZ;
   double Treb_last = stagedcore::clampd(opt.Tbottom, T_MIN, T_MAX);
   double Vfrac_reb_last = 0.0;

   // Diagnostics flags (mirrors JS)
   std::vector<Diagnostic> diagnostics;
   bool rb_hitDutyMax = false, rb_hitDutyMin = false, rb_vfracClamped = false;
   double rb_vfracRaw = NAN, rb_vfracUsed = NAN;
   bool c_tcAtMin = false, c_tcAtMax = false;

   // Condenser outlet temp (may float)
   double Tc = stagedcore::clampd(opt.Ttop, T_MIN, T_MAX);
   const double Tc_set_K = topBoundary.Tc_set_K;
   const double Qc_set_kW = topBoundary.Qc_set_kW;
   const double Treb_set_K = bottomBoundary.Treb_set_K;

   // Draw controller state lives in drawmodels::DrawModelState.
   const bool DISABLE_SIDEDRAW_PI_FOR_PARITY = unitSpec.disableSideDrawPIForParity;
   const bool DISABLE_TEMP_SHAPING_FOR_PARITY = unitSpec.disableTempShapingForParity;

   // -------- Iterate --------
   stagedcore::ConvergenceSnapshot convergence;
   const double kMaxTrafficDim = 50.0;
   auto boundarySeed = stagedunitsolver::makeInitialBoundarySeed(opt);
   L_ref = boundarySeed.L_ref;
   x_ref = boundarySeed.x_ref;
   V_boil = boundarySeed.V_boil;
   y_boil = boundarySeed.y_boil;
   stagedcore::BoundaryRecycleState boundaryState = stagedunitsolver::makeInitialRecycleState(boundarySeed);

   for (int iter = 0; iter < opt.maxIter; ++iter) {
      const double Ttop_prev = T[N - 1];
      const double Tbot_prev = T[0];

      // Side-draw controller update and per-iteration reset live in drawmodels.
      drawmodels::updateDrawControllers(drawState, iter, N);
      drawmodels::beginIteration(drawState);

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
         ev.iter = iter;
         ev.trays = N;
         ev.Ttop = T[N - 1];
         ev.Tbot = T[0];
         ev.Qc_kW = Qc_kW;
         ev.Qr_kW = Qr_kW;
         tick(ev);
      }

      std::vector<double> next_L_dn(N, 0.0);
      std::vector<std::vector<double>> next_X_dn(N);

      // Upward sweep
      double V_in = boundaryState.V_boil;
      std::vector<double> y_in = boundaryState.y_boil;
      double Hvap_carry = hVap(y_in, stagedcore::clampd(T[0], T_MIN, T_MAX), 0, comps, P[0]);

      for (int i = 0; i < N; ++i) {
         // Tray 1 (index 0) = reboiler drum boundary
         if (i == 0) {
            T[i] = stagedcore::clampd(Treb_last, T_MIN, T_MAX);
            V_up[i] = (1.0 - opt.relax) * V_up[i] + opt.relax * V_boil;
            Y_up[i] = stagedcore::blendVec(Y_up[i], y_boil, opt.relax);
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
               T[i] = stagedcore::clampd(T[i - 1], T_MIN + 5.0, T_MAX - 5.0);

               V_up[i] = std::max(1e-12, V_in);
               Y_up[i] = y_in;

               next_L_dn[i] = 0.0;
               next_X_dn[i] = y_in; // unused (no reflux), but keep sized/finite

               // Keep Tc consistent with the top tray temperature for UI/reporting.
               Tc = T[i];
            }
            else {
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

         const auto stripperReturn = aggregateStripperReturnForTray(i, coupledStripperStates);
         double V_in_eff = V_in;
         std::vector<double> y_in_eff = y_in;
         if (stripperReturn.kgps > 1e-12 && !stripperReturn.y.empty()) {
            if (y_in_eff.empty()) y_in_eff.assign(stripperReturn.y.size(), 0.0);
            std::vector<double> mixedY(std::max(y_in_eff.size(), stripperReturn.y.size()), 0.0);
            const size_t nCarry = y_in_eff.size();
            for (size_t k = 0; k < nCarry; ++k) mixedY[k] += V_in * y_in_eff[k];
            const size_t nRet = stripperReturn.y.size();
            for (size_t k = 0; k < nRet; ++k) mixedY[k] += stripperReturn.kgps * stripperReturn.y[k];
            V_in_eff = std::max(1e-12, V_in + stripperReturn.kgps);
            for (double& v : mixedY) v = std::max(0.0, v / V_in_eff);
            stagedcore::normalize(mixedY);
            y_in_eff = std::move(mixedY);
         }

         const double addV = (i == f) ? Vf : 0.0;
         const double addL = (i == f) ? (1.0 - Vf) : 0.0;

         const double M_raw = V_in_eff + L_in + addV + addL;
         const double M = std::max(1e-12, M_raw);

         // z-mix stays essentially the same, but use M (safe)
         std::vector<double> z(opt.feedZ.size(), 0.0);
         for (size_t k = 0; k < z.size(); ++k) {
            const double num = V_in_eff * y_in_eff[k] + L_in * x_in[k] + addV * yf[k] + addL * xf[k];
            z[k] = std::max(0.0, num / M);
         }
         stagedcore::normalize(z);

         const double Tlin = (i < N - 1) ? T[i + 1] : T[i];
         const double T_liq_in = (i == N - 1) ? Tc : Tlin;

         // Enthalpy numerator
         const double T_return_in = std::isfinite(stripperReturn.temperatureK)
            ? stagedcore::clampd(stripperReturn.temperatureK, T_MIN, T_MAX)
            : stagedcore::clampd(T[i - 1], T_MIN, T_MAX);
         const double hV_in = hVap(y_in_eff, T_return_in, i, comps, P[i]);
         const double hL_in = hLiq(x_in, T_liq_in, i, comps, P[i]);
         const double hV_feed = hVap(yf, TfeedSolved, i, comps, P[i]);
         const double hL_feed = hLiq(xf, TfeedSolved, i, comps, P[i]);

         const double Hnum =
            V_in_eff * hV_in +
            L_in * hL_in +
            addV * hV_feed +
            addL * hL_feed;

         // Hmix with tiny-flow fallback
         double Hmix;
         if (M_raw < 1e-6) {
            if (V_in_eff >= L_in && V_in_eff > 1e-9)
               Hmix = hV_in;
            else if (L_in > 1e-9)
               Hmix = hL_in;
            else
               Hmix = Hfeed; // make sure Hfeed is in scope in this function
         }
         else {
            Hmix = Hnum / M;
         }

         const double etaV = stagedcore::etaBySection(i, N, f,
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
         in.thermoConfig = opt.thermoConfig;
         in.log = logFn;
         in.logLevel = opt.logLevel;
         // inside the main tray sweep (where i is the tray index)
         const bool hasDrawOnThisTray = drawmodels::hasDrawOnTray(drawState, i);
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

            const double T_vap_in_used = T_return_in;

            oss << "[PH_FLASH_IN] tray=" << (in.trayIndex + 1)
               << " P=" << in.P
               << " Tseed=" << in.Tseed
               << " T_vap_in_used=" << T_return_in
               << " T_liq_in_used=" << T_liq_in
               << " TfeedSolved=" << TfeedSolved
               << " M=" << M
               << " V_in=" << V_in_eff
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
               << " V_in=" << V_in_eff
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
         T[i] = stagedcore::clampd(Traw, T_MIN + 5.0, T_MAX - 5.0);

         // Apply Murphree vapour efficiency post-flash (standard definition):
         //   y_out[k] = y_in[k] + eta*(y_eq[k] - y_in[k])
         //   x_eff back-calculated from the component material balance
         std::vector<double> y_out, x_eff;
         if (Vfrac_eq > 1e-6 && Vfrac_eq < 1.0 - 1e-6 && etaV < 1.0 - 1e-9
            && !y_eq.empty() && !x_eq.empty()) {
            const size_t nc = y_in.size();
            std::vector<double> y_out_raw(nc);
            double sy_out = 0.0;
            for (size_t k = 0; k < nc; ++k) {
               y_out_raw[k] = y_in[k] + etaV * (y_eq[k] - y_in[k]);
               sy_out += y_out_raw[k];
            }
            if (sy_out > 0.0) {
               y_out = y_out_raw;
               for (double& v : y_out) v /= sy_out;
            }
            else {
               y_out = y_eq;
            }
            // Back-calculate x from component material balance
            const double V_eff = Vfrac_eq * M;
            const double L_eff = std::max(1e-12, (1.0 - Vfrac_eq) * M);
            std::vector<double> x_out_raw(z.size());
            double sx_out = 0.0;
            for (size_t k = 0; k < z.size(); ++k) {
               x_out_raw[k] = std::max(0.0, (z[k] * M - V_eff * y_out[k]) / L_eff);
               sx_out += x_out_raw[k];
            }
            if (sx_out > 0.0) {
               x_eff = x_out_raw;
               for (double& v : x_eff) v /= sx_out;
            }
            else {
               x_eff = x_eq;
            }
         }
         else {
            y_out = y_eq;
            x_eff = x_eq;
         }

         const double epsFlow = 1e-12;
         double V_out = std::max(epsFlow * M, Vfrac_eq * M);
         double L_out = std::max(epsFlow * M, (1.0 - Vfrac_eq) * M);

         // Side-draw application lives in drawmodels.
         const auto drawResult = drawmodels::applyLiquidSideDraw(drawState, i, L_out, V_out);
         const double fDraw = drawResult.commandFraction;
         if (drawResult.applied) {
            const double L_before_dim = L_out;
            const double V_before_dim = V_out;
            L_out = drawResult.L_after_dim;

            if (iterPrint > 0 && (iter % iterPrint) == 0) {
               std::ostringstream oss;
               oss.setf(std::ios::fixed);
               oss.precision(6);
               oss << "[SIDE_DRAW] iter=" << iter
                  << " tray=" << i + 1
                  << " targetFrac=" << drawResult.targetFraction
                  << " cmdFrac=" << drawResult.commandFraction
                  << " basis=L_out"
                  << " L_out_before=" << L_before_dim
                  << " L_draw=" << drawResult.draw_dim;
               logFn(oss.str());
            }

            if (trayPrint > 0 && (i % trayPrint) == 0) {
               std::ostringstream oss;
               oss.precision(6);
               oss << "[DRAW] tray=" << (i + 1)
                  << " name=" << drawLabelForTray1(i + 1)
                  << " fDraw=" << drawResult.commandFraction
                  << " basis=L_out"
                  << " L_before_dim=" << L_before_dim
                  << " V_before_dim=" << V_before_dim
                  << " draw_dim=" << drawResult.draw_dim
                  << " L_after_dim=" << drawResult.L_after_dim;
               logFn(oss.str());
            }
         }

         V_up[i] = (1.0 - opt.relax) * V_up[i] + opt.relax * V_out;
         Y_up[i] = stagedcore::blendVec(Y_up[i], y_out, opt.relax);
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
         stagedcore::projectMonotoneTemps(T, f);
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

      const auto condenserResult = boundarymodels::computeCondenserBoundary(
         topBoundary, y_top, comps, P[N - 1], V_top * feed_kgps,
         hVap(y_top, stagedcore::clampd(T[N - 2], T_MIN, T_MAX), 0, comps, P[N - 2]),
         Tc, (std::isfinite(T[N - 1]) ? T[N - 1] : Tc_set_K), T_MIN, T_MAX);
      Qc_kW = condenserResult.Qc_kW;
      Tc = condenserResult.Tc;
      c_tcAtMin = condenserResult.tcAtMin;
      c_tcAtMax = condenserResult.tcAtMax;

      // Reboiler boundary handling
      const double L_to_reb = std::max(1e-12, (N > 1 ? next_L_dn[1] : next_L_dn[0]));
      const std::vector<double> x_to_reb = (N > 1 && !next_X_dn[1].empty()) ? next_X_dn[1] : (!next_X_dn[0].empty() ? next_X_dn[0] : opt.feedZ);

      const auto reboilerResult = boundarymodels::computeReboilerBoundary(
         bottomBoundary, L_to_reb, x_to_reb, feed_kgps, P[0], stagedcore::clampd((N > 1 ? T[1] : T[0]), T_MIN, T_MAX),
         Qr_kW, ei_bot_int, comps, opt.components, pickEOS(0), logFn, opt.logLevel, T_MIN, T_MAX, opt.Kr_Q, opt.Ki_Q);

      double Treb = reboilerResult.Treb;
      double Vfrac_reb = reboilerResult.Vfrac_reb;
      double Vboil_new = reboilerResult.Vboil_new;
      double B_new = reboilerResult.B_new;
      std::vector<double> yboil_new = reboilerResult.yboil_new;
      std::vector<double> xB_new = reboilerResult.xB_new;
      Qr_kW = reboilerResult.Qr_kW;
      rb_hitDutyMax = rb_hitDutyMax || reboilerResult.rb_hitDutyMax;
      rb_hitDutyMin = rb_hitDutyMin || reboilerResult.rb_hitDutyMin;
      rb_vfracClamped = rb_vfracClamped || reboilerResult.rb_vfracClamped;
      rb_vfracRaw = reboilerResult.rb_vfracRaw;
      rb_vfracUsed = reboilerResult.rb_vfracUsed;
      Vfrac_reb_last = reboilerResult.Vfrac_reb;

      // couple tray 1/2 temps
      T[0] = Treb;
      if (N > 1) {
         if (DISABLE_TEMP_SHAPING_FOR_PARITY) {
            T[1] = stagedcore::clampd(T[1], T_MIN, T_MAX);
         }
         else {
            T[1] = stagedcore::clampd(0.85 * T[1] + 0.15 * Treb, T_MIN, T_MAX);
         }
      }

      // push downflow (relax)
      stagedcore::applyRelaxedDownflow(next_L_dn, next_X_dn, opt.relax, L_dn, X_dn, Lref_new, xref_new);

      // Capture pre-relaxation boundary values for convergence residual
      // (residual must be measured against values BEFORE relaxation, not after)
      const double L_ref_preRelax = boundaryState.L_ref;
      const double V_boil_preRelax = boundaryState.V_boil;

      // boundary recycles (relaxed)
      stagedcore::applyRelaxedBoundaryRecycle(opt.relax, Lref_new, xref_new, Vboil_new, yboil_new, boundaryState);
      stagedunitsolver::syncBoundarySeedFromRecycle(boundaryState, boundarySeed);
      L_ref = boundarySeed.L_ref;
      x_ref = boundarySeed.x_ref;
      V_boil = boundarySeed.V_boil;
      y_boil = boundarySeed.y_boil;

      // --- Boundary sync ---
      // The boundary recycle variables (L_ref/x_ref and V_boil/y_boil) are already relaxed above,
      // and the per-tray loop uses those values to set the boundary trays.
      // Do NOT hard-overwrite V_up[0]/Y_up[0]/L_dn[N-1]/X_dn[N-1] here: it defeats relaxation and
      // can destabilize convergence and parity vs the React reference.
      stagedcore::clampTrafficDim(boundaryState, V_up, L_dn, kMaxTrafficDim, logFn, "post-boundary-sync");
      stagedunitsolver::syncBoundarySeedFromRecycle(boundaryState, boundarySeed);
      L_ref = boundarySeed.L_ref;
      x_ref = boundarySeed.x_ref;
      V_boil = boundarySeed.V_boil;
      y_boil = boundarySeed.y_boil;

      // store bottoms
      B_dim_last = B_new;
      xB_last = xB_new;
      Treb_last = Treb;

      // Keep a copy of the actual side draws from this iteration for the next PI update.
      drawmodels::finalizeIteration(drawState);

      coupledStripperResidLast = 0.0;
      for (auto& st : coupledStripperStates) {
         const auto& cfg = *st.cfg;
         const double stripperReturnRelax = std::clamp(cfg.returnDamping, 0.0, 1.0);
         if (st.coupledIterationsCompleted >= std::max(1, cfg.maxCoupledIterations)) {
            if (logFn && !st.maxCoupledIterationsNoticeEmitted) {
               logFn("[STRIPPER_COUPLED] label=" + cfg.label + " action=hold_last_return reason=max_coupled_iterations_reached count=" + std::to_string(st.coupledIterationsCompleted));
               st.maxCoupledIterationsNoticeEmitted = true;
            }
            continue;
         }
         const int src = cfg.sourceTrayIndex0;
         const bool validSrc = (src >= 0 && src < N);
         const double feedFlowKgph = (validSrc && src < static_cast<int>(drawState.sideDraw_dim.size()))
            ? std::max(0.0, drawState.sideDraw_dim[src] * 3600.0)
            : 0.0;
         const std::vector<double> feedZ = (validSrc && src < static_cast<int>(next_X_dn.size())) ? next_X_dn[src] : std::vector<double>{};
         const double feedTemperatureK = validSrc ? T[src] : 298.15;
         const double feedPressurePa = validSrc ? P[src] : 101325.0;
         auto stripperSpec = strippermodels::makeSolveSpecFromFeed(
            opt,
            cfg,
            feedFlowKgph,
            feedZ,
            feedTemperatureK,
            feedPressurePa);

         if (stripperSpec.feed.flowKgph <= 1e-9 || stripperSpec.feed.z.empty()) {
            Diagnostic d;
            d.level = "warn";
            d.code = "attached_stripper_feed_unavailable";
            d.message = "Attached stripper '" + cfg.label + "': the current coupled source tray did not provide a positive liquid side-draw feed, so the stripper solve was skipped for this iteration.";
            st.currentStatus = "SKIPPED";
            st.currentDiagnostics = { d };
            st.currentSummaryText.clear();
            st.currentVaporReturnKgps = (1.0 - stripperReturnRelax) * st.currentVaporReturnKgps;
            ++st.coupledIterationsCompleted;
            if (!st.currentVaporReturnY.empty()) {
               // keep composition for damping continuity if a later iteration recovers feed
            }
            coupledStripperResidLast = std::max(coupledStripperResidLast, st.currentVaporReturnKgps);
            continue;
         }

         auto stripperResult = strippermodels::simulateAttachedStripper(stripperSpec);
         auto summary = strippermodels::makeSummary(cfg, stripperResult);

         Diagnostic info;
         info.level = "info";
         info.code = "attached_stripper_coupled_iteration";
         info.message = "Attached stripper '" + summary.label + "': solved inside the global coupled column iteration. Vapor return is re-injected at tray "
            + std::to_string(summary.returnTray) + " on the next outer iteration so the main-column and attached-stripper states can relax toward a mutually consistent solution.";
         summary.diagnostics.push_back(info);
         stripperResult.diagnostics.push_back(info);

         const double newReturnKgpsRaw = std::max(0.0, stripperResult.vaporReturnKgph / 3600.0);
         const double relaxedReturnKgps = stripperReturnRelax * newReturnKgpsRaw + (1.0 - stripperReturnRelax) * st.currentVaporReturnKgps;
         const double baseReturn = std::max({1e-9, std::abs(newReturnKgpsRaw), std::abs(st.currentVaporReturnKgps)});
         const double localCoupledResidual = std::abs(relaxedReturnKgps - st.currentVaporReturnKgps) / baseReturn;
         coupledStripperResidLast = std::max(coupledStripperResidLast, localCoupledResidual);
         summary.coupledIterationsCompleted = st.coupledIterationsCompleted + 1;
         summary.maxCoupledIterations = std::max(1, cfg.maxCoupledIterations);
         summary.coupledResidual = localCoupledResidual;
         summary.couplingTolerance = std::max(1e-8, cfg.couplingTolerance);
         summary.returnDamping = stripperReturnRelax;
         summary.coupledConverged = (localCoupledResidual < summary.couplingTolerance);
         summary.coupledMode = "outer_iteration_reinject";

         if (!stripperResult.vaporReturnY.empty()) {
            if (st.currentVaporReturnY.empty()) st.currentVaporReturnY = stripperResult.vaporReturnY;
            else st.currentVaporReturnY = stagedcore::blendVec(st.currentVaporReturnY, stripperResult.vaporReturnY, stripperReturnRelax);
         }
         st.currentVaporReturnKgps = relaxedReturnKgps;
         st.currentTopTemperatureK = summary.topTemperatureK;
         st.currentBottomsKgph = stripperResult.bottomsProductKgph;
         st.currentBottomsX = stripperResult.bottomsX;
         st.currentBottomTemperatureK = summary.bottomTemperatureK;
         st.currentStatus = summary.status;
         st.currentDiagnostics = summary.diagnostics;
         st.currentSummaryText = summary.summaryText;
         ++st.coupledIterationsCompleted;
         st.lastSolveResult = std::move(stripperResult);
         st.lastSummary = std::move(summary);

         if (logFn && (iter % iterPrint) == 0) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss.precision(6);
            oss << "[STRIPPER_COUPLED] iter=" << iter
               << " label=" << cfg.label
               << " srcTray=" << (cfg.sourceTrayIndex0 + 1)
               << " retTray=" << (cfg.returnTrayIndex0 + 1)
               << " feedKgph=" << stripperSpec.feed.flowKgph
               << " vaporReturnKgph_raw=" << stripperResult.vaporReturnKgph
               << " vaporReturnKgph_relaxed=" << (st.currentVaporReturnKgps * 3600.0)
               << " bottomsKgph=" << stripperResult.bottomsProductKgph;
            logFn(oss.str());
         }
      }

      const double residSplit = std::max(std::abs(Lref_new - L_ref_preRelax), std::abs(Vboil_new - V_boil_preRelax));

      const std::string cMode = trimLower(opt.condenserSpec);
      const std::string rbMode = trimLower(opt.reboilerSpec);

      if (iter % iterPrint == 0) {
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
         ev.iter = iter;
         ev.trays = N;
         ev.Tc_K = Tc;
         ev.Qc_kW = Qc_kW;
         ev.Treb_K = Treb;
         ev.Qr_kW = Qr_kW;
         ev.resid = residSplit;
         tick(ev);
      }

      // convergence tests
      const double tolSplit = std::max(1e-8, opt.outerConvergenceTolerance);
      const double tolTemp = 0.3;
      const double dTend = std::max(std::abs(T[N - 1] - Ttop_prev), std::abs(T[0] - Tbot_prev));
      const bool Qstable = (std::abs(Qc_kW - last_Qc_kW) < 50.0);
      last_Qc_kW = Qc_kW;

      if (stagedcore::updateConvergence(convergence, iter, residSplit, dTend, tolSplit, tolTemp)) {
         const bool noAttachedStrippers = coupledStripperStates.empty();
         double coupledTol = std::numeric_limits<double>::infinity();
         for (const auto& s : coupledStripperStates) coupledTol = std::min(coupledTol, std::max(1e-8, s.cfg->couplingTolerance));
         if (!std::isfinite(coupledTol)) coupledTol = 1e-3;
         const bool stripperConverged = (coupledStripperResidLast < coupledTol);
         if (noAttachedStrippers || stripperConverged) {
            ProgressEvent ev;
            ev.stage = "converged";
            ev.iter = convergence.iterFinal;
            ev.trays = N;
            ev.resid = convergence.residFinal;
            ev.dT = convergence.dTFinal;
            ev.Ttop = T[N - 1];
            ev.Tbot = T[0];
            tick(ev);
            break;
         }
         if (logFn && (iter % iterPrint) == 0) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss.precision(6);
            oss << "[STRIPPER_COUPLED] iter=" << iter
               << " mainColumnConverged=true coupledStripperResid=" << coupledStripperResidLast
               << " action=continue_outer_iteration";
            logFn(oss.str());
         }
      }
      // JS had a near-converged fallback at iter>200; opt.maxIter defaults 80, so omitted here.
   }

   // If we exited without meeting convergence criteria, publish a final progress event for logging.
   if (!convergence.didConverge) {
      convergence.iterFinal = (convergence.iterFinal < 0) ? opt.maxIter : convergence.iterFinal;
      convergence.residFinal = convergence.residLast;
      convergence.dTFinal = convergence.dTLast;

      ProgressEvent ev;
      ev.stage = "maxIter";
      ev.iter = convergence.iterFinal;
      ev.trays = N;
      ev.resid = convergence.residFinal;
      ev.dT = convergence.dTFinal;
      ev.Ttop = T[N - 1];
      ev.Tbot = T[0];
      tick(ev);
   }

   const auto fallbackDraws = defaultDrawMap();
   reportingmodels::MainColumnReportingContext reportCtx;
   reportCtx.opt = &opt;
   reportCtx.drawState = &drawState;
   reportCtx.logFn = &logFn;
   reportCtx.noCondenser = noCondenser;
   reportCtx.noReboiler = noReboiler;
   reportCtx.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
   reportCtx.useSolvedStateForTrayReporting = USE_SOLVED_STATE_FOR_TRAY_REPORTING_PARITY;
   reportCtx.refluxRatio_eff = refluxRatio_eff;
   reportCtx.Qc_kW = Qc_kW;
   reportCtx.Qr_kW = Qr_kW;
   reportCtx.Tc = Tc;
   reportCtx.Treb_last = Treb_last;
   reportCtx.Tc_set_K = Tc_set_K;
   reportCtx.Qc_set_kW = Qc_set_kW;
   reportCtx.Treb_set_K = Treb_set_K;
   reportCtx.B_dim_last = B_dim_last;
   reportCtx.Vfrac_reb_last = Vfrac_reb_last;
   reportCtx.Vf = Vf;
   reportCtx.TfeedSolved = TfeedSolved;
   reportCtx.Hfeed = Hfeed;
   reportCtx.rb_hitDutyMax = rb_hitDutyMax;
   reportCtx.rb_hitDutyMin = rb_hitDutyMin;
   reportCtx.rb_vfracClamped = rb_vfracClamped;
   reportCtx.rb_vfracRaw = rb_vfracRaw;
   reportCtx.rb_vfracUsed = rb_vfracUsed;
   reportCtx.c_tcAtMin = c_tcAtMin;
   reportCtx.c_tcAtMax = c_tcAtMax;
   reportCtx.N = N;
   reportCtx.f = f;
   reportCtx.trayPrint = trayPrint;
   reportCtx.T_MIN = T_MIN;
   reportCtx.T_MAX = T_MAX;
   reportCtx.xf = &xf;
   reportCtx.yf = &yf;
   reportCtx.xB_last = &xB_last;
   reportCtx.x_ref = &x_ref;
   reportCtx.y_boil = &y_boil;
   reportCtx.T = &T;
   reportCtx.P = &P;
   reportCtx.V_up = &V_up;
   reportCtx.Y_up = &Y_up;
   reportCtx.L_dn = &L_dn;
   reportCtx.X_dn = &X_dn;
   reportCtx.convergence = &convergence;
   reportCtx.fallbackDrawMap = &fallbackDraws;

   SimulationResult result = reportingmodels::buildMainColumnResult(reportCtx, L_ref, V_boil);

   // Phase 19 Pass 1: attached strippers are solved inside the global column loop,
   // and their vapor returns are re-injected on the next outer iteration.
   // Final reporting is built from the last coupled-stripper working state.
   for (const auto& st : coupledStripperStates) {
      if (!st.cfg) continue;
      const auto& cfg = *st.cfg;

      if (st.currentStatus == "SKIPPED" || st.lastSummary.label.empty()) {
         Diagnostic d;
         if (!st.currentDiagnostics.empty()) d = st.currentDiagnostics.front();
         else {
            d.level = "warn";
            d.code = "attached_stripper_feed_unavailable";
            d.message = "Attached stripper '" + cfg.label + "': the solved source tray did not provide a positive liquid side-draw feed, so the stripper solve was skipped.";
         }
         result.diagnostics.push_back(d);

         SimulationAttachedStripperSummary s;
         s.stripperId = cfg.stripperId;
         s.label = cfg.label;
         s.sourceTray = cfg.sourceTrayIndex0 + 1;
         s.returnTray = cfg.returnTrayIndex0 + 1;
         s.status = "SKIPPED";
         s.solveConverged = false;
         s.coupledConverged = false;
         s.coupledIterationsCompleted = st.coupledIterationsCompleted;
         s.maxCoupledIterations = std::max(1, cfg.maxCoupledIterations);
         s.coupledResidual = st.currentVaporReturnKgps;
         s.couplingTolerance = std::max(1e-8, cfg.couplingTolerance);
         s.returnDamping = std::clamp(cfg.returnDamping, 0.0, 1.0);
         s.coupledMode = "outer_iteration_reinject";
         s.diagnostics.push_back(d);
         if (logFn) {
            logFn(std::string("[STRIPPER] ") + cfg.label + " status=SKIPPED sourceTray=" + std::to_string(cfg.sourceTrayIndex0 + 1) +
               " returnTray=" + std::to_string(cfg.returnTrayIndex0 + 1) +
               " reason=feed_unavailable");
         }
         result.attachedStrippers.push_back(std::move(s));
         continue;
      }

      auto summary = st.lastSummary;

      StreamSnapshot vapor;
      vapor.name = summary.label + " Vapor Return";
      vapor.tray = summary.returnTray;
      vapor.kgph = st.currentVaporReturnKgps * 3600.0;
      if (!st.lastSolveResult.columnLikeResult.trays.empty()) {
         const auto& topTr = st.lastSolveResult.columnLikeResult.trays.back();
         vapor.T = topTr.T;
         vapor.P = topTr.P;
         vapor.Vfrac = topTr.V;
         vapor.MW = mixMW(compsRef, topTr.y);
         vapor.rho = mixRhoL(compsRef, topTr.x);
         vapor.composition = st.currentVaporReturnY.empty() ? topTr.y : st.currentVaporReturnY;
      }
      result.streams.push_back(std::move(vapor));

      StreamSnapshot bottoms;
      bottoms.name = summary.label + " Bottoms";
      bottoms.tray = summary.sourceTray;
      bottoms.kgph = st.currentBottomsKgph;
      if (!st.lastSolveResult.columnLikeResult.trays.empty()) {
         const auto& botTr = st.lastSolveResult.columnLikeResult.trays.front();
         bottoms.T = botTr.T;
         bottoms.P = botTr.P;
         bottoms.Vfrac = botTr.V;
         bottoms.MW = mixMW(compsRef, botTr.x);
         bottoms.rho = mixRhoL(compsRef, botTr.x);
         bottoms.composition = botTr.x;
      }
      result.streams.push_back(std::move(bottoms));

      summary.coupledMode = "outer_iteration_reinject";
      if (summary.coupledIterationsCompleted <= 0) summary.coupledIterationsCompleted = st.coupledIterationsCompleted;
      if (summary.maxCoupledIterations <= 0) summary.maxCoupledIterations = std::max(1, cfg.maxCoupledIterations);
      if (!std::isfinite(summary.couplingTolerance)) summary.couplingTolerance = std::max(1e-8, cfg.couplingTolerance);
      if (!std::isfinite(summary.returnDamping)) summary.returnDamping = std::clamp(cfg.returnDamping, 0.0, 1.0);

      auto hasDiagnosticCode = [](const std::vector<Diagnostic>& diags, const std::string& code) {
         return std::any_of(diags.begin(), diags.end(), [&](const Diagnostic& d) { return d.code == code; });
      };

      if (!summary.solveConverged) {
         if (!hasDiagnosticCode(summary.diagnostics, "attached_stripper_solve_not_converged")) {
            Diagnostic d;
            d.level = "error";
            d.code = "attached_stripper_solve_not_converged";
            d.message = "Attached stripper '" + summary.label + "': the internal stripper solve did not converge to a usable result during the coupled column solve.";
            summary.diagnostics.push_back(d);
         }
         summary.status = "FAILED";
      }
      else if (!summary.coupledConverged) {
         if (!hasDiagnosticCode(summary.diagnostics, "attached_stripper_coupling_not_converged")) {
            Diagnostic d;
            d.level = "warn";
            d.code = "attached_stripper_coupling_not_converged";
            std::ostringstream msg;
            msg.setf(std::ios::fixed);
            msg.precision(6);
            msg << "Attached stripper '" << summary.label
                << "': the vapor-return recoupling did not settle within tolerance during the coupled column solve. residual="
                << summary.coupledResidual << " tolerance=" << summary.couplingTolerance
                << " iterations=" << summary.coupledIterationsCompleted << "/" << summary.maxCoupledIterations << ".";
            d.message = msg.str();
            summary.diagnostics.push_back(d);
         }
         summary.status = "WARN";
      }
      else if (summary.status.empty()) {
         summary.status = "OK";
      }

      {
         std::ostringstream extra;
         extra.setf(std::ios::fixed);
         extra.precision(6);
         extra << " coupledMode=outer_iteration_reinject"
               << " coupledConverged=" << (summary.coupledConverged ? "true" : "false")
               << " coupledResidual=" << summary.coupledResidual
               << " couplingTolerance=" << summary.couplingTolerance
               << " coupledIterations=" << summary.coupledIterationsCompleted << "/" << summary.maxCoupledIterations;
         summary.summaryText += extra.str();
      }

      for (const auto& d : summary.diagnostics) {
         result.diagnostics.push_back(d);
         if (logFn) {
            logFn(std::string("[STRIPPER_DIAG] ") + cfg.label + " level=" + d.level + " code=" + d.code + " msg=" + d.message);
         }
      }

      if (logFn) {
         logFn(std::string("[STRIPPER] ") + summary.summaryText);
      }
      result.attachedStrippers.push_back(std::move(summary));
   }

   return result;
}
