#include "AppState.h"

#include <QtCore/QDebug>
#include <cmath>
#include <algorithm>
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


#include "lib/config/CrudeInitialSettings.hpp"
#include "lib/sim/ColumnSolver.hpp"
#include "lib/thermo/EOSK.hpp"
#include "lib/thermo/eos/PRSV.hpp"

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

AppState::AppState(QObject* parent)
   : QObject(parent)
     , trayModel_(this)
     , diagnosticsModel_(this)
     , runLogModel_(this)
     , mbModel_(this)
{
   // Populate crude list from config registry.
   crudeNames_.clear();
   for (const auto& s : getAvailableCrudeNames())
      crudeNames_.push_back(QString::fromStdString(s));

   // Pick a stable default.
   selectedCrude_ = crudeNames_.contains("Brent") ? "Brent" : (crudeNames_.isEmpty() ? "Brent" : crudeNames_.front());

   applyCrudeDefaults(selectedCrude_);

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
      clearSpecsDirty_();
   });
}

void AppState::setSolving_(bool v)
{
   if (solving_ == v)
      return;
   solving_ = v;
   emit solvingChanged();
}

void AppState::setSolveElapsedMs_(qint64 v)
{
   if (solveElapsedMs_ == v)
      return;
   solveElapsedMs_ = v;
   emit solveElapsedMsChanged();
}

void AppState::setSpecsDirty_(bool v)
{
   if (specsDirty_ == v)
      return;
   specsDirty_ = v;
   emit specsDirtyChanged();
}

void AppState::markSpecsDirty_()
{
   // Mark that user-editable specs have changed since the last solve.
   setSpecsDirty_(true);
}

void AppState::clearSpecsDirty_()
{
   // Clear after a successful solve (or when starting a new solve).
   setSpecsDirty_(false);
}


void AppState::setSolverLogLevel(int v)
{
   v = std::clamp(v, 0, 2);
   if (solverLogLevel_ == v)
      return;
   solverLogLevel_ = v;
   emit solverLogLevelChanged();
}

void AppState::setTrays(int v)
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

QStringList AppState::crudeNames() const
{
   return crudeNames_;
}

QString AppState::selectedCrude() const
{
   return selectedCrude_;
}

void AppState::setSelectedCrude(const QString& v)
{
   if (selectedCrude_ == v)
      return;

   selectedCrude_ = v;

   // Apply defaults first so QML sees a consistent snapshot when it reacts to
   // selectedCrudeChanged (especially important when UI controls have had
   // their bindings broken by user edits).
   applyCrudeDefaults(selectedCrude_);
   markSpecsDirty_();

   emit selectedCrudeChanged();
}

// ---------------- EOS settings ----------------

QString AppState::eosMode() const
{
   return eosMode_;
}

void AppState::setEosMode(const QString& v)
{
   if (eosMode_ == v)
      return;
   eosMode_ = v;
   markSpecsDirty_();
   emit eosModeChanged();
}

QString AppState::eosManual() const
{
   return eosManual_;
}

void AppState::setEosManual(const QString& v)
{
   if (eosManual_ == v)
      return;
   eosManual_ = v;
   markSpecsDirty_();
   emit eosManualChanged();
}

// ---------------- Condenser / Reboiler types ----------------

QString AppState::condenserType() const
{
   return condenserType_;
}

void AppState::setCondenserType(const QString& v)
{
   if (condenserType_ == v)
      return;
   condenserType_ = v;
   markSpecsDirty_();
   emit condenserTypeChanged();
}

QString AppState::reboilerType() const
{
   return reboilerType_;
}

void AppState::setReboilerType(const QString& v)
{
   if (reboilerType_ == v)
      return;
   reboilerType_ = v;
   markSpecsDirty_();
   emit reboilerTypeChanged();
}

// ---------------- Pressures ----------------

double AppState::topPressurePa() const
{
   return topPressurePa_;
}

void AppState::setTopPressurePa(double v)
{
   if (qFuzzyCompare(topPressurePa_, v))
      return;
   topPressurePa_ = v;
   markSpecsDirty_();
   emit topPressurePaChanged();
}

double AppState::dpPerTrayPa() const
{
   return dpPerTrayPa_;
}

void AppState::setDpPerTrayPa(double v)
{
   if (qFuzzyCompare(dpPerTrayPa_, v))
      return;
   dpPerTrayPa_ = v;
   markSpecsDirty_();
   emit dpPerTrayPaChanged();
}

// ---------------- Murphree ----------------

double AppState::etaVTop() const { return etaVTop_; }

void AppState::setEtaVTop(double v)
{
   if (qFuzzyCompare(etaVTop_, v))
      return;
   etaVTop_ = v;
   markSpecsDirty_();
   emit etaVTopChanged();
}

double AppState::etaVMid() const { return etaVMid_; }

void AppState::setEtaVMid(double v)
{
   if (qFuzzyCompare(etaVMid_, v))
      return;
   etaVMid_ = v;
   markSpecsDirty_();
   emit etaVMidChanged();
}

double AppState::etaVBot() const { return etaVBot_; }

void AppState::setEtaVBot(double v)
{
   if (qFuzzyCompare(etaVBot_, v))
      return;
   etaVBot_ = v;
   markSpecsDirty_();
   emit etaVBotChanged();
}

bool AppState::enableEtaL() const { return enableEtaL_; }

void AppState::setEnableEtaL(bool v)
{
   if (enableEtaL_ == v)
      return;
   enableEtaL_ = v;
   markSpecsDirty_();
   emit enableEtaLChanged();
}

double AppState::etaLTop() const { return etaLTop_; }

void AppState::setEtaLTop(double v)
{
   if (qFuzzyCompare(etaLTop_, v))
      return;
   etaLTop_ = v;
   markSpecsDirty_();
   emit etaLTopChanged();
}

double AppState::etaLMid() const { return etaLMid_; }

void AppState::setEtaLMid(double v)
{
   if (qFuzzyCompare(etaLMid_, v))
      return;
   etaLMid_ = v;
   markSpecsDirty_();
   emit etaLMidChanged();
}

double AppState::etaLBot() const { return etaLBot_; }

void AppState::setEtaLBot(double v)
{
   if (qFuzzyCompare(etaLBot_, v))
      return;
   etaLBot_ = v;
   markSpecsDirty_();
   emit etaLBotChanged();
}

// ---------------- Feed ----------------

double AppState::feedRateKgph() const { return feedRateKgph_; }

void AppState::setFeedRateKgph(double v)
{
   if (qFuzzyCompare(feedRateKgph_, v))
      return;
   feedRateKgph_ = v;
   markSpecsDirty_();
   emit feedRateKgphChanged();
}

double AppState::feedTempK() const { return feedTempK_; }

void AppState::setFeedTempK(double v)
{
   if (qFuzzyCompare(feedTempK_, v))
      return;
   feedTempK_ = v;
   markSpecsDirty_();
   emit feedTempKChanged();
}

int AppState::feedTray() const { return feedTray_; }

void AppState::setFeedTray(int v)
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

QVariantList AppState::drawSpecs() const { return drawSpecs_; }

void AppState::setDrawSpecs(const QVariantList& v)
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

QString AppState::condenserSpec() const { return condenserSpec_; }

void AppState::setCondenserSpec(const QString& v)
{

   if (condenserSpec_ == v) return;
   condenserSpec_ = v;
   markSpecsDirty_();
   emit condenserSpecChanged();
}

QString AppState::reboilerSpec() const { return reboilerSpec_; }

void AppState::setReboilerSpec(const QString& v)
{
   if (reboilerSpec_ == v)
      return;
   reboilerSpec_ = v;
   markSpecsDirty_();
   emit reboilerSpecChanged();
}

// ---------------- Numbers ----------------

double AppState::refluxRatio() const { return refluxRatio_; }

void AppState::setRefluxRatio(double v)
{
   if (qFuzzyCompare(refluxRatio_, v))
      return;
   refluxRatio_ = v;
   markSpecsDirty_();
   emit refluxRatioChanged();
}

double AppState::boilupRatio() const { return boilupRatio_; }

void AppState::setBoilupRatio(double v)
{
   if (qFuzzyCompare(boilupRatio_, v)) 
      return;
   boilupRatio_ = v;
   markSpecsDirty_();
   emit boilupRatioChanged();
}

double AppState::qcKW() const { return qcKW_; }

void AppState::setQcKW(double v)
{
   if (qFuzzyCompare(qcKW_, v))
      return;
   qcKW_ = v;
   markSpecsDirty_();
   emit qcKWChanged();
}

double AppState::qrKW() const { return qrKW_; }
double AppState::qcCalcKW() const { return qcCalcKW_; }
double AppState::qrCalcKW() const { return qrCalcKW_; }

void AppState::setQrKW(double v)
{
   if (qFuzzyCompare(qrKW_, v))
      return;
   qrKW_ = v;
   markSpecsDirty_();
   emit qrKWChanged();
}

double AppState::topTsetK() const { return topTsetK_; }

void AppState::setTopTsetK(double v)
{
   if (qFuzzyCompare(topTsetK_, v))
      return;
   topTsetK_ = v;
   markSpecsDirty_();
   emit topTsetKChanged();
}

double AppState::bottomTsetK() const { return bottomTsetK_; }

void AppState::setBottomTsetK(double v)
{
   if (qFuzzyCompare(bottomTsetK_, v))
      return;
   bottomTsetK_ = v;
   markSpecsDirty_();
   emit bottomTsetKChanged();
}

// ---------------- Models ----------------

bool AppState::solved() const { return solved_; }

TrayModel* AppState::trayModel() { return &trayModel_; }
DiagnosticsModel* AppState::diagnosticsModel() { return &diagnosticsModel_; }
RunLogModel* AppState::runLogModel() { return &runLogModel_; }
MaterialBalanceModel* AppState::materialBalanceModel() { return &mbModel_; }

// ---------------- Actions ----------------

void AppState::reset()
{
   applyCrudeDefaults(selectedCrude_);
   diagnosticsModel_.clear();
   runLogModel_.clear();
   mbModel_.reset();

   solved_ = false;
   emit solvedChanged();
}

void AppState::resetDrawSpecsToDefaults()
{
   // Reset only the Draw Config rows (not the other crude settings).
   const CrudeInitialSettings s = getCrudeInitialSettings(selectedCrude_.toStdString());

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

      tmp.push_back(Row{tray1, fracOfFeed * 100.0, label});
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

void AppState::solve()
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
   in.crudeName = selectedCrude_.toStdString();
   in.trays = trays_;
   in.feedRateKgph = feedRateKgph_;
   in.feedTray = std::clamp(feedTray_, 1, in.trays);
   in.feedTempK = feedTempK_;
   in.topPressurePa = topPressurePa_;
   in.dpPerTrayPa = dpPerTrayPa_;

   // Capture UI verbosity at the moment the solve starts.
   // This controls ONLY what goes to the UI RunLogModel.
   const int uiLogLevel = solverLogLevel_; // 0=None, 1=Summary, 2=Debug

   // Solver emission level controls what the simulator emits via opt.onLog.
   // Even when UI verbosity is OFF, we still want full-fidelity file logging.
   const int solverEmitLevel = (uiLogLevel <= 0) ? 1 : uiLogLevel; // 2=Debug
   in.logLevel = static_cast<LogLevel>(solverEmitLevel);

   in.eosMode = eosMode_.toStdString();
   in.eosManual = eosManual_.toStdString();
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
   runLogModel_.append(QString("Solve: crude=%1 trays=%2 feed=%3 kg/h feedTray=%4")
                       .arg(selectedCrude_)
                       .arg(in.trays)
                       .arg(feedRateKgph_, 0, 'f', 0)
                       .arg(in.feedTray));
   // Open per-solve full-fidelity log file (disk) before launching worker.
   openSolverLogFile_();

   // --- thread-safe buffered log capture (solver thread -> UI thread flush timer) ---
   QPointer<AppState> self(this);
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

void AppState::clearRunOutputs_()
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

void AppState::applySolveOutputs_(const SolverInputs& in, const SolverOutputs& out)
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
         trayModel_.setTray(i, t.tempK, t.vFrac, t.V_kgph, t.L_kgph, hasDraw, /*unused*/ false, drawLabel, /*unused*/
                            false);
      }
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

   // Material balance: use available tray drawFlow placeholders if any.
   // ---- Material balance (product basis) ----
   // In the React master UI, each configured draw is displayed as a mass flow out of the column,
   // tagged with its tray number, and the sum of all draws should equal the feed.
   mbModel_.setFeedKg(feedRateKgph_);

   // DrawConfigView pushes { name, tray, basis, phase, value, pct } into drawSpecs_.
   // Compute displayed draw flow from selected basis.
   for (const auto& v : drawSpecs_)
   {
      const QVariantMap m = v.toMap();
      const QString name = m.value("name").toString();
      const int tray = m.value("tray").toInt();

      const QString basis = m.value("basis").toString().trimmed().isEmpty()
         ? QString("feedPct")
         : m.value("basis").toString().trimmed();

      const double value = m.contains("value")
         ? m.value("value").toDouble()
         : m.value("pct").toDouble();

      if (name.isEmpty() || tray <= 0 || !std::isfinite(value) || value <= 0.0)
         continue;

      double kgph = 0.0;
      if (basis.compare("kgph", Qt::CaseInsensitive) == 0)
         kgph = value;
      else // feedPct (legacy + default)
         kgph = feedRateKgph_ * (value / 100.0);

      const QString label = QString("%1 [Tray %2]").arg(name).arg(tray);
      mbModel_.setDraw(label, std::max(0.0, kgph));
   }
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

void AppState::applyCrudeDefaults(const QString& crude)
{
   const CrudeInitialSettings s = getCrudeInitialSettings(crude.toStdString());

   // These defaults come from cpp/lib/config/CrudeInitialSettings.*
   setFeedRateKgph(s.feedRate_kgph);
   setFeedTray(s.feedTray);
   setFeedTempK(s.Tfeed_K);

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

         tmp.push_back(Row{tray1, fracOfFeed * 100.0, label});
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

void AppState::openSolverLogFile_()
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

void AppState::closeSolverLogFile_()
{
   QMutexLocker lk(&solverLogMutex_);
   if (!solverLogFile_.isOpen()) return;
   solverLogStream_.flush();
   solverLogFile_.close();
}

void AppState::writeSolverLogLine_(const QString& line)
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
