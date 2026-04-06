#pragma once

#include <QAbstractListModel>
#include <vector>

#include "fluid/FluidPackageRecord.h"

class FluidPackageListModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        PropertyMethodRole,
        ThermoMethodIdRole,
        PhaseModelFamilyRole,
        ComponentListIdRole,
        IsCrudePackageRole,
        IsDefaultRole,
        SourceRole,
        NotesRole,
        TagsRole,
        RecordRole
    };
    Q_ENUM(Roles)

    explicit FluidPackageListModel(QObject* parent = nullptr);

    int      rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setPackages(const std::vector<sim::FluidPackageRecord>* packages);
    void refresh();

private:
    const std::vector<sim::FluidPackageRecord>* packages_ = nullptr;
};
