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
// PumpUnitState
//
// Liquid-phase centrifugal pump. Single in / single out plus an optional
// energy-stream pair for the calculated shaft power. Modeled as an adiabatic
// pressure raiser with a user-supplied efficiency:
//
//   W_ideal  = ṁ · ΔP / ρ_in            [W]    (incompressible liquid)
//   W_shaft  = W_ideal / η_p            [W]    (η_p = adiabatic efficiency)
//   ΔH       = W_shaft / ṁ              [J/kg → kJ/kg]
//   H_out    = H_in + ΔH
//   T_out    = PH flash at (P_out, H_out)
//
// The energy lost to friction (W_shaft − W_ideal) ends up as enthalpy in the
// fluid, which raises T_out by a small amount. For a typical η ≈ 0.75 pump
// across 5 bar ΔP on water, ΔT ≈ 0.4 K — so the temperature rise is real
// but usually small. PH flash captures it correctly without us hard-coding
// a Cp.
//
// Specification modes (HYSYS-style):
//   "outletPressure"  — user sets P_out;          ΔP and W_shaft are calculated
//   "deltaP"          — user sets ΔP;             P_out and W_shaft calculated
//   "power"           — user sets W_shaft;        ΔP and P_out calculated
//                       (ΔP = W_shaft · η_p · ρ_in / ṁ)
//
// Connections
//   inlet  material stream  ("feed"     port on target side)
//   outlet material stream  ("product"  port on source side)
//   inlet  energy stream    ("energyIn"  — optional driver supply, read-only kW)
//   outlet energy stream    ("energyOut" — calculated shaft power result, kW)
//
// Energy-stream sign convention (pump consumes shaft work):
//   W_shaft is always reported as a positive number. The pump direction is
//   intrinsic: pumps add pressure, never remove it. A negative ΔP user-spec
//   produces a Fail diagnostic (would require turbine/expander).
// ─────────────────────────────────────────────────────────────────────────────

class PumpUnitState : public ProcessUnitState
{
    Q_OBJECT

public:
    // StatusLevel mirrors the chip in the View's bottom bar. Same semantics
    // as HeaterCoolerUnitState — see that class for full enum docs.
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
    Q_PROPERTY(QString connectedEnergyInStreamUnitId
               READ connectedEnergyInStreamUnitId
               NOTIFY energyInStreamChanged)
    Q_PROPERTY(QString connectedEnergyOutStreamUnitId
               READ connectedEnergyOutStreamUnitId
               NOTIFY energyOutStreamChanged)

    // ── Specification ────────────────────────────────────────────────────────
    // specMode: "outletPressure" | "deltaP" | "power"
    Q_PROPERTY(QString specMode
               READ specMode WRITE setSpecMode
               NOTIFY specModeChanged)

    Q_PROPERTY(double outletPressurePa
               READ outletPressurePa WRITE setOutletPressurePa
               NOTIFY outletPressurePaChanged)

    Q_PROPERTY(double deltaPPa
               READ deltaPPa WRITE setDeltaPPa
               NOTIFY deltaPPaChanged)

    Q_PROPERTY(double powerKW
               READ powerKW WRITE setPowerKW
               NOTIFY powerKWChanged)

    Q_PROPERTY(double adiabaticEfficiency
               READ adiabaticEfficiency WRITE setAdiabaticEfficiency
               NOTIFY adiabaticEfficiencyChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved              READ solved              NOTIFY solvedChanged)
    Q_PROPERTY(double calcOutletPressurePa READ calcOutletPressurePa NOTIFY resultsChanged)
    Q_PROPERTY(double calcDeltaPPa        READ calcDeltaPPa        NOTIFY resultsChanged)
    Q_PROPERTY(double calcPowerKW         READ calcPowerKW         NOTIFY resultsChanged)
    Q_PROPERTY(double calcIdealPowerKW    READ calcIdealPowerKW    NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletTempK     READ calcOutletTempK     NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletVapFrac   READ calcOutletVapFrac   NOTIFY resultsChanged)
    Q_PROPERTY(double calcInletDensityKgM3 READ calcInletDensityKgM3 NOTIFY resultsChanged)
    Q_PROPERTY(QString solveStatus        READ solveStatus         NOTIFY resultsChanged)

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    Q_PROPERTY(int statusLevel READ statusLevelInt NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
    Q_PROPERTY(RunLogModel*      runLogModel      READ runLogModel      CONSTANT)

public:
    explicit PumpUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters ─────────────────────────────────────────
    QString connectedFeedStreamUnitId()      const { return feedStreamUnitId_; }
    QString connectedProductStreamUnitId()   const { return productStreamUnitId_; }
    QString connectedEnergyInStreamUnitId()  const { return energyInStreamUnitId_; }
    QString connectedEnergyOutStreamUnitId() const { return energyOutStreamUnitId_; }

    void setConnectedFeedStreamUnitId(const QString& id);
    void setConnectedProductStreamUnitId(const QString& id);
    void setConnectedEnergyInStreamUnitId(const QString& id);
    void setConnectedEnergyOutStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check; consumed by FlowsheetStatusModel.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ───────────────────────────────────────────────
    QString specMode()             const { return specMode_; }
    double  outletPressurePa()     const { return outletPressurePa_; }
    double  deltaPPa()             const { return deltaPPa_; }
    double  powerKW()              const { return powerKW_; }
    double  adiabaticEfficiency()  const { return adiabaticEfficiency_; }

    void setSpecMode(const QString& v);
    void setOutletPressurePa(double v);
    void setDeltaPPa(double v);
    void setPowerKW(double v);
    void setAdiabaticEfficiency(double v);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()                const { return solved_; }
    double  calcOutletPressurePa()  const { return calcOutletPressurePa_; }
    double  calcDeltaPPa()          const { return calcDeltaPPa_; }
    double  calcPowerKW()           const { return calcPowerKW_; }
    double  calcIdealPowerKW()      const { return calcIdealPowerKW_; }
    double  calcOutletTempK()       const { return calcOutletTempK_; }
    double  calcOutletVapFrac()     const { return calcOutletVapFrac_; }
    double  calcInletDensityKgM3()  const { return calcInletDensityKgM3_; }
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
    void energyInStreamChanged();
    void energyOutStreamChanged();

    void specModeChanged();
    void outletPressurePaChanged();
    void deltaPPaChanged();
    void powerKWChanged();
    void adiabaticEfficiencyChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeFeedStream() const;
    void clearResults_();
    void pushResultsToProductStream_();

    // Diagnostic / log helpers — same conventions as HeaterCoolerUnitState.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void appendRunLogLine_(const QString& line);
    void resetSolveArtifacts_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_  = nullptr;
    QString feedStreamUnitId_;
    QString productStreamUnitId_;
    QString energyInStreamUnitId_;
    QString energyOutStreamUnitId_;

    // ── Spec state ───────────────────────────────────────────────────────────
    // Defaults: 5 bar ΔP at 75% efficiency — sensible centrifugal-pump default.
    QString specMode_           = QStringLiteral("deltaP");
    double  outletPressurePa_   = 6.0e5;     // 6 bar abs (used in outletPressure mode)
    double  deltaPPa_           = 5.0e5;     // 5 bar lift
    double  powerKW_            = 10.0;      // 10 kW (used in power mode)
    double  adiabaticEfficiency_= 0.75;      // 75 % typical centrifugal

    // ── Results ──────────────────────────────────────────────────────────────
    bool    solved_               = false;
    double  calcOutletPressurePa_ = 0.0;
    double  calcDeltaPPa_         = 0.0;
    double  calcPowerKW_          = 0.0;
    double  calcIdealPowerKW_     = 0.0;
    double  calcOutletTempK_      = 0.0;
    double  calcOutletVapFrac_    = 0.0;
    double  calcInletDensityKgM3_ = 0.0;
    QString solveStatus_;

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
    RunLogModel      runLogModel_;
};
