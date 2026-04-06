#pragma once

#include <functional>
#include <vector>

#include "../cpp/thermo/pseudocomponents/componentData.hpp"
#include "ThermoConfig.hpp"

// Vapor enthalpy (kJ/kg)
double hVap(
   const std::vector<double>& y,
   double T,
   int trayIndex = -1,
   const std::vector<Component>& comps = emptyComponents(),
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);

double hVapWithConfig(
   const std::vector<double>& y,
   double T,
   const thermo::ThermoConfig& thermoConfig,
   int trayIndex = -1,
   const std::vector<Component>& comps = emptyComponents(),
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);

// Liquid enthalpy (kJ/kg)
double hLiq(
   const std::vector<double>& x,
   double T,
   int trayIndex = -1,
   const std::vector<Component>& comps = emptyComponents(),
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);

double hLiqWithConfig(
   const std::vector<double>& x,
   double T,
   const thermo::ThermoConfig& thermoConfig,
   int trayIndex = -1,
   const std::vector<Component>& comps = emptyComponents(),
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);
