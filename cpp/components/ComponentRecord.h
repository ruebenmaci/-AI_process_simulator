#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <optional>
#include <string>
#include <vector>

#include "thermo/pseudocomponents/componentData.hpp"

namespace sim {

enum class ComponentType {
    Pure,
    PseudoComponent,
    Ion,
    Salt,
    Solid,
    UserDefined
};

QString componentTypeToString(ComponentType type);
ComponentType componentTypeFromString(const QString& value);

struct ComponentRecord {
    QString id;
    QString name;
    QString formula;
    QString cas;
    QString family;
    ComponentType componentType = ComponentType::Pure;
    QStringList aliases;
    QStringList tags;
    QStringList phaseCapabilities;

    std::optional<double> molarMass;
    std::optional<double> normalBoilingPointK;
    std::optional<double> criticalTemperatureK;
    std::optional<double> criticalPressurePa;
    std::optional<double> acentricFactor;
    std::optional<double> criticalVolumeM3PerKmol;
    std::optional<double> criticalCompressibility;
    std::optional<double> specificGravity60F;
    std::optional<double> watsonK;
    std::optional<double> volumeShiftDelta;

    QString source;
    QString notes;

    bool isPseudoComponent() const { return componentType == ComponentType::PseudoComponent; }

    QVariantMap toVariantMap() const;
    QJsonObject toJson() const;

    static ComponentRecord fromVariantMap(const QVariantMap& map);
    static ComponentRecord fromJson(const QJsonObject& obj);
    static ComponentRecord fromPseudoComponent(const Component& c,
                                               const QString& sourceFluidName,
                                               const QString& inferredFamily = QStringLiteral("pseudo-fraction"));
};

struct BinaryInteractionRecord {
    QString method;
    QString componentA;
    QString componentB;
    QVariantMap parameters;
    QString source;
    QString notes;

    QVariantMap toVariantMap() const;
    QJsonObject toJson() const;

    static BinaryInteractionRecord fromVariantMap(const QVariantMap& map);
    static BinaryInteractionRecord fromJson(const QJsonObject& obj);
};

} // namespace sim
