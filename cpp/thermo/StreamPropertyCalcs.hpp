#pragma once
// thermo/StreamPropertyCalcs.hpp
//
// Post-flash stream property calculations.
// Correlations follow the same family used in Aspen Plus / HYSYS for
// petroleum pseudocomponent systems:
//
//   Density        — PRSV EOS compressibility (ZL/ZV) → ρ = P·Mw/(Z·R·T)
//   Viscosity liq  — Letsou-Stiel (pseudoreduced properties)
//   Viscosity vap  — Lucas method
//   k liq          — Sato-Riedel
//   k vap          — Stiel-Thodos (polyatomic)
//   Cp             — temperature-dependent ideal-gas + EOS departure (liq/vap)
//   Cp/Cv vap      — γ = Cp / (Cp − R/Mw)  [ideal-gas, valid for vapour]
//   Enthalpy       — calls existing hLiq / hVap (EOS departure + ideal-gas)
//   Entropy        — calls existing sLiq / sVap
//   Surface tension — Macleod-Sugden with estimated parachors
//   Watson K factor — Kw = Tb^(1/3) / SG, mole-fraction weighted
//   Critical mix    — Kay's mixing rule  Tcm = Σzi·Tci, Pcm = Σzi·Pci
//   Std vol flow    — liquid density at 15 °C / 101.325 kPa via PRSV

#include <vector>
#include <limits>
#include "pseudocomponents/componentData.hpp"
#include "ThermoConfig.hpp"

struct StreamPhaseProps {
    // ── Per-phase densities ─────────────────────────────────────────────────
    double rhoLiq        = std::numeric_limits<double>::quiet_NaN(); // kg/m³
    double rhoVap        = std::numeric_limits<double>::quiet_NaN(); // kg/m³

    // ── Per-phase viscosities ───────────────────────────────────────────────
    double viscLiqCp     = std::numeric_limits<double>::quiet_NaN(); // cP
    double viscVapCp     = std::numeric_limits<double>::quiet_NaN(); // cP

    // ── Per-phase thermal conductivities ────────────────────────────────────
    double kCondLiqWmK   = std::numeric_limits<double>::quiet_NaN(); // W/(m·K)
    double kCondVapWmK   = std::numeric_limits<double>::quiet_NaN(); // W/(m·K)

    // ── Per-phase heat capacities ───────────────────────────────────────────
    double cpLiqKJkgK    = std::numeric_limits<double>::quiet_NaN(); // kJ/(kg·K)
    double cpVapKJkgK    = std::numeric_limits<double>::quiet_NaN(); // kJ/(kg·K)
    double cpCvRatioVap  = std::numeric_limits<double>::quiet_NaN(); // dimensionless γ

    // ── Per-phase enthalpies ─────────────────────────────────────────────────
    double hLiqKJkg      = std::numeric_limits<double>::quiet_NaN(); // kJ/kg
    double hVapKJkg      = std::numeric_limits<double>::quiet_NaN(); // kJ/kg

    // ── Per-phase entropies ──────────────────────────────────────────────────
    double sLiqKJkgK     = std::numeric_limits<double>::quiet_NaN(); // kJ/(kg·K)
    double sVapKJkgK     = std::numeric_limits<double>::quiet_NaN(); // kJ/(kg·K)

    // ── Interfacial ──────────────────────────────────────────────────────────
    double surfTensionNm = std::numeric_limits<double>::quiet_NaN(); // N/m

    // ── Mixture / bulk ───────────────────────────────────────────────────────
    double watsonK       = std::numeric_limits<double>::quiet_NaN(); // dimensionless
    double TcMixK        = std::numeric_limits<double>::quiet_NaN(); // K   (Kay's rule)
    double PcMixKPa      = std::numeric_limits<double>::quiet_NaN(); // kPa (Kay's rule)

    // ── Std volumetric liquid flow ───────────────────────────────────────────
    // Computed from liquid density at 15 °C / 101.325 kPa.
    // Caller must supply massFlowKgph; result is in m³/h.
    double stdVolFlowM3ph = std::numeric_limits<double>::quiet_NaN(); // m³/h
};

// ---------------------------------------------------------------------------
// calcStreamProperties
//
// Call once after every successful flash to populate all derived properties.
//
//   T             — stream temperature [K]
//   P             — stream pressure [Pa]
//   z             — overall feed mole fractions (normalised, length n)
//   x             — liquid phase mole fractions from flash (length n)
//   y             — vapour phase mole fractions from flash (length n)
//   V             — vapour fraction [0-1]
//   massFlowKgph  — total mass flow [kg/h]  (used only for stdVolFlowM3ph)
//   comps         — component data (SI-normalised: Pc in Pa, Tc in K, etc.)
//
// Returns a fully-populated StreamPhaseProps.  Individual fields are NaN when
// the calculation cannot be performed (e.g. single-phase stream has no liquid
// density when V == 1).
// ---------------------------------------------------------------------------
StreamPhaseProps calcStreamProperties(
    double T,
    double P,
    const std::vector<double>& z,
    const std::vector<double>& x,
    const std::vector<double>& y,
    double V,
    double massFlowKgph,
    const std::vector<Component>& comps,
    const thermo::ThermoConfig& thermoConfig
);

StreamPhaseProps calcStreamProperties(
    double T,
    double P,
    const std::vector<double>& z,
    const std::vector<double>& x,
    const std::vector<double>& y,
    double V,
    double massFlowKgph,
    const std::vector<Component>& comps
);
