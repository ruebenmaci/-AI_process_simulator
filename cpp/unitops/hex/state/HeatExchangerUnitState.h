#pragma once

#include <QObject>
#include <QString>

#include <functional>
#include <string>

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "common/models/DiagnosticsModel.h"
#include "common/models/RunLogModel.h"

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// HeatExchangerUnitState  —  Phase 1: two-stream shell-and-tube HEX
//
// Four material stream ports:
//   hotIn   — hot-side feed     (target port, left-lower on icon)
//   hotOut  — hot-side product  (source port, right-upper on icon)
//   coldIn  — cold-side feed    (target port, left-upper on icon)
//   coldOut — cold-side product (source port, right-lower on icon)
//
// Specification modes (one must be set):
//   "duty"         — user specifies Q (kW); both outlet T are calculated
//   "hotOutletT"   — user specifies hot outlet T (K); Q and cold outlet T calculated
//   "coldOutletT"  — user specifies cold outlet T (K); Q and hot outlet T calculated
//
// Energy balance:
//   Q = ṁ_hot  · (H_hotIn  − H_hotOut)   [heat released by hot side]
//   Q = ṁ_cold · (H_coldOut − H_coldIn)  [heat absorbed by cold side]
//
// Flow arrangement: counter-current (Phase 1 only)
// ─────────────────────────────────────────────────────────────────────────────

class HeatExchangerUnitState : public ProcessUnitState
{
    Q_OBJECT

public:
    // Mirrors HeaterCoolerUnitState::StatusLevel. Drives the view's bottom
    // status chip color (None=gray, Ok=green, Warn=yellow, Fail=red,
    // Solving=blue). Solving is reserved for an async-solve refactor —
    // currently solve() is synchronous and never dwells on this value.
    enum class StatusLevel : int {
        None    = 0,
        Ok      = 1,
        Warn    = 2,
        Fail    = 3,
        Solving = 4
    };
    Q_ENUM(StatusLevel)

    // ── Stream connections ────────────────────────────────────────────────────
    Q_PROPERTY(QString connectedHotInStreamUnitId
               READ connectedHotInStreamUnitId   NOTIFY hotInStreamChanged)
    Q_PROPERTY(QString connectedHotOutStreamUnitId
               READ connectedHotOutStreamUnitId  NOTIFY hotOutStreamChanged)
    Q_PROPERTY(QString connectedColdInStreamUnitId
               READ connectedColdInStreamUnitId  NOTIFY coldInStreamChanged)
    Q_PROPERTY(QString connectedColdOutStreamUnitId
               READ connectedColdOutStreamUnitId NOTIFY coldOutStreamChanged)

    // ── Specification ─────────────────────────────────────────────────────────
    // specMode: "duty" | "hotOutletT" | "coldOutletT"
    Q_PROPERTY(QString specMode
               READ specMode WRITE setSpecMode NOTIFY specModeChanged)
    Q_PROPERTY(double dutyKW
               READ dutyKW WRITE setDutyKW NOTIFY dutyKWChanged)
    Q_PROPERTY(double hotOutletTK
               READ hotOutletTK WRITE setHotOutletTK NOTIFY hotOutletTKChanged)
    Q_PROPERTY(double coldOutletTK
               READ coldOutletTK WRITE setColdOutletTK NOTIFY coldOutletTKChanged)
    Q_PROPERTY(double hotSidePressureDropPa
               READ hotSidePressureDropPa WRITE setHotSidePressureDropPa
               NOTIFY hotSidePressureDropPaChanged)
    Q_PROPERTY(double coldSidePressureDropPa
               READ coldSidePressureDropPa WRITE setColdSidePressureDropPa
               NOTIFY coldSidePressureDropPaChanged)

    // ── Results (read-only) ───────────────────────────────────────────────────
    Q_PROPERTY(bool    solved             READ solved             NOTIFY solvedChanged)
    Q_PROPERTY(double  calcDutyKW         READ calcDutyKW         NOTIFY resultsChanged)
    Q_PROPERTY(double  calcHotOutTK       READ calcHotOutTK       NOTIFY resultsChanged)
    Q_PROPERTY(double  calcColdOutTK      READ calcColdOutTK      NOTIFY resultsChanged)
    Q_PROPERTY(double  calcHotOutVapFrac  READ calcHotOutVapFrac  NOTIFY resultsChanged)
    Q_PROPERTY(double  calcColdOutVapFrac READ calcColdOutVapFrac NOTIFY resultsChanged)
    Q_PROPERTY(double  calcLMTD          READ calcLMTD           NOTIFY resultsChanged)
    Q_PROPERTY(double  calcUA            READ calcUA             NOTIFY resultsChanged)
    Q_PROPERTY(double  calcApproachT     READ calcApproachT      NOTIFY resultsChanged)
    Q_PROPERTY(QString solveStatus        READ solveStatus        NOTIFY resultsChanged)

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    Q_PROPERTY(int statusLevel READ statusLevelInt NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
    Q_PROPERTY(RunLogModel*      runLogModel      READ runLogModel      CONSTANT)

public:
    explicit HeatExchangerUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters ─────────────────────────────────────────
    QString connectedHotInStreamUnitId()   const { return hotInStreamUnitId_; }
    QString connectedHotOutStreamUnitId()  const { return hotOutStreamUnitId_; }
    QString connectedColdInStreamUnitId()  const { return coldInStreamUnitId_; }
    QString connectedColdOutStreamUnitId() const { return coldOutStreamUnitId_; }

    void setConnectedHotInStreamUnitId(const QString& id);
    void setConnectedHotOutStreamUnitId(const QString& id);
    void setConnectedColdInStreamUnitId(const QString& id);
    void setConnectedColdOutStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check. All four ports are required.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ────────────────────────────────────────────────
    QString specMode()              const { return specMode_; }
    double  dutyKW()                const { return dutyKW_; }
    double  hotOutletTK()           const { return hotOutletTK_; }
    double  coldOutletTK()          const { return coldOutletTK_; }
    double  hotSidePressureDropPa() const { return hotSidePressureDropPa_; }
    double  coldSidePressureDropPa()const { return coldSidePressureDropPa_; }

    void setSpecMode(const QString& v);
    void setDutyKW(double v);
    void setHotOutletTK(double v);
    void setColdOutletTK(double v);
    void setHotSidePressureDropPa(double v);
    void setColdSidePressureDropPa(double v);

    // ── Result getters ────────────────────────────────────────────────────────
    bool    solved()             const { return solved_; }
    double  calcDutyKW()         const { return calcDutyKW_; }
    double  calcHotOutTK()       const { return calcHotOutTK_; }
    double  calcColdOutTK()      const { return calcColdOutTK_; }
    double  calcHotOutVapFrac()  const { return calcHotOutVapFrac_; }
    double  calcColdOutVapFrac() const { return calcColdOutVapFrac_; }
    double  calcLMTD()           const { return calcLMTD_; }
    double  calcUA()             const { return calcUA_; }
    double  calcApproachT()      const { return calcApproachT_; }
    QString solveStatus()        const { return solveStatus_; }

    StatusLevel statusLevel() const { return statusLevel_; }
    int statusLevelInt()      const { return static_cast<int>(statusLevel_); }

    DiagnosticsModel* diagnosticsModel() { return &diagnosticsModel_; }
    RunLogModel*      runLogModel()      { return &runLogModel_; }

    // ── Invokables ────────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

signals:
    void hotInStreamChanged();
    void hotOutStreamChanged();
    void coldInStreamChanged();
    void coldOutStreamChanged();

    void specModeChanged();
    void dutyKWChanged();
    void hotOutletTKChanged();
    void coldOutletTKChanged();
    void hotSidePressureDropPaChanged();
    void coldSidePressureDropPaChanged();

    void solvedChanged();
    void resultsChanged();

private:
    MaterialStreamState* findStream(const QString& unitId) const;
    void clearResults_();
    void pushResultsToOutletStreams_();

    // Diagnostic emission helpers — match HeaterCoolerUnitState's contract.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void appendRunLogLine_(const QString& line);
    void resetSolveArtifacts_();

    // ── Thermo helper: compute outlet T via PH flash given H_out ─────────────
    struct OutletResult {
        double T       = 0.0;
        double vapFrac = 0.0;
        bool   ok      = false;
        QString status;
    };
    OutletResult calcOutletFromH_(MaterialStreamState* inStream,
                                  double P_out, double H_out_kJkg,
                                  double T_seed,
                                  const std::function<void(const std::string&)>& logSink);

    FlowsheetState* flowsheetState_ = nullptr;

    // Connection IDs
    QString hotInStreamUnitId_;
    QString hotOutStreamUnitId_;
    QString coldInStreamUnitId_;
    QString coldOutStreamUnitId_;

    // Spec
    QString specMode_               = QStringLiteral("duty");
    double  dutyKW_                 = 1000.0;
    double  hotOutletTK_            = 350.0;
    double  coldOutletTK_           = 400.0;
    double  hotSidePressureDropPa_  = 0.0;
    double  coldSidePressureDropPa_ = 0.0;

    // Results
    bool    solved_             = false;
    double  calcDutyKW_         = 0.0;
    double  calcHotOutTK_       = 0.0;
    double  calcColdOutTK_      = 0.0;
    double  calcHotOutVapFrac_  = 0.0;
    double  calcColdOutVapFrac_ = 0.0;
    double  calcLMTD_           = 0.0;
    double  calcUA_             = 0.0;
    double  calcApproachT_      = 0.0;
    QString solveStatus_;

    // Status / diagnostics / thermo log
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
    RunLogModel      runLogModel_;
};
