#include "ComponentManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <algorithm>
#include <cmath>

#include "components/models/ComponentListModel.h"
#include "components/models/CompGroupListModel.h"
#include "thermo/pseudocomponents/FluidDefinition.hpp"
#include "thermo/pseudocomponents/componentData.hpp"

namespace {
constexpr auto kPreferredSeedResourcePath = ":/qt/qml/ChatGPT5/ADT/cpp/components/data/hydrocarbon_starter_components.json";
}

ComponentManager* ComponentManager::instance_ = nullptr;

ComponentManager::ComponentManager(QObject* parent)
    : QObject(parent)
    , componentModel_(new ComponentListModel(this))
    , groupModel_(new CompGroupListModel(this))
{
    instance_ = this;
    componentModel_->setComponents(&components_);
    groupModel_->setLists(&componentLists_);
    if (!reloadSeedAndPseudoFluids_()) {
        emit errorOccurred(QStringLiteral("ComponentManager could not load the starter component seed."));
    }
}

ComponentManager::~ComponentManager()
{
    if (instance_ == this) instance_ = nullptr;
}

ComponentManager* ComponentManager::instance()
{
    return instance_;
}

QObject* ComponentManager::componentModel() const
{
    return componentModel_;
}

int ComponentManager::componentCount() const
{
    return static_cast<int>(components_.size());
}

int ComponentManager::binaryInteractionCount() const
{
    return static_cast<int>(binaryInteractions_.size());
}

QStringList ComponentManager::componentFamilies() const
{
    QSet<QString> seen;
    for (const auto& c : components_) {
        if (!c.family.trimmed().isEmpty()) seen.insert(c.family.trimmed());
    }
    QStringList out = seen.values();
    out.sort(Qt::CaseInsensitive);
    return out;
}

QStringList ComponentManager::pseudoFluidNames() const
{
    QStringList out;
    for (const auto& name : listFluidDefinitions()) {
        out.push_back(QString::fromStdString(name));
    }
    out.sort(Qt::CaseInsensitive);
    return out;
}

QStringList ComponentManager::availableFluidNames() const
{
    return pseudoFluidNames();
}

QString ComponentManager::seedResourcePath() const
{
    return QString::fromUtf8(kPreferredSeedResourcePath);
}

QString ComponentManager::lastLoadStatus() const
{
    return lastLoadStatus_;
}

FluidDefinition ComponentManager::buildFluidDefinition(const QString& fluidName) const
{
    FluidDefinition fluid = getFluidDefinition(fluidName.toStdString());
    const auto warehouseComps = componentsForPseudoFluid_(fluidName);
    if (warehouseComps.empty()) {
        return fluid;
    }

    std::vector<Component> merged;
    merged.reserve(warehouseComps.size());
    for (const auto& rec : warehouseComps) {
        Component c;
        c.name = rec.name.toStdString();
        c.Tb = rec.normalBoilingPointK.value_or(0.0);
        c.MW = rec.molarMass.value_or(0.0);
        c.Tc = rec.criticalTemperatureK.value_or(0.0);
        c.Pc = rec.criticalPressurePa.value_or(0.0);
        c.omega = rec.acentricFactor.value_or(0.0);
        c.SG = rec.specificGravity60F.value_or(0.0);
        c.delta = rec.volumeShiftDelta.value_or(0.0);
        merged.push_back(c);
    }

    fluid.thermo.components = std::move(merged);
    fluid.thermo.zDefault = defaultCompositionForFluid_(fluidName, fluid.thermo.components.size());
    fluid.thermo.hasZDefault = !fluid.thermo.zDefault.empty();

    const std::size_t n = fluid.thermo.components.size();
    if (fluid.thermo.kij.size() != n) {
        fluid.thermo.kij.assign(n, std::vector<double>(n, 0.0));
    } else {
        for (auto& row : fluid.thermo.kij) {
            if (row.size() != n) row.assign(n, 0.0);
        }
    }
    return fluid;
}

bool ComponentManager::resetToStarterSeed()
{
    return reloadSeedAndPseudoFluids_();
}



QStringList ComponentManager::seedResourceCandidates_() const
{
    return QStringList{
        seedResourcePath(),
        QStringLiteral(":/qt/qml/ChatGPT5/ADT/hydrocarbon_starter_components.json"),
        QStringLiteral(":/qt/qml/ChatGPT5/ADT/data/hydrocarbon_starter_components.json"),
        QStringLiteral(":/cpp/components/data/hydrocarbon_starter_components.json"),
        QStringLiteral(":/hydrocarbon_starter_components.json"),
        QStringLiteral("qrc:/qt/qml/ChatGPT5/ADT/cpp/components/data/hydrocarbon_starter_components.json"),
        QStringLiteral("qrc:/qt/qml/ChatGPT5/ADT/hydrocarbon_starter_components.json")
    };
}

QStringList ComponentManager::discoverSeedResourceCandidates_() const
{
    QStringList found;
    const QString targetName = QStringLiteral("hydrocarbon_starter_components.json");

    QDirIterator it(QStringLiteral(":/"), QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        if (QFileInfo(path).fileName().compare(targetName, Qt::CaseInsensitive) == 0) {
            found.push_back(path);
        }
    }

    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList diskCandidates{
        QDir(appDir).filePath(QStringLiteral("hydrocarbon_starter_components.json")),
        QDir(appDir).filePath(QStringLiteral("components/hydrocarbon_starter_components.json")),
        QDir(appDir).filePath(QStringLiteral("data/hydrocarbon_starter_components.json")),
        QDir(appDir).filePath(QStringLiteral("cpp/components/data/hydrocarbon_starter_components.json"))
    };
    for (const auto& candidate : diskCandidates) {
        if (QFileInfo::exists(candidate)) found.push_back(candidate);
    }

    found.removeDuplicates();
    return found;
}

bool ComponentManager::reloadSeedAndPseudoFluids_()
{
    QString loadedPath;
    bool loaded = false;
    QStringList attempted;

    QStringList candidates = seedResourceCandidates_();
    const QStringList discovered = discoverSeedResourceCandidates_();
    for (const auto& path : discovered) {
        if (!candidates.contains(path)) candidates.push_back(path);
    }

    for (const auto& candidate : candidates) {
        if (candidate.trimmed().isEmpty()) continue;
        attempted.push_back(candidate);
        QFile file(candidate);
        if (!file.exists()) continue;
        if (!file.open(QIODevice::ReadOnly)) continue;
        if (loadFromJsonBytes(file.readAll(), candidate)) {
            loaded = true;
            loadedPath = candidate;
            break;
        }
    }

    if (!loaded) {
        lastLoadStatus_ = QStringLiteral("Starter seed load failed. Tried: %1").arg(attempted.join(QStringLiteral(" | ")));
        emit errorOccurred(lastLoadStatus_);
        return false;
    }

    int pseudoImported = 0;
    for (const auto& name : listFluidDefinitions()) {
        pseudoImported += importPseudoComponentFluid(QString::fromStdString(name), QStringLiteral("pseudo-fraction"), true);
    }

    ensureStarterComponentLists_(true);

    lastLoadStatus_ = QStringLiteral("Loaded starter seed from %1 and imported %2 pseudo-components from %3 fluids.")
            .arg(loadedPath)
            .arg(pseudoImported)
            .arg(listFluidDefinitions().size());
    emit componentsChanged();
    return true;
}

bool ComponentManager::loadFromJsonFile(const QString& absoluteOrRelativePath)
{
    QFile file(absoluteOrRelativePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit errorOccurred(QStringLiteral("Could not open component JSON file: %1").arg(absoluteOrRelativePath));
        return false;
    }
    return loadFromJsonBytes(file.readAll(), absoluteOrRelativePath);
}

bool ComponentManager::loadFromJsonResource(const QString& resourcePath)
{
    const QString actualPath = resourcePath.isEmpty() ? seedResourcePath() : resourcePath;
    QFile file(actualPath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit errorOccurred(QStringLiteral("Could not open component JSON resource: %1").arg(actualPath));
        return false;
    }
    return loadFromJsonBytes(file.readAll(), actualPath);
}

bool ComponentManager::saveToJsonFile(const QString& absoluteOrRelativePath) const
{
    QJsonObject root;
    root.insert(QStringLiteral("schemaVersion"), QStringLiteral("1.0"));
    root.insert(QStringLiteral("warehouseName"), QStringLiteral("AI Process Simulator Component Warehouse"));

    QJsonArray componentsArr;
    for (const auto& c : components_) componentsArr.append(c.toJson());
    root.insert(QStringLiteral("components"), componentsArr);

    QJsonArray binaryArr;
    for (const auto& bi : binaryInteractions_) binaryArr.append(bi.toJson());
    root.insert(QStringLiteral("binaryInteractions"), binaryArr);

    QJsonArray listArr;
    for (const auto& list : componentLists_) listArr.append(list.toJson());
    root.insert(QStringLiteral("componentLists"), listArr);

    QFile file(absoluteOrRelativePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return true;
}

QVariantMap ComponentManager::getComponent(const QString& componentId) const
{
    const int idx = indexOfComponentId_(componentId);
    if (idx < 0) return {};
    return components_[static_cast<std::size_t>(idx)].toVariantMap();
}

QVariantList ComponentManager::findComponents(const QString& text,
                                              const QString& family,
                                              bool includePseudoComponents) const
{
    const QString q = text.trimmed().toLower();
    const QString familyNorm = family.trimmed().toLower();
    QVariantList out;

    for (const auto& c : components_) {
        if (!includePseudoComponents && !c.isPseudoComponent()) {
            ;
        }
        if (!includePseudoComponents && c.isPseudoComponent()) continue;
        if (!familyNorm.isEmpty() && c.family.trimmed().toLower() != familyNorm) continue;

        bool match = q.isEmpty();
        if (!match) {
            const QString haystack = (c.id + QLatin1Char(' ') + c.name + QLatin1Char(' ') + c.formula + QLatin1Char(' ') + c.cas + QLatin1Char(' ') + c.family + QLatin1Char(' ') + c.tags.join(QLatin1Char(' '))).toLower();
            match = haystack.contains(q);
            if (!match) {
                for (const auto& alias : c.aliases) {
                    if (alias.toLower().contains(q)) { match = true; break; }
                }
            }
        }
        if (match) out.push_back(c.toVariantMap());
    }
    return out;
}

bool ComponentManager::containsComponent(const QString& componentId) const
{
    return indexOfComponentId_(componentId) >= 0;
}

bool ComponentManager::addOrUpdateComponent(const QVariantMap& componentMap)
{
    sim::ComponentRecord rec = sim::ComponentRecord::fromVariantMap(componentMap);
    if (rec.id.trimmed().isEmpty()) {
        rec.id = normalizeId_(rec.name);
    } else {
        rec.id = normalizeId_(rec.id);
    }
    if (rec.name.trimmed().isEmpty()) rec.name = rec.id;

    const int idx = indexOfComponentId_(rec.id);
    if (idx >= 0) components_[static_cast<std::size_t>(idx)] = std::move(rec);
    else components_.push_back(std::move(rec));
    syncModel_();
    return true;
}

bool ComponentManager::removeComponent(const QString& componentId)
{
    const int idx = indexOfComponentId_(componentId);
    if (idx < 0) return false;
    components_.erase(components_.begin() + idx);
    syncModel_();
    return true;
}

int ComponentManager::importPseudoComponentFluid(const QString& fluidName,
                                                 const QString& family,
                                                 bool replaceExisting)
{
    if (fluidName.trimmed().isEmpty()) return 0;
    const auto def = getFluidDefinition(fluidName.toStdString());
    int imported = 0;

    for (const auto& c : def.thermo.components) {
        auto rec = sim::ComponentRecord::fromPseudoComponent(c, fluidName, family);
        if (rec.id.isEmpty()) continue;
        const int idx = indexOfComponentId_(rec.id);
        if (idx >= 0) {
            if (replaceExisting) {
                components_[static_cast<std::size_t>(idx)] = std::move(rec);
                ++imported;
            }
        } else {
            components_.push_back(std::move(rec));
            ++imported;
        }
    }

    if (imported > 0) syncModel_();
    return imported;
}

bool ComponentManager::updatePseudoComponentProperty(const QString& fluidName,
                                                     const QString& componentName,
                                                     const QString& field,
                                                     double value)
{
    if (!std::isfinite(value)) return false;

    const QString sourceKey = QStringLiteral("pseudo-fluid:%1").arg(fluidName.trimmed());
    const QString nameKey = componentName.trimmed().toLower();
    const QString fieldKey = field.trimmed().toLower();

    for (auto& rec : components_) {
        if (rec.source.compare(sourceKey, Qt::CaseInsensitive) != 0) continue;
        if (rec.name.trimmed().toLower() != nameKey && rec.id.trimmed().toLower() != nameKey) continue;

        bool changed = false;
        auto setOpt = [&](std::optional<double>& target) {
            if (target.has_value() && qFuzzyCompare(1.0 + *target, 1.0 + value)) return;
            target = value;
            changed = true;
        };

        if (fieldKey == QStringLiteral("tb") || fieldKey == QStringLiteral("boilingpointk")) setOpt(rec.normalBoilingPointK);
        else if (fieldKey == QStringLiteral("mw") || fieldKey == QStringLiteral("molecularweight")) setOpt(rec.molarMass);
        else if (fieldKey == QStringLiteral("tc") || fieldKey == QStringLiteral("criticaltemperaturek")) setOpt(rec.criticalTemperatureK);
        else if (fieldKey == QStringLiteral("pc") || fieldKey == QStringLiteral("criticalpressure")) setOpt(rec.criticalPressurePa);
        else if (fieldKey == QStringLiteral("omega")) setOpt(rec.acentricFactor);
        else if (fieldKey == QStringLiteral("sg") || fieldKey == QStringLiteral("specificgravity")) setOpt(rec.specificGravity60F);
        else if (fieldKey == QStringLiteral("delta")) setOpt(rec.volumeShiftDelta);
        else return false;

        if (changed) syncModel_();
        return changed;
    }
    return false;
}

void ComponentManager::clear()
{
    components_.clear();
    binaryInteractions_.clear();
    componentLists_.clear();
    syncModel_();
    syncGroupModel_();
    emit componentListsChanged();
}

bool ComponentManager::loadFromJsonBytes(const QByteArray& jsonBytes, const QString& sourceLabel)
{
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(jsonBytes, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        emit errorOccurred(QStringLiteral("Component JSON parse error in %1: %2").arg(sourceLabel, error.errorString()));
        return false;
    }

    const auto root = doc.object();
    std::vector<sim::ComponentRecord> loadedComponents;
    std::vector<sim::BinaryInteractionRecord> loadedBinary;
    std::vector<sim::ComponentListRecord> loadedLists;

    for (const auto& v : root.value(QStringLiteral("components")).toArray()) {
        if (!v.isObject()) continue;
        auto rec = sim::ComponentRecord::fromJson(v.toObject());
        if (rec.id.trimmed().isEmpty()) rec.id = normalizeId_(rec.name);
        else rec.id = normalizeId_(rec.id);
        if (!rec.id.trimmed().isEmpty()) loadedComponents.push_back(std::move(rec));
    }

    for (const auto& v : root.value(QStringLiteral("binaryInteractions")).toArray()) {
        if (!v.isObject()) continue;
        loadedBinary.push_back(sim::BinaryInteractionRecord::fromJson(v.toObject()));
    }

    for (const auto& v : root.value(QStringLiteral("componentLists")).toArray()) {
        if (!v.isObject()) continue;
        auto rec = sim::ComponentListRecord::fromJson(v.toObject());
        if (rec.id.trimmed().isEmpty()) rec.id = normalizeListId_(rec.name);
        if (rec.name.trimmed().isEmpty()) rec.name = rec.id;
        if (!rec.id.trimmed().isEmpty()) loadedLists.push_back(std::move(rec));
    }

    components_ = std::move(loadedComponents);
    binaryInteractions_ = std::move(loadedBinary);
    componentLists_ = std::move(loadedLists);
    syncModel_();
    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

std::vector<sim::ComponentRecord> ComponentManager::componentsForPseudoFluid_(const QString& fluidName) const
{
    const QString sourceKey = QStringLiteral("pseudo-fluid:%1").arg(fluidName.trimmed());
    std::vector<sim::ComponentRecord> matching;
    for (const auto& rec : components_) {
        if (rec.source.compare(sourceKey, Qt::CaseInsensitive) == 0) {
            matching.push_back(rec);
        }
    }
    if (matching.empty()) return matching;

    const auto legacy = getFluidDefinition(fluidName.toStdString());
    std::vector<sim::ComponentRecord> ordered;
    ordered.reserve(matching.size());
    std::vector<bool> used(matching.size(), false);

    auto normalizedName = [](QString s) {
        s = s.trimmed().toLower();
        s.replace(' ', '-');
        return s;
    };

    for (const auto& comp : legacy.thermo.components) {
        const QString legacyName = normalizedName(QString::fromStdString(comp.name));
        for (std::size_t i = 0; i < matching.size(); ++i) {
            if (used[i]) continue;
            if (normalizedName(matching[i].name) == legacyName || normalizedName(matching[i].id) == legacyName) {
                ordered.push_back(matching[i]);
                used[i] = true;
                break;
            }
        }
    }

    for (std::size_t i = 0; i < matching.size(); ++i) {
        if (!used[i]) ordered.push_back(matching[i]);
    }
    return ordered;
}

std::vector<double> ComponentManager::defaultCompositionForFluid_(const QString& fluidName, std::size_t n)
{
    const auto all = crudeCompositions();
    auto it = all.find(fluidName.toStdString());
    if (it != all.end() && it->second.size() == n) return it->second;

    if (n == 0) return {};
    return std::vector<double>(n, 1.0 / static_cast<double>(n));
}

void ComponentManager::syncModel_()
{
    componentModel_->refresh();
    emit componentsChanged();
}

int ComponentManager::indexOfComponentId_(const QString& componentId) const
{
    const QString key = normalizeId_(componentId);
    for (int i = 0; i < static_cast<int>(components_.size()); ++i) {
        if (components_[static_cast<std::size_t>(i)].id == key) return i;
    }
    return -1;
}

QString ComponentManager::normalizeId_(QString id)
{
    id = id.trimmed().toLower();
    id.replace(' ', '-');
    return id;
}


QObject* ComponentManager::componentListModel() const
{
    return groupModel_;
}

int ComponentManager::componentListCount() const
{
    return static_cast<int>(componentLists_.size());
}

QStringList ComponentManager::componentListNames() const
{
    QStringList names;
    for (const auto& r : componentLists_)
        names.append(r.name);
    return names;
}

QVariantMap ComponentManager::getComponentList(const QString& listId) const
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return {};
    return componentLists_[static_cast<std::size_t>(idx)].toVariantMap();
}

QVariantList ComponentManager::listComponentLists() const
{
    QVariantList out;
    for (const auto& r : componentLists_)
        out.append(r.toVariantMap());
    return out;
}

bool ComponentManager::createComponentList(const QString& name)
{
    if (name.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Component list name cannot be empty."));
        return false;
    }

    const QString normalizedId = normalizeListId_(name);
    if (normalizedId.isEmpty()) {
        emit errorOccurred(QStringLiteral("Component list name is invalid."));
        return false;
    }
    if (indexOfListId_(normalizedId) >= 0) {
        emit errorOccurred(QStringLiteral("A component list with that name already exists."));
        return false;
    }

    sim::ComponentListRecord rec;
    rec.id = normalizedId;
    rec.name = name.trimmed();
    rec.source = QStringLiteral("user");
    componentLists_.push_back(std::move(rec));
    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

bool ComponentManager::addOrUpdateComponentList(const QVariantMap& listMap)
{
    sim::ComponentListRecord rec = sim::ComponentListRecord::fromVariantMap(listMap);
    if (rec.id.trimmed().isEmpty()) rec.id = normalizeListId_(rec.name);
    if (rec.name.trimmed().isEmpty()) rec.name = rec.id;
    if (rec.source.trimmed().isEmpty()) rec.source = QStringLiteral("user");
    if (rec.id.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Component list must have an id or name."));
        return false;
    }

    QStringList filteredIds;
    for (const auto& cid : rec.componentIds) {
        if (!containsComponent(cid)) continue;
        if (!filteredIds.contains(cid)) filteredIds.push_back(cid);
    }
    rec.componentIds = filteredIds;

    const int idx = indexOfListId_(rec.id);
    if (idx >= 0) componentLists_[static_cast<std::size_t>(idx)] = std::move(rec);
    else componentLists_.push_back(std::move(rec));

    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

bool ComponentManager::removeComponentList(const QString& listId)
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return false;
    componentLists_.erase(componentLists_.begin() + idx);
    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

bool ComponentManager::addComponentToList(const QString& listId, const QString& componentId)
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) {
        emit errorOccurred(QStringLiteral("Component list not found: %1").arg(listId));
        return false;
    }
    if (!containsComponent(componentId)) {
        emit errorOccurred(QStringLiteral("Component not found: %1").arg(componentId));
        return false;
    }

    auto& rec = componentLists_[static_cast<std::size_t>(idx)];
    if (rec.componentIds.contains(componentId)) return true;
    rec.componentIds.append(componentId);
    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

bool ComponentManager::removeComponentFromList(const QString& listId, const QString& componentId)
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return false;
    auto& rec = componentLists_[static_cast<std::size_t>(idx)];
    const int removed = rec.componentIds.removeAll(componentId);
    if (removed > 0) {
        syncGroupModel_();
        emit componentListsChanged();
    }
    return removed > 0;
}

bool ComponentManager::renameComponentList(const QString& listId, const QString& newName)
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return false;

    const QString trimmed = newName.trimmed();
    if (trimmed.isEmpty()) {
        emit errorOccurred(QStringLiteral("Component list name cannot be empty."));
        return false;
    }

    const QString newId = normalizeListId_(trimmed);
    if (newId.isEmpty()) return false;
    const int existingIdx = indexOfListId_(newId);
    if (existingIdx >= 0 && existingIdx != idx) {
        emit errorOccurred(QStringLiteral("A component list with that name already exists."));
        return false;
    }

    auto& rec = componentLists_[static_cast<std::size_t>(idx)];
    rec.id = newId;
    rec.name = trimmed;
    if (rec.source.trimmed().isEmpty()) rec.source = QStringLiteral("user");
    syncGroupModel_();
    emit componentListsChanged();
    return true;
}

QStringList ComponentManager::resolvedComponentIdsForList(const QString& listId) const
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return {};
    return componentLists_[static_cast<std::size_t>(idx)].componentIds;
}

QVariantList ComponentManager::resolvedComponentsForList(const QString& listId) const
{
    const int idx = indexOfListId_(listId);
    if (idx < 0) return {};
    QVariantList out;
    for (const auto& cid : componentLists_[static_cast<std::size_t>(idx)].componentIds) {
        const QVariantMap comp = getComponent(cid);
        if (!comp.isEmpty()) out.push_back(comp);
    }
    return out;
}

void ComponentManager::syncGroupModel_()
{
    if (groupModel_) groupModel_->refresh();
}

int ComponentManager::indexOfListId_(const QString& listId) const
{
    const QString key = normalizeListId_(listId);
    for (int i = 0; i < static_cast<int>(componentLists_.size()); ++i) {
        if (componentLists_[static_cast<std::size_t>(i)].id.compare(key, Qt::CaseInsensitive) == 0)
            return i;
    }
    return -1;
}

QString ComponentManager::normalizeListId_(QString name)
{
    name = name.trimmed().toLower();
    name.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    name.replace(QRegularExpression(QStringLiteral("(^-+|-+$)")), QString());
    return name;
}

void ComponentManager::ensureStarterComponentLists_(bool replaceStarterLists)
{
    if (replaceStarterLists) {
        componentLists_.erase(std::remove_if(componentLists_.begin(), componentLists_.end(), [](const auto& rec) {
            return rec.source.compare(QStringLiteral("starter"), Qt::CaseInsensitive) == 0;
        }), componentLists_.end());
    }

    for (const auto& fluidStd : listFluidDefinitions()) {
        const QString fluidName = QString::fromStdString(fluidStd);
        const auto comps = componentsForPseudoFluid_(fluidName);
        if (comps.empty()) continue;

        sim::ComponentListRecord rec;
        rec.id = normalizeListId_(fluidName);
        rec.name = fluidName;
        rec.notes = QStringLiteral("Starter pseudo-component list for %1.").arg(fluidName);
        rec.source = QStringLiteral("starter");
        for (const auto& comp : comps) {
            if (!comp.id.trimmed().isEmpty() && !rec.componentIds.contains(comp.id))
                rec.componentIds.push_back(comp.id);
        }
        if (rec.componentIds.isEmpty()) continue;

        const int idx = indexOfListId_(rec.id);
        if (idx >= 0) {
            if (componentLists_[static_cast<std::size_t>(idx)].source.compare(QStringLiteral("starter"), Qt::CaseInsensitive) == 0)
                componentLists_[static_cast<std::size_t>(idx)] = rec;
        } else {
            componentLists_.push_back(std::move(rec));
        }
    }

    std::sort(componentLists_.begin(), componentLists_.end(), [](const auto& a, const auto& b) {
        return a.name.toLower() < b.name.toLower();
    });
    syncGroupModel_();
    emit componentListsChanged();
}
