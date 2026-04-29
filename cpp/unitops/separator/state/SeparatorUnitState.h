#pragma once

#include <QObject>
#include <QString>
#include <QPointer>

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "common/models/DiagnosticsModel.h"
#include "common/models/RunLogModel.h"

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// SeparatorUnitState
//
// 2-phase vapor-liquid separator (HYSYS "Separator" / Aspen Plus "Flash2").
// Models a single equilibrium stage: feed enters, the contents flash to
// vapor-liquid equilibrium at vessel (T, P), and two outlet streams leave —
// one vapor, one liquid — at their equilibrium compositions.
//
// Topology
//   inlet  material stream  ("feed"   — single feed; multi-feed deferred)
//   outlet material stream  ("vapor"  — vapor product, equilibrium composition y)
//   outlet material stream  ("liquid" — liquid product, equilibrium composition x)
//
// Specification modes (one must be set)
//   "adiabatic"   — no duty; PH flash at (H_in, P_out) finds T_out and V
//   "duty"        — user sets Q (kW); PH flash at (H_in + Q·3600/ṁ, P_out)
//                   finds T_out and V
//   "temperature" — user sets vessel T; PT flash at (P_out, T) finds V
//                   and the duty Q = ṁ·(H_out − H_in) is back-calculated
//
// Pressure handling (matches HeaterCooler)
//   pressureDropPa_ specifies ΔP across the vessel; P_out = P_in − ΔP.
//   Defaults to 0 (no drop, vessel at feed pressure).
//
// Single-phase handling
//   If the flash produces a single phase (V == 0 → all liquid; V == 1 → all
//   vapor), the corresponding "absent" outlet stream gets zero mass flow but
//   keeps the feed composition (so downstream consumers see a sensible state).
//   A diagnostics warning is emitted but the solve does not fail — single-
//   phase separation is a valid (if degenerate) operating point.
//
// Energy stream
//   Deferred to a later phase. The duty result is exposed via calcDutyKW()
//   regardless, so an energy stream connection can be added later without
//   reworking the solve.
// ─────────────────────────────────────────────────────────────────────────────

class SeparatorUnitState : public ProcessUnitState
{
    Q_OBJECT

public:
    enum class StatusLevel : int {
        None    = 0,  // pristine — unit has not been solved yet
        Ok      = 1,  // solve succeeded, no warnings
        Warn    = 2,  // solve succeeded with warnings (e.g. single-phase result)
        Fail    = 3,  // solve failed
        Solving = 4   // reserved for future async-solve refactor
    };
    Q_ENUM(StatusLevel)

    // ── Connections ──────────────────────────────────────────────────────────
    Q_PROPERTY(QString connectedFeedStreamUnitId
               READ connectedFeedStreamUnitId
               NOTIFY feedStreamChanged)
    Q_PROPERTY(QString connectedVaporStreamUnitId
               READ connectedVaporStreamUnitId
               NOTIFY vaporStreamChanged)
    Q_PROPERTY(QString connectedLiquidStreamUnitId
               READ connectedLiquidStreamUnitId
               NOTIFY liquidStreamChanged)

    // ── Specification ────────────────────────────────────────────────────────
    // specMode: "adiabatic" | "duty" | "temperature"
    Q_PROPERTY(QString specMode
               READ specMode WRITE setSpecMode
               NOTIFY specModeChanged)

    // Used only when specMode == "temperature"
    Q_PROPERTY(double vesselTemperatureK
               READ vesselTemperatureK WRITE setVesselTemperatureK
               NOTIFY vesselTemperatureKChanged)

    // Used only when specMode == "duty"
    Q_PROPERTY(double dutyKW
               READ dutyKW WRITE setDutyKW
               NOTIFY dutyKWChanged)

    // Pressure drop across the vessel: P_out = P_in − ΔP. Default 0 Pa.
    Q_PROPERTY(double pressureDropPa
               READ pressureDropPa WRITE setPressureDropPa
               NOTIFY pressureDropPaChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved                 READ solved                 NOTIFY solvedChanged)
    Q_PROPERTY(double calcVesselTempK        READ calcVesselTempK        NOTIFY resultsChanged)
    Q_PROPERTY(double calcVesselPressurePa   READ calcVesselPressurePa   NOTIFY resultsChanged)
    Q_PROPERTY(double calcVaporMoleFrac      READ calcVaporMoleFrac      NOTIFY resultsChanged)
    Q_PROPERTY(double calcVaporMassFrac      READ calcVaporMassFrac      NOTIFY resultsChanged)
    Q_PROPERTY(double calcVaporFlowKgph      READ calcVaporFlowKgph      NOTIFY resultsChanged)
    Q_PROPERTY(double calcLiquidFlowKgph     READ calcLiquidFlowKgph     NOTIFY resultsChanged)
    Q_PROPERTY(double calcDutyKW             READ calcDutyKW             NOTIFY resultsChanged)
    Q_PROPERTY(QString solveStatus           READ solveStatus            NOTIFY resultsChanged)

    // True when the flash result was single-phase (one outlet has zero flow)
    Q_PROPERTY(bool isSinglePhase            READ isSinglePhase          NOTIFY resultsChanged)

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    Q_PROPERTY(int statusLevel READ statusLevelInt NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
    Q_PROPERTY(RunLogModel*      runLogModel      READ runLogModel      CONSTANT)

public:
    explicit SeparatorUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters (called by FlowsheetState) ─────────────
    QString connectedFeedStreamUnitId()   const { return feedStreamUnitId_;   }
    QString connectedVaporStreamUnitId()  const { return vaporStreamUnitId_;  }
    QString connectedLiquidStreamUnitId() const { return liquidStreamUnitId_; }

    void setConnectedFeedStreamUnitId(const QString& id);
    void setConnectedVaporStreamUnitId(const QString& id);
    void setConnectedLiquidStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ───────────────────────────────────────────────
    QString specMode()             const { return specMode_; }
    double  vesselTemperatureK()   const { return vesselTemperatureK_; }
    double  dutyKW()               const { return dutyKW_; }
    double  pressureDropPa()       const { return pressureDropPa_; }

    void setSpecMode(const QString& v);
    void setVesselTemperatureK(double v);
    void setDutyKW(double v);
    void setPressureDropPa(double v);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()               const { return solved_; }
    double  calcVesselTempK()      const { return calcVesselTempK_; }
    double  calcVesselPressurePa() const { return calcVesselPressurePa_; }
    double  calcVaporMoleFrac()    const { return calcVaporMoleFrac_; }
    double  calcVaporMassFrac()    const { return calcVaporMassFrac_; }
    double  calcVaporFlowKgph()    const { return calcVaporFlowKgph_; }
    double  calcLiquidFlowKgph()   const { return calcLiquidFlowKgph_; }
    double  calcDutyKW()           const { return calcDutyKW_; }
    QString solveStatus()          const { return solveStatus_; }
    bool    isSinglePhase()        const { return solved_ && singlePhase_; }

    StatusLevel statusLevel() const { return statusLevel_; }
    int statusLevelInt()      const { return static_cast<int>(statusLevel_); }

    DiagnosticsModel* diagnosticsModel() { return &diagnosticsModel_; }
    RunLogModel*      runLogModel()      { return &runLogModel_; }

    // ── Invokables ───────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

signals:
    void feedStreamChanged();
    void vaporStreamChanged();
    void liquidStreamChanged();

    void specModeChanged();
    void vesselTemperatureKChanged();
    void dutyKWChanged();
    void pressureDropPaChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeFeedStream() const;
    void clearResults_();

    // Pushes vapor-phase results (composition y, mass flow, T, P) onto the
    // connected vapor outlet stream. No-op if the stream is not bound.
    void pushResultsToVaporStream_();

    // Pushes liquid-phase results (composition x, mass flow, T, P) onto the
    // connected liquid outlet stream. No-op if the stream is not bound.
    void pushResultsToLiquidStream_();

    // Diagnostic emission helpers — same pattern as HeaterCoolerUnitState.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void appendRunLogLine_(const QString& line);
    void resetSolveArtifacts_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_ = nullptr;
    QString feedStreamUnitId_;
    QString vaporStreamUnitId_;
    QString liquidStreamUnitId_;

    // ── Spec state ───────────────────────────────────────────────────────────
    QString specMode_           = QStringLiteral("adiabatic");
    double  vesselTemperatureK_ = 350.0;   // K — only used for "temperature" mode
    double  dutyKW_             = 0.0;     // kW — only used for "duty" mode
    double  pressureDropPa_     = 0.0;     // Pa ΔP across vessel

    // ── Results ──────────────────────────────────────────────────────────────
    bool    solved_                 = false;
    bool    singlePhase_            = false;
    double  calcVesselTempK_        = 0.0;
    double  calcVesselPressurePa_   = 0.0;
    double  calcVaporMoleFrac_      = 0.0;  // V on a mole basis
    double  calcVaporMassFrac_      = 0.0;  // V on a mass basis (used for flow split)
    double  calcVaporFlowKgph_      = 0.0;
    double  calcLiquidFlowKgph_     = 0.0;
    double  calcDutyKW_             = 0.0;  // signed: + heat in, − heat out
    QString solveStatus_;

    // Equilibrium compositions from the flash, stored so push*Stream_() can
    // populate the outlet streams. Indexed by component-list order.
    std::vector<double> calcVaporCompositionY_;
    std::vector<double> calcLiquidCompositionX_;

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
    RunLogModel      runLogModel_;
};
