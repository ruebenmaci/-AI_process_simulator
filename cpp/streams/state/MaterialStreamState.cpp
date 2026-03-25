#include "MaterialStreamState.h"

#include "../models/StreamCompositionModel.h"

#include <QtGlobal>

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>

#include "../../thermo/EOSK.hpp"
#include "../../thermo/Flash.hpp"

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

static double bisectTemperature(const std::function<double(double)>& f, double lo, double hi)
{
    double flo = f(lo);
    double fhi = f(hi);
    if (!std::isfinite(flo) || !std::isfinite(fhi) || flo * fhi > 0.0)
        return std::numeric_limits<double>::quiet_NaN();

    for (int iter = 0; iter < 40; ++iter) {
        const double mid = 0.5 * (lo + hi);
        const double fm = f(mid);
        if (!std::isfinite(fm))
            return std::numeric_limits<double>::quiet_NaN();
        if (std::fabs(fm) < 1e-6 || std::fabs(hi - lo) < 1e-3)
            return mid;
        if (flo * fm <= 0.0) {
            hi = mid;
            fhi = fm;
        } else {
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


MaterialStreamState::MaterialStreamState(QObject* parent)
    : QObject(parent)
{
    compositionModel_ = new StreamCompositionModel(this, this);
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
    if (qFuzzyCompare(flowRateKgph_, value)) {
        return;
    }
    flowRateKgph_ = value;
    emit flowRateKgphChanged();
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
   recalcFeedPhase_();
   emit temperatureKChanged();
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

double MaterialStreamState::vaporFraction() const
{
    if (!std::isfinite(vaporFraction_))
        return 0.0;
    return std::clamp(vaporFraction_, 0.0, 1.0);
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

void MaterialStreamState::setBulkDensityOverrideKgM3(double value)
{
    if (!std::isfinite(value) || value <= 0.0)
        value = std::numeric_limits<double>::quiet_NaN();

    const bool same = (std::isfinite(bulkDensityOverrideKgM3_) == std::isfinite(value))
        && (!std::isfinite(value) || qFuzzyCompare(1.0 + bulkDensityOverrideKgM3_, 1.0 + value));
    if (same)
        return;

    bulkDensityOverrideKgM3_ = value;
    emitDerivedConditionsChanged_();
}

void MaterialStreamState::resetToFluidDefaults()
{
    setFlowRateKgph(fluidDefinition_.columnDefaults.feedRate_kgph);
    setTemperatureK(fluidDefinition_.columnDefaults.Tfeed_K);
    setPressurePa(fluidDefinition_.columnDefaults.Ptop_Pa);
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
    fluidDefinition_ = getFluidDefinition(selectedFluid_.toStdString());
    emit fluidDefinitionChanged();
    applyComposition_(currentComp, custom, false);
}

void MaterialStreamState::clearCustomCompositionEdits()
{
    const auto previousComp = composition_;
    const bool hadCustom = hasCustomComposition_;

    fluidDefinition_ = getFluidDefinition(selectedFluid_.toStdString());
    emit fluidDefinitionChanged();

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
    } else if (key == QStringLiteral("mw") || key == QStringLiteral("molecularweight")) {
        changed = assignIfChanged(comp.MW);
    } else if (key == QStringLiteral("tc") || key == QStringLiteral("criticaltemperaturek")) {
        changed = assignIfChanged(comp.Tc);
    } else if (key == QStringLiteral("pc") || key == QStringLiteral("criticalpressure")) {
        changed = assignIfChanged(comp.Pc);
    } else if (key == QStringLiteral("omega")) {
        changed = assignIfChanged(comp.omega);
    } else if (key == QStringLiteral("sg") || key == QStringLiteral("specificgravity")) {
        changed = assignIfChanged(comp.SG);
    } else if (key == QStringLiteral("delta")) {
        changed = assignIfChanged(comp.delta);
    }

    if (changed) {
        emit fluidDefinitionChanged();
        emitDerivedConditionsChanged_();
    }
    return changed;
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

void MaterialStreamState::recalcFeedPhase_()
{
   if (!isFeedStream())
      return;

   if (temperatureK_ <= 0.0 || pressurePa_ <= 0.0)
      return;

   const auto& comps = fluidDefinition_.thermo.components;
   if (comps.empty() || composition_.empty())
      return;

   const std::size_t n = std::min(comps.size(), composition_.size());
   if (n == 0)
      return;

   std::vector<double> z(n, 0.0);
   double zsum = 0.0;
   for (std::size_t i = 0; i < n; ++i) {
      z[i] = std::isfinite(composition_[i]) && composition_[i] > 0.0 ? composition_[i] : 0.0;
      zsum += z[i];
   }
   if (!(zsum > 0.0)) {
      flashMethod_ = QStringLiteral("EOS flash unavailable");
      bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
      dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
      setVaporFraction(0.0);
      return;
   }
   for (double& zi : z)
      zi /= zsum;

   try {
      const auto ek = eosK(pressurePa_, temperatureK_, z, comps, -1, 32, {}, nullptr, false, 1.0, "manual", "PRSV");
      const RRResult rr = rachfordRice(z, ek.K);

      double vf = rr.V;
      if (!std::isfinite(vf))
         vf = 0.0;
      setVaporFraction(vf);

      QString method = QStringLiteral("EOS flash (PRSV/RR)");
      if (!ek.eos.empty())
         method = QStringLiteral("EOS flash (%1/RR)").arg(QString::fromStdString(ek.eos));
      if (rr.status == "singlePhase")
         method += QStringLiteral(" - single phase");
      flashMethod_ = method;

      const auto sat = estimateBubbleDewFromEOS(pressurePa_, z, comps);
      bubblePointEstimateK_ = sat.bubbleK;
      dewPointEstimateK_ = sat.dewK;
   }
   catch (...) {
      double Tb_avg = 0.0;
      double wsum = 0.0;
      for (std::size_t i = 0; i < n; ++i) {
         const double zi = z[i];
         const double Tb = comps[i].Tb;
         if (!(zi > 0.0) || !std::isfinite(Tb) || Tb <= 0.0)
            continue;
         Tb_avg += zi * Tb;
         wsum += zi;
      }
      if (!(wsum > 0.0)) {
         flashMethod_ = QStringLiteral("Heuristic flash fallback");
         bubblePointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
         dewPointEstimateK_ = std::numeric_limits<double>::quiet_NaN();
         setVaporFraction(0.0);
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
      setVaporFraction(vaporFrac);
   }
}