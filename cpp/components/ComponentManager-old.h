#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <vector>

#include "components/ComponentRecord.h"
#include "thermo/pseudocomponents/FluidDefinition.hpp"

class ComponentListModel;

class ComponentManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject* componentModel READ componentModel CONSTANT)
    Q_PROPERTY(int componentCount READ componentCount NOTIFY componentsChanged)
    Q_PROPERTY(int binaryInteractionCount READ binaryInteractionCount NOTIFY componentsChanged)
    Q_PROPERTY(QStringList componentFamilies READ componentFamilies NOTIFY componentsChanged)
    Q_PROPERTY(QStringList pseudoFluidNames READ pseudoFluidNames CONSTANT)
    Q_PROPERTY(QStringList availableFluidNames READ availableFluidNames NOTIFY componentsChanged)
    Q_PROPERTY(QString seedResourcePath READ seedResourcePath CONSTANT)
    Q_PROPERTY(QString lastLoadStatus READ lastLoadStatus NOTIFY componentsChanged)

public:
    explicit ComponentManager(QObject* parent = nullptr);
    ~ComponentManager() override;

    static ComponentManager* instance();

    QObject* componentModel() const;
    int componentCount() const;
    int binaryInteractionCount() const;
    QStringList componentFamilies() const;
    QStringList pseudoFluidNames() const;
    QStringList availableFluidNames() const;
    QString seedResourcePath() const;
    QString lastLoadStatus() const;

    FluidDefinition buildFluidDefinition(const QString& fluidName) const;

    const std::vector<sim::ComponentRecord>& components() const { return components_; }
    const std::vector<sim::BinaryInteractionRecord>& binaryInteractions() const { return binaryInteractions_; }

    Q_INVOKABLE bool resetToStarterSeed();
    Q_INVOKABLE bool loadFromJsonFile(const QString& absoluteOrRelativePath);
    Q_INVOKABLE bool loadFromJsonResource(const QString& resourcePath = QString());
    Q_INVOKABLE bool saveToJsonFile(const QString& absoluteOrRelativePath) const;
    Q_INVOKABLE QVariantMap getComponent(const QString& componentId) const;
    Q_INVOKABLE QVariantList findComponents(const QString& text,
                                            const QString& family = QString(),
                                            bool includePseudoComponents = true) const;
    Q_INVOKABLE bool containsComponent(const QString& componentId) const;
    Q_INVOKABLE bool addOrUpdateComponent(const QVariantMap& componentMap);
    Q_INVOKABLE bool removeComponent(const QString& componentId);
    Q_INVOKABLE int importPseudoComponentFluid(const QString& fluidName,
                                               const QString& family = QStringLiteral("pseudo-fraction"),
                                               bool replaceExisting = false);
    Q_INVOKABLE bool updatePseudoComponentProperty(const QString& fluidName,
                                                   const QString& componentName,
                                                   const QString& field,
                                                   double value);
    Q_INVOKABLE void clear();

signals:
    void componentsChanged();
    void errorOccurred(const QString& message);

private:
    bool loadFromJsonBytes(const QByteArray& jsonBytes, const QString& sourceLabel);
    bool reloadSeedAndPseudoFluids_();
    QStringList seedResourceCandidates_() const;
    QStringList discoverSeedResourceCandidates_() const;
    void syncModel_();
    int indexOfComponentId_(const QString& componentId) const;
    std::vector<sim::ComponentRecord> componentsForPseudoFluid_(const QString& fluidName) const;
    static std::vector<double> defaultCompositionForFluid_(const QString& fluidName, std::size_t n);
    static QString normalizeId_(QString id);

private:
    std::vector<sim::ComponentRecord> components_;
    std::vector<sim::BinaryInteractionRecord> binaryInteractions_;
    ComponentListModel* componentModel_ = nullptr;
    QString lastLoadStatus_;

    static ComponentManager* instance_;
};
