#pragma once

#include <QAbstractListModel>
#include <vector>

#include "components/ComponentRecord.h"

class ComponentListModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        FormulaRole,
        CasRole,
        FamilyRole,
        ComponentTypeRole,
        IsPseudoComponentRole,
        TagsRole,
        PhaseCapabilitiesRole,
        MolarMassRole,
        NormalBoilingPointRole,
        CriticalTemperatureRole,
        CriticalPressureRole,
        AcentricFactorRole,
        SpecificGravityRole,
        VolumeShiftDeltaRole,
        SourceRole,
        NotesRole,
        RecordRole
    };
    Q_ENUM(Roles)

    explicit ComponentListModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setComponents(const std::vector<sim::ComponentRecord>* components);
    void refresh();

private:
    const std::vector<sim::ComponentRecord>* components_ = nullptr;
};
