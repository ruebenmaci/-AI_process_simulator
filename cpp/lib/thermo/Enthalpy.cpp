#include <cmath>
#include <algorithm>
#include <stdexcept>
#include <sstream>
#include <iostream>

#include "Enthalpy.hpp"
#include "../thermo/EOSK.hpp"

// ------------------------------------------------------------
// Rough ideal-gas Cp (J/mol/K)
// Same logic as Enthalpy.js
// ------------------------------------------------------------
static double CpIG(const Component& comp, double T)
{
   const double MW = comp.MW > 0 ? comp.MW : 200.0;

   const double base =
      20.0 + 0.05 * std::max(0.0, std::min(400.0, T - 300.0) / 100.0);

   const double size =
      std::min(60.0, 0.06 * std::max(0.0, MW - 20.0));

   return base + size; // J/mol/K
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
// Tref ≈ 0 K (same simplification as JS)
// ------------------------------------------------------------
static double hIG_molar(
   const std::vector<double>& x,
   double T,
   const std::vector<Component>& comps)
{
   double H = 0.0;

   for (size_t i = 0; i < x.size(); ++i) {
      H += x[i] * CpIG(comps[i], T) * T;
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
