#pragma once

#include <QObject>
#include <QVector>
#include <QPointF>
#include <memory>
#include <vector>
#include <optional>
#include <QVariantList>
#include <QDate>
#include <QJsonObject>

#include "flowsheet/UnitNode.h"
#include "flowsheet/state/ProcessUnitState.h"
#include "flowsheet/models/FlowsheetUnitModel.h"

class StreamUnitState;
class MaterialStreamState;
class HeaterCoolerUnitState;
class HeatExchangerUnitState;
class PumpUnitState;
class ValveUnitState;
class SeparatorUnitState;
class SplitterUnitState;
class MixerUnitState;
class QTimer;

class FlowsheetState : public QObject
{
   Q_OBJECT
      Q_PROPERTY(int unitCount READ unitCount NOTIFY unitCountChanged)
      Q_PROPERTY(FlowsheetUnitModel* unitModel READ unitModel CONSTANT)
      Q_PROPERTY(QString selectedUnitId READ selectedUnitId NOTIFY selectedUnitIdChanged)
      Q_PROPERTY(QObject* selectedUnit READ selectedUnitObject NOTIFY selectedUnitChanged)
      Q_PROPERTY(QVariantList materialConnections READ materialConnectionsVariant NOTIFY materialConnectionsChanged)
      Q_PROPERTY(QString lastOperationMessage READ lastOperationMessage NOTIFY lastOperationMessageChanged)

      // Transient highlight: the unit currently pulsing on the PFD as a result
      // of cross-view navigation (e.g. clicking a stream in a Delete Error
      // dialog). Empty string when no highlight is active. Set via
      // highlightStream(unitId); auto-clears after 3 seconds, or immediately
      // via clearHighlight() (called by Escape / click-elsewhere on canvas).
      Q_PROPERTY(QString highlightedUnitId READ highlightedUnitId NOTIFY highlightedUnitIdChanged)

      // ── Drawing metadata ─────────────────────────────────────────────────
      Q_PROPERTY(QString drawingTitle  READ drawingTitle  WRITE setDrawingTitle  NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString drawingNumber READ drawingNumber WRITE setDrawingNumber NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString drawnBy       READ drawnBy       WRITE setDrawnBy       NOTIFY drawingMetaChanged)
      Q_PROPERTY(int     revision      READ revision      NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString revisionDate  READ revisionDate  NOTIFY drawingMetaChanged)
      Q_PROPERTY(bool    isDirty       READ isDirty       NOTIFY isDirtyChanged)
      Q_PROPERTY(QString currentFilePath READ currentFilePath NOTIFY currentFilePathChanged)

public:
   struct MaterialConnection
   {
      QString streamUnitId;
      QString sourceUnitId;
      QString sourcePort;
      QString targetUnitId;
      QString targetPort;
   };

   explicit FlowsheetState(QObject* parent = nullptr);
   ~FlowsheetState() override;

   static FlowsheetState* instance();

   // Returns the names of every material stream whose selected fluid package
   // matches `packageId` (case-insensitive). Used to enforce the "cannot
   // delete a fluid package while a stream uses it" rule.
   QStringList streamsUsingPackage(const QString& packageId) const;

   // Returns the unit IDs (parallel to streamsUsingPackage()'s output, in the
   // same order) of every material stream whose selected fluid package
   // matches `packageId`. Used by the Delete Error dialog flow to navigate
   // from a clicked stream-name back to the underlying unit.
   Q_INVOKABLE QStringList streamUnitIdsUsingPackage(const QString& packageId) const;

   int unitCount() const;
   FlowsheetUnitModel* unitModel() { return &unitModel_; }

   QString selectedUnitId() const { return selectedUnitId_; }
   QObject* selectedUnitObject() const;

   Q_INVOKABLE void addColumn(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addColumnAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addStream(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addStreamAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addHeater(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addHeaterAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addCooler(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addCoolerAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addPump(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addPumpAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addValve(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addValveAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addHeatExchanger(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addHeatExchangerAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addSeparator(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addSeparatorAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addSplitter(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addSplitterAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addMixer(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addMixerAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void clear();

   Q_INVOKABLE void selectUnit(const QString& unitId);
   Q_INVOKABLE bool isSelected(const QString& unitId) const;
   Q_INVOKABLE void moveUnit(const QString& unitId, double x, double y);
   Q_INVOKABLE QPointF unitPosition(const QString& unitId) const;
   Q_INVOKABLE void setStreamConnectionDirection(const QString& unitId, const QString& direction);
   Q_INVOKABLE bool bindColumnFeedStream(const QString& columnUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindColumnProductStream(const QString& columnUnitId, const QString& productPort, const QString& streamUnitId);
   Q_INVOKABLE bool bindHeaterFeedStream(const QString& heaterUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindHeaterProductStream(const QString& heaterUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindPumpFeedStream(const QString& pumpUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindPumpProductStream(const QString& pumpUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindValveFeedStream(const QString& valveUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindValveProductStream(const QString& valveUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindHexStream(const QString& hexUnitId, const QString& port, const QString& streamUnitId);
   Q_INVOKABLE bool bindSeparatorStream(const QString& separatorUnitId, const QString& port, const QString& streamUnitId);
   Q_INVOKABLE bool bindSplitterStream(const QString& splitterUnitId, const QString& port, const QString& streamUnitId);
   Q_INVOKABLE bool bindMixerStream(const QString& mixerUnitId, const QString& port, const QString& streamUnitId);

   // Returns the live outlet count for a splitter unit, or 0 if the unit ID
   // isn't a splitter or doesn't exist. Used by PfdCanvas to compute port
   // positions / the live ports list.
   Q_INVOKABLE int splitterOutletCount(const QString& splitterUnitId) const;

   // Returns the live inlet count for a mixer unit, or 0 if the unit ID
   // isn't a mixer or doesn't exist. Symmetric counterpart to
   // splitterOutletCount — used by PfdCanvas for the mixer's variable-N
   // inlet ports.
   Q_INVOKABLE int mixerInletCount(const QString& mixerUnitId) const;
   Q_INVOKABLE bool disconnectMaterialStream(const QString& streamUnitId);
   Q_INVOKABLE bool deleteUnit(const QString& unitId);
   Q_INVOKABLE bool deleteSelectedUnit();
   Q_INVOKABLE bool unitHasConnections(const QString& unitId) const;

   // Refreshes the resolved fluid definition on every stream whose assigned
   // fluid package references the given component list ID. Call this whenever
   // a component list's membership changes so streams immediately see the
   // new component set. Pass an empty string to refresh all streams.
   void refreshStreamsForComponentList(const QString& componentListId);

   // Refreshes the resolved fluid definition on every stream that uses the
   // given fluid package ID. Call this whenever a package's thermo method,
   // component list assignment, or other properties change. Pass an empty
   // string to refresh all streams regardless of package.
   void refreshStreamsForPackage(const QString& packageId);
   Q_INVOKABLE bool disconnectUnitConnections(const QString& unitId);
   Q_INVOKABLE QString unitType(const QString& unitId) const;
   Q_INVOKABLE QString sanitizeUnitName(const QString& proposedName) const;
   Q_INVOKABLE bool setUnitName(const QString& unitId, const QString& proposedName);

   QString lastOperationMessage() const { return lastOperationMessage_; }

   // ── Transient PFD highlight ────────────────────────────────────────────
   QString highlightedUnitId() const { return highlightedUnitId_; }

   // Pulse-highlights a unit on the PFD for ~3 seconds. Replaces any current
   // highlight. Pass an empty string to behave like clearHighlight().
   Q_INVOKABLE void highlightStream(const QString& unitId);

   // Immediately clears any active highlight (called by Escape /
   // click-elsewhere on the canvas).
   Q_INVOKABLE void clearHighlight();

   // Drawing metadata
   QString drawingTitle()  const { return drawingTitle_; }
   QString drawingNumber() const { return drawingNumber_; }
   QString drawnBy()       const { return drawnBy_; }
   int     revision()      const { return revision_; }
   QString revisionDate()  const { return revisionDate_; }
   bool    isDirty()       const { return isDirty_; }

   void setDrawingTitle(const QString& v);
   void setDrawingNumber(const QString& v);
   void setDrawnBy(const QString& v);
   Q_INVOKABLE void stampRevision();   // advances rev, stamps date

   // ── Persistence ──────────────────────────────────────────────────────────
   Q_INVOKABLE bool saveToFile(const QString& filePath);
   Q_INVOKABLE bool loadFromFile(const QString& filePath);
   Q_INVOKABLE void newFlowsheet();
   Q_INVOKABLE QString lastSaveError() const { return lastSaveError_; }
   QString currentFilePath() const { return currentFilePath_; }

   QVariantList materialConnectionsVariant() const;
   MaterialStreamState* findMaterialStreamByUnitId(const QString& unitId) const;
   StreamUnitState* findStreamUnitById(const QString& unitId) const;

   ProcessUnitState* findUnitById(const QString& unitId) const;
   const UnitNode* findNodeById(const QString& unitId) const;

   // Enumerator returning the IDs of every unit in the flowsheet, in
   // creation order. Used by FlowsheetStatusModel to walk units when
   // refreshing the bottom Status panel.
   QStringList allUnitIds() const;

signals:
   void unitCountChanged();
   void selectedUnitIdChanged();
   void selectedUnitChanged();
   void materialConnectionsChanged();
   void lastOperationMessageChanged();
   void drawingMetaChanged();
   void isDirtyChanged();
   void currentFilePathChanged();
   void highlightedUnitIdChanged();

private:
   QString addColumnInternal(double x, double y);
   QString addStreamInternal(double x, double y);
   QString addHeaterCoolerInternal(double x, double y, const QString& unitType);
   QString addHeatExchangerInternal(double x, double y);
   QString addPumpInternal(double x, double y);
   QString addValveInternal(double x, double y);
   QString addSeparatorInternal(double x, double y);
   QString addSplitterInternal(double x, double y);
   QString addMixerInternal(double x, double y);
   QString nextAvailableUnitId_(const QString& prefix) const;
   QString makeUniqueUnitName_(const QString& proposedName, const QString& type, const QString& excludeUnitId = QString()) const;
   bool isUnitConnected_(const QString& unitId, QString* detailMessage = nullptr) const;
   void setLastOperationMessage_(const QString& message);
   int findNodeIndexById(const QString& unitId) const;
   void refreshUnitModel_();
   void removeConnectionsForStream_(const QString& streamUnitId, const QString& severeReason = QString{});
   void relabelStreamFromBindings_(const QString& streamUnitId);
   std::optional<MaterialConnection> findConnectionForTarget_(const QString& targetUnitId, const QString& targetPort) const;
   std::optional<MaterialConnection> findConnectionForSource_(const QString& sourceUnitId, const QString& sourcePort) const;

   // ── Bind-time messaging helpers ──────────────────────────────────────────
   //
   // emitConnectionSeveredMessage_  — called whenever a connection is being
   // removed as a side effect of another bind operation. Posts a trace-log
   // entry that names the now-broken unit (so the user can click-navigate
   // to fix it) and explains why the connection was removed. Severity is
   // always "warn": the action that triggered it succeeded, but the user
   // probably wants to know about the side effect.
   void emitConnectionSeveredMessage_(const MaterialConnection& severed,
                                      const QString& reason);

   // ── Bind-time validators ─────────────────────────────────────────────────
   //
   // checkSelfLoop_  — refuses (returns false) if the proposed binding
   // would make `streamUnitId` simultaneously the source and target of the
   // same unit (e.g. heater_1.product = stream_3 AND heater_1.feed = stream_3).
   // Posts an "error"-level trace message explaining the refusal.
   bool checkSelfLoop_(const QString& streamUnitId,
                       const QString& unitId,
                       const QString& portRole);   // "inlet" or "outlet"

   // checkCycleOnBind_  — does a simple BFS over current connections to
   // detect whether the proposed binding would close a directed cycle in
   // the flowsheet graph. Does NOT refuse the bind; emits a "warn"-level
   // trace message noting that recycle convergence is not yet supported.
   void checkCycleOnBind_(const QString& streamUnitId,
                          const QString& sourceUnitId,
                          const QString& targetUnitId);

   // checkFluidPackageOnBind_  — when the proposed binding makes a stream
   // simultaneously a source on unit A and a target on unit B (or the
   // stream already had one role and is gaining the other), check that
   // the stream's fluid-package id matches what the other endpoint
   // expects. Mismatches emit a "warn" trace message; the bind proceeds.
   void checkFluidPackageOnBind_(const QString& streamUnitId,
                                 const QString& counterpartUnitId);

private:
   QVector<UnitNode> nodes_;
   std::vector<std::unique_ptr<ProcessUnitState>> units_;
   int nextId_ = 1;
   FlowsheetUnitModel unitModel_;
   QString selectedUnitId_;
   std::vector<MaterialConnection> materialConnections_;
   QString lastOperationMessage_;

   // Drawing metadata members
   QString drawingTitle_;
   QString drawingNumber_ = QStringLiteral("PFD-001");
   QString drawnBy_;
   int     revision_ = 0;
   QString revisionDate_;
   bool    isDirty_ = false;

   void markDirty_();
   void clearDirty_();
   void setCurrentFilePath_(const QString& path);

   // Persistence
   QString currentFilePath_;
   QString lastSaveError_;

   // Transient PFD highlight (cross-view navigation)
   QString highlightedUnitId_;
   QTimer* highlightTimer_ = nullptr;

   static FlowsheetState* instance_;
};