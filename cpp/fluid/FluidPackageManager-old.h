#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <vector>

#include "fluid/FluidPackageRecord.h"

class FluidPackageListModel;

class FluidPackageManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject*     fluidPackageModel    READ fluidPackageModel    CONSTANT)
    Q_PROPERTY(int          fluidPackageCount    READ fluidPackageCount    NOTIFY fluidPackagesChanged)
    Q_PROPERTY(QStringList  propertyMethods      READ propertyMethods      CONSTANT)
    Q_PROPERTY(QString      defaultFluidPackageId READ defaultFluidPackageId NOTIFY fluidPackagesChanged)
    Q_PROPERTY(QString      lastStatus           READ lastStatus           NOTIFY fluidPackagesChanged)

public:
    explicit FluidPackageManager(QObject* parent = nullptr);

    QObject*    fluidPackageModel()     const;
    int         fluidPackageCount()     const;
    QStringList propertyMethods()       const;
    QString     defaultFluidPackageId() const;
    QString     lastStatus()            const;

    Q_INVOKABLE QVariantMap  getFluidPackage(const QString& packageId) const;
    Q_INVOKABLE QVariantList listFluidPackages() const;
    Q_INVOKABLE bool addOrUpdateFluidPackage(const QVariantMap& packageMap);
    Q_INVOKABLE bool removeFluidPackage(const QString& packageId);
    Q_INVOKABLE bool setDefaultFluidPackage(const QString& packageId);
    Q_INVOKABLE bool createStarterPackages();
    Q_INVOKABLE bool saveToJsonFile(const QString& path) const;
    Q_INVOKABLE bool loadFromJsonFile(const QString& path);

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
};
