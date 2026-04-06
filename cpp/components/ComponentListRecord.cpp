#include "components/ComponentListRecord.h"

#include <QJsonArray>

namespace sim {

// ── Serialise ────────────────────────────────────────────────────────────────

QVariantMap ComponentListRecord::toVariantMap() const
{
    QVariantMap m;
    m["id"]           = id;
    m["name"]         = name;
    m["componentIds"] = QVariant::fromValue(componentIds);
    m["notes"]          = notes;
    m["source"]         = source;
    m["listType"]       = listType;
    m["sourceFluidName"] = sourceFluidName;
    return m;
}

QJsonObject ComponentListRecord::toJson() const
{
    QJsonObject obj;
    obj["id"]           = id;
    obj["name"]         = name;
    obj["notes"]          = notes;
    obj["source"]         = source;
    obj["listType"]       = listType;
    obj["sourceFluidName"] = sourceFluidName;

    QJsonArray arr;
    for (const QString& cid : componentIds)
        arr.append(cid);
    obj["componentIds"] = arr;

    return obj;
}

// ── Deserialise ──────────────────────────────────────────────────────────────

ComponentListRecord ComponentListRecord::fromVariantMap(const QVariantMap& m)
{
    ComponentListRecord r;
    r.id     = m.value("id").toString();
    r.name   = m.value("name").toString();
    r.notes          = m.value("notes").toString();
    r.source         = m.value("source", "user").toString();
    r.listType       = m.value("listType").toString();
    r.sourceFluidName = m.value("sourceFluidName").toString();

    const QVariant ids = m.value("componentIds");
    if (ids.canConvert<QStringList>())
        r.componentIds = ids.value<QStringList>();
    else if (ids.canConvert<QVariantList>()) {
        const QVariantList vl = ids.value<QVariantList>();
        for (const QVariant& v : vl)
            r.componentIds.append(v.toString());
    }
    return r;
}

ComponentListRecord ComponentListRecord::fromJson(const QJsonObject& obj)
{
    ComponentListRecord r;
    r.id     = obj["id"].toString();
    r.name   = obj["name"].toString();
    r.notes          = obj["notes"].toString();
    r.source         = obj.value("source").toString("user");
    r.listType       = obj.value("listType").toString();
    r.sourceFluidName = obj.value("sourceFluidName").toString();

    const QJsonArray arr = obj["componentIds"].toArray();
    for (const QJsonValue& v : arr)
        r.componentIds.append(v.toString());

    return r;
}

} // namespace sim
