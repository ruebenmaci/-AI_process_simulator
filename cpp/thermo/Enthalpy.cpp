#include <cmath>
#include <algorithm>
#include <stdexcept>
#include <sstream>
#include <iostream>

#include "Enthalpy.hpp"
#include "../thermo/EOSK.hpp"

// ------------------------------------------------------------
// Rough ideal-gas Cp (J/mol/K)
// Temperature-dependent, matching fixed Enthalpy.js
// ------------------------------------------------------------
static double CpIG(const Component& comp, double T)
{
   const double MW = comp.MW > 0 ? comp.MW : 200.0;
   const double T_K = std::max(200.0, std::min(900.0, T));
   const double T_ref = 298.15;
   const double base = 20.0 + std::min(85.0, 0.08 * std::max(0.0, MW - 16.0));
   const double alpha = 7e-4; // K^-1
   return base * (1.0 + alpha * (T_K - T_ref)); // J/mol/K
}

// ------------------------------------------------------------
// Average molecular weight (kg/mol)
// ------------------------------------------------------------
static double avgMW(
   const std::vector<double>& x,
   const std::vector<Component>& comps)
{
   double M = 0.0;

   for (size_t i = 0; i < x.size(); ++i) {
      double mw = comps[i].MW > 0 ? comps[i].MW : 200.0;
      M += x[i] * mw;
   }

   return std::max(1e-12, M) / 1000.0; // kg/mol
}

// ------------------------------------------------------------
// Ideal-gas sensible enthalpy (J/mol)
// Integrated from T=0 K with temperature-dependent Cp.
// Integral of base*(1 + alpha*(T' - T_pivot)) dT' from 0 to T
//   = base * T * (1 + alpha*(T/2 - T_pivot))
// Matches fixed Enthalpy.js hIG_molar().
// ------------------------------------------------------------
static double hIG_molar(
   const std::vector<double>& x,
   double T,
   const std::vector<Component>& comps)
{
   const double T_K = std::max(200.0, std::min(900.0, T));
   const double alpha = 7e-4;    // K^-1
   const double T_pivot = 298.15;  // K
   double H = 0.0;

   for (size_t i = 0; i < x.size(); ++i) {
      const double MW = comps[i].MW > 0 ? comps[i].MW : 200.0;
      const double base = 20.0 + std::min(85.0, 0.08 * std::max(0.0, MW - 16.0));
      H += x[i] * base * T_K * (1.0 + alpha * (0.5 * T_K - T_pivot));
   }

   return H; // J/mol
}

// ------------------------------------------------------------
// Convert J/mol → kJ/kg
// ------------------------------------------------------------
static double to_kJ_per_kg(double H_J_per_mol, double MW_kg_per_mol)
{
   return H_J_per_mol / MW_kg_per_mol / 1000.0;
}

// ------------------------------------------------------------
// Phase enthalpy (kJ/kg)
// ------------------------------------------------------------
static double hPhase(
   const std::vector<double>& x,
   double T,
   double P,
   int trayIndex,
   const std::vector<Component>& comps,
   bool vapor,
   const std::function<void(const std::string&)>& log
)
{
   const auto& compsRef = comps;
   // EOS departure enthalpy (J/mol)
   auto eos = solvePRSV_mixture(P, T, x, trayIndex, comps, nullptr, log);

   const double Hdep = vapor ? eos.hdepV : eos.hdepL;

   if (log) {
      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(6);
      os << "[HDEP] T=" << T << " P=" << P
         << " hdepL=" << eos.hdepL
         << " hdepV=" << eos.hdepV
         << " diff=" << (eos.hdepV - eos.hdepL);
      log(os.str());
   }

   const double Hig = hIG_molar(x, T, compsRef);
   const double Hm = Hig + Hdep;
   const double MWb = avgMW(x, compsRef);
   return to_kJ_per_kg(Hm, MWb);
}

// ------------------------------------------------------------
// Public API
// ------------------------------------------------------------
double hVap(
   const std::vector<double>& y,
   double T,
   int trayIndex,
   const std::vector<Component>& comps,
   double P,
   const std::function<void(const std::string&)>& log)
{
   return hPhase(y, T, P, trayIndex, comps, true, log);
}

double hLiq(
   const std::vector<double>& x,
   double T,
   int trayIndex,
   const std::vector<Component>& comps,
   double P,
   const std::function<void(const std::string&)>& log)
{
   return hPhase(x, T, P, trayIndex, comps, false, log);
}