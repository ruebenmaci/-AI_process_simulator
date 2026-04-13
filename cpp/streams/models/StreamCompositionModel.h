#pragma once

#include <QAbstractListModel>

class MaterialStreamState;

class StreamCompositionModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QObject* stream READ streamObject CONSTANT)

public:
    enum Roles {
        ComponentNameRole = Qt::UserRole + 1,
        FractionRole,
        MoleFractionRole,
        BoilingPointKRole,
        MolecularWeightRole,
        CriticalTemperatureKRole,
        CriticalPressureRole,
        OmegaRole,
        SpecificGravityRole,
        DeltaRole,
        EditableRole
    };
    Q_ENUM(Roles)

    explicit StreamCompositionModel(MaterialStreamState* stream, QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    bool setData(const QModelIndex& index, const QVariant& value, int role = Qt::EditRole) override;
    Qt::ItemFlags flags(const QModelIndex& index) const override;
    QHash<int, QByteArray> roleNames() const override;

    QObject* streamObject() const;

    Q_INVOKABLE bool setFraction(int row, double value);
    Q_INVOKABLE bool setMoleFraction(int row, double value);
    Q_INVOKABLE bool setPropertyValue(int row, const QString& field, double value);
    Q_INVOKABLE void resetToDefault();
    Q_INVOKABLE void normalizeFractions();
    Q_INVOKABLE void normalizeMoleFractions();
    Q_INVOKABLE int rowCountQml() const { return rowCount(); }

private:
    void reloadModel_();
    MaterialStreamState* stream_ = nullptr;
};
