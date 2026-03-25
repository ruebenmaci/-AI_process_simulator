#include "FlowsheetUnitModel.h"

FlowsheetUnitModel::FlowsheetUnitModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int FlowsheetUnitModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return nodes_.size();
}

QVariant FlowsheetUnitModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= nodes_.size())
        return {};

    const UnitNode& node = nodes_.at(index.row());

    switch (role) {
    case UnitIdRole:      return node.unitId;
    case TypeRole:        return node.type;
    case NameRole:        return node.displayName;
    case DisplayNameRole: return node.displayName;
    case XRole:           return node.x;
    case YRole:           return node.y;
    default:              return {};
    }
}

QHash<int, QByteArray> FlowsheetUnitModel::roleNames() const
{
    return {
        { UnitIdRole, "unitId" },
        { TypeRole, "type" },
        { NameRole, "name" },
        { DisplayNameRole, "displayName" },
        { XRole, "x" },
        { YRole, "y" }
    };
}

void FlowsheetUnitModel::setNodes(const QVector<UnitNode>& nodes)
{
    beginResetModel();
    nodes_ = nodes;
    endResetModel();
}


void FlowsheetUnitModel::updateName(const QString& unitId, const QString& name)
{
    for (int row = 0; row < nodes_.size(); ++row) {
        if (nodes_[row].unitId != unitId)
            continue;
        if (nodes_[row].displayName == name)
            return;
        nodes_[row].displayName = name;
        const QModelIndex idx = index(row, 0);
        emit dataChanged(idx, idx, { NameRole, DisplayNameRole });
        return;
    }
}

void FlowsheetUnitModel::updatePosition(const QString& unitId, double x, double y)
{
    for (int row = 0; row < nodes_.size(); ++row) {
        if (nodes_[row].unitId != unitId)
            continue;
        if (nodes_[row].x == x && nodes_[row].y == y)
            return;
        nodes_[row].x = x;
        nodes_[row].y = y;
        const QModelIndex idx = index(row, 0);
        emit dataChanged(idx, idx, { XRole, YRole });
        return;
    }
}

void FlowsheetUnitModel::updateDisplayName(const QString& unitId, const QString& displayName)
{
    updateName(unitId, displayName);
}
