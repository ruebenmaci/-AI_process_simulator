#include "PumpUnitState.h"

#include "flowsheet/state/FlowsheetState.h"
#include "streams/state/StreamUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "fluid/FluidPackageManager.h"
#include "thermo/PH_PS_PT_TS_Flash.hpp"
#include "thermo/Enthalpy.hpp"
#include "thermo/pseudocomponents/FluidDefinition.hpp"
#include "thermo/ThermoConfig.hpp"

#include <QDebug>
#include <QDateTime>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

PumpUnitState::PumpUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void PumpUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Mirrors HeaterCoolerUnitState — feed and product are HARD requirements;
// the energy streams are optional (feature-equivalent display, not a solve
// blocker because the pump's shaft work is computed from the spec, not read
// from an energy stream input).
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus PumpUnitState::connectivityStatus() const
{
    const bool noFeed    = feedStreamUnitId_.isEmpty();
    const bool noProduct = productStreamUnitId_.isEmpty();
    if (noFeed && noProduct)
        return { 3, QStringLiteral("missing feed and product streams") };
    if (noFeed)
        return { 3, QStringLiteral("missing feed stream") };
    if (noProduct)
        return { 3, QStringLiteral("missing product stream") };
    return {};
}

void PumpUnitState::setConnectedFeedStreamUnitId(const QString& id)
{
    if (feedStreamUnitId_ == id) return;
    feedStreamUnitId_ = id;
    clearResults_();
    emit feedStreamChanged();
}

void PumpUnitState::setConnectedProductStreamUnitId(const QString& id)
{
    if (productStreamUnitId_ == id) return;
    productStreamUnitId_ = id;
    emit productStreamChanged();
}

void PumpUnitState::setConnectedEnergyInStreamUnitId(const QString& id)
{
    if (energyInStreamUnitId_ == id) return;
    energyInStreamUnitId_ = id;
    emit energyInStreamChanged();
}

void PumpUnitState::setConnectedEnergyOutStreamUnitId(const QString& id)
{
    if (energyOutStreamUnitId_ == id) return;
    energyOutStreamUnitId_ = id;
    emit energyOutStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters — clear results when user changes a spec
// ─────────────────────────────────────────────────────────────────────────────

void PumpUnitState::setSpecMode(const QString& v)
{
    if (specMode_ == v) return;
    specMode_ = v;
    clearResults_();
    emit specModeChanged();
}

void PumpUnitState::setOutletPressurePa(double v)
{
    if (qFuzzyCompare(outletPressurePa_, v)) return;
    outletPressurePa_ = v;
    clearResults_();
    emit outletPressurePaChanged();
}

void PumpUnitState::setDeltaPPa(double v)
{
    if (qFuzzyCompare(deltaPPa_, v)) return;
    deltaPPa_ = v;
    clearResults_();
    emit deltaPPaChanged();
}

void PumpUnitState::setPowerKW(double v)
{
    if (qFuzzyCompare(powerKW_, v)) return;
    powerKW_ = v;
    clearResults_();
    emit powerKWChanged();
}

void PumpUnitState::setAdiabaticEfficiency(double v)
{
    if (qFuzzyCompare(adiabaticEfficiency_, v)) return;
    adiabaticEfficiency_ = v;
    clearResults_();
    emit adiabaticEfficiencyChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

MaterialStreamState* PumpUnitState::activeFeedStream() const
{
    if (!flowsheetState_ || feedStreamUnitId_.isEmpty())
        return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(feedStreamUnitId_);
}

void PumpUnitState::clearResults_()
{
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_                = false;
    calcOutletPressurePa_  = 0.0;
    calcDeltaPPa_          = 0.0;
    calcPowerKW_           = 0.0;
    calcIdealPowerKW_      = 0.0;
    calcOutletTempK_       = 0.0;
    calcOutletVapFrac_     = 0.0;
    calcInletDensityKgM3_  = 0.0;
    solveStatus_.clear();
    statusLevel_           = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void PumpUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic / log helpers
// ─────────────────────────────────────────────────────────────────────────────

void PumpUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void PumpUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    appendRunLogLine_(QStringLiteral("[state][error] ") + message);
    statusLevel_ = StatusLevel::Fail;
}

void PumpUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    appendRunLogLine_(QStringLiteral("[state][warn] ") + message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void PumpUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
    appendRunLogLine_(QStringLiteral("[state][info] ") + message);
}

void PumpUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — incompressible-liquid pump model.
//
//   1. Determine ΔP and P_out from the spec mode.
//      • outletPressure → ΔP = P_out − P_in
//      • deltaP         → P_out = P_in + ΔP
//      • power          → ΔP = W·η·ρ/ṁ, P_out = P_in + ΔP
//   2. W_ideal = ṁ · ΔP / ρ_in       [W]
//      W_shaft = W_ideal / η_p       [W]
//      ΔH      = W_shaft / ṁ         [J/kg → kJ/kg]
//      H_out   = H_in + ΔH
//   3. PH-flash at (P_out, H_out) → outlet T and V.
//
// Numerous warnings are emitted post-solve: feed not liquid, very low η,
// zero/negative ΔP, two-phase outlet (cavitation flag), etc.
// ─────────────────────────────────────────────────────────────────────────────

void PumpUnitState::solve()
{
    // ── 0. Fresh solve — clear previous artifacts ────────────────────────────
    resetSolveArtifacts_();

    auto logSink = [this](const std::string& s) {
        runLogModel_.appendLine(QString::fromStdString(s));
    };

    const QString unitLabel = name().isEmpty() ? id() : name();
    appendRunLogLine_(QStringLiteral("[state] ─── Solving pump \"")
                      + unitLabel
                      + QStringLiteral("\" (spec: ") + specMode_
                      + QStringLiteral(") ───"));

    // ── 1. Gather inlet stream ───────────────────────────────────────────────
    MaterialStreamState* feed = activeFeedStream();
    if (!feed) {
        solveStatus_ = QStringLiteral("No feed stream connected.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    const double T_in  = feed->temperatureK();
    const double P_in  = feed->pressurePa();
    const double mdot  = feed->flowRateKgph();   // kg/h
    const double H_in  = feed->enthalpyKJkg();   // kJ/kg
    const double V_in  = feed->vaporFraction();

    if (mdot <= 0.0 || std::isnan(mdot)) {
        solveStatus_ = QStringLiteral("Feed stream flow rate is zero or undefined.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (std::isnan(T_in) || std::isnan(P_in) || std::isnan(H_in)) {
        solveStatus_ = QStringLiteral("Feed stream conditions are not fully defined.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // Density of the incoming fluid. The pump model assumes incompressible
    // liquid, so we want the liquid density specifically. Fall back to the
    // bulk-density estimate if the phase-props rho hasn't been computed yet
    // (can happen on a freshly-created stream that hasn't been flashed).
    double rho_in = feed->liquidDensityKgM3();
    if (!(rho_in > 0.0) || std::isnan(rho_in)) {
        rho_in = feed->estimatedBulkDensityKgM3();
    }
    if (!(rho_in > 0.0) || std::isnan(rho_in)) {
        solveStatus_ = QStringLiteral("Feed stream liquid density unavailable. "
                                      "Solve the upstream stream first.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    calcInletDensityKgM3_ = rho_in;

    appendRunLogLine_(QStringLiteral("[state] Feed: T=%1 K, P=%2 Pa, mdot=%3 kg/h, H=%4 kJ/kg, ρ=%5 kg/m³, V=%6")
                      .arg(T_in,   0, 'f', 2).arg(P_in,   0, 'f', 0)
                      .arg(mdot,   0, 'f', 2).arg(H_in,   0, 'f', 2)
                      .arg(rho_in, 0, 'f', 2).arg(V_in,   0, 'f', 4));

    // Pre-solve sanity: η must be in (0, 1].
    if (!(adiabaticEfficiency_ > 0.0 && adiabaticEfficiency_ <= 1.0)) {
        solveStatus_ = QStringLiteral("Adiabatic efficiency must be in the range (0, 1].");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    // Mass-flow in SI for the work calculation
    const double mdot_si = mdot / 3600.0;        // kg/s

    // ── 2. Determine ΔP and P_out from the spec mode ─────────────────────────
    double dP   = 0.0;
    double Pout = 0.0;

    if (specMode_ == QStringLiteral("outletPressure")) {
        Pout = outletPressurePa_;
        dP   = Pout - P_in;
    } else if (specMode_ == QStringLiteral("deltaP")) {
        dP   = deltaPPa_;
        Pout = P_in + dP;
    } else if (specMode_ == QStringLiteral("power")) {
        // Inverting the work equation for ΔP given a shaft-power spec:
        //   ΔP = W_shaft · η_p · ρ / ṁ
        const double W_shaft_si = powerKW_ * 1000.0;   // W
        dP   = W_shaft_si * adiabaticEfficiency_ * rho_in / mdot_si;
        Pout = P_in + dP;
    } else {
        solveStatus_ = QStringLiteral("Unknown spec mode: ") + specMode_;
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    if (Pout <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa. Check spec.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (dP < 0.0) {
        // Pumps are pressure raisers by definition. Treat negative ΔP as a
        // hard error — the user wants an expander/turbine, not a pump.
        solveStatus_ = QStringLiteral("Pump ΔP is negative — pumps cannot drop pressure. "
                                      "Use a Valve or Expander.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // ── 3. Power balance ─────────────────────────────────────────────────────
    //   W_ideal = ṁ · ΔP / ρ        (incompressible-liquid hydraulic work, W)
    //   W_shaft = W_ideal / η_p     (W)
    //   ΔH      = W_shaft / ṁ       (J/kg → /1000 = kJ/kg)
    const double W_ideal_si = mdot_si * dP / rho_in;     // W
    const double W_shaft_si = W_ideal_si / adiabaticEfficiency_;
    const double dH_kJkg    = (W_shaft_si / mdot_si) / 1000.0;

    const double H_out      = H_in + dH_kJkg;            // kJ/kg

    appendRunLogLine_(QStringLiteral("[state] ΔP=%1 Pa, W_ideal=%2 kW, W_shaft=%3 kW, ΔH=%4 kJ/kg")
                      .arg(dP,             0, 'f', 0)
                      .arg(W_ideal_si/1e3, 0, 'f', 4)
                      .arg(W_shaft_si/1e3, 0, 'f', 4)
                      .arg(dH_kJkg,        0, 'f', 4));

    // ── 4. Get fluid thermo info from the feed stream ────────────────────────
    thermo::ThermoConfig thermoConfig;
    std::vector<Component> components;
    std::vector<std::vector<double>> kij;
    std::vector<double> z;

    {
        const FluidDefinition& fd = feed->fluidDefinition();
        components = fd.thermo.components;
        kij        = fd.thermo.kij;

        if (components.empty()) {
            solveStatus_ = QStringLiteral("Feed stream fluid package not resolved.");
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }

        auto* fpm = FluidPackageManager::instance();
        thermoConfig = fpm
            ? fpm->thermoConfigForPackageResolved(feed->selectedFluidPackageId())
            : thermo::makeThermoConfig("PRSV");

        const std::vector<double>& wt = feed->compositionStd();
        if (wt.size() != components.size()) {
            solveStatus_ = QStringLiteral("Composition / component count mismatch.");
            emitError_(solveStatus_);
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
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    appendRunLogLine_(QStringLiteral("[state] Thermo: %1 components, EOS %2")
                      .arg(components.size())
                      .arg(QString::fromStdString(thermoConfig.eosName)));

    // ── 5. PH flash at (P_out, H_out) for outlet T, V ────────────────────────
    FlashPHInput phi;
    phi.Htarget    = H_out;
    phi.z          = z;
    phi.P          = Pout;
    phi.Tseed      = T_in;
    phi.components = &components;
    phi.thermoConfig = thermoConfig;
    phi.kij        = &kij;
    phi.log        = logSink;
    phi.logLevel   = LogLevel::Summary;

    const FlashPHResult res = flashPH(phi);

    bool   solveOk = false;
    double T_out   = std::numeric_limits<double>::quiet_NaN();
    double V_out   = std::numeric_limits<double>::quiet_NaN();
    QString status;

    if (res.status != "ok") {
        status = QStringLiteral("PH flash failed: ") + QString::fromStdString(res.status);
        emitError_(status);
    } else {
        T_out   = res.T;
        V_out   = res.V;
        solveOk = true;
        status  = QStringLiteral("OK");
    }

    // ── 6. Store results ─────────────────────────────────────────────────────
    solved_                = solveOk;
    calcOutletPressurePa_  = Pout;
    calcDeltaPPa_          = dP;
    calcIdealPowerKW_      = W_ideal_si / 1000.0;
    calcPowerKW_           = W_shaft_si / 1000.0;
    calcOutletTempK_       = T_out;
    calcOutletVapFrac_     = V_out;
    solveStatus_           = status;

    // ── 7. Post-solve diagnostics ────────────────────────────────────────────
    if (solveOk) {
        appendRunLogLine_(QStringLiteral("[state] Solved: P_out=%1 Pa, T_out=%2 K, W=%3 kW, ΔT=%4 K")
                          .arg(Pout,        0, 'f', 0)
                          .arg(T_out,       0, 'f', 3)
                          .arg(calcPowerKW_,0, 'f', 4)
                          .arg(T_out - T_in,0, 'f', 3));

        // (a) Feed not liquid — pump model assumes incompressible liquid.
        //     Even a small vapor fraction at the pump suction will cause
        //     cavitation in real life and our incompressible math will be
        //     materially wrong.
        if (V_in > 1.0e-4) {
            emitWarn_(QStringLiteral(
                "Feed has vapour fraction %1 — pump model assumes liquid. "
                "Real-world cavitation likely.").arg(V_in, 0, 'f', 4));
        }

        // (b) Outlet has flashed to two-phase — usually a sign that the
        //     PH flash carried us across the bubble line. Indicates the
        //     feed was at/above saturation, which the (a) check would
        //     normally have flagged at suction; we emit a separate
        //     diagnostic here in case (a) didn't fire.
        if (V_out > 1.0e-4 && V_out < 1.0 - 1.0e-4) {
            emitWarn_(QStringLiteral(
                "Outlet is two-phase (V=%1) — pump may be cavitating "
                "or the feed was near saturation.").arg(V_out, 0, 'f', 4));
        } else if (V_out > 1.0 - 1.0e-4) {
            emitError_(QStringLiteral(
                "Outlet is fully vapour. The pump is moving vapor, not liquid — "
                "incompressible model is invalid. Use a Compressor instead."));
            // Don't escalate to Fail though — the math ran. Downgrade:
            // emitError already escalated. We could downgrade but it's safer
            // to leave it red so the user notices.
        }

        // (c) Very low η — possible user data-entry error (fraction vs %).
        if (adiabaticEfficiency_ < 0.10) {
            emitWarn_(QStringLiteral(
                "Adiabatic efficiency is %1 — unusually low. "
                "Did you mean a percentage (e.g. 0.75 not 75)?").arg(adiabaticEfficiency_, 0, 'f', 3));
        }

        // (d) Trivial / no-op solve.
        if (dP < 1.0) {
            emitWarn_(QStringLiteral(
                "Pump ΔP is essentially zero — unit is a no-op."));
        }

        // (e) Extreme ΔP — sanity check (over 200 bar is plausible only
        //     for high-pressure injection pumps; warn so the user notices
        //     a potential typo).
        if (dP > 2.0e7) {
            emitWarn_(QStringLiteral(
                "Pump ΔP exceeds 200 bar — verify the spec, this is "
                "high-pressure-pump territory."));
        }

        // (f) Outlet pressure dipping below 1 kPa — was a copy-paste of the
        //     heater check; pumps with negative ΔP are blocked above, so
        //     this only fires if P_in itself was tiny.
        if (Pout > 0.0 && Pout < 1000.0) {
            emitWarn_(QStringLiteral(
                "Outlet pressure (%1 Pa) is below 1 kPa — verify feed pressure.")
                .arg(Pout, 0, 'f', 0));
        }

        // ── 8. Finalize status level ─────────────────────────────────────────
        if (statusLevel_ == StatusLevel::None)
            statusLevel_ = StatusLevel::Ok;

        if (statusLevel_ == StatusLevel::Ok) {
            emitInfo_(QStringLiteral("Solve completed successfully."));
        }
    } else {
        appendRunLogLine_(QStringLiteral("[state] Solve failed: ") + status);
    }

    emit solvedChanged();
    emit resultsChanged();

    // ── 9. Push results to product stream if connected ───────────────────────
    if (solveOk)
        pushResultsToProductStream_();
}

void PumpUnitState::pushResultsToProductStream_()
{
    if (!flowsheetState_ || productStreamUnitId_.isEmpty())
        return;

    MaterialStreamState* product = flowsheetState_->findMaterialStreamByUnitId(productStreamUnitId_);
    if (!product)
        return;

    MaterialStreamState* feed = activeFeedStream();
    if (!feed)
        return;

    product->setFlowRateKgph(feed->flowRateKgph());
    product->setTemperatureK(calcOutletTempK_);
    product->setPressurePa(calcOutletPressurePa_);

    if (feed->hasCustomComposition())
        product->setCompositionStd(feed->compositionStd());

    const QString pkgId = feed->selectedFluidPackageId();
    if (!pkgId.isEmpty() && product->selectedFluidPackageId() != pkgId)
        product->setSelectedFluidPackageId(pkgId);
}
