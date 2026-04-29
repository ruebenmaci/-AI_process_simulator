#include "SplitterUnitState.h"

#include "flowsheet/state/FlowsheetState.h"
#include "streams/state/StreamUnitState.h"
#include "streams/state/MaterialStreamState.h"

#include <QDebug>
#include <QDateTime>
#include <algorithm>
#include <cmath>
#include <limits>

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

SplitterUnitState::SplitterUnitState(QObject* parent)
    : ProcessUnitState(parent)
    , diagnosticsModel_(this)
{
    // Initial size matches outletCount_ default (2). Vectors are empty until
    // resizeOutletVectors_() is called — do that here so the splitter is in
    // a consistent state immediately on construction.
    resizeOutletVectors_();
    distributeFractionsEvenly();
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection wiring
// ─────────────────────────────────────────────────────────────────────────────

void SplitterUnitState::setFlowsheetState(FlowsheetState* fs)
{
    flowsheetState_ = fs;
}

// ─────────────────────────────────────────────────────────────────────────────
// connectivityStatus
//
// Feed is HARD required. Outlet completeness is reported as a count: any
// missing outlets are warnings since the user can still solve and the
// disconnected outlet just won't push results anywhere.
// ─────────────────────────────────────────────────────────────────────────────
ConnectivityStatus SplitterUnitState::connectivityStatus() const
{
    if (feedStreamUnitId_.isEmpty())
        return { 3, QStringLiteral("missing feed stream") };

    int unconnected = 0;
    for (const QString& s : outletStreamUnitIds_)
        if (s.isEmpty()) ++unconnected;

    if (unconnected > 0) {
        return { 2, QStringLiteral("%1 of %2 outlet%3 not connected")
                     .arg(unconnected)
                     .arg(outletCount_)
                     .arg(outletCount_ == 1 ? QString{} : QStringLiteral("s")) };
    }
    return {};
}

void SplitterUnitState::setConnectedFeedStreamUnitId(const QString& id)
{
    if (feedStreamUnitId_ == id) return;
    feedStreamUnitId_ = id;
    clearResults_();
    emit feedStreamChanged();
}

QString SplitterUnitState::connectedOutletStreamUnitId(int outletIndex) const
{
    if (outletIndex < 0 || outletIndex >= static_cast<int>(outletStreamUnitIds_.size()))
        return QString{};
    return outletStreamUnitIds_[outletIndex];
}

void SplitterUnitState::setConnectedOutletStreamUnitId(int outletIndex, const QString& id)
{
    if (outletIndex < 0 || outletIndex >= static_cast<int>(outletStreamUnitIds_.size()))
        return;
    if (outletStreamUnitIds_[outletIndex] == id) return;
    outletStreamUnitIds_[outletIndex] = id;
    emit outletStreamsChanged();
}

QVariantList SplitterUnitState::connectedOutletStreamUnitIdsVariant() const
{
    QVariantList out;
    out.reserve(static_cast<int>(outletStreamUnitIds_.size()));
    for (const auto& s : outletStreamUnitIds_)
        out.append(s);
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec setters
// ─────────────────────────────────────────────────────────────────────────────

void SplitterUnitState::setOutletCount(int n)
{
    const int clamped = std::max(kMinOutlets, std::min(n, kMaxOutlets));
    if (clamped == outletCount_) return;
    outletCount_ = clamped;
    resizeOutletVectors_();
    clearResults_();
    emit outletCountChanged();
    // Resizing the vectors implicitly changes the fraction-sum, the outlet-
    // streams list, and the result list — emit the corresponding signals so
    // the QML view re-binds all three projections.
    emit outletStreamsChanged();
    emit outletFractionsChanged();
}

void SplitterUnitState::setOutletFraction(int outletIndex, double value)
{
    if (outletIndex < 0 || outletIndex >= static_cast<int>(outletFractions_.size()))
        return;
    // Always emit so the live "Total: X.XX" display in the QML view updates
    // even when the user re-enters the same value (defensive — qFuzzyCompare
    // would suppress that and leave a stale total on screen).
    outletFractions_[outletIndex] = value;
    clearResults_();
    emit outletFractionsChanged();
}

void SplitterUnitState::setPressureDropPa(double v)
{
    if (qFuzzyCompare(pressureDropPa_, v)) return;
    pressureDropPa_ = v;
    clearResults_();
    emit pressureDropPaChanged();
}

double SplitterUnitState::outletFraction(int i) const
{
    if (i < 0 || i >= static_cast<int>(outletFractions_.size()))
        return std::numeric_limits<double>::quiet_NaN();
    return outletFractions_[i];
}

double SplitterUnitState::outletFractionSum() const
{
    double sum = 0.0;
    for (double f : outletFractions_) sum += f;
    return sum;
}

bool SplitterUnitState::outletFractionsBalanced() const
{
    return std::fabs(outletFractionSum() - 1.0) <= kFractionTolerance;
}

QVariantList SplitterUnitState::outletFractionsVariant() const
{
    QVariantList out;
    out.reserve(static_cast<int>(outletFractions_.size()));
    for (double f : outletFractions_) out.append(f);
    return out;
}

void SplitterUnitState::setOutletFractionsVariant(const QVariantList& list)
{
    // Only mutate as far as the existing vector allows — the QML side may
    // pass a list of any length, and the canonical length is outletCount_.
    const int n = std::min(static_cast<int>(list.size()),
                           static_cast<int>(outletFractions_.size()));
    bool changed = false;
    for (int i = 0; i < n; ++i) {
        const double v = list[i].toDouble();
        if (outletFractions_[i] != v) {
            outletFractions_[i] = v;
            changed = true;
        }
    }
    if (changed) {
        clearResults_();
        emit outletFractionsChanged();
    }
}

void SplitterUnitState::distributeFractionsEvenly()
{
    if (outletFractions_.empty()) return;
    const double even = 1.0 / static_cast<double>(outletFractions_.size());
    for (auto& f : outletFractions_) f = even;
    clearResults_();
    emit outletFractionsChanged();
}

void SplitterUnitState::normalizeFractions()
{
    // Scales the existing fractions so they sum to exactly 1.0, preserving
    // the user's relative split. Examples:
    //   [0.4, 0.4, 0.4]  → [0.333, 0.333, 0.333]   (sum was 1.2)
    //   [2.0, 1.0, 1.0]  → [0.5, 0.25, 0.25]       (sum was 4.0)
    //   [0.5, 0.5]       → [0.5, 0.5]              (already 1.0, no-op)
    //
    // Edge case: when all fractions are zero (sum == 0), there's no
    // proportional information to preserve, so fall back to even
    // distribution and flag it. This way the user always ends up with a
    // solvable state after clicking Normalize, regardless of input.
    if (outletFractions_.empty()) return;

    double sum = 0.0;
    for (double f : outletFractions_) sum += f;

    if (std::fabs(sum) < 1.0e-12) {
        // Degenerate input — can't normalize a zero-sum vector. Fall back.
        const double even = 1.0 / static_cast<double>(outletFractions_.size());
        for (auto& f : outletFractions_) f = even;
        emitWarn_(QStringLiteral("All fractions were zero — distributed evenly instead."));
    } else {
        for (auto& f : outletFractions_) f /= sum;
    }

    clearResults_();
    emit outletFractionsChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

void SplitterUnitState::resizeOutletVectors_()
{
    // outletStreamUnitIds_: preserve existing connections within new size,
    // clear extras when shrinking (any disconnected streams will be cleaned
    // up by FlowsheetState observing the outletCountChanged signal).
    outletStreamUnitIds_.resize(static_cast<size_t>(outletCount_));

    // outletFractions_: preserve existing values within new size, append
    // zeros when growing. Caller (typically setOutletCount or the
    // constructor) is responsible for re-balancing if needed.
    outletFractions_.resize(static_cast<size_t>(outletCount_), 0.0);

    // Result vector — clear it; it'll be repopulated on the next solve().
    calcOutletFlowsKgph_.assign(static_cast<size_t>(outletCount_), 0.0);
}

MaterialStreamState* SplitterUnitState::activeFeedStream() const
{
    if (!flowsheetState_ || feedStreamUnitId_.isEmpty())
        return nullptr;
    return flowsheetState_->findMaterialStreamByUnitId(feedStreamUnitId_);
}

double SplitterUnitState::calcOutletFlowKgph(int i) const
{
    if (i < 0 || i >= static_cast<int>(calcOutletFlowsKgph_.size()))
        return std::numeric_limits<double>::quiet_NaN();
    return calcOutletFlowsKgph_[i];
}

QVariantList SplitterUnitState::calcOutletFlowsKgphVariant() const
{
    QVariantList out;
    out.reserve(static_cast<int>(calcOutletFlowsKgph_.size()));
    for (double f : calcOutletFlowsKgph_) out.append(f);
    return out;
}

void SplitterUnitState::clearResults_()
{
    if (!solved_ && statusLevel_ == StatusLevel::None) return;
    solved_ = false;
    std::fill(calcOutletFlowsKgph_.begin(), calcOutletFlowsKgph_.end(), 0.0);
    calcOutletPressurePa_ = 0.0;
    calcOutletTemperatureK_ = 0.0;
    solveStatus_.clear();
    statusLevel_ = StatusLevel::None;
    emit solvedChanged();
    emit resultsChanged();
}

void SplitterUnitState::reset()
{
    clearResults_();
    diagnosticsModel_.clear();
    emit resultsChanged();
}

void SplitterUnitState::emitError_(const QString& message)
{
    diagnosticsModel_.error(message);
    statusLevel_ = StatusLevel::Fail;
}

void SplitterUnitState::emitWarn_(const QString& message)
{
    diagnosticsModel_.warn(message);
    if (statusLevel_ != StatusLevel::Fail)
        statusLevel_ = StatusLevel::Warn;
}

void SplitterUnitState::emitInfo_(const QString& message)
{
    diagnosticsModel_.info(message);
}

void SplitterUnitState::resetSolveArtifacts_()
{
    diagnosticsModel_.clear();
    statusLevel_ = StatusLevel::None;
}

// ─────────────────────────────────────────────────────────────────────────────
// Solve — pure mass balance, no thermo.
//
// Validation (any failure short-circuits before pushing results):
//   1. Feed stream connected and has positive flow / defined T,P
//   2. outletCount matches the size of all outlet vectors (defensive)
//   3. outletFractions sum to 1.0 ± kFractionTolerance
//   4. all individual fractions in [0, 1]
//
// On success, for each outlet i:
//   outlet_i.flow         = feed.flow * outletFractions[i]
//   outlet_i.composition  = feed.composition (mass-fraction copy)
//   outlet_i.T            = feed.T
//   outlet_i.P            = feed.P - pressureDropPa
//   outlet_i.fluidPackage = feed.fluidPackage (if set)
//
// Diagnostic warnings emitted post-solve:
//   - Outlet with fraction == 0 is unusual but legal — info-level note.
//   - Negative ΔP — produces outlet P > inlet P — warn.
//   - Outlet with fraction > 0 but no connected stream — info; the result
//     is computed but cannot be pushed anywhere.
// ─────────────────────────────────────────────────────────────────────────────

void SplitterUnitState::solve()
{
    resetSolveArtifacts_();

    // ── 1. Validate feed ─────────────────────────────────────────────────────
    MaterialStreamState* feed = activeFeedStream();
    if (!feed) {
        solveStatus_ = QStringLiteral("No feed stream connected.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    const double mdot = feed->flowRateKgph();
    const double T_in = feed->temperatureK();
    const double P_in = feed->pressurePa();

    if (mdot <= 0.0 || std::isnan(mdot)) {
        solveStatus_ = QStringLiteral("Feed flow rate is zero or undefined.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (std::isnan(T_in) || std::isnan(P_in)) {
        solveStatus_ = QStringLiteral("Feed conditions are not fully defined.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // ── 2. Defensive: vector sizes must match outletCount_ ──────────────────
    if (static_cast<int>(outletFractions_.size()) != outletCount_
        || static_cast<int>(outletStreamUnitIds_.size()) != outletCount_
        || static_cast<int>(calcOutletFlowsKgph_.size()) != outletCount_) {
        solveStatus_ = QStringLiteral("Internal error: outlet vector sizes inconsistent.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    // ── 3. Validate outlet fractions ────────────────────────────────────────
    const double fSum = outletFractionSum();
    if (std::fabs(fSum - 1.0) > kFractionTolerance) {
        solveStatus_ = QStringLiteral("Outlet fractions sum to %1, must be 1.000.")
                       .arg(fSum, 0, 'f', 4);
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }

    for (int i = 0; i < outletCount_; ++i) {
        const double f = outletFractions_[i];
        if (f < 0.0 || f > 1.0 || std::isnan(f)) {
            solveStatus_ = QStringLiteral("Outlet %1 fraction (%2) is out of [0, 1].")
                           .arg(i + 1).arg(f, 0, 'f', 4);
            emitError_(solveStatus_);
            emit resultsChanged();
            return;
        }
    }

    // ── 4. Compute outlet P ─────────────────────────────────────────────────
    const double P_out = P_in - pressureDropPa_;
    if (P_out <= 0.0) {
        solveStatus_ = QStringLiteral("Outlet pressure ≤ 0 Pa. Reduce ΔP.");
        emitError_(solveStatus_);
        emit resultsChanged();
        return;
    }
    if (pressureDropPa_ < 0.0) {
        emitWarn_(QStringLiteral("Pressure drop is negative — outlets > inlet pressure."));
    }
    calcOutletPressurePa_ = P_out;
    calcOutletTemperatureK_ = T_in;   // splitter is isothermal, no thermo

    // ── 5. Mass balance ─────────────────────────────────────────────────────
    for (int i = 0; i < outletCount_; ++i) {
        calcOutletFlowsKgph_[i] = mdot * outletFractions_[i];
    }

    solved_ = true;
    solveStatus_ = QStringLiteral("OK");

    // ── 6. Post-solve diagnostics ───────────────────────────────────────────

    // (a) Zero-fraction outlets are legal but unusual — flag as info so the
    //     user notices if they accidentally left an outlet at 0.
    for (int i = 0; i < outletCount_; ++i) {
        if (outletFractions_[i] == 0.0) {
            emitInfo_(QStringLiteral("Outlet %1 has zero fraction — outlet stream will carry no flow.")
                      .arg(i + 1));
        }
    }

    // (b) Outlets with non-zero fraction but no connected stream — info
    //     level; the result is computed but cannot propagate downstream.
    for (int i = 0; i < outletCount_; ++i) {
        if (outletFractions_[i] > 0.0 && outletStreamUnitIds_[i].isEmpty()) {
            emitInfo_(QStringLiteral("Outlet %1 has fraction %2 but no stream attached.")
                      .arg(i + 1)
                      .arg(outletFractions_[i], 0, 'f', 4));
        }
    }

    if (statusLevel_ == StatusLevel::None)
        statusLevel_ = StatusLevel::Ok;
    if (statusLevel_ == StatusLevel::Ok) {
        emitInfo_(QStringLiteral("Solve completed successfully."));
    }

    emit solvedChanged();
    emit resultsChanged();

    // ── 7. Push results to outlet streams ───────────────────────────────────
    for (int i = 0; i < outletCount_; ++i) {
        pushResultsToOutletStream_(i);
    }
}

void SplitterUnitState::pushResultsToOutletStream_(int outletIndex)
{
    if (outletIndex < 0 || outletIndex >= outletCount_)
        return;
    if (!flowsheetState_) return;
    const QString& streamId = outletStreamUnitIds_[outletIndex];
    if (streamId.isEmpty()) return;

    MaterialStreamState* outlet = flowsheetState_->findMaterialStreamByUnitId(streamId);
    if (!outlet) return;

    MaterialStreamState* feed = activeFeedStream();
    if (!feed) return;

    outlet->setFlowRateKgph(calcOutletFlowsKgph_[outletIndex]);
    outlet->setTemperatureK(feed->temperatureK());
    outlet->setPressurePa(calcOutletPressurePa_);

    // Composition is identical on every outlet (this is what makes a Tee
    // different from a component splitter / Sep block).
    if (feed->hasCustomComposition())
        outlet->setCompositionStd(feed->compositionStd());

    const QString pkgId = feed->selectedFluidPackageId();
    if (!pkgId.isEmpty() && outlet->selectedFluidPackageId() != pkgId)
        outlet->setSelectedFluidPackageId(pkgId);
}
