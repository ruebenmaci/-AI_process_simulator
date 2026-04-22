#include "flowsheet/state/FlowsheetState.h"
#include "unitops/column/state/ColumnUnitState.h"
#include "unitops/heater/state/HeaterCoolerUnitState.h"
#include "unitops/hex/state/HeatExchangerUnitState.h"
#include "unitops/column/models/TrayModel.h"
#include "unitops/column/models/MaterialBalanceModel.h"
#include "streams/state/StreamUnitState.h"
#include "fluid/FluidPackageManager.h"
#include "units/UnitRegistry.h"
#include "units/FormatRegistry.h"

#include <memory>
#include <QVariantMap>
#include <QRegularExpression>
#include <QDate>
#include <QDateTime>
#include <QStringList>
#include <QSet>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFileInfo>

namespace {
   double clampCoord(double v, double minV, double maxV)
   {
      if (v < minV) return minV;
      if (v > maxV) return maxV;
      return v;
   }
}

FlowsheetState::FlowsheetState(QObject* parent)
   : QObject(parent)
{
   drawingTitle_ = QStringLiteral("AI Process sim - 001");
   revisionDate_ = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm dd/MM/yyyy"));
   refreshUnitModel_();
}

int FlowsheetState::unitCount() const
{
   return nodes_.size();
}

QString FlowsheetState::nextAvailableUnitId_(const QString& prefix) const
{
   int candidate = 1;
   while (true) {
      const QString id = QStringLiteral("%1_%2").arg(prefix).arg(candidate);
      bool used = false;
      for (const auto& node : nodes_) {
         if (node.unitId == id) {
            used = true;
            break;
         }
      }
      if (!used)
         return id;
      ++candidate;
   }
}

QString FlowsheetState::makeUniqueUnitName_(const QString& proposedName, const QString& type, const QString& excludeUnitId) const
{
   QString base = sanitizeUnitName(proposedName);
   if (base.isEmpty()) {
      if (type == QStringLiteral("column"))       base = QStringLiteral("dist_column");
      else if (type == QStringLiteral("heater"))        base = QStringLiteral("heater");
      else if (type == QStringLiteral("cooler"))        base = QStringLiteral("cooler");
      else if (type == QStringLiteral("heat_exchanger")) base = QStringLiteral("HEX");
      else                                         base = QStringLiteral("stream");
   }

   auto exists = [&](const QString& candidate) {
      for (const auto& unit : units_) {
         if (!unit || unit->id() == excludeUnitId)
            continue;
         if (unit->type() == type && unit->name().compare(candidate, Qt::CaseInsensitive) == 0)
            return true;
      }
      return false;
      };

   if (!exists(base))
      return base;

   int suffix = 2;
   while (true) {
      QString candidate = QStringLiteral("%1_%2").arg(base).arg(suffix);
      if (candidate.size() > 100)
         candidate = candidate.left(100);
      if (!exists(candidate))
         return candidate;
      ++suffix;
   }
}

QString FlowsheetState::sanitizeUnitName(const QString& proposedName) const
{
   QString normalized = proposedName.trimmed();
   normalized.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("_"));
   normalized.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9_\\-.]")));
   if (normalized.size() > 100)
      normalized = normalized.left(100);
   return normalized;
}

bool FlowsheetState::setUnitName(const QString& unitId, const QString& proposedName)
{
   if (auto* unit = findUnitById(unitId)) {
      const QString unique = makeUniqueUnitName_(proposedName, unit->type(), unitId);
      unit->setName(unique);
      markDirty_();
      return true;
   }
   return false;
}

void FlowsheetState::setLastOperationMessage_(const QString& message)
{
   if (lastOperationMessage_ == message)
      return;
   lastOperationMessage_ = message;
   emit lastOperationMessageChanged();
}

// ── Drawing metadata ──────────────────────────────────────────────────────

void FlowsheetState::markDirty_()
{
   if (isDirty_) return;
   isDirty_ = true;
   emit isDirtyChanged();
}

void FlowsheetState::setDrawingTitle(const QString& v)
{
   if (drawingTitle_ == v) return;
   drawingTitle_ = v;
   emit drawingMetaChanged();
   markDirty_();
}

void FlowsheetState::setDrawingNumber(const QString& v)
{
   if (drawingNumber_ == v) return;
   drawingNumber_ = v;
   emit drawingMetaChanged();
   markDirty_();
}

void FlowsheetState::setDrawnBy(const QString& v)
{
   if (drawnBy_ == v) return;
   drawnBy_ = v;
   emit drawingMetaChanged();
   // drawnBy change does NOT mark the flowsheet dirty — it is user preference
}

void FlowsheetState::stampRevision()
{
   ++revision_;
   revisionDate_ = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm dd/MM/yyyy"));
   emit drawingMetaChanged();
}

void FlowsheetState::clearDirty_()
{
   if (!isDirty_) return;
   isDirty_ = false;
   emit isDirtyChanged();
}

void FlowsheetState::setCurrentFilePath_(const QString& path)
{
   if (currentFilePath_ == path) return;
   currentFilePath_ = path;
   emit currentFilePathChanged();
}

namespace {
   QString displayLabelForUnit(const FlowsheetState* flowsheet, const QString& unitId)
   {
      if (!flowsheet || unitId.isEmpty())
         return unitId;
      if (const auto* node = flowsheet->findNodeById(unitId)) {
         const QString label = node->displayName.trimmed();
         if (!label.isEmpty())
            return label;
      }
      return unitId;
   }

   QString bolded(const QString& text)
   {
      return QStringLiteral("<b>%1</b>").arg(text.toHtmlEscaped());
   }

   QString joinedBoldNames(const QStringList& names)
   {
      QStringList escaped;
      escaped.reserve(names.size());
      for (const QString& name : names)
         escaped.push_back(bolded(name));

      if (escaped.isEmpty())
         return QString{};
      if (escaped.size() == 1)
         return escaped.front();
      if (escaped.size() == 2)
         return escaped.at(0) + QStringLiteral(" and ") + escaped.at(1);

      QString result;
      for (int i = 0; i < escaped.size(); ++i) {
         if (i > 0)
            result += (i == escaped.size() - 1) ? QStringLiteral(", and ") : QStringLiteral(", ");
         result += escaped.at(i);
      }
      return result;
   }
}

bool FlowsheetState::isUnitConnected_(const QString& unitId, QString* detailMessage) const
{
   if (unitId.isEmpty())
      return false;

   const bool deletingStream = findStreamUnitById(unitId) != nullptr;

   if (deletingStream) {
      for (const auto& connection : materialConnections_) {
         if (connection.streamUnitId != unitId)
            continue;

         QString otherUnitId;
         QString roleText;
         if (!connection.targetUnitId.isEmpty()) {
            otherUnitId = displayLabelForUnit(this, connection.targetUnitId);
            roleText = QStringLiteral("Feed");
         }
         else if (!connection.sourceUnitId.isEmpty()) {
            otherUnitId = displayLabelForUnit(this, connection.sourceUnitId);
            const QString port = connection.sourcePort.trimmed().toLower();
            if (port == QStringLiteral("distillate"))
               roleText = QStringLiteral("Distillate");
            else if (port == QStringLiteral("bottoms"))
               roleText = QStringLiteral("Bottoms");
            else
               roleText = connection.sourcePort;
         }

         if (detailMessage) {
            *detailMessage = QStringLiteral("%1 is in use by %2 (%3) and cannot be deleted. Disconnect stream to delete it.")
               .arg(bolded(displayLabelForUnit(this, unitId)), bolded(otherUnitId), bolded(roleText));
         }
         return true;
      }
      return false;
   }

   QStringList connectedStreamNames;
   QSet<QString> seen;
   for (const auto& connection : materialConnections_) {
      if (connection.targetUnitId == unitId || connection.sourceUnitId == unitId) {
         const QString streamName = displayLabelForUnit(this, connection.streamUnitId);
         if (!seen.contains(streamName)) {
            connectedStreamNames.push_back(streamName);
            seen.insert(streamName);
         }
      }
   }

   if (!connectedStreamNames.isEmpty()) {
      if (detailMessage) {
         *detailMessage = QStringLiteral("%1 has connected stream %2 and cannot be deleted. Disconnect stream to delete it.")
            .arg(bolded(displayLabelForUnit(this, unitId)), joinedBoldNames(connectedStreamNames));
      }
      return true;
   }

   return false;
}


QObject* FlowsheetState::selectedUnitObject() const
{
   return findUnitById(selectedUnitId_);
}

void FlowsheetState::refreshUnitModel_()
{
   unitModel_.setNodes(nodes_);
}

int FlowsheetState::findNodeIndexById(const QString& unitId) const
{
   for (int i = 0; i < nodes_.size(); ++i) {
      if (nodes_.at(i).unitId == unitId)
         return i;
   }
   return -1;
}

QString FlowsheetState::addColumnInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("column"));

   UnitNode node;
   node.unitId = id;
   node.type = "column";
   node.displayName = makeUniqueUnitName_(nextAvailableUnitId_(QStringLiteral("dist_column")), QStringLiteral("column"));
   node.x = clampCoord(x, 42.0, 980.0);
   node.y = clampCoord(y, 90.0, 620.0);

   nodes_.push_back(node);

   auto column = std::make_unique<ColumnUnitState>();
   column->setFlowsheetState(this);
   column->setId(id);
   column->setName(node.displayName);
   connect(column.get(), &ProcessUnitState::nameChanged, this, [this, id, columnPtr = column.get()]() {
      const QString unique = makeUniqueUnitName_(columnPtr->name(), columnPtr->type(), id);
      if (unique != columnPtr->name()) {
         columnPtr->setName(unique);
         return;
      }
      if (const int idx = findNodeIndexById(id); idx >= 0) {
         nodes_[idx].displayName = unique;
         unitModel_.updateName(id, unique);
         markDirty_();
      }
      });
   column->setType("column");
   column->setIconKey("column");
   units_.push_back(std::move(column));

   refreshUnitModel_();

   if (selectedUnitId_.isEmpty()) {
      selectedUnitId_ = id;
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }

   markDirty_();
   emit unitCountChanged();
   return id;
}

void FlowsheetState::addColumn(double x, double y)
{
   addColumnInternal(x, y);
}

QString FlowsheetState::addColumnAndReturnId(double x, double y)
{
   return addColumnInternal(x, y);
}


QString FlowsheetState::addStreamInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("stream"));

   UnitNode node;
   node.unitId = id;
   node.type = "stream";
   node.displayName = id;
   node.x = clampCoord(x, 42.0, 980.0);
   node.y = clampCoord(y, 90.0, 620.0);

   nodes_.push_back(node);

   auto stream = std::make_unique<StreamUnitState>();
   stream->setId(id);
   stream->setName(node.displayName);
   stream->setType("stream");
   stream->setIconKey("stream");
   if (auto* streamState = stream->streamState()) {
      streamState->setStreamName(QStringLiteral("Standalone material stream"));
   }
   connect(stream.get(), &ProcessUnitState::nameChanged, this, [this, id, streamPtr = stream.get()]() {
      const QString unique = makeUniqueUnitName_(streamPtr->name(), streamPtr->type(), id);
      if (unique != streamPtr->name()) {
         streamPtr->setName(unique);
         return;
      }
      if (const int idx = findNodeIndexById(id); idx >= 0) {
         nodes_[idx].displayName = unique;
         unitModel_.updateName(id, unique);
         markDirty_();
      }
      });
   units_.push_back(std::move(stream));

   // Assign the default fluid package to the new stream now that
   // FluidPackageManager::instance() is guaranteed to be live.
   if (auto* su = dynamic_cast<StreamUnitState*>(units_.back().get()))
      su->initializeWithDefaultPackage();

   refreshUnitModel_();

   if (selectedUnitId_.isEmpty()) {
      selectedUnitId_ = id;
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }

   emit unitCountChanged();
   return id;
}

void FlowsheetState::addStream(double x, double y)
{
   addStreamInternal(x, y);
}

QString FlowsheetState::addStreamAndReturnId(double x, double y)
{
   return addStreamInternal(x, y);
}

// ─────────────────────────────────────────────────────────────────────────────
// Heater / Cooler
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addHeaterCoolerInternal(double x, double y, const QString& unitType)
{
   // unitType is "heater" or "cooler" — determines id prefix, display name, iconKey
   const QString id = nextAvailableUnitId_(unitType);

   UnitNode node;
   node.unitId      = id;
   node.type        = unitType;
   node.displayName = makeUniqueUnitName_(id, unitType);
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);

   nodes_.push_back(node);

   auto unit = std::make_unique<HeaterCoolerUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(unitType);
   unit->setIconKey(unitType);   // maps to "heater.svg" or "cooler.svg"

   // For cooler: default to cooling duty spec with negative duty
   if (unitType == QStringLiteral("cooler")) {
      unit->setSpecMode(QStringLiteral("duty"));
      unit->setDutyKW(-1000.0);
   }

   connect(unit.get(), &ProcessUnitState::nameChanged,
           this, [this, id, ptr = unit.get()]() {
      const QString unique = makeUniqueUnitName_(ptr->name(), ptr->type(), id);
      if (unique != ptr->name()) { ptr->setName(unique); return; }
      if (const int idx = findNodeIndexById(id); idx >= 0) {
         nodes_[idx].displayName = unique;
         unitModel_.updateName(id, unique);
         markDirty_();
      }
   });

   units_.push_back(std::move(unit));
   refreshUnitModel_();

   if (selectedUnitId_.isEmpty()) {
      selectedUnitId_ = id;
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }

   markDirty_();
   emit unitCountChanged();
   return id;
}

void FlowsheetState::addHeater(double x, double y)
{
   addHeaterCoolerInternal(x, y, QStringLiteral("heater"));
}

QString FlowsheetState::addHeaterAndReturnId(double x, double y)
{
   return addHeaterCoolerInternal(x, y, QStringLiteral("heater"));
}

void FlowsheetState::addCooler(double x, double y)
{
   addHeaterCoolerInternal(x, y, QStringLiteral("cooler"));
}

QString FlowsheetState::addCoolerAndReturnId(double x, double y)
{
   return addHeaterCoolerInternal(x, y, QStringLiteral("cooler"));
}

// ─────────────────────────────────────────────────────────────────────────────
// addHeatExchangerInternal
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addHeatExchangerInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("heat_exchanger"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("heat_exchanger");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("heat_exchanger"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);
   nodes_.push_back(node);

   auto unit = std::make_unique<HeatExchangerUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("heat_exchanger"));
   unit->setIconKey(QStringLiteral("heat_exchanger"));

   connect(unit.get(), &ProcessUnitState::nameChanged,
           this, [this, id, ptr = unit.get()]() {
      const QString unique = makeUniqueUnitName_(ptr->name(), ptr->type(), id);
      if (unique != ptr->name()) { ptr->setName(unique); return; }
      if (const int idx = findNodeIndexById(id); idx >= 0) {
         nodes_[idx].displayName = unique;
         unitModel_.updateName(id, unique);
         markDirty_();
      }
   });

   units_.push_back(std::move(unit));
   refreshUnitModel_();

   if (selectedUnitId_.isEmpty()) {
      selectedUnitId_ = id;
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }
   markDirty_();
   emit unitCountChanged();
   return id;
}

void FlowsheetState::addHeatExchanger(double x, double y)
{
   addHeatExchangerInternal(x, y);
}

QString FlowsheetState::addHeatExchangerAndReturnId(double x, double y)
{
   return addHeatExchangerInternal(x, y);
}

// ─────────────────────────────────────────────────────────────────────────────
// bindHexStream  — connect a stream to one of the four HEX ports
// port: "hotIn" | "hotOut" | "coldIn" | "coldOut"
// ─────────────────────────────────────────────────────────────────────────────

bool FlowsheetState::bindHexStream(const QString& hexUnitId,
                                    const QString& port,
                                    const QString& streamUnitId)
{
   auto* hex        = dynamic_cast<HeatExchangerUnitState*>(findUnitById(hexUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!hex || !streamUnit) return false;

   const bool isInlet = (port == QStringLiteral("hotIn") ||
                         port == QStringLiteral("coldIn"));

   // Displace any stream already on this port
   if (isInlet) {
      if (auto existing = findConnectionForTarget_(hexUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // already bound
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev);
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior target binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort == QStringLiteral("hotIn"))  hx->setConnectedHotInStreamUnitId(QString{});
               if (it->targetPort == QStringLiteral("coldIn")) hx->setConnectedColdInStreamUnitId(QString{});
            }
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }
   } else {
      if (auto existing = findConnectionForSource_(hexUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // already bound
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev);
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior source binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("hotOut"))  hx->setConnectedHotOutStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("coldOut")) hx->setConnectedColdOutStreamUnitId(QString{});
            }
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }
   }

   if (isInlet) {
      materialConnections_.push_back(MaterialConnection{
          streamUnitId, QString{}, QString{}, hexUnitId, port});
      if (port == QStringLiteral("hotIn"))
         hex->setConnectedHotInStreamUnitId(streamUnitId);
      else
         hex->setConnectedColdInStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));
   } else {
      materialConnections_.push_back(MaterialConnection{
          streamUnitId, hexUnitId, port, QString{}, QString{}});
      if (port == QStringLiteral("hotOut"))
         hex->setConnectedHotOutStreamUnitId(streamUnitId);
      else
         hex->setConnectedColdOutStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   }

   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   markDirty_();
   return true;
}

void FlowsheetState::clear()
{
   if (nodes_.isEmpty() && units_.empty())
      return;

   nodes_.clear();
   units_.clear();
   materialConnections_.clear();
   refreshUnitModel_();
   emit materialConnectionsChanged();

   const bool hadSelection = !selectedUnitId_.isEmpty();
   selectedUnitId_.clear();

   emit unitCountChanged();
   if (hadSelection) {
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }
}

void FlowsheetState::selectUnit(const QString& unitId)
{
   if (selectedUnitId_ == unitId)
      return;

   selectedUnitId_ = unitId;
   emit selectedUnitIdChanged();
   emit selectedUnitChanged();
}

bool FlowsheetState::isSelected(const QString& unitId) const
{
   return selectedUnitId_ == unitId;
}

void FlowsheetState::moveUnit(const QString& unitId, double x, double y)
{
   const int idx = findNodeIndexById(unitId);
   if (idx < 0)
      return;

   UnitNode& node = nodes_[idx];

   const double clampedX = clampCoord(x, 42.0, 980.0);
   const double clampedY = clampCoord(y, 90.0, 620.0);

   if (node.x == clampedX && node.y == clampedY)
      return;

   node.x = clampedX;
   node.y = clampedY;
   unitModel_.updatePosition(unitId, clampedX, clampedY);
}

void FlowsheetState::setStreamConnectionDirection(const QString& unitId, const QString& direction)
{
   if (auto* unit = dynamic_cast<StreamUnitState*>(findUnitById(unitId))) {
      if (auto* stream = unit->streamState()) {
         stream->setStreamTypeFromConnectionDirection(direction);
         if (const int idx = findNodeIndexById(unitId); idx >= 0) {
            stream->setStreamName(QStringLiteral("Standalone material stream"));
            if (direction.compare(QStringLiteral("outlet"), Qt::CaseInsensitive) == 0)
               stream->setStreamName(QStringLiteral("Product stream"));
            else if (direction.compare(QStringLiteral("inlet"), Qt::CaseInsensitive) == 0)
               stream->setStreamName(QStringLiteral("Feed stream"));
         }
      }
   }
}


bool FlowsheetState::bindColumnFeedStream(const QString& columnUnitId, const QString& streamUnitId)
{
   auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(columnUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!column || !streamUnit)
      return false;

   // Only refuse if this stream is already occupying the SAME ROLE (target/feed).
   // A stream can be a source on one unit and a target on another simultaneously.
   if (auto existing = findConnectionForTarget_(columnUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString previousStreamUnitId = existing->streamUnitId;
      removeConnectionsForStream_(previousStreamUnitId);
      relabelStreamFromBindings_(previousStreamUnitId);
   }
   // If stream is already a target somewhere else, remove that prior target binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       QString{},
       QString{},
       columnUnitId,
       QStringLiteral("feed")
      });

   column->setConnectedFeedStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::bindColumnProductStream(const QString& columnUnitId, const QString& productPort, const QString& streamUnitId)
{
   auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(columnUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   const QString normalizedPort = productPort.trimmed().toLower();
   if (!column || !streamUnit)
      return false;
   if (normalizedPort != QStringLiteral("distillate") && normalizedPort != QStringLiteral("bottoms"))
      return false;

   // Displace any stream already occupying this specific source port on the column
   if (auto existing = findConnectionForSource_(columnUnitId, normalizedPort)) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString previousStreamUnitId = existing->streamUnitId;
      removeConnectionsForStream_(previousStreamUnitId);
      relabelStreamFromBindings_(previousStreamUnitId);
   }
   // If stream is already a source somewhere else, remove that prior source binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       columnUnitId,
       normalizedPort,
       QString{},
       QString{}
      });

   column->setConnectedProductStreamUnitId(normalizedPort, streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::bindHeaterFeedStream(const QString& heaterUnitId, const QString& streamUnitId)
{
   auto* heater     = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(heaterUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!heater || !streamUnit)
      return false;

   // Displace any stream already occupying this heater's feed port (same role conflict)
   if (auto existing = findConnectionForTarget_(heaterUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev);
      relabelStreamFromBindings_(prev);
   }
   // If stream is already a target (feed) on another unit, remove that prior binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       QString{},
       QString{},
       heaterUnitId,
       QStringLiteral("feed")
   });

   heater->setConnectedFeedStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::bindHeaterProductStream(const QString& heaterUnitId, const QString& streamUnitId)
{
   auto* heater     = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(heaterUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!heater || !streamUnit)
      return false;

   // Displace any stream already occupying this heater's product port (same role conflict)
   if (auto existing = findConnectionForSource_(heaterUnitId, QStringLiteral("product"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev);
      relabelStreamFromBindings_(prev);
   }
   // If stream is already a source (product) on another unit, remove that prior binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       heaterUnitId,
       QStringLiteral("product"),
       QString{},
       QString{}
   });

   heater->setConnectedProductStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::disconnectMaterialStream(const QString& streamUnitId)
{
   const auto before = materialConnections_.size();
   removeConnectionsForStream_(streamUnitId);
   relabelStreamFromBindings_(streamUnitId);
   const bool changed = before != materialConnections_.size();
   if (changed) {
      markDirty_();
      emit materialConnectionsChanged();
      setLastOperationMessage_(QString{});
   }
   else {
      setLastOperationMessage_(QStringLiteral("Selected stream has no active material connection."));
   }
   return changed;
}

bool FlowsheetState::deleteUnit(const QString& unitId)
{
   if (unitId.isEmpty()) {
      setLastOperationMessage_(QStringLiteral("Nothing is selected to delete."));
      return false;
   }

   QString detailMessage;
   if (isUnitConnected_(unitId, &detailMessage)) {
      setLastOperationMessage_(detailMessage);
      return false;
   }

   const int nodeIdx = findNodeIndexById(unitId);
   if (nodeIdx < 0) {
      setLastOperationMessage_(QStringLiteral("Selected unit could not be found."));
      return false;
   }

   for (auto it = units_.begin(); it != units_.end(); ++it) {
      if (*it && (*it)->id() == unitId) {
         units_.erase(it);
         break;
      }
   }

   nodes_.removeAt(nodeIdx);
   removeConnectionsForStream_(unitId);
   refreshUnitModel_();
   markDirty_();
   emit unitCountChanged();

   if (selectedUnitId_ == unitId) {
      selectedUnitId_ = nodes_.isEmpty() ? QString{} : nodes_.front().unitId;
      emit selectedUnitIdChanged();
      emit selectedUnitChanged();
   }

   setLastOperationMessage_(QString{});
   return true;
}

bool FlowsheetState::deleteSelectedUnit()
{
   return deleteUnit(selectedUnitId_);
}

bool FlowsheetState::unitHasConnections(const QString& unitId) const
{
   return isUnitConnected_(unitId, nullptr);
}

bool FlowsheetState::disconnectUnitConnections(const QString& unitId)
{
   if (unitId.isEmpty()) {
      setLastOperationMessage_(QStringLiteral("Nothing is selected to disconnect."));
      return false;
   }

   QStringList streamIds;
   QSet<QString> seen;
   for (const auto& connection : materialConnections_) {
      if (connection.streamUnitId.isEmpty())
         continue;
      if (connection.streamUnitId == unitId || connection.targetUnitId == unitId || connection.sourceUnitId == unitId) {
         if (!seen.contains(connection.streamUnitId)) {
            streamIds.push_back(connection.streamUnitId);
            seen.insert(connection.streamUnitId);
         }
      }
   }

   bool changed = false;
   for (const QString& streamId : streamIds)
      changed = disconnectMaterialStream(streamId) || changed;

   if (changed)
      setLastOperationMessage_(QString{});
   else
      setLastOperationMessage_(QStringLiteral("Selected unit has no connected streams to disconnect."));

   return changed;
}

MaterialStreamState* FlowsheetState::findMaterialStreamByUnitId(const QString& unitId) const
{
   if (auto* streamUnit = findStreamUnitById(unitId))
      return streamUnit->streamState();
   return nullptr;
}

StreamUnitState* FlowsheetState::findStreamUnitById(const QString& unitId) const
{
   return dynamic_cast<StreamUnitState*>(findUnitById(unitId));
}

void FlowsheetState::removeConnectionsForStream_(const QString& streamUnitId)
{
   if (streamUnitId.isEmpty())
      return;

   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId != streamUnitId) {
         ++it;
         continue;
      }

      if (!it->targetUnitId.isEmpty()) {
         if (auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            column->setConnectedFeedStreamUnitId(QString{});
         if (auto* heater = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            heater->setConnectedFeedStreamUnitId(QString{});
         if (auto* hex = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
            if (it->targetPort == QStringLiteral("hotIn"))  hex->setConnectedHotInStreamUnitId(QString{});
            if (it->targetPort == QStringLiteral("coldIn")) hex->setConnectedColdInStreamUnitId(QString{});
         }
      }
      if (!it->sourceUnitId.isEmpty()) {
         if (auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            column->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* heater = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            heater->setConnectedProductStreamUnitId(QString{});
         if (auto* hex = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
            if (it->sourcePort == QStringLiteral("hotOut"))  hex->setConnectedHotOutStreamUnitId(QString{});
            if (it->sourcePort == QStringLiteral("coldOut")) hex->setConnectedColdOutStreamUnitId(QString{});
         }
      }

      it = materialConnections_.erase(it);
   }
}

void FlowsheetState::relabelStreamFromBindings_(const QString& streamUnitId)
{
   auto* unit = findStreamUnitById(streamUnitId);
   if (!unit)
      return;

   QString direction = QStringLiteral("none");
   for (const auto& connection : materialConnections_) {
      if (connection.streamUnitId != streamUnitId)
         continue;
      direction = connection.targetUnitId.isEmpty() ? QStringLiteral("outlet") : QStringLiteral("inlet");
      break;
   }
   setStreamConnectionDirection(streamUnitId, direction);
}

std::optional<FlowsheetState::MaterialConnection> FlowsheetState::findConnectionForTarget_(const QString& targetUnitId, const QString& targetPort) const
{
   for (const auto& connection : materialConnections_) {
      if (connection.targetUnitId == targetUnitId && connection.targetPort == targetPort)
         return connection;
   }
   return std::nullopt;
}

std::optional<FlowsheetState::MaterialConnection> FlowsheetState::findConnectionForSource_(const QString& sourceUnitId, const QString& sourcePort) const
{
   for (const auto& connection : materialConnections_) {
      if (connection.sourceUnitId == sourceUnitId && connection.sourcePort == sourcePort)
         return connection;
   }
   return std::nullopt;
}

QString FlowsheetState::unitType(const QString& unitId) const
{
   if (const auto* unit = findUnitById(unitId))
      return unit->type();
   return {};
}

QVariantList FlowsheetState::materialConnectionsVariant() const
{
   QVariantList out;
   out.reserve(static_cast<int>(materialConnections_.size()));
   for (const auto& connection : materialConnections_) {
      QVariantMap m;
      m.insert(QStringLiteral("streamUnitId"), connection.streamUnitId);
      m.insert(QStringLiteral("sourceUnitId"), connection.sourceUnitId);
      m.insert(QStringLiteral("sourcePort"), connection.sourcePort);
      m.insert(QStringLiteral("targetUnitId"), connection.targetUnitId);
      m.insert(QStringLiteral("targetPort"), connection.targetPort);
      out.push_back(m);
   }
   return out;
}

QPointF FlowsheetState::unitPosition(const QString& unitId) const
{
   const int idx = findNodeIndexById(unitId);
   if (idx < 0)
      return {};

   const UnitNode& node = nodes_.at(idx);
   return QPointF(node.x, node.y);
}

ProcessUnitState* FlowsheetState::findUnitById(const QString& unitId) const
{
   for (const auto& unit : units_) {
      if (unit && unit->id() == unitId)
         return unit.get();
   }
   return nullptr;
}

const UnitNode* FlowsheetState::findNodeById(const QString& unitId) const
{
   const int idx = findNodeIndexById(unitId);
   if (idx < 0)
      return nullptr;
   return &nodes_.at(idx);
}

void FlowsheetState::refreshStreamsForComponentList(const QString& componentListId)
{
   // For each stream, check whether its assigned fluid package references the
   // changed component list. If so, reload its fluid definition so it
   // immediately reflects the new component membership.
   auto* fpm = FluidPackageManager::instance();

   for (const auto& unit : units_) {
      auto* su = dynamic_cast<StreamUnitState*>(unit.get());
      if (!su) continue;
      MaterialStreamState* stream = su->streamState();
      if (!stream) continue;

      const QString pkgId = stream->selectedFluidPackageId();
      if (pkgId.isEmpty()) continue;

      // If componentListId is empty, refresh all streams unconditionally.
      if (!componentListId.isEmpty() && fpm) {
         const QVariantMap pkg = fpm->getFluidPackage(pkgId);
         const QString listId = pkg.value(QStringLiteral("componentListId")).toString();
         if (listId.compare(componentListId, Qt::CaseInsensitive) != 0)
            continue;  // this stream's package uses a different list
      }

      stream->reloadFluidDefinition();
   }
}

void FlowsheetState::refreshStreamsForPackage(const QString& packageId)
{
   // For each stream, reload if it uses the changed package (or all streams
   // if packageId is empty).
   for (const auto& unit : units_) {
      auto* su = dynamic_cast<StreamUnitState*>(unit.get());
      if (!su) continue;
      MaterialStreamState* stream = su->streamState();
      if (!stream) continue;

      const QString pkgId = stream->selectedFluidPackageId();
      if (pkgId.isEmpty()) continue;

      if (!packageId.isEmpty() &&
         pkgId.compare(packageId, Qt::CaseInsensitive) != 0)
         continue;  // this stream uses a different package

      stream->reloadFluidDefinition();
   }
}
// ── Persistence ───────────────────────────────────────────────────────────────

void FlowsheetState::newFlowsheet()
{
   clear();
   drawingTitle_ = QStringLiteral("AI Process sim - 001");
   drawingNumber_ = QStringLiteral("PFD-001");
   drawnBy_.clear();
   revision_ = 0;
   revisionDate_ = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm dd/MM/yyyy"));
   setCurrentFilePath_(QString{});
   clearDirty_();
   emit drawingMetaChanged();
}

bool FlowsheetState::saveToFile(const QString& filePath)
{
   // ── Drawing metadata ──────────────────────────────────────────────────
   QJsonObject root;
   root[QStringLiteral("fileVersion")] = 2;
   root[QStringLiteral("drawingTitle")] = drawingTitle_;
   root[QStringLiteral("drawingNumber")] = drawingNumber_;
   root[QStringLiteral("drawnBy")] = drawnBy_;
   root[QStringLiteral("revision")] = revision_;
   // stamp date on save
   const QString today = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm dd/MM/yyyy"));
   revisionDate_ = today;
   root[QStringLiteral("revisionDate")] = revisionDate_;

   if (auto* unitsRegistry = UnitRegistry::instance())
      root[QStringLiteral("unitSettings")] = unitsRegistry->saveProjectSettings();
   if (auto* formatsRegistry = FormatRegistry::instance())
      root[QStringLiteral("numberFormatSettings")] = formatsRegistry->saveProjectSettings();

   // ── Units (nodes + state) ─────────────────────────────────────────────
   QJsonArray units;
   for (const auto& node : nodes_) {
      QJsonObject u;
      u[QStringLiteral("id")] = node.unitId;
      u[QStringLiteral("type")] = node.type;
      u[QStringLiteral("name")] = node.displayName;
      u[QStringLiteral("x")] = node.x;
      u[QStringLiteral("y")] = node.y;

      // per-type state
      if (node.type == QStringLiteral("stream")) {
         auto* su = dynamic_cast<StreamUnitState*>(findUnitById(node.unitId));
         auto* ms = su ? su->streamState() : nullptr;
         if (ms) {
            QJsonObject s;
            s[QStringLiteral("fluidPackageId")] = ms->selectedFluidPackageId();
            s[QStringLiteral("flowRateKgph")] = ms->flowRateKgph();
            s[QStringLiteral("temperatureK")] = ms->temperatureK();
            s[QStringLiteral("pressurePa")] = ms->pressurePa();
            s[QStringLiteral("flowSpecMode")] = static_cast<int>(ms->flowSpecMode());
            s[QStringLiteral("thermoSpecMode")] = static_cast<int>(ms->thermoSpecMode());
            // composition (mass fractions)
            if (ms->hasCustomComposition()) {
               QJsonArray comp;
               for (double v : ms->compositionStd()) comp.append(v);
               s[QStringLiteral("customComposition")] = comp;
            }
            u[QStringLiteral("streamState")] = s;
         }
      }
      else if (node.type == QStringLiteral("column")) {
         auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(node.unitId));
         if (col) {
            QJsonObject c;
            c[QStringLiteral("trays")] = col->trays();
            c[QStringLiteral("feedTray")] = col->feedTray();
            c[QStringLiteral("feedRateKgph")] = col->feedRateKgph();
            c[QStringLiteral("feedTempK")] = col->feedTempK();
            c[QStringLiteral("topPressurePa")] = col->topPressurePa();
            c[QStringLiteral("dpPerTrayPa")] = col->dpPerTrayPa();
            c[QStringLiteral("condenserType")] = col->condenserType();
            c[QStringLiteral("condenserSpec")] = col->condenserSpec();
            c[QStringLiteral("reboilerType")] = col->reboilerType();
            c[QStringLiteral("reboilerSpec")] = col->reboilerSpec();
            c[QStringLiteral("refluxRatio")] = col->refluxRatio();
            c[QStringLiteral("boilupRatio")] = col->boilupRatio();
            c[QStringLiteral("qcKW")] = col->qcKW();
            c[QStringLiteral("qrKW")] = col->qrKW();
            c[QStringLiteral("topTsetK")] = col->topTsetK();
            c[QStringLiteral("bottomTsetK")] = col->bottomTsetK();
            c[QStringLiteral("eosMode")] = col->eosMode();
            c[QStringLiteral("eosManual")] = col->eosManual();
            c[QStringLiteral("etaVTop")] = col->etaVTop();
            c[QStringLiteral("etaVMid")] = col->etaVMid();
            c[QStringLiteral("etaVBot")] = col->etaVBot();
            c[QStringLiteral("enableEtaL")] = col->enableEtaL();
            // drawSpecs
            QJsonArray draws;
            for (const QVariant& dv : col->drawSpecs()) {
               const QVariantMap dm = dv.toMap();
               QJsonObject d;
               d[QStringLiteral("name")] = dm.value(QStringLiteral("name")).toString();
               d[QStringLiteral("tray")] = dm.value(QStringLiteral("tray")).toInt();
               d[QStringLiteral("phase")] = dm.value(QStringLiteral("phase")).toString();
               d[QStringLiteral("basis")] = dm.value(QStringLiteral("basis")).toString();
               d[QStringLiteral("value")] = dm.value(QStringLiteral("value")).toDouble();
               draws.append(d);
            }
            c[QStringLiteral("drawSpecs")] = draws;

            // ── Solver results ─────────────────────────────────────────────
            if (col->solved()) {
               QJsonObject sr;
               sr[QStringLiteral("solved")] = true;
               sr[QStringLiteral("tColdK")] = col->tColdK();
               sr[QStringLiteral("tHotK")] = col->tHotK();
               sr[QStringLiteral("qcCalcKW")] = col->qcCalcKW();
               sr[QStringLiteral("qrCalcKW")] = col->qrCalcKW();
               sr[QStringLiteral("refluxFraction")] = col->refluxFraction();
               sr[QStringLiteral("boilupFraction")] = col->boilupFraction();
               sr[QStringLiteral("solveElapsedMs")] = col->solveElapsedMs();

               // Component names
               QJsonArray cnames;
               for (const QString& n : col->componentNames()) cnames.append(n);
               sr[QStringLiteral("componentNames")] = cnames;

               // Tray table
               TrayModel* tm = col->trayModel();
               const int nTrays = tm ? tm->rowCountQml() : 0;
               QJsonArray trays;
               for (int ti = 0; ti < nTrays; ++ti) {
                  const QVariantMap row = tm->get(ti);
                  QJsonObject tr;
                  tr[QStringLiteral("trayNumber")] = row.value(QStringLiteral("trayNumber")).toInt();
                  tr[QStringLiteral("tempK")] = row.value(QStringLiteral("tempK")).toDouble();
                  tr[QStringLiteral("vaporFrac")] = row.value(QStringLiteral("vaporFrac")).toDouble();
                  tr[QStringLiteral("vaporFlow")] = row.value(QStringLiteral("vaporFlow")).toDouble();
                  tr[QStringLiteral("liquidFlow")] = row.value(QStringLiteral("liquidFlow")).toDouble();
                  tr[QStringLiteral("hasDraw")] = row.value(QStringLiteral("hasDraw")).toBool();
                  tr[QStringLiteral("drawLabel")] = row.value(QStringLiteral("drawLabel")).toString();
                  // x/y compositions
                  QJsonArray xArr, yArr;
                  const QVariantList xl = row.value(QStringLiteral("xLiq")).toList();
                  const QVariantList yl = row.value(QStringLiteral("yVap")).toList();
                  for (const QVariant& v : xl) xArr.append(v.toDouble());
                  for (const QVariant& v : yl) yArr.append(v.toDouble());
                  tr[QStringLiteral("xLiq")] = xArr;
                  tr[QStringLiteral("yVap")] = yArr;
                  trays.append(tr);
               }
               sr[QStringLiteral("trays")] = trays;

               // Material balance
               MaterialBalanceModel* mb = col->materialBalanceModel();
               QJsonObject mbal;
               mbal[QStringLiteral("feedKgph")] = mb->feedKgph();
               mbal[QStringLiteral("totalProductsKgph")] = mb->totalProductsKgph();
               mbal[QStringLiteral("balanceErrKgph")] = mb->balanceErrKgph();
               QJsonArray lines;
               for (int li = 0; li < mb->rowCount(); ++li) {
                  const QModelIndex idx = mb->index(li, 0);
                  QJsonObject line;
                  line[QStringLiteral("name")] = mb->data(idx, MaterialBalanceModel::NameRole).toString();
                  line[QStringLiteral("kgph")] = mb->data(idx, MaterialBalanceModel::KgphRole).toDouble();
                  line[QStringLiteral("frac")] = mb->data(idx, MaterialBalanceModel::FracRole).toDouble();
                  lines.append(line);
               }
               mbal[QStringLiteral("lines")] = lines;
               sr[QStringLiteral("materialBalance")] = mbal;

               c[QStringLiteral("solverResults")] = sr;
            }

            u[QStringLiteral("columnState")] = c;
         }
      }
      // ── Heater / Cooler state ─────────────────────────────────────────────
      else if (node.type == QStringLiteral("heater") || node.type == QStringLiteral("cooler")) {
         auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(node.unitId));
         if (hc) {
            QJsonObject h;
            h[QStringLiteral("specMode")]            = hc->specMode();
            h[QStringLiteral("outletTemperatureK")]  = hc->outletTemperatureK();
            h[QStringLiteral("dutyKW")]              = hc->dutyKW();
            h[QStringLiteral("outletVaporFraction")] = hc->outletVaporFraction();
            h[QStringLiteral("pressureDropPa")]      = hc->pressureDropPa();
            // Connection IDs — persisted so we can re-wire on load
            h[QStringLiteral("feedStreamUnitId")]    = hc->connectedFeedStreamUnitId();
            h[QStringLiteral("productStreamUnitId")] = hc->connectedProductStreamUnitId();
            u[QStringLiteral("heaterState")]         = h;
         }
      }

      // ── Heat Exchanger state ──────────────────────────────────────────────
      else if (node.type == QStringLiteral("heat_exchanger")) {
         auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(node.unitId));
         if (hx) {
            QJsonObject h;
            h[QStringLiteral("specMode")]              = hx->specMode();
            h[QStringLiteral("dutyKW")]                = hx->dutyKW();
            h[QStringLiteral("hotOutletTK")]           = hx->hotOutletTK();
            h[QStringLiteral("coldOutletTK")]          = hx->coldOutletTK();
            h[QStringLiteral("hotSideDpPa")]           = hx->hotSidePressureDropPa();
            h[QStringLiteral("coldSideDpPa")]          = hx->coldSidePressureDropPa();
            u[QStringLiteral("hexState")]              = h;
         }
      }

      units.append(u);
   }
   root[QStringLiteral("units")] = units;

   // ── Connections ───────────────────────────────────────────────────────
   QJsonArray conns;
   for (const auto& mc : materialConnections_) {
      QJsonObject co;
      co[QStringLiteral("streamUnitId")] = mc.streamUnitId;
      co[QStringLiteral("sourceUnitId")] = mc.sourceUnitId;
      co[QStringLiteral("sourcePort")] = mc.sourcePort;
      co[QStringLiteral("targetUnitId")] = mc.targetUnitId;
      co[QStringLiteral("targetPort")] = mc.targetPort;
      conns.append(co);
   }
   root[QStringLiteral("connections")] = conns;

   // ── Write file ────────────────────────────────────────────────────────
   QFile f(filePath);
   if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
      lastSaveError_ = QStringLiteral("Cannot open file for writing: ") + filePath;
      return false;
   }
   f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
   f.close();

   setCurrentFilePath_(filePath);
   clearDirty_();
   emit drawingMetaChanged();   // update DATE in title block
   lastSaveError_.clear();
   return true;
}

bool FlowsheetState::loadFromFile(const QString& filePath)
{
   QFile f(filePath);
   if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
      lastSaveError_ = QStringLiteral("Cannot open file: ") + filePath;
      return false;
   }
   const QByteArray data = f.readAll();
   f.close();

   QJsonParseError err;
   const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
   if (doc.isNull()) {
      lastSaveError_ = QStringLiteral("JSON parse error: ") + err.errorString();
      return false;
   }

   const QJsonObject root = doc.object();

   // Clear existing flowsheet first
   clear();

   // ── Drawing metadata ──────────────────────────────────────────────────
   drawingTitle_ = root[QStringLiteral("drawingTitle")].toString();
   drawingNumber_ = root[QStringLiteral("drawingNumber")].toString(QStringLiteral("PFD-001"));
   drawnBy_ = root[QStringLiteral("drawnBy")].toString();
   revision_ = root[QStringLiteral("revision")].toInt(0);
   revisionDate_ = root[QStringLiteral("revisionDate")].toString();
   emit drawingMetaChanged();

   if (auto* unitsRegistry = UnitRegistry::instance())
      unitsRegistry->loadProjectSettings(root.value(QStringLiteral("unitSettings")).toObject());
   if (auto* formatsRegistry = FormatRegistry::instance())
      formatsRegistry->loadProjectSettings(root.value(QStringLiteral("numberFormatSettings")).toObject());

   // ── Units ─────────────────────────────────────────────────────────────
   // Pass 1: create all units at saved positions with saved names
   const QJsonArray units = root[QStringLiteral("units")].toArray();
   for (const QJsonValue& uv : units) {
      const QJsonObject u = uv.toObject();
      const QString type = u[QStringLiteral("type")].toString();
      const QString id = u[QStringLiteral("id")].toString();
      const QString name = u[QStringLiteral("name")].toString();
      const double  x = u[QStringLiteral("x")].toDouble(100.0);
      const double  y = u[QStringLiteral("y")].toDouble(100.0);

      if (type == QStringLiteral("stream")) {
         addStreamInternal(x, y);
      }
      else if (type == QStringLiteral("column")) {
         addColumnInternal(x, y);
      }
      else if (type == QStringLiteral("heater") || type == QStringLiteral("cooler")) {
         addHeaterCoolerInternal(x, y, type);
      }
      else if (type == QStringLiteral("heat_exchanger")) {
         addHeatExchangerInternal(x, y);
      }
      else {
         continue;
      }

      // Rename the newly created unit to match saved name
      if (!nodes_.isEmpty()) {
         const QString newId = nodes_.back().unitId;
         setUnitName(newId, name);

         // Restore per-type state
         if (type == QStringLiteral("stream")) {
            const QJsonObject ss = u[QStringLiteral("streamState")].toObject();
            if (!ss.isEmpty()) {
               auto* su = dynamic_cast<StreamUnitState*>(findUnitById(newId));
               auto* ms = su ? su->streamState() : nullptr;
               if (ms) {
                  const QString pkgId = ss[QStringLiteral("fluidPackageId")].toString();
                  if (!pkgId.isEmpty()) ms->setSelectedFluidPackageId(pkgId);
                  ms->setFlowRateKgph(ss[QStringLiteral("flowRateKgph")].toDouble());
                  ms->setTemperatureK(ss[QStringLiteral("temperatureK")].toDouble());
                  ms->setPressurePa(ss[QStringLiteral("pressurePa")].toDouble());
                  // restore custom composition if present
                  const QJsonArray compArr = ss[QStringLiteral("customComposition")].toArray();
                  if (!compArr.isEmpty()) {
                     std::vector<double> comp;
                     comp.reserve(compArr.size());
                     for (const QJsonValue& cv : compArr) comp.push_back(cv.toDouble());
                     ms->setCompositionStd(comp);
                  }
               }
            }
         }
         else if (type == QStringLiteral("heater") || type == QStringLiteral("cooler")) {
            const QJsonObject hs = u[QStringLiteral("heaterState")].toObject();
            if (!hs.isEmpty()) {
               auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(newId));
               if (hc) {
                  hc->setSpecMode(hs[QStringLiteral("specMode")].toString(QStringLiteral("temperature")));
                  hc->setOutletTemperatureK(hs[QStringLiteral("outletTemperatureK")].toDouble(400.0));
                  hc->setDutyKW(hs[QStringLiteral("dutyKW")].toDouble(1000.0));
                  hc->setOutletVaporFraction(hs[QStringLiteral("outletVaporFraction")].toDouble(0.0));
                  hc->setPressureDropPa(hs[QStringLiteral("pressureDropPa")].toDouble(0.0));
               }
            }
         }
         else if (type == QStringLiteral("heat_exchanger")) {
            const QJsonObject hs = u[QStringLiteral("hexState")].toObject();
            if (!hs.isEmpty()) {
               auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(newId));
               if (hx) {
                  hx->setSpecMode(hs[QStringLiteral("specMode")].toString(QStringLiteral("duty")));
                  hx->setDutyKW(hs[QStringLiteral("dutyKW")].toDouble(1000.0));
                  hx->setHotOutletTK(hs[QStringLiteral("hotOutletTK")].toDouble(350.0));
                  hx->setColdOutletTK(hs[QStringLiteral("coldOutletTK")].toDouble(400.0));
                  hx->setHotSidePressureDropPa(hs[QStringLiteral("hotSideDpPa")].toDouble(0.0));
                  hx->setColdSidePressureDropPa(hs[QStringLiteral("coldSideDpPa")].toDouble(0.0));
               }
            }
         }
         else if (type == QStringLiteral("column")) {
            const QJsonObject cs = u[QStringLiteral("columnState")].toObject();
            if (!cs.isEmpty()) {
               auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(newId));
               if (col) {
                  col->setTrays(cs[QStringLiteral("trays")].toInt(20));
                  col->setFeedTray(cs[QStringLiteral("feedTray")].toInt(10));
                  col->setFeedRateKgph(cs[QStringLiteral("feedRateKgph")].toDouble());
                  col->setFeedTempK(cs[QStringLiteral("feedTempK")].toDouble());
                  col->setTopPressurePa(cs[QStringLiteral("topPressurePa")].toDouble());
                  col->setDpPerTrayPa(cs[QStringLiteral("dpPerTrayPa")].toDouble());
                  col->setCondenserType(cs[QStringLiteral("condenserType")].toString());
                  col->setCondenserSpec(cs[QStringLiteral("condenserSpec")].toString());
                  col->setReboilerType(cs[QStringLiteral("reboilerType")].toString());
                  col->setReboilerSpec(cs[QStringLiteral("reboilerSpec")].toString());
                  col->setRefluxRatio(cs[QStringLiteral("refluxRatio")].toDouble());
                  col->setBoilupRatio(cs[QStringLiteral("boilupRatio")].toDouble());
                  col->setQcKW(cs[QStringLiteral("qcKW")].toDouble());
                  col->setQrKW(cs[QStringLiteral("qrKW")].toDouble());
                  col->setTopTsetK(cs[QStringLiteral("topTsetK")].toDouble());
                  col->setBottomTsetK(cs[QStringLiteral("bottomTsetK")].toDouble());
                  col->setEosMode(cs[QStringLiteral("eosMode")].toString());
                  col->setEosManual(cs[QStringLiteral("eosManual")].toString());
                  col->setEtaVTop(cs[QStringLiteral("etaVTop")].toDouble(1.0));
                  col->setEtaVMid(cs[QStringLiteral("etaVMid")].toDouble(1.0));
                  col->setEtaVBot(cs[QStringLiteral("etaVBot")].toDouble(1.0));
                  col->setEnableEtaL(cs[QStringLiteral("enableEtaL")].toBool(false));
                  // drawSpecs
                  const QJsonArray draws = cs[QStringLiteral("drawSpecs")].toArray();
                  QVariantList dsList;
                  for (const QJsonValue& dv : draws) {
                     const QJsonObject d = dv.toObject();
                     QVariantMap dm;
                     dm[QStringLiteral("name")] = d[QStringLiteral("name")].toString();
                     dm[QStringLiteral("tray")] = d[QStringLiteral("tray")].toInt();
                     dm[QStringLiteral("phase")] = d[QStringLiteral("phase")].toString();
                     dm[QStringLiteral("basis")] = d[QStringLiteral("basis")].toString();
                     dm[QStringLiteral("value")] = d[QStringLiteral("value")].toDouble();
                     dsList.append(dm);
                  }
                  col->setDrawSpecs(dsList);

                  // ── Restore solver results ──────────────────────────────
                  const QJsonObject sr = cs[QStringLiteral("solverResults")].toObject();
                  if (!sr.isEmpty() && sr[QStringLiteral("solved")].toBool()) {
                     // Restore tray table
                     const QJsonArray trays = sr[QStringLiteral("trays")].toArray();
                     TrayModel* tm = col->trayModel();
                     if (tm && !trays.isEmpty()) {
                        tm->resetToDefaults(trays.size());
                        // Set component names first
                        const QJsonArray cnames = sr[QStringLiteral("componentNames")].toArray();
                        QStringList cnameList;
                        for (const QJsonValue& v : cnames) cnameList.append(v.toString());
                        tm->setComponentNames(cnameList);
                        // Restore each tray
                        for (int ti = 0; ti < trays.size(); ++ti) {
                           const QJsonObject tr = trays[ti].toObject();
                           TrayRow row;
                           row.trayNumber = tr[QStringLiteral("trayNumber")].toInt();
                           row.tempK = tr[QStringLiteral("tempK")].toDouble();
                           row.vaporFrac = tr[QStringLiteral("vaporFrac")].toDouble();
                           row.vaporFlow = tr[QStringLiteral("vaporFlow")].toDouble();
                           row.liquidFlow = tr[QStringLiteral("liquidFlow")].toDouble();
                           row.hasDraw = tr[QStringLiteral("hasDraw")].toBool();
                           row.drawLabel = tr[QStringLiteral("drawLabel")].toString();
                           const QJsonArray xl = tr[QStringLiteral("xLiq")].toArray();
                           const QJsonArray yl = tr[QStringLiteral("yVap")].toArray();
                           for (const QJsonValue& v : xl) row.xLiq.push_back(v.toDouble());
                           for (const QJsonValue& v : yl) row.yVap.push_back(v.toDouble());
                           tm->setRow(ti, row);
                        }
                     }

                     // Restore material balance
                     const QJsonObject mbal = sr[QStringLiteral("materialBalance")].toObject();
                     if (!mbal.isEmpty()) {
                        MaterialBalanceModel* mb = col->materialBalanceModel();
                        mb->reset();
                        mb->setFeedKg(mbal[QStringLiteral("feedKgph")].toDouble());
                        const QJsonArray lines = mbal[QStringLiteral("lines")].toArray();
                        for (const QJsonValue& lv : lines) {
                           const QJsonObject line = lv.toObject();
                           mb->setDraw(line[QStringLiteral("name")].toString(),
                              line[QStringLiteral("kgph")].toDouble());
                        }
                        mb->finalize();
                     }

                     // Restore scalar results + component names via the new Q_INVOKABLE
                     const QJsonArray cnamesArr = sr[QStringLiteral("componentNames")].toArray();
                     QStringList cnameList;
                     for (const QJsonValue& v : cnamesArr) cnameList.append(v.toString());

                     col->restoreSolveScalars(
                        sr[QStringLiteral("tColdK")].toDouble(),
                        sr[QStringLiteral("tHotK")].toDouble(),
                        sr[QStringLiteral("qcCalcKW")].toDouble(),
                        sr[QStringLiteral("qrCalcKW")].toDouble(),
                        sr[QStringLiteral("refluxFraction")].toDouble(),
                        sr[QStringLiteral("boilupFraction")].toDouble(),
                        static_cast<qint64>(sr[QStringLiteral("solveElapsedMs")].toDouble()),
                        cnameList
                     );
                  }
               }
            }
         }
      }
   }

   // Pass 2: restore connections
   // Since we add units in order with the same prefix, ids should match.
   const QJsonArray conns = root[QStringLiteral("connections")].toArray();
   for (const QJsonValue& cv : conns) {
      const QJsonObject co = cv.toObject();
      const QString streamId   = co[QStringLiteral("streamUnitId")].toString();
      const QString sourceId   = co[QStringLiteral("sourceUnitId")].toString();
      const QString sourcePort = co[QStringLiteral("sourcePort")].toString();
      const QString targetId   = co[QStringLiteral("targetUnitId")].toString();
      const QString targetPort = co[QStringLiteral("targetPort")].toString();

      if (!targetId.isEmpty() && targetPort == QStringLiteral("feed")) {
         // Could be column or heater/cooler — dispatch on the target unit type
         const QString ttype = unitType(targetId);
         if (ttype == QStringLiteral("heater") || ttype == QStringLiteral("cooler"))
            bindHeaterFeedStream(targetId, streamId);
         else
            bindColumnFeedStream(targetId, streamId);
      }
      else if (!targetId.isEmpty() && (targetPort == QStringLiteral("hotIn") ||
                                        targetPort == QStringLiteral("coldIn"))) {
         bindHexStream(targetId, targetPort, streamId);
      }
      else if (!sourceId.isEmpty() && (sourcePort == QStringLiteral("hotOut") ||
                                        sourcePort == QStringLiteral("coldOut"))) {
         bindHexStream(sourceId, sourcePort, streamId);
      }
      else if (!sourceId.isEmpty()) {
         // Could be column product (distillate/bottoms) or heater product
         const QString stype = unitType(sourceId);
         if (stype == QStringLiteral("heater") || stype == QStringLiteral("cooler"))
            bindHeaterProductStream(sourceId, streamId);
         else
            bindColumnProductStream(sourceId, sourcePort, streamId);
      }
   }

   setCurrentFilePath_(filePath);
   clearDirty_();
   lastSaveError_.clear();
   return true;
}