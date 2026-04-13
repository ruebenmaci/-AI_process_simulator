#include "ColumnUnitState.h"
#include "flowsheet/state/FlowsheetState.h"

#include <QtCore/QDebug>
#include <cmath>
#include <algorithm>
#include <limits>
#include <sstream>
#include <QtCore/QString>
#include <QVariantMap>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QTimer>
#include <QPointer>
#include <QMetaObject>
#include <QMutexLocker>
#include <QtConcurrent/QtConcurrent>
#include <QCoreApplication>
#include <QStringConverter>
#include <QFileInfo>
#include <QSaveFile>
#include <QRegularExpression>

#include "streams/state/StreamUnitState.h"
#include "unitops/column/config/CrudeInitialSettings.hpp"
#include "../../thermo/pseudocomponents/FluidDefinition.hpp"
#include "../../thermo/ThermoConfig.hpp"
#include "unitops/column/sim/ColumnSolver.hpp"
#include "../../../thermo/EOSK.hpp"
#include "../../../thermo/eos/PRSV.hpp"
#include "../../../fluid/FluidPackageManager.h"

static constexpr int MAX_LOG_BUFFER_LINES = 5000;

bool allowSummaryTag(const QString& s)
{
   static const QStringList allowed = {
      //"[BASIS_CHECK]",
      "[CONVERGED]",
      "[DRAW]",
      "[DRAW_CHECK]",
      //"[DRAW_EQUALITY]",
      //"[DRAW_MISMATCH]",
      //"[DrawSpecs UI]",
      //"[DrawSpecs Solver]",
      "[FAILED]",
      //"[LOG]",
      "[FLASH_WARN]",
      //"[HDEP]",
      "[EOSK]",
      "[EOSK_WARN]",
      //"[EOSK_ETA_IN]",
      //"[EOSK_FLOOR]",
      //"[EOSK_SEED]",
      //"[EOSK_PHI]",
      //"[EOSK_KDIAG]",
      "[EQTP]",
      //"[HDEP]",
      "[HDR]",
      //"[K_DEBUG]",
      "[ITER]",
      //"[K_DEBUG]",
      //"[PH]",
      "[PH_COMP]",
      "[PH_ENTER]",
      "[PH_BRACKET]",
      "[PH_FLASH_IN]",
      //"[PH_KSRC]",
      "[PH_OUT]",
      "[PH_RESID_SUM]",
      //"[PH_SEED_CHECK]",
      "[PH_XEVAL]",
      "[PH_Z]",
      //"[PRSV_DIAG]",
      //"[PRSV_INFO]",
      //"[PRSV_ROOTS]",
      //"[PRSV_WARN]",
      "[RRDIAG]",
      "[RR_SIGN]",
      "[SCALE]",
      //"[SCALE_PRODUCTS]",
      "[SIDE_DRAW]",
      //"[TRAFFIC_CLAMP]",
      "[UNITS]",
   };

   for (const auto& p : allowed)
      if (s.startsWith(p))
         return true;
   return false;
}

ColumnUnitState::ColumnUnitState(QObject* parent)
   : ProcessUnitState(parent)
   , feedStream_(this)
   , trayModel_(this)
   , diagnosticsModel_(this)
   , runLogModel_(this)
   , mbModel_(this)
{
   crudeNames_ = feedStream_.fluidNames();

   attachActiveFeedStreamSignals_();
   applyCrudeDefaults(activeFeedStream()->selectedFluid());

   // --- async solve timing + completion wiring ---
   solveUiTick_.setInterval(100);
   connect(&solveUiTick_, &QTimer::timeout, this, [this]()
      {
         if (!solving_) return;
         setSolveElapsedMs_(solveElapsedTimer_.elapsed());
      });

   // --- buffered Run Log flush (reduces queued UI invocations dramatically) ---
   logFlushTimer_.setInterval(500);
   connect(&logFlushTimer_, &QTimer::timeout, this, [this]()
      {
         QStringList batch;
         {
            QMutexLocker lk(&logBufferMutex_);
            if (logBuffer_.isEmpty()) return;
            batch = std::move(logBuffer_);
            logBuffer_.clear();
         }
         runLogModel_.appendLines(batch);
      });
   logFlushTimer_.start();

   connect(&solveWatcher_, &QFutureWatcher<SolverOutputs>::finished, this, [this]()
      {
         solveUiTick_.stop();
         setSolveElapsedMs_(solveElapsedTimer_.elapsed());
         setSolving_(false);

         // Flush any remaining buffered log lines.
         {
            QStringList batch;
            QMutexLocker lk(&logBufferMutex_);
            batch = std::move(logBuffer_);
            logBuffer_.clear();
            if (!batch.isEmpty()) runLogModel_.appendLines(batch);
         }

         // Close the per-solve file log now that the worker is finished.
         closeSolverLogFile_();

         // Apply results on the UI thread (we are already on UI thread here).
         const SolverOutputs out = solveWatcher_.result();
         applySolveOutputs_(pendingSolveInputs_, out);
         pushProductStreamScaffolding_(out);
         clearSpecsDirty_();
      });
}

void ColumnUnitState::setSolving_(bool v)
{
   if (solving_ == v)
      return;
   solving_ = v;
   emit solvingChanged();
}

void ColumnUnitState::setSolveElapsedMs_(qint64 v)
{
   if (solveElapsedMs_ == v)
      return;
   solveElapsedMs_ = v;
   emit solveElapsedMsChanged();
}

void ColumnUnitState::setSpecsDirty_(bool v)
{
   if (specsDirty_ == v)
      return;
   specsDirty_ = v;
   emit specsDirtyChanged();
}

void ColumnUnitState::markSpecsDirty_()
{
   // Mark that user-editable specs have changed since the last solve.
   setSpecsDirty_(true);
}

void ColumnUnitState::clearSpecsDirty_()
{
   // Clear after a successful solve (or when starting a new solve).
   setSpecsDirty_(false);
}

QString ColumnUnitState::connectedFeedStreamName() const
{
   if (flowsheetState_ && !connectedFeedStreamUnitId_.isEmpty()) {
      if (auto* streamUnit = flowsheetState_->findStreamUnitById(connectedFeedStreamUnitId_)) {
         QString n = streamUnit->name();
         if (!n.isEmpty()) return n;
         return streamUnit->id();
      }
   }
   return QString();
}

MaterialStreamState* ColumnUnitState::activeFeedStream()
{
   if (flowsheetState_ && !connectedFeedStreamUnitId_.isEmpty()) {
      if (auto* connected = flowsheetState_->findMaterialStreamByUnitId(connectedFeedStreamUnitId_))
         return connected;
   }
   return &feedStream_;
}

const MaterialStreamState* ColumnUnitState::activeFeedStream() const
{
   if (flowsheetState_ && !connectedFeedStreamUnitId_.isEmpty()) {
      if (auto* connected = flowsheetState_->findMaterialStreamByUnitId(connectedFeedStreamUnitId_))
         return connected;
   }
   return &feedStream_;
}

void ColumnUnitState::setFlowsheetState(FlowsheetState* flowsheet)
{
   flowsheetState_ = flowsheet;
   attachActiveFeedStreamSignals_();
}

void ColumnUnitState::setConnectedFeedStreamUnitId(const QString& streamUnitId)
{
   if (connectedFeedStreamUnitId_ == streamUnitId)
      return;

   connectedFeedStreamUnitId_ = streamUnitId;
   attachActiveFeedStreamSignals_();
   emit feedStreamChanged();
   emit selectedCrudeChanged();
   emit selectedFluidPackageChanged();
   emit effectiveThermoMethodChanged();
   emit feedRateKgphChanged();
   emit feedTempKChanged();
   markSpecsDirty_();
}

void ColumnUnitState::setConnectedProductStreamUnitId(const QString& portName, const QString& streamUnitId)
{
   const QString port = portName.trimmed().toLower();
   if (port == QStringLiteral("distillate")) {
      connectedDistillateStreamUnitId_ = streamUnitId;
   }
   else if (port == QStringLiteral("bottoms")) {
      connectedBottomsStreamUnitId_ = streamUnitId;
   }
}

QString ColumnUnitState::connectedProductStreamUnitId(const QString& portName) const
{
   const QString port = portName.trimmed().toLower();
   if (port == QStringLiteral("distillate"))
      return connectedDistillateStreamUnitId_;
   if (port == QStringLiteral("bottoms"))
      return connectedBottomsStreamUnitId_;
   return {};
}

void ColumnUnitState::detachActiveFeedStreamSignals_()
{
   QObject::disconnect(activeFeedSelectedFluidConn_);
   QObject::disconnect(activeFeedSelectedFluidPackageConn_);
   QObject::disconnect(activeFeedFlowConn_);
   QObject::disconnect(activeFeedTempConn_);
   QObject::disconnect(activeFeedCompositionConn_);
   observedActiveFeedStream_.clear();
}

void ColumnUnitState::attachActiveFeedStreamSignals_()
{
   auto* stream = activeFeedStream();
   if (observedActiveFeedStream_ == stream)
      return;

   detachActiveFeedStreamSignals_();
   observedActiveFeedStream_ = stream;
   if (!stream)
      return;

   activeFeedSelectedFluidConn_ = connect(stream, &MaterialStreamState::selectedFluidChanged, this, [this, stream]()
      {
         applyCrudeDefaults(stream->selectedFluid());
         markSpecsDirty_();
         emit selectedCrudeChanged();
         emit effectiveThermoMethodChanged();
      });
   activeFeedSelectedFluidPackageConn_ = connect(stream, &MaterialStreamState::selectedFluidPackageChanged, this, [this]()
      {
         markSpecsDirty_();
         emit selectedFluidPackageChanged();
         emit effectiveThermoMethodChanged();
      });
   activeFeedFlowConn_ = connect(stream, &MaterialStreamState::flowRateKgphChanged, this, [this]()
      {
         markSpecsDirty_();
         emit feedRateKgphChanged();
      });
   activeFeedTempConn_ = connect(stream, &MaterialStreamState::temperatureKChanged, this, [this]()
      {
         markSpecsDirty_();
         emit feedTempKChanged();
      });
   activeFeedCompositionConn_ = connect(stream, &MaterialStreamState::compositionChanged, this, [this]()
      {
         markSpecsDirty_();
      });
}

void ColumnUnitState::pushProductStreamScaffolding_(const SolverOutputs& out)
{
   if (!flowsheetState_)
      return;

   auto findSnapshotByName = [&out](const QString& expectedName) -> const StreamSnapshot*
      {
         for (const auto& snapshot : out.streams) {
            if (QString::fromStdString(snapshot.name).compare(expectedName, Qt::CaseInsensitive) == 0)
               return &snapshot;
         }
         return nullptr;
      };

   const SolverTrayOut* bottomTray = out.trays.empty() ? nullptr : &out.trays.front();
   const SolverTrayOut* topTray = out.trays.empty() ? nullptr : &out.trays.back();

   auto pushStream = [this, &findSnapshotByName, topTray, bottomTray, &out](
      const QString& streamUnitId,
      const QString& expectedName,
      double fallbackFlowKgph,
      const SolverTrayOut* fallbackTray)
      {
         if (streamUnitId.isEmpty())
            return;

         auto* stream = flowsheetState_->findMaterialStreamByUnitId(streamUnitId);
         if (!stream)
            return;

         const StreamSnapshot* snapshot = findSnapshotByName(expectedName);

         stream->setStreamType(MaterialStreamState::StreamType::Product);
         stream->setIsCrudeFeed(false);
         stream->setStreamName(expectedName);

         // Product streams are fully defined by the solver: force TP spec so the
         // UI shows T and P as the defining conditions (not editable spec fields),
         // and MassFlow since the solver output is in kg/h.
         stream->setThermoSpecMode(MaterialStreamState::ThermoSpecMode::TP);
         stream->setFlowSpecMode(MaterialStreamState::FlowSpecMode::MassFlow);

         if (auto* feed = activeFeedStream()) {
            const QString basisFluid = feed->selectedFluid().trimmed();
            if (!basisFluid.isEmpty())
               stream->setSelectedFluid(basisFluid);
            const QString packageId = feed->selectedFluidPackageId().trimmed();
            if (!packageId.isEmpty())
               stream->setSelectedFluidPackageId(packageId);
         }

         if (snapshot && !snapshot->composition.empty())
            stream->setCompositionStd(snapshot->composition);

         if (snapshot && std::isfinite(snapshot->Vfrac))
            stream->setVaporFraction(snapshot->Vfrac);
         else
            stream->setVaporFraction(0.0);

         if (snapshot && std::isfinite(snapshot->rho) && snapshot->rho > 0.0)
            stream->setBulkDensityOverrideKgM3(snapshot->rho);
         else
            stream->setBulkDensityOverrideKgM3(std::numeric_limits<double>::quiet_NaN());

         double flowKgph = fallbackFlowKgph;
         if (snapshot && std::isfinite(snapshot->kgph))
            flowKgph = snapshot->kgph;
         if (std::isfinite(flowKgph))
            stream->setFlowRateKgph(flowKgph);

         double temperatureK = std::numeric_limits<double>::quiet_NaN();
         if (snapshot && std::isfinite(snapshot->T))
            temperatureK = snapshot->T;
         else if (fallbackTray && std::isfinite(fallbackTray->tempK))
            temperatureK = fallbackTray->tempK;
         if (std::isfinite(temperatureK))
            stream->setTemperatureK(temperatureK);

         double pressurePa = std::numeric_limits<double>::quiet_NaN();
         if (snapshot && std::isfinite(snapshot->P))
            pressurePa = snapshot->P;
         else if (fallbackTray && std::isfinite(fallbackTray->pressurePa))
            pressurePa = fallbackTray->pressurePa;
         if (std::isfinite(pressurePa))
            stream->setPressurePa(pressurePa);
      };

   pushStream(connectedDistillateStreamUnitId_, QStringLiteral("Distillate"), out.energy.D_kgph, topTray);
   pushStream(connectedBottomsStreamUnitId_, QStringLiteral("Bottoms"), out.energy.B_kgph, bottomTray);
}

void ColumnUnitState::setSolverLogLevel(int v)
{
   v = std::clamp(v, 0, 2);
   if (solverLogLevel_ == v)
      return;
   solverLogLevel_ = v;
   emit solverLogLevelChanged();
}

void ColumnUnitState::setTrays(int v)
{
   v = std::clamp(v, minTrays(), maxTrays());
   if (trays_ == v)
      return;

   trays_ = v;

   if (feedTray_ < 1) feedTray_ = 1;
   if (feedTray_ > trays_) feedTray_ = trays_;
   emit feedTrayChanged();

   setDrawSpecs(drawSpecs_);               // re-clamp draw list
   trayModel_.resetToDefaults(trays_);     // resize model

   markSpecsDirty_();
   emit traysChanged();
}

// ---------------- Crude selection ----------------

QStringList ColumnUnitState::crudeNames() const
{
   return crudeNames_;
}

QString ColumnUnitState::selectedCrude() const
{
   return activeFeedStream()->selectedFluid();
}

void ColumnUnitState::setSelectedCrude(const QString& v)
{
   if (activeFeedStream()->selectedFluid() == v)
      return;

   activeFeedStream()->setSelectedFluid(v);
}

QString ColumnUnitState::selectedFluidPackageName() const
{
   const auto* feed = activeFeedStream();
   return feed ? feed->selectedFluidPackageName() : QString{};
}

QString ColumnUnitState::packageSelectedThermoMethod_() const
{
   const auto* feed = activeFeedStream();
   if (!feed)
      return {};
   const QString pkgId = feed->selectedFluidPackageId().trimmed();
   if (pkgId.isEmpty())
      return {};
   auto* mgr = FluidPackageManager::instance();
   if (!mgr)
      return {};
   return mgr->thermoMethodIdForPackage(pkgId).trimmed();
}

QString ColumnUnitState::packageThermoLabel_() const
{
   const QString method = packageSelectedThermoMethod_();
   if (method.isEmpty())
      return QStringLiteral("Legacy %1").arg(eosMode_ == QStringLiteral("manual") ? eosManual_ : QStringLiteral("tray-based EOS"));
   return QStringLiteral("From package (%1)").arg(method);
}

QString ColumnUnitState::effectiveThermoMethod() const
{
   const QString method = packageSelectedThermoMethod_();
   if (!method.isEmpty())
      return method;
   if (eosMode_ == QStringLiteral("manual") && !eosManual_.trimmed().isEmpty())
      return eosManual_.trimmed();
   return QStringLiteral("auto");
}

bool ColumnUnitState::packageThermoControlled() const
{
   return !packageSelectedThermoMethod_().isEmpty();
}

// ---------------- EOS settings ----------------

QString ColumnUnitState::eosMode() const
{
   return eosMode_;
}

void ColumnUnitState::setEosMode(const QString& v)
{
   if (eosMode_ == v)
      return;
   eosMode_ = v;
   markSpecsDirty_();
   emit eosModeChanged();
}

QString ColumnUnitState::eosManual() const
{
   return eosManual_;
}

void ColumnUnitState::setEosManual(const QString& v)
{
   if (eosManual_ == v)
      return;
   eosManual_ = v;
   markSpecsDirty_();
   emit eosManualChanged();
}

// ---------------- Condenser / Reboiler types ----------------

QString ColumnUnitState::condenserType() const
{
   return condenserType_;
}

void ColumnUnitState::setCondenserType(const QString& v)
{
   if (condenserType_ == v)
      return;
   condenserType_ = v;
   markSpecsDirty_();
   emit condenserTypeChanged();
}

QString ColumnUnitState::reboilerType() const
{
   return reboilerType_;
}

void ColumnUnitState::setReboilerType(const QString& v)
{
   if (reboilerType_ == v)
      return;
   reboilerType_ = v;
   markSpecsDirty_();
   emit reboilerTypeChanged();
}

// ---------------- Pressures ----------------

double ColumnUnitState::topPressurePa() const
{
   return topPressurePa_;
}

void ColumnUnitState::setTopPressurePa(double v)
{
   if (qFuzzyCompare(topPressurePa_, v))
      return;
   topPressurePa_ = v;
   markSpecsDirty_();
   emit topPressurePaChanged();
}

double ColumnUnitState::dpPerTrayPa() const
{
   return dpPerTrayPa_;
}

void ColumnUnitState::setDpPerTrayPa(double v)
{
   if (qFuzzyCompare(dpPerTrayPa_, v))
      return;
   dpPerTrayPa_ = v;
   markSpecsDirty_();
   emit dpPerTrayPaChanged();
}

// ---------------- Murphree ----------------

double ColumnUnitState::etaVTop() const { return etaVTop_; }

void ColumnUnitState::setEtaVTop(double v)
{
   if (qFuzzyCompare(etaVTop_, v))
      return;
   etaVTop_ = v;
   markSpecsDirty_();
   emit etaVTopChanged();
}

double ColumnUnitState::etaVMid() const { return etaVMid_; }

void ColumnUnitState::setEtaVMid(double v)
{
   if (qFuzzyCompare(etaVMid_, v))
      return;
   etaVMid_ = v;
   markSpecsDirty_();
   emit etaVMidChanged();
}

double ColumnUnitState::etaVBot() const { return etaVBot_; }

void ColumnUnitState::setEtaVBot(double v)
{
   if (qFuzzyCompare(etaVBot_, v))
      return;
   etaVBot_ = v;
   markSpecsDirty_();
   emit etaVBotChanged();
}

bool ColumnUnitState::enableEtaL() const { return enableEtaL_; }

void ColumnUnitState::setEnableEtaL(bool v)
{
   if (enableEtaL_ == v)
      return;
   enableEtaL_ = v;
   markSpecsDirty_();
   emit enableEtaLChanged();
}

double ColumnUnitState::etaLTop() const { return etaLTop_; }

void ColumnUnitState::setEtaLTop(double v)
{
   if (qFuzzyCompare(etaLTop_, v))
      return;
   etaLTop_ = v;
   markSpecsDirty_();
   emit etaLTopChanged();
}

double ColumnUnitState::etaLMid() const { return etaLMid_; }

void ColumnUnitState::setEtaLMid(double v)
{
   if (qFuzzyCompare(etaLMid_, v))
      return;
   etaLMid_ = v;
   markSpecsDirty_();
   emit etaLMidChanged();
}

double ColumnUnitState::etaLBot() const { return etaLBot_; }

void ColumnUnitState::setEtaLBot(double v)
{
   if (qFuzzyCompare(etaLBot_, v))
      return;
   etaLBot_ = v;
   markSpecsDirty_();
   emit etaLBotChanged();
}

// ---------------- Feed ----------------

double ColumnUnitState::feedRateKgph() const { return activeFeedStream()->flowRateKgph(); }

void ColumnUnitState::setFeedRateKgph(double v)
{
   if (qFuzzyCompare(activeFeedStream()->flowRateKgph(), v))
      return;
   activeFeedStream()->setFlowRateKgph(v);
}

double ColumnUnitState::feedTempK() const { return activeFeedStream()->temperatureK(); }

void ColumnUnitState::setFeedTempK(double v)
{
   if (qFuzzyCompare(activeFeedStream()->temperatureK(), v))
      return;
   activeFeedStream()->setTemperatureK(v);
}

int ColumnUnitState::feedTray() const { return feedTray_; }

void ColumnUnitState::setFeedTray(int v)
{
   v = std::clamp(v, 1, trays_);
   if (feedTray_ == v)
      return;
   feedTray_ = v;
   markSpecsDirty_();
   emit feedTrayChanged();
}

// ---------------- Specs ----------------


// ---------------- Draw specs ----------------

QVariantList ColumnUnitState::drawSpecs() const { return drawSpecs_; }

void ColumnUnitState::setDrawSpecs(const QVariantList& v)
{
   // Canonical schema:
   // { name, tray(1-based), basis, phase, value, pct(legacy mirror) }
   QVariantList normalized;
   normalized.reserve(v.size());

   auto pickStr = [](const QVariantMap& m, const QStringList& keys) -> QString {
      for (const auto& k : keys) {
         const QString s = m.value(k).toString().trimmed();
         if (!s.isEmpty()) return s;
      }
      return {};
      };
   auto pickInt = [](const QVariantMap& m, const QStringList& keys, int def = 0) -> int {
      for (const auto& k : keys) if (m.contains(k)) return m.value(k).toInt();
      return def;
      };
   auto pickDbl = [](const QVariantMap& m, const QStringList& keys, double def = 0.0) -> double {
      for (const auto& k : keys) if (m.contains(k)) return m.value(k).toDouble();
      return def;
      };

   const int cap = maxSideDraws();

   for (const auto& entry : v) {
      if (!entry.canConvert<QVariantMap>())
         continue;
      const QVariantMap m = entry.toMap();

      const QString name = pickStr(m, { "name", "label", "product", "cut", "title" });
      int tray = pickInt(m, { "tray", "trayNumber", "trayNo", "tray_index", "trayIndex" }, 0);

      QString basis = pickStr(m, { "basis" });
      if (basis.isEmpty())
         basis = "feedPct";

      QString phase = pickStr(m, { "phase" });
      if (phase.isEmpty())
         phase = "L";

      double value = pickDbl(m, { "value" }, std::numeric_limits<double>::quiet_NaN());
      const bool hasValue = std::isfinite(value);
      if (!hasValue) {
         // Backward compatibility
         value = pickDbl(m, { "pct", "percent", "percentage", "pctOfFeed", "frac", "fraction" }, 0.0);
      }

      qDebug() << "[DrawSpecs UI]"
         << "name=" << name
         << "tray=" << tray
         << "value=" << value
         << "basis=" << basis
         << "phase=" << phase;

      if (name.isEmpty())
         continue;
      if (tray < 1 || tray > trays_)
         continue;
      if (tray == 1 || tray == trays_)
         continue; // side draws only
      if (!std::isfinite(value) || value < 0.0)
         value = 0.0;

      QVariantMap out;
      out.insert("name", name);
      out.insert("tray", tray);
      out.insert("basis", basis);
      out.insert("phase", phase);
      out.insert("value", value);

      // legacy pct mirror (for old readers/UI)
      const double pctLegacy = (basis == "feedPct")
         ? value
         : pickDbl(m, { "pct" }, 0.0);
      out.insert("pct", std::max(0.0, pctLegacy));

      normalized.push_back(out);
      if (normalized.size() >= cap) break;
   }

   drawSpecs_ = normalized;
   markSpecsDirty_();
   emit drawSpecsChanged();
}

QString ColumnUnitState::condenserSpec() const { return condenserSpec_; }

void ColumnUnitState::setCondenserSpec(const QString& v)
{

   if (condenserSpec_ == v) return;
   condenserSpec_ = v;
   markSpecsDirty_();
   emit condenserSpecChanged();
}

QString ColumnUnitState::reboilerSpec() const { return reboilerSpec_; }

void ColumnUnitState::setReboilerSpec(const QString& v)
{
   if (reboilerSpec_ == v)
      return;
   reboilerSpec_ = v;
   markSpecsDirty_();
   emit reboilerSpecChanged();
}

// ---------------- Numbers ----------------

double ColumnUnitState::refluxRatio() const { return refluxRatio_; }

void ColumnUnitState::setRefluxRatio(double v)
{
   if (qFuzzyCompare(refluxRatio_, v))
      return;
   refluxRatio_ = v;
   markSpecsDirty_();
   emit refluxRatioChanged();
}

double ColumnUnitState::boilupRatio() const { return boilupRatio_; }

void ColumnUnitState::setBoilupRatio(double v)
{
   if (qFuzzyCompare(boilupRatio_, v))
      return;
   boilupRatio_ = v;
   markSpecsDirty_();
   emit boilupRatioChanged();
}

double ColumnUnitState::qcKW() const { return qcKW_; }

void ColumnUnitState::setQcKW(double v)
{
   if (qFuzzyCompare(qcKW_, v))
      return;
   qcKW_ = v;
   markSpecsDirty_();
   emit qcKWChanged();
}

double ColumnUnitState::qrKW() const { return qrKW_; }
double ColumnUnitState::qcCalcKW() const { return qcCalcKW_; }
double ColumnUnitState::qrCalcKW() const { return qrCalcKW_; }

void ColumnUnitState::setQrKW(double v)
{
   if (qFuzzyCompare(qrKW_, v))
      return;
   qrKW_ = v;
   markSpecsDirty_();
   emit qrKWChanged();
}

double ColumnUnitState::topTsetK() const { return topTsetK_; }

void ColumnUnitState::setTopTsetK(double v)
{
   if (qFuzzyCompare(topTsetK_, v))
      return;
   topTsetK_ = v;
   markSpecsDirty_();
   emit topTsetKChanged();
}

double ColumnUnitState::bottomTsetK() const { return bottomTsetK_; }

void ColumnUnitState::setBottomTsetK(double v)
{
   if (qFuzzyCompare(bottomTsetK_, v))
      return;
   bottomTsetK_ = v;
   markSpecsDirty_();
   emit bottomTsetKChanged();
}

// ---------------- Models ----------------

bool ColumnUnitState::solved() const { return solved_; }

TrayModel* ColumnUnitState::trayModel() { return &trayModel_; }
DiagnosticsModel* ColumnUnitState::diagnosticsModel() { return &diagnosticsModel_; }
RunLogModel* ColumnUnitState::runLogModel() { return &runLogModel_; }
MaterialBalanceModel* ColumnUnitState::materialBalanceModel() { return &mbModel_; }

// ---------------- Actions ----------------

void ColumnUnitState::reset()
{
   applyCrudeDefaults(activeFeedStream()->selectedFluid());
   diagnosticsModel_.clear();
   runLogModel_.clear();
   mbModel_.reset();

   solved_ = false;
   emit solvedChanged();
}

void ColumnUnitState::resetDrawSpecsToDefaults()
{
   // Reset only the Draw Config rows (not the other crude settings).
   const CrudeInitialSettings s = getCrudeInitialSettings(activeFeedStream()->selectedFluid().toStdString());

   const auto& nameMap = defaultDrawNamesByTray32(); // 1-based tray -> label
   QVariantList rows;
   rows.reserve(static_cast<int>(s.drawSpecsByTrayIndex.size()));

   struct Row
   {
      int tray1;
      double pct;
      QString name;
   };

   std::vector<Row> tmp;
   tmp.reserve(s.drawSpecsByTrayIndex.size());

   for (const auto& kv : s.drawSpecsByTrayIndex)
   {
      const int trayIndex0 = kv.first;
      const double fracOfFeed = kv.second;
      if (trayIndex0 < 0)
         continue;
      const int tray1 = trayIndex0 + 1;
      if (tray1 <= 1 || tray1 >= trays_)
         continue;
      if (!(fracOfFeed > 0.0))
         continue;

      auto it = nameMap.find(tray1);
      const QString label = (it != nameMap.end())
         ? QString::fromStdString(it->second)
         : QString("Draw [Tray %1]").arg(tray1);

      tmp.push_back(Row{ tray1, fracOfFeed * 100.0, label });
   }

   std::sort(tmp.begin(), tmp.end(), [](const Row& a, const Row& b)
      {
         return a.tray1 > b.tray1; // top (32) first
      });

   const int cap = maxSideDraws();
   int added = 0;
   for (const auto& r : tmp)
   {
      if (added >= cap)
         break;

      QVariantMap m;
      m.insert("name", r.name);
      m.insert("tray", r.tray1);
      m.insert("pct", r.pct);
      rows.push_back(m);
      ++added;
   }

   setDrawSpecs(rows);
}

void ColumnUnitState::restoreSolveScalars(
   double tColdK, double tHotK,
   double qcCalcKW, double qrCalcKW,
   double refluxFraction, double boilupFraction,
   qint64 elapsedMs,
   const QStringList& componentNames)
{
   tColdK_ = tColdK;
   tHotK_ = tHotK;
   qcCalcKW_ = qcCalcKW;
   qrCalcKW_ = qrCalcKW;
   refluxFraction_ = refluxFraction;
   boilupFraction_ = boilupFraction;
   solveElapsedMs_ = elapsedMs;
   solved_ = true;
   specsDirty_ = false;

   if (componentNames_ != componentNames) {
      componentNames_ = componentNames;
      emit componentNamesChanged();
   }

   emit tColdKChanged();
   emit tHotKChanged();
   emit qcCalcKWChanged();
   emit qrCalcKWChanged();
   emit refluxFractionChanged();
   emit boilupFractionChanged();
   emit solveElapsedMsChanged();
   emit solvedChanged();
   emit specsDirtyChanged();
}


QString ColumnUnitState::defaultSolverInputsExportPath_() const
{
   const QString baseDir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
      + "/AI_Process_Simulator/solver_inputs";
   QDir().mkpath(baseDir);

   QString unitPart = name().trimmed();
   if (unitPart.isEmpty())
      unitPart = QStringLiteral("column");
   unitPart.replace(QRegularExpression(QStringLiteral(R"([^A-Za-z0-9_\-]+)")), QStringLiteral("_"));

   QString fluidPart = selectedCrude().trimmed();
   if (fluidPart.isEmpty())
      fluidPart = QStringLiteral("unknown_fluid");
   fluidPart.replace(QRegularExpression(QStringLiteral(R"([^A-Za-z0-9_\-]+)")), QStringLiteral("_"));

   const QString ts = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
   return baseDir + "/" + unitPart + "_" + fluidPart + "_" + ts + "_solver_inputs.json";
}

QString ColumnUnitState::exportLatestSolverInputsJson(const QString& filePath)
{
   const bool havePending = !pendingSolveInputs_.fluidThermo.components.empty();
   if (!havePending) {
      qWarning() << "[ColumnUnitState] No prepared SolverInputs available to export yet."
                 << "Run the column solver first.";
      return QString();
   }

   const QString resolvedPath = filePath.trimmed().isEmpty()
      ? defaultSolverInputsExportPath_()
      : filePath;

   QFileInfo fi(resolvedPath);
   QDir().mkpath(fi.absolutePath());

   QSaveFile outFile(resolvedPath);
   if (!outFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
      qWarning() << "[ColumnUnitState] Failed to open solver inputs export file:" << resolvedPath
                 << outFile.errorString();
      return QString();
   }

   const std::string json = serializeSolverInputsToJson(pendingSolveInputs_, true);
   const QByteArray bytes = QByteArray::fromStdString(json);

   if (outFile.write(bytes) != bytes.size()) {
      qWarning() << "[ColumnUnitState] Failed to write solver inputs export file:" << resolvedPath
                 << outFile.errorString();
      outFile.cancelWriting();
      return QString();
   }

   if (!outFile.commit()) {
      qWarning() << "[ColumnUnitState] Failed to commit solver inputs export file:" << resolvedPath
                 << outFile.errorString();
      return QString();
   }

   if (lastSolverInputsExportPath_ != resolvedPath) {
      lastSolverInputsExportPath_ = resolvedPath;
      emit lastSolverInputsExportPathChanged();
   }

   runLogModel_.append(QString("Exported SolverInputs JSON: %1").arg(resolvedPath));
   return resolvedPath;
}


void ColumnUnitState::solve()
{
   if (solving_)
   {
      // Ignore re-entrant solve requests while a solve is already running.
      return;
   }

   // Clear ALL prior run outputs immediately so a second click starts from a clean UI.
   // (Tray table, Run Results, Run Summary/MB, condenser/reboiler derived fields, etc.)
   clearRunOutputs_();

   SolverInputs in;
   const MaterialStreamState* feed = activeFeedStream();

   // Guard: warn via diagnostics if the feed stream has no valid fluid package.
   // The solve proceeds using legacy crude-based thermo in this case.
   if (feed->selectedFluidPackageId().trimmed().isEmpty()) {
      qWarning() << "[ColumnUnitState] Feed stream has no fluid package assigned."
         << "Solver will use legacy crude-string EOS selection.";
   }
   else if (!feed->fluidPackageValid()) {
      qWarning() << "[ColumnUnitState] Feed stream fluid package is invalid or unresolvable:"
         << feed->selectedFluidPackageId()
         << "— Solver will fall back to legacy EOS selection.";
   }

   in.fluidName = feed->selectedFluid().toStdString();
   in.fluidThermo = feed->fluidDefinition().thermo;
   in.feedComposition = feed->compositionStd();
   in.trays = trays_;
   in.feedRateKgph = feedRateKgph();
   in.feedTray = std::clamp(feedTray_, 1, in.trays);
   in.feedTempK = feedTempK();
   in.topPressurePa = topPressurePa_;
   in.dpPerTrayPa = dpPerTrayPa_;

   // Capture UI verbosity at the moment the solve starts.
   // This controls ONLY what goes to the UI RunLogModel.
   const int uiLogLevel = solverLogLevel_; // 0=None, 1=Summary, 2=Debug

   // Solver emission level controls what the simulator emits via opt.onLog.
   // Even when UI verbosity is OFF, we still want full-fidelity file logging.
   const int solverEmitLevel = (uiLogLevel <= 0) ? 1 : uiLogLevel; // 2=Debug
   in.logLevel = static_cast<LogLevel>(solverEmitLevel);

   // Resolve ThermoConfig from the feed stream's fluid package (primary path).
   // Also keep eosMode/eosManual populated for legacy fallback inside the solver.
   const QString packageThermoMethod = packageSelectedThermoMethod_();
   if (!packageThermoMethod.isEmpty()) {
      const QString pkgId = feed->selectedFluidPackageId().trimmed();
      auto* fpm = FluidPackageManager::instance();
      if (fpm)
         in.thermoConfig = fpm->thermoConfigForPackageResolved(pkgId);
      in.eosMode = "manual";
      in.eosManual = packageThermoMethod.toStdString();
   }
   else {
      in.eosMode = eosMode_.toStdString();
      in.eosManual = eosManual_.toStdString();
   }
   in.condenserType = condenserType_.toStdString();
   in.reboilerType = reboilerType_.toStdString();
   in.condenserSpec = condenserSpec_.toStdString();
   in.reboilerSpec = reboilerSpec_.toStdString();

   in.refluxRatio = refluxRatio_;
   in.boilupRatio = boilupRatio_;
   in.qcKW = qcKW_;
   in.qrKW = qrKW_;
   in.topTsetK = topTsetK_;
   in.bottomTsetK = bottomTsetK_;

   in.etaVTop = etaVTop_;
   in.etaVMid = etaVMid_;
   in.etaVBot = etaVBot_;
   in.enableEtaL = enableEtaL_;
   in.etaLTop = etaLTop_;
   in.etaLMid = etaLMid_;
   in.etaLBot = etaLBot_;

   // Side draws: consume new schema ({name,tray,basis,phase,value,pct})
   in.drawSpecs.clear();
   in.drawLabelsByTray1.clear();

   for (const auto& v : drawSpecs_)
   {
      const QVariantMap m = v.toMap();

      const QString name = m.value("name").toString().trimmed();
      const int tray1 = m.value("tray").toInt();

      const QString basis = m.value("basis").toString().trimmed().isEmpty()
         ? QString("feedPct")
         : m.value("basis").toString().trimmed();

      const QString phase = m.value("phase").toString().trimmed().isEmpty()
         ? QString("L")
         : m.value("phase").toString().trimmed();

      const double value = m.contains("value")
         ? m.value("value").toDouble()
         : m.value("pct").toDouble(); // backward compatibility

      if (tray1 <= 0 || tray1 > in.trays)
         continue;
      if (!std::isfinite(value) || value <= 0.0)
         continue;
      if (phase.compare("L", Qt::CaseInsensitive) != 0)
         continue; // current solver path handles liquid side draws

      SolverDrawSpec ds;
      ds.trayIndex0 = tray1 - 1;       // keep 0-based internal tray index
      ds.name = name.toStdString();
      ds.basis = basis.toStdString();  // "feedPct" | "stageLiqPct" | "kgph"
      ds.phase = phase.toStdString();  // "L"
      ds.value = value;

      in.drawSpecs.push_back(std::move(ds));

      if (!name.isEmpty())
         in.drawLabelsByTray1[tray1] = name.toStdString();
   }

   // Debug: confirm solver-side draw specs built from AppState.drawSpecs_
   if (!in.drawSpecs.empty())
   {
      qDebug() << "[DrawSpecs Solver] entries=" << static_cast<int>(in.drawSpecs.size());
      for (const auto& ds : in.drawSpecs)
      {
         qDebug() << "  trayIndex0=" << ds.trayIndex0
            << " basis=" << QString::fromStdString(ds.basis)
            << " phase=" << QString::fromStdString(ds.phase)
            << " value=" << ds.value
            << " name=" << QString::fromStdString(ds.name);
      }
   }
   else
   {
      qDebug() << "[DrawSpecs Solver] entries=0";
   }
   runLogModel_.append(QString("Solve: fluid=%1 package=%2 thermo=%3 trays=%4 feed=%5 kg/h feedTray=%6")
      .arg(feed->selectedFluid())
      .arg(feed->selectedFluidPackageName().isEmpty() ? QStringLiteral("(legacy)") : feed->selectedFluidPackageName())
      .arg(effectiveThermoMethod())
      .arg(in.trays)
      .arg(feedRateKgph(), 0, 'f', 0)
      .arg(in.feedTray));
   // Open per-solve full-fidelity log file (disk) before launching worker.
   openSolverLogFile_();

   // --- thread-safe buffered log capture (solver thread -> UI thread flush timer) ---
   QPointer<ColumnUnitState> self(this);
   auto bufferLine = [self, uiLogLevel](const QString& s)
      {
         if (!self || s.isEmpty())
            return;

         // UI verbosity OFF: still keep full-fidelity file logging, but do not
         // append anything to the UI RunLogModel.
         if (uiLogLevel <= 0)
            return;

         QMutexLocker lk(&self->logBufferMutex_);
         self->logBuffer_.append(s);

         // prevent huge burst batches (especially if flush interval is large)
         if (self->logBuffer_.size() > MAX_LOG_BUFFER_LINES)
         {
            const int overflow = self->logBuffer_.size() - MAX_LOG_BUFFER_LINES;
            self->logBuffer_.erase(self->logBuffer_.begin(),
               self->logBuffer_.begin() + overflow);
            // optional: add a marker line once
            // self->logBuffer_.prepend(QString("[LOG] dropped %1 lines").arg(overflow));
         }
      };

   std::function<void(const std::string&)> onLog = [bufferLine, self, uiLogLevel](const std::string& line)
      {
         const QString q = QString::fromStdString(line);

         // Centralized filtering decision (Summary mode only).
         const bool passSummary = (uiLogLevel != 1) || allowSummaryTag(q);

         // File logging (filtered in Summary mode too).
         if (self && passSummary)
            self->writeSolverLogLine_(q);

         // UI off
         if (uiLogLevel <= 0)
            return;

         if (!passSummary)
            return;

         bufferLine(q);
      };

   std::function<void(const ProgressEvent&)> onProgress = [bufferLine, self, uiLogLevel](const ProgressEvent& ev)
      {
         if (!self)
            return;

         // Always write progress markers to the per-solve disk log (even if UI verbosity is OFF).
         // Detailed thermo/PH diagnostics are emitted via onLog; these are coarse markers.
         auto fileLine = [&](const QString& s)
            {
               self->writeSolverLogLine_(s);
            };

         // Keep progress logs coarse, similar to the React onProgress messages.
         if (ev.stage == "init")
         {
            fileLine(QStringLiteral("Solving..."));
            if (uiLogLevel > 0)
               bufferLine(QStringLiteral("Solving..."));
         }
         else if (ev.stage == "iter")
         {
            const QString s = QString("iter=%1  Ttop=%2  Tbot=%3")
               .arg(ev.iter)
               .arg(ev.Ttop, 0, 'f', 2)
               .arg(ev.Tbot, 0, 'f', 2);
            fileLine(s);
            if (uiLogLevel > 0)
               bufferLine(s);
         }
         else if (ev.stage == "trayStart")
         {
            // Force-flush any pending coalesced thermo logs so "(repeated N times)"
            // summaries land at the correct tray boundary (instead of drifting into
            // the next tray and appearing to "recycle" tray numbers).
            {
               // Flush to disk log
               const auto thermoLoggerFile = [fileLine, uiLogLevel](const std::string& s)
                  {
                     const QString q = QString::fromStdString(s);
                     if (uiLogLevel == 1 && !allowSummaryTag(q))
                        return;
                     fileLine(QString::fromStdString(s));
                  };
               flushEOSKCoalescer(thermoLoggerFile);
               flushPRSVCoalescer(thermoLoggerFile);

               // Flush to UI only when verbosity > 0
               if (uiLogLevel > 0)
               {
                  const auto thermoLoggerUi = [bufferLine, uiLogLevel](const std::string& s)
                     {
                        const QString q = QString::fromStdString(s);
                        if (uiLogLevel == 1 && !allowSummaryTag(q))
                           return;
                        bufferLine(QString::fromStdString(s));
                     };
                  flushEOSKCoalescer(thermoLoggerUi);
                  flushPRSVCoalescer(thermoLoggerUi);
               }
            }

            const QString endTag =
               (ev.tray == 1) ? " (Reboiler)" : (ev.tray == ev.trays) ? " (Condenser)" : "";
            const QString s = QString("trayStart tray=%1 idx0=%2 /%3 %4")
               .arg(ev.tray)
               .arg(ev.tray - 1)
               .arg(ev.trays)
               .arg(endTag);
            fileLine(s);
            if (uiLogLevel > 0)
               bufferLine(s);
         }
         else if (ev.stage == "trayEnd")
         {
            // Flush at tray end as well so any repeated thermo logs are attributed
            // to the tray that produced them.
            {
               // Flush to disk log
               const auto thermoLoggerFile = [fileLine, uiLogLevel](const std::string& s)
                  {
                     const QString q = QString::fromStdString(s);
                     if (uiLogLevel == 1 && !allowSummaryTag(q))
                        return;
                     fileLine(QString::fromStdString(s));
                  };
               flushEOSKCoalescer(thermoLoggerFile);
               flushPRSVCoalescer(thermoLoggerFile);

               // Flush to UI only when verbosity > 0
               if (uiLogLevel > 0)
               {
                  const auto thermoLoggerUi = [bufferLine, uiLogLevel](const std::string& s)
                     {
                        const QString q = QString::fromStdString(s);
                        if (uiLogLevel == 1 && !allowSummaryTag(q))
                           return;
                        bufferLine(QString::fromStdString(s));
                     };
                  flushEOSKCoalescer(thermoLoggerUi);
                  flushPRSVCoalescer(thermoLoggerUi);
               }
            }

            const QString endTag =
               (ev.tray == 1) ? " (Reboiler)" : (ev.tray == ev.trays) ? " (Condenser)" : "";
            const QString s = QString("trayEnd tray=%1 idx0=%2 /%3 %4")
               .arg(ev.tray)
               .arg(ev.tray - 1)
               .arg(ev.trays)
               .arg(endTag);
            fileLine(s);
            if (uiLogLevel > 0)
               bufferLine(s);
         }
         else if (ev.stage == "converged")
         {
            const QString s = QString("[CONVERGED] iter=%1 resid=%2 dT=%3")
               .arg(ev.iter)
               .arg(ev.resid, 0, 'e', 3)
               .arg(ev.dT, 0, 'e', 3);
            fileLine(s);
            if (uiLogLevel > 0)
               bufferLine(s);
         }
         else if (ev.stage == "failed")
         {
            const QString s = QString("[FAILED] iter=%1 resid=%2 dT=%3")
               .arg(ev.iter)
               .arg(ev.resid, 0, 'e', 3)
               .arg(ev.dT, 0, 'e', 3);
            fileLine(s);
            if (uiLogLevel > 0)
               bufferLine(s);
         }
         else if (ev.stage == "done")
         {
            fileLine(QStringLiteral("Done."));
            if (uiLogLevel > 0)
               bufferLine(QStringLiteral("Done."));
         }
      };

   // --- start live timer + dispatch solve on worker thread ---
   pendingSolveInputs_ = in;
   setSolveElapsedMs_(0);
   setSolving_(true);
   solveElapsedTimer_.restart();
   solveUiTick_.start();

   auto future = QtConcurrent::run([in, onLog, onProgress]() -> SolverOutputs
      {
         return solveColumn(in, onLog, onProgress);
      });
   solveWatcher_.setFuture(future);
}

void ColumnUnitState::clearRunOutputs_()
{
   // Models / panels
   diagnosticsModel_.clear();
   runLogModel_.clear();
   mbModel_.reset();
   trayModel_.resetToDefaults(trays_);

   // Clear any buffered log lines waiting to be flushed into the UI model.
   {
      QMutexLocker lk(&logBufferMutex_);
      logBuffer_.clear();
   }

   // Run Results (text panel)
   runResults_.clear();
   emit runResultsChanged();

   // Column / Condenser / Reboiler derived fields
   refluxFraction_ = 0.0;
   boilupFraction_ = 0.0;
   qcCalcKW_ = 0.0;
   qrCalcKW_ = 0.0;
   tColdK_ = 0.0;
   tHotK_ = 0.0;
   emit refluxFractionChanged();
   emit boilupFractionChanged();
   emit qcCalcKWChanged();
   emit qrCalcKWChanged();
   emit tColdKChanged();
   emit tHotKChanged();

   // Solved flag
   solved_ = false;
   emit solvedChanged();
}

void ColumnUnitState::applySolveOutputs_(const SolverInputs& in, const SolverOutputs& out)
{
   trayModel_.resetToDefaults(in.trays);

   const int N = static_cast<int>(out.trays.size());
   for (int i = 0; i < N; ++i)
   {
      const auto& t = out.trays[static_cast<size_t>(i)];
      const bool isFeed = (i == (feedTray_ - 1)); // feedTray is 1-based
      {
         // Determine whether this tray has a configured draw (from DrawConfigView).
         bool hasDraw = false;
         QString drawLabel;
         const int tray1 = i + 1; // UI uses 1-based tray numbers
         for (const auto& v : drawSpecs_)
         {
            const QVariantMap m = v.toMap();
            const int tr = m.value("tray").toInt();
            if (tr != tray1)
               continue;
            const QString name = m.value("name").toString();
            if (!name.isEmpty())
            {
               if (!drawLabel.isEmpty())
                  drawLabel += ", ";
               drawLabel += name;
            }
            hasDraw = true;
         }
         TrayRow row;
         row.trayNumber = i + 1;
         row.tempK = t.tempK;
         row.vaporFrac = t.vFrac;
         row.vaporFlow = t.V_kgph;
         row.liquidFlow = t.L_kgph;
         row.hasDraw = hasDraw;
         row.drawLabel = drawLabel;
         row.xLiq = t.xLiq;
         row.yVap = t.yVap;
         trayModel_.setRow(i, row);
      }
   }

   // Forward component names to TrayModel and expose as Q_PROPERTY
   {
      QStringList compNames;
      compNames.reserve(static_cast<int>(out.componentNames.size()));
      for (const auto& name : out.componentNames)
         compNames.append(QString::fromStdString(name));
      if (componentNames_ != compNames) {
         componentNames_ = compNames;
         emit componentNamesChanged();
      }
      trayModel_.setComponentNames(compNames);
   }

   // Derived values shown in the "Column" panel. Keep them simple for now.
   refluxFraction_ = out.energy.reflux_fraction;
   boilupFraction_ = out.energy.boilup_fraction;
   qcCalcKW_ = out.energy.Qc_calc_kW;
   qrCalcKW_ = out.energy.Qr_calc_kW;

   emit qcCalcKWChanged();
   emit qrCalcKWChanged();

   // these two should also come from the solver if you want parity with React’s "calc":
   tColdK_ = out.energy.Tc_calc_K;
   tHotK_ = out.energy.Treb_calc_K;

   emit refluxFractionChanged();
   emit boilupFractionChanged();
   emit tColdKChanged();
   emit tHotKChanged();

   // ---- Material balance (product basis) ----
   // Include all product streams contributing to the overall balance:
   //   - Distillate / overhead (calculated by solver)
   //   - Side draws (configured in Draw Config)
   //   - Bottoms / residue (calculated by solver)
   mbModel_.reset();
   mbModel_.setFeedKg(feedRateKgph());

   if (std::isfinite(out.energy.D_kgph) && out.energy.D_kgph > 0.0)
      mbModel_.setDraw(QStringLiteral("Distillate (Overhead)"), out.energy.D_kgph);

   // ---- Material balance (product basis) ----
   mbModel_.reset();
   mbModel_.setFeedKg(feedRateKgph());

   // 1) Distillate / overhead product (actual solved)
   if (std::isfinite(out.energy.D_kgph) && out.energy.D_kgph > 0.0)
      mbModel_.setDraw(QStringLiteral("Distillate (Overhead)"), out.energy.D_kgph);

   // 2) Actual solved side draws (NOT the target draw specs)
   for (int i = 0; i < static_cast<int>(out.trays.size()); ++i)
   {
      const auto& tr = out.trays[static_cast<size_t>(i)];
      const double kgph = tr.drawFlow;

      if (!std::isfinite(kgph) || kgph <= 0.0)
         continue;

      const int tray1 = i + 1;
      QString label;
      for (const auto& v : drawSpecs_)
      {
         const QVariantMap m = v.toMap();
         if (m.value("tray").toInt() != tray1)
            continue;

         const QString name = m.value("name").toString().trimmed();
         if (!name.isEmpty()) {
            label = QStringLiteral("%1 [Tray %2]").arg(name).arg(tray1);
            break;
         }
      }

      if (label.isEmpty())
         label = QStringLiteral("Side Draw [Tray %1]").arg(tray1);

      mbModel_.setDraw(label, kgph);
   }

   // 3) Bottoms / residue product (actual solved)
   if (std::isfinite(out.energy.B_kgph) && out.energy.B_kgph > 0.0)
      mbModel_.setDraw(QStringLiteral("Bottoms (Residue)"), out.energy.B_kgph);

   mbModel_.finalize();

   // ---- Temperature spike analysis (ported from React App.js) ----
   struct SpikeFlags
   {
      std::vector<int> spikeTrays;
      std::vector<std::string> notes;
   };

   auto analyzeTemperatureSpikes = [&](const SolverOutputs& r) -> SpikeFlags
      {
         SpikeFlags f;
         const int N = static_cast<int>(r.trays.size());
         constexpr double spikeTol = 60.0;
         constexpr double monoTol = 25.0;
         constexpr double btmTol = 60.0;
         constexpr double topTol = 40.0;
         if (N <= 0)
            return f;

         const double TbottomTray = r.trays.front().tempK;
         const double TtopTray = r.trays.back().tempK;
         const double Treb = r.Treb_K;
         const double Tcond = r.Tcond_K;

         const std::string condType = r.condenserType;

         // A) Boundary agreement
         if (std::isfinite(Treb) && std::isfinite(TbottomTray))
         {
            const double d = std::abs(Treb - TbottomTray);
            if (d > btmTol)
            {
               std::ostringstream oss;
               oss.setf(std::ios::fixed);
               oss.precision(1);
               oss << "Warning: bottom tray T (" << TbottomTray
                  << " K) differs from reboiler T_hot (" << Treb
                  << " K) by " << d << " K.";
               f.notes.push_back(oss.str());
               f.spikeTrays.push_back(1);
            }
         }
         if (std::isfinite(Tcond) && std::isfinite(TtopTray))
         {
            const double d = std::abs(Tcond - TtopTray);
            if (d > topTol)
            {
               const std::string lvl = (condType == "total") ? "Info" : "Warning";
               std::ostringstream oss;
               oss.setf(std::ios::fixed);
               oss.precision(1);
               oss << lvl << ": top tray T (" << TtopTray
                  << " K) differs from condenser T_cold (" << Tcond
                  << " K) by " << d << " K.";
               f.notes.push_back(oss.str());
               f.spikeTrays.push_back(N);
            }
         }

         // B) Monotonicity & C) Local spikes
         for (int i = 0; i < N; ++i)
         {
            const double Ti = r.trays[static_cast<size_t>(i)].tempK;
            if (!std::isfinite(Ti))
               continue;

            if (i < N - 1)
            {
               const double Tnext = r.trays[static_cast<size_t>(i + 1)].tempK;
               if (std::isfinite(Tnext) && (Tnext - Ti) > monoTol)
               {
                  std::ostringstream oss;
                  oss.setf(std::ios::fixed);
                  oss.precision(1);
                  oss << "Warning: non-monotonic rise between Tray " << (i + 1)
                     << " (" << Ti << " K) and Tray " << (i + 2)
                     << " (" << Tnext << " K), Δ=" << (Tnext - Ti) << " K.";
                  f.notes.push_back(oss.str());
                  f.spikeTrays.push_back(i + 2);
               }
            }

            if (i > 0 && i < N - 1)
            {
               const double Tm1 = r.trays[static_cast<size_t>(i - 1)].tempK;
               const double Tp1 = r.trays[static_cast<size_t>(i + 1)].tempK;
               if (std::isfinite(Tm1) && std::isfinite(Tp1))
               {
                  const double m = 0.5 * (Tm1 + Tp1);
                  const double d = std::abs(Ti - m);
                  if (d > spikeTol)
                  {
                     std::ostringstream oss;
                     oss.setf(std::ios::fixed);
                     oss.precision(1);
                     oss << "Warning: local spike at Tray " << (i + 1)
                        << ": T=" << Ti << " K deviates " << d
                        << " K from neighbors’ mean " << m << " K.";
                     f.notes.push_back(oss.str());
                     f.spikeTrays.push_back(i + 1);
                  }
               }
            }
         }

         // unique + sort
         std::sort(f.spikeTrays.begin(), f.spikeTrays.end());
         f.spikeTrays.erase(std::unique(f.spikeTrays.begin(), f.spikeTrays.end()), f.spikeTrays.end());
         return f;
      };

   // Attach solver diagnostics + spike notes to the Diagnostics panel
   auto addDiag = [&](const QString& level, const QString& message)
      {
         diagnosticsModel_.append(level, message);
      };

   // 1) Diagnostics returned by the solver (ported from JS diagnostics.push/addDiag).
   for (const auto& d : out.diagnostics)
   {
      QString lvl = QString::fromStdString(d.level).toLower();
      if (lvl == "warning")
         lvl = "warn";
      if (lvl == "warn")
         lvl = "warn";
      if (lvl == "error")
         lvl = "error";
      if (lvl != "warn" && lvl != "error")
         lvl = "info";
      addDiag(lvl, QString::fromStdString(d.message));
   }

   // 2) Temperature spike notes (same logic as React App.js)
   const auto flags = analyzeTemperatureSpikes(out);
   for (const auto& note : flags.notes)
   {
      const QString q = QString::fromStdString(note);
      const QString low = q.left(8).toLower();
      if (low.startsWith("warning"))
         addDiag("warn", q);
      else if (low.startsWith("info"))
         addDiag("info", q);
      else
         addDiag("info", q);
   }

   // 3) HYSYS-like explanation for TOTAL condenser top-spike (mirrors App.js diagnostics.push)
   const int Ntrays = static_cast<int>(out.trays.size());
   const bool topSpike = (Ntrays > 0) &&
      (std::find(flags.spikeTrays.begin(), flags.spikeTrays.end(), Ntrays) != flags.spikeTrays.end());
   if (topSpike && QString::fromStdString(out.condenserType).toLower() == "total")
   {
      const double Tcold = out.Tcond_K;
      const double Ttop = out.trays.empty() ? NAN : out.trays.back().tempK;
      const double dT = (std::isfinite(Tcold) && std::isfinite(Ttop)) ? std::abs(Ttop - Tcold) : NAN;

      QString msg = QString("Temperature 'spike' at Tray %1 is usually expected for a TOTAL condenser: "
         "Tray %1 is a condenser boundary (V forced to 0) and may report an equilibrium / inlet temperature "
         "that won't follow the internal tray profile. ")
         .arg(Ntrays);

      if (std::isfinite(dT))
         msg += QString("Here |T(top) - T_cold| ≈ %1 K. ").arg(dT, 0, 'f', 1);

      msg +=
         "This typically reflects condenser outlet subcooling / reflux enthalpy, not an internal column instability.";
      addDiag("info", msg);
   }

   if (diagnosticsModel_.rowCount() == 0)
   {
      addDiag("info", "No diagnostics.");
   }

   // Run Results (tray profile + stream summary)
   runResults_ = QString::fromStdString(out.runResultsText);
   emit runResultsChanged();

   solved_ = true;
   emit solvedChanged();
}

// ---------------- Private helpers ----------------

void ColumnUnitState::applyCrudeDefaults(const QString& crude)
{
   const FluidDefinition fluid = getFluidDefinition(crude.toStdString());
   const CrudeInitialSettings& s = fluid.columnDefaults;

   // These defaults come from cpp/unitops/column/config/CrudeInitialSettings.*
   setFeedRateKgph(s.feedRate_kgph);
   setFeedTray(s.feedTray);
   setFeedTempK(s.Tfeed_K);
   activeFeedStream()->setPressurePa(s.Ptop_Pa);

   setTopPressurePa(s.Ptop_Pa);
   setDpPerTrayPa(s.dP_perTray_Pa);

   // Specs mapping (config uses lowercase strings; UI uses TitleCase)
   if (s.condenserSpec == "temperature")
      setCondenserSpec("temperature");
   else if (s.condenserSpec == "duty")
      setCondenserSpec("duty");
   else
      setCondenserSpec("reflux");

   if (s.reboilerSpec == "temperature")
      setReboilerSpec("temperature");
   else if (s.reboilerSpec == "duty")
      setReboilerSpec("duty");
   else
      setReboilerSpec("boilup");

   // Ratios/duties
   setQcKW(s.Qc_kW); // UI expects positive magnitudes
   setQrKW(s.Qr_kW);
   setRefluxRatio(s.refluxRatio);
   setBoilupRatio(s.reboilRatio);

   // Temps (guesses)
   setTopTsetK(s.Ttop_K > 0.0 ? s.Ttop_K : topTsetK_);
   setBottomTsetK(s.Tbottom_K > 0.0 ? s.Tbottom_K : bottomTsetK_);

   // Murphree
   setEtaVTop(s.murphree.etaV_top);
   setEtaVMid(s.murphree.etaV_mid);
   setEtaVBot(s.murphree.etaV_bot);
   setEtaLTop(s.murphree.etaL_top);
   setEtaLMid(s.murphree.etaL_mid);
   setEtaLBot(s.murphree.etaL_bot);

   // Default side draws: populate the editable DrawConfigView from the crude registry
   // (React parity: crudeInitialSettings.drawSpecsByTrayIndex is the source of defaults).
   {
      const auto& nameMap = defaultDrawNamesByTray32(); // 1-based tray -> label
      QVariantList rows;
      rows.reserve(static_cast<int>(s.drawSpecsByTrayIndex.size()));

      // Copy to a sortable vector so the UI order is stable (top-to-bottom by tray number).
      struct Row
      {
         int tray1;
         double pct;
         QString name;
      };
      std::vector<Row> tmp;
      tmp.reserve(s.drawSpecsByTrayIndex.size());

      for (const auto& kv : s.drawSpecsByTrayIndex)
      {
         const int trayIndex0 = kv.first;
         const double fracOfFeed = kv.second;
         if (trayIndex0 < 0)
            continue;
         const int tray1 = trayIndex0 + 1;
         if (tray1 <= 1 || tray1 >= trays_)
            continue;
         if (!(fracOfFeed > 0.0))
            continue;

         auto it = nameMap.find(tray1);
         const QString label = (it != nameMap.end())
            ? QString::fromStdString(it->second)
            : QString("Draw [Tray %1]").arg(tray1);

         tmp.push_back(Row{ tray1, fracOfFeed * 100.0, label });
      }

      std::sort(tmp.begin(), tmp.end(), [](const Row& a, const Row& b)
         {
            return a.tray1 > b.tray1; // top (32) first
         });

      for (const auto& r : tmp)
      {
         QVariantMap m;
         m.insert("name", r.name);
         m.insert("tray", r.tray1);
         m.insert("pct", r.pct);
         rows.push_back(m);
      }

      // Reuse the existing setter so QML normalization + signal emission stays consistent.
      setDrawSpecs(rows);
   }


   // Reset tray table to match expected count.
   trayModel_.resetToDefaults(trays_);
   solved_ = false;
   emit solvedChanged();
}

// --- Full-fidelity solver log file (disk) ------------------------------------
// Goal: during Visual Studio dev runs, write logs to <projectRoot>/logs.
// Fallback: if a project root cannot be found, use Qt AppDataLocation/logs.

static QString findProjectRootCandidate_(const QString& startDir)
{
   QDir dir(startDir);
   // Walk up a bounded number of levels to avoid infinite loops on weird mounts.
   for (int depth = 0; depth < 12; ++depth)
   {
      const QString abs = dir.absolutePath();
      // Heuristics: any of these markers indicates the repo/project root.
      if (QFile::exists(dir.filePath("CMakeLists.txt")) ||
         QFile::exists(dir.filePath("CMakePresets.json")) ||
         QFile::exists(dir.filePath("chatgpt5_qt_adt_simulator.slnx")) ||
         dir.exists(".git"))
      {
         return abs;
      }
      if (!dir.cdUp())
         break;
   }
   return QString();
}

static QString findProjectRoot_()
{
   // Prefer the working directory (Visual Studio/CMake typically sets this to the build dir).
   const QString cwd = QDir::currentPath();
   QString root = findProjectRootCandidate_(cwd);
   if (!root.isEmpty())
      return root;

   // Also try the executable directory (when launched from VS or from an install folder).
   root = findProjectRootCandidate_(QCoreApplication::applicationDirPath());
   if (!root.isEmpty())
      return root;

   return QString();
}

void ColumnUnitState::openSolverLogFile_()
{
   QMutexLocker lk(&solverLogMutex_);

   // Close any prior file.
   if (solverLogFile_.isOpen())
   {
      solverLogStream_.flush();
      solverLogFile_.close();
   }
   solverLogFilePath_.clear();

   // Determine logs directory.
   QString logsDir;
   const QString projectRoot = findProjectRoot_();
   if (!projectRoot.isEmpty())
   {
      logsDir = QDir(projectRoot).filePath("logs");
   }
   else
   {
      // Fallback for deployed runs.
      logsDir = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).filePath("logs");
   }

   QDir().mkpath(logsDir);

   // Timestamped filename.
   const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
   solverLogFilePath_ = QDir(logsDir).filePath(QString("run_%1.log").arg(stamp));

   solverLogFile_.setFileName(solverLogFilePath_);
   if (!solverLogFile_.open(QIODevice::WriteOnly | QIODevice::Text))
   {
      // Don't fail the solve if file logging fails; just report to VS output.
      qDebug() << "[LOG] Failed to open solver log file:" << solverLogFilePath_;
      return;
   }

   solverLogStream_.setDevice(&solverLogFile_);
   // Qt 6 removed QTextStream::setCodec; use setEncoding instead.
   solverLogStream_.setEncoding(QStringConverter::Utf8);

   // Header line for context.
   solverLogStream_ << QString("[LOG] %1  projectRoot=%2\n")
      .arg(QDateTime::currentDateTime().toString(Qt::ISODate))
      .arg(projectRoot.isEmpty() ? QString("<fallback>") : projectRoot);
   solverLogStream_.flush();
}

void ColumnUnitState::closeSolverLogFile_()
{
   QMutexLocker lk(&solverLogMutex_);
   if (!solverLogFile_.isOpen()) return;
   solverLogStream_.flush();
   solverLogFile_.close();
}

void ColumnUnitState::writeSolverLogLine_(const QString& line)
{
   if (line.isEmpty())
      return;

   QMutexLocker lk(&solverLogMutex_);

   // If the file isn't open (e.g., open failed), do nothing.
   if (!solverLogFile_.isOpen())
      return;

   solverLogStream_ << line << "\n";

   // Flush each line so you always have a complete trace even if the app crashes.
   // If this ever becomes too slow, we can switch to buffered flushing.
   solverLogStream_.flush();
}