#pragma once

#include <vector>
#include <string>

#include "../pseudocomponents/componentData.hpp"

// SRK EOS mixture container used by SRK.cpp.
// NOTE: we store pointers (not references) so the type is default-constructible and assignable.
struct SRKMixture {
  std::string eos = "SRK";

  double P = 0.0;
  double T = 0.0;

  const std::vector<double>* x = nullptr;                 // composition (mole fractions)
  const std::vector<Component>* comps = nullptr;          // component properties
  const std::vector<std::vector<double>>* kij = nullptr;  // optional binary interaction matrix

  std::vector<double> ai;
  std::vector<double> bi;

  double amix = 0.0;
  double bmix = 0.0;

  double A = 0.0;
  double B = 0.0;

  std::vector<double> Z_roots; // real roots (sorted ascending)
};

struct SolveSRKResult {
	double ZL = 0.0;
	double ZV = 0.0;
	std::vector<double> phiL;
	std::vector<double> phiV;
};

SRKMixture solveSRK_mixture(
  double P,
  double T,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij = nullptr
);

std::vector<double> computePhi_SRK(const SRKMixture& mix, double Z);

SolveSRKResult solveSRK(
  double P,
  double T,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij = nullptr
);
