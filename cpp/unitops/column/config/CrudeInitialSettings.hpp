#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <optional>

// NOTE: All temperatures are Kelvin in this module.

struct MurphreeEff {
  double etaV_top = 0.75;
  double etaV_mid = 0.65;
  double etaV_bot = 0.55;
  double etaL_top = 1.0;
  double etaL_mid = 1.0;
  double etaL_bot = 1.0;
};

struct CrudeInitialSettings {
  // Column inputs
  double feedRate_kgph = 100000.0;
  int feedTray = 3;            // 1 = bottom/reboiler, N = top/condenser
  double Tfeed_K = 0.0;
  double Ttop_K = 0.0;
  double Tbottom_K = 0.0;
  double Ptop_Pa = 150000.0;
  double dP_perTray_Pa = 200.0;

  // Boundary specs
  std::string condenserSpec = "temperature"; // "temperature" | "duty"
  std::string reboilerSpec  = "duty";        // "duty" | "temperature" | "boilup"

  // Duties (kW)
  double Qc_kW = -6000.0;
  double Qr_kW =  6000.0;

  // Ratios
  double refluxRatio = 2.0;
  double reboilRatio = 0.06;

  MurphreeEff murphree;

  // Default product split (fraction of feed), keyed by 0-based tray index (0=bottom).
  std::unordered_map<int, double> drawSpecsByTrayIndex;
};

// Fixed draw tray list (0-based) used to build default editable draw rows.
// Keys are 0-based tray indices: 0 = bottom tray, (N-1) = top tray.
const std::vector<int>& drawTrays32();

// Default draw names keyed by 1-based tray number (1 = bottom, 32 = top)
const std::unordered_map<int, std::string>& defaultDrawNamesByTray32();

// All crude initial settings map
const std::unordered_map<std::string, CrudeInitialSettings>& crudeInitialSettings();

// Fetch settings for a crude name (fallback to Brent)
CrudeInitialSettings getCrudeInitialSettings(const std::string& crudeName);

// Crude-specific recommended feed tray (fallback heuristic if missing)
int getRecommendedFeedTray(const std::string& crudeName, int numTrays = 32);

// Returns all crude names available in the registry.
std::vector<std::string> getAvailableCrudeNames();
