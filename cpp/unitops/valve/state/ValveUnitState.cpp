#include "ValveUnitState.h"

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

ValveUnitState::ValveUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void ValveUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Mirrors PumpUnitState — feed and product are HARD requirements. There are
// no energy streams on a valve.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus ValveUnitState::connectivityStatus() const
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

void ValveUnitState::setConnectedFeedStreamUnitId(const QString& id)
{
    if (feedStreamUnitId_ == id) return;
    feedStreamUnitId_ = id;
    clearResults_();
    emit feedStreamChanged();
}

void ValveUnitState::setConnectedProductStreamUnitId(const QString& id)
{
    if (productStreamUnitId_ == id) return;
    productStreamUnitId_ = id;
    emit productStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters — clear results when user changes a spec
// ─────────────────────────────────────────────────────────────────────────────

void ValveUnitState::setSpecMode(const QString& v)
{
    if (specMode_ == v) return;
    specMode_ = v;
    clearResults_();
    emit specModeChanged();
}

void ValveUnitState::setOutletPressurePa(double v)
{
    if (qFuzzyCompare(outletPressurePa_, v)) return;
    outletPressurePa_ = v;
    clearResults_();
    emit outletPressurePaChanged();
}

void ValveUnitState::setDeltaPPa(double v)
{
    if (qFuzzyCompare(deltaPPa_, v)) return;
    deltaPPa_ = v;
    clearResults_();
    emit deltaPPaChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

MaterialStreamState* ValveUnitState::activeFeedStream() const
{
    if (!flowsheetState_ || feedStreamUnitId_.isEmpty())
        return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(feedStreamUnitId_);
}

void ValveUnitState::clearResults_()
{
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_                = false;
    calcOutletPressurePa_  = 0.0;
    calcDeltaPPa_          = 0.0;
    calcOutletTempK_       = 0.0;
    calcOutletVapFrac_     = 0.0;
    calcDeltaTK_           = 0.0;
    calcInletVapFrac_      = 0.0;
    solveStatus_.clear();
    statusLevel_           = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void ValveUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic / log helpers
// ─────────────────────────────────────────────────────────────────────────────

void ValveUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void ValveUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    appendRunLogLine_(QStringLiteral("[state][error] ") + message);
    statusLevel_ = StatusLevel::Fail;
}

void ValveUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    appendRunLogLine_(QStringLiteral("[state][warn] ") + message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void ValveUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
    appendRunLogLine_(QStringLiteral("[state][info] ") + message);
}

void ValveUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — adiabatic isenthalpic throttle (Joule-Thomson expansion).
//
//   1. Determine ΔP_drop and P_out from the spec mode.
//      • outletPressure → ΔP_drop = P_in − P_out
//      • deltaP         → P_out   = P_in − ΔP_drop
//   2. H_out = H_in   (no shaft work, no heat exchange — this is the entire
//                      thermodynamic content of the valve model)
//   3. PH-flash at (P_out, H_in) → outlet T and V.
//
// Diagnostics emitted post-solve: zero/negative drop (no-op or back-flow),
// extremely large drop (sanity check), feed already two-phase (still solves
// fine, but flagged so the user knows), inlet pressure ≤ outlet pressure
// (treated as Fail — physically impossible for a passive throttle).
// ─────────────────────────────────────────────────────────────────────────────

void ValveUnitState::solve()
{
    // ── 0. Fresh solve — clear previous artifacts ────────────────────────────
    resetSolveArtifacts_();

    auto logSink = [this](const std::string& s) {
        runLogModel_.appendLine(QString::fromStdString(s));
    };

    const QString unitLabel = name().isEmpty() ? id() : name();
    appendRunLogLine_(QStringLiteral("[state] ─── Solving valve \"")
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

    calcInletVapFrac_ = V_in;

    appendRunLogLine_(QStringLiteral("[state] Feed: T=%1 K, P=%2 Pa, mdot=%3 kg/h, H=%4 kJ/kg, V=%5")
                      .arg(T_in,   0, 'f', 2).arg(P_in,   0, 'f', 0)
                      .arg(mdot,   0, 'f', 2).arg(H_in,   0, 'f', 2)
                      .arg(V_in,   0, 'f', 4));

    // ── 2. Determine ΔP_drop and P_out from the spec mode ────────────────────
    //
    // dP is stored consistently as a POSITIVE pressure drop (P_in − P_out)
    // throughout the rest of the function. The user-facing deltaPPa_ field
    // already follows this convention.
    double dP   = 0.0;     // pressure drop (positive = expansion)
    double Pout = 0.0;

    if (specMode_ == QStringLiteral("outletPressure")) {
        Pout = outletPressurePa_;
        dP   = P_in - Pout;
    } else if (specMode_ == QStringLiteral("deltaP")) {
        dP   = deltaPPa_;
        Pout = P_in - dP;
    } else {
        solveStatus_ = QStringLiteral("Unknown spec mode: ") + specMode_;
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    if (Pout <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa. Check spec — "
                                      "ΔP drop exceeds inlet pressure.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (dP < 0.0) {
        // A passive throttle cannot raise pressure. The user wants a pump.
        solveStatus_ = QStringLiteral("Valve ΔP drop is negative — valves cannot raise pressure. "
                                      "Use a Pump or Compressor instead.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    appendRunLogLine_(QStringLiteral("[state] ΔP_drop=%1 Pa, P_out=%2 Pa (isenthalpic: H_out=H_in=%3 kJ/kg)")
                      .arg(dP,    0, 'f', 0)
                      .arg(Pout,  0, 'f', 0)
                      .arg(H_in,  0, 'f', 4));

    // ── 3. Get fluid thermo info from the feed stream ────────────────────────
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

    // ── 4. PH flash at (P_out, H_in) for outlet T, V ─────────────────────────
    //
    // The "isenthalpic" part of the valve model is really the only
    // thermodynamic statement: H_out = H_in. The PH flash at the lower
    // pressure delivers everything else — outlet T (whether JT cooling or
    // heating dominates), outlet V (whether the stream flashed across the
    // bubble line during expansion), and per-phase splits (consumed
    // downstream by the product stream when we push results).
    FlashPHInput phi;
    phi.Htarget    = H_in;
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

    // ── 5. Store results ─────────────────────────────────────────────────────
    solved_                = solveOk;
    calcOutletPressurePa_  = Pout;
    calcDeltaPPa_          = dP;
    calcOutletTempK_       = T_out;
    calcOutletVapFrac_     = V_out;
    calcDeltaTK_           = solveOk ? (T_out - T_in)
                                     : std::numeric_limits<double>::quiet_NaN();
    solveStatus_           = status;

    // ── 6. Post-solve diagnostics ────────────────────────────────────────────
    if (solveOk) {
        appendRunLogLine_(QStringLiteral("[state] Solved: P_out=%1 Pa, T_out=%2 K, ΔT=%3 K, V_out=%4")
                          .arg(Pout,            0, 'f', 0)
                          .arg(T_out,           0, 'f', 3)
                          .arg(T_out - T_in,    0, 'f', 3)
                          .arg(V_out,           0, 'f', 4));

        // (a) Trivial / no-op — user supplied zero or near-zero drop.
        //     Not a hard error (the result is valid: P_out ≈ P_in, T_out
        //     ≈ T_in, no flashing) but clearly not what the user intended.
        if (dP < 1.0) {
            emitWarn_(QStringLiteral(
                "Valve ΔP drop is essentially zero — unit is a no-op."));
        }

        // (b) Outlet pressure dipping below 1 kPa — physically possible
        //     (vacuum service), but more often a sign that the user typed
        //     the drop in bar without the trailing zero. Worth a flag.
        if (Pout > 0.0 && Pout < 1000.0) {
            emitWarn_(QStringLiteral(
                "Outlet pressure (%1 Pa) is below 1 kPa — verify the spec.")
                .arg(Pout, 0, 'f', 0));
        }

        // (c) Extreme ΔP — sanity check. Anything above 200 bar drop is
        //     unusual outside high-pressure letdown service (e.g. a wellhead
        //     choke or a HP→LP separator letdown).
        if (dP > 2.0e7) {
            emitWarn_(QStringLiteral(
                "Valve ΔP drop exceeds 200 bar — verify the spec, this is "
                "high-pressure-letdown territory."));
        }

        // (d) Feed is already two-phase. The flash handles this correctly
        //     — partial vaporization of an already-mixed feed is well-
        //     defined — but it's worth telling the user, since a vapor-
        //     fraction step on the inlet sometimes indicates an upstream
        //     spec wasn't set the way the user thought it was.
        if (V_in > 1.0e-4 && V_in < 1.0 - 1.0e-4) {
            emitInfo_(QStringLiteral(
                "Feed is two-phase (V=%1) — valve still solves; outlet phase "
                "split reflects the post-throttle equilibrium.").arg(V_in, 0, 'f', 4));
        }

        // (e) Significant flashing across the valve — the textbook letdown
        //     scenario. We surface this as INFO rather than warn, since it's
        //     the design intent in many valve applications. Threshold of 1 %
        //     vapor swing avoids spurious noise on a barely-saturated feed.
        if (V_out - V_in > 0.01) {
            emitInfo_(QStringLiteral(
                "Significant flashing across the valve: V_in=%1 → V_out=%2 "
                "(ΔV=%3). Two-phase letdown — check downstream piping for "
                "slug-flow / erosion concerns.")
                .arg(V_in,         0, 'f', 4)
                .arg(V_out,        0, 'f', 4)
                .arg(V_out - V_in, 0, 'f', 4));
        }

        // (f) JT temperature rise — uncommon but possible (e.g. H₂, He near
        //     room T). Worth noting because it surprises people who expect
        //     valves to always cool the stream.
        if (T_out > T_in + 0.1) {
            emitInfo_(QStringLiteral(
                "Outlet T (%1 K) exceeds inlet T (%2 K) by %3 K — fluid is "
                "above its JT inversion temperature for this drop.")
                .arg(T_out,        0, 'f', 2)
                .arg(T_in,         0, 'f', 2)
                .arg(T_out - T_in, 0, 'f', 3));
        }

        // ── 7. Finalize status level ─────────────────────────────────────────
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

    // ── 8. Push results to product stream if connected ───────────────────────
    if (solveOk)
        pushResultsToProductStream_();
}

void ValveUnitState::pushResultsToProductStream_()
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
