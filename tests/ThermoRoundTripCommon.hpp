#pragma once

#include <cmath>
#include <string>
#include <vector>

#include "thermo/PH_PS_PT_TS_Flash.hpp"
#include "thermo/pseudocomponents/FluidDefinition.hpp"

struct ThermoRoundTripRow {
    std::string fluid;
    double P_Pa = NAN;
    double T_inputK = NAN;

    bool tpFinite = false;
    double tpV = NAN;
    double tpH = NAN;
    double tpS = NAN;

    bool phFinite = false;
    double phT = NAN;
    double phV = NAN;
    double phH = NAN;
    double phS = NAN;
    std::string phStatus;

    bool psFinite = false;
    double psT = NAN;
    double psV = NAN;
    double psH = NAN;
    double psS = NAN;
    std::string psStatus;

    bool tsFinite = false;
    double tsP = NAN;
    double tsV = NAN;
    double tsH = NAN;
    double tsS = NAN;
    std::string tsStatus;

    double dT_PH = NAN;
    double dV_PH = NAN;
    double dH_PH = NAN;
    double dS_PH = NAN;

    double dT_PS = NAN;
    double dV_PS = NAN;
    double dH_PS = NAN;
    double dS_PS = NAN;

    double dP_TS = NAN;
    double dV_TS = NAN;
    double dH_TS = NAN;
    double dS_TS = NAN;
};

inline bool trtFinite(double x) { return std::isfinite(x); }

inline double trtAbsDiff(double a, double b) {
    return (trtFinite(a) && trtFinite(b)) ? std::fabs(a - b) : NAN;
}

inline ThermoRoundTripRow runThermoRoundTrip(const std::string& fluid, double P, double T)
{
    ThermoRoundTripRow row;
    row.fluid = fluid;
    row.P_Pa = P;
    row.T_inputK = T;

    const FluidDefinition def = getFluidDefinition(fluid);
    const auto& comps = def.thermo.components;
    const auto& z = def.thermo.zDefault;
    const auto& kij = def.thermo.kij;

    if (comps.empty() || z.empty()) {
        row.phStatus = "missing-components-or-z";
        row.psStatus = "missing-components-or-z";
        row.tsStatus = "missing-components-or-z";
        return row;
    }

    const auto pt = flashPT(P, T, z, &comps, -1, 32, fluid, &kij, 1.0, "manual", "PRSV");
    row.tpFinite = trtFinite(pt.H) && trtFinite(pt.S) && trtFinite(pt.V);
    row.tpV = pt.V;
    row.tpH = pt.H;
    row.tpS = pt.S;

    if (!row.tpFinite) {
        row.phStatus = "tp-not-finite";
        row.psStatus = "tp-not-finite";
        row.tsStatus = "tp-not-finite";
        return row;
    }

    FlashPHInput phIn;
    phIn.Htarget = pt.H;
    phIn.z = z;
    phIn.P = P;
    phIn.Tseed = T;
    phIn.components = &comps;
    phIn.trayIndex = -1;
    phIn.trays = 32;
    phIn.crudeName = fluid;
    phIn.eosMode = "manual";
    phIn.eosManual = "PRSV";
    phIn.kij = &kij;
    phIn.logLevel = LogLevel::None;

    const auto ph = flashPH(phIn);
    row.phFinite = trtFinite(ph.T) && trtFinite(ph.V) && trtFinite(ph.Hcalc) && trtFinite(ph.Scalc);
    row.phT = ph.T;
    row.phV = ph.V;
    row.phH = ph.Hcalc;
    row.phS = ph.Scalc;
    row.phStatus = ph.status;
    row.dT_PH = trtAbsDiff(ph.T, T);
    row.dV_PH = trtAbsDiff(ph.V, pt.V);
    row.dH_PH = trtAbsDiff(ph.Hcalc, pt.H);
    row.dS_PH = trtAbsDiff(ph.Scalc, pt.S);

    FlashPSInput psIn;
    psIn.Starget = pt.S;
    psIn.z = z;
    psIn.P = P;
    psIn.Tseed = T;
    psIn.components = &comps;
    psIn.trayIndex = -1;
    psIn.trays = 32;
    psIn.crudeName = fluid;
    psIn.eosMode = "manual";
    psIn.eosManual = "PRSV";
    psIn.kij = &kij;
    psIn.logLevel = LogLevel::None;

    const auto ps = flashPS(psIn);
    row.psFinite = trtFinite(ps.T) && trtFinite(ps.V) && trtFinite(ps.Hcalc) && trtFinite(ps.Scalc);
    row.psT = ps.T;
    row.psV = ps.V;
    row.psH = ps.Hcalc;
    row.psS = ps.Scalc;
    row.psStatus = ps.status;
    row.dT_PS = trtAbsDiff(ps.T, T);
    row.dV_PS = trtAbsDiff(ps.V, pt.V);
    row.dH_PS = trtAbsDiff(ps.Hcalc, pt.H);
    row.dS_PS = trtAbsDiff(ps.Scalc, pt.S);
    FlashTSInput tsIn;
    tsIn.Starget = pt.S;
    tsIn.z = z;
    tsIn.T = T;
    tsIn.Pseed = P;
    tsIn.components = &comps;
    tsIn.trayIndex = -1;
    tsIn.trays = 32;
    tsIn.crudeName = fluid;
    tsIn.eosMode = "manual";
    tsIn.eosManual = "PRSV";
    tsIn.kij = &kij;
    tsIn.logLevel = LogLevel::None;

    const auto ts = flashTS(tsIn);
    row.tsFinite = trtFinite(ts.P) && trtFinite(ts.V) && trtFinite(ts.Hcalc) && trtFinite(ts.Scalc);
    row.tsP = ts.P;
    row.tsV = ts.V;
    row.tsH = ts.Hcalc;
    row.tsS = ts.Scalc;
    row.tsStatus = ts.status;
    row.dP_TS = trtAbsDiff(ts.P, P);
    row.dV_TS = trtAbsDiff(ts.V, pt.V);
    row.dH_TS = trtAbsDiff(ts.Hcalc, pt.H);
    row.dS_TS = trtAbsDiff(ts.Scalc, pt.S);
    return row;
}
