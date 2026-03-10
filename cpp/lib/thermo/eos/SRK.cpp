#include <algorithm>
#include <cmath>
#include <limits>

#include "SRK.hpp"

// Universal gas constant [J/mol/K]
static double kij_ij(const std::vector<std::vector<double>>* kij, size_t i, size_t j) {
  if (!kij) return 0.0;
  if (i >= kij->size()) return 0.0;
  if (j >= (*kij)[i].size()) return 0.0;
  return (*kij)[i][j];
}

static inline double clampd(double x, double lo, double hi) {
   return std::max(lo, std::min(hi, x));
}

// Pure-component SRK parameters
static double alpha_SRK(double omega, double Tr) {
  // Soave alpha for SRK: alpha = [1 + m(1 - sqrt(Tr))]^2
  const double m = 0.480 + 1.574 * omega - 0.176 * omega * omega;
  const double s = 1.0 + m * (1.0 - std::sqrt(std::max(Tr, 1e-12)));
  return s * s;
}

static double ai_SRK(double Tc, double Pc, double omega, double T) {
  // a = 0.42747 * R^2 * Tc^2 / Pc * alpha
  const double Tr = T / Tc;
  const double alpha = alpha_SRK(omega, Tr);
  return 0.42747 * (R * R) * (Tc * Tc) / Pc * alpha;
}

static double bi_SRK(double Tc, double Pc) {
  // b = 0.08664 * R * Tc / Pc
  return 0.08664 * R * Tc / Pc;
}

static std::vector<double> solveCubicSRK(double A, double B) {
  // Cubic: Z^3 - Z^2 + (A - B - B^2)Z - A*B = 0
  // We'll use a robust real-root routine by converting to depressed cubic.
  const double a2 = -1.0;
  const double a1 = (A - B - B * B);
  const double a0 = -A * B;

  // Depress: Z = y - a2/3
  const double p = a1 - a2 * a2 / 3.0;
  const double q = 2.0 * a2 * a2 * a2 / 27.0 - a2 * a1 / 3.0 + a0;
  const double D = (q * q) / 4.0 + (p * p * p) / 27.0;

  std::vector<double> roots;
  const double shift = -a2 / 3.0;

  if (D > 0.0) {
    const double sqrtD = std::sqrt(D);
    const double u = std::cbrt(-q / 2.0 + sqrtD);
    const double v = std::cbrt(-q / 2.0 - sqrtD);
    roots.push_back(u + v + shift);
  } else {
    // 3 real roots (D <= 0)
    const double r = std::sqrt(std::max(-p * p * p / 27.0, 0.0));
    const double phi = std::atan2(std::sqrt(std::max(-D, 0.0)), -q / 2.0);
    const double t = 2.0 * std::cbrt(r);
    roots.push_back(t * std::cos(phi / 3.0) + shift);
    roots.push_back(t * std::cos((phi + 2.0 * 3.14159265358979323846) / 3.0) + shift);
    roots.push_back(t * std::cos((phi + 4.0 * 3.14159265358979323846) / 3.0) + shift);
  }

  // Keep only real-ish roots, sort
  roots.erase(std::remove_if(roots.begin(), roots.end(), [](double z) {
    return !std::isfinite(z);
  }), roots.end());
  std::sort(roots.begin(), roots.end());
  return roots;
}

SRKMixture solveSRK_mixture(
  double P,
  double T,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij
) {
  SRKMixture mix;
  mix.P = P;
  mix.T = T;
  mix.x = &x;
  mix.comps = &comps;
  mix.kij = kij;

  const size_t n = x.size();
  mix.ai.assign(n, 0.0);
  mix.bi.assign(n, 0.0);

  for (size_t i = 0; i < n; i++) {
    const auto& c = comps[i];
    mix.ai[i] = ai_SRK(c.Tc, c.Pc, c.omega, T);
    mix.bi[i] = bi_SRK(c.Tc, c.Pc);
  }

  // mixing rules
  double amix = 0.0;
  double bmix = 0.0;

  for (size_t i = 0; i < n; i++) {
    bmix += x[i] * mix.bi[i];
  }

  for (size_t i = 0; i < n; i++) {
    for (size_t j = 0; j < n; j++) {
      const double aij = std::sqrt(mix.ai[i] * mix.ai[j]) * (1.0 - kij_ij(kij, i, j));
      amix += x[i] * x[j] * aij;
    }
  }

  mix.amix = amix;
  mix.bmix = bmix;

  // dimensionless A and B
  mix.A = amix * P / (R * R * T * T);
  mix.B = bmix * P / (R * T);

  mix.Z_roots = solveCubicSRK(mix.A, mix.B);
  return mix;
}

std::vector<double> computePhi_SRK(const SRKMixture& mix, double Z) {
   const auto& x = *mix.x;
   const auto& comps = *mix.comps;
   const auto* kij = mix.kij;

   const size_t n = x.size();
   std::vector<double> phi(n, 1.0);

   const double A = mix.A;
   const double B = mix.B;

   // ---- numeric safety ----
   auto clamp = [](double v, double lo, double hi) {
      return (v < lo) ? lo : (v > hi) ? hi : v;
      };

   // React/JS parity (SRK.js):
   //   eps = 1e-15
   //   ln_term = log(1 + B / max(Z, eps))
   //   ZmB = max(Z - B, eps)
   const double eps = 1e-15;
   const double Zsafe = std::max(Z, eps);
   const double ln_term = std::log(1.0 + B / Zsafe);
   const double ZmB = std::max(Z - B, eps);

   for (size_t i = 0; i < n; i++) {
      // sum_j x_j * sqrt(ai*aj) * (1-kij)
      double sum_a = 0.0;
      for (size_t j = 0; j < n; j++) {
         const double aij = std::sqrt(mix.ai[i] * mix.ai[j]) * (1.0 - kij_ij(kij, i, j));
         sum_a += x[j] * aij;
      }

      const double bi = mix.bi[i];

      const double term1 = (bi / mix.bmix) * (Zsafe - 1.0);
      const double term2 = -std::log(ZmB);

      // Avoid A/B blow-up if B is tiny
      const double Bsafe = std::max(B, eps);
      const double AoverB = A / Bsafe;

      const double bracket = (2.0 * sum_a / mix.amix - bi / mix.bmix);
      const double term3 = -(AoverB)*bracket * ln_term;

      double lnphi = term1 + term2 + term3;

      // Prevent exp underflow/overflow.
      // exp(-50) ~ 1.9e-22 and will print as 0.000000 in many logs; keeping
      // a tighter clamp avoids systematic "all tiny" phiL while remaining safe.
      // React/JS parity: clamp lnphi to [-50, 50] before exp().
      lnphi = clamp(lnphi, -50.0, 50.0);

      const double ph = std::exp(lnphi);

      // Final safety: never return exactly 0
      phi[i] = std::max(ph, 1e-300);
   }

   return phi;
}

SolveSRKResult solveSRK(
  double P,
  double T,
  const std::vector<double>& x,
  const std::vector<Component>& comps,
  const std::vector<std::vector<double>>* kij
) {
  SRKMixture mix = solveSRK_mixture(P, T, x, comps, kij);

  SolveSRKResult out;
  if (mix.Z_roots.empty()) {
    // fallback: ideal-gas Z ~ 1
    out.ZL = out.ZV = 1.0;
    out.phiL.assign(x.size(), 1.0);
    out.phiV.assign(x.size(), 1.0);
    return out;
  }

  // React/JS parity (SRK.js): pick liquid/vapor roots as min/max of the real roots
  // with no B-based filtering here.
  auto roots = mix.Z_roots;
  std::sort(roots.begin(), roots.end());
  out.ZL = roots.front();
  out.ZV = roots.back();

  out.phiL = computePhi_SRK(mix, out.ZL);
  out.phiV = computePhi_SRK(mix, out.ZV);
  return out;
}
