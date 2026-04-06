#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QDir>
#include <QStandardPaths>
#include <QMutex>
#include <QPointer>

#include "flowsheet/state/ProcessUnitState.h"
#include "unitops/column/sim/ColumnSolver.hpp"  // SolverInputs / SolverOutputs / ProgressEvent
#include "models/TrayModel.h"
#include "models/DiagnosticsModel.h"
#include "models/RunLogModel.h"
#include "models/MaterialBalanceModel.h"
#include "streams/state/MaterialStreamState.h"

#include "./flowsheet/state/ProcessUnitState.h"

class FlowsheetState;

class ColumnUnitState : public ProcessUnitState {
   Q_OBJECT

      Q_PROPERTY(QStringList crudeNames READ crudeNames CONSTANT)
      Q_PROPERTY(QObject* feedStream READ feedStream NOTIFY feedStreamChanged)
      Q_PROPERTY(QString connectedFeedStreamName READ connectedFeedStreamName NOTIFY feedStreamChanged)
      Q_PROPERTY(QString selectedCrude READ selectedCrude WRITE setSelectedCrude NOTIFY selectedCrudeChanged)
      Q_PROPERTY(QString selectedFluidPackageName READ selectedFluidPackageName NOTIFY selectedFluidPackageChanged)
      Q_PROPERTY(QString effectiveThermoMethod READ effectiveThermoMethod NOTIFY effectiveThermoMethodChanged)
      Q_PROPERTY(bool packageThermoControlled READ packageThermoControlled NOTIFY selectedFluidPackageChanged)

      Q_PROPERTY(bool solving READ solving NOTIFY solvingChanged)
      Q_PROPERTY(qint64 solveElapsedMs READ solveElapsedMs NOTIFY solveElapsedMsChanged)
      Q_PROPERTY(bool specsDirty READ specsDirty NOTIFY specsDirtyChanged)

      Q_PROPERTY(int solverLogLevel READ solverLogLevel WRITE setSolverLogLevel NOTIFY solverLogLevelChanged) // 0=None 1=Summary 2=Debug

      // New: tray count controls
      Q_PROPERTY(int trays READ trays WRITE setTrays NOTIFY traysChanged)
      Q_PROPERTY(int minTrays READ minTrays CONSTANT)
      Q_PROPERTY(int maxTrays READ maxTrays CONSTANT)
      Q_PROPERTY(int maxSideDraws READ maxSideDraws NOTIFY traysChanged)
      Q_PROPERTY(bool separatorMode READ separatorMode NOTIFY traysChanged)

      Q_PROPERTY(QString eosMode READ eosMode WRITE setEosMode NOTIFY eosModeChanged)          // auto | manual
      Q_PROPERTY(QString eosManual READ eosManual WRITE setEosManual NOTIFY eosManualChanged) // PR | PRSV | SRK

      Q_PROPERTY(QString condenserType READ condenserType WRITE setCondenserType NOTIFY condenserTypeChanged) // total | partial
      Q_PROPERTY(QString reboilerType READ reboilerType WRITE setReboilerType NOTIFY reboilerTypeChanged)     // partial | total

      Q_PROPERTY(double topPressurePa READ topPressurePa WRITE setTopPressurePa NOTIFY topPressurePaChanged)
      Q_PROPERTY(double dpPerTrayPa READ dpPerTrayPa WRITE setDpPerTrayPa NOTIFY dpPerTrayPaChanged)

      Q_PROPERTY(double etaVTop READ etaVTop WRITE setEtaVTop NOTIFY etaVTopChanged)
      Q_PROPERTY(double etaVMid READ etaVMid WRITE setEtaVMid NOTIFY etaVMidChanged)
      Q_PROPERTY(double etaVBot READ etaVBot WRITE setEtaVBot NOTIFY etaVBotChanged)

      Q_PROPERTY(bool enableEtaL READ enableEtaL WRITE setEnableEtaL NOTIFY enableEtaLChanged)
      Q_PROPERTY(double etaLTop READ etaLTop WRITE setEtaLTop NOTIFY etaLTopChanged)
      Q_PROPERTY(double etaLMid READ etaLMid WRITE setEtaLMid NOTIFY etaLMidChanged)
      Q_PROPERTY(double etaLBot READ etaLBot WRITE setEtaLBot NOTIFY etaLBotChanged)

      Q_PROPERTY(double feedRateKgph READ feedRateKgph WRITE setFeedRateKgph NOTIFY feedRateKgphChanged)
      Q_PROPERTY(double feedTempK READ feedTempK WRITE setFeedTempK NOTIFY feedTempKChanged)
      Q_PROPERTY(int feedTray READ feedTray WRITE setFeedTray NOTIFY feedTrayChanged)

      Q_PROPERTY(QVariantList drawSpecs READ drawSpecs WRITE setDrawSpecs NOTIFY drawSpecsChanged)

      Q_PROPERTY(QString condenserSpec READ condenserSpec WRITE setCondenserSpec NOTIFY condenserSpecChanged)
      Q_PROPERTY(QString reboilerSpec READ reboilerSpec WRITE setReboilerSpec NOTIFY reboilerSpecChanged)

      Q_PROPERTY(double refluxRatio READ refluxRatio WRITE setRefluxRatio NOTIFY refluxRatioChanged)
      Q_PROPERTY(double boilupRatio READ boilupRatio WRITE setBoilupRatio NOTIFY boilupRatioChanged)
      Q_PROPERTY(double qcKW READ qcKW WRITE setQcKW NOTIFY qcKWChanged)
      Q_PROPERTY(double qrKW READ qrKW WRITE setQrKW NOTIFY qrKWChanged)
      Q_PROPERTY(double qcCalcKW READ qcCalcKW NOTIFY qcCalcKWChanged)
      Q_PROPERTY(double qrCalcKW READ qrCalcKW NOTIFY qrCalcKWChanged)
      Q_PROPERTY(double topTsetK READ topTsetK WRITE setTopTsetK NOTIFY topTsetKChanged)
      Q_PROPERTY(double bottomTsetK READ bottomTsetK WRITE setBottomTsetK NOTIFY bottomTsetKChanged)

      // Derived/result fields displayed in the "Column" panel
      Q_PROPERTY(double refluxFraction READ refluxFraction NOTIFY refluxFractionChanged)
      Q_PROPERTY(double boilupFraction READ boilupFraction NOTIFY boilupFractionChanged)
      Q_PROPERTY(double tColdK READ tColdK NOTIFY tColdKChanged)
      Q_PROPERTY(double tHotK READ tHotK NOTIFY tHotKChanged)

      Q_PROPERTY(bool solved READ solved NOTIFY solvedChanged)

      Q_PROPERTY(TrayModel* trayModel READ trayModel CONSTANT)
      Q_PROPERTY(DiagnosticsModel* diagnosticsModel READ diagnosticsModel CONSTANT)
      Q_PROPERTY(RunLogModel* runLogModel READ runLogModel CONSTANT)
      Q_PROPERTY(MaterialBalanceModel* materialBalanceModel READ materialBalanceModel CONSTANT)
      Q_PROPERTY(QString runResults READ runResults NOTIFY runResultsChanged)

public:
   explicit ColumnUnitState(QObject* parent = nullptr);

   bool solving() const {
      return solving_;
   }
   qint64 solveElapsedMs() const {
      return solveElapsedMs_;
   }
   bool specsDirty() const {
      return specsDirty_;
   }
   int solverLogLevel() const {
      return solverLogLevel_;
   }
   void setSolverLogLevel(int v);

   // New tray controls
   int trays() const {
      return trays_;
   }
   void setTrays(int v);
   int minTrays() const {
      return 1;
   }
   int maxTrays() const {
      return 200;
   }
   int maxSideDraws() const {
      return (trays_ > 2) ? (trays_ - 2) : 0;
   }
   bool separatorMode() const {
      return trays_ <= 2;
   }

   QStringList crudeNames() const;
   QObject* feedStream() { return activeFeedStream(); }
   MaterialStreamState* activeFeedStream();
   const MaterialStreamState* activeFeedStream() const;
   void setFlowsheetState(FlowsheetState* flowsheet);
   void setConnectedFeedStreamUnitId(const QString& streamUnitId);
   QString connectedFeedStreamUnitId() const { return connectedFeedStreamUnitId_; }
   QString connectedFeedStreamName() const;
   void setConnectedProductStreamUnitId(const QString& portName, const QString& streamUnitId);
   QString connectedProductStreamUnitId(const QString& portName) const;
   QString selectedCrude() const;
   void setSelectedCrude(const QString& v);
   QString selectedFluidPackageName() const;
   QString effectiveThermoMethod() const;
   bool packageThermoControlled() const;

   QString eosMode() const;
   void setEosMode(const QString& v);
   QString eosManual() const;
   void setEosManual(const QString& v);

   QString condenserType() const;
   void setCondenserType(const QString& v);
   QString reboilerType() const;
   void setReboilerType(const QString& v);

   double topPressurePa() const;
   void setTopPressurePa(double v);
   double dpPerTrayPa() const;
   void setDpPerTrayPa(double v);

   double etaVTop() const;
   void setEtaVTop(double v);
   double etaVMid() const;
   void setEtaVMid(double v);
   double etaVBot() const;
   void setEtaVBot(double v);

   bool enableEtaL() const;
   void setEnableEtaL(bool v);
   double etaLTop() const;
   void setEtaLTop(double v);
   double etaLMid() const;
   void setEtaLMid(double v);
   double etaLBot() const;
   void setEtaLBot(double v);

   double feedRateKgph() const;
   void setFeedRateKgph(double v);
   double feedTempK() const;
   void setFeedTempK(double v);
   int feedTray() const;
   void setFeedTray(int v);

   QString condenserSpec() const;
   void setCondenserSpec(const QString& v);
   QString reboilerSpec() const;
   void setReboilerSpec(const QString& v);

   double refluxRatio() const;
   void setRefluxRatio(double v);
   double boilupRatio() const;
   void setBoilupRatio(double v);
   double qcKW() const;
   void setQcKW(double v);
   double qrKW() const;
   double qcCalcKW() const;
   double qrCalcKW() const;
   void setQrKW(double v);
   double topTsetK() const;
   void setTopTsetK(double v);
   double bottomTsetK() const;
   void setBottomTsetK(double v);

   double refluxFraction() const {
      return refluxFraction_;
   }
   double boilupFraction() const {
      return boilupFraction_;
   }
   double tColdK() const {
      return tColdK_;
   }
   double tHotK() const {
      return tHotK_;
   }

   bool solved() const;

   TrayModel* trayModel();
   DiagnosticsModel* diagnosticsModel();
   RunLogModel* runLogModel();
   MaterialBalanceModel* materialBalanceModel();

   QString runResults() const {
      return runResults_;
   }

   void clearRunOutputs_();

   Q_INVOKABLE void solve();
   Q_INVOKABLE void reset();
   Q_INVOKABLE void resetDrawSpecsToDefaults();

   QVariantList drawSpecs() const;
   void setDrawSpecs(const QVariantList& v);

signals:
   void solverLogLevelChanged();
   void solvingChanged();
   void solveElapsedMsChanged();
   void specsDirtyChanged();

   void traysChanged();

   void drawSpecsChanged();
   void selectedCrudeChanged();
   void selectedFluidPackageChanged();
   void effectiveThermoMethodChanged();
   void feedStreamChanged();

   void eosModeChanged();
   void eosManualChanged();
   void condenserTypeChanged();
   void reboilerTypeChanged();
   void topPressurePaChanged();
   void dpPerTrayPaChanged();
   void etaVTopChanged();
   void etaVMidChanged();
   void etaVBotChanged();
   void enableEtaLChanged();
   void etaLTopChanged();
   void etaLMidChanged();
   void etaLBotChanged();
   void feedRateKgphChanged();
   void feedTempKChanged();
   void feedTrayChanged();
   void condenserSpecChanged();
   void reboilerSpecChanged();
   void refluxRatioChanged();
   void boilupRatioChanged();
   void qcKWChanged();
   void qrKWChanged();
   void qcCalcKWChanged();
   void qrCalcKWChanged();
   void topTsetKChanged();
   void bottomTsetKChanged();

   void refluxFractionChanged();
   void boilupFractionChanged();
   void tColdKChanged();
   void tHotKChanged();
   void solvedChanged();
   void runResultsChanged();

private:
   void setSolving_(bool v);
   void setSolveElapsedMs_(qint64 v);
   void setSpecsDirty_(bool v);
   void markSpecsDirty_();
   void clearSpecsDirty_();
   void applySolveOutputs_(const SolverInputs& in, const SolverOutputs& out);
   void attachActiveFeedStreamSignals_();
   void detachActiveFeedStreamSignals_();
   void pushProductStreamScaffolding_(const SolverOutputs& out);
   QString packageSelectedThermoMethod_() const;
   QString packageThermoLabel_() const;

   bool solving_ = false;
   bool specsDirty_ = false;
   int solverLogLevel_ = 1;
   qint64 solveElapsedMs_ = 0;
   QElapsedTimer solveElapsedTimer_;
   QTimer solveUiTick_;
   QFutureWatcher<SolverOutputs> solveWatcher_;
   SolverInputs pendingSolveInputs_;

   // New
   int trays_ = 32;

   QVariantList drawSpecs_;
   void applyCrudeDefaults(const QString& crude);

   QStringList crudeNames_;

   MaterialStreamState feedStream_;
   FlowsheetState* flowsheetState_ = nullptr;
   QString connectedFeedStreamUnitId_;
   QString connectedDistillateStreamUnitId_;
   QString connectedBottomsStreamUnitId_;
   QPointer<MaterialStreamState> observedActiveFeedStream_;
   QMetaObject::Connection activeFeedSelectedFluidConn_;
   QMetaObject::Connection activeFeedSelectedFluidPackageConn_;
   QMetaObject::Connection activeFeedFlowConn_;
   QMetaObject::Connection activeFeedTempConn_;
   QMetaObject::Connection activeFeedCompositionConn_;

   QString eosMode_ = "auto";
   QString eosManual_ = "PRSV";

   QString condenserType_ = "total";
   QString reboilerType_ = "partial";

   double topPressurePa_ = 150000.0;
   double dpPerTrayPa_ = 200.0;

   double etaVTop_ = 0.75;
   double etaVMid_ = 0.65;
   double etaVBot_ = 0.55;

   bool enableEtaL_ = false;
   double etaLTop_ = 1.0;
   double etaLMid_ = 1.0;
   double etaLBot_ = 1.0;

   int feedTray_ = 4;

   QString condenserSpec_ = "temperature";
   QString reboilerSpec_ = "boilup";

   double refluxRatio_ = 3.0;
   double boilupRatio_ = 2.0;
   double qcKW_ = 25000.0;
   double qrKW_ = 30000.0;
   double qcCalcKW_ = 0.0;
   double qrCalcKW_ = 0.0;
   double topTsetK_ = 370.0;
   double bottomTsetK_ = 670.0;

   double refluxFraction_ = 0.0;
   double boilupFraction_ = 0.0;
   double tColdK_ = 0.0;
   double tHotK_ = 0.0;

   bool solved_ = false;

   QString runResults_;

   QMutex logBufferMutex_;
   QMutex solverLogMutex_;
   QStringList logBuffer_;
   QTimer logFlushTimer_;

   QFile solverLogFile_;
   QTextStream solverLogStream_;
   QString solverLogFilePath_;

   void openSolverLogFile_();
   void closeSolverLogFile_();
   void writeSolverLogLine_(const QString& line);

   TrayModel trayModel_;
   DiagnosticsModel diagnosticsModel_;
   RunLogModel runLogModel_;
   MaterialBalanceModel mbModel_;
};