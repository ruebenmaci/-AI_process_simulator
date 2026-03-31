#include "flowsheet/state/FlowsheetState.h"
#include "unitops/column/state/ColumnUnitState.h"
#include "streams/state/StreamUnitState.h"

#include <memory>
#include <QVariantMap>
#include <QRegularExpression>
#include <QStringList>
#include <QSet>

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
    if (base.isEmpty())
        base = type == QStringLiteral("column") ? QStringLiteral("column") : QStringLiteral("stream");

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
            } else if (!connection.sourceUnitId.isEmpty()) {
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
    node.displayName = makeUniqueUnitName_(id, QStringLiteral("column"));
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
        }
    });
    units_.push_back(std::move(stream));

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

    removeConnectionsForStream_(streamUnitId);
    if (auto existing = findConnectionForTarget_(columnUnitId, QStringLiteral("feed"))) {
        const QString previousStreamUnitId = existing->streamUnitId;
        removeConnectionsForStream_(previousStreamUnitId);
        relabelStreamFromBindings_(previousStreamUnitId);
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

    removeConnectionsForStream_(streamUnitId);
    if (auto existing = findConnectionForSource_(columnUnitId, normalizedPort)) {
        const QString previousStreamUnitId = existing->streamUnitId;
        removeConnectionsForStream_(previousStreamUnitId);
        relabelStreamFromBindings_(previousStreamUnitId);
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
        emit materialConnectionsChanged();
        setLastOperationMessage_(QString{});
    } else {
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
        }
        if (!it->sourceUnitId.isEmpty()) {
            if (auto* column = dynamic_cast<ColumnUnitState*>(findUnitById(it->sourceUnitId)))
                column->setConnectedProductStreamUnitId(it->sourcePort, QString{});
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
