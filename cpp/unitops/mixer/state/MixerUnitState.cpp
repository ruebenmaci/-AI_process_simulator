#include "MixerUnitState.h"

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
#include <algorithm>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

MixerUnitState::MixerUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
    , runLogModel_(this)
{
    // Initial inlet vector size matches inletCount_ default (2). Mirror the
    // splitter's "always-consistent on construction" idiom.
    resizeInletVectors_();
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void MixerUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Mixer needs ≥2 connected inlets AND a product. <2 inlets is HARD Fail
// since no mixing can happen. Product missing is also HARD Fail since
// there's nowhere for the result to land. Some inlet ports being unconnected
// (e.g. inletCount=4 but only 3 connected) is OK if at least 2 are wired —
// the solver simply ignores the unconnected ones.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus MixerUnitState::connectivityStatus() const
{
    int connected = 0;
    for (const QString& s : inletStreamUnitIds_)
        if (!s.isEmpty()) ++connected;

    const bool noProduct = productStreamUnitId_.isEmpty();

    if (connected < 2 && noProduct)
        return { 3, QStringLiteral("needs ≥2 inlets and a product (have %1 inlets, no product)").arg(connected) };
    if (connected < 2)
        return { 3, QStringLiteral("needs ≥2 inlets (have %1)").arg(connected) };
    if (noProduct)
        return { 3, QStringLiteral("missing product stream") };
    return {};
}

QString MixerUnitState::connectedInletStreamUnitId(int inletIndex) const
{
    if (inletIndex < 0 || inletIndex >= static_cast<int>(inletStreamUnitIds_.size()))
        return QString{};
    return inletStreamUnitIds_[inletIndex];
}

void MixerUnitState::setConnectedInletStreamUnitId(int inletIndex, const QString& id)
{
    if (inletIndex < 0 || inletIndex >= static_cast<int>(inletStreamUnitIds_.size()))
        return;
    if (inletStreamUnitIds_[inletIndex] == id) return;
    inletStreamUnitIds_[inletIndex] = id;
    clearResults_();
    emit inletStreamsChanged();
}

QVariantList MixerUnitState::connectedInletStreamUnitIdsVariant() const
{
    QVariantList out;
    out.reserve(static_cast<int>(inletStreamUnitIds_.size()));
    for (const auto& s : inletStreamUnitIds_)
        out.append(s);
    return out;
}

void MixerUnitState::setConnectedProductStreamUnitId(const QString& id)
{
    if (productStreamUnitId_ == id) return;
    productStreamUnitId_ = id;
    emit productStreamChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters
// ─────────────────────────────────────────────────────────────────────────────

void MixerUnitState::setInletCount(int n)
{
    const int clamped = std::max(kMinInlets, std::min(n, kMaxInlets));
    if (clamped == inletCount_) return;
    inletCount_ = clamped;
    resizeInletVectors_();
    clearResults_();
    emit inletCountChanged();
    // Resizing the inlet vector implicitly changes the inlet-streams list —
    // emit so the QML view re-binds the projection.
    emit inletStreamsChanged();
}

void MixerUnitState::setPressureMode(const QString& mode)
{
    // Accept only the three documented values. Anything else is silently
    // coerced back to the default to keep solve() robust.
    QString v = mode;
    if (v != QStringLiteral("lowestInlet")
     && v != QStringLiteral("equalizeAll")
     && v != QStringLiteral("specified"))
        v = QStringLiteral("lowestInlet");

    if (pressureMode_ == v) return;
    pressureMode_ = v;
    clearResults_();
    emit pressureModeChanged();
}

void MixerUnitState::setSpecifiedOutletPressurePa(double v)
{
    if (qFuzzyCompare(specifiedOutletPressurePa_, v)) return;
    specifiedOutletPressurePa_ = v;
    clearResults_();
    emit specifiedOutletPressurePaChanged();
}

void MixerUnitState::setFlashPhaseMode(const QString& mode)
{
    QString v = mode;
    if (v != QStringLiteral("vle") && v != QStringLiteral("massBalanceOnly"))
        v = QStringLiteral("vle");
    if (flashPhaseMode_ == v) return;
    flashPhaseMode_ = v;
    clearResults_();
    emit flashPhaseModeChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

void MixerUnitState::resizeInletVectors_()
{
    // Preserve existing connections within the new size, clear extras when
    // shrinking. Any disconnected streams are cleaned up by FlowsheetState
    // observing the inletCountChanged signal (see addMixerInternal).
    inletStreamUnitIds_.resize(static_cast<size_t>(inletCount_));
}

MaterialStreamState* MixerUnitState::activeInletStream(int inletIndex) const
{
    if (!flowsheetState_) return nullptr;
    if (inletIndex < 0 || inletIndex >= static_cast<int>(inletStreamUnitIds_.size()))
        return nullptr;
    const QString& id = inletStreamUnitIds_[inletIndex];
    if (id.isEmpty()) return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(id);
}

void MixerUnitState::clearResults_()
{
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_                   = false;
    calcOutletPressurePa_     = 0.0;
    calcOutletTemperatureK_   = 0.0;
    calcOutletEnthalpyKJkg_   = 0.0;
    calcOutletFlowKgph_       = 0.0;
    calcOutletVaporMoleFrac_  = 0.0;
    calcOutletVaporMassFrac_  = 0.0;
    pressureSourceLabel_.clear();
    solveStatus_.clear();
    statusLevel_ = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void MixerUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    runLogModel_.clear();
    emit resultsChanged();
}

void MixerUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    statusLevel_ = StatusLevel::Fail;
}

void MixerUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void MixerUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
}

void MixerUnitState::appendRunLogLine_(const QString& line)
{
    runLogModel_.appendLine(line);
}

void MixerUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    runLogModel_.clear();
    statusLevel_ = StatusLevel::None;
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — multi-inlet mass + energy balance, then PH flash on the combined
// stream. Closely follows SeparatorUnitState's adiabatic-mode solve; the
// new step is the inlet aggregation (Σ m, Σ m·x, Σ m·h) at the top.
//
// Validation cascade:
//   1. ≥2 connected inlets, each with positive flow and defined T, P, H
//   2. All connected inlets share the same fluid package (warns on mismatch
//      but uses the first inlet's package)
//   3. Component-vector lengths are consistent
//
// Pressure assignment by mode:
//   "lowestInlet"  → P_out = min(P_i)
//   "equalizeAll"  → P_out = max(P_i)  (warns when inlet pressures differ)
//   "specified"    → P_out = specifiedOutletPressurePa
//
// Flash:
//   "vle"             → flashPH(H_out, P_out, z_out) → T_out, V
//   "massBalanceOnly" → outlet T = mass-weighted Σ(m_i·T_i)/m_out (rough)
//                       V is left at NaN/0 with an explanatory warning.
// ─────────────────────────────────────────────────────────────────────────────

void MixerUnitState::solve()
{
    resetSolveArtifacts_();

    // ── 1. Walk inlets and validate each connected one ───────────────────────
    struct InletData {
        int           index;          // 0-indexed
        double        mdot;           // kg/h
        double        T;              // K
        double        P;              // Pa
        double        H;              // kJ/kg
        std::vector<double> wt;       // mass fractions
        QString       packageId;
    };

    std::vector<InletData> inlets;
    inlets.reserve(static_cast<size_t>(inletCount_));

    int connectedCount = 0;
    QString firstPackageId;

    for (int i = 0; i < inletCount_; ++i) {
        MaterialStreamState* s = activeInletStream(i);
        if (!s) continue;          // not connected — skip silently
        ++connectedCount;

        const double mdot = s->flowRateKgph();
        const double T    = s->temperatureK();
        const double P    = s->pressurePa();
        const double H    = s->enthalpyKJkg();

        if (mdot <= 0.0 || std::isnan(mdot)) {
            emitWarn_(QStringLiteral("Inlet %1 has zero or undefined flow — ignored.")
                      .arg(i + 1));
            continue;
        }
        if (std::isnan(T) || std::isnan(P) || std::isnan(H)) {
            solveStatus_ = QStringLiteral("Inlet %1 conditions are not fully defined.")
                           .arg(i + 1);
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }

        InletData d;
        d.index      = i;
        d.mdot       = mdot;
        d.T          = T;
        d.P          = P;
        d.H          = H;
        d.wt         = s->compositionStd();
        d.packageId  = s->selectedFluidPackageId();

        // Capture the package-id BEFORE the move below — d.packageId is in
        // a valid-but-unspecified (typically empty) state after std::move,
        // so reading it post-move would silently drop the consistency check
        // and yield a "'pkg' but '' is the active package" warning where
        // firstPackageId never gets set.
        const QString pkgIdCopy = d.packageId;

        inlets.push_back(std::move(d));

        if (firstPackageId.isEmpty() && !pkgIdCopy.isEmpty())
            firstPackageId = pkgIdCopy;
    }

    if (connectedCount < 2) {
        solveStatus_ = QStringLiteral("Mixer requires at least 2 connected inlet streams (have %1).")
                       .arg(connectedCount);
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (inlets.size() < 2) {
        // Could happen if all-but-one connected inlets had zero/undefined flow.
        solveStatus_ = QStringLiteral("Mixer needs at least 2 inlets with positive flow (have %1).")
                       .arg(static_cast<int>(inlets.size()));
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // Fluid package consistency: the first inlet's package wins; mismatches
    // warn but don't fail. Real mismatches usually mean the user mixed up
    // their stream wiring; a warning is the right level.
    for (const auto& d : inlets) {
        if (!d.packageId.isEmpty() && d.packageId != firstPackageId) {
            emitWarn_(QStringLiteral("Inlet %1 uses fluid package '%2' but '%3' is the active package — "
                                     "mixing across packages, results may be approximate.")
                      .arg(d.index + 1).arg(d.packageId).arg(firstPackageId));
        }
    }

    appendRunLogLine_(QStringLiteral("[state] Mixing %1 inlets (package: %2)")
                      .arg(static_cast<int>(inlets.size()))
                      .arg(firstPackageId.isEmpty() ? QStringLiteral("(unset)") : firstPackageId));

    // ── 2. Resolve fluid thermo from first inlet ─────────────────────────────
    // Use the first inlet's resolved fluid definition as the reference. All
    // mass-fraction vectors will be checked against this component count.
    MaterialStreamState* refStream = activeInletStream(inlets.front().index);
    if (!refStream) {
        // Defensive — shouldn't happen since we just enumerated it.
        solveStatus_ = QStringLiteral("Internal error: reference inlet stream lost.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    const FluidDefinition& fd = refStream->fluidDefinition();
    const std::vector<Component>&        components = fd.thermo.components;
    const std::vector<std::vector<double>>& kij     = fd.thermo.kij;

    if (components.empty()) {
        solveStatus_ = QStringLiteral("Reference inlet's fluid package not resolved.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    auto* fpm = FluidPackageManager::instance();
    thermo::ThermoConfig thermoConfig = fpm
        ? fpm->thermoConfigForPackageResolved(refStream->selectedFluidPackageId())
        : thermo::makeThermoConfig("PRSV");

    appendRunLogLine_(QStringLiteral("[state] Thermo: %1 components, EOS %2")
                      .arg(static_cast<int>(components.size()))
                      .arg(QString::fromStdString(thermoConfig.eosName)));

    // ── 3. Inlet aggregation: Σ m, Σ m·x_j, Σ m·h ────────────────────────────
    const size_t nComp = components.size();
    double m_total      = 0.0;       // kg/h
    double mh_total     = 0.0;       // kJ/h          (mdot · H sums to enthalpy flux)
    double mT_total     = 0.0;       // kg·K/h        (for massBalanceOnly mode)
    std::vector<double> mx_total(nComp, 0.0);   // kg/h per component (mass basis)

    double P_min = std::numeric_limits<double>::infinity();
    double P_max = -std::numeric_limits<double>::infinity();
    int    idxMin = -1, idxMax = -1;

    for (const auto& d : inlets) {
        if (d.wt.size() != nComp) {
            solveStatus_ = QStringLiteral("Inlet %1 composition has %2 components but the package has %3.")
                           .arg(d.index + 1)
                           .arg(static_cast<int>(d.wt.size()))
                           .arg(static_cast<int>(nComp));
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }

        m_total  += d.mdot;
        mh_total += d.mdot * d.H;
        mT_total += d.mdot * d.T;
        for (size_t j = 0; j < nComp; ++j)
            mx_total[j] += d.mdot * d.wt[j];

        if (d.P < P_min) { P_min = d.P; idxMin = d.index; }
        if (d.P > P_max) { P_max = d.P; idxMax = d.index; }

        appendRunLogLine_(QStringLiteral("[state]   Inlet %1: mdot=%2 kg/h, T=%3 K, P=%4 Pa, H=%5 kJ/kg")
                          .arg(d.index + 1)
                          .arg(d.mdot, 0, 'f', 2)
                          .arg(d.T, 0, 'f', 2)
                          .arg(d.P, 0, 'f', 0)
                          .arg(d.H, 0, 'f', 2));
    }

    if (m_total <= 0.0) {
        solveStatus_ = QStringLiteral("Combined inlet flow is zero.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // Outlet mass-fraction composition (mass basis, what MaterialStreamState stores).
    std::vector<double> wt_out(nComp, 0.0);
    {
        double wsum = 0.0;
        for (size_t j = 0; j < nComp; ++j) {
            wt_out[j] = mx_total[j] / m_total;
            wsum += wt_out[j];
        }
        // Renormalise to fight floating-point drift; the input fractions are
        // expected to sum to ~1, but slight rounding can leave us at 0.9999..
        // which the flash routines tolerate but is worth tightening.
        if (wsum > 1.0e-12) {
            for (auto& w : wt_out) w /= wsum;
        }
    }

    // Outlet specific enthalpy [kJ/kg]
    const double H_out = mh_total / m_total;

    // ── 4. Pressure assignment ───────────────────────────────────────────────
    double P_out = 0.0;
    QString pressureLabel;
    const bool inletPressuresEqual =
        (std::fabs(P_max - P_min) < std::max(1.0, 1.0e-6 * std::fabs(P_max)));   // 1 Pa or 1 ppm

    if (pressureMode_ == QStringLiteral("specified")) {
        P_out = specifiedOutletPressurePa_;
        pressureLabel = QStringLiteral("user specified");
        if (P_out > P_max + 1.0) {
            // Specified outlet > highest inlet means we'd need a pump — flag it.
            emitWarn_(QStringLiteral("Specified outlet pressure (%1 Pa) exceeds the highest inlet "
                                     "pressure (%2 Pa) — physically requires a pump.")
                      .arg(P_out, 0, 'f', 0).arg(P_max, 0, 'f', 0));
        }
    } else if (pressureMode_ == QStringLiteral("equalizeAll")) {
        // We adopt the highest inlet pressure as the outlet. In real "Equalize
        // All" semantics, lower-pressure feeds would have to be raised by some
        // upstream device — that's an upstream-modeling concern, not ours.
        P_out = P_max;
        pressureLabel = QStringLiteral("from Inlet %1 (highest)").arg(idxMax + 1);
        if (!inletPressuresEqual) {
            emitWarn_(QStringLiteral("Equalize All mode: inlet pressures differ "
                                     "(min %1 Pa, max %2 Pa) — outlet uses the maximum, but lower-pressure "
                                     "inlets physically require a pump.")
                      .arg(P_min, 0, 'f', 0).arg(P_max, 0, 'f', 0));
        }
    } else {
        // "lowestInlet" — HYSYS / Aspen Plus default
        P_out = P_min;
        pressureLabel = QStringLiteral("from Inlet %1 (lowest)").arg(idxMin + 1);
    }

    if (P_out <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // ── 5. Flash to get T_out and V ──────────────────────────────────────────
    double T_out  = std::numeric_limits<double>::quiet_NaN();
    double V_mole = 0.0;
    double V_mass = 0.0;
    bool   solveOk = false;
    QString status;

    if (flashPhaseMode_ == QStringLiteral("massBalanceOnly")) {
        // No flash. Outlet T is a rough mass-weighted average of inlet T's —
        // this is the wrong answer thermodynamically but correct as a "no
        // equilibrium assumed" placeholder. V is left undefined.
        T_out  = mT_total / m_total;
        V_mole = std::numeric_limits<double>::quiet_NaN();
        V_mass = std::numeric_limits<double>::quiet_NaN();
        solveOk = true;
        status = QStringLiteral("OK (mass balance only)");
        emitInfo_(QStringLiteral("Mass-balance-only mode: outlet T is mass-weighted average; "
                                 "no phase equilibrium computed."));
        appendRunLogLine_(QStringLiteral("[state] Mass-balance-only: T_out (avg)=%1 K, P_out=%2 Pa")
                          .arg(T_out, 0, 'f', 2).arg(P_out, 0, 'f', 0));
    } else {
        // VLE mode (default). Convert outlet mass fractions → mole fractions
        // for the flash, then run PH at (H_out, P_out).
        std::vector<double> z_out(nComp, 0.0);
        double sumMolar = 0.0;
        for (size_t i = 0; i < nComp; ++i) {
            z_out[i] = (components[i].MW > 0.0) ? wt_out[i] / components[i].MW : 0.0;
            sumMolar += z_out[i];
        }
        if (sumMolar > 0.0)
            for (auto& zi : z_out) zi /= sumMolar;

        // Pick a sensible T seed: mass-weighted inlet average is much closer
        // to the answer than any single inlet's T.
        const double Tseed = mT_total / m_total;

        FlashPHInput phi;
        phi.Htarget    = H_out;
        phi.z          = z_out;
        phi.P          = P_out;
        phi.Tseed      = Tseed;
        phi.components = &components;
        phi.thermoConfig = thermoConfig;
        phi.kij        = &kij;
        phi.log        = nullptr;
        phi.logLevel   = LogLevel::Summary;

        const FlashPHResult res = flashPH(phi);

        if (res.status != "ok") {
            status = QStringLiteral("PH flash failed: ") + QString::fromStdString(res.status);
            emitError_(status);
        } else {
            T_out = res.T;
            V_mole = std::clamp(res.V, 0.0, 1.0);

            // Mass-basis V via phase MWs. This mirrors Separator's exact
            // formula so downstream consumers get a consistent number.
            auto mwOfPhase = [&](const std::vector<double>& comp) -> double {
                double mw = 0.0;
                for (size_t i = 0; i < components.size() && i < comp.size(); ++i) {
                    const double mwi = (components[i].MW > 0.0) ? components[i].MW : 200.0;
                    mw += comp[i] * mwi;
                }
                return std::max(1.0, mw);
            };
            std::vector<double> yVec = res.y;
            std::vector<double> xVec = res.x;
            if (yVec.size() != nComp) yVec = z_out;
            if (xVec.size() != nComp) xVec = z_out;
            const double MW_v = mwOfPhase(yVec);
            const double MW_l = mwOfPhase(xVec);
            const double num  = V_mole * MW_v;
            const double den  = num + (1.0 - V_mole) * MW_l;
            V_mass = (den > 1.0e-12) ? (num / den) : 0.0;

            solveOk = true;
            status  = QStringLiteral("OK");
            appendRunLogLine_(QStringLiteral("[state] Flash result: T_out=%1 K, V(mole)=%2, V(mass)=%3")
                              .arg(T_out, 0, 'f', 2)
                              .arg(V_mole, 0, 'f', 6)
                              .arg(V_mass, 0, 'f', 6));
        }
    }

    // ── 6. Stash results ─────────────────────────────────────────────────────
    if (solveOk) {
        calcOutletPressurePa_     = P_out;
        calcOutletTemperatureK_   = T_out;
        calcOutletEnthalpyKJkg_   = H_out;
        calcOutletFlowKgph_       = m_total;
        calcOutletVaporMoleFrac_  = V_mole;
        calcOutletVaporMassFrac_  = V_mass;
        pressureSourceLabel_      = pressureLabel;
        solveStatus_              = status;
        solved_                   = true;

        // ── 7. Post-solve diagnostics ────────────────────────────────────────

        // (a) Wide T-spread among inlets often indicates the user combined
        //     streams that should have been temperature-matched first via
        //     heaters/coolers. Informational, not an error.
        double Tmin = std::numeric_limits<double>::infinity();
        double Tmax = -std::numeric_limits<double>::infinity();
        for (const auto& d : inlets) {
            if (d.T < Tmin) Tmin = d.T;
            if (d.T > Tmax) Tmax = d.T;
        }
        if ((Tmax - Tmin) > 50.0) {
            emitInfo_(QStringLiteral("Inlet temperatures span %1 K (%2 → %3 K) — wide spread.")
                      .arg(Tmax - Tmin, 0, 'f', 1)
                      .arg(Tmin, 0, 'f', 1).arg(Tmax, 0, 'f', 1));
        }

        // (b) Wide P-spread when not in "specified" mode — the realistic
        //     mixing pressure is usually somewhere between, and HYSYS/Aspen
        //     don't model that. Worth flagging.
        if (!inletPressuresEqual && pressureMode_ != QStringLiteral("specified")) {
            const double dP = P_max - P_min;
            if (dP > 1.0e5) {  // > 1 bar spread
                emitInfo_(QStringLiteral("Inlet pressure spread is %1 Pa — actual mixing pressure depends "
                                         "on pipe geometry; the model uses the rule-based outlet pressure.")
                          .arg(dP, 0, 'f', 0));
            }
        }

        // (c) Phase-transition info (matches Separator and HeaterCooler).
        if (flashPhaseMode_ == QStringLiteral("vle")) {
            const bool outletSinglePhase = (V_mole <= 1.0e-6 || V_mole >= 1.0 - 1.0e-6);
            // Did at least one feed change phase across the mix?
            bool anyFeedTwoPhase = false;
            bool anyFeedSinglePhase = false;
            for (const auto& d : inlets) {
                MaterialStreamState* s = activeInletStream(d.index);
                if (!s) continue;
                const double v = s->vaporFraction();
                if (std::isnan(v)) continue;
                if (v > 1.0e-6 && v < 1.0 - 1.0e-6) anyFeedTwoPhase = true;
                else                                anyFeedSinglePhase = true;
            }
            if (anyFeedSinglePhase && !outletSinglePhase)
                emitInfo_(QStringLiteral("Phase change at mixer: at least one single-phase feed flashes "
                                         "to two phases (V=%1).").arg(V_mole, 0, 'f', 4));
            else if (anyFeedTwoPhase && outletSinglePhase)
                emitInfo_(QStringLiteral("Phase change at mixer: two-phase feed becomes single-phase outlet."));
        }

        // (d) Extreme T sanity (matches HeaterCooler / Separator).
        if (T_out < 150.0)
            emitWarn_(QStringLiteral("Outlet temperature (%1 K) is below cryogenic range — verify spec.")
                      .arg(T_out, 0, 'f', 2));
        else if (T_out > 1500.0)
            emitWarn_(QStringLiteral("Outlet temperature (%1 K) exceeds 1500 K — verify spec.")
                      .arg(T_out, 0, 'f', 2));

        // (e) Deep-vacuum sanity (matches Separator).
        if (P_out > 0.0 && P_out < 1000.0)
            emitWarn_(QStringLiteral("Outlet pressure (%1 Pa) is below 1 kPa — deep vacuum, verify spec.")
                      .arg(P_out, 0, 'f', 0));

        // (f) Disconnected inlet ports — informational.
        const int unconnected = inletCount_ - connectedCount;
        if (unconnected > 0) {
            emitInfo_(QStringLiteral("%1 of %2 inlet ports unconnected — solve used %3 inlets.")
                      .arg(unconnected).arg(inletCount_).arg(connectedCount));
        }

        if (statusLevel_ == StatusLevel::None) statusLevel_ = StatusLevel::Ok;
        if (statusLevel_ == StatusLevel::Ok)
            emitInfo_(QStringLiteral("Solve completed successfully."));
    } else {
        appendRunLogLine_(QStringLiteral("[state] Solve failed: ") + status);
        // statusLevel_ already escalated to Fail by emitError_().
    }

    emit solvedChanged();
    emit resultsChanged();

    // ── 8. Push results to product stream ────────────────────────────────────
    if (solveOk)
        pushResultsToProductStream_(wt_out, firstPackageId);
}

void MixerUnitState::pushResultsToProductStream_(const std::vector<double>& outletMassFractions,
                                                 const QString& fluidPackageId)
{
    if (!flowsheetState_ || productStreamUnitId_.isEmpty()) return;

    MaterialStreamState* product = flowsheetState_->findMaterialStreamByUnitId(productStreamUnitId_);
    if (!product) return;

    product->setFlowRateKgph(calcOutletFlowKgph_);
    product->setTemperatureK(calcOutletTemperatureK_);
    product->setPressurePa(calcOutletPressurePa_);

    if (!outletMassFractions.empty())
        product->setCompositionStd(outletMassFractions);

    if (!fluidPackageId.isEmpty() && product->selectedFluidPackageId() != fluidPackageId)
        product->setSelectedFluidPackageId(fluidPackageId);
}
