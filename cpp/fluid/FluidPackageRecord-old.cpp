#include "FluidPackageRecord.h"

#include <QJsonArray>

namespace sim {
namespace {
QJsonArray stringListToJsonArray(const QStringList& list)
{
    QJsonArray arr;
    for (const auto& s : list) arr.append(s);
    return arr;
}
QStringList jsonArrayToStringList(const QJsonValue& v)
{
    QStringList out;
    for (const auto& item : v.toArray()) out.push_back(item.toString());
    return out;
}
}

QVariantMap FluidPackageRecord::toVariantMap() const
{
    QVariantMap out;
    out.insert(QStringLiteral("id"),              id);
    out.insert(QStringLiteral("name"),            name);
    out.insert(QStringLiteral("componentListId"), componentListId);
    out.insert(QStringLiteral("propertyMethod"),  propertyMethod);
    out.insert(QStringLiteral("notes"),           notes);
    out.insert(QStringLiteral("source"),          source);
    out.insert(QStringLiteral("tags"),            tags);
    out.insert(QStringLiteral("isDefault"),       isDefault);
    return out;
}

QJsonObject FluidPackageRecord::toJson() const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("id"),              id);
    obj.insert(QStringLiteral("name"),            name);
    obj.insert(QStringLiteral("componentListId"), componentListId);
    obj.insert(QStringLiteral("propertyMethod"),  propertyMethod);
    obj.insert(QStringLiteral("notes"),           notes);
    obj.insert(QStringLiteral("source"),          source);
    obj.insert(QStringLiteral("tags"),            stringListToJsonArray(tags));
    obj.insert(QStringLiteral("isDefault"),       isDefault);
    return obj;
}

FluidPackageRecord FluidPackageRecord::fromVariantMap(const QVariantMap& map)
{
    FluidPackageRecord rec;
    rec.id              = map.value(QStringLiteral("id")).toString();
    rec.name            = map.value(QStringLiteral("name")).toString();
    rec.componentListId = map.value(QStringLiteral("componentListId")).toString();
    rec.propertyMethod  = map.value(QStringLiteral("propertyMethod")).toString();
    rec.notes           = map.value(QStringLiteral("notes")).toString();
    rec.source          = map.value(QStringLiteral("source")).toString();
    rec.tags            = map.value(QStringLiteral("tags")).toStringList();
    rec.isDefault       = map.value(QStringLiteral("isDefault")).toBool();
    return rec;
}

FluidPackageRecord FluidPackageRecord::fromJson(const QJsonObject& obj)
{
    FluidPackageRecord rec;
    rec.id              = obj.value(QStringLiteral("id")).toString();
    rec.name            = obj.value(QStringLiteral("name")).toString();
    rec.componentListId = obj.value(QStringLiteral("componentListId")).toString();
    rec.propertyMethod  = obj.value(QStringLiteral("propertyMethod")).toString();
    rec.notes           = obj.value(QStringLiteral("notes")).toString();
    rec.source          = obj.value(QStringLiteral("source")).toString();
    rec.tags            = jsonArrayToStringList(obj.value(QStringLiteral("tags")));
    rec.isDefault       = obj.value(QStringLiteral("isDefault")).toBool();
    return rec;
}

} // namespace sim
