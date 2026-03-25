#pragma once

#include <vector>
#include <string>
#include <cmath>

#include "../pseudocomponents/componentData.hpp"

// Peng–Robinson EOS (classic PR alpha), vdW-1 mixing with optional kij,
// fugacity coefficients (phi_i), cubic Z roots, and PR departure enthalpy.
// Units: T[K], P[Pa], Tc[K], Pc[Pa], omega[-]. R = 8.314462618 J/mol/K.

struct PRResult {
  bool singlePhase = false;
  double Z = NAN;   // if singlePhase, this is ZL=ZV=Z
  double ZL = NAN;
  double ZV = NAN;

  std::vector<double> phiL;
  std::vector<double> phiV;

  // Departure enthalpies (J/mol)
  double hdepL = 0.0;
  double hdepV = 0.0;

  // Per-component PR parameters at T
  std::vector<double> a_i;
  std::vector<double> b_i;

  // Mixture params
  double a_mix = 0.0;
  double b_mix = 0.0;
};

// Main API (mirrors solvePR({P,T,x,comps,kij}) from JS)
PRResult solvePR(
    double P,
    double T,
    const std::vector<double>& x,
    const std::vector<Component>& comps,
    const std::vector<std::vector<double>>* kij = nullptr);
