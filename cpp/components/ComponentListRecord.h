#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QJsonObject>

namespace sim {

struct ComponentListRecord {
    QString     id;
    QString     name;
    QStringList componentIds;   // ordered list of component IDs
    QString     notes;
    QString     source;         // "user" | "starter"
    QString     listType;       // e.g. "pseudo-crude", "pure-component", "mixed"
    QString     sourceFluidName;

    QVariantMap  toVariantMap() const;
    QJsonObject  toJson()       const;

    static ComponentListRecord fromVariantMap(const QVariantMap& map);
    static ComponentListRecord fromJson(const QJsonObject& obj);
};

} // namespace sim
