#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <vector>
#include <limits>
#include "../../thermo/pseudocomponents/FluidDefinition.hpp"

class ComponentManager;
#include "../../thermo/StreamPropertyCalcs.hpp"   // StreamPhaseProps

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

      enum class FlowSpecMode {
      MassFlow = 0,
      MolarFlow,
      StdLiquidVolumeFlow
   };
   Q_ENUM(FlowSpecMode)

      enum class ThermoSpecMode {
      TP = 0,
      PH,
      PS,
      PVF,
      TS
   };
   Q_ENUM(ThermoSpecMode)

      explicit MaterialStreamState(QObject* parent = nullptr);

   // ── Existing properties (unchanged) ──────────────────────────────────────
   Q_PROPERTY(QString streamName READ streamName WRITE setStreamName NOTIFY streamNameChanged)
      Q_PROPERTY(QStringList fluidNames READ fluidNames NOTIFY fluidNamesChanged)
      Q_PROPERTY(QString selectedFluid READ selectedFluid WRITE setSelectedFluid NOTIFY selectedFluidChanged)
      Q_PROPERTY(double flowRateKgph READ flowRateKgph WRITE setFlowRateKgph NOTIFY flowRateKgphChanged)
      Q_PROPERTY(double molarFlowKmolph READ molarFlowKmolph WRITE setMolarFlowKmolph NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double volumetricFlowM3ph READ volumetricFlowM3ph NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double standardLiquidVolumeFlowM3ph READ standardLiquidVolumeFlowM3ph WRITE setStandardLiquidVolumeFlowM3ph NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double temperatureK READ temperatureK WRITE setTemperatureK NOTIFY temperatureKChanged)
      Q_PROPERTY(double pressurePa READ pressurePa WRITE setPressurePa NOTIFY pressurePaChanged)
      Q_PROPERTY(double vaporFraction READ vaporFraction WRITE setSpecifiedVaporFraction NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double specifiedVaporFraction READ specifiedVaporFraction WRITE setSpecifiedVaporFraction NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double enthalpyKJkg READ enthalpyKJkg WRITE setEnthalpyKJkg NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double entropyKJkgK READ entropyKJkgK WRITE setEntropyKJkgK NOTIFY derivedConditionsChanged)
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
      Q_PROPERTY(QString phaseStatus READ phaseStatus NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString flashMethod READ flashMethod NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString thermoRegionLabel READ thermoRegionLabel NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double bubblePointEstimateK READ bubblePointEstimateK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double dewPointEstimateK READ dewPointEstimateK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString compositionSourceLabel READ compositionSourceLabel NOTIFY compositionChanged)
      Q_PROPERTY(QString compositionEditStatusLabel READ compositionEditStatusLabel NOTIFY streamTypeChanged)
      Q_PROPERTY(FlowSpecMode flowSpecMode READ flowSpecMode WRITE setFlowSpecMode NOTIFY flowSpecModeChanged)
      Q_PROPERTY(ThermoSpecMode thermoSpecMode READ thermoSpecMode WRITE setThermoSpecMode NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool supportsPS READ supportsPS CONSTANT)
      Q_PROPERTY(bool temperatureEditable READ temperatureEditable NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool pressureEditable READ pressureEditable NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool enthalpyEditable READ enthalpyEditable NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool entropyEditable READ entropyEditable NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool vaporFractionEditable READ vaporFractionEditable NOTIFY thermoSpecModeChanged)
      Q_PROPERTY(bool massFlowEditable READ massFlowEditable NOTIFY flowSpecModeChanged)
      Q_PROPERTY(bool molarFlowEditable READ molarFlowEditable NOTIFY flowSpecModeChanged)
      Q_PROPERTY(bool standardLiquidVolumeFlowEditable READ standardLiquidVolumeFlowEditable NOTIFY flowSpecModeChanged)
      Q_PROPERTY(bool compositionValid READ compositionValid NOTIFY derivedConditionsChanged)
      Q_PROPERTY(bool averageMwValid READ averageMwValid NOTIFY derivedConditionsChanged)
      Q_PROPERTY(bool referenceDensityValid READ referenceDensityValid NOTIFY derivedConditionsChanged)
      Q_PROPERTY(bool flowInputsSufficient READ flowInputsSufficient NOTIFY derivedConditionsChanged)
      Q_PROPERTY(bool thermoInputsSufficient READ thermoInputsSufficient NOTIFY derivedConditionsChanged)
      Q_PROPERTY(bool streamSolvable READ streamSolvable NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString specificationStatus READ specificationStatus NOTIFY derivedConditionsChanged)
      Q_PROPERTY(QString specificationError READ specificationError NOTIFY derivedConditionsChanged)

      // ── NEW: phase-split properties (all fire derivedConditionsChanged) ───────

      // Densities
      Q_PROPERTY(double liquidDensityKgM3    READ liquidDensityKgM3    NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourDensityKgM3    READ vapourDensityKgM3    NOTIFY derivedConditionsChanged)

      // Viscosities
      Q_PROPERTY(double liquidViscosityCp    READ liquidViscosityCp    NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourViscosityCp    READ vapourViscosityCp    NOTIFY derivedConditionsChanged)

      // Thermal conductivities
      Q_PROPERTY(double liquidThermalCondWmK READ liquidThermalCondWmK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourThermalCondWmK READ vapourThermalCondWmK NOTIFY derivedConditionsChanged)

      // Heat capacities
      Q_PROPERTY(double liquidCpKJkgK        READ liquidCpKJkgK        NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourCpKJkgK        READ vapourCpKJkgK        NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourCpCvRatio      READ vapourCpCvRatio      NOTIFY derivedConditionsChanged)

      // Per-phase enthalpies (mixture enthalpyKJkg already exposed above)
      Q_PROPERTY(double liquidEnthalpyKJkg   READ liquidEnthalpyKJkg   NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourEnthalpyKJkg   READ vapourEnthalpyKJkg   NOTIFY derivedConditionsChanged)

      // Per-phase entropies (mixture entropyKJkgK already exposed above)
      Q_PROPERTY(double liquidEntropyKJkgK   READ liquidEntropyKJkgK   NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double vapourEntropyKJkgK   READ vapourEntropyKJkgK   NOTIFY derivedConditionsChanged)

      // Interfacial / bulk
      Q_PROPERTY(double surfaceTensionNm     READ surfaceTensionNm     NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double watsonKFactor        READ watsonKFactor        NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double criticalTemperatureK READ criticalTemperatureK NOTIFY derivedConditionsChanged)
      Q_PROPERTY(double criticalPressureKPa  READ criticalPressureKPa  NOTIFY derivedConditionsChanged)

      // Std volumetric flow (m³/h at 15 °C / 101.325 kPa) — feeds the stream
      // summary row and the conditions panel Std. liquid vol. flow field.
      Q_PROPERTY(double calcStdVolFlowM3ph   READ calcStdVolFlowM3ph   NOTIFY derivedConditionsChanged)

      // Per-component K-values (y/x), liquid mole fractions, vapour mole fractions.
      // Returns a QVariantList of QVariantMap, each with keys:
      //   "name"  — component name (QString)
      //   "x"     — liquid mole fraction (double)
      //   "y"     — vapour mole fraction (double)
      //   "K"     — equilibrium K-value y/x (double, NaN → shown as "—")
      // List is empty when the stream has not been flashed or is single-phase.
      Q_PROPERTY(QVariantList kValuesData READ kValuesData NOTIFY derivedConditionsChanged)

      // ── Existing method declarations (unchanged) ──────────────────────────────
      QString streamName() const { return streamRoleLabel_; }
   void setStreamName(const QString& value);
   QStringList fluidNames() const { return fluidNames_; }
   QString selectedFluid() const { return selectedFluid_; }
   void setSelectedFluid(const QString& value);
   double flowRateKgph() const { return flowRateKgph_; }
   void setFlowRateKgph(double value);
   void setMolarFlowKmolph(double value);
   void setStandardLiquidVolumeFlowM3ph(double value);
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
   double standardLiquidVolumeFlowM3ph() const;
   double vaporFraction() const;
   double specifiedVaporFraction() const;
   double enthalpyKJkg() const;
   double entropyKJkgK() const;
   QString phaseStatus() const;
   QString flashMethod() const;
   QString thermoRegionLabel() const;
   double bubblePointEstimateK() const;
   double dewPointEstimateK() const;
   QString compositionSourceLabel() const;
   QString compositionEditStatusLabel() const;
   void setVaporFraction(double value);
   void setSpecifiedVaporFraction(double value);
   void setEnthalpyKJkg(double value);
   void setEntropyKJkgK(double value);
   void setBulkDensityOverrideKgM3(double value);
   FlowSpecMode flowSpecMode() const { return flowSpecMode_; }
   void setFlowSpecMode(FlowSpecMode value);
   ThermoSpecMode thermoSpecMode() const { return thermoSpecMode_; }
   void setThermoSpecMode(ThermoSpecMode value);
   bool supportsPS() const { return true; }
   bool temperatureEditable() const;
   bool pressureEditable() const;
   bool enthalpyEditable() const;
   bool entropyEditable() const;
   bool vaporFractionEditable() const;
   bool massFlowEditable() const;
   bool molarFlowEditable() const;
   bool standardLiquidVolumeFlowEditable() const;
   bool compositionValid() const;
   bool averageMwValid() const;
   bool referenceDensityValid() const;
   bool flowInputsSufficient() const;
   bool thermoInputsSufficient() const;
   bool streamSolvable() const;
   QString specificationStatus() const;
   QString specificationError() const;
   Q_INVOKABLE void resetToFluidDefaults();
   Q_INVOKABLE void resetCompositionToFluidDefault();
   Q_INVOKABLE void normalizeComposition();
   Q_INVOKABLE void resetComponentPropertiesToFluidDefault();
   Q_INVOKABLE void clearCustomCompositionEdits();
   bool setCompositionStd(const std::vector<double>& value);
   bool setComponentProperty(int row, const QString& field, double value);

   // ── NEW: property getters ─────────────────────────────────────────────────
   double liquidDensityKgM3()    const { return phaseProps_.rhoLiq; }
   double vapourDensityKgM3()    const { return phaseProps_.rhoVap; }
   double liquidViscosityCp()    const { return phaseProps_.viscLiqCp; }
   double vapourViscosityCp()    const { return phaseProps_.viscVapCp; }
   double liquidThermalCondWmK() const { return phaseProps_.kCondLiqWmK; }
   double vapourThermalCondWmK() const { return phaseProps_.kCondVapWmK; }
   double liquidCpKJkgK()        const { return phaseProps_.cpLiqKJkgK; }
   double vapourCpKJkgK()        const { return phaseProps_.cpVapKJkgK; }
   double vapourCpCvRatio()      const { return phaseProps_.cpCvRatioVap; }
   double liquidEnthalpyKJkg()   const { return phaseProps_.hLiqKJkg; }
   double vapourEnthalpyKJkg()   const { return phaseProps_.hVapKJkg; }
   double liquidEntropyKJkgK()   const { return phaseProps_.sLiqKJkgK; }
   double vapourEntropyKJkgK()   const { return phaseProps_.sVapKJkgK; }
   double surfaceTensionNm()     const { return phaseProps_.surfTensionNm; }
   double watsonKFactor()        const { return phaseProps_.watsonK; }
   double criticalTemperatureK() const { return phaseProps_.TcMixK; }
   double criticalPressureKPa()  const { return phaseProps_.PcMixKPa; }
   double calcStdVolFlowM3ph()   const { return phaseProps_.stdVolFlowM3ph; }
   QVariantList kValuesData()    const;

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
   void flowSpecModeChanged();
   void thermoSpecModeChanged();

private:
   ComponentManager* componentManager_() const;

private:
   void refreshFluidDefinition_();
   bool applyComposition_(std::vector<double> value, bool customFlag, bool normalize);
   bool setComponentPropertyByKey_(int row, const QString& field, double value);
   void emitDerivedConditionsChanged_();
   void recalcFeedPhase_();
   bool normalizedComposition_(std::vector<double>& z) const;
   void validateAndUpdateStatus_();
   void applyCanonicalFlowFromActiveSpec_();

   // ── Existing member data (unchanged) ─────────────────────────────────────
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
   double specifiedVaporFraction_ = 0.0;
   double enthalpyKJkg_ = std::numeric_limits<double>::quiet_NaN();
   double entropyKJkgK_ = std::numeric_limits<double>::quiet_NaN();
   QString flashMethod_ = QStringLiteral("Not calculated");
   double bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
   double dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
   double bulkDensityOverrideKgM3_ = std::numeric_limits<double>::quiet_NaN();
   FlowSpecMode flowSpecMode_ = FlowSpecMode::MassFlow;
   ThermoSpecMode thermoSpecMode_ = ThermoSpecMode::TP;
   double specifiedMolarFlowKmolph_ = std::numeric_limits<double>::quiet_NaN();
   double specifiedStandardLiquidVolumeFlowM3ph_ = std::numeric_limits<double>::quiet_NaN();
   QString specificationStatus_ = QStringLiteral("Ready");
   QString specificationError_;
   bool compositionValid_ = false;
   bool averageMwValid_ = false;
   bool referenceDensityValid_ = false;
   bool flowInputsSufficient_ = true;
   bool thermoInputsSufficient_ = false;
   bool streamSolvable_ = false;
   StreamType m_streamType = StreamType::Unknown;

   // ── NEW member data ───────────────────────────────────────────────────────
   // Phase compositions saved after every flash (all spec modes)
   std::vector<double> liqComposition_;  // x — liquid phase mole fractions
   std::vector<double> vapComposition_;  // y — vapour phase mole fractions

   // Computed after every successful flash via calcStreamProperties()
   StreamPhaseProps phaseProps_;
};