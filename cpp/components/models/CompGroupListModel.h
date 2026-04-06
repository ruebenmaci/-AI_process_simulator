#pragma once

#include <QAbstractListModel>
#include <vector>

#include "components/ComponentListRecord.h"

class ComponentManager;

// Model that exposes the vector<ComponentListRecord> to QML.
// Registered as gComponentManager.componentListModel in QML.
class CompGroupListModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        IdRole   = Qt::UserRole + 1,
        NameRole,
        CountRole,   // number of componentIds
        NotesRole,
        SourceRole,
        ListTypeRole,
        SourceFluidNameRole,
        ResolvedCountRole,
        ValidRole,
        StatusTextRole,
        MissingCountRole,
        RecordRole   // full QVariantMap
    };
    Q_ENUM(Roles)

    explicit CompGroupListModel(QObject* parent = nullptr);

    int     rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setLists(const std::vector<sim::ComponentListRecord>* lists);
    void setManager(const ComponentManager* manager);
    void refresh();

private:
    const std::vector<sim::ComponentListRecord>* lists_ = nullptr;
    const ComponentManager* manager_ = nullptr;
};
