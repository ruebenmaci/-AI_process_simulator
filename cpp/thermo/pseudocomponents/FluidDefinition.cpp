#include "FluidDefinition.hpp"

#include "loaders.hpp"

FluidDefinition getFluidDefinition(const std::string& name)
{
  const CrudeSet crude = getCrudeSet(name);

  FluidDefinition fluid;
  fluid.name = crude.name;
  fluid.thermo.components = crude.components;
  fluid.thermo.kij = crude.kij;
  fluid.thermo.hasZDefault = crude.hasZDefault;
  fluid.thermo.zDefault = crude.zDefault;
  fluid.columnDefaults = getCrudeInitialSettings(name);
  return fluid;
}

std::vector<std::string> listFluidDefinitions()
{
  return listCrudes();
}
