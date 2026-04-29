#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <vector>

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "common/models/DiagnosticsModel.h"

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// SplitterUnitState
//
// Tee / Stream Splitter (HYSYS "Tee" / Aspen Plus "FSplit"). Splits a single
// inlet stream into N outlet streams of identical composition, T, and P,
// distributed by user-specified flow fractions that must sum to 1.0.
//
// Topology
//   inlet:  one feed material stream  (port "feed")
//   outlet: N material streams        (ports "outlet1", "outlet2", ..., "outletN")
//
// The number of outlets is user-controlled via outletCount (default 2, range
// 2-8). Increasing outletCount allocates new ports; decreasing it disconnects
// any streams currently bound to ports that no longer exist (handled by
// FlowsheetState when the property change is observed).
//
// Specification
//   outletFractions: QVariantList of doubles, parallel to outlet1..outletN.
//                    Must sum to 1.0 ± fractionTolerance to be solvable.
//                    Validated during solve() — if out of tolerance, an error
//                    diagnostic is emitted and the solve does not push results.
//
//   pressureDropPa:  ΔP applied across the unit (same on every outlet). Default 0.
//                    P_outlet = P_feed - ΔP for all outlets.
//
// Math (no thermo, just mass balance):
//   For each outlet i:
//     outlet_i.flow         = feed.flow * outletFractions[i]
//     outlet_i.composition  = feed.composition         (mass-fraction copy)
//     outlet_i.temperature  = feed.temperature
//     outlet_i.pressure     = feed.pressure - pressureDropPa
//
// Future extensions (not in v1):
//   - "specify flow on N-1 outlets, balance is the rest" mode (HYSYS-style)
//   - per-outlet pressure drops
//   - heat-loss term for non-isothermal splitting
// ─────────────────────────────────────────────────────────────────────────────

class SplitterUnitState : public ProcessUnitState
{
    Q_OBJECT

public:
    enum class StatusLevel : int {
        None    = 0,
        Ok      = 1,
        Warn    = 2,
        Fail    = 3,
        Solving = 4
    };
    Q_ENUM(StatusLevel)

    // Bounds on the outlet count. Two is the minimum (anything less is a
    // pass-through, not a splitter); eight is a soft ceiling that covers
    // realistic refinery splits while keeping the property view tractable.
    static constexpr int kMinOutlets = 2;
    static constexpr int kMaxOutlets = 8;
    static constexpr double kFractionTolerance = 1.0e-4;

    // ── Connections ──────────────────────────────────────────────────────────
    Q_PROPERTY(QString connectedFeedStreamUnitId
               READ connectedFeedStreamUnitId
               NOTIFY feedStreamChanged)

    // QVariantList of QString unit IDs, length == outletCount, with empty
    // strings for unconnected ports. The QML view binds to this so its
    // "Connections" group can render one row per outlet.
    Q_PROPERTY(QVariantList connectedOutletStreamUnitIds
               READ connectedOutletStreamUnitIdsVariant
               NOTIFY outletStreamsChanged)

    // ── Specification ────────────────────────────────────────────────────────
    Q_PROPERTY(int outletCount
               READ outletCount WRITE setOutletCount
               NOTIFY outletCountChanged)

    // QVariantList of doubles, length == outletCount. Must sum to 1.0 within
    // fractionTolerance for the solve to succeed. The QML view edits each
    // entry through setOutletFraction(index, value) — the whole list can
    // also be replaced via setOutletFractions().
    Q_PROPERTY(QVariantList outletFractions
               READ outletFractionsVariant WRITE setOutletFractionsVariant
               NOTIFY outletFractionsChanged)

    // Live-computed sum of outletFractions. The QML view binds to this and
    // turns the on-screen total red when it deviates from 1.0 by more than
    // fractionTolerance, giving the user immediate feedback.
    Q_PROPERTY(double outletFractionSum
               READ outletFractionSum
               NOTIFY outletFractionsChanged)

    // True iff abs(outletFractionSum - 1.0) <= fractionTolerance. Bound by
    // the QML view to colour the sum display and to enable/disable Solve.
    Q_PROPERTY(bool outletFractionsBalanced
               READ outletFractionsBalanced
               NOTIFY outletFractionsChanged)

    Q_PROPERTY(double pressureDropPa
               READ pressureDropPa WRITE setPressureDropPa
               NOTIFY pressureDropPaChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved              READ solved              NOTIFY solvedChanged)

    // Per-outlet calculated mass flow (kg/h). Length == outletCount.
    Q_PROPERTY(QVariantList calcOutletFlowsKgph
               READ calcOutletFlowsKgphVariant
               NOTIFY resultsChanged)

    Q_PROPERTY(double calcOutletPressurePa
               READ calcOutletPressurePa
               NOTIFY resultsChanged)

    Q_PROPERTY(double calcOutletTemperatureK
               READ calcOutletTemperatureK
               NOTIFY resultsChanged)

    Q_PROPERTY(QString solveStatus        READ solveStatus         NOTIFY resultsChanged)

    // ── Status / diagnostics ─────────────────────────────────────────────────
    Q_PROPERTY(int statusLevel READ statusLevelInt NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)

public:
    explicit SplitterUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters (called by FlowsheetState) ─────────────
    QString connectedFeedStreamUnitId() const { return feedStreamUnitId_; }
    void setConnectedFeedStreamUnitId(const QString& id);

    // Returns the unit ID of the stream connected to the i-th outlet
    // (0-indexed). Returns "" if no stream bound or i is out of range.
    Q_INVOKABLE QString connectedOutletStreamUnitId(int outletIndex) const;

    // Binds (or unbinds, when streamId is empty) a stream to the i-th outlet.
    // 0-indexed. No-op if outletIndex is out of [0, outletCount).
    void setConnectedOutletStreamUnitId(int outletIndex, const QString& id);

    // QVariantList projection used by the QML Q_PROPERTY binding.
    QVariantList connectedOutletStreamUnitIdsVariant() const;

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ───────────────────────────────────────────────
    int    outletCount()                 const { return outletCount_; }
    double outletFraction(int i)         const;
    double outletFractionSum()           const;
    bool   outletFractionsBalanced()     const;
    double pressureDropPa()              const { return pressureDropPa_; }

    void setOutletCount(int n);

    // Sets a single outlet's flow fraction. 0-indexed. No-op if i out of
    // range. Emits outletFractionsChanged whether or not the value differs
    // (so the QML view always sees the sum-display update).
    Q_INVOKABLE void setOutletFraction(int outletIndex, double value);

    void setPressureDropPa(double v);

    // QVariantList projections used by the QML Q_PROPERTY bindings.
    QVariantList outletFractionsVariant() const;
    void setOutletFractionsVariant(const QVariantList& list);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()                 const { return solved_; }
    double  calcOutletFlowKgph(int i) const;
    QVariantList calcOutletFlowsKgphVariant() const;
    double  calcOutletPressurePa()   const { return calcOutletPressurePa_; }
    double  calcOutletTemperatureK() const { return calcOutletTemperatureK_; }
    QString solveStatus()            const { return solveStatus_; }

    StatusLevel statusLevel()        const { return statusLevel_; }
    int statusLevelInt()             const { return static_cast<int>(statusLevel_); }

    DiagnosticsModel* diagnosticsModel() { return &diagnosticsModel_; }

    // ── Invokables ───────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

    // Distributes flow fractions evenly across all outlets (each gets
    // 1.0/outletCount), discarding the user's existing values. Convenience
    // for the QML "Even split" button.
    Q_INVOKABLE void distributeFractionsEvenly();

    // Scales existing fractions so they sum to 1.0, preserving the user's
    // relative split. Use case: user enters [0.5, 0.4, 0.4] (sum 1.3),
    // clicks Normalize, gets [0.385, 0.308, 0.308]. Edge case: if every
    // fraction is zero, falls back to an even distribution and emits a
    // warning. Bound to the QML "Normalize" button.
    Q_INVOKABLE void normalizeFractions();

signals:
    void feedStreamChanged();
    void outletStreamsChanged();

    void outletCountChanged();
    void outletFractionsChanged();
    void pressureDropPaChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeFeedStream() const;
    void clearResults_();
    void pushResultsToOutletStream_(int outletIndex);

    // Resizes outletFractions_ and outletStreamUnitIds_ to match
    // outletCount_, preserving existing entries within the new size and
    // appending zeros / empty strings as needed. Called after outletCount_
    // is changed.
    void resizeOutletVectors_();

    // Diagnostic emit helpers — same pattern as other unit ops.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void resetSolveArtifacts_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_ = nullptr;
    QString feedStreamUnitId_;
    std::vector<QString> outletStreamUnitIds_;   // length == outletCount_

    // ── Spec state ───────────────────────────────────────────────────────────
    int                 outletCount_     = 2;
    std::vector<double> outletFractions_;        // length == outletCount_
    double              pressureDropPa_  = 0.0;

    // ── Results ──────────────────────────────────────────────────────────────
    bool                solved_                = false;
    std::vector<double> calcOutletFlowsKgph_;    // length == outletCount_ when solved
    double              calcOutletPressurePa_  = 0.0;
    double              calcOutletTemperatureK_ = 0.0;
    QString             solveStatus_;

    // ── Status / diagnostics ─────────────────────────────────────────────────
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
};
