#include <algorithm>
#include <cmath>
#include <limits>

#include <functional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <mutex>
#include "PRSV.hpp"

#include <iomanip>
#include <iostream>

// ---- PRSV log coalescer -----------------------------------------------------
// Same motivation as EOSK: repeated [PRSV_DIAG] or related lines can be produced
// many times per tray during PH iterations. If tray boundaries are logged outside
// PRSV (in AppState), summaries can otherwise be delayed into the next tray.

namespace {
   struct PRSVCoalescerState {
     std::string last;
     int repeatCount = 0;
   };

   static thread_local PRSVCoalescerState g_prsvCoalescer;

   static inline void prsvEmitCoalesced(const std::function<void(const std::string&)>& log,
                                        const std::string& s)
   {
     // PRSV warnings should never be hidden.
     const bool critical = (s.rfind("[PRSV_WARN]", 0) == 0);

     if (!critical && s == g_prsvCoalescer.last) {
       g_prsvCoalescer.repeatCount++;
       return;
     }

     if (!g_prsvCoalescer.last.empty() && g_prsvCoalescer.repeatCount > 0) {
       const std::string summary =
         g_prsvCoalescer.last + "   (repeated " + std::to_string(g_prsvCoalescer.repeatCount) + " times)";
       if (log)
          log(summary);
       g_prsvCoalescer.repeatCount = 0;
     }

     if (log)
        log(s);
     g_prsvCoalescer.last = s;
   }
} // namespace

void flushPRSVCoalescer(const std::function<void(const std::string&)>& log)
{
  if (!g_prsvCoalescer.last.empty() && g_prsvCoalescer.repeatCount > 0) {
    const std::string summary =
      g_prsvCoalescer.last + "   (repeated " + std::to_string(g_prsvCoalescer.repeatCount) + " times)";
    log(summary);
  }
  g_prsvCoalescer.last.clear();
  g_prsvCoalescer.repeatCount = 0;
}

// Gas constant used throughout the thermo backend (J/mol/K)
static constexpr double SQRT2 = 1.4142135623730950488;

// ------------------------------------------------------------
// PRSV alpha
// ------------------------------------------------------------
double kappaPRSV(double omega) {
   double w = std::clamp(omega, -0.15, 1.2);
   return 0.378893
      + 1.4897153 * w
      - 0.17131848 * w * w
      + 0.0196554 * w * w * w;
}

double alphaPRSV(double T, double Tc, double omega) {
   double Tr = std::max(1e-6, T / Tc);
   double k = kappaPRSV(omega);
   double g = 1.0 + k * (1.0 - std::sqrt(Tr));
   return g * g;
}

// ------------------------------------------------------------
// Cubic PR EOS
// ------------------------------------------------------------
static std::vector<double> solveCubicPR(double A, double B) {
   // Z^3 - (1-B)Z^2 + (A - 3B^2 - 2B)Z - (AB - B^2 - B^3) = 0

   double c2 = -(1.0 - B);
   double c1 = A - 3.0 * B * B - 2.0 * B;
   double c0 = -(A * B - B * B - B * B * B);

   double p = (3 * c1 - c2 * c2) / 3.0;
   double q = (2 * c2 * c2 * c2 - 9 * c2 * c1 + 27 * c0) / 27.0;
   double D = q * q / 4.0 + p * p * p / 27.0;

   std::vector<double> roots;

   if (D > 0) {
      double u = std::cbrt(-q / 2 + std::sqrt(D));
      double v = std::cbrt(-q / 2 - std::sqrt(D));
      roots.push_back(u + v - c2 / 3.0);
   }
   else {
      double r = std::sqrt(-p * p * p / 27.0);
      double phi = std::acos(-q / (2 * r));
      double m = 2 * std::sqrt(-p / 3.0);

      roots.push_back(m * std::cos(phi / 3.0) - c2 / 3.0);
      const double PI = 3.141592653589793238462643383279502884;
      roots.push_back(m * std::cos((phi + 2 * PI) / 3.0) - c2 / 3.0);
      roots.push_back(m * std::cos((phi + 4 * PI) / 3.0) - c2 / 3.0);
   }

   return roots;
}

// Fugacity coefficients for PR-family EOS at a given compressibility factor Z.
// Mirrors the implementation in PRSV.js (fugacityCoefficientsAtZ).
static std::vector<double> fugacityCoefficientsAtZ(
  double P_Pa,
  double T_K,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij,
  double Z,
  const std::vector<double>& ai,         // dimensional a_i
  const std::vector<double>& bi,         // dimensional b_i
  const std::vector<double>& sumAij,     // dimensional Σ_j x_j a_ij
  double Amix,                           // dimensional a_mix
  double Bmix                            // dimensional b_mix
) {
  const size_t n = x.size();
  std::vector<double> phi(n, 1.0);
  if (n == 0) return phi;

  // Reduced mixture parameters (dimensionless)
  const double Ared = (Amix * P_Pa) / (R * R * T_K * T_K);
  const double Bred = (Bmix * P_Pa) / (R * T_K);

  // Domain guards
  const double ZmB = std::max(1e-30, Z - Bred);
  const double logZminusB = std::log(ZmB);

  const double SQRT2 = std::sqrt(2.0);
  const double denom = std::max(1e-30, 2.0 * SQRT2 * Bred);
  const double common = Ared / denom; // matches PRSV.js

  for (size_t i = 0; i < n; ++i) {
    (void)comps; (void)kij; (void)ai; // kept for signature parity/future use

    // Reduced Bi (dimensionless)
    const double Bi = (bi[i] * P_Pa) / (R * T_K);

    // term1: (Bi/B)(Z-1) - ln(Z-B)
    const double term1 = (Bi / std::max(1e-30, Bred)) * (Z - 1.0) - logZminusB;

    // sum_xAij is dimensional; ratio sum/Amix is dimensionless and correct as-is
    const double sum_xAij = sumAij[i];
    const double bracket = (2.0 * (sum_xAij / std::max(1e-30, Amix))) - (Bi / std::max(1e-30, Bred));

    // term3: ln( (Z + B(1+sqrt2)) / (Z + B(1-sqrt2)) )
    const double num = std::max(1e-30, Z + Bred * (1.0 + SQRT2));
    const double den = std::max(1e-30, Z + Bred * (1.0 - SQRT2));
    const double logFrac = std::log(num / den);

    const double lnPhi = term1 - common * bracket * logFrac;
    phi[i] = std::exp(std::clamp(lnPhi, -700.0, 700.0));
  }

  return phi;
}

static double dalphaPRSV_dT(double T, double Tc, double omega)
{
   const double dT = std::max(1e-3, 1e-4 * std::max(1.0, T));
   const double a1 = alphaPRSV(T + dT, Tc, omega);
   const double a0 = alphaPRSV(T - dT, Tc, omega);
   return (a1 - a0) / (2.0 * dT);
}

static double hdepPR(double T, double Z, double a_mix, double b_mix, double da_mix_dT, double B)
{
   const double sqrt2 = std::sqrt(2.0);
   const double term1 = R * T * (Z - 1.0);

   const double num = Z + (1.0 + sqrt2) * B;
   const double den = Z + (1.0 - sqrt2) * B;
   const double lnTerm = std::log(std::max(1e-300, num / std::max(1e-300, den)));

   const double term2 = ((T * da_mix_dT - a_mix) / (2.0 * sqrt2 * b_mix)) * lnTerm;

   return term1 + term2; // J/mol
}

// ------------------------------------------------------------
// Main PRSV solver
// ------------------------------------------------------------
PRSVResult solvePRSV(
   double P,
   double T,
   const std::vector<double>& x,
   int trayIndex,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& log)
{
   const int n = (int)x.size();

   std::vector<double> a_i(n), b_i(n);
   std::vector<double> da_i_dT(n, 0.0);

   for (int i = 0; i < n; ++i) {
      const double a0 = 0.45724 * R * R * comps[i].Tc * comps[i].Tc / comps[i].Pc;
      const double alpha = alphaPRSV(T, comps[i].Tc, comps[i].omega);
      const double dalpha_dT = dalphaPRSV_dT(T, comps[i].Tc, comps[i].omega);

      a_i[i] = a0 * alpha;
      da_i_dT[i] = a0 * dalpha_dT;

      b_i[i] = 0.0778 * R * comps[i].Tc / comps[i].Pc;
   }

   double a_mix = 0.0;
   double b_mix = 0.0;
   // sumAij[i] = sum_j x_j * sqrt(a_i a_j) * (1 - kij)
   std::vector<double> sumAij(n, 0.0);

   for (int i = 0; i < n; ++i)
      b_mix += x[i] * b_i[i];

   for (int i = 0; i < n; ++i) {
      for (int j = 0; j < n; ++j) {
         double kij_ij = 0.0;
         if (kij && i < (int)kij->size() && j < (int)(*kij)[i].size())
            kij_ij = (*kij)[i][j];
         const double aij = std::sqrt(a_i[i] * a_i[j]) * (1.0 - kij_ij);
         sumAij[i] += x[j] * aij;
      }
      a_mix += x[i] * sumAij[i];
   }

   double da_mix_dT = 0.0;
   for (int i = 0; i < n; ++i) {
      for (int j = 0; j < n; ++j) {
         double kij_ij = 0.0;
         if (kij && i < (int)kij->size() && j < (int)(*kij)[i].size())
            kij_ij = (*kij)[i][j];

         if (a_i[i] > 0.0 && a_i[j] > 0.0) {
            const double sqrt_ai_aj = std::sqrt(a_i[i] * a_i[j]);
            const double d_sqrt = 0.5 * sqrt_ai_aj *
               (da_i_dT[i] / a_i[i] + da_i_dT[j] / a_i[j]);

            da_mix_dT += x[i] * x[j] * d_sqrt * (1.0 - kij_ij);
         }
      }
   }

   double A = a_mix * P / (R * R * T * T);
   double B = b_mix * P / (R * T);

   auto roots = solveCubicPR(A, B);

   std::vector<double> valid;
   // React/JS parity: fixed epsZ = 1e-9; keep roots > max(0, B + epsZ)
   const double epsZ = 1e-9;
   for (double Z : roots)
      if (std::isfinite(Z) && Z > std::max(0.0, B + epsZ))
         valid.push_back(Z);

   std::sort(valid.begin(), valid.end());

   if (log) {
      std::ostringstream os;
      os.setf(std::ios::fixed); os.precision(8);
      os << "[PRSV_ROOTS] tray=" + std::to_string(trayIndex + 1) + " P=" << P << " T=" << T
         << " A=" << A << " B=" << B
         << " roots=(";
      for (size_t i = 0; i < roots.size(); ++i) os << roots[i] << (i + 1 < roots.size() ? "," : "");
      os << ") validN=" << valid.size();
      log(os.str());
   }

   PRSVResult out;
   out.a_i = a_i;
   out.b_i = b_i;
   out.a_mix = a_mix;
   out.b_mix = b_mix;

   out.fallbackUsed = false;

   if (valid.empty()) {
      out.singlePhase = true;
      out.ZL = out.ZV = 1.0;
      out.phiL.assign(n, 1.0);
      out.phiV.assign(n, 1.0);
      return out;
   }

   if (valid.size() == 1) {
      out.singlePhase = true;
      out.ZL = out.ZV = valid[0];
      out.phiL = fugacityCoefficientsAtZ(P, T, x, comps, kij, out.ZL,
         out.a_i, out.b_i, sumAij, out.a_mix, out.b_mix);
      out.phiV = out.phiL;
      return out;
   }

   // Select ZL/ZV from filtered roots (parity with JS: smallest = liquid, largest = vapor)
   if (valid.empty()) {
      // Defensive fallback (shouldn't occur): treat as single-phase near liquid root
      out.singlePhase = true;
      out.ZL = B + epsZ;
      out.ZV = out.ZL;
   }
   else if (valid.size() == 1) {
      out.singlePhase = true;
      out.ZL = valid[0];
      out.ZV = valid[0];
   }
   else {
      out.singlePhase = false;
      out.ZL = valid.front();
      out.ZV = valid.back();
   }

   // Hard physical guard: never allow Z at or below B (avoids ln(Z-B) blowups and K-floor cascades).
   const double ZminPhys = std::max(0.0, B + epsZ);
   if (!std::isfinite(out.ZL) || out.ZL <= ZminPhys) {
      if (log) {
         std::ostringstream ws;
         ws.setf(std::ios::fixed); ws.precision(8);
         ws << "[PRSV_WARN] P=" << P << " T=" << T
            << " ZL=" << out.ZL << " B=" << B
            << " -> clamping ZL to " << ZminPhys;
         log(ws.str());
      }
      out.ZL = ZminPhys;
      out.fallbackUsed = true;
   }
   if (!std::isfinite(out.ZV) || out.ZV <= ZminPhys) {
      if (log) {
         std::ostringstream ws;
         ws.setf(std::ios::fixed); ws.precision(8);
         ws << "[PRSV_WARN] P=" << P << " T=" << T
            << " ZV=" << out.ZV << " B=" << B
            << " -> clamping ZV to " << ZminPhys;
         log(ws.str());
      }
      out.ZV = ZminPhys;
      out.fallbackUsed = true;
   }
   if (out.ZV < out.ZL) {
      // If clamping collapses the ordering, treat as single-phase at the clamped Z.
      out.ZV = out.ZL;
      out.singlePhase = true;
   }

   out.hdepL = hdepPR(T, out.ZL, a_mix, b_mix, da_mix_dT, B);
   out.hdepV = hdepPR(T, out.ZV, a_mix, b_mix, da_mix_dT, B);
   if (out.singlePhase)
      out.hdepV = out.hdepL;

   // Fugacity coefficients at overall composition z=x
   out.phiL = fugacityCoefficientsAtZ(P, T, x, comps, kij, out.ZL,
      out.a_i, out.b_i, sumAij, out.a_mix, out.b_mix);
   out.phiV = fugacityCoefficientsAtZ(P, T, x, comps, kij, out.ZV,
      out.a_i, out.b_i, sumAij, out.a_mix, out.b_mix);

   // In single-phase region, keep both arrays consistent
   if (out.singlePhase) out.phiV = out.phiL;

   return out;
}

// --- Optional diagnostic wrapper that logs to caller-provided log ---
PRSVResult solvePRSV_withLogger(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& log,
   bool diag,
   int trayIndex)
{
   auto emitLog = [&](const std::string& s)
   {
       if (!log)
         return;

      const bool isWarn = (s.rfind("[PRSV_WARN]", 0) == 0);
      if (!diag && !isWarn)
         return;

      // One outbound path for PRSV logs.
      prsvEmitCoalesced(log, s);
   };

   PRSVResult r = solvePRSV(P, T, z, trayIndex, comps, kij, emitLog);

   if (diag && log) {
      const int n = (int)r.phiL.size();
      if (n <= 0)
         return r;

      // ---- Rate-limit first: count only "bad events" per tray ----
      static std::unordered_map<int, int> g_prsvBadCount;
      int& bc = g_prsvBadCount[trayIndex];

      // ---- Single pass: phi stats + tiny count ----
      double phiLmin = std::numeric_limits<double>::infinity();
      double phiLmax = -std::numeric_limits<double>::infinity();
      double phiVmin = std::numeric_limits<double>::infinity();
      double phiVmax = -std::numeric_limits<double>::infinity();
      int tinyPhiLCount = 0;

      for (int i = 0; i < n; ++i) {
         const double a = r.phiL[i];
         const double b = (i < (int)r.phiV.size()) ? r.phiV[i]
            : std::numeric_limits<double>::quiet_NaN();

         if (!std::isfinite(a) || a < 1e-20) {
            ++tinyPhiLCount;
            if (tinyPhiLCount > (int)(0.8 * n)) break;
         }

         if (std::isfinite(a))
         {
            phiLmin = std::min(phiLmin, a);
            phiLmax = std::max(phiLmax, a);
         }
         if (std::isfinite(b))
         {
            phiVmin = std::min(phiVmin, b);
            phiVmax = std::max(phiVmax, b);
         }
      }

      const bool mostlyTinyPhiL = (tinyPhiLCount > (int)(0.8 * n));

      // ---- Kdiag + floorCount (skip if already "mostly tiny") ----
      constexpr double K_FLOOR = 1e-6;
      int floorCount = 0;
      std::vector<double> Kdiag;
      bool mostlyFloored = false;

      double Kmin = std::numeric_limits<double>::infinity();
      double Kmax = -std::numeric_limits<double>::infinity();

      if (!mostlyTinyPhiL) {
         Kdiag.assign(n, std::numeric_limits<double>::quiet_NaN());

         for (int i = 0; i < n; ++i) {
            const double phiL = r.phiL[i];
            const double phiV = (i < (int)r.phiV.size()) ? r.phiV[i]
               : std::numeric_limits<double>::quiet_NaN();

            if (std::isfinite(phiL) && std::isfinite(phiV) && phiL > 0.0 && phiV > 0.0) {
               const double K = phiL / phiV; // matches EOSK.cpp convention
               Kdiag[i] = K;
               Kmin = std::min(Kmin, K);
               Kmax = std::max(Kmax, K);
               if (K <= K_FLOOR * 1.000001) ++floorCount;
            }
            else {
               ++floorCount;
            }

            if (floorCount > (int)(0.8 * n))
            {
               mostlyFloored = true; break;
            }
         }
      }

      // ---- Correct ZL vs B check (dimensionless B) ----
      const double Bdim = r.b_mix * P / (R * T);
      const bool zUnphysical =
         std::isfinite(Bdim) && std::isfinite(r.ZL) && (r.ZL <= Bdim + 1e-10);

      // ---- RR bracket check only if needed (it's extra work) ----
      bool rrNoRoot = false;

      double f0 = std::numeric_limits<double>::quiet_NaN();
      double f1 = std::numeric_limits<double>::quiet_NaN();
      double sumz = 0.0;
      double sumzK = std::numeric_limits<double>::quiet_NaN();
      double sumzOverK = std::numeric_limits<double>::quiet_NaN();

      bool rrSuggestSinglePhase = false;
      std::string rrPhaseSuggest; // "V" or "L"

      if (!mostlyTinyPhiL && !mostlyFloored) {

         // compute RR endpoints + optional sanity sums
         auto rrF = [&](double beta) -> double {
            double s = 0.0;
            for (int i = 0; i < n; ++i) {
               const double zi = (i < (int)z.size()) ? z[i] : 0.0;
               const double Ki = (i < (int)Kdiag.size()) ? Kdiag[i] : std::numeric_limits<double>::quiet_NaN();
               if (!(zi > 0.0) || !std::isfinite(Ki))
                  continue;

               const double d = 1.0 + beta * (Ki - 1.0);
               if (d <= 0.0)
                  return std::numeric_limits<double>::quiet_NaN();
               s += zi * (Ki - 1.0) / d;
            }
            return s;
         };

         // sums (only if finite)
         double sZ = 0.0, sZK = 0.0, sZOK = 0.0;
         bool sumsFinite = true;
         for (int i = 0; i < n; ++i) {
            const double zi = (i < (int)z.size()) ? z[i] : 0.0;
            const double Ki = (i < (int)Kdiag.size()) ? Kdiag[i] : std::numeric_limits<double>::quiet_NaN();
            if (!(zi > 0.0))
               continue;
            sZ += zi;
            if (!std::isfinite(Ki) || Ki <= 0.0)
            {
               sumsFinite = false;
               continue;
            }
            sZK += zi * Ki;
            sZOK += zi / Ki;
         }
         sumz = sZ;
         if (sumsFinite)
         {
            sumzK = sZK;
            sumzOverK = sZOK;
         }

         f0 = rrF(0.0);
         f1 = rrF(1.0);

         if (std::isfinite(f0) && std::isfinite(f1)) {
            constexpr double eps = 1e-12;

            // Endpoint root or bracket?
            if (std::abs(f0) < eps || std::abs(f1) < eps) {
               rrNoRoot = false;
            }
            else {
               rrNoRoot = ((f0 > 0.0 && f1 > 0.0) || (f0 < 0.0 && f1 < 0.0));
            }

            // If no root, this is typically a valid single-phase endpoint.
            if (rrNoRoot) {
               rrSuggestSinglePhase = true;
               rrPhaseSuggest = (f0 > 0.0 && f1 > 0.0) ? "V" : "L";
            }
         }
         else {
            rrNoRoot = true; // blew up -> treat as bad
         }
      }

      // If RR indicates single-phase, force consistency on the result.
      if (rrSuggestSinglePhase) {
         rrNoRoot = false; // do not classify as bad

         // ---- VERY LIGHT logging: once per tray, then every 200 occurrences ----
         static std::unordered_map<int, int> g_prsvInfoCount;
         int& ic = g_prsvInfoCount[trayIndex];
         ++ic;

         const bool shouldInfoLog = (ic == 1) || (ic % 200 == 0);
         if (shouldInfoLog && log) {
            // Keep it short to reduce overhead; no heavy formatting
            std::string msg = "[PRSV_INFO] tray=" + std::to_string(trayIndex + 1) +
               " forcedSinglePhase=" + rrPhaseSuggest +
               " f0=" + std::to_string(f0) +
               " f1=" + std::to_string(f1);
            emitLog(msg);
         }
      }

      const bool bad =
         !std::isfinite(r.ZL) || !std::isfinite(r.ZV) ||
         zUnphysical ||
         mostlyFloored || (floorCount > (int)(0.8 * n)) ||
         mostlyTinyPhiL ||
         rrNoRoot ||                 // now only "bad" when it blew up / invalid, not valid single-phase
         r.fallbackUsed;

      if (!bad)
         return r;

      // ---- Rate limiting: first 3 logs, then every 10 up to 50, then every 100 ----
      const bool shouldLog =
         (bc < 3) || (bc < 50 && (bc % 10 == 0)) || (bc % 100 == 0);

      ++bc;
      if (!shouldLog)
         return r;

      // ---- Build the string ONLY when we will emit ----
      std::ostringstream oss;
      oss.setf(std::ios::fixed);
      oss << std::setprecision(6);
      oss << "[PRSV_DIAG] tray=" << trayIndex + 1
         << " P=" << P << " T=" << T
         << " singlePhase=" << (r.singlePhase ? 1 : 0)
         << " phase=" << (r.phase.empty() ? "?" : r.phase)
         << " ZL=" << r.ZL << " ZV=" << r.ZV
         << " B=" << (std::isfinite(Bdim) ? Bdim : 0.0)
         << " (ZL-B)=" << ((std::isfinite(r.ZL) && std::isfinite(Bdim)) ? (r.ZL - Bdim) : 0.0)
         << " floorCount=" << floorCount << "/" << n
         << " tinyPhiLCount=" << tinyPhiLCount << "/" << n
         << " Kmin=" << (std::isfinite(Kmin) ? Kmin : 0.0)
         << " Kmax=" << (std::isfinite(Kmax) ? Kmax : 0.0)
         << " rrNoRoot=" << (rrNoRoot ? 1 : 0)
         << " f0=" << f0
         << " f1=" << f1
         << " sumz=" << sumz
         << " sumzK=" << sumzK
         << " sumzOverK=" << sumzOverK
         << " fallbackUsed=" << (r.fallbackUsed ? 1 : 0)
         << " phiL(min,max)=(" << (std::isfinite(phiLmin) ? phiLmin : 0.0)
         << "," << (std::isfinite(phiLmax) ? phiLmax : 0.0) << ")"
         << " phiV(min,max)=(" << (std::isfinite(phiVmin) ? phiVmin : 0.0)
         << "," << (std::isfinite(phiVmax) ? phiVmax : 0.0) << ")";
      emitLog(oss.str());
   }

   return r;
}