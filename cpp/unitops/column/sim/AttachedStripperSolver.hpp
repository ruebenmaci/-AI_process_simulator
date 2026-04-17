#pragma once

#include <algorithm>
#include <utility>

#include "AttachedStripperModels.hpp"
#include "ColumnBoundaryModels.hpp"

namespace strippermodels {

inline stagedunitsolver::StagedUnitSolveSpec makeAttachedStripperUnitSpec(
   const AttachedStripperSolveSpec& spec)
{
   return stagedunitsolver::makeAttachedSideStripperUnitSpec(
      spec.label,
      spec.trays,
      spec.feedTrayIndex0,
      spec.feed.flowKgph,
      spec.feed.z,
      spec.feed.temperatureK,
      spec.topPressurePa,
      spec.dpPerStagePa,
      /*openBottom=*/(spec.heatMode == AttachedStripperHeatMode::None),
      /*disableSinglePhaseShortCircuit=*/false,
      /*useSolvedStateForTrayReporting=*/!spec.reportTrayFlashDiagnostics,
      /*disableTempShapingForParity=*/true,
      /*disableSideDrawPIForParity=*/true);
}

inline SimulationOptions makeAttachedStripperSimulationOptions(
   const AttachedStripperSolveSpec& spec)
{
   SimulationOptions opt;
   opt.thermoConfig = spec.thermoConfig;
   opt.crudeName = spec.crudeName.empty() ? spec.label : spec.crudeName;
   opt.components = spec.components;
   opt.feedZ = spec.feed.z;
   opt.feedTray = std::clamp(spec.feedTrayIndex0, 0, std::max(1, spec.trays) - 1);
   opt.Tfeed = spec.feed.temperatureK;

   const double tTopGuess = std::clamp(spec.feed.temperatureK - 15.0, 250.0, 900.0);
   const double tBotGuess = std::clamp(spec.feed.temperatureK + 15.0, 250.0, 900.0);
   opt.Ttop = tTopGuess;
   opt.Tbottom = tBotGuess;

   opt.eosMode = spec.eosMode;
   opt.eosManual = spec.eosManual;
   opt.kij = spec.kij;
   opt.Ptop = spec.topPressurePa;
   opt.Pdrop = spec.dpPerStagePa;
   opt.trays = std::max(2, spec.trays);

   opt.refluxRatio = 0.0;
   opt.reboilRatio = 0.0;
   opt.Qr_kW_in = (spec.heatMode == AttachedStripperHeatMode::ReboilerDuty)
      ? std::max(0.0, spec.reboilerDutyKW)
      : 0.0;
   opt.Qc_kW_in = 0.0;

   opt.condenserSpec = "none";
   opt.reboilerSpec = (spec.heatMode == AttachedStripperHeatMode::ReboilerDuty)
      ? "duty"
      : "none";
   opt.condenserType = "none";
   opt.reboilerType = "partial";

   opt.feedRate_kgph = std::max(0.0, spec.feed.flowKgph);
   opt.maxIter = spec.maxIter;
   opt.relax = spec.relax;
   opt.relaxT = spec.relaxT;
   opt.Kr_Q = spec.Kr_Q;
   opt.Ki_Q = spec.Ki_Q;
   opt.murphree = spec.murphree;
   opt.onProgress = spec.onProgress;
   opt.onLog = spec.onLog;
   opt.logLevel = spec.logLevel;
   opt.debug_iterPrint = spec.debug_iterPrint;
   opt.debug_trayPrint = spec.debug_trayPrint;
   opt.forceTwoPhase = spec.forceTwoPhase;
   opt.reportTrayFlashDiagnostics = spec.reportTrayFlashDiagnostics;
   return opt;
}

inline AttachedStripperSolveResult simulateAttachedStripper(
   const AttachedStripperSolveSpec& spec)
{
   AttachedStripperSolveResult out;
   out.heatMode = spec.heatMode;
   out.stagedUnitSpec = makeAttachedStripperUnitSpec(spec);

   SimulationOptions opt = makeAttachedStripperSimulationOptions(spec);
   out.columnLikeResult = simulateColumn(opt);
   out.status = out.columnLikeResult.status;

   out.feedKgph = spec.feed.flowKgph;
   out.feedTemperatureK = spec.feed.temperatureK;
   out.feedPressurePa = spec.feed.pressurePa;
   out.vaporReturnKgph = out.columnLikeResult.energy.massBalance.overhead_kgph;
   out.bottomsProductKgph = out.columnLikeResult.energy.massBalance.bottoms_kgph;
   out.solveConverged = (out.columnLikeResult.status != "FAILED" && out.columnLikeResult.status != "failed");

   if (!out.columnLikeResult.trays.empty()) {
      const auto& bot = out.columnLikeResult.trays.front();
      const auto& top = out.columnLikeResult.trays.back();
      out.bottomsX = bot.x;
      out.vaporReturnY = top.y;
      out.vaporReturnTemperatureK = top.T;
      out.vaporReturnPressurePa = top.P;
      out.bottomsTemperatureK = bot.T;
      out.bottomsPressurePa = bot.P;
   }

   if (spec.heatMode == AttachedStripperHeatMode::SteamRate && spec.steamRateKgph > 0.0) {
      Diagnostic d;
      d.level = "info";
      d.code = "attached_stripper_steam_scaffold";
      d.message = "Attached stripper '" + spec.label + "': steam-rate mode is scaffolded in Phase 9. The internal stripper solve currently runs hydrocarbon-only without a separate steam component feed, so the requested steam rate is recorded but not yet injected into the equilibrium solve.";
      out.diagnostics.push_back(d);
      out.approximatedSteamMode = true;
   }

   if (spec.feed.returnTrayIndex0 >= 0) {
      Diagnostic d;
      d.level = "info";
      d.code = "attached_stripper_return_path_ready";
      d.message = "Attached stripper '" + spec.label + "': vapor return tray routing is carried in the typed stripper spec/result path and is available for coupled main-column return routing.";
      out.diagnostics.push_back(d);
   }

   return out;
}

} // namespace strippermodels
