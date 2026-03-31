#include "MaterialStreamState.h"

#include "../models/StreamCompositionModel.h"

#include <QtGlobal>
#include <QDebug>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <functional>
#include <limits>
#include <numeric>

#include "../../thermo/EOSK.hpp"
#include "components/ComponentManager.h"
#include "../../thermo/Flash.hpp"
#include "../../thermo/PH_PS_PT_TS_Flash.hpp"
#include "../../thermo/StreamPropertyCalcs.hpp"

#include <QString>

namespace {
   bool fuzzyVectorEqual(const std::vector<double>& a, const std::vector<double>& b)
   {
      return a.size() == b.size()
         && std::equal(a.begin(), a.end(), b.begin(), [](double x, double y) {
         return qFuzzyCompare(1.0 + x, 1.0 + y);
            });
   }

   double mixMassFractionAvgMw(const std::vector<Component>& comps, const std::vector<double>& z)
   {
      const std::size_t n = std::min(comps.size(), z.size());
      double denom = 0.0;
      for (std::size_t i = 0; i < n; ++i) {
         const double wi = z[i];
         const double mw = comps[i].MW;
         if (!(wi > 0.0) || !std::isfinite(mw) || mw <= 0.0)
            continue;
         denom += wi / mw;
      }
      if (!(denom > 0.0))
         return 0.0;
      return 1.0 / denom;
   }

   double mixRhoLFromSg(const std::vector<Component>& comps, const std::vector<double>& z)
   {
      const std::size_t n = std::min(comps.size(), z.size());
      double sg = 0.0;
      double sum = 0.0;
      for (std::size_t i = 0; i < n; ++i) {
         const double wi = z[i];
         const double compSg = comps[i].SG;
         if (!(wi > 0.0) || !std::isfinite(compSg) || compSg <= 0.0)
            continue;
         sg += wi * compSg;
         sum += wi;
      }
      if (!(sum > 0.0))
         return std::numeric_limits<double>::quiet_NaN();
      return (sg / sum) * 1000.0;
   }
}

struct BubbleDewEstimate {
   double bubbleK = std::numeric_limits<double>::quiet_NaN();
   double dewK = std::numeric_limits<double>::quiet_NaN();
};

static double sumZiKi(const std::vector<double>& z, const std::vector<double>& K)
{
   const std::size_t n = std::min(z.size(), K.size());
   double s = 0.0;
   for (std::size_t i = 0; i < n; ++i) {
      if (!std::isfinite(z[i]) || !std::isfinite(K[i]))
         continue;
      s += z[i] * K[i];
   }
   return s;
}

static double sumZiOverKi(const std::vector<double>& z, const std::vector<double>& K)
{
   const std::size_t n = std::min(z.size(), K.size());
   double s = 0.0;
   for (std::size_t i = 0; i < n; ++i) {
      if (!std::isfinite(z[i]) || !std::isfinite(K[i]) || K[i] <= 0.0)
         continue;
      s += z[i] / K[i];
   }
   return s;
}

static double clampFiniteV(double v)
{
   if (!std::isfinite(v))
      return std::numeric_limits<double>::quiet_NaN();
   return std::clamp(v, 0.0, 1.0);
}

static double bisectTemperature(const std::function<double(double)>& f, double lo, double hi)
{
   double flo = f(lo);
   double fhi = f(hi);
   if (!std::isfinite(flo) || !std::isfinite(fhi) || flo * fhi > 0.0)
      return std::numeric_limits<double>::quiet_NaN();

   for (int iter = 0; iter < 60; ++iter) {
      const double mid = 0.5 * (lo + hi);
      const double fm = f(mid);
      if (!std::isfinite(fm))
         return std::numeric_limits<double>::quiet_NaN();
      if (std::fabs(fm) < 1e-6 || std::fabs(hi - lo) < 1e-3)
         return mid;
      if (flo * fm <= 0.0) {
         hi = mid;
         fhi = fm;
      }
      else {
         lo = mid;
         flo = fm;
      }
   }
   return 0.5 * (lo + hi);
}

static BubbleDewEstimate estimateBubbleDewFromEOS(double P, const std::vector<double>& z, const std::vector<Component>& comps)
{
   BubbleDewEstimate out;
   if (z.empty() || comps.empty())
      return out;

   double Tmin = std::numeric_limits<double>::infinity();
   double Tmax = -std::numeric_limits<double>::infinity();
   for (const auto& c : comps) {
      if (!std::isfinite(c.Tb) || c.Tb <= 0.0)
         continue;
      Tmin = std::min(Tmin, c.Tb);
      Tmax = std::max(Tmax, c.Tb);
   }
   if (!std::isfinite(Tmin) || !std::isfinite(Tmax))
      return out;

   Tmin = std::max(200.0, Tmin - 120.0);
   Tmax = std::min(1200.0, Tmax + 120.0);

   auto bubbleResid = [&](double T) -> double {
      const auto ek = eosK(P, T, z, comps, -1, 32, {}, nullptr, false, 1.0, "manual", "PRSV");
      return sumZiKi(z, ek.K) - 1.0;
      };
   auto dewResid = [&](double T) -> double {
      const auto ek = eosK(P, T, z, comps, -1, 32, {}, nullptr, false, 1.0, "manual", "PRSV");
      return 1.0 - sumZiOverKi(z, ek.K);
      };

   out.bubbleK = bisectTemperature(bubbleResid, Tmin, Tmax);
   out.dewK = bisectTemperature(dewResid, Tmin, Tmax);
   return out;
}

static BubbleDewEstimate estimateBubbleDewFromPTScan(
   double P,
   const std::vector<double>& z,
   const std::vector<Component>& comps,
   const std::string& crudeHint,
   const std::vector<std::vector<double>>* kij)
{
   BubbleDewEstimate out;
   if (z.empty() || comps.empty())
      return out;

   double Tmin = std::numeric_limits<double>::infinity();
   double Tmax = -std::numeric_limits<double>::infinity();
   for (const auto& c : comps) {
      if (!std::isfinite(c.Tb) || c.Tb <= 0.0)
         continue;
      Tmin = std::min(Tmin, c.Tb);
      Tmax = std::max(Tmax, c.Tb);
   }
   if (!std::isfinite(Tmin) || !std::isfinite(Tmax))
      return out;

   Tmin = std::max(220.0, Tmin - 80.0);
   Tmax = std::min(1000.0, Tmax + 80.0);
   if (!(Tmax > Tmin + 5.0))
      return out;

   auto solveAtT = [&](double T) {
      return flashPT(P, T, z, &comps, -1, 32, crudeHint, kij, 1.0, "manual", "PRSV");
      };
   auto vfAt = [&](double T) -> double {
      return clampFiniteV(solveAtT(T).V);
      };

   struct Sample { double T; double V; };
   std::vector<Sample> samples;
   for (double T = Tmin; T <= Tmax + 1e-9; T += 20.0) {
      const double V = vfAt(T);
      if (std::isfinite(V))
         samples.push_back({ T, V });
   }
   if (samples.size() < 2)
      return out;

   auto refineForTarget = [&](double target, double T1, double T2) -> double {
      auto resid = [&](double T) -> double {
         const double V = vfAt(T);
         if (!std::isfinite(V))
            return std::numeric_limits<double>::quiet_NaN();
         return V - target;
         };
      return bisectTemperature(resid, T1, T2);
      };

   constexpr double bubbleTarget = 0.01;
   constexpr double dewTarget = 0.99;

   for (std::size_t i = 1; i < samples.size(); ++i) {
      const auto& a = samples[i - 1];
      const auto& b = samples[i];
      if (!std::isfinite(out.bubbleK) && a.V <= bubbleTarget && b.V >= bubbleTarget) {
         out.bubbleK = refineForTarget(bubbleTarget, a.T, b.T);
         if (!std::isfinite(out.bubbleK))
            out.bubbleK = 0.5 * (a.T + b.T);
      }
      if (!std::isfinite(out.dewK) && a.V <= dewTarget && b.V >= dewTarget) {
         out.dewK = refineForTarget(dewTarget, a.T, b.T);
         if (!std::isfinite(out.dewK))
            out.dewK = 0.5 * (a.T + b.T);
      }
   }

   return out;
}

MaterialStreamState::MaterialStreamState(QObject* parent)
   : QObject(parent)
{
   compositionModel_ = new StreamCompositionModel(this, this);
   if (auto* cm = componentManager_())
      fluidNames_ = cm->availableFluidNames();
   else
      for (const auto& name : listFluidDefinitions()) {
         fluidNames_.push_back(QString::fromStdString(name));
      }

   selectedFluid_ = fluidNames_.contains("Brent")
      ? QStringLiteral("Brent")
      : (fluidNames_.isEmpty() ? QStringLiteral("Brent") : fluidNames_.front());

   refreshFluidDefinition_();
   resetToFluidDefaults();
   resetCompositionToFluidDefault();
}

void MaterialStreamState::setStreamName(const QString& value)
{
   if (streamRoleLabel_ == value) {
      return;
   }
   streamRoleLabel_ = value;
   emit streamNameChanged();
}

void MaterialStreamState::setSelectedFluid(const QString& value)
{
   if (selectedFluid_ == value) {
      return;
   }

   selectedFluid_ = value;
   refreshFluidDefinition_();
   resetToFluidDefaults();
   resetCompositionToFluidDefault();
   recalcFeedPhase_();
   emit selectedFluidChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setFlowRateKgph(double value)
{
   if (!std::isfinite(value) || value < 0.0) {
      value = 0.0;
   }
   const bool changed = !qFuzzyCompare(1.0 + flowRateKgph_, 1.0 + value);
   flowRateKgph_ = value;
   flowSpecMode_ = FlowSpecMode::MassFlow;
   specifiedMolarFlowKmolph_ = std::numeric_limits<double>::quiet_NaN();
   specifiedStandardLiquidVolumeFlowM3ph_ = std::numeric_limits<double>::quiet_NaN();
   validateAndUpdateStatus_();
   if (changed)
      emit flowRateKgphChanged();
   emit flowSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setMolarFlowKmolph(double value)
{
   if (!std::isfinite(value) || value < 0.0)
      value = 0.0;
   specifiedMolarFlowKmolph_ = value;
   flowSpecMode_ = FlowSpecMode::MolarFlow;
   applyCanonicalFlowFromActiveSpec_();
   validateAndUpdateStatus_();
   emit flowSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setStandardLiquidVolumeFlowM3ph(double value)
{
   if (!std::isfinite(value) || value < 0.0)
      value = 0.0;
   specifiedStandardLiquidVolumeFlowM3ph_ = value;
   flowSpecMode_ = FlowSpecMode::StdLiquidVolumeFlow;
   applyCanonicalFlowFromActiveSpec_();
   validateAndUpdateStatus_();
   emit flowSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setTemperatureK(double value)
{
   if (!std::isfinite(value)) {
      return;
   }
   if (qFuzzyCompare(temperatureK_, value)) {
      return;
   }
   temperatureK_ = value;
   if (thermoSpecMode_ != ThermoSpecMode::TS && thermoSpecMode_ != ThermoSpecMode::TP)
      thermoSpecMode_ = ThermoSpecMode::TP;
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit temperatureKChanged();
   emit thermoSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setPressurePa(double value)
{
   if (!std::isfinite(value) || value < 0.0) {
      value = 0.0;
   }
   if (qFuzzyCompare(pressurePa_, value)) {
      return;
   }
   pressurePa_ = value;
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit pressurePaChanged();
   emitDerivedConditionsChanged_();
}

QObject* MaterialStreamState::compositionModel() const
{
   return compositionModel_;
}

QVariantList MaterialStreamState::composition() const
{
   QVariantList out;
   out.reserve(static_cast<int>(composition_.size()));
   for (double zi : composition_) {
      out.push_back(zi);
   }
   return out;
}

void MaterialStreamState::setIsCrudeFeed(bool value)
{
   if (isCrudeFeed_ == value) {
      return;
   }

   const bool oldEditable = componentEditingEnabled();
   isCrudeFeed_ = value;

   if (isCrudeFeed_ && m_streamType == StreamType::Product) {
      m_streamType = StreamType::Feed;
      emit streamTypeChanged();
   }
   else if (isCrudeFeed_ && m_streamType == StreamType::Unknown) {
      m_streamType = StreamType::Feed;
      emit streamTypeChanged();
   }

   emit isCrudeFeedChanged();

   if (oldEditable != componentEditingEnabled()) {
      emit componentEditingEnabledChanged();
   }
}

bool MaterialStreamState::componentEditingEnabled() const
{
   return isCrudeFeed_ && m_streamType != StreamType::Product;
}

double MaterialStreamState::massFractionSum() const
{
   return std::accumulate(composition_.begin(), composition_.end(), 0.0);
}

bool MaterialStreamState::massFractionsBalanced() const
{
   return std::fabs(massFractionSum() - 1.0) <= 1e-3;
}

double MaterialStreamState::averageMolecularWeight() const
{
   return mixMassFractionAvgMw(fluidDefinition_.thermo.components, composition_);
}

double MaterialStreamState::molarFlowKmolph() const
{
   if (flowSpecMode_ == FlowSpecMode::MolarFlow && std::isfinite(specifiedMolarFlowKmolph_))
      return specifiedMolarFlowKmolph_;
   const double avgMw = averageMolecularWeight();
   if (!(avgMw > 0.0) || !std::isfinite(avgMw) || !std::isfinite(flowRateKgph_))
      return 0.0;
   return flowRateKgph_ / avgMw;
}

double MaterialStreamState::estimatedBulkDensityKgM3() const
{
   if (std::isfinite(bulkDensityOverrideKgM3_) && bulkDensityOverrideKgM3_ > 0.0)
      return bulkDensityOverrideKgM3_;
   return mixRhoLFromSg(fluidDefinition_.thermo.components, composition_);
}

double MaterialStreamState::volumetricFlowM3ph() const
{
   const double rho = estimatedBulkDensityKgM3();
   if (!(rho > 0.0) || !std::isfinite(rho) || !std::isfinite(flowRateKgph_))
      return 0.0;
   return flowRateKgph_ / rho;
}

double MaterialStreamState::standardLiquidVolumeFlowM3ph() const
{
   if (flowSpecMode_ == FlowSpecMode::StdLiquidVolumeFlow && std::isfinite(specifiedStandardLiquidVolumeFlowM3ph_))
      return specifiedStandardLiquidVolumeFlowM3ph_;
   return volumetricFlowM3ph();
}

double MaterialStreamState::vaporFraction() const
{
   if (!std::isfinite(vaporFraction_))
      return 0.0;
   return std::clamp(vaporFraction_, 0.0, 1.0);
}

double MaterialStreamState::specifiedVaporFraction() const
{
   if (!std::isfinite(specifiedVaporFraction_))
      return 0.0;
   return std::clamp(specifiedVaporFraction_, 0.0, 1.0);
}

double MaterialStreamState::enthalpyKJkg() const
{
   return enthalpyKJkg_;
}

double MaterialStreamState::entropyKJkgK() const
{
   return entropyKJkgK_;
}

QString MaterialStreamState::phaseStatus() const
{
   const double vf = vaporFraction();
   const double eps = 1e-6;
   if (vf <= eps)
      return QStringLiteral("Liquid");
   if (vf >= 1.0 - eps)
      return QStringLiteral("Vapor");
   return QStringLiteral("Two-Phase");
}

QString MaterialStreamState::flashMethod() const
{
   if (isProductStream())
      return QStringLiteral("Set by unit operation");
   return flashMethod_;
}

QString MaterialStreamState::thermoRegionLabel() const
{
   if (!isFeedStream())
      return QStringLiteral("Thermo summary available for feed streams ONLY");

   const double vf = vaporFraction();
   const double eps = 1e-6;
   if (vf <= eps)
      return QStringLiteral("Below bubble region");
   if (vf >= 1.0 - eps)
      return QStringLiteral("Above dew region");
   return QStringLiteral("Inside two-phase envelope");
}

double MaterialStreamState::bubblePointEstimateK() const
{
   return bubblePointEstimateK_;
}

double MaterialStreamState::dewPointEstimateK() const
{
   return dewPointEstimateK_;
}

QString MaterialStreamState::compositionSourceLabel() const
{
   if (isProductStream())
      return QStringLiteral("Source: connected unit operation");
   if (hasCustomComposition_)
      return QStringLiteral("Source: user-edited composition");
   return QStringLiteral("Source: default fluid definition");
}

QString MaterialStreamState::compositionEditStatusLabel() const
{
   if (isProductStream())
      return QStringLiteral("Product stream: composition set by unit operation");
   if (componentEditingEnabled())
      return QStringLiteral("Feed stream: composition is user-editable");
   return QStringLiteral("Composition is currently read-only");
}

void MaterialStreamState::setVaporFraction(double value)
{
   if (!std::isfinite(value))
      value = 0.0;
   value = std::clamp(value, 0.0, 1.0);
   if (qFuzzyCompare(1.0 + vaporFraction_, 1.0 + value))
      return;
   vaporFraction_ = value;
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setSpecifiedVaporFraction(double value)
{
   if (!std::isfinite(value))
      value = 0.0;
   value = std::clamp(value, 0.0, 1.0);
   if (qFuzzyCompare(1.0 + specifiedVaporFraction_, 1.0 + value) && thermoSpecMode_ == ThermoSpecMode::PVF)
      return;
   specifiedVaporFraction_ = value;
   if (thermoSpecMode_ != ThermoSpecMode::PVF)
      thermoSpecMode_ = ThermoSpecMode::PVF;
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit thermoSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setEnthalpyKJkg(double value)
{
   if (qFuzzyCompare(1.0 + enthalpyKJkg_, 1.0 + value) && thermoSpecMode_ == ThermoSpecMode::PH)
      return;
   enthalpyKJkg_ = value;
   if (thermoSpecMode_ != ThermoSpecMode::PH)
      thermoSpecMode_ = ThermoSpecMode::PH;
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit thermoSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setEntropyKJkgK(double value)
{
   if (qFuzzyCompare(1.0 + entropyKJkgK_, 1.0 + value) &&
      (thermoSpecMode_ == ThermoSpecMode::PS || thermoSpecMode_ == ThermoSpecMode::TS))
      return;

   entropyKJkgK_ = value;
   if (thermoSpecMode_ != ThermoSpecMode::TS && thermoSpecMode_ != ThermoSpecMode::PS)
      thermoSpecMode_ = ThermoSpecMode::PS;

   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit thermoSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setBulkDensityOverrideKgM3(double value)
{
   if (!std::isfinite(value) || value <= 0.0)
      value = std::numeric_limits<double>::quiet_NaN();

   const bool same = (std::isfinite(bulkDensityOverrideKgM3_) == std::isfinite(value))
      && (!std::isfinite(value) || qFuzzyCompare(1.0 + bulkDensityOverrideKgM3_, 1.0 + value));
   if (same)
      return;

   bulkDensityOverrideKgM3_ = value;
   validateAndUpdateStatus_();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setFlowSpecMode(FlowSpecMode value)
{
   if (flowSpecMode_ == value)
      return;
   flowSpecMode_ = value;
   if (value == FlowSpecMode::MolarFlow && !std::isfinite(specifiedMolarFlowKmolph_))
      specifiedMolarFlowKmolph_ = averageMwValid() ? (flowRateKgph_ / averageMolecularWeight()) : 0.0;
   if (value == FlowSpecMode::StdLiquidVolumeFlow && !std::isfinite(specifiedStandardLiquidVolumeFlowM3ph_))
      specifiedStandardLiquidVolumeFlowM3ph_ = referenceDensityValid() ? (flowRateKgph_ / estimatedBulkDensityKgM3()) : 0.0;
   applyCanonicalFlowFromActiveSpec_();
   validateAndUpdateStatus_();
   emit flowSpecModeChanged();
   emitDerivedConditionsChanged_();
}

void MaterialStreamState::setThermoSpecMode(ThermoSpecMode value)
{
   if (thermoSpecMode_ == value)
      return;

   thermoSpecMode_ = value;

   if (thermoSpecMode_ == ThermoSpecMode::PVF) {
      double vfSeed = std::numeric_limits<double>::quiet_NaN();
      if (std::isfinite(vaporFraction_))
         vfSeed = std::clamp(vaporFraction_, 0.0, 1.0);
      else if (std::isfinite(specifiedVaporFraction_))
         vfSeed = std::clamp(specifiedVaporFraction_, 0.0, 1.0);

      if (!std::isfinite(vfSeed))
         vfSeed = 0.5;

      specifiedVaporFraction_ = vfSeed;
   }

   emit thermoSpecModeChanged();
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emitDerivedConditionsChanged_();
}

bool MaterialStreamState::temperatureEditable() const
{
   return thermoSpecMode_ == ThermoSpecMode::TP || thermoSpecMode_ == ThermoSpecMode::TS;
}

bool MaterialStreamState::pressureEditable() const
{
   return thermoSpecMode_ != ThermoSpecMode::TS;
}

bool MaterialStreamState::enthalpyEditable() const
{
   return thermoSpecMode_ == ThermoSpecMode::PH;
}

bool MaterialStreamState::entropyEditable() const
{
   return thermoSpecMode_ == ThermoSpecMode::PS || thermoSpecMode_ == ThermoSpecMode::TS;
}

bool MaterialStreamState::vaporFractionEditable() const
{
   return thermoSpecMode_ == ThermoSpecMode::PVF;
}

bool MaterialStreamState::massFlowEditable() const
{
   return flowSpecMode_ == FlowSpecMode::MassFlow;
}

bool MaterialStreamState::molarFlowEditable() const
{
   return flowSpecMode_ == FlowSpecMode::MolarFlow;
}

bool MaterialStreamState::standardLiquidVolumeFlowEditable() const
{
   return flowSpecMode_ == FlowSpecMode::StdLiquidVolumeFlow;
}

void MaterialStreamState::resetToFluidDefaults()
{
   flowSpecMode_ = FlowSpecMode::MassFlow;
   thermoSpecMode_ = ThermoSpecMode::TP;
   flowRateKgph_ = fluidDefinition_.columnDefaults.feedRate_kgph;
   temperatureK_ = fluidDefinition_.columnDefaults.Tfeed_K;
   pressurePa_ = fluidDefinition_.columnDefaults.Ptop_Pa;
   emit flowRateKgphChanged();
   emit temperatureKChanged();
   emit pressurePaChanged();
   emit flowSpecModeChanged();
   emit thermoSpecModeChanged();
}

void MaterialStreamState::resetCompositionToFluidDefault()
{
   std::vector<double> z = fluidDefinition_.thermo.zDefault;
   const std::size_t n = fluidDefinition_.thermo.components.size();
   if (z.size() != n) {
      z.assign(n, n ? 1.0 / static_cast<double>(n) : 0.0);
   }
   applyComposition_(std::move(z), false, false);
}

void MaterialStreamState::normalizeComposition()
{
   applyComposition_(composition_, true, true);
}

void MaterialStreamState::resetComponentPropertiesToFluidDefault()
{
   const auto currentComp = composition_;
   const bool custom = hasCustomComposition_;
   refreshFluidDefinition_();
   applyComposition_(currentComp, custom, false);
}

void MaterialStreamState::clearCustomCompositionEdits()
{
   const auto previousComp = composition_;
   const bool hadCustom = hasCustomComposition_;

   refreshFluidDefinition_();

   resetCompositionToFluidDefault();

   if (hadCustom || !fuzzyVectorEqual(previousComp, composition_)) {
      emitDerivedConditionsChanged_();
   }
}

bool MaterialStreamState::setCompositionStd(const std::vector<double>& value)
{
   return applyComposition_(value, true, false);
}

bool MaterialStreamState::setComponentProperty(int row, const QString& field, double value)
{
   if (!componentEditingEnabled()) {
      return false;
   }
   return setComponentPropertyByKey_(row, field, value);
}

void MaterialStreamState::refreshFluidDefinition_()
{
   if (auto* cm = componentManager_())
      fluidDefinition_ = cm->buildFluidDefinition(selectedFluid_);
   else
      fluidDefinition_ = getFluidDefinition(selectedFluid_.toStdString());
   emit fluidDefinitionChanged();
}

bool MaterialStreamState::applyComposition_(std::vector<double> value, bool customFlag, bool normalize)
{
   const std::size_t n = fluidDefinition_.thermo.components.size();
   if (value.size() != n) {
      if (n == 0) {
         value.clear();
      }
      else {
         return false;
      }
   }

   for (double& zi : value) {
      if (!std::isfinite(zi) || zi < 0.0) {
         zi = 0.0;
      }
   }

   if (normalize && n > 0) {
      const double sum = std::accumulate(value.begin(), value.end(), 0.0);
      if (sum > 0.0) {
         for (double& zi : value) {
            zi /= sum;
         }
      }
   }

   const bool same = fuzzyVectorEqual(composition_, value);
   const bool customChanged = (hasCustomComposition_ != customFlag);
   if (same && !customChanged) {
      return false;
   }

   composition_ = std::move(value);
   hasCustomComposition_ = customFlag;
   recalcFeedPhase_();
   validateAndUpdateStatus_();
   emit compositionChanged();
   emitDerivedConditionsChanged_();
   if (customChanged) {
      emit hasCustomCompositionChanged();
   }
   return true;
}

bool MaterialStreamState::setComponentPropertyByKey_(int row, const QString& field, double value)
{
   auto& comps = fluidDefinition_.thermo.components;
   if (row < 0 || row >= static_cast<int>(comps.size()) || !std::isfinite(value)) {
      return false;
   }

   Component& comp = comps[static_cast<std::size_t>(row)];
   const QString key = field.trimmed().toLower();
   bool changed = false;

   auto assignIfChanged = [&](double& target) {
      if (qFuzzyCompare(1.0 + target, 1.0 + value)) {
         return false;
      }
      target = value;
      return true;
      };

   if (key == QStringLiteral("tb") || key == QStringLiteral("boilingpointk")) {
      changed = assignIfChanged(comp.Tb);
   }
   else if (key == QStringLiteral("mw") || key == QStringLiteral("molecularweight")) {
      changed = assignIfChanged(comp.MW);
   }
   else if (key == QStringLiteral("tc") || key == QStringLiteral("criticaltemperaturek")) {
      changed = assignIfChanged(comp.Tc);
   }
   else if (key == QStringLiteral("pc") || key == QStringLiteral("criticalpressure")) {
      changed = assignIfChanged(comp.Pc);
   }
   else if (key == QStringLiteral("omega")) {
      changed = assignIfChanged(comp.omega);
   }
   else if (key == QStringLiteral("sg") || key == QStringLiteral("specificgravity")) {
      changed = assignIfChanged(comp.SG);
   }
   else if (key == QStringLiteral("delta")) {
      changed = assignIfChanged(comp.delta);
   }

   if (changed) {
      if (auto* cm = componentManager_()) {
         cm->updatePseudoComponentProperty(selectedFluid_, QString::fromStdString(comp.name), key, value);
      }
      emit fluidDefinitionChanged();
      validateAndUpdateStatus_();
      emitDerivedConditionsChanged_();
   }
   return changed;
}

ComponentManager* MaterialStreamState::componentManager_() const
{
   return ComponentManager::instance();
}

MaterialStreamState::StreamType MaterialStreamState::streamType() const
{
   return m_streamType;
}

QString MaterialStreamState::streamTypeLabel() const
{
   switch (m_streamType) {
   case StreamType::Feed: return QStringLiteral("Feed");
   case StreamType::Product: return QStringLiteral("Product");
   default: return QStringLiteral("Unknown");
   }
}

void MaterialStreamState::setStreamType(MaterialStreamState::StreamType type)
{
   if (m_streamType == type)
      return;

   const bool oldEditable = componentEditingEnabled();
   const bool oldIsCrudeFeed = isCrudeFeed_;

   m_streamType = type;

   if (m_streamType == StreamType::Product) {
      isCrudeFeed_ = false;
   }
   else if (m_streamType == StreamType::Feed) {
      recalcFeedPhase_();
   }

   validateAndUpdateStatus_();
   emit streamTypeChanged();

   if (oldIsCrudeFeed != isCrudeFeed_) {
      emit isCrudeFeedChanged();
   }

   if (oldEditable != componentEditingEnabled()) {
      emit componentEditingEnabledChanged();
   }
}

bool MaterialStreamState::isFeedStream() const
{
   return m_streamType == StreamType::Feed;
}

bool MaterialStreamState::isProductStream() const
{
   return m_streamType == StreamType::Product;
}

void MaterialStreamState::setStreamTypeFromConnectionDirection(const QString& direction)
{
   const QString d = direction.trimmed().toLower();

   if (d == "inlet" || d == "feed" || d == "input") {
      setStreamType(StreamType::Feed);
   }
   else if (d == "outlet" || d == "product" || d == "output") {
      setStreamType(StreamType::Product);
   }
   else {
      setStreamType(StreamType::Unknown);
   }
}

void MaterialStreamState::emitDerivedConditionsChanged_()
{
   emit derivedConditionsChanged();
}

bool MaterialStreamState::normalizedComposition_(std::vector<double>& z) const
{
   const auto& comps = fluidDefinition_.thermo.components;
   if (comps.empty() || composition_.empty())
      return false;

   const std::size_t n = std::min(comps.size(), composition_.size());
   if (n == 0)
      return false;

   z.assign(n, 0.0);
   double zsum = 0.0;
   for (std::size_t i = 0; i < n; ++i) {
      z[i] = std::isfinite(composition_[i]) && composition_[i] > 0.0 ? composition_[i] : 0.0;
      zsum += z[i];
   }
   if (!(zsum > 0.0))
      return false;
   for (double& zi : z)
      zi /= zsum;
   return true;
}

void MaterialStreamState::applyCanonicalFlowFromActiveSpec_()
{
   if (flowSpecMode_ == FlowSpecMode::MassFlow)
      return;

   const double old = flowRateKgph_;
   if (flowSpecMode_ == FlowSpecMode::MolarFlow) {
      const double avgMw = averageMolecularWeight();
      if (std::isfinite(specifiedMolarFlowKmolph_) && specifiedMolarFlowKmolph_ >= 0.0 && std::isfinite(avgMw) && avgMw > 0.0)
         flowRateKgph_ = specifiedMolarFlowKmolph_ * avgMw;
   }
   else if (flowSpecMode_ == FlowSpecMode::StdLiquidVolumeFlow) {
      const double rho = estimatedBulkDensityKgM3();
      if (std::isfinite(specifiedStandardLiquidVolumeFlowM3ph_) && specifiedStandardLiquidVolumeFlowM3ph_ >= 0.0 && std::isfinite(rho) && rho > 0.0)
         flowRateKgph_ = specifiedStandardLiquidVolumeFlowM3ph_ * rho;
   }
   if (!qFuzzyCompare(1.0 + old, 1.0 + flowRateKgph_))
      emit flowRateKgphChanged();
}

void MaterialStreamState::validateAndUpdateStatus_()
{
   std::vector<double> z;
   compositionValid_ = normalizedComposition_(z);
   const double avgMw = compositionValid_ ? mixMassFractionAvgMw(fluidDefinition_.thermo.components, z) : std::numeric_limits<double>::quiet_NaN();
   averageMwValid_ = std::isfinite(avgMw) && avgMw > 0.0;
   const double rho = compositionValid_ ? estimatedBulkDensityKgM3() : std::numeric_limits<double>::quiet_NaN();
   referenceDensityValid_ = std::isfinite(rho) && rho > 0.0;

   if (isProductStream()) {
      flowInputsSufficient_ = true;
      thermoInputsSufficient_ = false;
      streamSolvable_ = false;
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Product stream: values are supplied by the connected unit operation");
      return;
   }

   const QString existingError = specificationError_;
   QString baseError;

   switch (flowSpecMode_) {
   case FlowSpecMode::MassFlow:
      flowInputsSufficient_ = std::isfinite(flowRateKgph_) && flowRateKgph_ >= 0.0;
      break;
   case FlowSpecMode::MolarFlow:
      flowInputsSufficient_ = std::isfinite(specifiedMolarFlowKmolph_) && specifiedMolarFlowKmolph_ >= 0.0 && averageMwValid_;
      if (!flowInputsSufficient_)
         baseError = QStringLiteral("Incomplete: molar flow entered, waiting for valid composition / molecular weights to calculate mass flow");
      break;
   case FlowSpecMode::StdLiquidVolumeFlow:
      flowInputsSufficient_ = std::isfinite(specifiedStandardLiquidVolumeFlowM3ph_) && specifiedStandardLiquidVolumeFlowM3ph_ >= 0.0 && referenceDensityValid_;
      if (!flowInputsSufficient_)
         baseError = QStringLiteral("Incomplete: std. liquid volume flow entered, waiting for valid composition / density to calculate mass flow");
      break;
   }

   switch (thermoSpecMode_) {
   case ThermoSpecMode::TP:
      thermoInputsSufficient_ = compositionValid_ && std::isfinite(temperatureK_) && std::isfinite(pressurePa_) && pressurePa_ > 0.0;
      if (!compositionValid_) baseError = QStringLiteral("Incomplete: composition required");
      else if (!(std::isfinite(pressurePa_) && pressurePa_ > 0.0)) baseError = QStringLiteral("Incomplete: positive pressure required for TP flash");
      else if (!std::isfinite(temperatureK_)) baseError = QStringLiteral("Incomplete: temperature required for TP flash");
      break;
   case ThermoSpecMode::PH:
      thermoInputsSufficient_ = compositionValid_ && std::isfinite(enthalpyKJkg_) && std::isfinite(pressurePa_) && pressurePa_ > 0.0;
      if (!compositionValid_) baseError = QStringLiteral("Incomplete: composition required");
      else if (!(std::isfinite(pressurePa_) && pressurePa_ > 0.0)) baseError = QStringLiteral("Incomplete: positive pressure required for PH flash");
      else if (!std::isfinite(enthalpyKJkg_)) baseError = QStringLiteral("Incomplete: enthalpy required for PH flash");
      break;
   case ThermoSpecMode::PVF:
      thermoInputsSufficient_ = compositionValid_ && std::isfinite(specifiedVaporFraction_) && std::isfinite(pressurePa_) && pressurePa_ > 0.0;
      if (!compositionValid_) baseError = QStringLiteral("Incomplete: composition required");
      else if (!(std::isfinite(pressurePa_) && pressurePa_ > 0.0)) baseError = QStringLiteral("Incomplete: positive pressure required for PVF flash");
      else if (!std::isfinite(specifiedVaporFraction_)) baseError = QStringLiteral("Incomplete: vapor fraction required for PVF flash");
      else if (specifiedVaporFraction_ < 0.0 || specifiedVaporFraction_ > 1.0) baseError = QStringLiteral("Incomplete: vapor fraction must be between 0 and 1");
      break;
   case ThermoSpecMode::PS:
      thermoInputsSufficient_ = compositionValid_
         && std::isfinite(pressurePa_) && pressurePa_ > 0.0
         && std::isfinite(entropyKJkgK_);
      if (!compositionValid()) baseError = QStringLiteral("Incomplete: valid composition required for PS flash");
      else if (!(std::isfinite(pressurePa_) && pressurePa_ > 0.0)) baseError = QStringLiteral("Incomplete: positive pressure required for PS flash");
      else if (!std::isfinite(entropyKJkgK_)) baseError = QStringLiteral("Incomplete: entropy required for PS flash");
      break;
   case ThermoSpecMode::TS:
      thermoInputsSufficient_ = compositionValid_
         && std::isfinite(temperatureK_)
         && std::isfinite(entropyKJkgK_);
      if (!compositionValid()) baseError = QStringLiteral("Incomplete: valid composition required for TS flash");
      else if (!std::isfinite(temperatureK_)) baseError = QStringLiteral("Incomplete: temperature required for TS flash");
      else if (!std::isfinite(entropyKJkgK_)) baseError = QStringLiteral("Incomplete: entropy required for TS flash");
      break;
   }

   streamSolvable_ = flowInputsSufficient_ && thermoInputsSufficient_;

   if (!baseError.isEmpty()) {
      specificationError_ = baseError;
      specificationStatus_ = baseError;
      return;
   }

   specificationError_ = existingError;

   if (thermoSpecMode_ == ThermoSpecMode::PVF) {
      if (flashMethod_.startsWith(QStringLiteral("PVF flash failed"))) {
         specificationStatus_ = flashMethod_;
         if (specificationError_.isEmpty())
            specificationError_ = flashMethod_;
         return;
      }
      if (flashMethod_.startsWith(QStringLiteral("PVF flash"))) {
         specificationStatus_ = QStringLiteral("Solved using PVF flash");
         return;
      }
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Ready for PVF solve");
      return;
   }

   if (thermoSpecMode_ == ThermoSpecMode::PH) {
      if (flashMethod_.startsWith(QStringLiteral("PH flash failed"))) {
         specificationStatus_ = flashMethod_;
         if (specificationError_.isEmpty())
            specificationError_ = flashMethod_;
         return;
      }
      if (flashMethod_.startsWith(QStringLiteral("PH flash"))) {
         specificationError_.clear();
         specificationStatus_ = QStringLiteral("Solved using PH flash");
         return;
      }
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Ready for PH solve");
      return;
   }

   if (thermoSpecMode_ == ThermoSpecMode::TP) {
      if (flashMethod_.startsWith(QStringLiteral("PT flash"))) {
         specificationError_.clear();
         specificationStatus_ = QStringLiteral("Solved using TP flash");
         return;
      }
      if (flashMethod_.startsWith(QStringLiteral("No flash")) ||
         flashMethod_.startsWith(QStringLiteral("EOS flash unavailable")) ||
         flashMethod_.startsWith(QStringLiteral("Heuristic flash fallback"))) {
         specificationStatus_ = flashMethod_;
         if (specificationError_.isEmpty() && !flashMethod_.startsWith(QStringLiteral("PT flash")))
            specificationError_.clear();
         return;
      }
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Ready for TP solve");
      return;
   }

   if (thermoSpecMode_ == ThermoSpecMode::PS) {
      if (flashMethod_.startsWith(QStringLiteral("PS flash failed"))) {
         specificationStatus_ = flashMethod_;
         if (specificationError_.isEmpty())
            specificationError_ = flashMethod_;
         return;
      }
      if (flashMethod_.startsWith(QStringLiteral("PS flash"))) {
         specificationError_.clear();
         specificationStatus_ = QStringLiteral("Solved using PS flash");
         return;
      }
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Ready for PS solve");
      return;
   }

   if (thermoSpecMode_ == ThermoSpecMode::TS) {
      if (flashMethod_.startsWith(QStringLiteral("TS flash failed"))) {
         specificationStatus_ = flashMethod_;
         if (specificationError_.isEmpty())
            specificationError_ = flashMethod_;
         return;
      }
      if (flashMethod_.startsWith(QStringLiteral("TS flash"))) {
         specificationError_.clear();
         specificationStatus_ = QStringLiteral("Solved using TS flash");
         return;
      }
      specificationError_.clear();
      specificationStatus_ = QStringLiteral("Ready for TS solve");
      return;
   }

   specificationError_.clear();
   specificationStatus_ = QStringLiteral("Ready");
}

void MaterialStreamState::recalcFeedPhase_()
{
   if (!isFeedStream()) {
      validateAndUpdateStatus_();
      return;
   }

   const double oldPressurePa = pressurePa_;

   applyCanonicalFlowFromActiveSpec_();
   if (pressurePa_ <= 0.0) {
      flashMethod_ = QStringLiteral("No flash: invalid pressure");
      specificationError_.clear();
      liqComposition_.clear();
      vapComposition_.clear();
      phaseProps_ = StreamPhaseProps{};
      validateAndUpdateStatus_();
      return;
   }

   const auto& comps = fluidDefinition_.thermo.components;
   std::vector<double> z;
   if (!normalizedComposition_(z)) {
      flashMethod_ = QStringLiteral("EOS flash unavailable");
      specificationError_.clear();
      bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
      dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
      liqComposition_.clear();
      vapComposition_.clear();
      phaseProps_ = StreamPhaseProps{};
      setVaporFraction(0.0);
      validateAndUpdateStatus_();
      return;
   }

   try {
      const auto satEOS = estimateBubbleDewFromEOS(pressurePa_, z, comps);
      const auto satScan = estimateBubbleDewFromPTScan(
         pressurePa_, z, comps, selectedFluid_.toStdString(), &fluidDefinition_.thermo.kij);
      bubblePointEstimateK_ = std::isfinite(satScan.bubbleK) ? satScan.bubbleK : satEOS.bubbleK;
      dewPointEstimateK_ = std::isfinite(satScan.dewK) ? satScan.dewK : satEOS.dewK;

      double solvedT = temperatureK_;
      QString method;

      specificationError_.clear();

      if (thermoSpecMode_ == ThermoSpecMode::PH) {
         if (!std::isfinite(enthalpyKJkg_)) {
            flashMethod_ = QStringLiteral("PH flash unavailable: invalid enthalpy");
            specificationError_.clear();
            validateAndUpdateStatus_();
            return;
         }
         FlashPHInput in;
         in.Htarget = enthalpyKJkg_;
         in.z = z;
         in.P = pressurePa_;
         in.Tseed = std::isfinite(temperatureK_) ? temperatureK_ : (std::isfinite(bubblePointEstimateK_) ? bubblePointEstimateK_ : 500.0);
         in.components = &comps;
         in.eosMode = "manual";
         in.eosManual = "PRSV";
         const auto ph = flashPH(in);
         if (std::isfinite(ph.T)) {
            solvedT = ph.T;
            temperatureK_ = solvedT;
            vaporFraction_ = std::clamp(ph.V, 0.0, 1.0);
            enthalpyKJkg_ = ph.Hcalc;
            entropyKJkgK_ = ph.Scalc;
            specifiedVaporFraction_ = vaporFraction_;
            liqComposition_ = ph.x;
            vapComposition_ = ph.y;
            method = QStringLiteral("PH flash (%1)").arg(QString::fromStdString(ph.status.empty() ? std::string("PRSV") : ph.status));
         }
         else {
            flashMethod_ = QStringLiteral("PH flash failed");
            specificationError_ = QStringLiteral("PH flash failed to converge");
            validateAndUpdateStatus_();
            return;
         }
      }
      else if (thermoSpecMode_ == ThermoSpecMode::PVF) {
         const double targetVF = specifiedVaporFraction_;

         auto solveAtT = [&](double T) {
            return flashPT(pressurePa_, T, z, &comps, -1, 32, selectedFluid_.toStdString(), &fluidDefinition_.thermo.kij, 1.0, "manual", "PRSV");
            };

         const double minTwoPhaseSpanK = 1.0;
         const double endpointVfTol = 0.05;
         const double middleVfTol = 0.02;
         const bool bubbleValid = std::isfinite(bubblePointEstimateK_) && bubblePointEstimateK_ >= 200.0 && bubblePointEstimateK_ <= 1200.0;
         const bool dewValid = std::isfinite(dewPointEstimateK_) && dewPointEstimateK_ >= 200.0 && dewPointEstimateK_ <= 1200.0;
         const bool validTwoPhaseWindow = bubbleValid && dewValid && (dewPointEstimateK_ > bubblePointEstimateK_ + minTwoPhaseSpanK);

         if (targetVF <= 0.0) {
            const double liquidT = bubbleValid ? bubblePointEstimateK_ : (std::isfinite(temperatureK_) ? temperatureK_ : 300.0);
            solvedT = liquidT;
            const auto pt = solveAtT(solvedT);
            if (!std::isfinite(pt.V) || pt.V > endpointVfTol) {
               flashMethod_ = QStringLiteral("PVF flash failed: no valid liquid-side state at this P/z/VF");
               specificationError_ = QStringLiteral("Requested VF<=0, but PT evaluation did not produce a liquid-side state at current pressure/composition");
               validateAndUpdateStatus_();
               emitDerivedConditionsChanged_();
               return;
            }
            temperatureK_ = solvedT;
            vaporFraction_ = 0.0;
            specifiedVaporFraction_ = 0.0;
            enthalpyKJkg_ = pt.H;
            entropyKJkgK_ = pt.S;
            liqComposition_ = pt.x;
            vapComposition_ = pt.y;
            method = QStringLiteral("PVF flash (liquid-side limit)");
         }
         else if (targetVF >= 1.0) {
            const double vaporT = dewValid ? dewPointEstimateK_ : (std::isfinite(temperatureK_) ? temperatureK_ : 800.0);
            solvedT = vaporT;
            const auto pt = solveAtT(solvedT);
            if (!std::isfinite(pt.V) || pt.V < 1.0 - endpointVfTol) {
               flashMethod_ = QStringLiteral("PVF flash failed: no valid vapor-side state at this P/z/VF");
               specificationError_ = QStringLiteral("Requested VF>=1, but PT evaluation did not produce a vapor-side state at current pressure/composition");
               validateAndUpdateStatus_();
               emitDerivedConditionsChanged_();
               return;
            }
            temperatureK_ = solvedT;
            vaporFraction_ = 1.0;
            specifiedVaporFraction_ = 1.0;
            enthalpyKJkg_ = pt.H;
            entropyKJkgK_ = pt.S;
            liqComposition_ = pt.x;
            vapComposition_ = pt.y;
            method = QStringLiteral("PVF flash (vapor-side limit)");
         }
         else {
            if (!validTwoPhaseWindow) {
               flashMethod_ = QStringLiteral("PVF flash failed: no valid two-phase solution at this P/z/VF");
               specificationError_ = QStringLiteral("Bubble/dew temperature window is invalid or degenerate at current pressure/composition");
               validateAndUpdateStatus_();
               emitDerivedConditionsChanged_();
               return;
            }
            double lo = std::isfinite(bubblePointEstimateK_) ? bubblePointEstimateK_ - 40.0 : 250.0;
            double hi = std::isfinite(dewPointEstimateK_) ? dewPointEstimateK_ + 40.0 : 950.0;
            lo = std::max(200.0, lo);
            hi = std::min(1200.0, hi);
            auto vfResid = [&](double T) -> double {
               const auto pt = solveAtT(T);
               if (!std::isfinite(pt.V))
                  return std::numeric_limits<double>::quiet_NaN();
               return pt.V - targetVF;
               };
            double fLo = vfResid(lo);
            double fHi = vfResid(hi);
            bool bracketed = std::isfinite(fLo) && std::isfinite(fHi) && fLo * fHi <= 0.0;
            if (!bracketed) {
               const double step = 25.0;
               double bestLo = lo, bestHi = hi;
               double prevT = lo;
               double prevF = fLo;
               for (double T = lo + step; T <= hi; T += step) {
                  const double f = vfResid(T);
                  if (std::isfinite(prevF) && std::isfinite(f) && prevF * f <= 0.0) {
                     bestLo = prevT; bestHi = T; bracketed = true; break;
                  }
                  prevT = T; prevF = f;
               }
               if (bracketed) {
                  lo = bestLo;
                  hi = bestHi;
                  fLo = vfResid(lo);
                  fHi = vfResid(hi);
               }
            }
            if (!bracketed) {
               flashMethod_ = QStringLiteral("PVF flash failed: could not bracket temperature");
               specificationError_ = QStringLiteral("Target vapor fraction not bracketed at current pressure/composition");
               validateAndUpdateStatus_();
               emitDerivedConditionsChanged_();
               return;
            }
            const double solved = bisectTemperature(vfResid, lo, hi);
            if (std::isfinite(solved)) {
               const auto pt = solveAtT(solved);
               const double Vsolved = pt.V;
               if (!std::isfinite(Vsolved) || std::fabs(Vsolved - targetVF) > middleVfTol) {
                  flashMethod_ = QStringLiteral("PVF flash failed: no valid two-phase solution at this P/z/VF");
                  specificationError_ = QStringLiteral("Solved temperature did not reproduce the requested vapor fraction within tolerance");
                  validateAndUpdateStatus_();
                  emitDerivedConditionsChanged_();
                  return;
               }
               solvedT = solved;
               temperatureK_ = solvedT;
               vaporFraction_ = std::clamp(Vsolved, 0.0, 1.0);
               specifiedVaporFraction_ = targetVF;
               enthalpyKJkg_ = pt.H;
               entropyKJkgK_ = pt.S;
               liqComposition_ = pt.x;
               vapComposition_ = pt.y;
               method = QStringLiteral("PVF flash (PT root solve / PRSV)");
            }
            else {
               flashMethod_ = QStringLiteral("PVF flash failed: failed to converge");
               specificationError_ = QStringLiteral("PVF flash failed to converge");
               validateAndUpdateStatus_();
               emitDerivedConditionsChanged_();
               return;
            }
         }
      }
      else if (thermoSpecMode_ == ThermoSpecMode::PS) {
         FlashPSInput in;
         in.Starget = entropyKJkgK_;
         in.z = z;
         in.P = pressurePa_;
         in.Tseed = std::isfinite(temperatureK_) ? temperatureK_ : (std::isfinite(bubblePointEstimateK_) ? bubblePointEstimateK_ : 500.0);
         in.components = &comps;
         in.kij = &fluidDefinition_.thermo.kij;
         in.crudeName = selectedFluid_.toStdString();
         in.eosMode = "manual";
         in.eosManual = "PRSV";
         const auto ps = flashPS(in);
         if (std::isfinite(ps.T)) {
            solvedT = ps.T;
            temperatureK_ = solvedT;
            vaporFraction_ = std::clamp(ps.V, 0.0, 1.0);
            specifiedVaporFraction_ = vaporFraction_;
            enthalpyKJkg_ = ps.Hcalc;
            entropyKJkgK_ = ps.Scalc;
            liqComposition_ = ps.x;
            vapComposition_ = ps.y;
            method = QStringLiteral("PS flash (%1)").arg(QString::fromStdString(ps.status.empty() ? std::string("PRSV") : ps.status));
         }
         else {
            flashMethod_ = QStringLiteral("PS flash failed");
            specificationError_ = QStringLiteral("PS flash failed to converge");
            validateAndUpdateStatus_();
            return;
         }
      }
      else if (thermoSpecMode_ == ThermoSpecMode::TS) {
         FlashTSInput in;
         in.Starget = entropyKJkgK_;
         in.z = z;
         in.T = temperatureK_;
         in.Pseed = std::isfinite(pressurePa_) && pressurePa_ > 0.0 ? pressurePa_
            : 101325.0;
         in.components = &comps;
         in.kij = &fluidDefinition_.thermo.kij;
         in.crudeName = selectedFluid_.toStdString();
         in.eosMode = "manual";
         in.eosManual = "PRSV";
         const auto ts = flashTS(in);
         if (std::isfinite(ts.P) && ts.P > 0.0) {
            pressurePa_ = ts.P;
            vaporFraction_ = std::clamp(ts.V, 0.0, 1.0);
            specifiedVaporFraction_ = vaporFraction_;
            enthalpyKJkg_ = ts.Hcalc;
            entropyKJkgK_ = ts.Scalc;
            liqComposition_ = ts.x;
            vapComposition_ = ts.y;
            method = QStringLiteral("TS flash (%1)").arg(QString::fromStdString(ts.status.empty() ? std::string("PRSV") : ts.status));
         }
         else {
            flashMethod_ = QStringLiteral("TS flash failed");
            specificationError_ = QStringLiteral("TS flash failed to converge");
            validateAndUpdateStatus_();
            return;
         }
      }
      else {
         const auto pt = flashPT(pressurePa_, temperatureK_, z, &comps, -1, 32, selectedFluid_.toStdString(), &fluidDefinition_.thermo.kij, 1.0, "manual", "PRSV");
         vaporFraction_ = std::clamp(pt.V, 0.0, 1.0);
         specifiedVaporFraction_ = vaporFraction_;
         enthalpyKJkg_ = pt.H;
         entropyKJkgK_ = pt.S;
         liqComposition_ = pt.x;
         vapComposition_ = pt.y;
         method = QStringLiteral("PT flash (PRSV)");
      }

      if (thermoSpecMode_ != ThermoSpecMode::TP) {
         emit temperatureKChanged();
      }
      if (!qFuzzyCompare(1.0 + oldPressurePa, 1.0 + pressurePa_)) {
         emit pressurePaChanged();
      }

      // Compute all derived phase properties (density, viscosity, k, Cp, etc.)
      // from the phase compositions captured above.  This runs once regardless
      // of which flash spec mode was used.
      phaseProps_ = calcStreamProperties(
         temperatureK_,
         pressurePa_,
         z,
         liqComposition_,
         vapComposition_,
         vaporFraction_,
         flowRateKgph_,
         comps
      );

      flashMethod_ = method;
      specificationError_.clear();
      validateAndUpdateStatus_();
      emitDerivedConditionsChanged_();
   }
   catch (...) {
      double Tb_avg = 0.0;
      double wsum = 0.0;
      for (std::size_t i = 0; i < z.size(); ++i) {
         const double zi = z[i];
         const double Tb = comps[i].Tb;
         if (!(zi > 0.0) || !std::isfinite(Tb) || Tb <= 0.0)
            continue;
         Tb_avg += zi * Tb;
         wsum += zi;
      }
      if (!(wsum > 0.0)) {
         flashMethod_ = QStringLiteral("Heuristic flash fallback");
         specificationError_.clear();
         bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
         dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
         liqComposition_.clear();
         vapComposition_.clear();
         phaseProps_ = StreamPhaseProps{};
         setVaporFraction(0.0);
         validateAndUpdateStatus_();
         return;
      }
      Tb_avg /= wsum;
      bubblePointEstimateK_ = Tb_avg - 10.0;
      dewPointEstimateK_ = Tb_avg + 10.0;
      double vaporFrac = 0.0;
      if (temperatureK_ <= Tb_avg - 20.0)
         vaporFrac = 0.0;
      else if (temperatureK_ >= Tb_avg + 20.0)
         vaporFrac = 1.0;
      else
         vaporFrac = (temperatureK_ - (Tb_avg - 20.0)) / 40.0;
      flashMethod_ = QStringLiteral("Heuristic flash fallback");
      specificationError_.clear();
      setVaporFraction(vaporFrac);
      enthalpyKJkg_ = std::numeric_limits<double>::quiet_NaN();
      entropyKJkgK_ = std::numeric_limits<double>::quiet_NaN();
      liqComposition_.clear();
      vapComposition_.clear();
      phaseProps_ = StreamPhaseProps{};
      validateAndUpdateStatus_();
   }
}

bool MaterialStreamState::compositionValid() const
{
   return compositionValid_;
}

bool MaterialStreamState::averageMwValid() const
{
   return averageMwValid_;
}

bool MaterialStreamState::referenceDensityValid() const
{
   return referenceDensityValid_;
}

bool MaterialStreamState::flowInputsSufficient() const
{
   return flowInputsSufficient_;
}

bool MaterialStreamState::thermoInputsSufficient() const
{
   return thermoInputsSufficient_;
}

bool MaterialStreamState::streamSolvable() const
{
   return streamSolvable_;
}

QString MaterialStreamState::specificationStatus() const
{
   return specificationStatus_;
}

QString MaterialStreamState::specificationError() const
{
   return specificationError_;
}

QVariantList MaterialStreamState::kValuesData() const
{
   QVariantList out;
   const auto& comps = fluidDefinition_.thermo.components;
   const std::size_t n = comps.size();

   // Only meaningful when we have valid phase compositions from a flash
   if (liqComposition_.size() != n || vapComposition_.size() != n || n == 0)
      return out;

   for (std::size_t i = 0; i < n; ++i) {
      const double xi = liqComposition_[i];
      const double yi = vapComposition_[i];

      // K = y/x — only defined when both phases are present with non-trivial x
      double K = std::numeric_limits<double>::quiet_NaN();
      if (std::isfinite(xi) && xi > 1e-10 &&
         std::isfinite(yi) && yi >= 0.0) {
         K = yi / xi;
      }

      QVariantMap row;
      row[QStringLiteral("name")] = QString::fromStdString(comps[i].name);
      row[QStringLiteral("x")] = xi;
      row[QStringLiteral("y")] = yi;
      row[QStringLiteral("K")] = K;
      out.append(row);
   }
   return out;
}