#pragma once

#include <algorithm>
#include <string>
#include <vector>

#include "CounterCurrentColumnSimulator.hpp"
#include "ColumnBoundaryModels.hpp"
#include "ColumnDrawModels.hpp"
#include "StagedColumnCore.hpp"

namespace stagedunitsolver {

enum class UnitKind {
   MainColumn,
   AttachedSideStripper,
};

struct StageFeedSpec {
   int trayIndex0 = 0;
   double flowKgph = 0.0;
   std::vector<double> z;
   double temperatureK = 298.15;
   double pressurePa = 101325.0;
   std::string phaseHint = "L";
   std::string label;
};

struct StageProductSpec {
   int trayIndex0 = 0;
   std::string label;
   std::string phase = "L";
   bool returnsToParent = false;
};

struct StagedUnitSolveSpec {
   UnitKind kind = UnitKind::MainColumn;
   std::string label;

   int trays = 0;
   int feedTrayIndex0 = 0;
   double feedRateKgph = 0.0;
   double topPressurePa = 101325.0;
   double dpPerStagePa = 0.0;

   double TminK = 250.0;
   double TmaxK = 900.0;

   bool openTop = false;
   bool openBottom = false;
   double refluxRatioEff = 0.0;
   double reboilRatioEff = 0.0;

   bool disableSinglePhaseShortCircuit = false;
   bool disableSideDrawPIForParity = true;
   bool disableTempShapingForParity = true;
   bool useSolvedStateForTrayReporting = true;

   std::vector<StageFeedSpec> feeds;
   std::vector<StageProductSpec> products;
};

struct StagedUnitBoundarySeed {
   double L_ref = 0.5;
   std::vector<double> x_ref;
   double V_boil = 0.3;
   std::vector<double> y_boil;
};

inline StagedUnitSolveSpec makeMainColumnSolveSpec(
   const SimulationOptions& opt,
   const boundarymodels::TopBoundarySpec& topBoundary,
   const boundarymodels::BottomBoundarySpec& bottomBoundary,
   bool disableSinglePhaseShortCircuit,
   bool useSolvedStateForTrayReporting,
   bool disableTempShapingForParity,
   bool disableSideDrawPIForParity)
{
   StagedUnitSolveSpec spec;
   spec.kind = UnitKind::MainColumn;
   spec.label = opt.crudeName;
   spec.trays = opt.trays;
   spec.feedTrayIndex0 = opt.feedTray;
   spec.feedRateKgph = opt.feedRate_kgph;
   spec.topPressurePa = opt.Ptop;
   spec.dpPerStagePa = opt.Pdrop;
   spec.TminK = 250.0;
   spec.TmaxK = 900.0;
   spec.openTop = (topBoundary.mode == boundarymodels::TopBoundaryMode::OpenTop);
   spec.openBottom = (bottomBoundary.mode == boundarymodels::BottomBoundaryMode::OpenBottom);
   spec.refluxRatioEff = spec.openTop ? 0.0 : topBoundary.refluxRatio;
   spec.reboilRatioEff = spec.openBottom ? 0.0 : bottomBoundary.reboilRatio;
   spec.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
   spec.disableSideDrawPIForParity = disableSideDrawPIForParity;
   spec.disableTempShapingForParity = disableTempShapingForParity;
   spec.useSolvedStateForTrayReporting = useSolvedStateForTrayReporting;

   StageFeedSpec feed;
   feed.trayIndex0 = opt.feedTray;
   feed.flowKgph = opt.feedRate_kgph;
   feed.z = opt.feedZ;
   feed.temperatureK = opt.Tfeed;
   feed.pressurePa = opt.Ptop + (std::max(0, opt.trays - 1 - opt.feedTray) * opt.Pdrop);
   feed.phaseHint = "mixed";
   feed.label = "main_feed";
   spec.feeds.push_back(feed);

   StageProductSpec distillate;
   distillate.trayIndex0 = std::max(0, opt.trays - 1);
   distillate.label = "distillate";
   distillate.phase = spec.openTop ? "V" : "L";
   spec.products.push_back(distillate);

   StageProductSpec bottoms;
   bottoms.trayIndex0 = 0;
   bottoms.label = "bottoms";
   bottoms.phase = "L";
   spec.products.push_back(bottoms);
   return spec;
}

inline StagedUnitSolveSpec makeAttachedSideStripperUnitSpec(
   const std::string& label,
   int trays,
   int feedTrayIndex0,
   double feedRateKgph,
   const std::vector<double>& z,
   double feedTemperatureK,
   double topPressurePa,
   double dpPerStagePa,
   bool openBottom,
   bool disableSinglePhaseShortCircuit,
   bool useSolvedStateForTrayReporting,
   bool disableTempShapingForParity = true,
   bool disableSideDrawPIForParity = true)
{
   StagedUnitSolveSpec spec;
   spec.kind = UnitKind::AttachedSideStripper;
   spec.label = label;
   spec.trays = std::max(2, trays);
   spec.feedTrayIndex0 = std::clamp(feedTrayIndex0, 0, spec.trays - 1);
   spec.feedRateKgph = std::max(0.0, feedRateKgph);
   spec.topPressurePa = topPressurePa;
   spec.dpPerStagePa = dpPerStagePa;
   spec.openTop = true;
   spec.openBottom = openBottom;
   spec.refluxRatioEff = 0.0;
   spec.reboilRatioEff = 0.0;
   spec.disableSinglePhaseShortCircuit = disableSinglePhaseShortCircuit;
   spec.disableSideDrawPIForParity = disableSideDrawPIForParity;
   spec.disableTempShapingForParity = disableTempShapingForParity;
   spec.useSolvedStateForTrayReporting = useSolvedStateForTrayReporting;

   StageFeedSpec feed;
   feed.trayIndex0 = spec.feedTrayIndex0;
   feed.flowKgph = std::max(0.0, feedRateKgph);
   feed.z = z;
   feed.temperatureK = feedTemperatureK;
   feed.pressurePa = topPressurePa + (std::max(0, spec.trays - 1 - spec.feedTrayIndex0) * dpPerStagePa);
   feed.phaseHint = "L";
   feed.label = "stripper_feed";
   spec.feeds.push_back(feed);

   StageProductSpec vaporReturn;
   vaporReturn.trayIndex0 = std::max(0, spec.trays - 1);
   vaporReturn.label = "vapor_return";
   vaporReturn.phase = "V";
   vaporReturn.returnsToParent = true;
   spec.products.push_back(vaporReturn);

   StageProductSpec bottoms;
   bottoms.trayIndex0 = 0;
   bottoms.label = "stripper_bottoms";
   bottoms.phase = "L";
   spec.products.push_back(bottoms);
   return spec;
}

inline StagedUnitBoundarySeed makeInitialBoundarySeed(const SimulationOptions& opt)
{
   StagedUnitBoundarySeed seed;
   seed.x_ref = opt.feedZ;
   seed.y_boil = opt.feedZ;
   return seed;
}

inline StagedUnitBoundarySeed makeHydrocarbonOnlyBoundarySeed(const std::vector<double>& z)
{
   StagedUnitBoundarySeed seed;
   seed.x_ref = z;
   seed.y_boil = z;
   return seed;
}

inline stagedcore::BoundaryRecycleState makeInitialRecycleState(const StagedUnitBoundarySeed& seed)
{
   stagedcore::BoundaryRecycleState state;
   state.L_ref = seed.L_ref;
   state.x_ref = seed.x_ref;
   state.V_boil = seed.V_boil;
   state.y_boil = seed.y_boil;
   return state;
}

inline void syncBoundarySeedFromRecycle(const stagedcore::BoundaryRecycleState& recycle,
                                        StagedUnitBoundarySeed& seed)
{
   seed.L_ref = recycle.L_ref;
   seed.x_ref = recycle.x_ref;
   seed.V_boil = recycle.V_boil;
   seed.y_boil = recycle.y_boil;
}

inline bool hasHydrocarbonFeedOnTray(const StagedUnitSolveSpec& spec, int trayIndex0)
{
   for (const auto& feed : spec.feeds) {
      if (feed.trayIndex0 == trayIndex0 && feed.flowKgph > 0.0)
         return true;
   }
   return false;
}

} // namespace stagedunitsolver
