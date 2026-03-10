#pragma once

#include <functional>
#include <vector>

#include "../cpp/lib/thermo/pseudocomponents/componentData.hpp"

// Vapor enthalpy (kJ/kg)
double hVap(
   const std::vector<double>& y,
   double T,
   int trayIndex,
   const std::vector<Component>& comps,
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);

// Liquid enthalpy (kJ/kg)
double hLiq(
   const std::vector<double>& x,
   double T,
   int trayIndex,
   const std::vector<Component>& comps,
   double P = 101325.0,
   const std::function<void(const std::string&)>& log = nullptr
);
