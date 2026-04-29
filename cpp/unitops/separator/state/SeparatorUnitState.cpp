#include "SeparatorUnitState.h"

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

SeparatorUnitState::SeparatorUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void SeparatorUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Feed is HARD required. Vapor and liquid outlets are softer requirements:
// in a single-phase flash result one of them legitimately carries no flow,
// but the user still typically wants both stream nodes connected so they
// have a place to read the result. Surface as Warn rather than Fail.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus SeparatorUnitState::connectivityStatus() const
{
    if (feedStreamUnitId_.isEmpty())
        return { 3, QStringLiteral("missing feed stream") };

    const bool noVapor  = vaporStreamUnitId_.isEmpty();
    const bool noLiquid = liquidStreamUnitId_.isEmpty();
    if (noVapor && noLiquid)
        return { 2, QStringLiteral("missing vapor and liquid outlet streams") };
    if (noVapor)
        return { 2, QStringLiteral("missing vapor outlet stream") };
    if (noLiquid)
        return { 2, QStringLiteral("missing liquid outlet stream") };
    return {};
}

void SeparatorUnitState::setConnectedFeedStreamUnitId(const QString& id)
{
    if (feedStreamUnitId_ == id) return;
    feedStreamUnitId_ = id;
    clearResults_();
    emit feedStreamChanged();
}

void SeparatorUnitState::setConnectedVaporStreamUnitId(const QString& id)
{
    if (vaporStreamUnitId_ == id) return;
    vaporStreamUnitId_ = id;
    emit vaporStreamChanged();
}

void SeparatorUnitState::setConnectedLiquidStreamUnitId(const QString& id)
{
    if (liquidStreamUnitId_ == id) return;
    liquidStreamUnitId_ = id;
    emit liquidStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters — clear previous results when user changes a spec
// ─────────────────────────────────────────────────────────────────────────────

void SeparatorUnitState::setSpecMode(const QString& v)
{
    if (specMode_ == v) return;
    specMode_ = v;
    clearResults_();
    emit specModeChanged();
}

void SeparatorUnitState::setVesselTemperatureK(double v)
{
    if (qFuzzyCompare(vesselTemperatureK_, v)) return;
    vesselTemperatureK_ = v;
    clearResults_();
    emit vesselTemperatureKChanged();
}

void SeparatorUnitState::setDutyKW(double v)
{
    if (qFuzzyCompare(dutyKW_, v)) return;
    dutyKW_ = v;
    clearResults_();
    emit dutyKWChanged();
}

void SeparatorUnitState::setPressureDropPa(double v)
{
    if (qFuzzyCompare(pressureDropPa_, v)) return;
    pressureDropPa_ = v;
    clearResults_();
    emit pressureDropPaChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

MaterialStreamState* SeparatorUnitState::activeFeedStream() const
{
    if (!flowsheetState_ || feedStreamUnitId_.isEmpty())
        return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(feedStreamUnitId_);
}

void SeparatorUnitState::clearResults_()
{
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_                  = false;
    singlePhase_             = false;
    calcVesselTempK_         = 0.0;
    calcVesselPressurePa_    = 0.0;
    calcVaporMoleFrac_       = 0.0;
    calcVaporMassFrac_       = 0.0;
    calcVaporFlowKgph_       = 0.0;
    calcLiquidFlowKgph_      = 0.0;
    calcDutyKW_              = 0.0;
    calcVaporCompositionY_.clear();
    calcLiquidCompositionX_.clear();
    solveStatus_.clear();
    statusLevel_             = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void SeparatorUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic / log helpers — same pattern as HeaterCoolerUnitState
// ─────────────────────────────────────────────────────────────────────────────

void SeparatorUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void SeparatorUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    appendRunLogLine_(QStringLiteral("[state][error] ") + message);
    statusLevel_ = StatusLevel::Fail;
}

void SeparatorUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    appendRunLogLine_(QStringLiteral("[state][warn] ") + message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void SeparatorUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
    appendRunLogLine_(QStringLiteral("[state][info] ") + message);
}

void SeparatorUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — equilibrium flash, then mass split into vapor/liquid outlets
//
// Branches by spec mode:
//   "adiabatic"   → PH flash at (H_in, P_out)              → finds T, V
//   "duty"        → PH flash at (H_in + Q·3600/ṁ, P_out)   → finds T, V
//   "temperature" → PT flash at (P_out, T_user)            → finds V, back-calc Q
//
// All three branches yield (T_out, P_out, V_mole, x[], y[]) — the post-solve
// path then converts V_mole → V_mass (by composition·MW) and splits the feed
// mass flow into the two outlet streams.
//
// Single-phase result (V == 0 or V == 1) is treated as a warning, not an
// error: the "absent" outlet gets zero flow but inherits the feed composition
// so downstream consumers see a sensible state.
// ─────────────────────────────────────────────────────────────────────────────

void SeparatorUnitState::solve()
{
    // ── 0. Fresh solve — clear previous artifacts ─────────────────────────────
    resetSolveArtifacts_();

    auto logSink = [this](const std::string& s) {
        runLogModel_.appendLine(QString::fromStdString(s));
    };

    const QString unitLabel = name().isEmpty() ? id() : name();
    appendRunLogLine_(QStringLiteral("[state] ─── Solving separator \"%1\" (spec: %2) ───")
                      .arg(unitLabel).arg(specMode_));

    // ── 1. Gather inlet stream ────────────────────────────────────────────────
    MaterialStreamState* feed = activeFeedStream();
    if (!feed) {
        solveStatus_ = QStringLiteral("No feed stream connected.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    const double T_in = feed->temperatureK();
    const double P_in = feed->pressurePa();
    const double mdot = feed->flowRateKgph();   // kg/h
    const double H_in = feed->enthalpyKJkg();   // kJ/kg

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
        solveStatus_ = QStringLiteral("Vessel pressure ≤ 0 Pa. Reduce ΔP.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (pressureDropPa_ < 0.0) {
        emitWarn_(QStringLiteral("Pressure drop is negative — vessel pressure > inlet pressure."));
    }

    // ── 2. Resolve fluid thermo from feed stream ──────────────────────────────
    thermo::ThermoConfig thermoConfig;
    std::vector<Component> components;
    std::vector<std::vector<double>> kij;
    std::vector<double> z;          // overall mole fractions

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

        // Convert mass fractions → mole fractions (z is the overall mole basis
        // composition, which the flash routines all consume).
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

    // ── 3. Solve by spec mode ─────────────────────────────────────────────────
    double Q_kW    = 0.0;
    double T_out   = std::numeric_limits<double>::quiet_NaN();
    double V_mole  = std::numeric_limits<double>::quiet_NaN();
    std::vector<double> xVec, yVec;
    bool   solveOk = false;
    QString status;

    if (specMode_ == QStringLiteral("adiabatic")) {
        // Adiabatic flash: enthalpy preserved across the vessel boundary.
        // Q = 0, find T such that H_out(T, P_out, z) == H_in.
        FlashPHInput phi;
        phi.Htarget    = H_in;
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
            V_mole  = res.V;
            xVec    = res.x;
            yVec    = res.y;
            Q_kW    = 0.0;
            solveOk = true;
            status  = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("duty")) {
        const double Q_kJh = dutyKW_ * 3600.0;
        const double H_out = H_in + Q_kJh / mdot;

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
            V_mole  = res.V;
            xVec    = res.x;
            yVec    = res.y;
            Q_kW    = dutyKW_;
            solveOk = true;
            status  = QStringLiteral("OK");
        }

    } else if (specMode_ == QStringLiteral("temperature")) {
        T_out = vesselTemperatureK_;
        const FlashPTResult res = flashPT(
            P_out, T_out, z, thermoConfig, &components, &kij,
            /*murphreeEtaV=*/1.0, /*log=*/logSink);

        const double H_out = res.H;
        if (std::isnan(H_out)) {
            status = QStringLiteral("PT flash failed at vessel conditions.");
            emitError_(status);
        } else {
            V_mole = res.V;
            xVec   = res.x;
            yVec   = res.y;
            Q_kW   = mdot * (H_out - H_in) / 3600.0;
            solveOk = true;
            status = QStringLiteral("OK");
        }

    } else {
        status = QStringLiteral("Unknown spec mode: ") + specMode_;
        emitError_(status);
    }

    appendRunLogLine_(QStringLiteral("[state] Flash result: T_out=%1 K, V(mole)=%2, Q=%3 kW (%4)")
                      .arg(T_out, 0, 'f', 2).arg(V_mole, 0, 'f', 6)
                      .arg(Q_kW, 0, 'f', 3).arg(status));

    // ── 4. Post-flash: mole → mass conversion and outlet flow split ───────────
    if (solveOk) {
        // Clamp V_mole into [0, 1] for the mass-balance arithmetic below; the
        // flash can return slightly out-of-range values from numerical noise.
        const double Vmol = std::clamp(V_mole, 0.0, 1.0);

        // Compute the molecular weights of the vapor and liquid phases. If
        // the flash returned empty x/y (single-phase result), fall back to the
        // overall composition for the present phase.
        auto mwOfPhase = [&](const std::vector<double>& comp) -> double {
            double mw = 0.0;
            for (size_t i = 0; i < components.size() && i < comp.size(); ++i) {
                const double mwi = (components[i].MW > 0.0) ? components[i].MW : 200.0;
                mw += comp[i] * mwi;
            }
            return std::max(1.0, mw);
        };

        const bool phaseV_present = (Vmol > 1.0e-9);
        const bool phaseL_present = (Vmol < 1.0 - 1.0e-9);
        singlePhase_ = !(phaseV_present && phaseL_present);

        // If a phase is absent, the flash may have returned an empty composition
        // vector for it. Substitute the overall feed composition so downstream
        // state remains coherent (the absent stream will carry zero mass flow,
        // so its composition is informational only).
        if (yVec.size() != components.size()) yVec = z;
        if (xVec.size() != components.size()) xVec = z;

        const double MW_v = mwOfPhase(yVec);
        const double MW_l = mwOfPhase(xVec);

        // Mass-basis vapor fraction:
        //   V_mass = (V_mole · MW_v) / (V_mole · MW_v + (1 − V_mole) · MW_l)
        // This is exact for any V_mole in [0, 1].
        const double numerator   = Vmol * MW_v;
        const double denominator = numerator + (1.0 - Vmol) * MW_l;
        const double Vmass = (denominator > 1.0e-12) ? (numerator / denominator) : 0.0;

        const double mdotV = mdot * Vmass;
        const double mdotL = mdot - mdotV;

        // ── 5. Stash results ────────────────────────────────────────────────
        calcVesselTempK_       = T_out;
        calcVesselPressurePa_  = P_out;
        calcVaporMoleFrac_     = Vmol;
        calcVaporMassFrac_     = Vmass;
        calcVaporFlowKgph_     = mdotV;
        calcLiquidFlowKgph_    = mdotL;
        calcDutyKW_            = Q_kW;
        calcVaporCompositionY_ = yVec;   // mole fractions
        calcLiquidCompositionX_ = xVec;  // mole fractions
        solveStatus_           = status;
        solved_                = true;

        // ── 6. Post-solve diagnostics ───────────────────────────────────────

        // (a) Single-phase result — unit is acting as a pass-through. Warn,
        //     not error, since this can be a legitimate operating point.
        if (singlePhase_) {
            if (Vmol >= 1.0 - 1.0e-9) {
                emitWarn_(QStringLiteral("Flash result is all vapor — liquid outlet has zero flow."));
            } else {
                emitWarn_(QStringLiteral("Flash result is all liquid — vapor outlet has zero flow."));
            }
        }

        // (b) Phase transition (informational): tell the user when the feed
        //     was single-phase but the vessel produces two phases, or vice
        //     versa. Useful sanity check that the spec is doing what they expect.
        const double feedV = feed->vaporFraction();
        const bool feedSingle  = !std::isnan(feedV) && (feedV <= 1.0e-6 || feedV >= 1.0 - 1.0e-6);
        if (feedSingle && !singlePhase_) {
            emitInfo_(QStringLiteral("Phase transition: single-phase feed flashes to two phases (V=%1 mole, %2 mass).")
                      .arg(Vmol, 0, 'f', 4).arg(Vmass, 0, 'f', 4));
        } else if (!feedSingle && singlePhase_) {
            emitInfo_(QStringLiteral("Phase transition: two-phase feed becomes single-phase in vessel."));
        }

        // (c) Extreme T result (typical upset indicator).
        if (T_out < 150.0) {
            emitWarn_(QStringLiteral("Vessel temperature (%1 K) is below cryogenic range — verify spec.")
                      .arg(T_out, 0, 'f', 2));
        } else if (T_out > 1500.0) {
            emitWarn_(QStringLiteral("Vessel temperature (%1 K) exceeds 1500 K — verify spec.")
                      .arg(T_out, 0, 'f', 2));
        }

        // (d) Deep-vacuum sanity check (matches HeaterCooler).
        if (P_out > 0.0 && P_out < 1000.0) {
            emitWarn_(QStringLiteral("Vessel pressure (%1 Pa) is below 1 kPa — deep vacuum, verify ΔP.")
                      .arg(P_out, 0, 'f', 0));
        }

        // ── 7. Finalize status level ────────────────────────────────────────
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

    // ── 8. Push results to outlet streams if connected ────────────────────────
    if (solveOk) {
        pushResultsToVaporStream_();
        pushResultsToLiquidStream_();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outlet stream population
//
// Each outlet stream gets:
//   - flow rate (mass-basis split of the feed)
//   - vessel T and P (both phases are in equilibrium at vessel conditions)
//   - composition (mole fractions y or x converted to mass fractions for
//     storage; MaterialStreamState stores compositions on a mass basis)
//   - fluid package id (inherited from the feed)
//
// If the outlet's phase is absent (single-phase result), we still set T, P,
// and the feed composition, but flow rate is zero. This keeps downstream
// state coherent — e.g. the user can connect the absent outlet to a
// heater and won't see NaN propagation.
// ─────────────────────────────────────────────────────────────────────────────

namespace {

// Convert mole fractions to mass fractions, given a parallel components
// vector. Returns an empty vector on size mismatch.
std::vector<double> moleToMassFractions(const std::vector<double>& moleFracs,
                                        const std::vector<Component>& components)
{
    std::vector<double> mass;
    if (moleFracs.size() != components.size())
        return mass;

    mass.resize(moleFracs.size(), 0.0);
    double sum = 0.0;
    for (size_t i = 0; i < moleFracs.size(); ++i) {
        const double mwi = (components[i].MW > 0.0) ? components[i].MW : 200.0;
        mass[i] = moleFracs[i] * mwi;
        sum += mass[i];
    }
    if (sum > 1.0e-12) {
        for (auto& w : mass) w /= sum;
    }
    return mass;
}

} // anonymous namespace

void SeparatorUnitState::pushResultsToVaporStream_()
{
    if (!flowsheetState_ || vaporStreamUnitId_.isEmpty())
        return;

    MaterialStreamState* vapor = flowsheetState_->findMaterialStreamByUnitId(vaporStreamUnitId_);
    if (!vapor)
        return;

    MaterialStreamState* feed = activeFeedStream();
    if (!feed)
        return;

    vapor->setFlowRateKgph(calcVaporFlowKgph_);
    vapor->setTemperatureK(calcVesselTempK_);
    vapor->setPressurePa(calcVesselPressurePa_);

    const QString pkgId = feed->selectedFluidPackageId();
    if (!pkgId.isEmpty() && vapor->selectedFluidPackageId() != pkgId)
        vapor->setSelectedFluidPackageId(pkgId);

    // Convert mole fractions y → mass fractions and push.
    const std::vector<Component>& components = feed->fluidDefinition().thermo.components;
    const std::vector<double> wt = moleToMassFractions(calcVaporCompositionY_, components);
    if (!wt.empty())
        vapor->setCompositionStd(wt);
}

void SeparatorUnitState::pushResultsToLiquidStream_()
{
    if (!flowsheetState_ || liquidStreamUnitId_.isEmpty())
        return;

    MaterialStreamState* liquid = flowsheetState_->findMaterialStreamByUnitId(liquidStreamUnitId_);
    if (!liquid)
        return;

    MaterialStreamState* feed = activeFeedStream();
    if (!feed)
        return;

    liquid->setFlowRateKgph(calcLiquidFlowKgph_);
    liquid->setTemperatureK(calcVesselTempK_);
    liquid->setPressurePa(calcVesselPressurePa_);

    const QString pkgId = feed->selectedFluidPackageId();
    if (!pkgId.isEmpty() && liquid->selectedFluidPackageId() != pkgId)
        liquid->setSelectedFluidPackageId(pkgId);

    // Convert mole fractions x → mass fractions and push.
    const std::vector<Component>& components = feed->fluidDefinition().thermo.components;
    const std::vector<double> wt = moleToMassFractions(calcLiquidCompositionX_, components);
    if (!wt.empty())
        liquid->setCompositionStd(wt);
}
