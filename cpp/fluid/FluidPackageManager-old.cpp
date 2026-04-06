#include "FluidPackageManager.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>

#include "components/ComponentManager.h"
#include "fluid/models/FluidPackageListModel.h"

FluidPackageManager::FluidPackageManager(QObject* parent)
    : QObject(parent)
    , model_(new FluidPackageListModel(this))
{
    model_->setPackages(&packages_);
    auto* cm = ComponentManager::instance();
    if (cm) {
        QObject::connect(cm, &ComponentManager::componentListsChanged, this, [this]() {
            if (packages_.empty()) {
                createStarterPackages();
            } else if (model_) {
                model_->refresh();
                emit fluidPackagesChanged();
            }
        });
    }
    createStarterPackages();
}

QObject* FluidPackageManager::fluidPackageModel() const { return model_; }

int FluidPackageManager::fluidPackageCount() const
{
    return static_cast<int>(packages_.size());
}

QStringList FluidPackageManager::propertyMethods() const
{
    return {
        QStringLiteral("Peng-Robinson"),
        QStringLiteral("PRSV"),
        QStringLiteral("SRK"),
        QStringLiteral("Ideal"),
        QStringLiteral("Raoult's Law")
    };
}

QString FluidPackageManager::defaultFluidPackageId() const
{
    for (const auto& p : packages_)
        if (p.isDefault) return p.id;
    return {};
}

QString FluidPackageManager::lastStatus() const { return lastStatus_; }

QVariantMap FluidPackageManager::getFluidPackage(const QString& packageId) const
{
    const int idx = indexOfPackageId_(packageId);
    return idx >= 0 ? packages_[static_cast<std::size_t>(idx)].toVariantMap() : QVariantMap{};
}

QVariantList FluidPackageManager::listFluidPackages() const
{
    QVariantList out;
    for (const auto& p : packages_) out.push_back(p.toVariantMap());
    return out;
}

void FluidPackageManager::normalizeRecord_(sim::FluidPackageRecord& rec) const
{
    rec.id = normalizeId_(rec.id.isEmpty() ? rec.name : rec.id);
    if (rec.name.trimmed().isEmpty())          rec.name = rec.id;
    if (rec.propertyMethod.trimmed().isEmpty()) rec.propertyMethod = QStringLiteral("Peng-Robinson");
    if (rec.source.trimmed().isEmpty())         rec.source = QStringLiteral("user");
}

bool FluidPackageManager::addOrUpdateFluidPackage(const QVariantMap& packageMap)
{
    sim::FluidPackageRecord rec = sim::FluidPackageRecord::fromVariantMap(packageMap);
    normalizeRecord_(rec);

    const int idx = indexOfPackageId_(rec.id);
    if (idx >= 0) packages_[static_cast<std::size_t>(idx)] = rec;
    else          packages_.push_back(rec);

    if (rec.isDefault) setDefaultFluidPackage(rec.id);
    else syncModel_();

    lastStatus_ = QStringLiteral("Saved fluid package: %1").arg(rec.name);
    emit fluidPackagesChanged();
    return true;
}

bool FluidPackageManager::removeFluidPackage(const QString& packageId)
{
    const int idx = indexOfPackageId_(packageId);
    if (idx < 0) return false;
    const bool wasDefault = packages_[static_cast<std::size_t>(idx)].isDefault;
    packages_.erase(packages_.begin() + idx);
    if (wasDefault && !packages_.empty()) packages_.front().isDefault = true;
    syncModel_();
    lastStatus_ = QStringLiteral("Deleted fluid package: %1").arg(packageId);
    emit fluidPackagesChanged();
    return true;
}

bool FluidPackageManager::setDefaultFluidPackage(const QString& packageId)
{
    bool found = false;
    for (auto& pkg : packages_) {
        pkg.isDefault = (pkg.id.compare(packageId, Qt::CaseInsensitive) == 0);
        if (pkg.isDefault) found = true;
    }
    if (!found) return false;
    syncModel_();
    lastStatus_ = QStringLiteral("Default fluid package set to: %1").arg(packageId);
    emit fluidPackagesChanged();
    return true;
}

bool FluidPackageManager::createStarterPackages()
{
    packages_.clear();

    // Create one starter fluid package per starter Component List.
    auto* cm = ComponentManager::instance();
    if (cm && cm->componentListCount() > 0) {
        const QVariantList lists = cm->listComponentLists();
        bool first = true;
        for (const auto& v : lists) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("source")).toString().compare(QStringLiteral("starter"), Qt::CaseInsensitive) != 0)
                continue;
            sim::FluidPackageRecord pkg;
            const QString baseName = m.value(QStringLiteral("name")).toString();
            pkg.id              = normalizeId_(baseName + QStringLiteral(" package"));
            pkg.name            = baseName + QStringLiteral(" Package");
            pkg.componentListId = m.value(QStringLiteral("id")).toString();
            pkg.propertyMethod  = QStringLiteral("Peng-Robinson");
            pkg.source          = QStringLiteral("starter");
            pkg.tags            = { QStringLiteral("starter"), QStringLiteral("fluid-package") };
            pkg.isDefault       = first;
            first = false;
            packages_.push_back(pkg);
        }
    }
    if (packages_.empty()) {
        // No Component Lists yet — create a single empty placeholder package
        sim::FluidPackageRecord pkg;
        pkg.id             = QStringLiteral("default-package");
        pkg.name           = QStringLiteral("Default Package");
        pkg.componentListId = QString();
        pkg.propertyMethod = QStringLiteral("Peng-Robinson");
        pkg.source         = QStringLiteral("starter");
        pkg.tags           = { QStringLiteral("starter"), QStringLiteral("fluid-package") };
        pkg.isDefault      = true;
        packages_.push_back(pkg);
    }

    syncModel_();
    lastStatus_ = QStringLiteral("Created %1 starter fluid packages.").arg(packages_.size());
    emit fluidPackagesChanged();
    return true;
}

bool FluidPackageManager::saveToJsonFile(const QString& path) const
{
    QJsonObject root;
    QJsonArray arr;
    for (const auto& p : packages_) arr.append(p.toJson());
    root.insert(QStringLiteral("fluidPackages"), arr);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return true;
}

bool FluidPackageManager::loadFromJsonFile(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;
    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return false;
    packages_.clear();
    for (const auto& v : doc.object().value(QStringLiteral("fluidPackages")).toArray()) {
        if (!v.isObject()) continue;
        auto rec = sim::FluidPackageRecord::fromJson(v.toObject());
        normalizeRecord_(rec);
        packages_.push_back(rec);
    }
    if (!packages_.empty() &&
        std::none_of(packages_.begin(), packages_.end(), [](const auto& p){ return p.isDefault; }))
        packages_.front().isDefault = true;
    syncModel_();
    lastStatus_ = QStringLiteral("Loaded %1 fluid packages.").arg(packages_.size());
    emit fluidPackagesChanged();
    return true;
}

void FluidPackageManager::syncModel_()
{
    if (model_) model_->refresh();
}

int FluidPackageManager::indexOfPackageId_(const QString& packageId) const
{
    for (std::size_t i = 0; i < packages_.size(); ++i)
        if (packages_[i].id.compare(packageId, Qt::CaseInsensitive) == 0)
            return static_cast<int>(i);
    return -1;
}

QString FluidPackageManager::normalizeId_(QString id)
{
    id = id.trimmed().toLower();
    id.replace(' ', '-');
    id.replace('/', '-');
    id.replace('_', '-');
    return id;
}
