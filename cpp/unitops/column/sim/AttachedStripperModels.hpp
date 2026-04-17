#pragma once

#include <string>
#include <sstream>
#include <cmath>
#include <vector>
#include <limits>
#include <algorithm>

#include "CounterCurrentColumnSimulator.hpp"
#include "StagedUnitSolver.hpp"

namespace strippermodels {

enum class AttachedStripperHeatMode {
   None,
   SteamRate,
   ReboilerDuty,
};

struct AttachedStripperFeedSpec {
   int sourceTrayIndex0 = -1;
   int returnTrayIndex0 = -1;
   double flowKgph = 0.0;
   std::vector<double> z;
   double temperatureK = 298.15;
   double pressurePa = 101325.0;
   std::string label = "attached_stripper_feed";
};

struct AttachedStripperSolveSpec {
   std::string stripperId;
   std::string label = "Attached Side Stripper";

   int trays = 4;
   int feedTrayIndex0 = 2;
   double topPressurePa = 101325.0;
   double dpPerStagePa = 0.0;

   thermo::ThermoConfig thermoConfig;
   std::string crudeName;
   const std::vector<Component>* components = nullptr;
   const std::vector<std::vector<double>>* kij = nullptr;

   AttachedStripperFeedSpec feed;

   AttachedStripperHeatMode heatMode = AttachedStripperHeatMode::None;
   double steamRateKgph = 0.0;
   double reboilerDutyKW = 0.0;

   std::string eosMode = "auto";
   std::string eosManual;
   MurphreeEff murphree;

   int maxIter = 60;
   double relax = 0.45;
   double relaxT = 0.3;
   double Kr_Q = 600.0;
   double Ki_Q = 0.02;

   bool forceTwoPhase = false;
   bool reportTrayFlashDiagnostics = false;

   std::function<void(const ProgressEvent&)> onProgress;
   std::function<void(const std::string&)> onLog;
   LogLevel logLevel = LogLevel::Summary;
   int debug_iterPrint = 5;
   int debug_trayPrint = 1;
};

struct AttachedStripperSolveResult {
   SimulationResult columnLikeResult;
   stagedunitsolver::StagedUnitSolveSpec stagedUnitSpec;
   AttachedStripperHeatMode heatMode = AttachedStripperHeatMode::ReboilerDuty;

   double feedKgph = 0.0;
   double feedTemperatureK = std::numeric_limits<double>::quiet_NaN();
   double feedPressurePa = std::numeric_limits<double>::quiet_NaN();
   double vaporReturnKgph = 0.0;
   double vaporReturnTemperatureK = std::numeric_limits<double>::quiet_NaN();
   double vaporReturnPressurePa = std::numeric_limits<double>::quiet_NaN();
   double bottomsProductKgph = 0.0;
   double bottomsTemperatureK = std::numeric_limits<double>::quiet_NaN();
   double bottomsPressurePa = std::numeric_limits<double>::quiet_NaN();
   std::vector<double> vaporReturnY;
   std::vector<double> bottomsX;

   bool approximatedSteamMode = false;
   bool solveConverged = false;
   std::vector<Diagnostic> diagnostics;
   std::string status = "OK";
};


inline AttachedStripperHeatMode heatModeFromString(std::string mode)
{
   auto lower = [](std::string s) {
      std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
      return s;
   };
   mode = lower(mode);
   if (mode == "steam" || mode == "steamrate" || mode == "steam_rate")
      return AttachedStripperHeatMode::SteamRate;
   if (mode == "reboiler_duty" || mode == "reboilerduty" || mode == "duty")
      return AttachedStripperHeatMode::ReboilerDuty;
   return AttachedStripperHeatMode::None;
}

inline AttachedStripperSolveSpec makeSolveSpecFromMainColumn(
   const SimulationOptions& opt,
   const SimulationResult& mainResult,
   const SimulationAttachedStripperSpec& cfg)
{
   AttachedStripperSolveSpec spec;
   spec.stripperId = cfg.stripperId;
   spec.label = cfg.label.empty() ? "Attached Side Stripper" : cfg.label;
   spec.trays = std::max(2, cfg.trays);
   spec.feedTrayIndex0 = std::clamp(cfg.feedTrayIndex0, 0, spec.trays - 1);
   spec.topPressurePa = cfg.topPressurePa;
   spec.dpPerStagePa = cfg.dpPerStagePa;
   spec.thermoConfig = opt.thermoConfig;
   spec.crudeName = opt.crudeName;
   spec.components = opt.components;
   spec.kij = opt.kij;
   spec.eosMode = opt.eosMode;
   spec.eosManual = opt.eosManual;
   spec.murphree = opt.murphree;
   spec.maxIter = std::max(20, opt.maxIter);
   spec.relax = opt.relax;
   spec.relaxT = opt.relaxT;
   spec.Kr_Q = opt.Kr_Q;
   spec.Ki_Q = opt.Ki_Q;
   spec.forceTwoPhase = opt.forceTwoPhase;
   spec.reportTrayFlashDiagnostics = opt.reportTrayFlashDiagnostics;
   spec.onProgress = opt.onProgress;
   spec.onLog = opt.onLog;
   spec.logLevel = opt.logLevel;
   spec.debug_iterPrint = opt.debug_iterPrint;
   spec.debug_trayPrint = opt.debug_trayPrint;

   spec.feed.sourceTrayIndex0 = cfg.sourceTrayIndex0;
   spec.feed.returnTrayIndex0 = cfg.returnTrayIndex0;
   spec.feed.label = spec.label + " feed";

   if (cfg.sourceTrayIndex0 >= 0 && cfg.sourceTrayIndex0 < static_cast<int>(mainResult.trays.size())) {
      const auto& tr = mainResult.trays[cfg.sourceTrayIndex0];
      const double feedKgph = (tr.sideDraw_kgph > 0.0) ? tr.sideDraw_kgph : tr.sideDraw_target_kgph;
      spec.feed.flowKgph = std::max(0.0, feedKgph);
      spec.feed.z = !tr.x.empty() ? tr.x : tr.y;
      spec.feed.temperatureK = std::isfinite(tr.T_internal) ? tr.T_internal : tr.T;
      spec.feed.pressurePa = tr.P;
   }

   spec.heatMode = heatModeFromString(cfg.heatMode);
   spec.steamRateKgph = std::max(0.0, cfg.steamRateKgph);
   spec.reboilerDutyKW = std::max(0.0, cfg.reboilerDutyKW);
   return spec;
}

inline AttachedStripperSolveSpec makeSolveSpecFromFeed(
   const SimulationOptions& opt,
   const SimulationAttachedStripperSpec& cfg,
   double feedFlowKgph,
   const std::vector<double>& feedZ,
   double feedTemperatureK,
   double feedPressurePa)
{
   AttachedStripperSolveSpec spec;
   spec.stripperId = cfg.stripperId;
   spec.label = cfg.label.empty() ? "Attached Side Stripper" : cfg.label;
   spec.trays = std::max(2, cfg.trays);
   spec.feedTrayIndex0 = std::clamp(cfg.feedTrayIndex0, 0, spec.trays - 1);
   spec.topPressurePa = cfg.topPressurePa;
   spec.dpPerStagePa = cfg.dpPerStagePa;
   spec.thermoConfig = opt.thermoConfig;
   spec.crudeName = opt.crudeName;
   spec.components = opt.components;
   spec.kij = opt.kij;
   spec.eosMode = opt.eosMode;
   spec.eosManual = opt.eosManual;
   spec.murphree = opt.murphree;
   spec.maxIter = std::max(20, opt.maxIter);
   spec.relax = opt.relax;
   spec.relaxT = opt.relaxT;
   spec.Kr_Q = opt.Kr_Q;
   spec.Ki_Q = opt.Ki_Q;
   spec.forceTwoPhase = opt.forceTwoPhase;
   spec.reportTrayFlashDiagnostics = opt.reportTrayFlashDiagnostics;
   spec.onProgress = opt.onProgress;
   spec.onLog = opt.onLog;
   spec.logLevel = opt.logLevel;
   spec.debug_iterPrint = opt.debug_iterPrint;
   spec.debug_trayPrint = opt.debug_trayPrint;

   spec.feed.sourceTrayIndex0 = cfg.sourceTrayIndex0;
   spec.feed.returnTrayIndex0 = cfg.returnTrayIndex0;
   spec.feed.label = spec.label + " feed";
   spec.feed.flowKgph = std::max(0.0, feedFlowKgph);
   spec.feed.z = feedZ;
   spec.feed.temperatureK = feedTemperatureK;
   spec.feed.pressurePa = feedPressurePa;

   spec.heatMode = heatModeFromString(cfg.heatMode);
   spec.steamRateKgph = std::max(0.0, cfg.steamRateKgph);
   spec.reboilerDutyKW = std::max(0.0, cfg.reboilerDutyKW);
   return spec;
}

inline SimulationAttachedStripperSummary makeSummary(
   const SimulationAttachedStripperSpec& cfg,
   const AttachedStripperSolveResult& result)
{
   auto heatModeText = [](AttachedStripperHeatMode mode) -> std::string {
      switch (mode) {
      case AttachedStripperHeatMode::SteamRate: return "steam";
      case AttachedStripperHeatMode::ReboilerDuty: return "reboiler_duty";
      default: return "none";
      }
   };

   SimulationAttachedStripperSummary s;
   s.stripperId = cfg.stripperId;
   s.label = cfg.label;
   s.sourceTray = cfg.sourceTrayIndex0 + 1;
   s.returnTray = cfg.returnTrayIndex0 + 1;
   s.trays = result.stagedUnitSpec.trays;
   s.feedTray = result.stagedUnitSpec.feedTrayIndex0 + 1;
   s.heatMode = heatModeText(result.heatMode);
   s.feedKgph = result.feedKgph > 0.0 ? result.feedKgph : (result.stagedUnitSpec.feeds.empty() ? 0.0 : result.stagedUnitSpec.feeds.front().flowKgph);
   s.vaporReturnKgph = result.vaporReturnKgph;
   s.bottomsProductKgph = result.bottomsProductKgph;
   s.feedTemperatureK = result.feedTemperatureK;
   s.feedPressurePa = result.feedPressurePa;
   s.vaporReturnTemperatureK = result.vaporReturnTemperatureK;
   s.vaporReturnPressurePa = result.vaporReturnPressurePa;
   s.bottomsTemperatureK = result.bottomsTemperatureK;
   s.bottomsPressurePa = result.bottomsPressurePa;
   s.approximatedSteamMode = result.approximatedSteamMode;
   s.status = result.status;
   s.solveConverged = result.solveConverged;
   s.diagnostics = result.diagnostics;
   if (!result.columnLikeResult.trays.empty()) {
      const auto& bot = result.columnLikeResult.trays.front();
      const auto& top = result.columnLikeResult.trays.back();
      s.bottomTemperatureK = bot.T;
      s.topTemperatureK = top.T;
      s.topPressurePa = top.P;
      if (!std::isfinite(s.vaporReturnTemperatureK)) s.vaporReturnTemperatureK = top.T;
      if (!std::isfinite(s.vaporReturnPressurePa)) s.vaporReturnPressurePa = top.P;
      if (!std::isfinite(s.bottomsTemperatureK)) s.bottomsTemperatureK = bot.T;
      if (!std::isfinite(s.bottomsPressurePa)) s.bottomsPressurePa = bot.P;
   }
   std::ostringstream oss;
   oss.setf(std::ios::fixed);
   oss.precision(2);
   oss << s.label
       << " status=" << s.status
       << " srcTray=" << s.sourceTray
       << " retTray=" << s.returnTray
       << " trays=" << s.trays
       << " feedTray=" << s.feedTray
       << " heatMode=" << s.heatMode
       << " feedKgph=" << s.feedKgph
       << " vaporReturnKgph=" << s.vaporReturnKgph
       << " bottomsKgph=" << s.bottomsProductKgph
       << " solveConverged=" << (s.solveConverged ? "true" : "false");
   if (std::isfinite(s.topTemperatureK)) oss << " topT_K=" << s.topTemperatureK;
   if (std::isfinite(s.bottomTemperatureK)) oss << " botT_K=" << s.bottomTemperatureK;
   if (std::isfinite(s.topPressurePa)) oss << " topP_Pa=" << s.topPressurePa;
   if (s.approximatedSteamMode) oss << " steamMode=approximated";
   s.summaryText = oss.str();
   return s;
}

} // namespace strippermodels
