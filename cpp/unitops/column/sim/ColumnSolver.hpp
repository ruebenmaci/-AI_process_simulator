#pragma once

#include <string>
#include <vector>
#include <functional>
#include <unordered_map>
#include <cmath>

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

struct SolverInputs {
   std::string fluidName;     // "Brent" etc (for UI/reporting only)
   FluidThermoData fluidThermo;
   std::vector<double> feedComposition;
   int trays = 32;

   double feedRateKgph = 100000.0;
   int feedTray = 4;          // 1-based
   double feedTempK = 640.0;

   double topPressurePa = 150000.0;
   double dpPerTrayPa = 200.0;

   // Resolved thermo configuration from the feed stream's fluid package.
   // When set (thermoMethodId non-empty), this takes priority over eosMode/eosManual.
   thermo::ThermoConfig thermoConfig;

   // UI specs (legacy fallback when no fluid package is assigned)
   std::string eosMode = "auto";        // "auto" | "manual"
   std::string eosManual = "PRSV";      // "PR" | "PRSV" | "SRK"

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
};

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
