#pragma once
// thermo/Entropy.hpp

#include <vector>
#include "../../thermo/pseudocomponents/componentData.hpp"

// ── Per-phase mixture entropy [kJ/(kg·K)] ───────────────────────────────────
double sLiq(const std::vector<double>& x, double T, int trayIndex,
   const std::vector<Component>& comps, double P);

double sVap(const std::vector<double>& y, double T, int trayIndex,
   const std::vector<Component>& comps, double P);

// ── Component Cp helpers ─────────────────────────────────────────────────────
// These were previously in an anonymous namespace in Entropy.cpp.
// They are promoted here so that StreamPropertyCalcs.cpp can call them without
// duplicating the correlation.  The implementations remain in Entropy.cpp.
//
// Returns kJ/(kg·K).
double cpLiqKJperKgK(const Component& c, double T);
double cpVapKJperKgK(const Component& c, double T);