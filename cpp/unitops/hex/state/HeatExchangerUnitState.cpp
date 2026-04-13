#include "HeatExchangerUnitState.h"

#include "flowsheet/state/FlowsheetState.h"
#include "streams/state/StreamUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "fluid/FluidPackageManager.h"
#include "thermo/PH_PS_PT_TS_Flash.hpp"
#include "thermo/Enthalpy.hpp"
#include "thermo/pseudocomponents/FluidDefinition.hpp"
#include "thermo/ThermoConfig.hpp"

#include <QDebug>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

HeatExchangerUnitState::HeatExchangerUnitState(QObject* parent)
    : ProcessUnitState(parent)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Wiring
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

void HeatExchangerUnitState::setConnectedHotInStreamUnitId(const QString& id)
{
    if (hotInStreamUnitId_ == id) return;
    hotInStreamUnitId_ = id;
    clearResults_();
    emit hotInStreamChanged();
}

void HeatExchangerUnitState::setConnectedHotOutStreamUnitId(const QString& id)
{
    if (hotOutStreamUnitId_ == id) return;
    hotOutStreamUnitId_ = id;
    emit hotOutStreamChanged();
}

void HeatExchangerUnitState::setConnectedColdInStreamUnitId(const QString& id)
{
    if (coldInStreamUnitId_ == id) return;
    coldInStreamUnitId_ = id;
    clearResults_();
    emit coldInStreamChanged();
}

void HeatExchangerUnitState::setConnectedColdOutStreamUnitId(const QString& id)
{
    if (coldOutStreamUnitId_ == id) return;
    coldOutStreamUnitId_ = id;
    emit coldOutStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::setSpecMode(const QString& v)
{
    if (specMode_ == v) return;
    specMode_ = v;
    clearResults_();
    emit specModeChanged();
}

void HeatExchangerUnitState::setDutyKW(double v)
{
    if (qFuzzyCompare(dutyKW_, v)) return;
    dutyKW_ = v;
    clearResults_();
    emit dutyKWChanged();
}

void HeatExchangerUnitState::setHotOutletTK(double v)
{
    if (qFuzzyCompare(hotOutletTK_, v)) return;
    hotOutletTK_ = v;
    clearResults_();
    emit hotOutletTKChanged();
}

void HeatExchangerUnitState::setColdOutletTK(double v)
{
    if (qFuzzyCompare(coldOutletTK_, v)) return;
    coldOutletTK_ = v;
    clearResults_();
    emit coldOutletTKChanged();
}

void HeatExchangerUnitState::setHotSidePressureDropPa(double v)
{
    if (qFuzzyCompare(hotSidePressureDropPa_, v)) return;
    hotSidePressureDropPa_ = v;
    clearResults_();
    emit hotSidePressureDropPaChanged();
}

void HeatExchangerUnitState::setColdSidePressureDropPa(double v)
{
    if (qFuzzyCompare(coldSidePressureDropPa_, v)) return;
    coldSidePressureDropPa_ = v;
    clearResults_();
    emit coldSidePressureDropPaChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

MaterialStreamState* HeatExchangerUnitState::findStream(const QString& unitId) const
{
    if (!flowsheetState_ || unitId.isEmpty()) return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(unitId);
}

void HeatExchangerUnitState::clearResults_()
{
    if (!solved_) return;
    solved_             = false;
    calcDutyKW_         = 0.0;
    calcHotOutTK_       = 0.0;
    calcColdOutTK_      = 0.0;
    calcHotOutVapFrac_  = 0.0;
    calcColdOutVapFrac_ = 0.0;
    calcLMTD_           = 0.0;
    calcUA_             = 0.0;
    calcApproachT_      = 0.0;
    solveStatus_.clear();
    emit solvedChanged();
    emit resultsChanged();
}

void HeatExchangerUnitState::reset()
{
    clearResults_();
}

// ─────────────────────────────────────────────────────────────────────────────
// Thermo helpers
// ─────────────────────────────────────────────────────────────────────────────

// Build mole fractions + thermo config from a material stream
static bool buildThermoInputs(MaterialStreamState* stream,
                               thermo::ThermoConfig& cfgOut,
                               std::vector<Component>& compsOut,
                               std::vector<std::vector<double>>& kijOut,
                               std::vector<double>& zOut,
                               QString& errOut)
{
    const FluidDefinition& fd = stream->fluidDefinition();
    compsOut = fd.thermo.components;
    kijOut   = fd.thermo.kij;

    if (compsOut.empty()) {
        errOut = QStringLiteral("Fluid package not resolved.");
        return false;
    }

    auto* fpm = FluidPackageManager::instance();
    cfgOut = fpm
        ? fpm->thermoConfigForPackageResolved(stream->selectedFluidPackageId())
        : thermo::makeThermoConfig("PRSV");

    const std::vector<double>& wt = stream->compositionStd();
    if (wt.size() != compsOut.size()) {
        errOut = QStringLiteral("Composition / component count mismatch.");
        return false;
    }

    zOut.resize(wt.size(), 0.0);
    double sumMolar = 0.0;
    for (size_t i = 0; i < wt.size(); ++i) {
        zOut[i] = (compsOut[i].MW > 0.0) ? wt[i] / compsOut[i].MW : 0.0;
        sumMolar += zOut[i];
    }
    if (sumMolar > 0.0)
        for (auto& zi : zOut) zi /= sumMolar;

    return true;
}

HeatExchangerUnitState::OutletResult
HeatExchangerUnitState::calcOutletFromH_(MaterialStreamState* inStream,
                                          double P_out,
                                          double H_out_kJkg,
                                          double T_seed) const
{
    OutletResult res;

    thermo::ThermoConfig cfg;
    std::vector<Component> comps;
    std::vector<std::vector<double>> kij;
    std::vector<double> z;

    if (!buildThermoInputs(inStream, cfg, comps, kij, z, res.status))
        return res;

    FlashPHInput phi;
    phi.Htarget    = H_out_kJkg;
    phi.z          = z;
    phi.P          = P_out;
    phi.Tseed      = T_seed;
    phi.components = &comps;
    phi.thermoConfig = cfg;
    phi.kij        = &kij;

    const FlashPHResult r = flashPH(phi);
    if (r.status != "ok") {
        res.status = QStringLiteral("PH flash failed: ") + QString::fromStdString(r.status);
        return res;
    }

    res.T       = r.T;
    res.vapFrac = r.V;
    res.ok      = true;
    return res;
}

// ─────────────────────────────────────────────────────────────────────────────
// LMTD calculation (counter-current)
//   ΔT1 = T_hotIn  − T_coldOut   (hot-end temperature difference)
//   ΔT2 = T_hotOut − T_coldIn    (cold-end temperature difference)
//   LMTD = (ΔT1 − ΔT2) / ln(ΔT1/ΔT2)
// ─────────────────────────────────────────────────────────────────────────────
static double computeLMTD(double T_hotIn, double T_hotOut,
                        double T_coldIn, double T_coldOut)
{
    const double dt1 = T_hotIn  - T_coldOut;
    const double dt2 = T_hotOut - T_coldIn;
    if (dt1 <= 0.0 || dt2 <= 0.0) return std::numeric_limits<double>::quiet_NaN();
    if (std::fabs(dt1 - dt2) < 0.001) return dt1;  // degenerate → arithmetic mean
    return (dt1 - dt2) / std::log(dt1 / dt2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::solve()
{
    // ── 1. Gather inlet streams ───────────────────────────────────────────────
    MaterialStreamState* hotIn  = findStream(hotInStreamUnitId_);
    MaterialStreamState* coldIn = findStream(coldInStreamUnitId_);

    if (!hotIn || !coldIn) {
        solveStatus_ = QStringLiteral("Both hot-side and cold-side feed streams must be connected.");
        emit resultsChanged();
        return;
    }

    const double T_hotIn  = hotIn->temperatureK();
    const double P_hotIn  = hotIn->pressurePa();
    const double mdot_hot = hotIn->flowRateKgph();
    const double H_hotIn  = hotIn->enthalpyKJkg();

    const double T_coldIn  = coldIn->temperatureK();
    const double P_coldIn  = coldIn->pressurePa();
    const double mdot_cold = coldIn->flowRateKgph();
    const double H_coldIn  = coldIn->enthalpyKJkg();

    // Basic validation
    if (mdot_hot <= 0.0 || std::isnan(mdot_hot)) {
        solveStatus_ = QStringLiteral("Hot-side flow rate is zero or undefined.");
        emit resultsChanged(); return;
    }
    if (mdot_cold <= 0.0 || std::isnan(mdot_cold)) {
        solveStatus_ = QStringLiteral("Cold-side flow rate is zero or undefined.");
        emit resultsChanged(); return;
    }
    if (std::isnan(T_hotIn)  || std::isnan(P_hotIn)  || std::isnan(H_hotIn)) {
        solveStatus_ = QStringLiteral("Hot-side inlet conditions not fully defined.");
        emit resultsChanged(); return;
    }
    if (std::isnan(T_coldIn) || std::isnan(P_coldIn) || std::isnan(H_coldIn)) {
        solveStatus_ = QStringLiteral("Cold-side inlet conditions not fully defined.");
        emit resultsChanged(); return;
    }
    if (T_hotIn <= T_coldIn) {
        solveStatus_ = QStringLiteral("Hot-side inlet temperature must be above cold-side inlet temperature.");
        emit resultsChanged(); return;
    }

    const double P_hotOut  = P_hotIn  - hotSidePressureDropPa_;
    const double P_coldOut = P_coldIn - coldSidePressureDropPa_;
    if (P_hotOut  <= 0.0) { solveStatus_ = QStringLiteral("Hot-side outlet pressure ≤ 0."); emit resultsChanged(); return; }
    if (P_coldOut <= 0.0) { solveStatus_ = QStringLiteral("Cold-side outlet pressure ≤ 0."); emit resultsChanged(); return; }

    // ── 2. Build thermo inputs for hot and cold streams ───────────────────────
    thermo::ThermoConfig hotCfg, coldCfg;
    std::vector<Component> hotComps, coldComps;
    std::vector<std::vector<double>> hotKij, coldKij;
    std::vector<double> hotZ, coldZ;
    QString errMsg;

    if (!buildThermoInputs(hotIn,  hotCfg,  hotComps,  hotKij,  hotZ,  errMsg)) {
        solveStatus_ = QStringLiteral("Hot side: ") + errMsg; emit resultsChanged(); return;
    }
    if (!buildThermoInputs(coldIn, coldCfg, coldComps, coldKij, coldZ, errMsg)) {
        solveStatus_ = QStringLiteral("Cold side: ") + errMsg; emit resultsChanged(); return;
    }

    // ── 3. Solve by spec mode ─────────────────────────────────────────────────
    double Q_kW       = 0.0;
    double T_hotOut   = std::numeric_limits<double>::quiet_NaN();
    double T_coldOut  = std::numeric_limits<double>::quiet_NaN();
    double V_hotOut   = std::numeric_limits<double>::quiet_NaN();
    double V_coldOut  = std::numeric_limits<double>::quiet_NaN();
    bool   solveOk    = false;
    QString status;

    if (specMode_ == QStringLiteral("duty")) {
        // Q specified → H_hotOut = H_hotIn − Q*3600/ṁ_hot
        //             → H_coldOut = H_coldIn + Q*3600/ṁ_cold
        const double Q_kJh   = dutyKW_ * 3600.0;
        const double H_hotOut_kJkg  = H_hotIn  - Q_kJh / mdot_hot;
        const double H_coldOut_kJkg = H_coldIn + Q_kJh / mdot_cold;

        // Estimate outlet T seeds: assume linear Cp
        const double T_hotSeed  = T_hotIn  - (T_hotIn  - T_coldIn) * 0.5;
        const double T_coldSeed = T_coldIn + (T_hotIn  - T_coldIn) * 0.5;

        auto hotRes  = calcOutletFromH_(hotIn,  P_hotOut,  H_hotOut_kJkg,  T_hotSeed);
        auto coldRes = calcOutletFromH_(coldIn, P_coldOut, H_coldOut_kJkg, T_coldSeed);

        if (!hotRes.ok)  { solveStatus_ = QStringLiteral("Hot outlet: ") + hotRes.status; emit resultsChanged(); return; }
        if (!coldRes.ok) { solveStatus_ = QStringLiteral("Cold outlet: ") + coldRes.status; emit resultsChanged(); return; }

        Q_kW      = dutyKW_;
        T_hotOut  = hotRes.T;
        T_coldOut = coldRes.T;
        V_hotOut  = hotRes.vapFrac;
        V_coldOut = coldRes.vapFrac;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else if (specMode_ == QStringLiteral("hotOutletT")) {
        // Hot outlet T specified → Q from hot-side energy balance → cold outlet from Q
        const FlashPTResult hotRes = flashPT(
            P_hotOut, hotOutletTK_, hotZ, hotCfg, &hotComps, &hotKij);
        if (std::isnan(hotRes.H)) {
            solveStatus_ = QStringLiteral("PT flash failed for hot outlet."); emit resultsChanged(); return;
        }

        const double Q_kJh          = mdot_hot * (H_hotIn - hotRes.H);   // heat released
        const double H_coldOut_kJkg = H_coldIn + Q_kJh / mdot_cold;
        const double T_coldSeed     = T_coldIn + (hotOutletTK_ - T_coldIn) * 0.5;

        auto coldRes = calcOutletFromH_(coldIn, P_coldOut, H_coldOut_kJkg, T_coldSeed);
        if (!coldRes.ok) { solveStatus_ = QStringLiteral("Cold outlet: ") + coldRes.status; emit resultsChanged(); return; }

        Q_kW      = Q_kJh / 3600.0;
        T_hotOut  = hotOutletTK_;
        T_coldOut = coldRes.T;
        V_hotOut  = hotRes.V;
        V_coldOut = coldRes.vapFrac;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else if (specMode_ == QStringLiteral("coldOutletT")) {
        // Cold outlet T specified → Q from cold-side energy balance → hot outlet from Q
        const FlashPTResult coldRes = flashPT(
            P_coldOut, coldOutletTK_, coldZ, coldCfg, &coldComps, &coldKij);
        if (std::isnan(coldRes.H)) {
            solveStatus_ = QStringLiteral("PT flash failed for cold outlet."); emit resultsChanged(); return;
        }

        const double Q_kJh         = mdot_cold * (coldRes.H - H_coldIn);  // heat absorbed
        const double H_hotOut_kJkg = H_hotIn - Q_kJh / mdot_hot;
        const double T_hotSeed     = T_hotIn - (T_hotIn - coldOutletTK_) * 0.5;

        auto hotRes = calcOutletFromH_(hotIn, P_hotOut, H_hotOut_kJkg, T_hotSeed);
        if (!hotRes.ok) { solveStatus_ = QStringLiteral("Hot outlet: ") + hotRes.status; emit resultsChanged(); return; }

        Q_kW      = Q_kJh / 3600.0;
        T_hotOut  = hotRes.T;
        T_coldOut = coldOutletTK_;
        V_hotOut  = hotRes.vapFrac;
        V_coldOut = coldRes.V;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else {
        status = QStringLiteral("Unknown spec mode: ") + specMode_;
    }

    if (!solveOk) {
        solveStatus_ = status;
        emit resultsChanged();
        return;
    }

    // Feasibility check: hot must cool, cold must heat
    if (T_hotOut >= T_hotIn) {
        solveStatus_ = QStringLiteral("Hot side heated instead of cooled — check duty sign or spec.");
        emit resultsChanged(); return;
    }
    if (T_coldOut <= T_coldIn) {
        solveStatus_ = QStringLiteral("Cold side cooled instead of heated — check duty sign or spec.");
        emit resultsChanged(); return;
    }

    // ── 4. LMTD and UA ───────────────────────────────────────────────────────
    const double lmtd = computeLMTD(T_hotIn, T_hotOut, T_coldIn, T_coldOut);
    double ua = std::numeric_limits<double>::quiet_NaN();
    if (!std::isnan(lmtd) && lmtd > 0.0)
        ua = (Q_kW * 1000.0) / lmtd;   // W/K  (Q in kW × 1000 → W)

    // Approach temperature (minimum terminal ΔT, counter-current)
    const double approach = std::min(T_hotIn - T_coldOut, T_hotOut - T_coldIn);

    // ── 5. Store ──────────────────────────────────────────────────────────────
    solved_             = true;
    calcDutyKW_         = Q_kW;
    calcHotOutTK_       = T_hotOut;
    calcColdOutTK_      = T_coldOut;
    calcHotOutVapFrac_  = V_hotOut;
    calcColdOutVapFrac_ = V_coldOut;
    calcLMTD_           = lmtd;
    calcUA_             = ua;
    calcApproachT_      = approach;
    solveStatus_        = status;

    emit solvedChanged();
    emit resultsChanged();

    pushResultsToOutletStreams_();
}

void HeatExchangerUnitState::pushResultsToOutletStreams_()
{
    MaterialStreamState* hotIn  = findStream(hotInStreamUnitId_);
    MaterialStreamState* coldIn = findStream(coldInStreamUnitId_);

    if (MaterialStreamState* hotOut = findStream(hotOutStreamUnitId_)) {
        if (hotIn) {
            hotOut->setFlowRateKgph(hotIn->flowRateKgph());
            if (hotIn->hasCustomComposition())
                hotOut->setCompositionStd(hotIn->compositionStd());
            const QString pkgId = hotIn->selectedFluidPackageId();
            if (!pkgId.isEmpty() && hotOut->selectedFluidPackageId() != pkgId)
                hotOut->setSelectedFluidPackageId(pkgId);
        }
        hotOut->setTemperatureK(calcHotOutTK_);
        hotOut->setPressurePa(hotIn ? hotIn->pressurePa() - hotSidePressureDropPa_ : hotIn->pressurePa());
    }

    if (MaterialStreamState* coldOut = findStream(coldOutStreamUnitId_)) {
        if (coldIn) {
            coldOut->setFlowRateKgph(coldIn->flowRateKgph());
            if (coldIn->hasCustomComposition())
                coldOut->setCompositionStd(coldIn->compositionStd());
            const QString pkgId = coldIn->selectedFluidPackageId();
            if (!pkgId.isEmpty() && coldOut->selectedFluidPackageId() != pkgId)
                coldOut->setSelectedFluidPackageId(pkgId);
        }
        coldOut->setTemperatureK(calcColdOutTK_);
        coldOut->setPressurePa(coldIn ? coldIn->pressurePa() - coldSidePressureDropPa_ : coldIn->pressurePa());
    }
}
