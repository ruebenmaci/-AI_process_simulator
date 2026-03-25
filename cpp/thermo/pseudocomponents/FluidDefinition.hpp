#pragma once

#include <string>
#include <vector>

#include "componentData.hpp"
#include "unitops/column/config/CrudeInitialSettings.hpp"

struct FluidThermoData {
  std::vector<Component> components;       // SI-normalized
  std::vector<std::vector<double>> kij;    // n×n
  bool hasZDefault = false;
  std::vector<double> zDefault;            // length n when present
};

struct FluidDefinition {
  std::string name;
  FluidThermoData thermo;
  CrudeInitialSettings columnDefaults;
};

FluidDefinition getFluidDefinition(const std::string& name);
std::vector<std::string> listFluidDefinitions();
