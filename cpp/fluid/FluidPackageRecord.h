#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QJsonObject>

namespace sim {

struct FluidPackageRecord {
    QString id;
    QString name;
    QString componentListId;  // references a ComponentListRecord by id

    // Legacy UI/display label kept for compatibility with the current FluidManagerView.
    QString propertyMethod;

    // Phase 0 HYSYS-style ownership fields.
    QString thermoMethodId;
    QString phaseModelFamily;
    QStringList supportFlags;
    bool isCrudePackage = false;

    QString notes;
    QString source;
    QStringList tags;
    bool isDefault = false;

    QVariantMap  toVariantMap() const;
    QJsonObject  toJson()       const;

    static FluidPackageRecord fromVariantMap(const QVariantMap& map);
    static FluidPackageRecord fromJson(const QJsonObject& obj);
};

} // namespace sim
