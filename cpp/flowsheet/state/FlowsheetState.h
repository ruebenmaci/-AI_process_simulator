#pragma once

#include <QObject>
#include <QVector>
#include <QPointF>
#include <memory>
#include <vector>
#include <optional>
#include <QVariantList>
#include <QDate>

#include "flowsheet/UnitNode.h"
#include "flowsheet/state/ProcessUnitState.h"
#include "flowsheet/models/FlowsheetUnitModel.h"

class StreamUnitState;
class MaterialStreamState;

class FlowsheetState : public QObject
{
   Q_OBJECT
      Q_PROPERTY(int unitCount READ unitCount NOTIFY unitCountChanged)
      Q_PROPERTY(FlowsheetUnitModel* unitModel READ unitModel CONSTANT)
      Q_PROPERTY(QString selectedUnitId READ selectedUnitId NOTIFY selectedUnitIdChanged)
      Q_PROPERTY(QObject* selectedUnit READ selectedUnitObject NOTIFY selectedUnitChanged)
      Q_PROPERTY(QVariantList materialConnections READ materialConnectionsVariant NOTIFY materialConnectionsChanged)
      Q_PROPERTY(QString lastOperationMessage READ lastOperationMessage NOTIFY lastOperationMessageChanged)

      // ── Drawing metadata ─────────────────────────────────────────────────
      Q_PROPERTY(QString drawingTitle  READ drawingTitle  WRITE setDrawingTitle  NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString drawingNumber READ drawingNumber WRITE setDrawingNumber NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString drawnBy       READ drawnBy       WRITE setDrawnBy       NOTIFY drawingMetaChanged)
      Q_PROPERTY(int     revision      READ revision      NOTIFY drawingMetaChanged)
      Q_PROPERTY(QString revisionDate  READ revisionDate  NOTIFY drawingMetaChanged)
      Q_PROPERTY(bool    isDirty       READ isDirty       NOTIFY isDirtyChanged)

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

   int unitCount() const;
   FlowsheetUnitModel* unitModel() { return &unitModel_; }

   QString selectedUnitId() const { return selectedUnitId_; }
   QObject* selectedUnitObject() const;

   Q_INVOKABLE void addColumn(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addColumnAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void addStream(double x = 100.0, double y = 100.0);
   Q_INVOKABLE QString addStreamAndReturnId(double x = 100.0, double y = 100.0);
   Q_INVOKABLE void clear();

   Q_INVOKABLE void selectUnit(const QString& unitId);
   Q_INVOKABLE bool isSelected(const QString& unitId) const;
   Q_INVOKABLE void moveUnit(const QString& unitId, double x, double y);
   Q_INVOKABLE QPointF unitPosition(const QString& unitId) const;
   Q_INVOKABLE void setStreamConnectionDirection(const QString& unitId, const QString& direction);
   Q_INVOKABLE bool bindColumnFeedStream(const QString& columnUnitId, const QString& streamUnitId);
   Q_INVOKABLE bool bindColumnProductStream(const QString& columnUnitId, const QString& productPort, const QString& streamUnitId);
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
   Q_INVOKABLE void stampRevision();   // advances rev, clears dirty, stamps date

   QVariantList materialConnectionsVariant() const;
   MaterialStreamState* findMaterialStreamByUnitId(const QString& unitId) const;
   StreamUnitState* findStreamUnitById(const QString& unitId) const;

   ProcessUnitState* findUnitById(const QString& unitId) const;
   const UnitNode* findNodeById(const QString& unitId) const;

signals:
   void unitCountChanged();
   void selectedUnitIdChanged();
   void selectedUnitChanged();
   void materialConnectionsChanged();
   void lastOperationMessageChanged();
   void drawingMetaChanged();
   void isDirtyChanged();

private:
   QString addColumnInternal(double x, double y);
   QString addStreamInternal(double x, double y);
   QString nextAvailableUnitId_(const QString& prefix) const;
   QString makeUniqueUnitName_(const QString& proposedName, const QString& type, const QString& excludeUnitId = QString()) const;
   bool isUnitConnected_(const QString& unitId, QString* detailMessage = nullptr) const;
   void setLastOperationMessage_(const QString& message);
   int findNodeIndexById(const QString& unitId) const;
   void refreshUnitModel_();
   void removeConnectionsForStream_(const QString& streamUnitId);
   void relabelStreamFromBindings_(const QString& streamUnitId);
   std::optional<MaterialConnection> findConnectionForTarget_(const QString& targetUnitId, const QString& targetPort) const;
   std::optional<MaterialConnection> findConnectionForSource_(const QString& sourceUnitId, const QString& sourcePort) const;

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
};