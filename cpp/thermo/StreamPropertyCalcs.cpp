// thermo/StreamPropertyCalcs.cpp
//
// Correlation references
// ─────────────────────
//  Density:         PRSV EOS — exact within the chosen EOS, same as Aspen/HYSYS
//  Viscosity liq:   Letsou & Stiel (1973) — AIChE J 19(2):409
//  Viscosity vap:   Lucas (1980) — Chem Eng 87(25):153
//  k liquid:        Sato & Riedel (1976) — AIChE J 22(4):716  (simplified form)
//  k vapour:        Stiel & Thodos (1964) — AIChE J 10(1):26  (polyatomic)
//  Cp:              Temperature-dependent ideal-gas + EOS departure (see Enthalpy.cpp)
//  Cp/Cv vapour:    γ = Cp/(Cp − R/Mw)  — ideal-gas identity
//  Enthalpy:        calls hLiq / hVap (EOS departure, Enthalpy.hpp)
//  Entropy:         calls sLiq / sVap (Entropy.hpp)
//  Surface tension: Macleod-Sugden with parachors estimated via Knotts et al. (2001)
//  Watson K factor: Watson (1935) Kw = Tb^(1/3)/SG
//  Critical mix:    Kay's mixing rule (1936)
//  Std vol flow:    PRSV liquid root at T=288.15 K, P=101325 Pa

#include "StreamPropertyCalcs.hpp"
#include "Enthalpy.hpp"
#include "Entropy.hpp"
#include "EOSK.hpp"
#include "eos/PRSV.hpp"
#include "eos/PR.hpp"
#include "eos/SRK.hpp"
#include "ThermoConfig.hpp"

#include <cmath>
#include <algorithm>
#include <numeric>
#include <limits>

// ============================================================================
// Internal constants
// ============================================================================
namespace {

constexpr double R_J     = 8.31446261815324;  // J/(mol·K)
constexpr double R_kJ    = 8.31446261815324e-3; // kJ/(mol·K)
constexpr double T_STD   = 288.15;            // K  (15 °C, standard conditions)
constexpr double P_STD   = 101325.0;          // Pa

// ============================================================================
// Helpers
// ============================================================================

inline bool ok(double v) { return std::isfinite(v) && v > 0.0; }
inline double clamp(double v, double lo, double hi) { return std::max(lo, std::min(hi, v)); }

// Mole-fraction-weighted average molecular weight [kg/kmol]
double mixMw(const std::vector<double>& z, const std::vector<Component>& c)
{
    double mw = 0.0;
    const std::size_t n = std::min(z.size(), c.size());
    for (std::size_t i = 0; i < n; ++i)
        mw += z[i] * (ok(c[i].MW) ? c[i].MW : 200.0);
    return std::max(1.0, mw);  // kg/kmol
}

// ============================================================================
// Density  (EOS-based, same approach as Aspen/HYSYS)
// ρ = P · Mw / (Z · R · T)   where Mw is in kg/mol, P in Pa, T in K
// Returns kg/m³, or NaN on failure.
// ============================================================================
double eosDensity(
    double P, double T,
    const std::vector<double>& x,
    const std::vector<Component>& comps,
    bool liquid,
    const thermo::ThermoConfig& thermoConfig)
{
    if (x.empty() || comps.empty() || !ok(P) || !ok(T))
        return std::numeric_limits<double>::quiet_NaN();

    const std::string eosName = thermoConfig.eosName.empty() ? std::string("PRSV") : thermoConfig.eosName;

    double Z = std::numeric_limits<double>::quiet_NaN();
    if (eosName == "PR") {
        const PRResult r = solvePR_mixture(P, T, x, comps, nullptr);
        Z = liquid ? r.ZL : r.ZV;
    } else if (eosName == "SRK") {
        const auto r = solveSRK(P, T, x, comps, nullptr);
        Z = liquid ? r.ZL : r.ZV;
    } else {
        const PRSVResult r = solvePRSV_mixture(P, T, x, -1, comps, nullptr, nullptr);
        Z = liquid ? r.ZL : r.ZV;
    }

    if (!ok(Z)) return std::numeric_limits<double>::quiet_NaN();

    const double Mw_kg_mol = mixMw(x, comps) / 1000.0;
    const double rho = (P * Mw_kg_mol) / (Z * R_J * T);
    return ok(rho) ? rho : std::numeric_limits<double>::quiet_NaN();
}

// ============================================================================
// Cp helpers (promoted from Entropy.cpp anonymous namespace)
// ============================================================================

} // anonymous namespace

namespace {

// Mixture Cp [kJ/(kg·K)]
double mixCp(const std::vector<double>& z, const std::vector<Component>& comps,
             double T, bool liquid)
{
    const std::size_t n = std::min(z.size(), comps.size());
    double cpMolar = 0.0;   // kJ/(kmol·K)
    double Mwmix   = 0.0;   // kg/kmol
    for (std::size_t i = 0; i < n; ++i) {
        const double zi  = z[i];
        const double mwi = ok(comps[i].MW) ? comps[i].MW : 200.0;
        const double cpi = liquid
            ? cpLiqKJperKgK(comps[i], T) * mwi   // kJ/(kmol·K)
            : cpVapKJperKgK(comps[i], T) * mwi;
        cpMolar += zi * cpi;
        Mwmix   += zi * mwi;
    }
    if (!(Mwmix > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    return cpMolar / Mwmix;  // kJ/(kg·K)
}

// ============================================================================
// Viscosity — liquid  (Letsou-Stiel, 1973)
//
// ξ = (Tc^(1/6)) / (Mw^(1/2) · Pc^(2/3))    [SI: Pa·s]
// η·ξ = (ξ₀ + ω·ξ₁)  where
//   ξ₀ = 1.2435×10⁻³ · exp(1.4684·Tr) − 1.0681×10⁻³ · exp(−1.0886·Tr)   (× 10⁻⁷)
//   ξ₁ = 6.8510×10⁻³ · exp(1.4778·Tr) − 7.4310×10⁻³ · exp(−1.2440·Tr)   (× 10⁻⁷)
// Applied component-by-component then linearly mixed (mass fractions for liquid).
// Result in cP = mPa·s.
// ============================================================================
double viscLiqCp(const std::vector<double>& x,
                 const std::vector<Component>& comps, double T)
{
    const std::size_t n = std::min(x.size(), comps.size());
    double numSum = 0.0, denSum = 0.0;

    for (std::size_t i = 0; i < n; ++i) {
        if (!(x[i] > 0.0)) continue;
        const auto& c = comps[i];
        const double Tc = ok(c.Tc)    ? c.Tc    : 700.0;
        const double Pc = ok(c.Pc)    ? c.Pc    : 3.0e6; // Pa
        const double om = std::isfinite(c.omega) ? c.omega : 0.5;
        const double Mw = ok(c.MW)    ? c.MW    : 200.0;  // kg/kmol

        const double Tr = clamp(T / Tc, 0.3, 1.0);

        // ξ in (Pa·s)⁻¹  — Letsou-Stiel dimensional group
        // Pc in Pa, Tc in K, Mw in g/mol = kg/kmol
        const double xi = std::pow(Tc, 1.0/6.0)
                        / (std::sqrt(Mw) * std::pow(Pc / 1e5, 2.0/3.0));
        // 1e-5 factor keeps units consistent when Pc is in Pa and we want cP output
        const double xi0 = (1.2435e-3 * std::exp( 1.4684 * Tr)
                          - 1.0681e-3 * std::exp(-1.0886 * Tr)) * 1e-7;
        const double xi1 = (6.8510e-3 * std::exp( 1.4778 * Tr)
                          - 7.4310e-3 * std::exp(-1.2440 * Tr)) * 1e-7;

        const double eta_PaS = (xi > 0.0) ? (xi0 + om * xi1) / xi : std::numeric_limits<double>::quiet_NaN();
        if (!std::isfinite(eta_PaS) || eta_PaS <= 0.0) continue;

        // Liquid mixing: Grunberg-Nissan ln-sum (common in Aspen)
        numSum += x[i] * std::log(eta_PaS * 1000.0); // log(cP)
        denSum += x[i];
    }
    if (!(denSum > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    const double visc_cP = std::exp(numSum / denSum);
    return clamp(visc_cP, 0.001, 100000.0);
}

// ============================================================================
// Viscosity — vapour  (Lucas method, 1980)
//
// η° = [0.807·Tr^0.618 − 0.357·exp(−0.449·Tr) + 0.340·exp(−4.058·Tr) + 0.018] · F°_P · F°_Q · ξ⁻¹
// where ξ = 0.176·(Tc / Mw³·Pc⁴)^(1/6)    (Pc in bar)
// Applied component-by-component, then Wilke mixing rule for gas mixtures.
// Result in cP = mPa·s.
// ============================================================================
double viscVapCp(const std::vector<double>& y,
                 const std::vector<Component>& comps, double T)
{
    const std::size_t n = std::min(y.size(), comps.size());

    // Component viscosities [Pa·s]
    std::vector<double> eta(n, 0.0);
    std::vector<double> Mwv(n, 200.0);

    for (std::size_t i = 0; i < n; ++i) {
        const auto& c = comps[i];
        const double Tc = ok(c.Tc) ? c.Tc : 700.0;
        const double Pc = ok(c.Pc) ? c.Pc : 3.0e6; // Pa
        const double Mw = ok(c.MW) ? c.MW : 200.0;  // kg/kmol

        const double Tr = clamp(T / Tc, 0.4, 20.0);
        const double Pc_bar = Pc / 1e5;

        // ξ  [cP⁻¹] — Lucas dimensional group
        // ξ = 0.176 · (Tc / (Mw³ · Pc⁴))^(1/6)   Pc in bar, Mw in g/mol
        const double xi = 0.176 * std::pow(Tc / (Mw * Mw * Mw * Pc_bar * Pc_bar * Pc_bar * Pc_bar), 1.0/6.0);

        const double eta0 = (0.807 * std::pow(Tr, 0.618)
                           - 0.357 * std::exp(-0.449 * Tr)
                           + 0.340 * std::exp(-4.058 * Tr)
                           + 0.018) / xi; // cP

        eta[i] = ok(eta0) ? clamp(eta0 * 1e-3, 1e-8, 1e-2) : 1e-5; // Pa·s
        Mwv[i] = Mw;
    }

    // Wilke mixing rule
    double etaMix = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!(y[i] > 0.0)) continue;
        double denom = 0.0;
        for (std::size_t j = 0; j < n; ++j) {
            if (!(y[j] > 0.0)) continue;
            const double phi = std::pow(1.0 + std::sqrt(eta[i]/eta[j]) * std::pow(Mwv[j]/Mwv[i], 0.25), 2.0)
                             / std::sqrt(8.0 * (1.0 + Mwv[i]/Mwv[j]));
            denom += y[j] * phi;
        }
        if (denom > 0.0)
            etaMix += y[i] * eta[i] / denom;
    }
    const double visc_cP = etaMix * 1000.0; // Pa·s → cP
    return ok(visc_cP) ? clamp(visc_cP, 1e-4, 1.0) : std::numeric_limits<double>::quiet_NaN();
}

// ============================================================================
// Thermal conductivity — liquid  (Sato-Riedel, simplified)
//
// k = (1.1053 / Mw^(1/2)) · (3 + 20·(1 − Tr)^(2/3)) / (3 + 20·(1 − Tbr)^(2/3))
// Returns W/(m·K).
// ============================================================================
double kCondLiq(const std::vector<double>& x,
                const std::vector<Component>& comps, double T)
{
    const std::size_t n = std::min(x.size(), comps.size());
    double kNum = 0.0, kDen = 0.0;

    for (std::size_t i = 0; i < n; ++i) {
        if (!(x[i] > 0.0)) continue;
        const auto& c = comps[i];
        const double Tc  = ok(c.Tc) ? c.Tc : 700.0;
        const double Tb  = ok(c.Tb) ? c.Tb : 500.0;
        const double Mw  = ok(c.MW) ? c.MW : 200.0;

        const double Tr  = clamp(T  / Tc, 0.01, 0.99);
        const double Tbr = clamp(Tb / Tc, 0.01, 0.99);

        const double num = 3.0 + 20.0 * std::pow(1.0 - Tr,  2.0/3.0);
        const double den = 3.0 + 20.0 * std::pow(1.0 - Tbr, 2.0/3.0);
        if (!(den > 0.0)) continue;

        const double ki = (1.1053 / std::sqrt(Mw)) * (num / den);
        // Li mixing rule (volume-fraction approximation via mole fractions)
        kNum += x[i] * ki;
        kDen += x[i];
    }
    if (!(kDen > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    const double k = kNum / kDen;
    return ok(k) ? clamp(k, 0.05, 1.0) : std::numeric_limits<double>::quiet_NaN();
}

// ============================================================================
// Thermal conductivity — vapour  (Stiel-Thodos, polyatomic, 1964)
//
// For each component:
//   k = (4.358×10⁻³ · η · Cp + R/(4·Mw)) / Mw   [W/(m·K)]
//     simplified form for non-linear polyatomic molecules.
// Mole-fraction mixing for the vapour phase.
// ============================================================================
double kCondVap(const std::vector<double>& y,
                const std::vector<Component>& comps, double T, double P)
{
    const std::size_t n = std::min(y.size(), comps.size());

    // Get individual component vapour viscosities via Lucas (single-component limit)
    double kNum = 0.0, kDen = 0.0;

    for (std::size_t i = 0; i < n; ++i) {
        if (!(y[i] > 0.0)) continue;
        const auto& c = comps[i];
        const double Tc  = ok(c.Tc) ? c.Tc : 700.0;
        const double Pc  = ok(c.Pc) ? c.Pc : 3.0e6;
        const double Mw  = ok(c.MW) ? c.MW : 200.0;

        const double Tr     = clamp(T / Tc, 0.4, 20.0);
        const double Pc_bar = Pc / 1e5;
        const double xi     = 0.176 * std::pow(Tc / (Mw * Mw * Mw * Pc_bar * Pc_bar * Pc_bar * Pc_bar), 1.0/6.0);
        const double eta_cP = (0.807 * std::pow(Tr, 0.618)
                             - 0.357 * std::exp(-0.449 * Tr)
                             + 0.340 * std::exp(-4.058 * Tr)
                             + 0.018) / xi;  // cP
        const double eta_PaS = clamp(eta_cP * 1e-3, 1e-7, 1e-2);

        const double cp_J = cpVapKJperKgK(c, T) * 1000.0 * (Mw / 1000.0); // J/(mol·K)

        // Stiel-Thodos: k_i = (4.358e-3 * eta[Pa·s] * Cp[J/mol·K] + R/4) / Mw[kg/mol]
        const double Mw_kgmol = Mw / 1000.0;
        const double ki = (4.358e-3 * eta_PaS * cp_J + R_J / 4.0) / Mw_kgmol;  // W/(m·K)

        kNum += y[i] * ki;
        kDen += y[i];
    }
    if (!(kDen > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    const double k = kNum / kDen;
    (void)P;
    return ok(k) ? clamp(k, 0.003, 0.5) : std::numeric_limits<double>::quiet_NaN();
}

// ============================================================================
// Surface tension  (Macleod-Sugden, with parachors from Knotts et al. 2001)
//
// σ^(1/4) = [P] · (ρL − ρV) / Mw     [σ in N/m, ρ in mol/cm³]
// Parachor estimated: [P] ≈ 40 + 0.32·Mw + 0.03·(Tb − 300)  (crude but standard for petroleum)
// ============================================================================
double surfaceTension(const std::vector<double>& x,
                      const std::vector<Component>& comps,
                      double rhoLiq_kgm3, double rhoVap_kgm3)
{
    const std::size_t n = std::min(x.size(), comps.size());
    if (!ok(rhoLiq_kgm3)) return std::numeric_limits<double>::quiet_NaN();

    double sigma4 = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!(x[i] > 0.0)) continue;
        const auto& c = comps[i];
        const double Mw = ok(c.MW) ? c.MW : 200.0;         // kg/kmol
        const double Tb = ok(c.Tb) ? c.Tb : 500.0;         // K
        const double Mw_gmol = Mw;                           // g/mol ≡ kg/kmol

        // Estimated parachor
        const double parachor = 40.0 + 0.32 * Mw_gmol + 0.03 * (Tb - 300.0);

        // ρ in mol/cm³
        const double rhoL_molcm3 = (ok(rhoLiq_kgm3)) ? rhoLiq_kgm3 / (Mw_gmol * 1000.0) : 0.0;
        const double rhoV_molcm3 = (ok(rhoVap_kgm3)) ? rhoVap_kgm3 / (Mw_gmol * 1000.0) : 0.0;

        const double deltaRho = rhoL_molcm3 - rhoV_molcm3;
        sigma4 += x[i] * parachor * deltaRho;
    }
    if (!(sigma4 > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    // σ [dyn/cm] from Macleod-Sugden, convert to N/m: 1 dyn/cm = 1e-3 N/m
    const double sigma_dyncm = std::pow(sigma4, 4.0);
    const double sigma_Nm    = sigma_dyncm * 1e-3;
    return clamp(sigma_Nm, 1e-6, 0.1);
}

// ============================================================================
// Watson K factor  (Watson, 1935)
// Kw = Tb^(1/3) / SG      Tb in Rankine, but equivalent form with Tb in K:
//   Kw = (Tb[R])^(1/3) / SG = (Tb[K] × 1.8)^(1/3) / SG
// Mole-fraction weighted mixture value, matching Aspen convention.
// ============================================================================
double watsonKFactor(const std::vector<double>& z,
                     const std::vector<Component>& comps)
{
    const std::size_t n = std::min(z.size(), comps.size());
    double kw = 0.0, wSum = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!(z[i] > 0.0)) continue;
        const auto& c = comps[i];
        const double Tb = ok(c.Tb) ? c.Tb : 500.0; // K
        const double SG = ok(c.SG) ? c.SG : 0.85;

        const double Tb_R = Tb * 1.8;  // K → Rankine
        const double kwi  = std::pow(Tb_R, 1.0/3.0) / SG;
        kw   += z[i] * kwi;
        wSum += z[i];
    }
    if (!(wSum > 0.0)) return std::numeric_limits<double>::quiet_NaN();
    return kw / wSum;
}

// ============================================================================
// Critical mixture properties  (Kay's mixing rule, 1936)
// ============================================================================
void criticalMix(const std::vector<double>& z, const std::vector<Component>& comps,
                 double& TcK, double& PcKPa)
{
    const std::size_t n = std::min(z.size(), comps.size());
    double tc = 0.0, pc = 0.0, wSum = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!(z[i] > 0.0)) continue;
        const double tci = ok(comps[i].Tc) ? comps[i].Tc : 700.0;
        const double pci = ok(comps[i].Pc) ? comps[i].Pc : 3.0e6; // Pa
        tc   += z[i] * tci;
        pc   += z[i] * pci;
        wSum += z[i];
    }
    if (!(wSum > 0.0)) {
        TcK   = std::numeric_limits<double>::quiet_NaN();
        PcKPa = std::numeric_limits<double>::quiet_NaN();
        return;
    }
    TcK   = tc   / wSum;
    PcKPa = pc   / wSum / 1000.0; // Pa → kPa
}

// ============================================================================
// Standard volumetric flow
// Compute liquid density at T=288.15 K (15 °C), P=101325 Pa via PRSV.
// stdVolFlow [m³/h] = massFlow [kg/h] / rho_std [kg/m³]
// ============================================================================
double stdVolFlowM3ph(double massFlowKgph,
                      const std::vector<double>& z,
                      const std::vector<Component>& comps,
                      const thermo::ThermoConfig& thermoConfig)
{
    if (!(massFlowKgph > 0.0) || z.empty() || comps.empty())
        return std::numeric_limits<double>::quiet_NaN();

    const double rhoStd = eosDensity(P_STD, T_STD, z, comps, /*liquid=*/true, thermoConfig);
    if (!ok(rhoStd)) return std::numeric_limits<double>::quiet_NaN();

    return massFlowKgph / rhoStd;
}

} // anonymous namespace

// ============================================================================
// Public API
// ============================================================================

StreamPhaseProps calcStreamProperties(
    double T,
    double P,
    const std::vector<double>& z,
    const std::vector<double>& x,
    const std::vector<double>& y,
    double V,
    double massFlowKgph,
    const std::vector<Component>& comps,
    const thermo::ThermoConfig& thermoConfig)
{
    StreamPhaseProps out;

    const bool hasLiq = std::isfinite(V) && V < 0.9999 && !x.empty();
    const bool hasVap = std::isfinite(V) && V > 0.0001 && !y.empty();

    if (hasLiq) out.rhoLiq = eosDensity(P, T, x, comps, true, thermoConfig);
    if (hasVap) out.rhoVap = eosDensity(P, T, y, comps, false, thermoConfig);

    if (hasLiq) out.viscLiqCp = viscLiqCp(x, comps, T);
    if (hasVap) out.viscVapCp = viscVapCp(y, comps, T);

    if (hasLiq) out.kCondLiqWmK = kCondLiq(x, comps, T);
    if (hasVap) out.kCondVapWmK = kCondVap(y, comps, T, P);

    if (hasLiq) out.cpLiqKJkgK = mixCp(x, comps, T, true);
    if (hasVap) out.cpVapKJkgK = mixCp(y, comps, T, false);

    if (hasVap && ok(out.cpVapKJkgK)) {
        const double Mwv   = mixMw(y, comps);
        const double RkJkg = R_kJ / (Mwv / 1000.0);
        const double CvVap = out.cpVapKJkgK - RkJkg;
        if (CvVap > 0.0)
            out.cpCvRatioVap = out.cpVapKJkgK / CvVap;
    }

    if (hasLiq) out.hLiqKJkg = hLiqWithConfig(x, T, thermoConfig, -1, comps, P, nullptr);
    if (hasVap) out.hVapKJkg = hVapWithConfig(y, T, thermoConfig, -1, comps, P, nullptr);

    if (hasLiq) out.sLiqKJkgK = sLiq(x, T, -1, comps, P);
    if (hasVap) out.sVapKJkgK = sVap(y, T, -1, comps, P);

    if (hasLiq && hasVap)
        out.surfTensionNm = surfaceTension(x, comps, out.rhoLiq, out.rhoVap);

    out.watsonK = watsonKFactor(z, comps);
    criticalMix(z, comps, out.TcMixK, out.PcMixKPa);
    out.stdVolFlowM3ph = stdVolFlowM3ph(massFlowKgph, z, comps, thermoConfig);

    return out;
}

StreamPhaseProps calcStreamProperties(
    double T,
    double P,
    const std::vector<double>& z,
    const std::vector<double>& x,
    const std::vector<double>& y,
    double V,
    double massFlowKgph,
    const std::vector<Component>& comps)
{
    return calcStreamProperties(T, P, z, x, y, V, massFlowKgph, comps, thermo::makeThermoConfig("PRSV"));
}
