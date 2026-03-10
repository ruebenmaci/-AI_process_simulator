#pragma once

#include <vector>
#include <string>
#include <unordered_map>
#include <cmath>
#include <functional>
#include <limits>

struct RRDiag {
  bool enable = false;     // mirrors diag.enable in JS
  bool force = false;      // mirrors diag.force
  bool returnObject = false;
  int tray = -1;
  double T = std::numeric_limits<double>::quiet_NaN();
  double P = std::numeric_limits<double>::quiet_NaN();
};

struct RRResult {
  double V = 0.5;
  std::string status;   // "twoPhase", "singlePhase", "fail"
  std::string reason;   // e.g. "CONVERGED", "F0F1_POS", ...
  int iters = 0;
  double f0 = std::numeric_limits<double>::quiet_NaN();
  double f1 = std::numeric_limits<double>::quiet_NaN();
  double f0n = std::numeric_limits<double>::quiet_NaN();
  double f1n = std::numeric_limits<double>::quiet_NaN();
  std::string phase;    // "L" or "V" when single-phase is inferred
};

// Port of Flash.js:
// - rachfordRice(z, K, diag)  -> returns either V (number) or RRResult (object)
// In C++ we always compute meta; caller can ignore it.
RRResult rachfordRice(const std::vector<double>& z,
                      const std::vector<double>& K,
                      const RRDiag* diag = nullptr,
                      const std::function<void(const std::string&)>& log = nullptr);

std::pair<std::vector<double>, std::vector<double>> phaseCompositions(const std::vector<double>& z,
                  const std::vector<double>& K, double V);

std::vector<double> forceTwoPhaseK(const std::vector<double>& z,
               const std::vector<double>& K);
