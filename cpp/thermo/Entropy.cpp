// thermo/Entropy.cpp
//
// Change from original: cpLiqKJperKgK and cpVapKJperKgK are no longer in the
// anonymous namespace — they are now public functions declared in Entropy.hpp
// so that StreamPropertyCalcs.cpp can call them directly.  All other logic is
// unchanged.

#include "Entropy.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

namespace {

   constexpr double R_kJ_per_kmolK = 8.31446261815324;
   constexpr double Pref_Pa = 101325.0;

   double safeFrac(double v) { return std::isfinite(v) && v > 1e-16 ? v : 1e-16; }

   double mixIdealEntropy(const std::vector<double>& z, double T,
      const std::vector<Component>& comps, double P, bool vapor)
   {
      if (!std::isfinite(T) || T <= 1.0)
         return std::numeric_limits<double>::quiet_NaN();

      const double pTerm = vapor && std::isfinite(P) && P > 0.0
         ? -(R_kJ_per_kmolK / 200.0) * std::log(P / Pref_Pa)
         : 0.0;

      double s = 0.0;
      for (std::size_t i = 0; i < z.size() && i < comps.size(); ++i) {
         const double zi = z[i];
         if (!(zi > 0.0) || !std::isfinite(zi)) continue;
         const auto& c = comps[i];
         const double cp = vapor ? cpVapKJperKgK(c, T) : cpLiqKJperKgK(c, T);
         s += zi * cp * std::log(T / 298.15);
         s += zi * pTerm;
         s -= zi * (R_kJ_per_kmolK / 200.0) * std::log(safeFrac(zi));
      }
      return s;
   }

} // namespace

// ── Cp helpers (public — declared in Entropy.hpp) ────────────────────────────

double cpLiqKJperKgK(const Component& c, double T)
{
   const double mw = (std::isfinite(c.MW) && c.MW > 1e-9) ? c.MW : 200.0;
   const double tb = (std::isfinite(c.Tb) && c.Tb > 1.0) ? c.Tb : 500.0;
   const double base = 1.6
      + 0.0015 * std::clamp(T - 298.15, -200.0, 800.0)
      + 0.0002 * (tb - 400.0);
   return std::clamp(base * (200.0 / mw), 0.8, 4.0);
}

double cpVapKJperKgK(const Component& c, double T)
{
   const double mw = (std::isfinite(c.MW) && c.MW > 1e-9) ? c.MW : 200.0;
   const double base = 1.8 + 0.0025 * std::clamp(T - 298.15, -200.0, 1200.0);
   return std::clamp(base * (180.0 / mw), 0.8, 5.0);
}

// ── Public entropy API ───────────────────────────────────────────────────────

double sLiq(const std::vector<double>& x, double T, int /*trayIndex*/,
   const std::vector<Component>& comps, double P)
{
   return mixIdealEntropy(x, T, comps, P, false);
}

double sVap(const std::vector<double>& y, double T, int /*trayIndex*/,
   const std::vector<Component>& comps, double P)
{
   return mixIdealEntropy(y, T, comps, P, true);
}