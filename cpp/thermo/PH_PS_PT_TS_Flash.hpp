#pragma once

#include <vector>
#include <string>
#include <functional>
#include <limits>

#include "../../thermo/pseudocomponents/componentData.hpp"
#include "../../utils/LogLevel.hpp"
#include "ThermoConfig.hpp"

struct FlashPHInput {
   double Htarget = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> z;
   double P = std::numeric_limits<double>::quiet_NaN();
   double Tseed = std::numeric_limits<double>::quiet_NaN();
   const std::vector<Component>* components = nullptr;
   int trayIndex = -1;
   int trays = 32;
   std::string crudeName;
   std::string eosMode = "auto";
   std::string eosManual; // e.g. "PRSV" — used as fallback when thermoConfig is empty
   thermo::ThermoConfig thermoConfig; // preferred: drives EOS selection when thermoMethodId is set
   const std::vector<std::vector<double>>* kij = nullptr;
   std::function<void(const std::string&)> log;
   LogLevel logLevel = LogLevel::Summary;
   bool forceTwoPhase = false;
   bool disableSinglePhaseShortCircuit = false;
   double murphreeEtaV = std::numeric_limits<double>::quiet_NaN();
};

struct FlashPHResult {
   double T = std::numeric_limits<double>::quiet_NaN();
   double V = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> x;
   std::vector<double> y;

   // K-value range for the last EOS/K-value evaluation (debug / tray profile columns)
   double Kmin = std::numeric_limits<double>::quiet_NaN();
   double Kmax = std::numeric_limits<double>::quiet_NaN();

   std::string status; // "ok", "no-bracket-soft", "bad-target", ...
   double dH = std::numeric_limits<double>::quiet_NaN();
   double Hcalc = std::numeric_limits<double>::quiet_NaN();
   double Htarget = std::numeric_limits<double>::quiet_NaN();
   double Scalc = std::numeric_limits<double>::quiet_NaN();

   bool singlePhase = false;
   std::string phase; // "L"/"V" when singlePhase
};

FlashPHResult flashPH(const FlashPHInput& in);

struct FlashPSInput {
   double Starget = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> z;
   double P = std::numeric_limits<double>::quiet_NaN();
   double Tseed = std::numeric_limits<double>::quiet_NaN();
   const std::vector<Component>* components = nullptr;
   int trayIndex = -1;
   int trays = 32;
   std::string crudeName;
   std::string eosMode = "auto";
   std::string eosManual;
   thermo::ThermoConfig thermoConfig; // preferred: drives EOS selection when thermoMethodId is set
   const std::vector<std::vector<double>>* kij = nullptr;
   std::function<void(const std::string&)> log;
   LogLevel logLevel = LogLevel::Summary;
   double murphreeEtaV = std::numeric_limits<double>::quiet_NaN();
};

struct FlashPSResult {
   double T = std::numeric_limits<double>::quiet_NaN();
   double V = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> x;
   std::vector<double> y;
   double Hcalc = std::numeric_limits<double>::quiet_NaN();
   double Scalc = std::numeric_limits<double>::quiet_NaN();
   double Starget = std::numeric_limits<double>::quiet_NaN();
   double dS = std::numeric_limits<double>::quiet_NaN();
   std::string status;
};

FlashPSResult flashPS(const FlashPSInput& in);


struct FlashTSInput {
   double Starget = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> z;
   double T = std::numeric_limits<double>::quiet_NaN();
   double Pseed = std::numeric_limits<double>::quiet_NaN();
   const std::vector<Component>* components = nullptr;
   int trayIndex = -1;
   int trays = 32;
   std::string crudeName;
   std::string eosMode = "auto";
   std::string eosManual;
   thermo::ThermoConfig thermoConfig; // preferred: drives EOS selection when thermoMethodId is set
   const std::vector<std::vector<double>>* kij = nullptr;
   std::function<void(const std::string&)> log;
   LogLevel logLevel = LogLevel::Summary;
   double murphreeEtaV = std::numeric_limits<double>::quiet_NaN();
};

struct FlashTSResult {
   double P = std::numeric_limits<double>::quiet_NaN();
   double T = std::numeric_limits<double>::quiet_NaN();
   double V = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> x;
   std::vector<double> y;
   double Hcalc = std::numeric_limits<double>::quiet_NaN();
   double Scalc = std::numeric_limits<double>::quiet_NaN();
   double Starget = std::numeric_limits<double>::quiet_NaN();
   double dS = std::numeric_limits<double>::quiet_NaN();
   std::string status;
};

FlashTSResult flashTS(const FlashTSInput& in);

// Saturated helper port (reboiler/condensers)
struct FlashPHSatInput {
   std::vector<double> z;
   double P = 101325.0;
   double Htarget = std::numeric_limits<double>::quiet_NaN();
   const std::vector<Component>* components = nullptr;
   std::string eos = "PRSV";
   int trayIndex = -1;
   double Tseed = std::numeric_limits<double>::quiet_NaN();
   double Tmax = 1400.0;
   double Tmin = 250.0;
   int maxIter = 80;
   std::function<void(const std::string&)> log;
   LogLevel logLevel = LogLevel::Summary;
};

struct FlashPHSatResult {
   double T = std::numeric_limits<double>::quiet_NaN();
   double V = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> x;
   std::vector<double> y;
   std::string singlePhase; // "L"/"V"/"" (null in JS)
   std::string reason;

   // envelope diagnostics
   double Tbub = std::numeric_limits<double>::quiet_NaN();
   double Tdew = std::numeric_limits<double>::quiet_NaN();
   double Hbub = std::numeric_limits<double>::quiet_NaN();
   double Hdew = std::numeric_limits<double>::quiet_NaN();
};

FlashPHSatResult flashPH_saturated(const FlashPHSatInput& in);

struct FlashPTResult {
   double H = NAN;
   double S = NAN;
   double V = NAN;
   std::vector<double> x, y, K;
   bool singlePhase = false;
   std::string phase; // "L" or "V" when singlePhase
};

FlashPTResult flashPT(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>* components = nullptr,
   int trayIndex = -1,
   int trays = 32,
   const std::string& crudeHint = "",
   const std::vector<std::vector<double>>* kij = nullptr,
   double murphreeEtaV = 1.0,
   const std::string& eosMode = "",
   const std::string& eosManual = "",
   const std::function<void(const std::string&)>& log = nullptr
);

// ThermoConfig-aware overload — resolves EOS from config, delegates to the above.
FlashPTResult flashPT(
   double P,
   double T,
   const std::vector<double>& z,
   const thermo::ThermoConfig& thermoConfig,
   const std::vector<Component>* components = nullptr,
   const std::vector<std::vector<double>>* kij = nullptr,
   double murphreeEtaV = 1.0,
   const std::function<void(const std::string&)>& log = nullptr
);

struct RRAndComp {
   double dH = 0.0;
   double V = 0.5;
   double Kmin = std::numeric_limits<double>::quiet_NaN();
   double Kmax = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> x;
   std::vector<double> y;
   bool singlePhase = false;
   std::string phase;

   // meta (optional)
   std::string rrStatus;
   std::string rrReason;
   double f0 = std::numeric_limits<double>::quiet_NaN();
   double f1 = std::numeric_limits<double>::quiet_NaN();
   double f0n = std::numeric_limits<double>::quiet_NaN();
   double f1n = std::numeric_limits<double>::quiet_NaN();
   int iters = 0;
};