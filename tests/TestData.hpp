#pragma once
#include <string>

// Include the real input struct:
#include "../lib/sim/ColumnSolver.hpp"

struct DrawSpec {
   std::string name;
   int tray1 = 0;      // 1-based tray number
   double pct = 0.0;   // percent of feed
};

inline std::vector<DrawSpec> baselineDrawSpecs() {
   // Brent - CrudeInitialSettings.cpp.
   return {
       {"C1-C4",         32, 2.7},
       {"Light Naphtha", 30, 6.8},
       {"Heavy Naphtha", 27, 14.4},
       {"Kerosene",      21, 13.3},
       {"LGO",           15, 13.05},
       {"HGO",            8, 13.05},
       {"Residue",        1, 36.7}
   };
}

inline SolverInputs makeBaselineInputs() {
   SolverInputs in{};
   in.trays = 32;
   in.feedRateKgph = 100000.0;
   in.feedTray = 4;

   in.crudeName = "Brent";

   in.eosMode = "auto";
   in.eosManual = "PRSV";

   // If your names differ, adjust:
   in.topPressurePa = 150000.0;
   in.dpPerTrayPa = 200.0;

   in.feedTempK = 628.15;
   in.topTsetK = 398.15;
   in.bottomTsetK = 618.15;

   in.qcKW = -6000.0;
   in.qrKW = 6000.0;

   in.condenserSpec = "Temperature";
   in.reboilerSpec = "Duty";
   in.condenserType = "total";
   in.reboilerType = "partial";

   in.refluxRatio = 2.0;
   in.boilupRatio = 0.06;

   in.etaVTop = 0.75;
   in.etaVMid = 0.65;
   in.etaVBot = 0.55;
   in.enableEtaL = false;
   in.etaLTop = 1.0;
   in.etaLMid = 1.0;
   in.etaLBot = 1.0;

   // No side draws initially
   in.drawSpecs.clear();
   in.drawLabelsByTray1.clear();

   for (const auto& d : baselineDrawSpecs()) {
      const int tray1 = d.tray1;
      const double pct = d.pct;
      const std::string& name = d.name;

      if (tray1 <= 0 || tray1 > in.trays) continue;
      if (!(pct > 0.0)) continue;

      SolverDrawSpec ds;
      ds.trayIndex0 = tray1 - 1;
      ds.name = name;
      ds.basis = "feedPct";
      ds.phase = "L";
      ds.value = pct; // percent value for feedPct basis

      in.drawSpecs.push_back(ds);

      if (!name.empty()) in.drawLabelsByTray1[tray1] = name;
   }

   return in;
}

// Plain C++ log collector (replaces runLogModel_)
struct LogCollector {
   std::vector<std::string> lines;

   void operator()(const std::string& s) { lines.push_back(s); }
};

// Optional: progress collector if you want to assert progress behavior
struct ProgressCollector {
   std::vector<ProgressEvent> events;

   void operator()(const ProgressEvent& ev) { events.push_back(ev); }
};
