#include "ComponentManager.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <algorithm>
#include <cmath>

#include "components/models/ComponentListModel.h"
#include "thermo/pseudocomponents/FluidDefinition.hpp"
#include "thermo/pseudocomponents/componentData.hpp"

namespace {
constexpr auto kSeedResourcePath = ":/qt/qml/ChatGPT5/ADT/cpp/components/data/hydrocarbon_starter_components.json";
}

ComponentManager* ComponentManager::instance_ = nullptr;

ComponentManager::ComponentManager(QObject* parent)
    : QObject(parent)
    , componentModel_(new ComponentListModel(this))
{
    instance_ = this;
    componentModel_->setComponents(&components_);
    if (!resetToStarterSeed()) {
        emit errorOccurred(QStringLiteral("ComponentManager could not load the starter component seed."));
    }
    for (const auto& name : listFluidDefinitions()) {
        importPseudoComponentFluid(QString::fromStdString(name), QStringLiteral("pseudo-fraction"), true);
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
    return QString::fromUtf8(kSeedResourcePath);
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
    return loadFromJsonResource(seedResourcePath());
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
    syncModel_();
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

    components_ = std::move(loadedComponents);
    binaryInteractions_ = std::move(loadedBinary);
    syncModel_();
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
