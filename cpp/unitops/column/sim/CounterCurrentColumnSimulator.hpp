#pragma once
#include <vector>
#include <string>
#include <unordered_map>
#include <functional>
#include <optional>

// CrudeInitialSettings is retained as an optional operating-template provider
// (legacy defaults, draw tray names). It no longer drives thermo identity.
// MurphreeEff is defined there and re-exported via this include.
#include "../config/CrudeInitialSettings.hpp"
#include "../thermo/pseudocomponents/componentData.hpp"
#include "../../../utils/LogLevel.hpp"
#include "../../../thermo/ThermoConfig.hpp"
#include "StagedColumnCore.hpp"

struct ProgressEvent {
  std::string stage;          // "init", "iter", "trayStart", "trayEnd", "units", "converged", ...
  int iter = -1;
  int tray = -1;
  int trays = -1;
  double Ttop = NAN, Tbot = NAN;
  double Tc_K = NAN, Treb_K = NAN;
  double Qc_kW = NAN, Qr_kW = NAN;
  double resid = NAN;
  double dT = NAN;
  double Vfrac = NAN;
  bool converged = false;
};

struct TrayResult {
  int i = 0;                  // 1-based tray number for UI
  double T = 0.0;             // displayed temperature (K)
  double T_internal = 0.0;    // internal iteration temperature (K)
  double P = 0.0;             // pressure (same units used by thermo)
  double V = 0.0;             // vapor fraction (0..1)

  // Flash diagnostics (captured from PH flash)
  double Kmin = NAN;
  double Kmax = NAN;
  double Htarget = NAN;
  double Hcalc = NAN;
  double dH = NAN;
  std::vector<double> x;      // liquid composition
  std::vector<double> y;      // vapor composition
  double m_vap_up_kgph = 0.0;
  double m_liq_dn_kgph = 0.0;
  double sideDraw_kgph = 0.0;          // actual achieved draw (kg/h)
  double sideDraw_target_kgph = 0.0;   // configured target draw (kg/h)
  double sideDraw_frac = 0.0;

  // Reboiler-only display fields (optional)
  double reboilerFeed_kgph = 0.0;
  double bottomsFromSplit_kgph = 0.0;
};

// A compact, UI-friendly "results snapshot" for product streams.
// These are *not* rigorous property packages yet (density is a simple
// correlation based on pseudo-component SG), but they provide the
// columns you asked for in the Run Results view.
struct StreamSnapshot {
  std::string name;            // e.g. "Distillate", "Kerosene"
  int tray = 0;                // 1-based tray where it is taken (0 for boundary)
  double kgph = 0.0;
  double T = std::numeric_limits<double>::quiet_NaN();
  double P = std::numeric_limits<double>::quiet_NaN();
  double Vfrac = 0.0;
  double MW = std::numeric_limits<double>::quiet_NaN();
  double rho = std::numeric_limits<double>::quiet_NaN(); // kg/m3 (approx)
  std::vector<double> composition;
};

struct Diagnostic {
  std::string level;   // "info" | "warn" | "error"
  std::string code;
  std::string message;
};

struct SimulationAttachedStripperSpec {
  std::string stripperId;
  std::string label = "Attached Side Stripper";
  int sourceTrayIndex0 = -1;
  int returnTrayIndex0 = -1;
  int trays = 4;
  int feedTrayIndex0 = 2;
  double topPressurePa = 101325.0;
  double dpPerStagePa = 0.0;
  std::string heatMode = "none";    // "none" | "steam" | "reboiler_duty"
  double steamRateKgph = 0.0;
  double reboilerDutyKW = 0.0;
  int maxCoupledIterations = 25;
  double couplingTolerance = 1e-3;
  double returnDamping = 0.35;
};

struct SimulationAttachedStripperSummary {
  std::string stripperId;
  std::string label;
  int sourceTray = 0;
  int returnTray = 0;
  int trays = 0;
  int feedTray = 0;
  std::string heatMode;
  double feedKgph = 0.0;
  double vaporReturnKgph = 0.0;
  double bottomsProductKgph = 0.0;
  double topTemperatureK = std::numeric_limits<double>::quiet_NaN();
  double bottomTemperatureK = std::numeric_limits<double>::quiet_NaN();
  double topPressurePa = std::numeric_limits<double>::quiet_NaN();
  double feedTemperatureK = std::numeric_limits<double>::quiet_NaN();
  double feedPressurePa = std::numeric_limits<double>::quiet_NaN();
  double vaporReturnTemperatureK = std::numeric_limits<double>::quiet_NaN();
  double vaporReturnPressurePa = std::numeric_limits<double>::quiet_NaN();
  double bottomsTemperatureK = std::numeric_limits<double>::quiet_NaN();
  double bottomsPressurePa = std::numeric_limits<double>::quiet_NaN();
  bool approximatedSteamMode = false;
  std::string status = "OK";
  bool solveConverged = false;
  bool coupledConverged = false;
  int coupledIterationsCompleted = 0;
  int maxCoupledIterations = 0;
  double coupledResidual = std::numeric_limits<double>::quiet_NaN();
  double couplingTolerance = std::numeric_limits<double>::quiet_NaN();
  double returnDamping = std::numeric_limits<double>::quiet_NaN();
  std::string coupledMode;
  std::string summaryText;
  std::vector<Diagnostic> diagnostics;
};

struct MassBalance {
  double feed_kgph = 0.0;
  double overhead_kgph = 0.0;
  std::vector<double> sideDraws_kgph;
  double bottoms_kgph = 0.0;
  double totalProducts_kgph = 0.0;
};

struct EnergySpecSummary {
  // boundary specification bookkeeping for UI
  std::string condenserSpec = "temperature";
  std::string reboilerSpec  = "duty";
  std::string condenserType = "total";
  std::string reboilerType  = "partial";

  // user setpoints
  double Tc_set_K = NAN;
  double Qc_set_kW = NAN;
  double Treb_set_K = NAN;
  double Qr_set_kW = NAN;

  // calculated
  double Tc_calc_K = NAN;
  double Qc_calc_kW = NAN;
  double Treb_calc_K = NAN;
  double Qr_calc_kW = NAN;

  // ratios
  double refluxRatio_set = NAN;
  double refluxRatio_calc = NAN;
  double boilupRatio_set = NAN;
  double boilupRatio_calc = NAN;

  // scales
  double mScale_internal = NAN;
  double mScale_products = NAN;

  // products and boundary flows
  double D_kgph = NAN;
  double B_kgph = NAN;
  double L_ref_kgph = NAN;
  double V_boil_kgph = NAN;

  double reflux_fraction = std::numeric_limits<double>::quiet_NaN();
  double boilup_fraction = std::numeric_limits<double>::quiet_NaN();

  std::vector<double> sideDraws_kgph;

  MassBalance massBalance;
};

struct BoundaryTemps {
  double T_cold_K = NAN; // condenser
  double T_hot_K  = NAN; // reboiler
};

struct SimulationResult {
  std::vector<TrayResult> trays;
  std::vector<StreamSnapshot> streams;
  int feedTray = 1;
  std::unordered_map<int, std::string> draws; // UI labels: {tray(1-based)->label}
  std::string status = "OK";
  std::vector<Diagnostic> diagnostics;
  EnergySpecSummary energy;
  struct { BoundaryTemps condenser; BoundaryTemps reboiler; } boundary;
  std::vector<SimulationAttachedStripperSummary> attachedStrippers;
};

struct SimulationDrawSpec {
   int trayIndex0 = -1;                 // 0-based tray
   std::string name;
   std::string basis = "feedPct";       // "feedPct" | "stageLiqPct" | "kgph"
   std::string phase = "L";             // "L" | "V"
   double value = 0.0;                  // basis-dependent
};

struct SimulationOptions {
  // Resolved thermo configuration from the feed stream's fluid package.
  // When thermoMethodId is non-empty this drives EOS selection on every tray.
  thermo::ThermoConfig thermoConfig;

  std::string crudeName; // reporting/label only — no longer drives EOS selection
  const std::vector<Component>* components = nullptr;
  std::vector<double> feedZ;
  int feedTray = 1;     // 1-based
  double Tfeed = 0.0;
  double Ttop = 0.0;
  double Tbottom = 0.0;

  std::string eosMode = "auto";
  std::string eosManual;

  const std::vector<std::vector<double>>* kij = nullptr;

  double Ptop = 0.0;
  double Pdrop = 0.0;
  int trays = 32;

  double refluxRatio = 2.0;
  double reboilRatio = 0.06;

  double Qr_kW_in = 6000.0;
  double Qc_kW_in = -6000.0;

  std::string condenserSpec = "temperature"; // "temperature" | "duty"

  std::string reboilerSpec = "duty"; // "duty" | "temperature" | "boilup"
  std::string condenserType = "total";
  std::string reboilerType = "partial";

  std::vector<SimulationDrawSpec> drawSpecs;
  std::unordered_map<int, std::string> drawLabels; // 1-based tray index -> label (UI)

  double feedRate_kgph = 100000.0;

  int maxIter = 80;
  double outerConvergenceTolerance = 1e-4;
  double relax = 0.45;
  double relaxT = 0.3;
  double topApproach = 10.0;
  double bottomApproach = 10.0;

  double Kc_Q = 600.0;
  double Kr_Q = 600.0;
  double Ki_Q = 0.02;

  MurphreeEff murphree;

  std::function<void(const ProgressEvent&)> onProgress;

  // Optional line-oriented logging sink. When provided, the simulator will
  // emit human-readable diagnostics (similar to the React/JS Run log).
  std::function<void(const std::string&)> onLog;
  LogLevel logLevel = LogLevel::Summary; // controls PH/EOS diagnostic verbosity
  int debug_iterPrint = 5;
  int debug_trayPrint = 1;

  // React/JS-style robustness toggle:
  // If true, allow PHFlash to attempt an EOS-based two-phase solve even when
  // a quick single-phase shortcut would otherwise be taken.
  bool forceTwoPhase = false;

  // When true, final tray reporting runs an additional flashPH per internal tray
  // to populate K/H diagnostics (Kmin/Kmax/Htarget/Hcalc/dH). This is slower.
  // When false, tray reporting uses converged solver state directly (faster).
  bool reportTrayFlashDiagnostics = false;

  // Optional internal attached side strippers fed from main-column side draws.
  // Phase 19 Pass 1 integrates an outer-iteration coupled attached-stripper path:
  // the stripper feed is taken from the current side draw on sourceTrayIndex0,
  // and the returned vapor is re-injected at returnTrayIndex0 on the next outer iteration.
  std::vector<SimulationAttachedStripperSpec> attachedStripperSpecs;
};

SimulationResult simulateColumn(const SimulationOptions& opt);
