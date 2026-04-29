#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <vector>

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "common/models/DiagnosticsModel.h"
#include "common/models/RunLogModel.h"

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// MixerUnitState
//
// Mixer (HYSYS "Mixer" / Aspen Plus "Mixer" block). Combines N material feed
// streams into one product stream via mass and energy balance, then a PH
// flash at the chosen outlet pressure determines the product's T and phase
// distribution.
//
// Topology
//   inlets:  N material streams   (ports "inlet1", "inlet2", ..., "inletN")
//   outlet:  one material stream  (port  "product")
//
// The number of inlets is user-controlled via inletCount (default 2, range
// 2-8). Increasing inletCount allocates new inlet ports; decreasing it
// disconnects any streams currently bound to ports that no longer exist —
// the same dynamic-port pattern SplitterUnitState uses for outlets, just
// flipped to the inlet side.
//
// Specifications
//   pressureMode:               outlet-pressure assignment rule
//     "lowestInlet"  (default) — outlet P = min(inlet P_i)            [HYSYS default]
//     "equalizeAll"            — outlet P = max(inlet P_i)
//                                (warns when inlet pressures differ —
//                                 a real "Equalize All" requires bumping
//                                 lower-pressure feeds, which is an upstream
//                                 modeling concern, not our problem here)
//     "specified"              — outlet P = specifiedOutletPressurePa
//                                (Aspen-style explicit override)
//
//   specifiedOutletPressurePa:  used only when pressureMode == "specified".
//                               No effect otherwise.
//
//   flashPhaseMode:             how to determine outlet T and phase
//     "vle"             (default) — adiabatic PH flash at (H_combined, P_out)
//                                   finds T_out and V (vapor mole frac)
//     "massBalanceOnly"           — no flash; outlet T is mass-weighted
//                                   inlet T (rough estimate), V is unset.
//                                   Useful for non-equilibrium feeds; the
//                                   result is approximate and clearly flagged.
//
// Math (mass balance always; energy balance + flash when flashPhaseMode = "vle"):
//   m_out         = Σ m_i                                             [kg/h]
//   x_out,j       = Σ(m_i · x_i,j) / m_out         (mass-fraction basis)
//   H_out         = Σ(m_i · h_i) / m_out           [kJ/kg, adiabatic]
//   (T_out, V_out) = flashPH(H_out, P_out, z_out)  [PH flash on combined]
//
// Validation:
//   - At least 2 connected inlets, each with positive flow and defined T,P,H.
//   - All connected inlets share the same fluid package — first inlet's
//     package wins, mismatches emit warnings but don't fail the solve.
//   - Component-vector lengths consistent with feed's resolved package.
//
// Energy stream / heat duty is intentionally OUT of scope. Mixers in HYSYS
// and Aspen Plus are isenthalpic by definition; if heat addition/removal is
// needed, place a heater/cooler downstream.
//
// Future extensions (not in v1):
//   - VLLE (3-phase) flash mode
//   - Per-inlet pressure-drop spec
//   - Realistic momentum-balanced outlet pressure (would need pipe-network model)
//   - Free-water decant outlet (Aspen "Vapor-Liquid Free-Water")
// ─────────────────────────────────────────────────────────────────────────────

class MixerUnitState : public ProcessUnitState
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

    // Bounds on the inlet count — same shape as SplitterUnitState's outlet
    // bounds, kept symmetric so the panel UX feels like a twin.
    static constexpr int kMinInlets = 2;
    static constexpr int kMaxInlets = 8;

    // ── Connections ──────────────────────────────────────────────────────────
    // QVariantList of QString unit IDs, length == inletCount, with empty
    // strings for unconnected ports. The QML view binds to this so its
    // "Connections" group can render one row per inlet.
    Q_PROPERTY(QVariantList connectedInletStreamUnitIds
               READ connectedInletStreamUnitIdsVariant
               NOTIFY inletStreamsChanged)

    Q_PROPERTY(QString connectedProductStreamUnitId
               READ connectedProductStreamUnitId
               NOTIFY productStreamChanged)

    // ── Specification ────────────────────────────────────────────────────────
    Q_PROPERTY(int inletCount
               READ inletCount WRITE setInletCount
               NOTIFY inletCountChanged)

    // "lowestInlet" | "equalizeAll" | "specified"
    Q_PROPERTY(QString pressureMode
               READ pressureMode WRITE setPressureMode
               NOTIFY pressureModeChanged)

    Q_PROPERTY(double specifiedOutletPressurePa
               READ specifiedOutletPressurePa WRITE setSpecifiedOutletPressurePa
               NOTIFY specifiedOutletPressurePaChanged)

    // "vle" | "massBalanceOnly"
    Q_PROPERTY(QString flashPhaseMode
               READ flashPhaseMode WRITE setFlashPhaseMode
               NOTIFY flashPhaseModeChanged)

    // ── Results (read-only, populated after solve) ───────────────────────────
    Q_PROPERTY(bool   solved                READ solved              NOTIFY solvedChanged)

    Q_PROPERTY(double calcOutletPressurePa  READ calcOutletPressurePa  NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletTemperatureK READ calcOutletTemperatureK NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletEnthalpyKJkg READ calcOutletEnthalpyKJkg NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletFlowKgph    READ calcOutletFlowKgph    NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletVaporMoleFrac READ calcOutletVaporMoleFrac NOTIFY resultsChanged)
    Q_PROPERTY(double calcOutletVaporMassFrac READ calcOutletVaporMassFrac NOTIFY resultsChanged)

    // Human-readable label describing where the outlet pressure came from
    // (e.g. "from Inlet 2 (lowest)" / "user specified" / "from Inlet 1
    // (highest)"). Bound by the QML Results panel.
    Q_PROPERTY(QString pressureSourceLabel  READ pressureSourceLabel   NOTIFY resultsChanged)

    Q_PROPERTY(QString solveStatus          READ solveStatus           NOTIFY resultsChanged)

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    Q_PROPERTY(int statusLevel              READ statusLevelInt        NOTIFY resultsChanged)
    Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
    Q_PROPERTY(RunLogModel*      runLogModel      READ runLogModel      CONSTANT)

public:
    explicit MixerUnitState(QObject* parent = nullptr);

    // ── Connection getters / setters (called by FlowsheetState) ─────────────
    // Returns the unit ID of the stream connected to the i-th inlet
    // (0-indexed). Returns "" if no stream bound or i is out of range.
    Q_INVOKABLE QString connectedInletStreamUnitId(int inletIndex) const;

    // Binds (or unbinds, when streamId is empty) a stream to the i-th inlet.
    // 0-indexed. No-op if inletIndex is out of [0, inletCount).
    void setConnectedInletStreamUnitId(int inletIndex, const QString& id);

    // QVariantList projection used by the QML Q_PROPERTY binding.
    QVariantList connectedInletStreamUnitIdsVariant() const;

    QString connectedProductStreamUnitId() const { return productStreamUnitId_; }
    void setConnectedProductStreamUnitId(const QString& id);

    void setFlowsheetState(FlowsheetState* fs);

    // Connection-completeness check.
    ConnectivityStatus connectivityStatus() const override;

    // ── Spec getters / setters ───────────────────────────────────────────────
    int     inletCount()                  const { return inletCount_; }
    QString pressureMode()                const { return pressureMode_; }
    double  specifiedOutletPressurePa()   const { return specifiedOutletPressurePa_; }
    QString flashPhaseMode()              const { return flashPhaseMode_; }

    void setInletCount(int n);
    void setPressureMode(const QString& mode);
    void setSpecifiedOutletPressurePa(double v);
    void setFlashPhaseMode(const QString& mode);

    // ── Result getters ───────────────────────────────────────────────────────
    bool    solved()                  const { return solved_; }
    double  calcOutletPressurePa()    const { return calcOutletPressurePa_; }
    double  calcOutletTemperatureK()  const { return calcOutletTemperatureK_; }
    double  calcOutletEnthalpyKJkg()  const { return calcOutletEnthalpyKJkg_; }
    double  calcOutletFlowKgph()      const { return calcOutletFlowKgph_; }
    double  calcOutletVaporMoleFrac() const { return calcOutletVaporMoleFrac_; }
    double  calcOutletVaporMassFrac() const { return calcOutletVaporMassFrac_; }
    QString pressureSourceLabel()     const { return pressureSourceLabel_; }
    QString solveStatus()             const { return solveStatus_; }

    StatusLevel statusLevel()         const { return statusLevel_; }
    int statusLevelInt()              const { return static_cast<int>(statusLevel_); }

    DiagnosticsModel* diagnosticsModel() { return &diagnosticsModel_; }
    RunLogModel*      runLogModel()      { return &runLogModel_; }

    // ── Invokables ───────────────────────────────────────────────────────────
    Q_INVOKABLE void solve();
    Q_INVOKABLE void reset();

signals:
    void inletStreamsChanged();
    void productStreamChanged();

    void inletCountChanged();
    void pressureModeChanged();
    void specifiedOutletPressurePaChanged();
    void flashPhaseModeChanged();

    void solvedChanged();
    void resultsChanged();

private:
    // ── Helpers ──────────────────────────────────────────────────────────────
    MaterialStreamState* activeInletStream(int inletIndex) const;

    void clearResults_();
    void pushResultsToProductStream_(const std::vector<double>& outletMassFractions,
                                     const QString& fluidPackageId);

    // Resizes inletStreamUnitIds_ to match inletCount_, preserving existing
    // entries within the new size and appending empty strings as needed.
    void resizeInletVectors_();

    // Diagnostic emit helpers — same pattern as other unit ops.
    void emitError_(const QString& message);
    void emitWarn_ (const QString& message);
    void emitInfo_ (const QString& message);
    void appendRunLogLine_(const QString& line);
    void resetSolveArtifacts_();

    // ── Connection IDs ───────────────────────────────────────────────────────
    FlowsheetState* flowsheetState_ = nullptr;
    std::vector<QString> inletStreamUnitIds_;   // length == inletCount_
    QString productStreamUnitId_;

    // ── Spec state ───────────────────────────────────────────────────────────
    int     inletCount_                = 2;
    QString pressureMode_              = QStringLiteral("lowestInlet");
    double  specifiedOutletPressurePa_ = 101325.0;     // 1 atm default
    QString flashPhaseMode_            = QStringLiteral("vle");

    // ── Results ──────────────────────────────────────────────────────────────
    bool    solved_                  = false;
    double  calcOutletPressurePa_    = 0.0;
    double  calcOutletTemperatureK_  = 0.0;
    double  calcOutletEnthalpyKJkg_  = 0.0;
    double  calcOutletFlowKgph_      = 0.0;
    double  calcOutletVaporMoleFrac_ = 0.0;
    double  calcOutletVaporMassFrac_ = 0.0;
    QString pressureSourceLabel_;
    QString solveStatus_;

    // ── Status / diagnostics / thermo log ────────────────────────────────────
    StatusLevel      statusLevel_ = StatusLevel::None;
    DiagnosticsModel diagnosticsModel_;
    RunLogModel      runLogModel_;
};
