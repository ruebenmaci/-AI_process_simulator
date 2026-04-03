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
    m["notes"]        = notes;
    m["source"]       = source;
    return m;
}

QJsonObject ComponentListRecord::toJson() const
{
    QJsonObject obj;
    obj["id"]           = id;
    obj["name"]         = name;
    obj["notes"]        = notes;
    obj["source"]       = source;

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
    r.notes  = m.value("notes").toString();
    r.source = m.value("source", "user").toString();

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
    r.notes  = obj["notes"].toString();
    r.source = obj.value("source").toString("user");

    const QJsonArray arr = obj["componentIds"].toArray();
    for (const QJsonValue& v : arr)
        r.componentIds.append(v.toString());

    return r;
}

} // namespace sim
