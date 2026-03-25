#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include <vector>
#include <limits>

#include "../../thermo/pseudocomponents/FluidDefinition.hpp"

#include <QString>

class StreamCompositionModel;

class MaterialStreamState : public QObject
{
   Q_OBJECT

public:
   enum class StreamType {
      Unknown = 0,
      Feed,
      Product
   };
   Q_ENUM(StreamType)

      explicit MaterialStreamState(QObject* parent = nullptr);

   Q_PROPERTY(QString streamName READ streamName WRITE setStreamName NOTIFY streamNameChanged)
      Q_PROPERTY(QStringList fluidNames READ fluidNames NOTIFY fluidNamesChanged)
      Q_PROPERTY(QString selectedFluid READ selectedFluid WRITE setSelectedFluid NOTIFY selectedFluidChanged)
      Q_PROPERTY(double flowRateKgph READ flowRateKgph WRITE setFlowRateKgph NOTIFY flowRateKgphChanged)
      Q_PROPERTY(double temperatureK READ temperatureK WRITE setTemperatureK NOTIFY temperatureKChanged)
      Q_PROPERTY(double pressurePa READ pressurePa WRITE setPressurePa NOTIFY pressurePaChanged)
      Q_PROPERTY(QVariantList composition READ composition NOTIFY compositionChanged)
      Q_PROPERTY(QObject* compositionModel READ compositionModel CONSTANT)
      Q_PROPERTY(bool hasCustomComposition READ hasCustomComposition NOTIFY hasCustomCompositionChanged)
      Q_PROPERTY(StreamType streamType READ streamType WRITE setStreamType NOTIFY streamTypeChanged)
      Q_PROPERTY(QString streamTypeLabel READ streamTypeLabel NOTIFY streamTypeChanged)
      Q_PROPERTY(bool feedStream READ isFeedStream NOTIFY streamTypeChanged)
      Q_PROPERTY(bool productStream READ isProductStream NOTIFY streamTypeChanged)
      Q_PROPERTY(bool isCrudeFeed READ isCrudeFeed WRITE setIsCrudeFeed NOTIFY isCrudeFeedChanged)
      Q_PROPERTY(bool componentEditingEnabled READ componentEditingEnabled NOTIFY componentEditingEnabledChanged)
      Q_PROPERTY(double massFractionSum READ massFractionSum NOTIFY compositionChanged)
      Q_PROPERTY(bool massFractionsBalanced READ massFractionsBalanced NOTIFY compositionChanged)
      Q_PROPERTY(double molarFlowKmolph READ molarFlowKmolph NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double volumetricFlowM3ph READ volumetricFlowM3ph NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vaporFraction READ vaporFraction NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString phaseStatus READ phaseStatus NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString flashMethod READ flashMethod NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString thermoRegionLabel READ thermoRegionLabel NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double bubblePointEstimateK READ bubblePointEstimateK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double dewPointEstimateK READ dewPointEstimateK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString compositionSourceLabel READ compositionSourceLabel NOTIFY compositionChanged)
      Q_PROPERTY(QString compositionEditStatusLabel READ compositionEditStatusLabel NOTIFY streamTypeChanged)

      QString streamName() const { return streamRoleLabel_; }
   void setStreamName(const QString& value);

   QStringList fluidNames() const { return fluidNames_; }
   QString selectedFluid() const { return selectedFluid_; }
   void setSelectedFluid(const QString& value);

   double flowRateKgph() const { return flowRateKgph_; }
   void setFlowRateKgph(double value);

   double temperatureK() const { return temperatureK_; }
   void setTemperatureK(double value);

   double pressurePa() const { return pressurePa_; }
   void setPressurePa(double value);

   const FluidDefinition& fluidDefinition() const { return fluidDefinition_; }
   QVariantList composition() const;
   QObject* compositionModel() const;
   const std::vector<double>& compositionStd() const { return composition_; }
   bool hasCustomComposition() const { return hasCustomComposition_; }

   StreamType streamType() const;
   QString streamTypeLabel() const;
   void setStreamType(StreamType type);

   Q_INVOKABLE bool isFeedStream() const;
   Q_INVOKABLE bool isProductStream() const;
   Q_INVOKABLE void setStreamTypeFromConnectionDirection(const QString& direction);

   bool isCrudeFeed() const { return isCrudeFeed_; }
   void setIsCrudeFeed(bool value);

   bool componentEditingEnabled() const;
   double massFractionSum() const;
   bool massFractionsBalanced() const;
   double averageMolecularWeight() const;
   double molarFlowKmolph() const;
   double estimatedBulkDensityKgM3() const;
   double volumetricFlowM3ph() const;
   double vaporFraction() const;
   QString phaseStatus() const;
   QString flashMethod() const;
   QString thermoRegionLabel() const;
   double bubblePointEstimateK() const;
   double dewPointEstimateK() const;
   QString compositionSourceLabel() const;
   QString compositionEditStatusLabel() const;
   void setVaporFraction(double value);
   void setBulkDensityOverrideKgM3(double value);

   Q_INVOKABLE void resetToFluidDefaults();
   Q_INVOKABLE void resetCompositionToFluidDefault();
   Q_INVOKABLE void normalizeComposition();
   Q_INVOKABLE void resetComponentPropertiesToFluidDefault();
   Q_INVOKABLE void clearCustomCompositionEdits();

   bool setCompositionStd(const std::vector<double>& value);
   bool setComponentProperty(int row, const QString& field, double value);

signals:
   void streamNameChanged();
   void fluidNamesChanged();
   void selectedFluidChanged();
   void flowRateKgphChanged();
   void temperatureKChanged();
   void pressurePaChanged();
   void compositionChanged();
   void hasCustomCompositionChanged();
   void fluidDefinitionChanged();
   void streamTypeChanged();
   void isCrudeFeedChanged();
   void componentEditingEnabledChanged();
   void derivedConditionsChanged();

private:
   void refreshFluidDefinition_();
   bool applyComposition_(std::vector<double> value, bool customFlag, bool normalize);
   bool setComponentPropertyByKey_(int row, const QString& field, double value);
   void emitDerivedConditionsChanged_();
   void recalcFeedPhase_();

   QString streamRoleLabel_ = QStringLiteral("Feed stream");
   QStringList fluidNames_;
   QString selectedFluid_;
   FluidDefinition fluidDefinition_;
   double flowRateKgph_ = 100000.0;
   double temperatureK_ = 640.0;
   double pressurePa_ = 150000.0;
   std::vector<double> composition_;
   bool hasCustomComposition_ = false;
   bool isCrudeFeed_ = false;
   StreamCompositionModel* compositionModel_ = nullptr;
   double vaporFraction_ = 0.0;
   QString flashMethod_ = QStringLiteral("Not calculated");
   double bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
   double dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
   double bulkDensityOverrideKgM3_ = std::numeric_limits<double>::quiet_NaN();

   StreamType m_streamType = StreamType::Unknown;
};