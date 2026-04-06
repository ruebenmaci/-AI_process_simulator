#include "StreamCompositionModel.h"

#include "../state/MaterialStreamState.h"

#include <QString>

#include <algorithm>
#include <cmath>

StreamCompositionModel::StreamCompositionModel(MaterialStreamState* stream, QObject* parent)
    : QAbstractListModel(parent)
    , stream_(stream)
{
    if (stream_) {
        connect(stream_, &MaterialStreamState::selectedFluidChanged, this, &StreamCompositionModel::reloadModel_);
        connect(stream_, &MaterialStreamState::selectedFluidPackageChanged, this, &StreamCompositionModel::reloadModel_);
        connect(stream_, &MaterialStreamState::compositionChanged, this, &StreamCompositionModel::reloadModel_);
        connect(stream_, &MaterialStreamState::fluidDefinitionChanged, this, &StreamCompositionModel::reloadModel_);
        connect(stream_, &MaterialStreamState::componentEditingEnabledChanged, this, &StreamCompositionModel::reloadModel_);
    }
}

int StreamCompositionModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid() || !stream_) {
        return 0;
    }
    return static_cast<int>(stream_->fluidDefinition().thermo.components.size());
}

QVariant StreamCompositionModel::data(const QModelIndex& index, int role) const
{
    if (!stream_ || !index.isValid()) {
        return {};
    }

    const auto row = index.row();
    const auto& thermo = stream_->fluidDefinition().thermo;
    if (row < 0 || row >= static_cast<int>(thermo.components.size())) {
        return {};
    }

    const auto& comp = thermo.components[static_cast<std::size_t>(row)];
    const auto& z = stream_->compositionStd();
    const double frac = (row < static_cast<int>(z.size())) ? z[static_cast<std::size_t>(row)] : 0.0;

    double moleFrac = 0.0;
    double denom = 0.0;
    const auto n = std::min(thermo.components.size(), z.size());
    for (std::size_t i = 0; i < n; ++i) {
        const double wi = z[i];
        const double mw = thermo.components[i].MW;
        if (!(wi > 0.0) || !std::isfinite(mw) || mw <= 0.0)
            continue;
        denom += wi / mw;
    }
    if (denom > 0.0 && std::isfinite(comp.MW) && comp.MW > 0.0)
        moleFrac = (frac / comp.MW) / denom;

    switch (role) {
       case ComponentNameRole:
          return QString::fromStdString(comp.name);
       case FractionRole:
          return frac;
       case MoleFractionRole:
          return moleFrac;
       case BoilingPointKRole:
          return comp.Tb;
       case MolecularWeightRole:
          return comp.MW;
       case CriticalTemperatureKRole:
          return comp.Tc;
       case CriticalPressureRole:
          return comp.Pc;
       case OmegaRole:
          return comp.omega;
       case SpecificGravityRole:
          return comp.SG;
       case DeltaRole:
          return comp.delta;
       case EditableRole:
          return stream_->componentEditingEnabled();
       default: return {};
    }
}

bool StreamCompositionModel::setData(const QModelIndex& index, const QVariant& value, int role)
{
    if (!index.isValid()) {
        return false;
    }

    switch (role) {
       case FractionRole:
           return setFraction(index.row(), value.toDouble());
       case BoilingPointKRole:
           return setPropertyValue(index.row(), QStringLiteral("Tb"), value.toDouble());
       case MolecularWeightRole:
           return setPropertyValue(index.row(), QStringLiteral("MW"), value.toDouble());
       case CriticalTemperatureKRole:
           return setPropertyValue(index.row(), QStringLiteral("Tc"), value.toDouble());
       case CriticalPressureRole:
           return setPropertyValue(index.row(), QStringLiteral("Pc"), value.toDouble());
       case OmegaRole:
           return setPropertyValue(index.row(), QStringLiteral("omega"), value.toDouble());
       case SpecificGravityRole:
           return setPropertyValue(index.row(), QStringLiteral("SG"), value.toDouble());
       case DeltaRole:
           return setPropertyValue(index.row(), QStringLiteral("delta"), value.toDouble());
       default:
           return false;
    }
}

Qt::ItemFlags StreamCompositionModel::flags(const QModelIndex& index) const
{
    auto f = QAbstractListModel::flags(index);
    if (index.isValid() && stream_ && stream_->componentEditingEnabled()) {
        f |= Qt::ItemIsEditable;
    }
    return f;
}

QHash<int, QByteArray> StreamCompositionModel::roleNames() const
{
    return {
        { ComponentNameRole, "componentName" },
        { FractionRole, "fraction" },
        { MoleFractionRole, "moleFraction" },
        { BoilingPointKRole, "boilingPointK" },
        { MolecularWeightRole, "molecularWeight" },
        { CriticalTemperatureKRole, "criticalTemperatureK" },
        { CriticalPressureRole, "criticalPressure" },
        { OmegaRole, "omega" },
        { SpecificGravityRole, "specificGravity" },
        { DeltaRole, "delta" },
        { EditableRole, "editable" },
    };
}

QObject* StreamCompositionModel::streamObject() const
{
    return stream_;
}

bool StreamCompositionModel::setFraction(int row, double value)
{
    if (!stream_ || !stream_->componentEditingEnabled()) {
        return false;
    }
    auto z = stream_->compositionStd();
    if (row < 0 || row >= static_cast<int>(z.size())) {
        return false;
    }
    z[static_cast<std::size_t>(row)] = value;
    return stream_->setCompositionStd(z);
}

bool StreamCompositionModel::setPropertyValue(int row, const QString& field, double value)
{
    return stream_ && stream_->setComponentProperty(row, field, value);
}

void StreamCompositionModel::resetToDefault()
{
    if (stream_) {
        stream_->resetCompositionToFluidDefault();
        stream_->resetComponentPropertiesToFluidDefault();
    }
}

void StreamCompositionModel::normalizeFractions()
{
    if (stream_) {
        stream_->normalizeComposition();
    }
}

void StreamCompositionModel::reloadModel_()
{
    beginResetModel();
    endResetModel();
}
