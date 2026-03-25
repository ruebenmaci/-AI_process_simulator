#pragma once

#include <QAbstractListModel>
#include <QVector>
#include "flowsheet/UnitNode.h"

class FlowsheetUnitModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        UnitIdRole = Qt::UserRole + 1,
        TypeRole,
        DisplayNameRole,
        XRole,
        YRole
    };
    Q_ENUM(Roles)

    explicit FlowsheetUnitModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;


    void setNodes(const QVector<UnitNode>& nodes);
    void updateDisplayName(const QString& unitId, const QString& displayName);
    void updatePosition(const QString& unitId, double x, double y);
    const QVector<UnitNode>& nodes() const { return nodes_; }

private:
    QVector<UnitNode> nodes_;
};
