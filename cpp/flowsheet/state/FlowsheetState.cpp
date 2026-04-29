#include "flowsheet/state/FlowsheetState.h"
#include "unitops/column/state/ColumnUnitState.h"
#include "unitops/heater/state/HeaterCoolerUnitState.h"
#include "unitops/hex/state/HeatExchangerUnitState.h"
#include "unitops/pump/state/PumpUnitState.h"
#include "unitops/valve/state/ValveUnitState.h"
#include "unitops/separator/state/SeparatorUnitState.h"
#include "unitops/splitter/state/SplitterUnitState.h"
#include "unitops/mixer/state/MixerUnitState.h"
#include "unitops/column/models/TrayModel.h"
#include "unitops/column/models/MaterialBalanceModel.h"
#include "streams/state/StreamUnitState.h"
#include "fluid/FluidPackageManager.h"
#include "common/models/MessageLog.h"
#include "units/UnitRegistry.h"
#include "units/FormatRegistry.h"

#include <memory>
#include <QVariantMap>
#include <QRegularExpression>
#include <QDebug>
#include <QElapsedTimer>
#include <QDate>
#include <QDateTime>
#include <QStringList>
#include <QSet>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QFileInfo>

namespace {
   double clampCoord(double v, double minV, double maxV)
   {
      if (v < minV) return minV;
      if (v > maxV) return maxV;
      return v;
   }
}

FlowsheetState* FlowsheetState::instance_ = nullptr;

FlowsheetState* FlowsheetState::instance()
{
   return instance_;
}

FlowsheetState::FlowsheetState(QObject* parent)
   : QObject(parent)
{
   instance_ = this;
   drawingTitle_ = QStringLiteral("AI Process sim - 001");
   revisionDate_ = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm dd/MM/yyyy"));

   highlightTimer_ = new QTimer(this);
   highlightTimer_->setSingleShot(true);
   highlightTimer_->setInterval(3000);
   QObject::connect(highlightTimer_, &QTimer::timeout, this, [this]() {
      clearHighlight();
   });

   refreshUnitModel_();
}

FlowsheetState::~FlowsheetState()
{
   if (instance_ == this) instance_ = nullptr;
}

QStringList FlowsheetState::streamsUsingPackage(const QString& packageId) const
{
   QStringList names;
   if (packageId.trimmed().isEmpty()) return names;

   for (const auto& unit : units_) {
      auto* su = dynamic_cast<StreamUnitState*>(unit.get());
      if (!su) continue;
      MaterialStreamState* stream = su->streamState();
      if (!stream) continue;

      const QString pkgId = stream->selectedFluidPackageId();
      if (pkgId.compare(packageId, Qt::CaseInsensitive) != 0) continue;

      // Name priority: the unit's PFD-level name (e.g. "stream_1") is the
      // user-facing identifier. Fall back to the stream's role label (e.g.
      // "Feed stream"), then the unit id, in case the PFD name is empty.
      QString name = su->name().trimmed();
      if (name.isEmpty()) name = stream->streamName().trimmed();
      if (name.isEmpty()) name = su->id();
      names.append(name);
   }
   return names;
}

QStringList FlowsheetState::streamUnitIdsUsingPackage(const QString& packageId) const
{
   QStringList ids;
   if (packageId.trimmed().isEmpty()) return ids;

   for (const auto& unit : units_) {
      auto* su = dynamic_cast<StreamUnitState*>(unit.get());
      if (!su) continue;
      MaterialStreamState* stream = su->streamState();
      if (!stream) continue;

      const QString pkgId = stream->selectedFluidPackageId();
      if (pkgId.compare(packageId, Qt::CaseInsensitive) != 0) continue;

      ids.append(su->id());
   }
   return ids;
}

void FlowsheetState::highlightStream(const QString& unitId)
{
   const QString trimmed = unitId.trimmed();
   if (trimmed.isEmpty()) {
      clearHighlight();
      return;
   }

   if (highlightedUnitId_ != trimmed) {
      highlightedUnitId_ = trimmed;
      emit highlightedUnitIdChanged();
   }
   if (highlightTimer_) {
      highlightTimer_->stop();
      highlightTimer_->start();
   }
}

void FlowsheetState::clearHighlight()
{
   if (highlightTimer_) highlightTimer_->stop();
   if (!highlightedUnitId_.isEmpty()) {
      highlightedUnitId_.clear();
      emit highlightedUnitIdChanged();
   }
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
      else if (type == QStringLiteral("pump"))           base = QStringLiteral("pump");
      else if (type == QStringLiteral("valve"))          base = QStringLiteral("valve");
      else if (type == QStringLiteral("heat_exchanger")) base = QStringLiteral("HEX");
      else if (type == QStringLiteral("separator"))      base = QStringLiteral("separator");
      else if (type == QStringLiteral("tee_splitter"))   base = QStringLiteral("tee");
      else if (type == QStringLiteral("mixer"))           base = QStringLiteral("mixer");
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
// Pump
//
// Single-in / single-out adiabatic liquid pump. Pattern mirrors the Heater
// scaffolding exactly — id prefix "pump", iconKey "pump", default specs are
// 5 bar ΔP at 75% efficiency (set in the PumpUnitState ctor).
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addPumpInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("pump"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("pump");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("pump"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);

   nodes_.push_back(node);

   auto unit = std::make_unique<PumpUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("pump"));
   unit->setIconKey(QStringLiteral("pump"));

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

void FlowsheetState::addPump(double x, double y)
{
   addPumpInternal(x, y);
}

QString FlowsheetState::addPumpAndReturnId(double x, double y)
{
   return addPumpInternal(x, y);
}

// ─────────────────────────────────────────────────────────────────────────────
// Valve
//
// Single-in / single-out adiabatic isenthalpic throttle. Pattern mirrors the
// Pump scaffolding exactly — id prefix "valve", iconKey "valve", default
// spec is 2 bar drop (set in the ValveUnitState ctor). No energy-stream
// connections (passive throttle, no shaft work).
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addValveInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("valve"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("valve");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("valve"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);

   nodes_.push_back(node);

   auto unit = std::make_unique<ValveUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("valve"));
   unit->setIconKey(QStringLiteral("valve"));

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

void FlowsheetState::addValve(double x, double y)
{
   addValveInternal(x, y);
}

QString FlowsheetState::addValveAndReturnId(double x, double y)
{
   return addValveInternal(x, y);
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
// addSeparatorInternal
//
// 2-phase vapor-liquid separator (HYSYS "Separator" / Aspen Plus "Flash2").
// Three ports: feed (inlet), vapor (outlet), liquid (outlet). Construction
// pattern mirrors addHeatExchangerInternal exactly — only the type/iconKey
// strings and the concrete unit class differ.
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addSeparatorInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("separator"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("separator");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("separator"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);
   nodes_.push_back(node);

   auto unit = std::make_unique<SeparatorUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("separator"));
   unit->setIconKey(QStringLiteral("separator"));

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

void FlowsheetState::addSeparator(double x, double y)
{
   addSeparatorInternal(x, y);
}

QString FlowsheetState::addSeparatorAndReturnId(double x, double y)
{
   return addSeparatorInternal(x, y);
}

// ─────────────────────────────────────────────────────────────────────────────
// addSplitterInternal
//
// Tee / Stream Splitter (HYSYS "Tee" / Aspen Plus "FSplit"). Variable-port
// unit: the user-controlled outletCount (default 2, range 2-8) determines
// how many outlet ports exist at any given moment.
//
// Construction wires up two extra observers on top of the standard pattern:
//   1. outletCountChanged → handle shrink: when outletCount drops below
//      the index of any currently-bound outlet stream, that stream's
//      connection is removed and its label is recomputed. Mirrors the
//      "stream gets disconnected" path that removeConnectionsForStream_
//      handles, but driven by the splitter's own state change instead of
//      a stream deletion.
//   2. nameChanged → standard rename-uniqueness handler (same as separator
//      and HEX).
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addSplitterInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("tee_splitter"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("tee_splitter");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("tee_splitter"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);
   nodes_.push_back(node);

   auto unit = std::make_unique<SplitterUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("tee_splitter"));
   unit->setIconKey(QStringLiteral("tee_splitter"));

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

   // Dynamic-port observer: when outletCount shrinks, any stream whose
   // sourcePort points at an outlet beyond the new count must be cleanly
   // disconnected. We can't rely on removeConnectionsForStream_ here
   // because the stream itself is still alive; only its binding to *this*
   // splitter is invalidated. So walk materialConnections_, identify the
   // stale rows, and erase them — re-emitting materialConnectionsChanged
   // so the canvas redraws without the phantom connection lines.
   //
   // We also emit materialConnectionsChanged unconditionally (even when no
   // stale rows were pruned) because the port geometry on the splitter
   // changed — the canvas needs to repaint to reposition dots and snap
   // targets at the new locations. This is safe because the signal only
   // triggers a canvas repaint; nothing else cares about it.
   connect(unit.get(), &SplitterUnitState::outletCountChanged,
           this, [this, id, ptr = unit.get()]() {
      const int liveCount = ptr->outletCount();
      bool changed = false;
      QStringList freedStreams;
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->sourceUnitId == id && it->sourcePort.startsWith(QStringLiteral("outlet"))) {
            // Port name is "outletN" (1-indexed). Extract N.
            bool ok = false;
            const int portIdx = it->sourcePort.mid(6).toInt(&ok);
            if (ok && portIdx > liveCount) {
               freedStreams.append(it->streamUnitId);
               emitConnectionSeveredMessage_(*it, QStringLiteral("splitter outlet count reduced"));
               it = materialConnections_.erase(it);
               changed = true;
               continue;
            }
         }
         ++it;
      }
      if (changed) {
         // Streams that lost their splitter binding need their label
         // refreshed (they're no longer "outletN" of anything).
         for (const QString& sid : freedStreams)
            relabelStreamFromBindings_(sid);
         markDirty_();
      }
      // Always emit — port geometry changed even if no connections pruned.
      emit materialConnectionsChanged();
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

void FlowsheetState::addSplitter(double x, double y)
{
   addSplitterInternal(x, y);
}

QString FlowsheetState::addSplitterAndReturnId(double x, double y)
{
   return addSplitterInternal(x, y);
}

// ─────────────────────────────────────────────────────────────────────────────
// addMixerInternal
//
// Mixer (HYSYS "Mixer" / Aspen Plus "Mixer" block). Variable-port unit on
// the inlet side: user-controlled inletCount (default 2, range 2-8)
// determines how many inlet ports exist at any moment. The dynamic-port
// observer pattern is symmetric to addSplitterInternal — when inletCount
// shrinks, any stream whose targetPort points at an inlet beyond the new
// count is cleanly disconnected, and materialConnectionsChanged is emitted
// regardless so the canvas can repaint port positions.
//
// Port naming: "inlet1"..."inletN" on the target (inlet) side, "product"
// on the source (outlet) side.
// ─────────────────────────────────────────────────────────────────────────────

QString FlowsheetState::addMixerInternal(double x, double y)
{
   const QString id = nextAvailableUnitId_(QStringLiteral("mixer"));

   UnitNode node;
   node.unitId      = id;
   node.type        = QStringLiteral("mixer");
   node.displayName = makeUniqueUnitName_(id, QStringLiteral("mixer"));
   node.x           = clampCoord(x, 42.0, 980.0);
   node.y           = clampCoord(y, 90.0, 620.0);
   nodes_.push_back(node);

   auto unit = std::make_unique<MixerUnitState>();
   unit->setFlowsheetState(this);
   unit->setId(id);
   unit->setName(node.displayName);
   unit->setType(QStringLiteral("mixer"));
   unit->setIconKey(QStringLiteral("mixer"));

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

   // Dynamic-port observer: when inletCount shrinks, any stream whose
   // targetPort points at an inlet beyond the new count is invalidated.
   // Mirror of the splitter observer flipped to the inlet (target) side.
   //
   // We also emit materialConnectionsChanged unconditionally because the
   // mixer's port geometry changed — the canvas needs to repaint to
   // reposition dots and snap targets at the new locations.
   connect(unit.get(), &MixerUnitState::inletCountChanged,
           this, [this, id, ptr = unit.get()]() {
      const int liveCount = ptr->inletCount();
      bool changed = false;
      QStringList freedStreams;
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->targetUnitId == id && it->targetPort.startsWith(QStringLiteral("inlet"))) {
            // Port name is "inletN" (1-indexed). Extract N.
            bool ok = false;
            const int portIdx = it->targetPort.mid(5).toInt(&ok);
            if (ok && portIdx > liveCount) {
               freedStreams.append(it->streamUnitId);
               emitConnectionSeveredMessage_(*it, QStringLiteral("mixer inlet count reduced"));
               it = materialConnections_.erase(it);
               changed = true;
               continue;
            }
         }
         ++it;
      }
      if (changed) {
         for (const QString& sid : freedStreams)
            relabelStreamFromBindings_(sid);
         markDirty_();
      }
      // Always emit — port geometry changed even if no connections pruned.
      emit materialConnectionsChanged();
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

void FlowsheetState::addMixer(double x, double y)
{
   addMixerInternal(x, y);
}

QString FlowsheetState::addMixerAndReturnId(double x, double y)
{
   return addMixerInternal(x, y);
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

   if (!checkSelfLoop_(streamUnitId, hexUnitId, isInlet ? QStringLiteral("inlet") : QStringLiteral("outlet")))
      return false;
   if (isInlet) {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, c.sourceUnitId, hexUnitId);
            break;
         }
      }
   } else {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, hexUnitId, c.targetUnitId);
            break;
         }
      }
   }
   checkFluidPackageOnBind_(streamUnitId, hexUnitId);

   // Displace any stream already on this port
   if (isInlet) {
      if (auto existing = findConnectionForTarget_(hexUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // already bound
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior target binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort == QStringLiteral("hotIn"))  hx->setConnectedHotInStreamUnitId(QString{});
               if (it->targetPort == QStringLiteral("coldIn")) hx->setConnectedColdInStreamUnitId(QString{});
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }
   } else {
      if (auto existing = findConnectionForSource_(hexUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // already bound
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior source binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("hotOut"))  hx->setConnectedHotOutStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("coldOut")) hx->setConnectedColdOutStreamUnitId(QString{});
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
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

// ─────────────────────────────────────────────────────────────────────────────
// bindSeparatorStream
//
// Single multi-port bind method (mirrors bindHexStream). Port values:
//   "feed"   → target side  (inlet)
//   "vapor"  → source side  (outlet)
//   "liquid" → source side  (outlet)
// Any other port name returns false.
//
// Same displacement semantics as bindHexStream:
//   - If another stream already occupies the same port on this separator,
//     it is fully disconnected (its other bindings on other units are also
//     cleared via removeConnectionsForStream_).
//   - If the supplied stream already has a binding in the same role
//     (target if connecting to feed; source if connecting to vapor/liquid)
//     on a different unit, only that role-specific binding is removed.
//     Bindings in the *other* role remain — i.e. a stream that is currently
//     a heater product can become this separator's feed without losing its
//     heater connection.
// ─────────────────────────────────────────────────────────────────────────────

bool FlowsheetState::bindSeparatorStream(const QString& separatorUnitId,
                                          const QString& port,
                                          const QString& streamUnitId)
{
   auto* sep        = dynamic_cast<SeparatorUnitState*>(findUnitById(separatorUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!sep || !streamUnit) return false;

   const bool isFeed   = (port == QStringLiteral("feed"));
   const bool isVapor  = (port == QStringLiteral("vapor"));
   const bool isLiquid = (port == QStringLiteral("liquid"));
   if (!isFeed && !isVapor && !isLiquid) return false;

   if (!checkSelfLoop_(streamUnitId, separatorUnitId, isFeed ? QStringLiteral("inlet") : QStringLiteral("outlet")))
      return false;
   if (isFeed) {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, c.sourceUnitId, separatorUnitId);
            break;
         }
      }
   } else {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, separatorUnitId, c.targetUnitId);
            break;
         }
      }
   }
   checkFluidPackageOnBind_(streamUnitId, separatorUnitId);

   if (isFeed) {
      // Inlet path (target side)
      if (auto existing = findConnectionForTarget_(separatorUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // no-op
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior target binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
               col->setConnectedFeedStreamUnitId(QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
               hc->setConnectedFeedStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
               pp->setConnectedFeedStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
               vv->setConnectedFeedStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort == QStringLiteral("hotIn"))  hx->setConnectedHotInStreamUnitId(QString{});
               if (it->targetPort == QStringLiteral("coldIn")) hx->setConnectedColdInStreamUnitId(QString{});
            }
            if (auto* sp = dynamic_cast<SeparatorUnitState*>(findUnitById(it->targetUnitId)))
               sp->setConnectedFeedStreamUnitId(QString{});
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, QString{}, QString{}, separatorUnitId, port});
      sep->setConnectedFeedStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));

   } else {
      // Outlet path (source side) — handles both vapor and liquid
      if (auto existing = findConnectionForSource_(separatorUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true; // no-op
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior source binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
               col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
               hc->setConnectedProductStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
               pp->setConnectedProductStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
               vv->setConnectedProductStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("hotOut"))  hx->setConnectedHotOutStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("coldOut")) hx->setConnectedColdOutStreamUnitId(QString{});
            }
            if (auto* sp = dynamic_cast<SeparatorUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("vapor"))  sp->setConnectedVaporStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("liquid")) sp->setConnectedLiquidStreamUnitId(QString{});
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, separatorUnitId, port, QString{}, QString{}});
      if (isVapor)
         sep->setConnectedVaporStreamUnitId(streamUnitId);
      else
         sep->setConnectedLiquidStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   }

   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   markDirty_();
   return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// bindSplitterStream
//
// Single multi-port bind method (mirrors bindSeparatorStream). Port values:
//   "feed"      → target side (inlet)
//   "outletN"   → source side (outlet), where N is 1..outletCount.
//
// Outlet-port index validation: ports beyond the splitter's current
// outletCount are rejected. Index extraction uses "outlet" + N where N is
// 1-indexed user-facing; internally setConnectedOutletStreamUnitId() takes
// a 0-indexed int.
//
// Same displacement semantics as bindHexStream / bindSeparatorStream:
//   - If another stream already occupies the same port on this splitter,
//     it is fully disconnected.
//   - If the supplied stream already has a binding in the same role, that
//     prior role-binding is removed; bindings in the other role remain.
// ─────────────────────────────────────────────────────────────────────────────

bool FlowsheetState::bindSplitterStream(const QString& splitterUnitId,
                                         const QString& port,
                                         const QString& streamUnitId)
{
   auto* sp         = dynamic_cast<SplitterUnitState*>(findUnitById(splitterUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!sp || !streamUnit) return false;

   const bool isFeed = (port == QStringLiteral("feed"));
   int outletIndex = -1;
   if (!isFeed) {
      // Expecting "outletN" with N in [1, outletCount].
      if (!port.startsWith(QStringLiteral("outlet"))) return false;
      bool ok = false;
      const int oneIndexed = port.mid(6).toInt(&ok);
      if (!ok) return false;
      if (oneIndexed < 1 || oneIndexed > sp->outletCount()) return false;
      outletIndex = oneIndexed - 1;   // → 0-indexed for state API
   }

   if (!checkSelfLoop_(streamUnitId, splitterUnitId, isFeed ? QStringLiteral("inlet") : QStringLiteral("outlet")))
      return false;
   if (isFeed) {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, c.sourceUnitId, splitterUnitId);
            break;
         }
      }
   } else {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, splitterUnitId, c.targetUnitId);
            break;
         }
      }
   }
   checkFluidPackageOnBind_(streamUnitId, splitterUnitId);

   if (isFeed) {
      // Inlet path (target side)
      if (auto existing = findConnectionForTarget_(splitterUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true;
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior target binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
               col->setConnectedFeedStreamUnitId(QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
               hc->setConnectedFeedStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
               pp->setConnectedFeedStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
               vv->setConnectedFeedStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort == QStringLiteral("hotIn"))  hx->setConnectedHotInStreamUnitId(QString{});
               if (it->targetPort == QStringLiteral("coldIn")) hx->setConnectedColdInStreamUnitId(QString{});
            }
            if (auto* spx = dynamic_cast<SeparatorUnitState*>(findUnitById(it->targetUnitId)))
               spx->setConnectedFeedStreamUnitId(QString{});
            if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->targetUnitId)))
               tee->setConnectedFeedStreamUnitId(QString{});
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, QString{}, QString{}, splitterUnitId, port});
      sp->setConnectedFeedStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));

   } else {
      // Outlet path (source side)
      if (auto existing = findConnectionForSource_(splitterUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true;
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior source binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
               col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
               hc->setConnectedProductStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
               pp->setConnectedProductStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
               vv->setConnectedProductStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("hotOut"))  hx->setConnectedHotOutStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("coldOut")) hx->setConnectedColdOutStreamUnitId(QString{});
            }
            if (auto* spx = dynamic_cast<SeparatorUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("vapor"))  spx->setConnectedVaporStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("liquid")) spx->setConnectedLiquidStreamUnitId(QString{});
            }
            if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort.startsWith(QStringLiteral("outlet"))) {
                  bool okIdx = false;
                  const int prevIdx = it->sourcePort.mid(6).toInt(&okIdx);
                  if (okIdx) tee->setConnectedOutletStreamUnitId(prevIdx - 1, QString{});
               }
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, splitterUnitId, port, QString{}, QString{}});
      sp->setConnectedOutletStreamUnitId(outletIndex, streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   }

   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   markDirty_();
   return true;
}

int FlowsheetState::splitterOutletCount(const QString& splitterUnitId) const
{
   auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(splitterUnitId));
   return tee ? tee->outletCount() : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// bindMixerStream
//
// Single multi-port bind method symmetric with bindSplitterStream. Port values:
//   "inletN"  → target side (inlet),  N in [1, inletCount]
//   "product" → source side (outlet)
//
// Inlet-port index validation: ports beyond the mixer's current inletCount
// are rejected. Index extraction uses "inlet" + N where N is 1-indexed
// user-facing; internally setConnectedInletStreamUnitId() takes a 0-indexed int.
//
// Same displacement semantics as bindSplitterStream:
//   - If another stream already occupies the same port on this mixer,
//     it is fully disconnected.
//   - If the supplied stream already has a binding in the same role, that
//     prior role-binding is removed; bindings in the other role remain.
//
// Note: this routine clears any *prior* mixer inlet binding the stream may
// have had (in the inner "remove prior target binding" loop), via the same
// dynamic-cast cascade other bind routines use.
// ─────────────────────────────────────────────────────────────────────────────

bool FlowsheetState::bindMixerStream(const QString& mixerUnitId,
                                      const QString& port,
                                      const QString& streamUnitId)
{
   auto* mx         = dynamic_cast<MixerUnitState*>(findUnitById(mixerUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!mx || !streamUnit) return false;

   const bool isProduct = (port == QStringLiteral("product"));
   int inletIndex = -1;
   if (!isProduct) {
      // Expecting "inletN" with N in [1, inletCount].
      if (!port.startsWith(QStringLiteral("inlet"))) return false;
      bool ok = false;
      const int oneIndexed = port.mid(5).toInt(&ok);
      if (!ok) return false;
      if (oneIndexed < 1 || oneIndexed > mx->inletCount()) return false;
      inletIndex = oneIndexed - 1;   // → 0-indexed for state API
   }

   if (!checkSelfLoop_(streamUnitId, mixerUnitId, isProduct ? QStringLiteral("outlet") : QStringLiteral("inlet")))
      return false;
   if (isProduct) {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, mixerUnitId, c.targetUnitId);
            break;
         }
      }
   } else {
      for (const auto& c : materialConnections_) {
         if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
            checkCycleOnBind_(streamUnitId, c.sourceUnitId, mixerUnitId);
            break;
         }
      }
   }
   checkFluidPackageOnBind_(streamUnitId, mixerUnitId);

   if (!isProduct) {
      // Inlet path (target side)
      if (auto existing = findConnectionForTarget_(mixerUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true;
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior target binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
               col->setConnectedFeedStreamUnitId(QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
               hc->setConnectedFeedStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
               pp->setConnectedFeedStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
               vv->setConnectedFeedStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort == QStringLiteral("hotIn"))  hx->setConnectedHotInStreamUnitId(QString{});
               if (it->targetPort == QStringLiteral("coldIn")) hx->setConnectedColdInStreamUnitId(QString{});
            }
            if (auto* spx = dynamic_cast<SeparatorUnitState*>(findUnitById(it->targetUnitId)))
               spx->setConnectedFeedStreamUnitId(QString{});
            if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->targetUnitId)))
               tee->setConnectedFeedStreamUnitId(QString{});
            if (auto* mxOther = dynamic_cast<MixerUnitState*>(findUnitById(it->targetUnitId))) {
               if (it->targetPort.startsWith(QStringLiteral("inlet"))) {
                  bool okIdx = false;
                  const int prevIdx = it->targetPort.mid(5).toInt(&okIdx);
                  if (okIdx) mxOther->setConnectedInletStreamUnitId(prevIdx - 1, QString{});
               }
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, QString{}, QString{}, mixerUnitId, port});
      mx->setConnectedInletStreamUnitId(inletIndex, streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));

   } else {
      // Product path (source side, single outlet)
      if (auto existing = findConnectionForSource_(mixerUnitId, port)) {
         if (existing->streamUnitId == streamUnitId) return true;
         const QString prev = existing->streamUnitId;
         removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
         relabelStreamFromBindings_(prev);
      }
      // Remove any prior source binding on this stream
      for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
         if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
            if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
               col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
            if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
               hc->setConnectedProductStreamUnitId(QString{});
            if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
               pp->setConnectedProductStreamUnitId(QString{});
            if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
               vv->setConnectedProductStreamUnitId(QString{});
            if (auto* hx = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("hotOut"))  hx->setConnectedHotOutStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("coldOut")) hx->setConnectedColdOutStreamUnitId(QString{});
            }
            if (auto* spx = dynamic_cast<SeparatorUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("vapor"))  spx->setConnectedVaporStreamUnitId(QString{});
               if (it->sourcePort == QStringLiteral("liquid")) spx->setConnectedLiquidStreamUnitId(QString{});
            }
            if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort.startsWith(QStringLiteral("outlet"))) {
                  bool okIdx = false;
                  const int prevIdx = it->sourcePort.mid(6).toInt(&okIdx);
                  if (okIdx) tee->setConnectedOutletStreamUnitId(prevIdx - 1, QString{});
               }
            }
            if (auto* mxOther = dynamic_cast<MixerUnitState*>(findUnitById(it->sourceUnitId))) {
               if (it->sourcePort == QStringLiteral("product"))
                  mxOther->setConnectedProductStreamUnitId(QString{});
            }
            emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
            it = materialConnections_.erase(it);
         } else {
            ++it;
         }
      }

      materialConnections_.push_back(MaterialConnection{
          streamUnitId, mixerUnitId, port, QString{}, QString{}});
      mx->setConnectedProductStreamUnitId(streamUnitId);
      setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   }

   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   markDirty_();
   return true;
}

int FlowsheetState::mixerInletCount(const QString& mixerUnitId) const
{
   auto* mx = dynamic_cast<MixerUnitState*>(findUnitById(mixerUnitId));
   return mx ? mx->inletCount() : 0;
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

   // Bind-time validation: refuse self-loops; warn (don't refuse) on
   // recycle creation and fluid-package mismatches.
   if (!checkSelfLoop_(streamUnitId, columnUnitId, QStringLiteral("inlet")))
      return false;
   // For cycle detection, the proposed edge is sourceUnit→columnUnitId via
   // streamUnitId. The source is whatever unit already has streamUnitId
   // bound as its product (if any).
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, c.sourceUnitId, columnUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, columnUnitId);

   // Only refuse if this stream is already occupying the SAME ROLE (target/feed).
   // A stream can be a source on one unit and a target on another simultaneously.
   if (auto existing = findConnectionForTarget_(columnUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString previousStreamUnitId = existing->streamUnitId;
      removeConnectionsForStream_(previousStreamUnitId, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(previousStreamUnitId);
   }
   // If stream is already a target somewhere else, remove that prior target binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
            pp->setConnectedFeedStreamUnitId(QString{});
         if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
            vv->setConnectedFeedStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
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

   if (!checkSelfLoop_(streamUnitId, columnUnitId, QStringLiteral("outlet")))
      return false;
   // The proposed edge is columnUnitId→targetUnit via streamUnitId.
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, columnUnitId, c.targetUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, columnUnitId);

   // Displace any stream already occupying this specific source port on the column
   if (auto existing = findConnectionForSource_(columnUnitId, normalizedPort)) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString previousStreamUnitId = existing->streamUnitId;
      removeConnectionsForStream_(previousStreamUnitId, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(previousStreamUnitId);
   }
   // If stream is already a source somewhere else, remove that prior source binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
            pp->setConnectedProductStreamUnitId(QString{});
         if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
            vv->setConnectedProductStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
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

   if (!checkSelfLoop_(streamUnitId, heaterUnitId, QStringLiteral("inlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, c.sourceUnitId, heaterUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, heaterUnitId);

   // Displace any stream already occupying this heater's feed port (same role conflict)
   if (auto existing = findConnectionForTarget_(heaterUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   // If stream is already a target (feed) on another unit, remove that prior binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
            pp->setConnectedFeedStreamUnitId(QString{});
         if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
            vv->setConnectedFeedStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
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

   if (!checkSelfLoop_(streamUnitId, heaterUnitId, QStringLiteral("outlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, heaterUnitId, c.targetUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, heaterUnitId);

   // Displace any stream already occupying this heater's product port (same role conflict)
   if (auto existing = findConnectionForSource_(heaterUnitId, QStringLiteral("product"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound, no-op
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   // If stream is already a source (product) on another unit, remove that prior binding only
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         if (auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
            pp->setConnectedProductStreamUnitId(QString{});
         if (auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
            vv->setConnectedProductStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
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

// ─────────────────────────────────────────────────────────────────────────────
// Pump stream bindings — same structural pattern as bindHeaterFeedStream /
// bindHeaterProductStream. See those functions for inline commentary; the
// only differences here are (a) the dynamic_cast target (PumpUnitState) and
// (b) the role-displacement loops also clear pump bindings on the existing
// stream side, which keeps the symmetric "stream gained a new role" logic
// consistent across all unit-op types.
// ─────────────────────────────────────────────────────────────────────────────
bool FlowsheetState::bindPumpFeedStream(const QString& pumpUnitId, const QString& streamUnitId)
{
   auto* pump       = dynamic_cast<PumpUnitState*>(findUnitById(pumpUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!pump || !streamUnit)
      return false;

   if (!checkSelfLoop_(streamUnitId, pumpUnitId, QStringLiteral("inlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, c.sourceUnitId, pumpUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, pumpUnitId);

   // Displace any stream already occupying this pump's feed port.
   if (auto existing = findConnectionForTarget_(pumpUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   // Remove this stream's prior target binding on any other unit.
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         if (auto* pp2 = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
            pp2->setConnectedFeedStreamUnitId(QString{});
         if (auto* vv2 = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
            vv2->setConnectedFeedStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       QString{},
       QString{},
       pumpUnitId,
       QStringLiteral("feed")
   });

   pump->setConnectedFeedStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::bindPumpProductStream(const QString& pumpUnitId, const QString& streamUnitId)
{
   auto* pump       = dynamic_cast<PumpUnitState*>(findUnitById(pumpUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!pump || !streamUnit)
      return false;

   if (!checkSelfLoop_(streamUnitId, pumpUnitId, QStringLiteral("outlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, pumpUnitId, c.targetUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, pumpUnitId);

   if (auto existing = findConnectionForSource_(pumpUnitId, QStringLiteral("product"))) {
      if (existing->streamUnitId == streamUnitId) return true;
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         if (auto* pp2 = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
            pp2->setConnectedProductStreamUnitId(QString{});
         if (auto* vv2 = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
            vv2->setConnectedProductStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       pumpUnitId,
       QStringLiteral("product"),
       QString{},
       QString{}
   });

   pump->setConnectedProductStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Valve stream bindings — same structural pattern as bindPumpFeedStream /
// bindPumpProductStream. The valve has no energy stream so we only need
// feed and product binders. The role-displacement loops also clear valve
// bindings on the existing stream side, which keeps the symmetric
// "stream gained a new role" logic consistent across all unit-op types.
// ─────────────────────────────────────────────────────────────────────────────
bool FlowsheetState::bindValveFeedStream(const QString& valveUnitId, const QString& streamUnitId)
{
   auto* valve      = dynamic_cast<ValveUnitState*>(findUnitById(valveUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!valve || !streamUnit)
      return false;

   if (!checkSelfLoop_(streamUnitId, valveUnitId, QStringLiteral("inlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.sourceUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, c.sourceUnitId, valveUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, valveUnitId);

   // Displace any stream already occupying this valve's feed port.
   if (auto existing = findConnectionForTarget_(valveUnitId, QStringLiteral("feed"))) {
      if (existing->streamUnitId == streamUnitId) return true; // already bound
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   // Remove this stream's prior target binding on any other unit.
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->targetUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            col->setConnectedFeedStreamUnitId(QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            hc->setConnectedFeedStreamUnitId(QString{});
         if (auto* pp2 = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
            pp2->setConnectedFeedStreamUnitId(QString{});
         if (auto* vv2 = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
            vv2->setConnectedFeedStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       QString{},
       QString{},
       valveUnitId,
       QStringLiteral("feed")
   });

   valve->setConnectedFeedStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("inlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::bindValveProductStream(const QString& valveUnitId, const QString& streamUnitId)
{
   auto* valve      = dynamic_cast<ValveUnitState*>(findUnitById(valveUnitId));
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!valve || !streamUnit)
      return false;

   if (!checkSelfLoop_(streamUnitId, valveUnitId, QStringLiteral("outlet")))
      return false;
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId && !c.targetUnitId.isEmpty()) {
         checkCycleOnBind_(streamUnitId, valveUnitId, c.targetUnitId);
         break;
      }
   }
   checkFluidPackageOnBind_(streamUnitId, valveUnitId);

   if (auto existing = findConnectionForSource_(valveUnitId, QStringLiteral("product"))) {
      if (existing->streamUnitId == streamUnitId) return true;
      const QString prev = existing->streamUnitId;
      removeConnectionsForStream_(prev, QStringLiteral("replaced by another stream"));
      relabelStreamFromBindings_(prev);
   }
   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId == streamUnitId && !it->sourceUnitId.isEmpty()) {
         if (auto* col = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            col->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* hc = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            hc->setConnectedProductStreamUnitId(QString{});
         if (auto* pp2 = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
            pp2->setConnectedProductStreamUnitId(QString{});
         if (auto* vv2 = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
            vv2->setConnectedProductStreamUnitId(QString{});
         emitConnectionSeveredMessage_(*it, QStringLiteral("stream gained a new role binding"));
         it = materialConnections_.erase(it);
      } else {
         ++it;
      }
   }

   materialConnections_.push_back(MaterialConnection{
       streamUnitId,
       valveUnitId,
       QStringLiteral("product"),
       QString{},
       QString{}
   });

   valve->setConnectedProductStreamUnitId(streamUnitId);
   setStreamConnectionDirection(streamUnitId, QStringLiteral("outlet"));
   markDirty_();
   setLastOperationMessage_(QString{});
   emit materialConnectionsChanged();
   return true;
}

bool FlowsheetState::disconnectMaterialStream(const QString& streamUnitId)
{
   const auto before = materialConnections_.size();
   removeConnectionsForStream_(streamUnitId, QStringLiteral("disconnected by user"));
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
   removeConnectionsForStream_(unitId, QStringLiteral("stream deleted"));
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

void FlowsheetState::removeConnectionsForStream_(const QString& streamUnitId, const QString& severeReason)
{
   if (streamUnitId.isEmpty())
      return;

   for (auto it = materialConnections_.begin(); it != materialConnections_.end();) {
      if (it->streamUnitId != streamUnitId) {
         ++it;
         continue;
      }

      // Post a trace message for the severed connection BEFORE clearing
      // the unit-side pointer state. Empty severeReason means caller did
      // not opt into messaging (e.g. deletion / clear paths where the
      // user already initiated the removal explicitly).
      if (!severeReason.isEmpty()) {
         emitConnectionSeveredMessage_(*it, severeReason);
      }

      if (!it->targetUnitId.isEmpty()) {
         if (auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(it->targetUnitId)))
            column->setConnectedFeedStreamUnitId(QString{});
         if (auto* heater = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->targetUnitId)))
            heater->setConnectedFeedStreamUnitId(QString{});
         if (auto* pump = dynamic_cast<PumpUnitState*>(findUnitById(it->targetUnitId)))
            pump->setConnectedFeedStreamUnitId(QString{});
         if (auto* valve = dynamic_cast<ValveUnitState*>(findUnitById(it->targetUnitId)))
            valve->setConnectedFeedStreamUnitId(QString{});
         if (auto* hex = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->targetUnitId))) {
            if (it->targetPort == QStringLiteral("hotIn"))  hex->setConnectedHotInStreamUnitId(QString{});
            if (it->targetPort == QStringLiteral("coldIn")) hex->setConnectedColdInStreamUnitId(QString{});
         }
         if (auto* sep = dynamic_cast<SeparatorUnitState*>(findUnitById(it->targetUnitId)))
            sep->setConnectedFeedStreamUnitId(QString{});
         if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->targetUnitId)))
            tee->setConnectedFeedStreamUnitId(QString{});
         if (auto* mx = dynamic_cast<MixerUnitState*>(findUnitById(it->targetUnitId))) {
            if (it->targetPort.startsWith(QStringLiteral("inlet"))) {
               bool okIdx = false;
               const int mxIdx = it->targetPort.mid(5).toInt(&okIdx);
               if (okIdx) mx->setConnectedInletStreamUnitId(mxIdx - 1, QString{});
            }
         }
      }
      if (!it->sourceUnitId.isEmpty()) {
         if (auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
            column->setConnectedProductStreamUnitId(it->sourcePort, QString{});
         if (auto* heater = dynamic_cast<HeaterCoolerUnitState*>(findUnitById(it->sourceUnitId)))
            heater->setConnectedProductStreamUnitId(QString{});
         if (auto* pump = dynamic_cast<PumpUnitState*>(findUnitById(it->sourceUnitId)))
            pump->setConnectedProductStreamUnitId(QString{});
         if (auto* valve = dynamic_cast<ValveUnitState*>(findUnitById(it->sourceUnitId)))
            valve->setConnectedProductStreamUnitId(QString{});
         if (auto* hex = dynamic_cast<HeatExchangerUnitState*>(findUnitById(it->sourceUnitId))) {
            if (it->sourcePort == QStringLiteral("hotOut"))  hex->setConnectedHotOutStreamUnitId(QString{});
            if (it->sourcePort == QStringLiteral("coldOut")) hex->setConnectedColdOutStreamUnitId(QString{});
         }
         if (auto* sep = dynamic_cast<SeparatorUnitState*>(findUnitById(it->sourceUnitId))) {
            if (it->sourcePort == QStringLiteral("vapor"))  sep->setConnectedVaporStreamUnitId(QString{});
            if (it->sourcePort == QStringLiteral("liquid")) sep->setConnectedLiquidStreamUnitId(QString{});
         }
         if (auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(it->sourceUnitId))) {
            if (it->sourcePort.startsWith(QStringLiteral("outlet"))) {
               bool okIdx = false;
               const int teeIdx = it->sourcePort.mid(6).toInt(&okIdx);
               if (okIdx) tee->setConnectedOutletStreamUnitId(teeIdx - 1, QString{});
            }
         }
         if (auto* mx = dynamic_cast<MixerUnitState*>(findUnitById(it->sourceUnitId))) {
            if (it->sourcePort == QStringLiteral("product"))
               mx->setConnectedProductStreamUnitId(QString{});
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

QStringList FlowsheetState::allUnitIds() const
{
   QStringList ids;
   ids.reserve(static_cast<int>(units_.size()));
   for (const auto& unit : units_) {
      if (unit) ids.push_back(unit->id());
   }
   return ids;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bind-time messaging helpers
// ─────────────────────────────────────────────────────────────────────────────

namespace {
   // Format a port name for human display: "outlet1" → "outlet 1",
   // "hotIn" → "hot inlet", "coldOut" → "cold outlet". Fallback returns
   // the raw string. Centralised here to keep message wording consistent.
   QString prettyPort(const QString& port) {
      if (port == QStringLiteral("hotIn"))   return QStringLiteral("hot inlet");
      if (port == QStringLiteral("hotOut"))  return QStringLiteral("hot outlet");
      if (port == QStringLiteral("coldIn"))  return QStringLiteral("cold inlet");
      if (port == QStringLiteral("coldOut")) return QStringLiteral("cold outlet");
      if (port == QStringLiteral("vapor"))   return QStringLiteral("vapor outlet");
      if (port == QStringLiteral("liquid"))  return QStringLiteral("liquid outlet");
      if (port == QStringLiteral("feed"))    return QStringLiteral("feed");
      if (port == QStringLiteral("product")) return QStringLiteral("product");
      if (port == QStringLiteral("distillate")) return QStringLiteral("distillate");
      if (port == QStringLiteral("bottoms")) return QStringLiteral("bottoms");
      if (port.startsWith(QStringLiteral("inlet"))) {
         bool ok = false;
         const int n = port.mid(5).toInt(&ok);
         return ok ? QStringLiteral("inlet %1").arg(n) : port;
      }
      if (port.startsWith(QStringLiteral("outlet"))) {
         bool ok = false;
         const int n = port.mid(6).toInt(&ok);
         return ok ? QStringLiteral("outlet %1").arg(n) : port;
      }
      return port;
   }
}

void FlowsheetState::emitConnectionSeveredMessage_(const MaterialConnection& severed,
                                                    const QString& reason)
{
   auto* log = MessageLog::instance();
   if (!log) return;

   // The "now-broken" unit is the one that's losing the binding. For a
   // target-side severance, that's the target unit (the inlet's gone, so
   // the target unit now has a hole). For a source-side severance, the
   // source unit is now broken. The click-target unitId should point to
   // whichever is now broken so the user can navigate there to fix it.
   QString brokenUnitId;
   QString text;

   if (!severed.targetUnitId.isEmpty()) {
      brokenUnitId = severed.targetUnitId;
      text = QStringLiteral("%1 disconnected from %2 %3 (%4)")
                .arg(severed.streamUnitId)
                .arg(severed.targetUnitId)
                .arg(prettyPort(severed.targetPort))
                .arg(reason);
   } else if (!severed.sourceUnitId.isEmpty()) {
      brokenUnitId = severed.sourceUnitId;
      text = QStringLiteral("%1 disconnected from %2 %3 (%4)")
                .arg(severed.streamUnitId)
                .arg(severed.sourceUnitId)
                .arg(prettyPort(severed.sourcePort))
                .arg(reason);
   } else {
      // Defensive: severed connection has no endpoint?
      return;
   }

   log->warn(QStringLiteral("Connection"), text, brokenUnitId);
}

bool FlowsheetState::checkSelfLoop_(const QString& streamUnitId,
                                     const QString& unitId,
                                     const QString& portRole)
{
   // Walk current connections looking for the SAME stream already in the
   // OPPOSITE role on the SAME unit.
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId != streamUnitId) continue;

      const bool streamIsTarget = !c.targetUnitId.isEmpty();
      const bool streamIsSource = !c.sourceUnitId.isEmpty();
      const bool sameTargetUnit = streamIsTarget && c.targetUnitId == unitId;
      const bool sameSourceUnit = streamIsSource && c.sourceUnitId == unitId;

      const bool wouldLoop =
         (portRole == QStringLiteral("inlet")  && sameSourceUnit) ||
         (portRole == QStringLiteral("outlet") && sameTargetUnit);

      if (wouldLoop) {
         if (auto* log = MessageLog::instance()) {
            log->error(QStringLiteral("Connection"),
                       QStringLiteral("Refused: %1 cannot be both an inlet and an outlet of %2 — that would be a self-loop")
                          .arg(streamUnitId).arg(unitId),
                       unitId);
         }
         return false;
      }
   }
   return true;
}

void FlowsheetState::checkCycleOnBind_(const QString& streamUnitId,
                                        const QString& sourceUnitId,
                                        const QString& targetUnitId)
{
   // The proposed binding adds an edge sourceUnitId → targetUnitId via
   // streamUnitId. A directed cycle exists if there's already a path
   // from targetUnitId back to sourceUnitId in the existing graph.
   //
   // BFS from targetUnitId, following source→target edges only, looking
   // for sourceUnitId as a reachable node.
   if (sourceUnitId.isEmpty() || targetUnitId.isEmpty()) return;
   if (sourceUnitId == targetUnitId) return;  // already covered by self-loop check

   QStringList queue;
   QSet<QString> visited;
   queue.push_back(targetUnitId);
   visited.insert(targetUnitId);

   bool foundCycle = false;
   while (!queue.isEmpty() && !foundCycle) {
      const QString current = queue.takeFirst();
      // Find all streams sourced from `current`, follow them to their target.
      for (const auto& c : materialConnections_) {
         if (c.sourceUnitId != current) continue;
         if (c.targetUnitId.isEmpty()) continue;
         if (c.targetUnitId == sourceUnitId) {
            foundCycle = true;
            break;
         }
         if (!visited.contains(c.targetUnitId)) {
            visited.insert(c.targetUnitId);
            queue.push_back(c.targetUnitId);
         }
      }
   }

   if (foundCycle) {
      if (auto* log = MessageLog::instance()) {
         log->warn(QStringLiteral("Connection"),
                   QStringLiteral("Connecting %1 from %2 to %3 closes a recycle loop — recycle convergence is not yet supported, the flowsheet won't fully solve")
                      .arg(streamUnitId).arg(sourceUnitId).arg(targetUnitId),
                   targetUnitId);
      }
   }
}

void FlowsheetState::checkFluidPackageOnBind_(const QString& streamUnitId,
                                               const QString& counterpartUnitId)
{
   // Compare the stream's currently-set fluid package against any other
   // streams attached to the counterpart unit. If there's a mismatch,
   // warn — the bind itself proceeds (the user might be in the middle of
   // restructuring, and the Mixer/HEX solve will warn again at solve time).
   auto* streamUnit = findStreamUnitById(streamUnitId);
   if (!streamUnit) return;
   auto* stream = streamUnit->streamState();
   if (!stream) return;

   const QString streamPkg = stream->selectedFluidPackageId();
   if (streamPkg.isEmpty()) return;   // unset package = nothing to compare

   // Find any other stream connected to this counterpart unit.
   for (const auto& c : materialConnections_) {
      if (c.streamUnitId == streamUnitId) continue;
      const bool touchesCounterpart =
         (c.sourceUnitId == counterpartUnitId) || (c.targetUnitId == counterpartUnitId);
      if (!touchesCounterpart) continue;

      auto* otherSU = findStreamUnitById(c.streamUnitId);
      if (!otherSU) continue;
      auto* otherS = otherSU->streamState();
      if (!otherS) continue;
      const QString otherPkg = otherS->selectedFluidPackageId();
      if (otherPkg.isEmpty()) continue;
      if (otherPkg != streamPkg) {
         if (auto* log = MessageLog::instance()) {
            log->warn(QStringLiteral("Validation"),
                      QStringLiteral("%1 uses fluid package '%2' but other streams on %3 use '%4' — solve results may be approximate")
                         .arg(streamUnitId).arg(streamPkg).arg(counterpartUnitId).arg(otherPkg),
                      counterpartUnitId);
         }
         return;   // one warning is enough
      }
   }
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

      // ── Pump state ────────────────────────────────────────────────────────
      else if (node.type == QStringLiteral("pump")) {
         auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(node.unitId));
         if (pp) {
            QJsonObject p;
            p[QStringLiteral("specMode")]             = pp->specMode();
            p[QStringLiteral("outletPressurePa")]     = pp->outletPressurePa();
            p[QStringLiteral("deltaPPa")]             = pp->deltaPPa();
            p[QStringLiteral("powerKW")]              = pp->powerKW();
            p[QStringLiteral("adiabaticEfficiency")]  = pp->adiabaticEfficiency();
            // Connection IDs — persisted so we can re-wire on load
            p[QStringLiteral("feedStreamUnitId")]     = pp->connectedFeedStreamUnitId();
            p[QStringLiteral("productStreamUnitId")]  = pp->connectedProductStreamUnitId();
            u[QStringLiteral("pumpState")]            = p;
         }
      }

      // ── Valve state ───────────────────────────────────────────────────────
      else if (node.type == QStringLiteral("valve")) {
         auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(node.unitId));
         if (vv) {
            QJsonObject v;
            v[QStringLiteral("specMode")]            = vv->specMode();
            v[QStringLiteral("outletPressurePa")]    = vv->outletPressurePa();
            v[QStringLiteral("deltaPPa")]            = vv->deltaPPa();
            // Connection IDs — persisted so we can re-wire on load
            v[QStringLiteral("feedStreamUnitId")]    = vv->connectedFeedStreamUnitId();
            v[QStringLiteral("productStreamUnitId")] = vv->connectedProductStreamUnitId();
            u[QStringLiteral("valveState")]          = v;
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

      // ── Separator state ───────────────────────────────────────────────────
      else if (node.type == QStringLiteral("separator")) {
         auto* sp = dynamic_cast<SeparatorUnitState*>(findUnitById(node.unitId));
         if (sp) {
            QJsonObject h;
            h[QStringLiteral("specMode")]            = sp->specMode();
            h[QStringLiteral("vesselTemperatureK")]  = sp->vesselTemperatureK();
            h[QStringLiteral("dutyKW")]              = sp->dutyKW();
            h[QStringLiteral("pressureDropPa")]      = sp->pressureDropPa();
            u[QStringLiteral("separatorState")]      = h;
         }
      }

      // ── Splitter (Tee) state ──────────────────────────────────────────────
      else if (node.type == QStringLiteral("tee_splitter")) {
         auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(node.unitId));
         if (tee) {
            QJsonObject h;
            h[QStringLiteral("outletCount")]    = tee->outletCount();
            h[QStringLiteral("pressureDropPa")] = tee->pressureDropPa();
            QJsonArray fracs;
            for (int i = 0; i < tee->outletCount(); ++i)
               fracs.append(tee->outletFraction(i));
            h[QStringLiteral("outletFractions")] = fracs;
            u[QStringLiteral("splitterState")]   = h;
         }
      }

      // ── Mixer state ───────────────────────────────────────────────────────
      else if (node.type == QStringLiteral("mixer")) {
         auto* mx = dynamic_cast<MixerUnitState*>(findUnitById(node.unitId));
         if (mx) {
            QJsonObject h;
            h[QStringLiteral("inletCount")]                = mx->inletCount();
            h[QStringLiteral("pressureMode")]              = mx->pressureMode();
            h[QStringLiteral("specifiedOutletPressurePa")] = mx->specifiedOutletPressurePa();
            h[QStringLiteral("flashPhaseMode")]            = mx->flashPhaseMode();
            u[QStringLiteral("mixerState")]                = h;
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
      else if (type == QStringLiteral("pump")) {
         addPumpInternal(x, y);
      }
      else if (type == QStringLiteral("valve")) {
         addValveInternal(x, y);
      }
      else if (type == QStringLiteral("heat_exchanger")) {
         addHeatExchangerInternal(x, y);
      }
      else if (type == QStringLiteral("separator")) {
         addSeparatorInternal(x, y);
      }
      else if (type == QStringLiteral("tee_splitter")) {
         addSplitterInternal(x, y);
      }
      else if (type == QStringLiteral("mixer")) {
         addMixerInternal(x, y);
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
         else if (type == QStringLiteral("pump")) {
            const QJsonObject ps = u[QStringLiteral("pumpState")].toObject();
            if (!ps.isEmpty()) {
               auto* pp = dynamic_cast<PumpUnitState*>(findUnitById(newId));
               if (pp) {
                  pp->setSpecMode(ps[QStringLiteral("specMode")].toString(QStringLiteral("deltaP")));
                  pp->setOutletPressurePa(ps[QStringLiteral("outletPressurePa")].toDouble(6.0e5));
                  pp->setDeltaPPa(ps[QStringLiteral("deltaPPa")].toDouble(5.0e5));
                  pp->setPowerKW(ps[QStringLiteral("powerKW")].toDouble(10.0));
                  pp->setAdiabaticEfficiency(ps[QStringLiteral("adiabaticEfficiency")].toDouble(0.75));
               }
            }
         }
         else if (type == QStringLiteral("valve")) {
            const QJsonObject vs = u[QStringLiteral("valveState")].toObject();
            if (!vs.isEmpty()) {
               auto* vv = dynamic_cast<ValveUnitState*>(findUnitById(newId));
               if (vv) {
                  vv->setSpecMode(vs[QStringLiteral("specMode")].toString(QStringLiteral("deltaP")));
                  vv->setOutletPressurePa(vs[QStringLiteral("outletPressurePa")].toDouble(1.0e5));
                  vv->setDeltaPPa(vs[QStringLiteral("deltaPPa")].toDouble(2.0e5));
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
         else if (type == QStringLiteral("separator")) {
            const QJsonObject ss = u[QStringLiteral("separatorState")].toObject();
            if (!ss.isEmpty()) {
               auto* sp = dynamic_cast<SeparatorUnitState*>(findUnitById(newId));
               if (sp) {
                  sp->setSpecMode(ss[QStringLiteral("specMode")].toString(QStringLiteral("adiabatic")));
                  sp->setVesselTemperatureK(ss[QStringLiteral("vesselTemperatureK")].toDouble(350.0));
                  sp->setDutyKW(ss[QStringLiteral("dutyKW")].toDouble(0.0));
                  sp->setPressureDropPa(ss[QStringLiteral("pressureDropPa")].toDouble(0.0));
               }
            }
         }
         else if (type == QStringLiteral("tee_splitter")) {
            const QJsonObject ts = u[QStringLiteral("splitterState")].toObject();
            if (!ts.isEmpty()) {
               auto* tee = dynamic_cast<SplitterUnitState*>(findUnitById(newId));
               if (tee) {
                  // Restore outletCount FIRST so the fraction array's
                  // length matches before we set the values. setOutletCount
                  // resizes the internal vectors and emits the dynamic-port
                  // observer signal — at this point no streams are bound
                  // yet (they're restored from materialConnections later),
                  // so the observer harmlessly walks an empty list.
                  tee->setOutletCount(ts[QStringLiteral("outletCount")].toInt(2));
                  tee->setPressureDropPa(ts[QStringLiteral("pressureDropPa")].toDouble(0.0));
                  const QJsonArray fracs = ts[QStringLiteral("outletFractions")].toArray();
                  for (int i = 0; i < fracs.size() && i < tee->outletCount(); ++i)
                     tee->setOutletFraction(i, fracs[i].toDouble());
               }
            }
         }
         else if (type == QStringLiteral("mixer")) {
            const QJsonObject ms = u[QStringLiteral("mixerState")].toObject();
            if (!ms.isEmpty()) {
               auto* mx = dynamic_cast<MixerUnitState*>(findUnitById(newId));
               if (mx) {
                  // Restore inletCount FIRST so port-bound stream restoration
                  // in Pass 2 sees the correct port count. Same rationale as
                  // splitter outletCount above.
                  mx->setInletCount(ms[QStringLiteral("inletCount")].toInt(2));
                  mx->setPressureMode(ms[QStringLiteral("pressureMode")].toString(QStringLiteral("lowestInlet")));
                  mx->setSpecifiedOutletPressurePa(ms[QStringLiteral("specifiedOutletPressurePa")].toDouble(101325.0));
                  mx->setFlashPhaseMode(ms[QStringLiteral("flashPhaseMode")].toString(QStringLiteral("vle")));
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
   //
   // Type-dispatch: examine the relevant endpoint's unit type (target side
   // for inlet-bound streams, source side for outlet-bound streams) and call
   // the matching bind* routine. This is more robust than dispatching on
   // port names — it correctly handles separator, splitter, and mixer ports
   // that the older name-pattern dispatcher ignored.
   //
   // Note: a single connection has either a target (inlet binding) or a
   // source (outlet binding) populated, not both — bind* routines erase the
   // other side as part of their normal stream-displacement semantics.
   const QJsonArray conns = root[QStringLiteral("connections")].toArray();
   for (const QJsonValue& cv : conns) {
      const QJsonObject co = cv.toObject();
      const QString streamId   = co[QStringLiteral("streamUnitId")].toString();
      const QString sourceId   = co[QStringLiteral("sourceUnitId")].toString();
      const QString sourcePort = co[QStringLiteral("sourcePort")].toString();
      const QString targetId   = co[QStringLiteral("targetUnitId")].toString();
      const QString targetPort = co[QStringLiteral("targetPort")].toString();

      if (!targetId.isEmpty()) {
         const QString ttype = unitType(targetId);
         if (ttype == QStringLiteral("column")) {
            // Column has a single inlet port "feed".
            bindColumnFeedStream(targetId, streamId);
         } else if (ttype == QStringLiteral("heater") || ttype == QStringLiteral("cooler")) {
            bindHeaterFeedStream(targetId, streamId);
         } else if (ttype == QStringLiteral("pump")) {
            bindPumpFeedStream(targetId, streamId);
         } else if (ttype == QStringLiteral("valve")) {
            bindValveFeedStream(targetId, streamId);
         } else if (ttype == QStringLiteral("heat_exchanger")) {
            // Port is "hotIn" or "coldIn".
            bindHexStream(targetId, targetPort, streamId);
         } else if (ttype == QStringLiteral("separator")) {
            // Port is "feed".
            bindSeparatorStream(targetId, targetPort, streamId);
         } else if (ttype == QStringLiteral("tee_splitter")) {
            // Port is "feed".
            bindSplitterStream(targetId, targetPort, streamId);
         } else if (ttype == QStringLiteral("mixer")) {
            // Port is "inletN".
            bindMixerStream(targetId, targetPort, streamId);
         }
      }
      else if (!sourceId.isEmpty()) {
         const QString stype = unitType(sourceId);
         if (stype == QStringLiteral("column")) {
            // Port is "distillate" or "bottoms".
            bindColumnProductStream(sourceId, sourcePort, streamId);
         } else if (stype == QStringLiteral("heater") || stype == QStringLiteral("cooler")) {
            bindHeaterProductStream(sourceId, streamId);
         } else if (stype == QStringLiteral("pump")) {
            bindPumpProductStream(sourceId, streamId);
         } else if (stype == QStringLiteral("valve")) {
            bindValveProductStream(sourceId, streamId);
         } else if (stype == QStringLiteral("heat_exchanger")) {
            // Port is "hotOut" or "coldOut".
            bindHexStream(sourceId, sourcePort, streamId);
         } else if (stype == QStringLiteral("separator")) {
            // Port is "vapor" or "liquid".
            bindSeparatorStream(sourceId, sourcePort, streamId);
         } else if (stype == QStringLiteral("tee_splitter")) {
            // Port is "outletN".
            bindSplitterStream(sourceId, sourcePort, streamId);
         } else if (stype == QStringLiteral("mixer")) {
            // Port is "product".
            bindMixerStream(sourceId, sourcePort, streamId);
         }
      }
   }

   setCurrentFilePath_(filePath);
   clearDirty_();
   lastSaveError_.clear();
   return true;
}