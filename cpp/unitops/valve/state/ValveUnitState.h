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
// ValveUnitState
//
// Adiabatic throttling valve / expansion valve. Single in / single out. Modeled
// as a passive isenthalpic pressure dropper (Joule-Thomson expansion):
//
//   H_out = H_in                            (no shaft work, no heat exchange)
//   P_out = user-supplied                   (or P_in − ΔP)
//   T_out = PH flash at (P_out, H_in)
//
// The PH flash naturally captures the JT temperature change. For an ideal gas
// the JT coefficient is zero (T_out = T_in); for real fluids dropped across
// a valve the temperature usually drops (positive μ_JT region, e.g. methane,
// natural gas, refrigerants below their inversion temperature) but can rise
// for hydrogen and helium at room temperature. The flash also handles any
// flashing across the bubble line — common in liquid-letdown service where
// the upstream subcooled liquid partially vaporizes downstream.
//
// This is the mirror of the pump:
//
//                                Pump (active)            Valve (passive)
//   ─────────────────────────  ───────────────────  ──────────────────────
//   ΔP                         positive (rise)       negative-of-drop
//   Process effect             H_out > H_in (work)   H_out = H_in (throttle)
//   Friction                   captured via η        intrinsic to throttling
//   Energy stream              shaft power           none
//
// Specification modes (HYSYS-style):
//   "outletPressure"  — user sets P_out; ΔP_drop = P_in − P_out is calculated
//   "deltaP"          — user sets ΔP_drop (positive number); P_out = P_in − ΔP_drop
//
// Sign convention: deltaPPa is stored as a POSITIVE pressure drop (drop = P_in
// − P_out). A negative or zero drop generates a Warn diagnostic — the valve
// would be acting as a pump, which is non-physical for a passive throttle.
//
// Connections
//   inlet  material stream  ("feed"     port on target side)
//   outlet material stream  ("product"  port on source side)
//
// (No energy streams. A throttle is adiabatic and does no shaft work — there
//  is no power to report. This is the main structural difference from the
//  pump's connection set.)
// ─────────────────────────────────────────────────────────────────────────────

class ValveUnitState : public ProcessUnitState
{
    Q_OBJECT

public:
    // StatusLevel mirrors the chip in the View's bottom bar. Same semantics
    // as PumpUnitState / HeaterCoolerUnitState — see those for full enum docs.
    enum class StatusLevel : int {
        None    = 0,
        Ok      = 1,
        Warn    = 2,
        Fail    = 3,
        Solving = 4
    };
    Q_ENUM(StatusLevel)

    // ── Connections ──────────────────────────────────────────────────────────
    Q_PROPERTY(QString connectedFeedStreamUnitId
               READ connectedFeedStreamUnitId
               NOTIFY feedStreamChanged)
    Q_PROPERTY(QString connectedProductStreamUnitId
               READ connectedProductStreamUnitId
               NOTIFY productStreamChanged)

    // ── Specification ────────────────────────────────────────────────────────
    // specMode: "outletPressure" | "deltaP"
    Q_PROPERTY(QString specMode
               READ specMode WRITE setSpecMode
               NOTIFY specModeChanged)

    Q_PROPERTY(double outletPressurePa
               READ outletPressurePa WRITE setOutletPressurePa
               NOTIFY outletPressurePaChanged)

    // Stored as a POSITIVE pressure drop (P_in − P_out). UI prompts the user
    // for "ΔP (drop)" as a positive number; the math layer subtracts it from
    // P_in. This avoids the sign-convention confusion that bites people when
    // they're typing "5 bar" expecting a 5-bar drop.
    Q_PROPERTY(double deltaPPa
               READ deltaPPa WRITE setDeltaPPa
               NOTIFY deltaPPaChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved              READ solved              NOTIFY solvedChanged)
    Q_PROPERTY(double calcOutletPressurePa READ calcOutletPressurePa NOTIFY resultsChanged)
    Q_PROPERTY(double calcDeltaPPa        READ calcDeltaPPa        NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletTempK     READ calcOutletTempK     NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletVapFrac   READ calcOutletVapFrac   NOTIFY resultsChanged)
    Q_PROPERTY(double calcDeltaTK         READ calcDeltaTK         NOTIFY resultsChanged)
    Q_PROPERTY(double calcInletVapFrac    READ calcInletVapFrac    NOTIFY resultsChanged)
    Q_PROPERTY(QString solveStatus        READ solveStatus         NOTIFY resultsChanged)

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    Q_PROPERTY(int statusLevel READ statusLevelInt NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
    Q_PROPERTY(RunLogModel*      runLogModel      READ runLogModel      CONSTANT)

public:
    explicit ValveUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters ─────────────────────────────────────────
    QString connectedFeedStreamUnitId()    const { return feedStreamUnitId_; }
    QString connectedProductStreamUnitId() const { return productStreamUnitId_; }

    void setConnectedFeedStreamUnitId(const QString& id);
    void setConnectedProductStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check; consumed by FlowsheetStatusModel.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ───────────────────────────────────────────────
    QString specMode()         const { return specMode_; }
    double  outletPressurePa() const { return outletPressurePa_; }
    double  deltaPPa()         const { return deltaPPa_; }

    void setSpecMode(const QString& v);
    void setOutletPressurePa(double v);
    void setDeltaPPa(double v);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()                const { return solved_; }
    double  calcOutletPressurePa()  const { return calcOutletPressurePa_; }
    double  calcDeltaPPa()          const { return calcDeltaPPa_; }
    double  calcOutletTempK()       const { return calcOutletTempK_; }
    double  calcOutletVapFrac()     const { return calcOutletVapFrac_; }
    double  calcDeltaTK()           const { return calcDeltaTK_; }
    double  calcInletVapFrac()      const { return calcInletVapFrac_; }
    QString solveStatus()           const { return solveStatus_; }

    StatusLevel statusLevel() const { return statusLevel_; }
    int statusLevelInt()      const { return static_cast<int>(statusLevel_); }

    DiagnosticsModel* diagnosticsModel() { return &diagnosticsModel_; }
    RunLogModel*      runLogModel()      { return &runLogModel_; }

    // ── Invokables ───────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

signals:
    void feedStreamChanged();
    void productStreamChanged();

    void specModeChanged();
    void outletPressurePaChanged();
    void deltaPPaChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeFeedStream() const;
    void clearResults_();
    void pushResultsToProductStream_();

    // Diagnostic / log helpers — same conventions as PumpUnitState.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void appendRunLogLine_(const QString& line);
    void resetSolveArtifacts_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_  = nullptr;
    QString feedStreamUnitId_;
    QString productStreamUnitId_;

    // ── Spec state ───────────────────────────────────────────────────────────
    // Defaults: 2 bar drop is a typical small-control-valve / let-down spec.
    QString specMode_         = QStringLiteral("deltaP");
    double  outletPressurePa_ = 1.0e5;     // 1 bar abs (used in outletPressure mode)
    double  deltaPPa_         = 2.0e5;     // 2 bar drop

    // ── Results ──────────────────────────────────────────────────────────────
    bool    solved_               = false;
    double  calcOutletPressurePa_ = 0.0;
    double  calcDeltaPPa_         = 0.0;
    double  calcOutletTempK_      = 0.0;
    double  calcOutletVapFrac_    = 0.0;
    double  calcDeltaTK_          = 0.0;   // T_out − T_in (signed; usually ≤ 0)
    double  calcInletVapFrac_     = 0.0;
    QString solveStatus_;

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
    RunLogModel      runLogModel_;
};
