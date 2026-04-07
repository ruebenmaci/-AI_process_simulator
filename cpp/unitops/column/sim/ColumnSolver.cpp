#include <algorithm>
#include <cctype>
#include <cmath>
#include <limits>
#include <sstream>

#include "ColumnSolver.hpp"
#include "../unitops/column/sim/CounterCurrentColumnSimulator.hpp"

SolverOutputs solveColumn(
   const SolverInputs& in,
   const std::function<void(const std::string&)>& onLog,
   const std::function<void(const ProgressEvent&)>& onProgress) {
   const FluidThermoData& thermo = in.fluidThermo;

   SimulationOptions opt;
   opt.thermoConfig = in.thermoConfig;
   opt.crudeName = in.fluidName;
   opt.trays = std::max(2, in.trays);
   opt.feedRate_kgph = std::max(0.0, in.feedRateKgph);

   // Components + z (use the prepared FluidThermoData snapshot from the feed stream)
   opt.components = &thermo.components;
   opt.kij = &thermo.kij;

   const size_t NC = thermo.components.size();
   if (in.feedComposition.size() == NC) {
      opt.feedZ = in.feedComposition;
   }
   else if (thermo.hasZDefault && thermo.zDefault.size() == NC) {
      opt.feedZ = thermo.zDefault;
   }
   else {
      opt.feedZ.assign(NC, NC ? 1.0 / (double)NC : 0.0);
   }

   opt.feedTray = std::clamp(in.feedTray, 1, opt.trays);
   opt.Tfeed = in.feedTempK;
   opt.Ttop = in.topTsetK;
   opt.Tbottom = in.bottomTsetK;

   opt.Ptop = in.topPressurePa;
   opt.Pdrop = in.dpPerTrayPa; // per-tray drop in this C++ port

   // EOS selection
   opt.eosMode = in.eosMode;
   opt.eosManual = in.eosManual;

   // Wire UI logging/progress callbacks (if present)
   opt.onLog = (in.logLevel == LogLevel::None) ? std::function<void(const std::string&)>{} : onLog;
   opt.onProgress = onProgress;

   // Solver diagnostics verbosity (UI-controlled)
   opt.logLevel = in.logLevel;
   opt.reportTrayFlashDiagnostics = true;

   // Convert typed draw specs to simulator draw specs
   opt.drawSpecs.clear();
   opt.drawSpecs.reserve(in.drawSpecs.size());
   for (const auto& ds : in.drawSpecs) {
      SimulationDrawSpec s;
      s.trayIndex0 = ds.trayIndex0;
      s.name = ds.name;
      s.basis = ds.basis;
      s.phase = ds.phase;
      s.value = ds.value;
      opt.drawSpecs.push_back(std::move(s));
   }
   opt.drawLabels = in.drawLabelsByTray1;

   // Specs
   opt.condenserType = in.condenserType;
   opt.reboilerType = in.reboilerType;

   auto trimLower = [](std::string s) {
      // basic trim
      auto isSpace = [](unsigned char c) { return std::isspace(c) != 0; };
      while (!s.empty() && isSpace((unsigned char)s.front())) s.erase(s.begin());
      while (!s.empty() && isSpace((unsigned char)s.back())) s.pop_back();
      std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
      return s;
      };

   const std::string cSpec = trimLower(in.condenserSpec);
   const std::string rSpec = trimLower(in.reboilerSpec);

   // Null/empty spec means "remove" (parity with React)
   opt.condenserSpec = cSpec.empty() ? "none" : cSpec;
   opt.reboilerSpec = rSpec.empty() ? "none" : rSpec;

   opt.refluxRatio = in.refluxRatio;
   opt.reboilRatio = in.boilupRatio;

   opt.Qc_kW_in = in.qcKW;
   opt.Qr_kW_in = in.qrKW;

   // Murphree (V always enabled; L optional)
   opt.murphree.etaV_top = in.etaVTop;
   opt.murphree.etaV_mid = in.etaVMid;
   opt.murphree.etaV_bot = in.etaVBot;
   opt.murphree.etaL_top = in.enableEtaL ? in.etaLTop : 1.0;
   opt.murphree.etaL_mid = in.enableEtaL ? in.etaLMid : 1.0;
   opt.murphree.etaL_bot = in.enableEtaL ? in.etaLBot : 1.0;

   // Run
   const SimulationResult sim = simulateColumn(opt);

   SolverOutputs out;
   out.trays.resize((size_t)opt.trays);

   // Convert tray indexing: sim.trays is 1..N in TrayResult.i, but stored in vector in solver order.
   // We will map 0=bottom, N-1=top (to match TrayModel).
   for (int i = 0; i < opt.trays && i < (int)sim.trays.size(); ++i) {
      // In the JS model and this port, trays vector is bottom->top. Keep consistent.
      const auto& t = sim.trays[(size_t)i];

      out.trays[(size_t)i].tempK = std::isfinite(t.T) ? t.T : t.T_internal;
      out.trays[(size_t)i].vFrac = t.V;
      out.trays[(size_t)i].pressurePa = t.P;
      out.trays[(size_t)i].L_kgph = t.m_liq_dn_kgph;
      out.trays[(size_t)i].V_kgph = t.m_vap_up_kgph;
      out.trays[(size_t)i].drawFlow = t.sideDraw_kgph;
      out.trays[(size_t)i].xLiq = t.x;
      out.trays[(size_t)i].yVap = t.y;
   }

   std::ostringstream ss;
   ss << sim.status;
   if (!sim.diagnostics.empty())
      ss << " (" << sim.diagnostics.size() << " diagnostics)";
   out.summary = ss.str();

   out.diagnostics = sim.diagnostics;
   out.Tcond_K = sim.boundary.condenser.T_cold_K;
   out.Treb_K = sim.boundary.reboiler.T_hot_K;
   out.condenserType = sim.energy.condenserType;

   // Run Results text (tray profile + stream summary)
   {
      std::ostringstream rr;
      rr << "Tray Profile\n";
      rr << "Tray,TempK,PressurePa,Vfrac,L_kgph,V_kgph,DrawTarget_kgph,DrawActual_kgph,Kmin,Kmax,Htarget,Hcalc,dH\n";
      for (int i = 0; i < opt.trays && i < (int)sim.trays.size(); ++i) {
         const auto& t = sim.trays[(size_t)i];
         rr << t.i << "," << t.T << "," << t.P << "," << t.V
            << "," << t.m_liq_dn_kgph << "," << t.m_vap_up_kgph << "," << t.sideDraw_target_kgph << "," << t.sideDraw_kgph
            << "," << t.Kmin << "," << t.Kmax
            << "," << t.Htarget << "," << t.Hcalc << "," << t.dH << "\n";
      }
      rr << "\nStream Summary\n";
      rr << "Stream,kgph,TempK,PressurePa,Vfrac,MW,rhoL_kgm3\n";
      for (const auto& s : sim.streams) {
         rr << s.name << "," << s.kgph << "," << s.T << "," << s.P << "," << s.Vfrac
            << "," << s.MW << "," << s.rho << "\n";
      }
      out.runResultsText = rr.str();
   }

   out.energy = sim.energy;
   out.streams = sim.streams;

   // Component names parallel to x/y vectors
   if (opt.components) {
      out.componentNames.clear();
      out.componentNames.reserve(opt.components->size());
      for (const auto& c : *opt.components)
         out.componentNames.push_back(c.name);
   }

   return out;
}