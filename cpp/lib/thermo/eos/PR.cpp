#include <algorithm>
#include <cmath>
#include <limits>

#include "PR.hpp"

static inline double clamp(double v, double lo, double hi) { return std::min(hi, std::max(lo, v)); }

// ---- PR alpha and d(alpha)/dT ----
static double kappaPR(double omega) {
  const double w = clamp(std::isfinite(omega) ? omega : 0.0, -0.15, 1.2);
  return 0.37464 + 1.54226 * w - 0.26992 * w * w;
}

static double alphaPR(double T, double Tc, double omega) {
  const double Tr = std::max(1e-12, T / Tc);
  const double k = kappaPR(omega);
  const double g = 1.0 + k * (1.0 - std::sqrt(Tr));
  return g * g;
}

static double dalpha_dT_PR(double T, double Tc, double omega) {
  const double Tr = std::max(1e-12, T / Tc);
  const double k = kappaPR(omega);
  const double g = 1.0 + k * (1.0 - std::sqrt(Tr));
  const double dg_dT = (k * -0.5) / (std::sqrt(Tr) * Tc);
  return 2.0 * g * dg_dT;
}

// ---- Pure (a,b) ----
struct PurePR {
  double a = NAN;
  double b = NAN;
};

static PurePR purePRParams(const Component& comp, double T) {
  PurePR p;
  const double Tc = comp.Tc;
  const double Pc = comp.Pc;
  const double omega = comp.omega;
  const double a0 = (0.45724 * R * R * Tc * Tc) / Pc;
  const double b  = (0.0778  * R * Tc) / Pc;
  p.a = a0 * alphaPR(T, Tc, omega);
  p.b = b;
  return p;
}

// ---- vdW-1 mixing with optional kij ----
static void mixParams(const std::vector<double>& z,
                      std::vector<double>& a_i,
                      std::vector<double>& b_i,
                      const std::vector<std::vector<double>>* kij,
                      double& a_mix,
                      double& b_mix) {
  const int n = (int)z.size();
  a_mix = 0.0;
  b_mix = 0.0;

  for (int i = 0; i < n; ++i) b_mix += z[i] * b_i[i];

  for (int i = 0; i < n; ++i) {
    for (int j = 0; j < n; ++j) {
      double kij_ij = 0.0;
      if (kij && i < (int)kij->size() && j < (int)(*kij)[i].size() && std::isfinite((*kij)[i][j])) {
        kij_ij = (*kij)[i][j];
      }
      a_mix += z[i] * z[j] * std::sqrt(std::max(0.0, a_i[i] * a_i[j])) * (1.0 - kij_ij);
    }
  }
}

// ---- Cubic real solver ----
static std::vector<double> solveCubicReal(double a, double b, double c, double d) {
  b /= a; c /= a; d /= a;
  const double Q = (3.0*c - b*b) / 9.0;
  const double Rr = (9.0*b*c - 27.0*d - 2.0*b*b*b) / 54.0;
  const double D = Q*Q*Q + Rr*Rr;

  std::vector<double> out;
  if (D >= 0.0) {
    const double sqrtD = std::sqrt(D);
    const double S = std::cbrt(Rr + sqrtD);
    const double T = std::cbrt(Rr - sqrtD);
    out.push_back(-b/3.0 + (S + T));
  } else {
    const double denom = std::sqrt(std::max(1e-30, -Q*Q*Q));
    double arg = Rr / denom;
    arg = clamp(arg, -1.0, 1.0);
    const double th = std::acos(arg);
    const double r = 2.0 * std::sqrt(std::max(0.0, -Q));
    constexpr double PI = 3.14159265358979323846;
    out.push_back(r * std::cos(th/3.0) - b/3.0);
    out.push_back(r * std::cos((th + 2.0*PI)/3.0) - b/3.0);
    out.push_back(r * std::cos((th + 4.0*PI)/3.0) - b/3.0);
  }
  return out;
}

static std::vector<double> solveCubicPR(double A, double B) {
  const double c2 = -(1.0 - B);
  const double c1 = A - 3.0*B*B - 2.0*B;
  const double c0 = -(A*B - B*B - B*B*B);

  auto roots = solveCubicReal(1.0, c2, c1, c0);

  std::vector<double> out;
  for (double Z : roots) if (std::isfinite(Z) && Z > 0.0) out.push_back(Z);
  std::sort(out.begin(), out.end());
  return out;
}

// ---- Fugacity coefficients (phi_i) at Z ----
static std::vector<double> fugacityCoefficientsAtZ(
    double Z,
    const std::vector<double>& z,
    const std::vector<double>& a_i,
    const std::vector<double>& b_i,
    double a_mix,
    double b_mix,
    double A,
    double B,
    const std::vector<std::vector<double>>* kij)
{
  const int n = (int)z.size();

  std::vector<double> sqrt_ai(n);
  for (int i = 0; i < n; ++i) sqrt_ai[i] = std::sqrt(std::max(0.0, a_i[i]));

  // a_ij including kij
  std::vector<std::vector<double>> a_ij(n, std::vector<double>(n, 0.0));
  for (int i = 0; i < n; ++i) {
    for (int j = 0; j < n; ++j) {
      double kij_ij = 0.0;
      if (kij && i < (int)kij->size() && j < (int)(*kij)[i].size() && std::isfinite((*kij)[i][j])) {
        kij_ij = (*kij)[i][j];
      }
      a_ij[i][j] = sqrt_ai[i] * sqrt_ai[j] * (1.0 - kij_ij);
    }
  }

  // da_mix/dn_i ~ 2 Σ z_j a_ij
  std::vector<double> da_mix_i(n, 0.0);
  for (int i = 0; i < n; ++i) {
    double s = 0.0;
    for (int j = 0; j < n; ++j) s += z[j] * a_ij[i][j];
    da_mix_i[i] = 2.0 * s;
  }

  std::vector<double> phi(n, 1.0);

  // React/JS parity: guard Z-B with a fixed 1e-12.
  // JS: const ZmB = Math.max(1e-12, Z - B);
  const double ZmB = std::max(1e-12, Z - B);
  const double denomB = std::max(1e-30, B);
  const double denom2 = 2.0 * std::sqrt(2.0) * denomB;

  const double Zp = Z + (1.0 + std::sqrt(2.0)) * B;
  const double Zm = std::max(1e-12, Z + (1.0 - std::sqrt(2.0)) * B);
  const double lnArg = std::log(std::max(1e-12, Zp / Zm));

  for (int i = 0; i < n; ++i) {
    const double bi_b = b_i[i] / std::max(1e-30, b_mix);

    const double ln1 = bi_b * (Z - 1.0) - std::log(ZmB);
    const double ln2 = (A / denom2) *
                       ((da_mix_i[i] / std::max(1e-30, a_mix)) - (b_i[i] / std::max(1e-30, b_mix))) *
                       lnArg;

        double lnPhi = ln1 - ln2;
    if (!std::isfinite(lnPhi)) lnPhi = 0.0;
    // exp(-50) ~ 1.9e-22 which prints as 0.000000 and can trip "tinyPhi" heuristics.
    // A tighter clamp still protects numerics while avoiding systematic collapse.
    // React/JS parity: clamp lnPhi to [-50, 50] before exp().
    phi[i] = std::exp(clamp(lnPhi, -50.0, 50.0));
  }

  return phi;
}

// ---- Departure enthalpy (J/mol) for PR at Z ----
static double departureEnthalpyAtZ(
    double T, double Z,
    const std::vector<double>& z,
    const std::vector<double>& a_i,
    double a_mix, double b_mix,
    double B,
    const std::vector<Component>& comps,
    const std::vector<std::vector<double>>* kij)
{
  const int n = (int)z.size();

  // da_i/dT via PR alpha
  std::vector<double> a0_i(n, 0.0);
  std::vector<double> da_i(n, 0.0);
  for (int i = 0; i < n; ++i) {
    const double Tc = comps[i].Tc;
    const double Pc = comps[i].Pc;
    const double omega = comps[i].omega;
    a0_i[i] = (0.45724 * R * R * Tc * Tc) / Pc;
    da_i[i] = a0_i[i] * dalpha_dT_PR(T, Tc, omega);
  }

  // da_mix/dT (vdW-1 with kij)
  double da_mix_dT = 0.0;
  for (int i = 0; i < n; ++i) {
    for (int j = 0; j < n; ++j) {
      double kij_ij = 0.0;
      if (kij && i < (int)kij->size() && j < (int)(*kij)[i].size() && std::isfinite((*kij)[i][j])) {
        kij_ij = (*kij)[i][j];
      }
      const double aij_sqrt = std::sqrt(std::max(0.0, a_i[i] * a_i[j]));
      const double frac_i = da_i[i] / std::max(1e-30, a_i[i]);
      const double frac_j = da_i[j] / std::max(1e-30, a_i[j]);
      const double term = 0.5 * (frac_i + frac_j) * aij_sqrt * (1.0 - kij_ij);
      da_mix_dT += z[i] * z[j] * term;
    }
  }

  const double Zp = Z + (1.0 + std::sqrt(2.0)) * B;
  const double Zm = std::max(1e-12, Z + (1.0 - std::sqrt(2.0)) * B);
  const double lnArg = std::log(std::max(1e-12, Zp / Zm));

  const double term1 = R * T * (Z - 1.0);
  const double term2 = ((T * da_mix_dT - a_mix) / (2.0 * std::sqrt(2.0) * std::max(1e-30, b_mix))) * lnArg;
  return term1 + term2;
}

// ---- Public: solve PR mixture ----
PRResult solvePR(double P, double T,
                 const std::vector<double>& x,
                 const std::vector<Component>& comps,
                 const std::vector<std::vector<double>>* kij)
{
  const int n = (int)x.size();
  PRResult out;
  out.a_i.assign(n, 0.0);
  out.b_i.assign(n, 0.0);

  for (int i = 0; i < n; ++i) {
    const PurePR p = purePRParams(comps[i], T);
    out.a_i[i] = p.a;
    out.b_i[i] = p.b;
  }

  mixParams(x, out.a_i, out.b_i, kij, out.a_mix, out.b_mix);

  const double A = (out.a_mix * P) / (R * R * T * T);
  const double B = (out.b_mix * P) / (R * T);

  // React/JS parity: fixed epsilon for Z-root filtering/selection.
  // JS: const epsZ = 1e-9; keep roots > max(0, B + epsZ)
  const double epsZ = 1e-9;
  const auto rootsAll = solveCubicPR(A, B);

  std::vector<double> roots;
    const double minZ = std::max(0.0, B + epsZ);
  for (double Z : rootsAll) if (std::isfinite(Z) && Z > minZ) roots.push_back(Z);
  std::sort(roots.begin(), roots.end());

  bool singlePhase = false;
  double Zsingle = NAN;
  double ZL = NAN, ZV = NAN;

  if (roots.size() >= 2) {
    // Vapor root: largest valid Z.
    ZV = roots.back();

    // Liquid root: prefer smallest root, but if it yields pathological
    // fugacity coefficients (phiL collapses to ~0 for most components),
    // consider the middle root.
    auto scoreZ = [&](double Zcand) {
      if (!(Zcand > B + epsZ) || !(Zcand < ZV - 1e-8)) return std::numeric_limits<int>::max();
      const auto phi = fugacityCoefficientsAtZ(Zcand, x, out.a_i, out.b_i, out.a_mix, out.b_mix, A, B, kij);
      int tiny = 0;
      for (double v : phi) {
        if (!std::isfinite(v) || v < 1e-20) tiny++;
      }
      return tiny;
    };

    double ZLcand = roots.front();
    int bestScore = scoreZ(ZLcand);

    // Near-B safeguard: bump off the smallest root if it is too close to B.
    if ((ZLcand - B) < epsZ && roots.size() >= 2) {
      ZLcand = roots[1];
      bestScore = scoreZ(ZLcand);
    }

    // Quality safeguard: compare against middle root if present.
    if (roots.size() >= 3) {
      const double Zmid = roots[1];
      const int sMid = scoreZ(Zmid);
      if (sMid < bestScore) {
        bestScore = sMid;
        ZLcand = Zmid;
      }
    }

    ZL = ZLcand;
  } else if (roots.size() == 1) {
    singlePhase = true;
    Zsingle = roots[0];
    ZL = ZV = Zsingle;
  } else {
    singlePhase = true;
    double Zcand = rootsAll.empty() ? 1.0 : *std::max_element(rootsAll.begin(), rootsAll.end());
    Zsingle = std::max(std::max(1e-6, B + 1e-6), Zcand);
    ZL = ZV = Zsingle;
  }

  if (!singlePhase) {
    const double rel = std::abs(ZV - ZL) / std::max(1e-12, std::abs(ZV));
    if (rel < 1e-8) {
      singlePhase = true;
      Zsingle = 0.5 * (ZL + ZV);
      ZL = ZV = Zsingle;
    }
  }

  if (singlePhase) {
    out.singlePhase = true;
    out.Z = Zsingle;
    out.ZL = Zsingle;
    out.ZV = Zsingle;
    const auto phi = fugacityCoefficientsAtZ(Zsingle, x, out.a_i, out.b_i, out.a_mix, out.b_mix, A, B, kij);
    out.phiL = phi;
    out.phiV = phi;
    out.hdepL = 0.0;
    out.hdepV = 0.0;
    return out;
  }

  out.singlePhase = false;
  out.ZL = ZL;
  out.ZV = ZV;

  out.phiL = fugacityCoefficientsAtZ(ZL, x, out.a_i, out.b_i, out.a_mix, out.b_mix, A, B, kij);
  out.phiV = fugacityCoefficientsAtZ(ZV, x, out.a_i, out.b_i, out.a_mix, out.b_mix, A, B, kij);

  out.hdepL = departureEnthalpyAtZ(T, ZL, x, out.a_i, out.a_mix, out.b_mix, B, comps, kij);
  out.hdepV = departureEnthalpyAtZ(T, ZV, x, out.a_i, out.a_mix, out.b_mix, B, comps, kij);

  return out;
}
