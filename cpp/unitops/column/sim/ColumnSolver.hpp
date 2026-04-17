#pragma once

#include <string>
#include <vector>
#include <functional>
#include <unordered_map>
#include <cmath>
#include <utility>

#include "CounterCurrentColumnSimulator.hpp"  // ProgressEvent
#include "../thermo/pseudocomponents/FluidDefinition.hpp"
#include "../../../utils/LogLevel.hpp"
#include "../../../thermo/ThermoConfig.hpp"

struct SolverDrawSpec {
   int trayIndex0 = -1;                 // 0-based tray
   std::string name;                    // label
   std::string basis = "feedPct";       // "feedPct" | "stageLiqPct" | "kgph"
   std::string phase = "L";             // "L" | "V" (currently L used)
   double value = 0.0;                  // basis-dependent value
};

struct StagedColumnCoreSpec {
   std::string fluidName;     // "Brent" etc (for UI/reporting only)
   FluidThermoData fluidThermo;
   std::vector<double> feedComposition;
   int trays = 32;

   double feedRateKgph = 100000.0;
   int feedTray = 4;          // 1-based
   double feedTempK = 640.0;
   int maxIter = 100;
   double outerConvergenceTolerance = 1e-4;

   double topPressurePa = 150000.0;
   double dpPerTrayPa = 200.0;

   // Resolved thermo configuration from the feed stream's fluid package.
   // When set (thermoMethodId non-empty), this takes priority over eosMode/eosManual.
   thermo::ThermoConfig thermoConfig;

   // UI specs (legacy fallback when no fluid package is assigned)
   std::string eosMode = "auto";        // "auto" | "manual"
   std::string eosManual = "PRSV";      // "PR" | "PRSV" | "SRK"

   // Murphree
   double etaVTop = 0.75;
   double etaVMid = 0.65;
   double etaVBot = 0.55;
   bool enableEtaL = false;
   double etaLTop = 1.0;
   double etaLMid = 1.0;
   double etaLBot = 1.0;

   // Solver diagnostic verbosity
   LogLevel logLevel = LogLevel::Summary;

   // When true, suppress solver logging/noisy console output during solveColumn().
   bool suppressLogs = false;

   // Typed draw specs from UI/AppState
   std::vector<SolverDrawSpec> drawSpecs;
   // Optional labels keyed by 1-based tray number for UI display
   std::unordered_map<int, std::string> drawLabelsByTray1;
   // Optional attached side stripper configs driven from draw rows.
   std::vector<SimulationAttachedStripperSpec> attachedStripperSpecs;
};

struct MainColumnBoundarySpec {
   std::string condenserType = "total";
   std::string reboilerType = "partial";

   // "RefluxRatio" | "Duty" | "Temperature"
   std::string condenserSpec = "Temperature";
   // "BoilupRatio" | "Duty" | "Temperature"
   std::string reboilerSpec = "Duty";

   double refluxRatio = 3.0;
   double boilupRatio = 2.0;
   double qcKW = 25000.0;
   double qrKW = 30000.0;
   double topTsetK = 370.0;
   double bottomTsetK = 670.0;
};

struct MainColumnSolveSpec {
   StagedColumnCoreSpec core;
   MainColumnBoundarySpec boundary;

   // Backward-compatible aliases so existing tests/callers can still use the
   // original flat SolverInputs field names during the Phase 3 transition.
   std::string& fluidName;
   FluidThermoData& fluidThermo;
   std::vector<double>& feedComposition;
   int& trays;
   double& feedRateKgph;
   int& feedTray;
   double& feedTempK;
   int& maxIter;
   double& outerConvergenceTolerance;
   double& topPressurePa;
   double& dpPerTrayPa;
   thermo::ThermoConfig& thermoConfig;
   std::string& eosMode;
   std::string& eosManual;
   double& etaVTop;
   double& etaVMid;
   double& etaVBot;
   bool& enableEtaL;
   double& etaLTop;
   double& etaLMid;
   double& etaLBot;
   LogLevel& logLevel;
   bool& suppressLogs;
   std::vector<SolverDrawSpec>& drawSpecs;
   std::unordered_map<int, std::string>& drawLabelsByTray1;
   std::vector<SimulationAttachedStripperSpec>& attachedStripperSpecs;

   std::string& condenserType;
   std::string& reboilerType;
   std::string& condenserSpec;
   std::string& reboilerSpec;
   double& refluxRatio;
   double& boilupRatio;
   double& qcKW;
   double& qrKW;
   double& topTsetK;
   double& bottomTsetK;

   MainColumnSolveSpec()
      : fluidName(core.fluidName)
      , fluidThermo(core.fluidThermo)
      , feedComposition(core.feedComposition)
      , trays(core.trays)
      , feedRateKgph(core.feedRateKgph)
      , feedTray(core.feedTray)
      , feedTempK(core.feedTempK)
      , maxIter(core.maxIter)
      , outerConvergenceTolerance(core.outerConvergenceTolerance)
      , topPressurePa(core.topPressurePa)
      , dpPerTrayPa(core.dpPerTrayPa)
      , thermoConfig(core.thermoConfig)
      , eosMode(core.eosMode)
      , eosManual(core.eosManual)
      , etaVTop(core.etaVTop)
      , etaVMid(core.etaVMid)
      , etaVBot(core.etaVBot)
      , enableEtaL(core.enableEtaL)
      , etaLTop(core.etaLTop)
      , etaLMid(core.etaLMid)
      , etaLBot(core.etaLBot)
      , logLevel(core.logLevel)
      , suppressLogs(core.suppressLogs)
      , drawSpecs(core.drawSpecs)
      , drawLabelsByTray1(core.drawLabelsByTray1)
      , attachedStripperSpecs(core.attachedStripperSpecs)
      , condenserType(boundary.condenserType)
      , reboilerType(boundary.reboilerType)
      , condenserSpec(boundary.condenserSpec)
      , reboilerSpec(boundary.reboilerSpec)
      , refluxRatio(boundary.refluxRatio)
      , boilupRatio(boundary.boilupRatio)
      , qcKW(boundary.qcKW)
      , qrKW(boundary.qrKW)
      , topTsetK(boundary.topTsetK)
      , bottomTsetK(boundary.bottomTsetK)
   {}

   MainColumnSolveSpec(const MainColumnSolveSpec& other)
      : core(other.core)
      , boundary(other.boundary)
      , fluidName(core.fluidName)
      , fluidThermo(core.fluidThermo)
      , feedComposition(core.feedComposition)
      , trays(core.trays)
      , feedRateKgph(core.feedRateKgph)
      , feedTray(core.feedTray)
      , feedTempK(core.feedTempK)
      , maxIter(core.maxIter)
      , outerConvergenceTolerance(core.outerConvergenceTolerance)
      , topPressurePa(core.topPressurePa)
      , dpPerTrayPa(core.dpPerTrayPa)
      , thermoConfig(core.thermoConfig)
      , eosMode(core.eosMode)
      , eosManual(core.eosManual)
      , etaVTop(core.etaVTop)
      , etaVMid(core.etaVMid)
      , etaVBot(core.etaVBot)
      , enableEtaL(core.enableEtaL)
      , etaLTop(core.etaLTop)
      , etaLMid(core.etaLMid)
      , etaLBot(core.etaLBot)
      , logLevel(core.logLevel)
      , suppressLogs(core.suppressLogs)
      , drawSpecs(core.drawSpecs)
      , drawLabelsByTray1(core.drawLabelsByTray1)
      , attachedStripperSpecs(core.attachedStripperSpecs)
      , condenserType(boundary.condenserType)
      , reboilerType(boundary.reboilerType)
      , condenserSpec(boundary.condenserSpec)
      , reboilerSpec(boundary.reboilerSpec)
      , refluxRatio(boundary.refluxRatio)
      , boilupRatio(boundary.boilupRatio)
      , qcKW(boundary.qcKW)
      , qrKW(boundary.qrKW)
      , topTsetK(boundary.topTsetK)
      , bottomTsetK(boundary.bottomTsetK)
   {}

   MainColumnSolveSpec(MainColumnSolveSpec&& other) noexcept
      : core(std::move(other.core))
      , boundary(std::move(other.boundary))
      , fluidName(core.fluidName)
      , fluidThermo(core.fluidThermo)
      , feedComposition(core.feedComposition)
      , trays(core.trays)
      , feedRateKgph(core.feedRateKgph)
      , feedTray(core.feedTray)
      , feedTempK(core.feedTempK)
      , maxIter(core.maxIter)
      , outerConvergenceTolerance(core.outerConvergenceTolerance)
      , topPressurePa(core.topPressurePa)
      , dpPerTrayPa(core.dpPerTrayPa)
      , thermoConfig(core.thermoConfig)
      , eosMode(core.eosMode)
      , eosManual(core.eosManual)
      , etaVTop(core.etaVTop)
      , etaVMid(core.etaVMid)
      , etaVBot(core.etaVBot)
      , enableEtaL(core.enableEtaL)
      , etaLTop(core.etaLTop)
      , etaLMid(core.etaLMid)
      , etaLBot(core.etaLBot)
      , logLevel(core.logLevel)
      , suppressLogs(core.suppressLogs)
      , drawSpecs(core.drawSpecs)
      , drawLabelsByTray1(core.drawLabelsByTray1)
      , attachedStripperSpecs(core.attachedStripperSpecs)
      , condenserType(boundary.condenserType)
      , reboilerType(boundary.reboilerType)
      , condenserSpec(boundary.condenserSpec)
      , reboilerSpec(boundary.reboilerSpec)
      , refluxRatio(boundary.refluxRatio)
      , boilupRatio(boundary.boilupRatio)
      , qcKW(boundary.qcKW)
      , qrKW(boundary.qrKW)
      , topTsetK(boundary.topTsetK)
      , bottomTsetK(boundary.bottomTsetK)
   {}

   MainColumnSolveSpec& operator=(const MainColumnSolveSpec& other) {
      if (this != &other) {
         core = other.core;
         boundary = other.boundary;
      }
      return *this;
   }

   MainColumnSolveSpec& operator=(MainColumnSolveSpec&& other) noexcept {
      if (this != &other) {
         core = std::move(other.core);
         boundary = std::move(other.boundary);
      }
      return *this;
   }
};

using SolverInputs = MainColumnSolveSpec;

struct SolverTrayOut {
   double tempK = 0.0;
   double vFrac = 0.0;
   double pressurePa = 0.0;

   double L_kgph = 0.0;
   double V_kgph = 0.0;

   double drawFlow = 0.0; // kgph (placeholder)
   std::vector<double> xLiq;  // liquid mole fractions
   std::vector<double> yVap;  // vapor mole fractions
};

struct SolverOutputs {
   std::vector<SolverTrayOut> trays;
   std::vector<StreamSnapshot> streams;
   std::vector<SimulationAttachedStripperSummary> attachedStrippers;
   std::string summary;
   std::string runResultsText;

   std::vector<Diagnostic> diagnostics;

   double Tcond_K = NAN;
   double Treb_K = NAN;

   std::string condenserType = "total";

   EnergySpecSummary energy;
   std::vector<std::string> componentNames;
};

std::string serializeSolverInputsToJson(
   const SolverInputs& in,
   bool pretty = true);

bool writeSolverInputsJsonFile(
   const SolverInputs& in,
   const std::string& filePath,
   std::string* errorMessage = nullptr,
   bool pretty = true);

SolverOutputs solveColumn(
   const SolverInputs& in,
   const std::function<void(const std::string&)>& onLog = {},
   const std::function<void(const ProgressEvent&)>& onProgress = {});
