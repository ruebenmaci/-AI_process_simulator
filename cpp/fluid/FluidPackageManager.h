#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <vector>

#include "fluid/FluidPackageRecord.h"
#include "thermo/pseudocomponents/FluidDefinition.hpp"
#include "thermo/ThermoConfig.hpp"

class FluidPackageListModel;

class FluidPackageManager : public QObject
{
   Q_OBJECT
      Q_PROPERTY(QObject* fluidPackageModel      READ fluidPackageModel      CONSTANT)
      Q_PROPERTY(int          fluidPackageCount      READ fluidPackageCount      NOTIFY fluidPackagesChanged)
      Q_PROPERTY(QStringList  propertyMethods        READ propertyMethods        CONSTANT)
      Q_PROPERTY(QStringList  availableThermoMethods READ availableThermoMethods CONSTANT)
      Q_PROPERTY(QString      defaultFluidPackageId  READ defaultFluidPackageId  NOTIFY fluidPackagesChanged)
      Q_PROPERTY(QString      lastStatus             READ lastStatus             NOTIFY fluidPackagesChanged)

public:
   explicit FluidPackageManager(QObject* parent = nullptr);
   ~FluidPackageManager() override;

   static FluidPackageManager* instance();

   QObject* fluidPackageModel()     const;
   int         fluidPackageCount()     const;
   QStringList propertyMethods()       const;
   QStringList availableThermoMethods() const;
   QString     defaultFluidPackageId() const;
   QString     lastStatus()            const;

   Q_INVOKABLE QVariantMap  getFluidPackage(const QString& packageId) const;
   Q_INVOKABLE QVariantList listFluidPackages() const;
   Q_INVOKABLE bool addOrUpdateFluidPackage(const QVariantMap& packageMap);
   Q_INVOKABLE bool removeFluidPackage(const QString& packageId);

   // Returns the names of every material stream currently using `packageId`.
   // Used by removeFluidPackage to block deletion when a stream still
   // references the package, and may also be called from QML to display the
   // blocking reason in a dialog.
   Q_INVOKABLE QStringList streamsUsingPackage(const QString& packageId) const;

   // Parallel helper: returns the unit IDs (in the same order as
   // streamsUsingPackage) for navigation back to the underlying stream.
   Q_INVOKABLE QStringList streamUnitIdsUsingPackage(const QString& packageId) const;
   Q_INVOKABLE bool setDefaultFluidPackage(const QString& packageId);
   Q_INVOKABLE bool createStarterPackages();
   Q_INVOKABLE bool saveToJsonFile(const QString& path) const;
   Q_INVOKABLE bool loadFromJsonFile(const QString& path);

   // Phase 0 ownership scaffolding.
   Q_INVOKABLE bool packageExists(const QString& packageId) const;
   Q_INVOKABLE QString fluidPackageName(const QString& packageId) const;
   Q_INVOKABLE QString thermoMethodIdForPackage(const QString& packageId) const;
   Q_INVOKABLE QString starterPackageIdForLegacyCrudeName(const QString& crudeName) const;
   Q_INVOKABLE QVariantMap thermoConfigForPackage(const QString& packageId) const;
   thermo::ThermoConfig thermoConfigForPackageResolved(const QString& packageId) const;
   FluidDefinition resolveFluidDefinitionForPackage(const QString& packageId) const;
   Q_INVOKABLE QVariantMap describeResolvedPackage(const QString& packageId) const;
   Q_INVOKABLE QVariantMap packageEditorSummary(const QString& packageId) const;
   Q_INVOKABLE QVariantList packageComposition(const QString& packageId) const;  // [{id,name,massFrac,moleFrac}]

signals:
   void fluidPackagesChanged();
   void errorOccurred(const QString& message);

private:
   void    syncModel_();
   int     indexOfPackageId_(const QString& packageId) const;
   void    normalizeRecord_(sim::FluidPackageRecord& rec) const;
   static  QString normalizeId_(QString id);

   std::vector<sim::FluidPackageRecord> packages_;
   FluidPackageListModel* model_ = nullptr;
   QString lastStatus_;

   static FluidPackageManager* instance_;
};