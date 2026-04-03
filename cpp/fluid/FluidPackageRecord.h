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
    QString propertyMethod;
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
