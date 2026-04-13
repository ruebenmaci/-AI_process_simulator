#include "HeaterCoolerUnitState.h"

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

HeaterCoolerUnitState::HeaterCoolerUnitState(QObject* parent)
    : ProcessUnitState(parent)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

void HeaterCoolerUnitState::setConnectedFeedStreamUnitId(const QString& id)
{
    if (feedStreamUnitId_ == id) return;
    feedStreamUnitId_ = id;
    clearResults_();
    emit feedStreamChanged();
}

void HeaterCoolerUnitState::setConnectedProductStreamUnitId(const QString& id)
{
    if (productStreamUnitId_ == id) return;
    productStreamUnitId_ = id;
    emit productStreamChanged();
}

void HeaterCoolerUnitState::setConnectedEnergyInStreamUnitId(const QString& id)
{
    if (energyInStreamUnitId_ == id) return;
    energyInStreamUnitId_ = id;
    emit energyInStreamChanged();
}

void HeaterCoolerUnitState::setConnectedEnergyOutStreamUnitId(const QString& id)
{
    if (energyOutStreamUnitId_ == id) return;
    energyOutStreamUnitId_ = id;
    emit energyOutStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters — mark dirty and clear old results when user changes a spec
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::setSpecMode(const QString& v)
{
    if (specMode_ == v) return;
    specMode_ = v;
    clearResults_();
    emit specModeChanged();
}

void HeaterCoolerUnitState::setOutletTemperatureK(double v)
{
    if (qFuzzyCompare(outletTemperatureK_, v)) return;
    outletTemperatureK_ = v;
    clearResults_();
    emit outletTemperatureKChanged();
}

void HeaterCoolerUnitState::setDutyKW(double v)
{
    if (qFuzzyCompare(dutyKW_, v)) return;
    dutyKW_ = v;
    clearResults_();
    emit dutyKWChanged();
}

void HeaterCoolerUnitState::setOutletVaporFraction(double v)
{
    if (qFuzzyCompare(outletVaporFraction_, v)) return;
    outletVaporFraction_ = v;
    clearResults_();
    emit outletVaporFractionChanged();
}

void HeaterCoolerUnitState::setPressureDropPa(double v)
{
    if (qFuzzyCompare(pressureDropPa_, v)) return;
    pressureDropPa_ = v;
    clearResults_();
    emit pressureDropPaChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

MaterialStreamState* HeaterCoolerUnitState::activeFeedStream() const
{
    if (!flowsheetState_ || feedStreamUnitId_.isEmpty())
        return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(feedStreamUnitId_);
}

void HeaterCoolerUnitState::clearResults_()
{
    if (!solved_) return;
    solved_               = false;
    calcDutyKW_           = 0.0;
    calcOutletTempK_      = 0.0;
    calcOutletVapFrac_    = 0.0;
    calcOutletPressurePa_ = 0.0;
    solveStatus_.clear();
    emit solvedChanged();
    emit resultsChanged();
}

void HeaterCoolerUnitState::reset()
{
    clearResults_();
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — pure energy balance, no geometry
//
// Governing equation:  Q = ṁ · (H_out − H_in)   [kJ/h → converted to kW]
//
// Branch on specMode_:
//
//   "temperature"   → PT flash at (P_out, T_out) → H_out → Q = ṁ·ΔH
//   "duty"          → H_out = H_in + Q·3600/ṁ → PH flash at P_out → T_out
//   "vaporFraction" → bisect T until flash V == target V_out → Q = ṁ·ΔH
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::solve()
{
    // ── 1. Gather inlet stream ────────────────────────────────────────────────
    MaterialStreamState* feed = activeFeedStream();
    if (!feed) {
        solveStatus_ = QStringLiteral("No feed stream connected.");
        emit resultsChanged();
        return;
    }

    const double T_in  = feed->temperatureK();
    const double P_in  = feed->pressurePa();
    const double mdot  = feed->flowRateKgph();   // kg/h
    const double H_in  = feed->enthalpyKJkg();   // kJ/kg  (mixture)

    if (mdot <= 0.0 || std::isnan(mdot)) {
        solveStatus_ = QStringLiteral("Feed stream flow rate is zero or undefined.");
        emit resultsChanged();
        return;
    }
    if (std::isnan(T_in) || std::isnan(P_in) || std::isnan(H_in)) {
        solveStatus_ = QStringLiteral("Feed stream conditions are not fully defined.");
        emit resultsChanged();
        return;
    }

    // Outlet pressure
    const double P_out = P_in - pressureDropPa_;
    if (P_out <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa. Reduce ΔP.");
        emit resultsChanged();
        return;
    }

    // ── 2. Get fluid thermo info from the feed stream ─────────────────────────
    // FluidDefinition holds the resolved component list and binary interaction
    // parameters.  ThermoConfig (EOS selection) comes from the fluid package
    // manager using the stream's assigned package ID.
    // compositionStd() returns mass fractions; we convert to mole fractions here.

    thermo::ThermoConfig thermoConfig;
    std::vector<Component> components;
    std::vector<std::vector<double>> kij;
    std::vector<double> z; // overall mole fractions

    {
        const FluidDefinition& fd = feed->fluidDefinition();
        components = fd.thermo.components;
        kij        = fd.thermo.kij;

        if (components.empty()) {
            solveStatus_ = QStringLiteral("Feed stream fluid package not resolved.");
            emit resultsChanged();
            return;
        }

        // Build ThermoConfig from the assigned fluid package
        auto* fpm = FluidPackageManager::instance();
        thermoConfig = fpm
            ? fpm->thermoConfigForPackageResolved(feed->selectedFluidPackageId())
            : thermo::makeThermoConfig("PRSV");

        // Convert mass fractions → mole fractions
        const std::vector<double>& wt = feed->compositionStd(); // mass fractions
        if (wt.size() != components.size()) {
            solveStatus_ = QStringLiteral("Composition / component count mismatch.");
            emit resultsChanged();
            return;
        }
        z.resize(wt.size(), 0.0);
        double sumMolar = 0.0;
        for (size_t i = 0; i < wt.size(); ++i) {
            z[i] = (components[i].MW > 0.0) ? wt[i] / components[i].MW : 0.0;
            sumMolar += z[i];
        }
        if (sumMolar > 0.0)
            for (auto& zi : z) zi /= sumMolar;
    }

    if (z.empty()) {
        solveStatus_ = QStringLiteral("Feed stream composition not set.");
        emit resultsChanged();
        return;
    }

    // ── 3. Solve by spec mode ─────────────────────────────────────────────────
    double Q_kW        = 0.0;
    double T_out       = std::numeric_limits<double>::quiet_NaN();
    double V_out       = std::numeric_limits<double>::quiet_NaN();
    bool   solveOk     = false;
    QString status;

    if (specMode_ == QStringLiteral("temperature")) {
        // ── Temperature spec: flash at (P_out, T_out) to get H_out ──────────
        T_out = outletTemperatureK_;
        const FlashPTResult res = flashPT(
            P_out, T_out, z, thermoConfig, &components, &kij);

        const double H_out = res.H;  // kJ/kg
        if (std::isnan(H_out)) {
            status = QStringLiteral("PT flash failed at outlet conditions.");
        } else {
            // Q = ṁ [kg/h] · ΔH [kJ/kg] / 3600 [s/h]  → kW
            Q_kW   = mdot * (H_out - H_in) / 3600.0;
            V_out  = res.V;
            solveOk = true;
            status = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("duty")) {
        // ── Duty spec: H_out = H_in + Q·3600/ṁ, then PH flash ──────────────
        const double Q_kJh  = dutyKW_ * 3600.0;          // kJ/h
        const double H_out  = H_in + Q_kJh / mdot;       // kJ/kg

        FlashPHInput phi;
        phi.Htarget    = H_out;
        phi.z          = z;
        phi.P          = P_out;
        phi.Tseed      = T_in;   // good initial guess
        phi.components = &components;
        phi.thermoConfig = thermoConfig;
        phi.kij        = &kij;

        const FlashPHResult res = flashPH(phi);

        if (res.status != "ok") {
            status = QStringLiteral("PH flash failed: ") + QString::fromStdString(res.status);
        } else {
            T_out   = res.T;
            V_out   = res.V;
            Q_kW    = dutyKW_;
            solveOk = true;
            status  = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("vaporFraction")) {
        // ── Vapor fraction spec: bisect T until flash V == target ────────────
        // Simple bounded bisection between dew and bubble point region.
        // Seed the bracket using the inlet T ± 200 K.
        const double V_target = outletVaporFraction_;
        double T_lo = std::max(200.0, T_in - 200.0);
        double T_hi = T_in + 300.0;
        double T_mid = 0.0;
        bool   bracketed = false;

        // Evaluate V at bracket ends
        auto evalV = [&](double T) -> double {
            const FlashPTResult r = flashPT(P_out, T, z, thermoConfig, &components, &kij);
            return r.V;
        };

        double V_lo = evalV(T_lo);
        double V_hi = evalV(T_hi);

        if ((V_lo - V_target) * (V_hi - V_target) < 0.0)
            bracketed = true;

        if (bracketed) {
            for (int iter = 0; iter < 60; ++iter) {
                T_mid = 0.5 * (T_lo + T_hi);
                const double V_mid = evalV(T_mid);
                if ((V_mid - V_target) * (V_lo - V_target) < 0.0)
                    T_hi = T_mid;
                else
                    T_lo = T_mid;
                if ((T_hi - T_lo) < 0.05) break;  // 0.05 K tolerance
            }

            const FlashPTResult res = flashPT(P_out, T_mid, z, thermoConfig, &components, &kij);
            T_out   = T_mid;
            V_out   = res.V;
            const double H_out = res.H;
            Q_kW    = mdot * (H_out - H_in) / 3600.0;
            solveOk = true;
            status  = QStringLiteral("OK");
        } else {
            status = QStringLiteral("Could not bracket vapor fraction. Check inlet conditions.");
        }

    } else {
        status = QStringLiteral("Unknown spec mode: ") + specMode_;
    }

    // ── 4. Store results ──────────────────────────────────────────────────────
    solved_               = solveOk;
    calcDutyKW_           = Q_kW;
    calcOutletTempK_      = T_out;
    calcOutletVapFrac_    = V_out;
    calcOutletPressurePa_ = P_out;
    solveStatus_          = status;

    emit solvedChanged();
    emit resultsChanged();

    // ── 5. Push results to product stream if connected ────────────────────────
    if (solveOk)
        pushResultsToProductStream_();
}

void HeaterCoolerUnitState::pushResultsToProductStream_()
{
    if (!flowsheetState_ || productStreamUnitId_.isEmpty())
        return;

    MaterialStreamState* product = flowsheetState_->findMaterialStreamByUnitId(productStreamUnitId_);
    if (!product)
        return;

    // Copy inlet flow and composition, update T and P
    MaterialStreamState* feed = activeFeedStream();
    if (!feed)
        return;

    product->setFlowRateKgph(feed->flowRateKgph());
    product->setTemperatureK(calcOutletTempK_);
    product->setPressurePa(calcOutletPressurePa_);

    // Copy composition from feed — composition is conserved (no reaction)
    if (feed->hasCustomComposition())
        product->setCompositionStd(feed->compositionStd());

    // Mirror fluid package
    const QString pkgId = feed->selectedFluidPackageId();
    if (!pkgId.isEmpty() && product->selectedFluidPackageId() != pkgId)
        product->setSelectedFluidPackageId(pkgId);
}
