#pragma once

#include <QObject>
#include <QString>
#include <QPointer>

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// HeaterCoolerUnitState
//
// Backs both the "heater" and "cooler" palette icons.  The two icons place
// units with type "heater" or "cooler" respectively; the iconKey_ mirrors that
// so the correct SVG appears on the PFD.  The underlying math is identical —
// a single-stream energy-balance black box:
//
//   Q  = ṁ · (H_out − H_in)          [kJ/h, positive = heat added]
//
// Specification modes (one must be set, not both):
//   "temperature"   — user sets outlet T; Q is calculated
//   "duty"          — user sets Q (kW);   outlet T is calculated via PH flash
//   "vaporFraction" — user sets outlet vapor fraction; Q calculated
//
// Connections
//   inlet  material stream  ("feed"    port on target side)
//   outlet material stream  ("product" port on source side)
//   inlet  energy stream    ("energyIn"  — optional utility supply, read-only kW)
//   outlet energy stream    ("energyOut" — calculated duty result,  kW)
//
// Energy stream convention (matches HYSYS):
//   Positive Q → heat is ADDED  to the process stream  (heater)
//   Negative Q → heat is REMOVED from the process stream (cooler)
//   The UI always shows |Q| with a direction label; the sign is an internal
//   convention only.
// ─────────────────────────────────────────────────────────────────────────────

class HeaterCoolerUnitState : public ProcessUnitState
{
    Q_OBJECT

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
    // specMode: "temperature" | "duty" | "vaporFraction"
    Q_PROPERTY(QString specMode
               READ specMode WRITE setSpecMode
               NOTIFY specModeChanged)

    Q_PROPERTY(double outletTemperatureK
               READ outletTemperatureK WRITE setOutletTemperatureK
               NOTIFY outletTemperatureKChanged)

    Q_PROPERTY(double dutyKW
               READ dutyKW WRITE setDutyKW
               NOTIFY dutyKWChanged)

    Q_PROPERTY(double outletVaporFraction
               READ outletVaporFraction WRITE setOutletVaporFraction
               NOTIFY outletVaporFractionChanged)

    Q_PROPERTY(double pressureDropPa
               READ pressureDropPa WRITE setPressureDropPa
               NOTIFY pressureDropPaChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved            READ solved            NOTIFY solvedChanged)
    Q_PROPERTY(double calcDutyKW        READ calcDutyKW        NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletTempK   READ calcOutletTempK   NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletVapFrac READ calcOutletVapFrac NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletPressurePa READ calcOutletPressurePa NOTIFY resultsChanged)
    Q_PROPERTY(QString solveStatus      READ solveStatus       NOTIFY resultsChanged)

    // ── Convenience display ──────────────────────────────────────────────────
    // True when Q < 0 (heat removed); the QML can show "Cooling duty" vs "Heating duty"
    Q_PROPERTY(bool isCooling READ isCooling NOTIFY resultsChanged)

public:
    explicit HeaterCoolerUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters (called by FlowsheetState) ─────────────
    QString connectedFeedStreamUnitId()      const { return feedStreamUnitId_; }
    QString connectedProductStreamUnitId()   const { return productStreamUnitId_; }
    QString connectedEnergyInStreamUnitId()  const { return energyInStreamUnitId_; }
    QString connectedEnergyOutStreamUnitId() const { return energyOutStreamUnitId_; }

    void setConnectedFeedStreamUnitId(const QString& id);
    void setConnectedProductStreamUnitId(const QString& id);
    void setConnectedEnergyInStreamUnitId(const QString& id);
    void setConnectedEnergyOutStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // ── Spec getters / setters ───────────────────────────────────────────────
    QString specMode()            const { return specMode_; }
    double  outletTemperatureK()  const { return outletTemperatureK_; }
    double  dutyKW()              const { return dutyKW_; }
    double  outletVaporFraction() const { return outletVaporFraction_; }
    double  pressureDropPa()      const { return pressureDropPa_; }

    void setSpecMode(const QString& v);
    void setOutletTemperatureK(double v);
    void setDutyKW(double v);
    void setOutletVaporFraction(double v);
    void setPressureDropPa(double v);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()              const { return solved_; }
    double  calcDutyKW()         const { return calcDutyKW_; }
    double  calcOutletTempK()    const { return calcOutletTempK_; }
    double  calcOutletVapFrac()  const { return calcOutletVapFrac_; }
    double  calcOutletPressurePa() const { return calcOutletPressurePa_; }
    QString solveStatus()        const { return solveStatus_; }
    bool    isCooling()          const { return solved_ && calcDutyKW_ < 0.0; }

    // ── Invokables ───────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

signals:
    void feedStreamChanged();
    void productStreamChanged();
    void energyInStreamChanged();
    void energyOutStreamChanged();

    void specModeChanged();
    void outletTemperatureKChanged();
    void dutyKWChanged();
    void outletVaporFractionChanged();
    void pressureDropPaChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeFeedStream() const;
    void clearResults_();
    void pushResultsToProductStream_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_  = nullptr;
    QString feedStreamUnitId_;
    QString productStreamUnitId_;
    QString energyInStreamUnitId_;
    QString energyOutStreamUnitId_;

    // ── Spec state ───────────────────────────────────────────────────────────
    QString specMode_            = QStringLiteral("temperature");
    double  outletTemperatureK_  = 500.0;   // K (227 °C) — sensible heater default
    double  dutyKW_              = 1000.0;  // kW — default guess
    double  outletVaporFraction_ = 0.0;
    double  pressureDropPa_      = 0.0;     // Pa ΔP across unit

    // ── Results ──────────────────────────────────────────────────────────────
    bool    solved_               = false;
    double  calcDutyKW_           = 0.0;
    double  calcOutletTempK_      = 0.0;
    double  calcOutletVapFrac_    = 0.0;
    double  calcOutletPressurePa_ = 0.0;
    QString solveStatus_;
};
