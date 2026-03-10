#pragma once
// cpp/lib/thermo/EOSK.hpp
//
// EOS-based K-values with per-tray EOS selection.
// Ported from EOSK.js.
//
// Dependencies (expected in your project):
//   cpp/lib/thermo/eos/PR.hpp
//   cpp/lib/thermo/eos/PRSV.hpp
//   cpp/lib/thermo/eos/SRK.hpp
//
// Notes:
// - Uses φ–φ K-values with iterative update using phase compositions (x/y).
// - Includes optional Murphree-style efficiency on K-values:
//     K_eff = 1 + eta * (K_eq - 1)
//
// Units:
//   P [Pa], T [K], compositions are mole fractions.

#include <string>
#include <vector>
#include <optional>
#include <limits>
#include <functional>
#include "PR.hpp"
#include "PRSV.hpp"
#include "SRK.hpp"

struct EosKResult {
  // K-values used for RR/flash. If singlePhase==true, K may still be provided
  // (forced two-phase) to allow RR to proceed.
  std::vector<double> K;
  double Z_liq = std::numeric_limits<double>::quiet_NaN();
  double Z_vap = std::numeric_limits<double>::quiet_NaN();
  std::string eos; // "PRSV" | "PR" | "SRK"
  bool singlePhase = false;
  std::string phase;  // "L" or "V" when singlePhase==true
  std::string reason; // diagnostic tag (e.g., "SINGLEPHASE_L", "FORCED_TWOPHASE")
  double Z = std::numeric_limits<double>::quiet_NaN();
};

std::string getEOSForTray(
  int trayIndex,
  int trays,
  const std::string& crudeName = "",
  const std::string& eosMode = "auto",
  const std::string& eosManual = "PRSV"
);

void setEosKLogging(bool on);

// Flush/clear EOSK log coalescing state.
//
// EOSK coalesces identical consecutive log lines (e.g. repeated [EOSK_SEED] lines)
// into a single summary like "... (repeated N times)" when the next *different*
// line arrives.
//
// If you log tray boundaries outside EOSK (e.g. in AppState), call this right
// before you emit trayStart/trayEnd so any pending "(repeated ...)" summary is
// printed at the correct tray boundary rather than being delayed into the next tray.
void flushEOSKCoalescer(const std::function<void(const std::string&)>& logger = {});

EosKResult eosK(
  double P,
  double T,
  const std::vector<double>& z,
  const std::vector<Component>& comps,
  int trayIndex = 0,
  int trays = 32,
  const std::string& crudeName = "",
  const std::vector<std::vector<double>>* kij = nullptr,
  bool log = false,
  double murphreeEtaV = 0,
  const std::string& eosMode = "auto",
  const std::string& eosManual = "PRSV",
  const std::function<void(const std::string&)>& logger = {}
);

// Convenience wrappers (kept for parity with EOSK.js)
PRSVResult solvePRSV_mixture(
  double P, double T,
  const std::vector<double>& x,
  int trayIndex,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij = nullptr,
  const std::function<void(const std::string&)>& log = nullptr
);

PRResult solvePR_mixture(
  double P, double T,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij = nullptr
);

// SRK solver API (types + functions) is declared in eos/SRK.hpp.
// Do not redeclare it here: different SRK implementations may return different
// result structs (e.g., SolveSRKResult vs SRKMixture), and redeclaring causes
// build breaks and/or ODR issues.
