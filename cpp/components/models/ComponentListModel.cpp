#include "ComponentListModel.h"

ComponentListModel::ComponentListModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int ComponentListModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid() || !components_) return 0;
    return static_cast<int>(components_->size());
}

QVariant ComponentListModel::data(const QModelIndex& index, int role) const
{
    if (!components_ || !index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(components_->size())) {
        return {};
    }

    const auto& c = (*components_)[static_cast<std::size_t>(index.row())];
    switch (role) {
    case IdRole: return c.id;
    case NameRole: return c.name;
    case FormulaRole: return c.formula;
    case CasRole: return c.cas;
    case FamilyRole: return c.family;
    case ComponentTypeRole: return sim::componentTypeToString(c.componentType);
    case IsPseudoComponentRole: return c.isPseudoComponent();
    case TagsRole: return c.tags;
    case PhaseCapabilitiesRole: return c.phaseCapabilities;
    case MolarMassRole: return c.molarMass ? QVariant(*c.molarMass) : QVariant();
    case NormalBoilingPointRole: return c.normalBoilingPointK ? QVariant(*c.normalBoilingPointK) : QVariant();
    case CriticalTemperatureRole: return c.criticalTemperatureK ? QVariant(*c.criticalTemperatureK) : QVariant();
    case CriticalPressureRole: return c.criticalPressurePa ? QVariant(*c.criticalPressurePa) : QVariant();
    case AcentricFactorRole: return c.acentricFactor ? QVariant(*c.acentricFactor) : QVariant();
    case SpecificGravityRole: return c.specificGravity60F ? QVariant(*c.specificGravity60F) : QVariant();
    case VolumeShiftDeltaRole: return c.volumeShiftDelta ? QVariant(*c.volumeShiftDelta) : QVariant();
    case SourceRole: return c.source;
    case NotesRole: return c.notes;
    case RecordRole: return c.toVariantMap();
    case Qt::DisplayRole: return c.name;
    default: return {};
    }
}

QHash<int, QByteArray> ComponentListModel::roleNames() const
{
    return {
        { IdRole, "id" },
        { NameRole, "name" },
        { FormulaRole, "formula" },
        { CasRole, "cas" },
        { FamilyRole, "family" },
        { ComponentTypeRole, "componentType" },
        { IsPseudoComponentRole, "isPseudoComponent" },
        { TagsRole, "tags" },
        { PhaseCapabilitiesRole, "phaseCapabilities" },
        { MolarMassRole, "molarMass" },
        { NormalBoilingPointRole, "normalBoilingPointK" },
        { CriticalTemperatureRole, "criticalTemperatureK" },
        { CriticalPressureRole, "criticalPressurePa" },
        { AcentricFactorRole, "acentricFactor" },
        { SpecificGravityRole, "specificGravity60F" },
        { VolumeShiftDeltaRole, "volumeShiftDelta" },
        { SourceRole, "source" },
        { NotesRole, "notes" },
        { RecordRole, "record" }
    };
}

void ComponentListModel::setComponents(const std::vector<sim::ComponentRecord>* components)
{
    beginResetModel();
    components_ = components;
    endResetModel();
}

void ComponentListModel::refresh()
{
    beginResetModel();
    endResetModel();
}
