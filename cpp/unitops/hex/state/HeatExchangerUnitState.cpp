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
#include <QStringList>
#include <QDateTime>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

HeatExchangerUnitState::HeatExchangerUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
}

// ─────────────────────────────────────────────────────────────────────────────
// Wiring
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// All four ports are required for a HEX to solve. We surface a compact
// summary listing which ports are missing rather than four separate rows
// in the Status panel.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus HeatExchangerUnitState::connectivityStatus() const
{
    QStringList missing;
    if (hotInStreamUnitId_.isEmpty())   missing << QStringLiteral("hot-in");
    if (hotOutStreamUnitId_.isEmpty())  missing << QStringLiteral("hot-out");
    if (coldInStreamUnitId_.isEmpty())  missing << QStringLiteral("cold-in");
    if (coldOutStreamUnitId_.isEmpty()) missing << QStringLiteral("cold-out");

    if (missing.isEmpty()) return {};
    return { 3, QStringLiteral("missing %1 stream%2: %3")
                 .arg(missing.size())
                 .arg(missing.size() == 1 ? QString{} : QStringLiteral("s"))
                 .arg(missing.join(QStringLiteral(", "))) };
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
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
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
    statusLevel_        = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void HeatExchangerUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic / log helpers
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void HeatExchangerUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    appendRunLogLine_(QStringLiteral("[state][error] ") + message);
    statusLevel_ = StatusLevel::Fail;
}

void HeatExchangerUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    appendRunLogLine_(QStringLiteral("[state][warn] ") + message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void HeatExchangerUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
    appendRunLogLine_(QStringLiteral("[state][info] ") + message);
}

void HeatExchangerUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
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
                                          double T_seed,
                                          const std::function<void(const std::string&)>& logSink)
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
    phi.log        = logSink;
    phi.logLevel   = LogLevel::Summary;

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
//
// Counter-current, single-pass, two-stream black-box HEX.
// Specs: duty (kW), hot outlet T (K), or cold outlet T (K) — exactly one.
//
// After the solve we run post-hoc checks for warnings (close approach ΔT,
// pinch, phase transitions, extreme outlet T, small LMTD, etc.) and report
// them through diagnosticsModel_. The final statusLevel_ is None/Ok/Warn/Fail
// depending on what was emitted.
// ─────────────────────────────────────────────────────────────────────────────

void HeatExchangerUnitState::solve()
{
    // ── 0. Fresh solve — clear previous artifacts ─────────────────────────────
    resetSolveArtifacts_();

    auto logSink = [this](const std::string& s) {
        runLogModel_.appendLine(QString::fromStdString(s));
    };

    const QString unitLabel = name().isEmpty() ? id() : name();
    appendRunLogLine_(QStringLiteral("[state] ─── Solving heat_exchanger \"")
                      + unitLabel + QStringLiteral("\" (spec: ") + specMode_
                      + QStringLiteral(") ───"));

    // ── 1. Gather inlet streams ───────────────────────────────────────────────
    MaterialStreamState* hotIn  = findStream(hotInStreamUnitId_);
    MaterialStreamState* coldIn = findStream(coldInStreamUnitId_);

    if (!hotIn || !coldIn) {
        solveStatus_ = QStringLiteral("Both hot-side and cold-side feed streams must be connected.");
        emitError_(solveStatus_);
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
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (mdot_cold <= 0.0 || std::isnan(mdot_cold)) {
        solveStatus_ = QStringLiteral("Cold-side flow rate is zero or undefined.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (std::isnan(T_hotIn)  || std::isnan(P_hotIn)  || std::isnan(H_hotIn)) {
        solveStatus_ = QStringLiteral("Hot-side inlet conditions not fully defined.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (std::isnan(T_coldIn) || std::isnan(P_coldIn) || std::isnan(H_coldIn)) {
        solveStatus_ = QStringLiteral("Cold-side inlet conditions not fully defined.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (T_hotIn <= T_coldIn) {
        solveStatus_ = QStringLiteral("Hot-side inlet temperature must be above cold-side inlet temperature.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }

    appendRunLogLine_(QStringLiteral("[state] Hot inlet:  T=%1 K, P=%2 Pa, mdot=%3 kg/h")
                      .arg(T_hotIn,  0, 'f', 2).arg(P_hotIn,  0, 'f', 0).arg(mdot_hot,  0, 'f', 2));
    appendRunLogLine_(QStringLiteral("[state] Cold inlet: T=%1 K, P=%2 Pa, mdot=%3 kg/h")
                      .arg(T_coldIn, 0, 'f', 2).arg(P_coldIn, 0, 'f', 0).arg(mdot_cold, 0, 'f', 2));

    const double P_hotOut  = P_hotIn  - hotSidePressureDropPa_;
    const double P_coldOut = P_coldIn - coldSidePressureDropPa_;
    if (P_hotOut  <= 0.0) {
        solveStatus_ = QStringLiteral("Hot-side outlet pressure ≤ 0.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (P_coldOut <= 0.0) {
        solveStatus_ = QStringLiteral("Cold-side outlet pressure ≤ 0.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (hotSidePressureDropPa_ < 0.0) {
        emitWarn_(QStringLiteral("Hot-side pressure drop is negative."));
    }
    if (coldSidePressureDropPa_ < 0.0) {
        emitWarn_(QStringLiteral("Cold-side pressure drop is negative."));
    }

    // ── 2. Build thermo inputs for hot and cold streams ───────────────────────
    thermo::ThermoConfig hotCfg, coldCfg;
    std::vector<Component> hotComps, coldComps;
    std::vector<std::vector<double>> hotKij, coldKij;
    std::vector<double> hotZ, coldZ;
    QString errMsg;

    if (!buildThermoInputs(hotIn,  hotCfg,  hotComps,  hotKij,  hotZ,  errMsg)) {
        solveStatus_ = QStringLiteral("Hot side: ") + errMsg;
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (!buildThermoInputs(coldIn, coldCfg, coldComps, coldKij, coldZ, errMsg)) {
        solveStatus_ = QStringLiteral("Cold side: ") + errMsg;
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }

    appendRunLogLine_(QStringLiteral("[state] Hot  thermo: %1 comps, EOS %2")
                      .arg(hotComps.size()).arg(QString::fromStdString(hotCfg.eosName)));
    appendRunLogLine_(QStringLiteral("[state] Cold thermo: %1 comps, EOS %2")
                      .arg(coldComps.size()).arg(QString::fromStdString(coldCfg.eosName)));

    // Pre-solve feasibility checks for the T-spec modes.
    if (specMode_ == QStringLiteral("hotOutletT")) {
        if (hotOutletTK_ >= T_hotIn) {
            solveStatus_ = QStringLiteral("Hot outlet T (%1 K) must be less than hot inlet T (%2 K).")
                           .arg(hotOutletTK_, 0, 'f', 2).arg(T_hotIn, 0, 'f', 2);
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }
        if (hotOutletTK_ <= T_coldIn) {
            solveStatus_ = QStringLiteral("Hot outlet T (%1 K) cannot fall below cold inlet T (%2 K) — violates 2nd law.")
                           .arg(hotOutletTK_, 0, 'f', 2).arg(T_coldIn, 0, 'f', 2);
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }
    } else if (specMode_ == QStringLiteral("coldOutletT")) {
        if (coldOutletTK_ <= T_coldIn) {
            solveStatus_ = QStringLiteral("Cold outlet T (%1 K) must be greater than cold inlet T (%2 K).")
                           .arg(coldOutletTK_, 0, 'f', 2).arg(T_coldIn, 0, 'f', 2);
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }
        if (coldOutletTK_ >= T_hotIn) {
            solveStatus_ = QStringLiteral("Cold outlet T (%1 K) cannot exceed hot inlet T (%2 K) — violates 2nd law.")
                           .arg(coldOutletTK_, 0, 'f', 2).arg(T_hotIn, 0, 'f', 2);
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }
    } else if (specMode_ == QStringLiteral("duty")) {
        if (dutyKW_ <= 0.0) {
            emitWarn_(QStringLiteral("Duty spec is non-positive — hot side will not be cooled as expected."));
        }
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
        const double Q_kJh   = dutyKW_ * 3600.0;
        const double H_hotOut_kJkg  = H_hotIn  - Q_kJh / mdot_hot;
        const double H_coldOut_kJkg = H_coldIn + Q_kJh / mdot_cold;

        const double T_hotSeed  = T_hotIn  - (T_hotIn - T_coldIn) * 0.5;
        const double T_coldSeed = T_coldIn + (T_hotIn - T_coldIn) * 0.5;

        auto hotRes  = calcOutletFromH_(hotIn,  P_hotOut,  H_hotOut_kJkg,  T_hotSeed,  logSink);
        auto coldRes = calcOutletFromH_(coldIn, P_coldOut, H_coldOut_kJkg, T_coldSeed, logSink);

        if (!hotRes.ok)  {
            solveStatus_ = QStringLiteral("Hot outlet: ") + hotRes.status;
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }
        if (!coldRes.ok) {
            solveStatus_ = QStringLiteral("Cold outlet: ") + coldRes.status;
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }

        Q_kW      = dutyKW_;
        T_hotOut  = hotRes.T;
        T_coldOut = coldRes.T;
        V_hotOut  = hotRes.vapFrac;
        V_coldOut = coldRes.vapFrac;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else if (specMode_ == QStringLiteral("hotOutletT")) {
        const FlashPTResult hotRes = flashPT(
            P_hotOut, hotOutletTK_, hotZ, hotCfg, &hotComps, &hotKij,
            /*murphreeEtaV=*/1.0, /*log=*/logSink);
        if (std::isnan(hotRes.H)) {
            solveStatus_ = QStringLiteral("PT flash failed for hot outlet.");
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }

        const double Q_kJh          = mdot_hot * (H_hotIn - hotRes.H);
        const double H_coldOut_kJkg = H_coldIn + Q_kJh / mdot_cold;
        const double T_coldSeed     = T_coldIn + (hotOutletTK_ - T_coldIn) * 0.5;

        auto coldRes = calcOutletFromH_(coldIn, P_coldOut, H_coldOut_kJkg, T_coldSeed, logSink);
        if (!coldRes.ok) {
            solveStatus_ = QStringLiteral("Cold outlet: ") + coldRes.status;
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }

        Q_kW      = Q_kJh / 3600.0;
        T_hotOut  = hotOutletTK_;
        T_coldOut = coldRes.T;
        V_hotOut  = hotRes.V;
        V_coldOut = coldRes.vapFrac;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else if (specMode_ == QStringLiteral("coldOutletT")) {
        const FlashPTResult coldRes = flashPT(
            P_coldOut, coldOutletTK_, coldZ, coldCfg, &coldComps, &coldKij,
            /*murphreeEtaV=*/1.0, /*log=*/logSink);
        if (std::isnan(coldRes.H)) {
            solveStatus_ = QStringLiteral("PT flash failed for cold outlet.");
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }

        const double Q_kJh         = mdot_cold * (coldRes.H - H_coldIn);
        const double H_hotOut_kJkg = H_hotIn - Q_kJh / mdot_hot;
        const double T_hotSeed     = T_hotIn - (T_hotIn - coldOutletTK_) * 0.5;

        auto hotRes = calcOutletFromH_(hotIn, P_hotOut, H_hotOut_kJkg, T_hotSeed, logSink);
        if (!hotRes.ok) {
            solveStatus_ = QStringLiteral("Hot outlet: ") + hotRes.status;
            emitError_(solveStatus_);
            emit resultsChanged(); return;
        }

        Q_kW      = Q_kJh / 3600.0;
        T_hotOut  = hotRes.T;
        T_coldOut = coldOutletTK_;
        V_hotOut  = hotRes.vapFrac;
        V_coldOut = coldRes.V;
        solveOk   = true;
        status    = QStringLiteral("OK");

    } else {
        status = QStringLiteral("Unknown spec mode: ") + specMode_;
        emitError_(status);
    }

    if (!solveOk) {
        solveStatus_ = status;
        emit resultsChanged();
        return;
    }

    // Feasibility check: hot must cool, cold must heat
    if (T_hotOut >= T_hotIn) {
        solveStatus_ = QStringLiteral("Hot side heated instead of cooled — check duty sign or spec.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (T_coldOut <= T_coldIn) {
        solveStatus_ = QStringLiteral("Cold side cooled instead of heated — check duty sign or spec.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }

    // Temperature cross (counter-current): hot outlet should be above cold
    // inlet, and cold outlet should be below hot inlet. If either fails we
    // have an infeasible counter-current design (would need more passes).
    if (T_hotOut < T_coldIn) {
        solveStatus_ = QStringLiteral("Hot outlet T is below cold inlet T — infeasible counter-current design.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }
    if (T_coldOut > T_hotIn) {
        solveStatus_ = QStringLiteral("Cold outlet T exceeds hot inlet T — infeasible counter-current design.");
        emitError_(solveStatus_);
        emit resultsChanged(); return;
    }

    // ── 4. LMTD and UA ───────────────────────────────────────────────────────
    const double lmtd = computeLMTD(T_hotIn, T_hotOut, T_coldIn, T_coldOut);
    double ua = std::numeric_limits<double>::quiet_NaN();
    if (!std::isnan(lmtd) && lmtd > 0.0)
        ua = (Q_kW * 1000.0) / lmtd;   // W/K

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

    appendRunLogLine_(QStringLiteral("[state] Solved: Q=%1 kW, T_hotOut=%2 K, T_coldOut=%3 K")
                      .arg(Q_kW, 0, 'f', 3).arg(T_hotOut, 0, 'f', 2).arg(T_coldOut, 0, 'f', 2));
    appendRunLogLine_(QStringLiteral("[state] LMTD=%1 K, UA=%2 W/K, approach=%3 K")
                      .arg(lmtd, 0, 'f', 2).arg(ua, 0, 'f', 1).arg(approach, 0, 'f', 2));

    // ── 6. Post-solve detection of warnings ──────────────────────────────────

    // (a) Close approach ΔT — a fundamental HEX design concern.
    //     < 1 K: effectively an error (impractical area required).
    //     < 5 K: warn (tight design, very large surface).
    //     Anything larger is fine.
    if (!std::isnan(approach)) {
        if (approach < 1.0) {
            emitError_(QStringLiteral("Approach ΔT (%1 K) is below 1 K — design is impractically tight.")
                       .arg(approach, 0, 'f', 3));
        } else if (approach < 5.0) {
            emitWarn_(QStringLiteral("Approach ΔT (%1 K) is below 5 K — tight design with large area requirement.")
                      .arg(approach, 0, 'f', 2));
        }
    }

    // (b) Pinch warning: one end's ΔT is much smaller than the other's.
    //     Ratio > 10 suggests a pinch somewhere inside the exchanger that
    //     simple LMTD doesn't capture.
    const double dt_hotEnd  = T_hotIn  - T_coldOut;
    const double dt_coldEnd = T_hotOut - T_coldIn;
    if (dt_hotEnd > 0.0 && dt_coldEnd > 0.0) {
        const double ratio = std::max(dt_hotEnd, dt_coldEnd) / std::min(dt_hotEnd, dt_coldEnd);
        if (ratio > 10.0) {
            emitWarn_(QStringLiteral("Terminal ΔT ratio (%1:%2) exceeds 10 — possible pinch inside the exchanger.")
                      .arg(dt_hotEnd, 0, 'f', 2).arg(dt_coldEnd, 0, 'f', 2));
        }
    }

    // (c) LMTD problematic (near zero, or NaN when ΔT's have opposite signs).
    if (std::isnan(lmtd) || lmtd <= 0.0) {
        emitWarn_(QStringLiteral("LMTD could not be computed — check terminal temperatures."));
    } else if (lmtd < 1.0) {
        emitWarn_(QStringLiteral("LMTD (%1 K) is below 1 K — UA estimate is unreliable.")
                  .arg(lmtd, 0, 'f', 3));
    }

    // (d) UA magnitude sanity — very small Q_kW/LMTD can indicate a
    //     degenerate spec; extremely large UA suggests the user's spec
    //     approaches the thermodynamic limit.
    if (!std::isnan(ua)) {
        if (ua > 1.0e8) {   // > 100 MW/K is unrealistic for any real HEX
            emitWarn_(QStringLiteral("UA (%1 W/K) is unrealistically large — spec is near thermodynamic limit.")
                      .arg(ua, 0, 'f', 0));
        }
    }

    // (e) Phase transitions occurring on either side — informational.
    const double hotFeedV  = hotIn->vaporFraction();
    const double coldFeedV = coldIn->vaporFraction();
    const auto isSingle = [](double v) {
        return !std::isnan(v) && (v <= 1.0e-6 || v >= 1.0 - 1.0e-6);
    };
    if (isSingle(hotFeedV) && !isSingle(V_hotOut)) {
        emitInfo_(QStringLiteral("Hot side: single-phase feed produces two-phase outlet (V=%1).")
                  .arg(V_hotOut, 0, 'f', 4));
    } else if (!isSingle(hotFeedV) && isSingle(V_hotOut)) {
        emitInfo_(QStringLiteral("Hot side: two-phase feed becomes single-phase at outlet."));
    }
    if (isSingle(coldFeedV) && !isSingle(V_coldOut)) {
        emitInfo_(QStringLiteral("Cold side: single-phase feed produces two-phase outlet (V=%1).")
                  .arg(V_coldOut, 0, 'f', 4));
    } else if (!isSingle(coldFeedV) && isSingle(V_coldOut)) {
        emitInfo_(QStringLiteral("Cold side: two-phase feed becomes single-phase at outlet."));
    }

    // (f) Extreme outlet temperatures.
    if (T_hotOut < 150.0) {
        emitWarn_(QStringLiteral("Hot outlet T (%1 K) is below cryogenic range.")
                  .arg(T_hotOut, 0, 'f', 2));
    }
    if (T_coldOut > 1500.0) {
        emitWarn_(QStringLiteral("Cold outlet T (%1 K) exceeds 1500 K.")
                  .arg(T_coldOut, 0, 'f', 2));
    }

    // (g) Very-low outlet pressure (deep vacuum) on either side.
    if (P_hotOut  > 0.0 && P_hotOut  < 1000.0) {
        emitWarn_(QStringLiteral("Hot-side outlet pressure (%1 Pa) is below 1 kPa — deep vacuum.")
                  .arg(P_hotOut, 0, 'f', 0));
    }
    if (P_coldOut > 0.0 && P_coldOut < 1000.0) {
        emitWarn_(QStringLiteral("Cold-side outlet pressure (%1 Pa) is below 1 kPa — deep vacuum.")
                  .arg(P_coldOut, 0, 'f', 0));
    }

    // ── 7. Finalize status level ─────────────────────────────────────────────
    if (statusLevel_ == StatusLevel::None)
        statusLevel_ = StatusLevel::Ok;

    if (statusLevel_ == StatusLevel::Ok) {
        emitInfo_(QStringLiteral("Solve completed successfully."));
    }

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
