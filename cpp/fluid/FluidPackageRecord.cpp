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
QString firstNonEmpty(const QString& a, const QString& b)
{
    return !a.trimmed().isEmpty() ? a : b;
}
}

QVariantMap FluidPackageRecord::toVariantMap() const
{
    QVariantMap out;
    out.insert(QStringLiteral("id"),               id);
    out.insert(QStringLiteral("name"),             name);
    out.insert(QStringLiteral("componentListId"),  componentListId);
    out.insert(QStringLiteral("propertyMethod"),   propertyMethod);
    out.insert(QStringLiteral("thermoMethodId"),   thermoMethodId);
    out.insert(QStringLiteral("phaseModelFamily"), phaseModelFamily);
    out.insert(QStringLiteral("supportFlags"),     supportFlags);
    out.insert(QStringLiteral("isCrudePackage"),   isCrudePackage);
    out.insert(QStringLiteral("notes"),            notes);
    out.insert(QStringLiteral("source"),           source);
    out.insert(QStringLiteral("tags"),             tags);
    out.insert(QStringLiteral("isDefault"),        isDefault);
    return out;
}

QJsonObject FluidPackageRecord::toJson() const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("id"),               id);
    obj.insert(QStringLiteral("name"),             name);
    obj.insert(QStringLiteral("componentListId"),  componentListId);
    obj.insert(QStringLiteral("propertyMethod"),   propertyMethod);
    obj.insert(QStringLiteral("thermoMethodId"),   thermoMethodId);
    obj.insert(QStringLiteral("phaseModelFamily"), phaseModelFamily);
    obj.insert(QStringLiteral("supportFlags"),     stringListToJsonArray(supportFlags));
    obj.insert(QStringLiteral("isCrudePackage"),   isCrudePackage);
    obj.insert(QStringLiteral("notes"),            notes);
    obj.insert(QStringLiteral("source"),           source);
    obj.insert(QStringLiteral("tags"),             stringListToJsonArray(tags));
    obj.insert(QStringLiteral("isDefault"),        isDefault);
    return obj;
}

FluidPackageRecord FluidPackageRecord::fromVariantMap(const QVariantMap& map)
{
    FluidPackageRecord rec;
    rec.id               = map.value(QStringLiteral("id")).toString();
    rec.name             = map.value(QStringLiteral("name")).toString();
    rec.componentListId  = map.value(QStringLiteral("componentListId")).toString();
    rec.propertyMethod   = map.value(QStringLiteral("propertyMethod")).toString();
    rec.thermoMethodId   = firstNonEmpty(map.value(QStringLiteral("thermoMethodId")).toString(),
                                         rec.propertyMethod);
    rec.phaseModelFamily = map.value(QStringLiteral("phaseModelFamily")).toString();
    rec.supportFlags     = map.value(QStringLiteral("supportFlags")).toStringList();
    rec.isCrudePackage   = map.value(QStringLiteral("isCrudePackage")).toBool();
    rec.notes            = map.value(QStringLiteral("notes")).toString();
    rec.source           = map.value(QStringLiteral("source")).toString();
    rec.tags             = map.value(QStringLiteral("tags")).toStringList();
    rec.isDefault        = map.value(QStringLiteral("isDefault")).toBool();
    if (rec.propertyMethod.trimmed().isEmpty())
        rec.propertyMethod = rec.thermoMethodId;
    return rec;
}

FluidPackageRecord FluidPackageRecord::fromJson(const QJsonObject& obj)
{
    FluidPackageRecord rec;
    rec.id               = obj.value(QStringLiteral("id")).toString();
    rec.name             = obj.value(QStringLiteral("name")).toString();
    rec.componentListId  = obj.value(QStringLiteral("componentListId")).toString();
    rec.propertyMethod   = obj.value(QStringLiteral("propertyMethod")).toString();
    rec.thermoMethodId   = firstNonEmpty(obj.value(QStringLiteral("thermoMethodId")).toString(),
                                         rec.propertyMethod);
    rec.phaseModelFamily = obj.value(QStringLiteral("phaseModelFamily")).toString();
    rec.supportFlags     = jsonArrayToStringList(obj.value(QStringLiteral("supportFlags")));
    rec.isCrudePackage   = obj.value(QStringLiteral("isCrudePackage")).toBool();
    rec.notes            = obj.value(QStringLiteral("notes")).toString();
    rec.source           = obj.value(QStringLiteral("source")).toString();
    rec.tags             = jsonArrayToStringList(obj.value(QStringLiteral("tags")));
    rec.isDefault        = obj.value(QStringLiteral("isDefault")).toBool();
    if (rec.propertyMethod.trimmed().isEmpty())
        rec.propertyMethod = rec.thermoMethodId;
    return rec;
}

} // namespace sim
