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
#include <QDateTime>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

HeaterCoolerUnitState::HeaterCoolerUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Both feed and product are HARD requirements: a heater/cooler can't solve
// without knowing where its inlet stream comes from, and there's nowhere
// for the outlet conditions to land if the product stream isn't connected.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus HeaterCoolerUnitState::connectivityStatus() const
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
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_               = false;
    calcDutyKW_           = 0.0;
    calcOutletTempK_      = 0.0;
    calcOutletVapFrac_    = 0.0;
    calcOutletPressurePa_ = 0.0;
    solveStatus_.clear();
    statusLevel_          = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void HeaterCoolerUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic / log helpers
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void HeaterCoolerUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    appendRunLogLine_(QStringLiteral("[state][error] ") + message);
    // Errors always escalate to Fail.
    statusLevel_ = StatusLevel::Fail;
}

void HeaterCoolerUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    appendRunLogLine_(QStringLiteral("[state][warn] ") + message);
    // Warn only escalates if we are not already in Fail.
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void HeaterCoolerUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
    appendRunLogLine_(QStringLiteral("[state][info] ") + message);
    // Info never changes statusLevel_.
}

void HeaterCoolerUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
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
//
// After the solve we run post-hoc checks for warnings (duty sign flipped,
// phase transition occurring, extreme outlet T, etc.) and report them via
// diagnosticsModel_. The final statusLevel_ is None/Ok/Warn/Fail depending
// on what was emitted.
// ─────────────────────────────────────────────────────────────────────────────

void HeaterCoolerUnitState::solve()
{
    // ── 0. Fresh solve — clear previous artifacts ─────────────────────────────
    resetSolveArtifacts_();

    // Thermo log sink — captures LogLevel::Summary lines into the RunLogModel.
    // We prefix thermo lines so the Thermo Log is easy to filter vs [state] lines.
    auto logSink = [this](const std::string& s) {
        runLogModel_.appendLine(QString::fromStdString(s));
    };

    const QString unitLabel = name().isEmpty() ? id() : name();
    appendRunLogLine_(QStringLiteral("[state] ─── Solving ") + type()
                      + QStringLiteral(" \"") + unitLabel
                      + QStringLiteral("\" (spec: ") + specMode_
                      + QStringLiteral(") ───"));

    // ── 1. Gather inlet stream ────────────────────────────────────────────────
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
    const double H_in  = feed->enthalpyKJkg();   // kJ/kg  (mixture)

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

    appendRunLogLine_(QStringLiteral("[state] Feed: T=%1 K, P=%2 Pa, mdot=%3 kg/h, H=%4 kJ/kg")
                      .arg(T_in, 0, 'f', 2).arg(P_in, 0, 'f', 0)
                      .arg(mdot, 0, 'f', 2).arg(H_in, 0, 'f', 2));

    // Outlet pressure
    const double P_out = P_in - pressureDropPa_;
    if (P_out <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa. Reduce ΔP.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (pressureDropPa_ < 0.0) {
        // Negative ΔP means the unit is a pressure-raiser — unusual for a
        // heater/cooler. Not fatal, but worth flagging.
        emitWarn_(QStringLiteral("Pressure drop is negative — outlet pressure > inlet pressure."));
    }

    // ── 2. Get fluid thermo info from the feed stream ─────────────────────────
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
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }

        auto* fpm = FluidPackageManager::instance();
        thermoConfig = fpm
            ? fpm->thermoConfigForPackageResolved(feed->selectedFluidPackageId())
            : thermo::makeThermoConfig("PRSV");

        // Convert mass fractions → mole fractions
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

    // ── Pre-solve feasibility checks for specific spec modes ─────────────────
    if (specMode_ == QStringLiteral("vaporFraction")) {
        if (outletVaporFraction_ < 0.0 || outletVaporFraction_ > 1.0) {
            solveStatus_ = QStringLiteral("Outlet vapor fraction must be between 0 and 1.");
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }
    }

    // Flag heater/cooler type vs duty sign mismatch BEFORE solving (duty spec).
    // A "heater" with negative duty will actually cool its stream; a "cooler"
    // with positive duty will heat it. This is a user-spec error worth warning
    // about but isn't a solve-blocker (the math is fine).
    const bool isCoolerType = (type() == QStringLiteral("cooler"));
    if (specMode_ == QStringLiteral("duty")) {
        if (isCoolerType && dutyKW_ > 0.0) {
            emitWarn_(QStringLiteral("Cooler duty spec is positive — the stream will be heated, not cooled."));
        } else if (!isCoolerType && dutyKW_ < 0.0) {
            emitWarn_(QStringLiteral("Heater duty spec is negative — the stream will be cooled, not heated."));
        }
    }

    // ── 3. Solve by spec mode ─────────────────────────────────────────────────
    double Q_kW        = 0.0;
    double T_out       = std::numeric_limits<double>::quiet_NaN();
    double V_out       = std::numeric_limits<double>::quiet_NaN();
    bool   solveOk     = false;
    QString status;

    if (specMode_ == QStringLiteral("temperature")) {
        T_out = outletTemperatureK_;
        const FlashPTResult res = flashPT(
            P_out, T_out, z, thermoConfig, &components, &kij,
            /*murphreeEtaV=*/1.0, /*log=*/logSink);

        const double H_out = res.H;
        if (std::isnan(H_out)) {
            status = QStringLiteral("PT flash failed at outlet conditions.");
            emitError_(status);
        } else {
            Q_kW   = mdot * (H_out - H_in) / 3600.0;
            V_out  = res.V;
            solveOk = true;
            status = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("duty")) {
        const double Q_kJh  = dutyKW_ * 3600.0;          // kJ/h
        const double H_out  = H_in + Q_kJh / mdot;       // kJ/kg

        FlashPHInput phi;
        phi.Htarget    = H_out;
        phi.z          = z;
        phi.P          = P_out;
        phi.Tseed      = T_in;
        phi.components = &components;
        phi.thermoConfig = thermoConfig;
        phi.kij        = &kij;
        phi.log        = logSink;
        phi.logLevel   = LogLevel::Summary;

        const FlashPHResult res = flashPH(phi);

        if (res.status != "ok") {
            status = QStringLiteral("PH flash failed: ") + QString::fromStdString(res.status);
            emitError_(status);
        } else {
            T_out   = res.T;
            V_out   = res.V;
            Q_kW    = dutyKW_;
            solveOk = true;
            status  = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("vaporFraction")) {
        const double V_target = outletVaporFraction_;
        double T_lo = std::max(200.0, T_in - 200.0);
        double T_hi = T_in + 300.0;
        double T_mid = 0.0;
        bool   bracketed = false;

        auto evalV = [&](double T) -> double {
            const FlashPTResult r = flashPT(P_out, T, z, thermoConfig, &components, &kij,
                                            /*murphreeEtaV=*/1.0, /*log=*/logSink);
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
                if ((T_hi - T_lo) < 0.05) break;
            }

            const FlashPTResult res = flashPT(P_out, T_mid, z, thermoConfig, &components, &kij,
                                              /*murphreeEtaV=*/1.0, /*log=*/logSink);
            T_out   = T_mid;
            V_out   = res.V;
            const double H_out = res.H;
            Q_kW    = mdot * (H_out - H_in) / 3600.0;
            solveOk = true;
            status  = QStringLiteral("OK");
        } else {
            status = QStringLiteral("Could not bracket vapor fraction. Check inlet conditions.");
            emitError_(status);
        }

    } else {
        status = QStringLiteral("Unknown spec mode: ") + specMode_;
        emitError_(status);
    }

    // ── 4. Store results ──────────────────────────────────────────────────────
    solved_               = solveOk;
    calcDutyKW_           = Q_kW;
    calcOutletTempK_      = T_out;
    calcOutletVapFrac_    = V_out;
    calcOutletPressurePa_ = P_out;
    solveStatus_          = status;

    // ── 5. Post-solve detection of warnings ──────────────────────────────────
    if (solveOk) {
        appendRunLogLine_(QStringLiteral("[state] Solved: Q=%1 kW, T_out=%2 K, V_out=%3")
                          .arg(Q_kW, 0, 'f', 3).arg(T_out, 0, 'f', 2)
                          .arg(V_out, 0, 'f', 4));

        // (a) Temperature-spec sanity: did the actual solve match the direction
        //     the user chose with the heater/cooler type?
        if (isCoolerType && Q_kW > 0.0) {
            emitWarn_(QStringLiteral("Cooler produced positive duty — stream was heated (check spec)."));
        } else if (!isCoolerType && Q_kW < 0.0) {
            emitWarn_(QStringLiteral("Heater produced negative duty — stream was cooled (check spec)."));
        }

        // (b) Trivial/no-op solve: outlet T essentially equals inlet T.
        const double dT = T_out - T_in;
        if (std::fabs(dT) < 0.01) {
            emitWarn_(QStringLiteral("Outlet temperature is within 0.01 K of inlet — unit is effectively a no-op."));
        }

        // (c) Phase transition occurring across the unit (inlet single-phase,
        //     outlet two-phase, or vice-versa). Informational, not a warning.
        const double feedV = feed->vaporFraction();
        const bool feedSingle  = !std::isnan(feedV) && (feedV <= 1.0e-6 || feedV >= 1.0 - 1.0e-6);
        const bool outletSingle = std::isnan(V_out) || (V_out <= 1.0e-6 || V_out >= 1.0 - 1.0e-6);
        if (feedSingle && !outletSingle) {
            emitInfo_(QStringLiteral("Phase transition: single-phase feed produces two-phase outlet (V=%1).")
                      .arg(V_out, 0, 'f', 4));
        } else if (!feedSingle && outletSingle) {
            emitInfo_(QStringLiteral("Phase transition: two-phase feed becomes single-phase at outlet."));
        }

        // (d) Extreme outlet T (below 150 K or above 1500 K) — usually
        //     indicates the user picked an impractical spec.
        if (T_out < 150.0) {
            emitWarn_(QStringLiteral("Outlet temperature (%1 K) is below cryogenic range — verify spec.")
                      .arg(T_out, 0, 'f', 2));
        } else if (T_out > 1500.0) {
            emitWarn_(QStringLiteral("Outlet temperature (%1 K) exceeds 1500 K — verify spec.")
                      .arg(T_out, 0, 'f', 2));
        }

        // (e) Very-low outlet pressure (below 1 kPa but above 0) — not fatal
        //     but worth flagging. Below-zero would have errored earlier.
        if (P_out > 0.0 && P_out < 1000.0) {
            emitWarn_(QStringLiteral("Outlet pressure (%1 Pa) is below 1 kPa — deep vacuum, verify ΔP.")
                      .arg(P_out, 0, 'f', 0));
        }

        // ── 6. Finalize status level ─────────────────────────────────────────
        // If no warn/error/info was escalated, we are cleanly Ok.
        if (statusLevel_ == StatusLevel::None)
            statusLevel_ = StatusLevel::Ok;

        // Informational: a brief success summary for the Diagnostics panel so
        // the user always sees a row even on a clean solve.
        if (statusLevel_ == StatusLevel::Ok) {
            emitInfo_(QStringLiteral("Solve completed successfully."));
        }
    } else {
        appendRunLogLine_(QStringLiteral("[state] Solve failed: ") + status);
        // statusLevel_ was already escalated to Fail by emitError_().
    }

    emit solvedChanged();
    emit resultsChanged();

    // ── 7. Push results to product stream if connected ────────────────────────
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
