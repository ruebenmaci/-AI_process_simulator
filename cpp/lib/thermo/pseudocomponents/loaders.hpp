#pragma once
#include <string>
#include <vector>
#include <unordered_map>

#include "componentData.hpp"

struct CrudeSet {
  std::string name;
  std::vector<Component> components;       // SI-normalized
  std::vector<std::vector<double>> kij;    // n×n
  bool hasZDefault = false;
  std::vector<double> zDefault;            // length n when present
};

CrudeSet getCrudeSet(const std::string& name);
std::vector<std::string> listCrudes();
