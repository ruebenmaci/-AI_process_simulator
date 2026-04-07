#include "FluidPackageManager.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>

#include "components/ComponentManager.h"
#include "fluid/models/FluidPackageListModel.h"
#include "thermo/ThermoConfig.hpp"

FluidPackageManager* FluidPackageManager::instance_ = nullptr;

FluidPackageManager::FluidPackageManager(QObject* parent)
   : QObject(parent)
   , model_(new FluidPackageListModel(this))
{
   instance_ = this;
   model_->setPackages(&packages_);
   auto* cm = ComponentManager::instance();
   if (cm) {
      QObject::connect(cm, &ComponentManager::componentListsChanged, this, [this]() {
         if (packages_.empty()) {
            createStarterPackages();
         }
         else if (model_) {
            model_->refresh();
            emit fluidPackagesChanged();
         }
         });
   }
   createStarterPackages();
}

FluidPackageManager::~FluidPackageManager()
{
   if (instance_ == this) instance_ = nullptr;
}

FluidPackageManager* FluidPackageManager::instance()
{
   return instance_;
}

QObject* FluidPackageManager::fluidPackageModel() const { return model_; }

int FluidPackageManager::fluidPackageCount() const
{
   return static_cast<int>(packages_.size());
}

QStringList FluidPackageManager::propertyMethods() const
{
   return availableThermoMethods();
}

QStringList FluidPackageManager::availableThermoMethods() const
{
   return {
       QStringLiteral("PRSV"),
       QStringLiteral("PR"),
       QStringLiteral("SRK"),
       QStringLiteral("Ideal")
   };
}

QString FluidPackageManager::defaultFluidPackageId() const
{
   for (const auto& p : packages_)
      if (p.isDefault) return p.id;
   // Fallback: if no package is explicitly marked as default, use the first
   // available one. StreamUnitState relies on this returning a non-empty string
   // whenever at least one package exists.
   if (!packages_.empty())
      return packages_.front().id;
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
   if (rec.name.trimmed().isEmpty())            rec.name = rec.id;
   if (rec.thermoMethodId.trimmed().isEmpty())  rec.thermoMethodId = rec.propertyMethod.trimmed();
   if (rec.thermoMethodId.trimmed().isEmpty())  rec.thermoMethodId = QStringLiteral("PRSV");
   if (rec.propertyMethod.trimmed().isEmpty())  rec.propertyMethod = rec.thermoMethodId;
   if (rec.phaseModelFamily.trimmed().isEmpty()) rec.phaseModelFamily = QStringLiteral("EOS");
   if (rec.source.trimmed().isEmpty())          rec.source = QStringLiteral("user");
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
         pkg.id = normalizeId_(baseName + QStringLiteral(" package"));
         pkg.name = baseName + QStringLiteral(" Package");
         pkg.componentListId = m.value(QStringLiteral("id")).toString();
         pkg.propertyMethod = QStringLiteral("PRSV");
         pkg.thermoMethodId = pkg.propertyMethod;
         pkg.phaseModelFamily = QStringLiteral("EOS");
         pkg.source = QStringLiteral("starter");
         pkg.isCrudePackage = true;
         pkg.tags = { QStringLiteral("starter"), QStringLiteral("fluid-package") };
         pkg.supportFlags = { QStringLiteral("TP"), QStringLiteral("PH"), QStringLiteral("PS"), QStringLiteral("PVF"), QStringLiteral("TS") };
         pkg.isDefault = first;
         first = false;
         packages_.push_back(pkg);
      }
   }
   if (packages_.empty()) {
      sim::FluidPackageRecord pkg;
      pkg.id = QStringLiteral("default-package");
      pkg.name = QStringLiteral("Default Package");
      pkg.componentListId = QString();
      pkg.propertyMethod = QStringLiteral("PRSV");
      pkg.thermoMethodId = pkg.propertyMethod;
      pkg.phaseModelFamily = QStringLiteral("EOS");
      pkg.source = QStringLiteral("starter");
      pkg.tags = { QStringLiteral("starter"), QStringLiteral("fluid-package") };
      pkg.supportFlags = { QStringLiteral("TP"), QStringLiteral("PH"), QStringLiteral("PS"), QStringLiteral("PVF"), QStringLiteral("TS") };
      pkg.isDefault = true;
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
      std::none_of(packages_.begin(), packages_.end(), [](const auto& p) { return p.isDefault; }))
      packages_.front().isDefault = true;
   syncModel_();
   lastStatus_ = QStringLiteral("Loaded %1 fluid packages.").arg(packages_.size());
   emit fluidPackagesChanged();
   return true;
}

bool FluidPackageManager::packageExists(const QString& packageId) const
{
   return indexOfPackageId_(packageId) >= 0;
}

QString FluidPackageManager::fluidPackageName(const QString& packageId) const
{
   const int idx = indexOfPackageId_(packageId);
   return idx >= 0 ? packages_[static_cast<std::size_t>(idx)].name : QString{};
}

QString FluidPackageManager::thermoMethodIdForPackage(const QString& packageId) const
{
   const int idx = indexOfPackageId_(packageId);
   return idx >= 0 ? packages_[static_cast<std::size_t>(idx)].thermoMethodId : QString{};
}

QString FluidPackageManager::starterPackageIdForLegacyCrudeName(const QString& crudeName) const
{
   const QString target = crudeName.trimmed();
   if (target.isEmpty()) return QString{};

   const QString exactPackageName = target + QStringLiteral(" Package");
   for (const auto& pkg : packages_) {
      if (pkg.name.compare(exactPackageName, Qt::CaseInsensitive) == 0)
         return pkg.id;
      if (pkg.componentListId.compare(target, Qt::CaseInsensitive) == 0)
         return pkg.id;
   }
   return QString{};
}

thermo::ThermoConfig FluidPackageManager::thermoConfigForPackageResolved(const QString& packageId) const
{
   const int idx = indexOfPackageId_(packageId);
   if (idx < 0)
      return thermo::makeThermoConfig("PRSV");

   const auto& pkg = packages_[static_cast<std::size_t>(idx)];
   std::vector<std::string> supportFlags;
   supportFlags.reserve(pkg.supportFlags.size());
   for (const auto& flag : pkg.supportFlags) supportFlags.push_back(flag.toStdString());
   return thermo::makeThermoConfig(pkg.thermoMethodId.toStdString(), pkg.phaseModelFamily.toStdString(), supportFlags);
}

QVariantMap FluidPackageManager::thermoConfigForPackage(const QString& packageId) const
{
   QVariantMap out;
   const int idx = indexOfPackageId_(packageId);
   if (idx < 0) return out;

   const auto& pkg = packages_[static_cast<std::size_t>(idx)];
   const auto cfg = thermoConfigForPackageResolved(packageId);
   out.insert(QStringLiteral("thermoMethodId"), QString::fromStdString(cfg.thermoMethodId));
   out.insert(QStringLiteral("displayName"), QString::fromStdString(cfg.displayName));
   out.insert(QStringLiteral("eosName"), QString::fromStdString(cfg.eosName));
   out.insert(QStringLiteral("phaseModelFamily"), QString::fromStdString(cfg.phaseModelFamily));
   QStringList supportFlags;
   for (const auto& flag : cfg.supportFlags) supportFlags.push_back(QString::fromStdString(flag));
   out.insert(QStringLiteral("supportFlags"), supportFlags);
   out.insert(QStringLiteral("supportsEnthalpy"), cfg.supportsEnthalpy);
   out.insert(QStringLiteral("supportsEntropy"), cfg.supportsEntropy);
   out.insert(QStringLiteral("supportsTwoPhase"), cfg.supportsTwoPhase);
   out.insert(QStringLiteral("packageId"), pkg.id);
   out.insert(QStringLiteral("packageName"), pkg.name);
   out.insert(QStringLiteral("propertyMethod"), pkg.propertyMethod);
   out.insert(QStringLiteral("componentListId"), pkg.componentListId);
   out.insert(QStringLiteral("isCrudePackage"), pkg.isCrudePackage);
   return out;
}


QVariantMap FluidPackageManager::describeResolvedPackage(const QString& packageId) const
{
   QVariantMap out = thermoConfigForPackage(packageId);
   const int idx = indexOfPackageId_(packageId);
   if (idx < 0) return out;

   if (auto* cm = ComponentManager::instance()) {
      const auto& pkg = packages_[static_cast<std::size_t>(idx)];
      const QVariantMap listInfo = cm->describeComponentList(pkg.componentListId);
      for (auto it = listInfo.constBegin(); it != listInfo.constEnd(); ++it) {
         out.insert(it.key(), it.value());
      }
   }
   return out;
}

QVariantMap FluidPackageManager::packageEditorSummary(const QString& packageId) const
{
   QVariantMap out;
   const int idx = indexOfPackageId_(packageId);
   if (idx < 0) {
      out.insert(QStringLiteral("valid"), false);
      out.insert(QStringLiteral("status"), QStringLiteral("Fluid package not found."));
      return out;
   }

   const auto& pkg = packages_[static_cast<std::size_t>(idx)];
   out.insert(QStringLiteral("packageId"), pkg.id);
   out.insert(QStringLiteral("packageName"), pkg.name);
   out.insert(QStringLiteral("componentListId"), pkg.componentListId);
   out.insert(QStringLiteral("thermoMethodId"), pkg.thermoMethodId);
   out.insert(QStringLiteral("propertyMethod"), pkg.propertyMethod);
   out.insert(QStringLiteral("isDefault"), pkg.isDefault);
   out.insert(QStringLiteral("isCrudePackage"), pkg.isCrudePackage);

   const auto cfg = thermoConfigForPackageResolved(packageId);
   out.insert(QStringLiteral("displayName"), QString::fromStdString(cfg.displayName));
   out.insert(QStringLiteral("eosName"), QString::fromStdString(cfg.eosName));
   out.insert(QStringLiteral("phaseModelFamily"), QString::fromStdString(cfg.phaseModelFamily));
   out.insert(QStringLiteral("supportsEnthalpy"), cfg.supportsEnthalpy);
   out.insert(QStringLiteral("supportsEntropy"), cfg.supportsEntropy);
   out.insert(QStringLiteral("supportsTwoPhase"), cfg.supportsTwoPhase);
   QStringList supportFlags;
   for (const auto& flag : cfg.supportFlags) supportFlags.push_back(QString::fromStdString(flag));
   out.insert(QStringLiteral("supportFlags"), supportFlags);

   if (auto* cm = ComponentManager::instance()) {
      const QVariantMap listInfo = cm->describeComponentList(pkg.componentListId);
      const QVariantList resolved = cm->resolvedComponentsForList(pkg.componentListId);
      out.insert(QStringLiteral("componentListName"), listInfo.value(QStringLiteral("name")));
      out.insert(QStringLiteral("listType"), listInfo.value(QStringLiteral("listType")));
      out.insert(QStringLiteral("sourceFluidName"), listInfo.value(QStringLiteral("sourceFluidName")));
      out.insert(QStringLiteral("componentCount"), resolved.size());
      const bool hasList = !pkg.componentListId.trimmed().isEmpty() && !listInfo.isEmpty();
      out.insert(QStringLiteral("valid"), hasList);
      out.insert(QStringLiteral("status"), hasList
         ? QStringLiteral("Package is valid and resolves %1 components.").arg(resolved.size())
         : QStringLiteral("Select a valid component list for this package."));
   }
   else {
      out.insert(QStringLiteral("valid"), !pkg.componentListId.trimmed().isEmpty());
      out.insert(QStringLiteral("status"), !pkg.componentListId.trimmed().isEmpty()
         ? QStringLiteral("Component manager unavailable; package metadata only.")
         : QStringLiteral("Select a component list for this package."));
   }

   return out;
}

FluidDefinition FluidPackageManager::resolveFluidDefinitionForPackage(const QString& packageId) const
{
   FluidDefinition def;
   const int idx = indexOfPackageId_(packageId);
   if (idx < 0) return def;

   const auto& pkg = packages_[static_cast<std::size_t>(idx)];
   QVariantMap listInfo;
   if (auto* cm = ComponentManager::instance()) {
      def = cm->buildFluidDefinitionSkeletonFromComponentList(pkg.componentListId);
      listInfo = cm->describeComponentList(pkg.componentListId);
   }

   const QString sourceFluidName = listInfo.value(QStringLiteral("sourceFluidName")).toString().trimmed();
   if (!sourceFluidName.isEmpty()) {
      const FluidDefinition legacy = getFluidDefinition(sourceFluidName.toStdString());
      def.columnDefaults = legacy.columnDefaults;
      if (legacy.thermo.zDefault.size() == def.thermo.components.size()) {
         def.thermo.zDefault = legacy.thermo.zDefault;
         def.thermo.hasZDefault = legacy.thermo.hasZDefault;
      }
   }

   if (def.name.empty())
      def.name = pkg.name.toStdString();
   return def;
}

QVariantList FluidPackageManager::packageComposition(const QString& packageId) const
{
   QVariantList out;
   const FluidDefinition def = resolveFluidDefinitionForPackage(packageId);
   const auto& comps = def.thermo.components;
   const auto& zDef = def.thermo.zDefault;   // mass fractions, normalized to sum=1

   const std::size_t n = comps.size();
   if (n == 0) return out;

   // Build mass fractions — use zDefault if present and correct size, else equal split
   std::vector<double> massFrac(n, 1.0 / static_cast<double>(n));
   if (zDef.size() == n) massFrac = zDef;

   // Convert mass fractions to mole fractions: xi_mole = (xi_mass/MWi) / sum(xj_mass/MWj)
   std::vector<double> moleFrac(n, 0.0);
   double moleSum = 0.0;
   for (std::size_t i = 0; i < n; ++i) {
      const double mw = comps[i].MW > 0.0 ? comps[i].MW : 1.0;
      moleFrac[i] = massFrac[i] / mw;
      moleSum += moleFrac[i];
   }
   if (moleSum > 0.0)
      for (double& v : moleFrac) v /= moleSum;

   for (std::size_t i = 0; i < n; ++i) {
      QVariantMap row;
      row.insert(QStringLiteral("id"), QString::fromStdString(comps[i].name));
      row.insert(QStringLiteral("name"), QString::fromStdString(comps[i].name));
      row.insert(QStringLiteral("massFrac"), massFrac[i]);
      row.insert(QStringLiteral("moleFrac"), moleFrac[i]);
      row.insert(QStringLiteral("mw"), comps[i].MW);
      out.append(row);
   }
   return out;
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