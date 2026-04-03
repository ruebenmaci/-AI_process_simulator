#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <vector>

#include "components/ComponentRecord.h"
#include "components/ComponentListRecord.h"
#include "thermo/pseudocomponents/FluidDefinition.hpp"

class ComponentListModel;
class CompGroupListModel;

class ComponentManager : public QObject
{
    Q_OBJECT

    // ── Existing component properties ─────────────────────────────────
    Q_PROPERTY(QObject* componentModel READ componentModel CONSTANT)
    Q_PROPERTY(int componentCount READ componentCount NOTIFY componentsChanged)
    Q_PROPERTY(int binaryInteractionCount READ binaryInteractionCount NOTIFY componentsChanged)
    Q_PROPERTY(QStringList componentFamilies READ componentFamilies NOTIFY componentsChanged)
    Q_PROPERTY(QStringList pseudoFluidNames READ pseudoFluidNames CONSTANT)
    Q_PROPERTY(QStringList availableFluidNames READ availableFluidNames NOTIFY componentsChanged)
    Q_PROPERTY(QString seedResourcePath READ seedResourcePath CONSTANT)
    Q_PROPERTY(QString lastLoadStatus READ lastLoadStatus NOTIFY componentsChanged)

    // ── NEW: Component List properties ────────────────────────────────
    Q_PROPERTY(QObject* componentListModel READ componentListModel CONSTANT)
    Q_PROPERTY(int componentListCount READ componentListCount NOTIFY componentListsChanged)
    Q_PROPERTY(QStringList componentListNames READ componentListNames NOTIFY componentListsChanged)

public:
    explicit ComponentManager(QObject* parent = nullptr);
    ~ComponentManager() override;

    static ComponentManager* instance();

    // ── Existing component API ─────────────────────────────────────────
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

    // ── NEW: Component List API ────────────────────────────────────────
    QObject*     componentListModel() const;
    int          componentListCount() const;
    QStringList  componentListNames() const;

    Q_INVOKABLE QVariantMap  getComponentList(const QString& listId) const;
    Q_INVOKABLE QVariantList listComponentLists() const;
    Q_INVOKABLE bool createComponentList(const QString& name);
    Q_INVOKABLE bool addOrUpdateComponentList(const QVariantMap& listMap);
    Q_INVOKABLE bool removeComponentList(const QString& listId);
    Q_INVOKABLE bool addComponentToList(const QString& listId, const QString& componentId);
    Q_INVOKABLE bool removeComponentFromList(const QString& listId, const QString& componentId);
    Q_INVOKABLE bool renameComponentList(const QString& listId, const QString& newName);
    Q_INVOKABLE QStringList  resolvedComponentIdsForList(const QString& listId) const;
    Q_INVOKABLE QVariantList resolvedComponentsForList(const QString& listId) const;

signals:
    void componentsChanged();
    void componentListsChanged();
    void errorOccurred(const QString& message);

private:
    // Existing private helpers
    bool loadFromJsonBytes(const QByteArray& jsonBytes, const QString& sourceLabel);
    bool reloadSeedAndPseudoFluids_();
    QStringList seedResourceCandidates_() const;
    QStringList discoverSeedResourceCandidates_() const;
    void syncModel_();
    int indexOfComponentId_(const QString& componentId) const;
    std::vector<sim::ComponentRecord> componentsForPseudoFluid_(const QString& fluidName) const;
    static std::vector<double> defaultCompositionForFluid_(const QString& fluidName, std::size_t n);
    static QString normalizeId_(QString id);

    // NEW private helpers
    void syncGroupModel_();
    int  indexOfListId_(const QString& listId) const;
    static QString normalizeListId_(QString name);
    void ensureStarterComponentLists_(bool replaceStarterLists);

private:
    std::vector<sim::ComponentRecord> components_;
    std::vector<sim::BinaryInteractionRecord> binaryInteractions_;
    ComponentListModel*  componentModel_ = nullptr;

    // NEW
    std::vector<sim::ComponentListRecord> componentLists_;
    CompGroupListModel*  groupModel_ = nullptr;

    QString lastLoadStatus_;

    static ComponentManager* instance_;
};
