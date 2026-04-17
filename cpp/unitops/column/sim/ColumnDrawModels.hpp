#pragma once

#include <algorithm>
#include <unordered_map>
#include <vector>

#include "CounterCurrentColumnSimulator.hpp"
#include "StagedColumnCore.hpp"

namespace drawmodels {

struct DrawControllerConfig {
   double Kp = 0.60;
   double Ki = 0.10;
   double fracMin = 0.0;
   double fracMax = 0.50;
   double intMin = -0.50;
   double intMax = 0.50;
   bool disablePI = true;
};

struct DrawModelState {
   DrawControllerConfig config{};
   std::unordered_map<int, double> drawFrac_target;
   std::unordered_map<int, double> drawFrac_current;
   std::vector<double> sideDraw_dim;
   std::vector<double> sideDraw_dim_last;
   std::vector<double> sideDraw_intErr;
   bool disablePI = true;
};

struct DrawApplicationResult {
   bool applied = false;
   double targetFraction = 0.0;
   double commandFraction = 0.0;
   double draw_dim = 0.0;
   double L_after_dim = 0.0;
};

inline DrawControllerConfig defaultDrawControllerConfig() {
   return DrawControllerConfig{};
}

inline double normalizeDrawTargetFraction(const SimulationDrawSpec& ds, double feedRate_kgph) {
   double frac = 0.0;
   if (ds.basis == "stageLiqPct" || ds.basis == "feedPct") {
      frac = ds.value / 100.0;
   }
   else if (ds.basis == "kgph") {
      frac = ds.value / std::max(1e-12, feedRate_kgph);
   }
   else {
      frac = ds.value / 100.0;
   }
   return frac;
}

inline DrawModelState makeInitialDrawModelState(
   const std::vector<SimulationDrawSpec>& drawSpecs,
   int trayCount,
   double feedRate_kgph,
   DrawControllerConfig config = defaultDrawControllerConfig())
{
   DrawModelState state;
   state.config = config;
   state.disablePI = config.disablePI;
   state.sideDraw_dim.assign(trayCount, 0.0);
   state.sideDraw_dim_last.assign(trayCount, 0.0);
   state.sideDraw_intErr.assign(trayCount, 0.0);
   state.drawFrac_target.reserve(drawSpecs.size());

   for (const auto& ds : drawSpecs) {
      if (ds.trayIndex0 <= 0 || ds.trayIndex0 >= trayCount) continue;
      if (!ds.phase.empty() && ds.phase != "L") continue;
      const double frac = stagedcore::clampd(
         normalizeDrawTargetFraction(ds, feedRate_kgph),
         config.fracMin,
         config.fracMax);
      state.drawFrac_target[ds.trayIndex0] = frac;
   }

   state.drawFrac_current = state.drawFrac_target;
   return state;
}

inline void beginIteration(DrawModelState& state) {
   std::fill(state.sideDraw_dim.begin(), state.sideDraw_dim.end(), 0.0);
}

inline bool hasDrawOnTray(const DrawModelState& state, int trayIndex0) {
   auto it = state.drawFrac_target.find(trayIndex0);
   return it != state.drawFrac_target.end() && it->second > 0.0;
}

inline double targetFractionForTray(const DrawModelState& state, int trayIndex0) {
   auto it = state.drawFrac_target.find(trayIndex0);
   return (it != state.drawFrac_target.end()) ? it->second : 0.0;
}

inline double commandFractionForTray(const DrawModelState& state, int trayIndex0) {
   auto it = state.drawFrac_current.find(trayIndex0);
   if (it != state.drawFrac_current.end()) return it->second;
   return targetFractionForTray(state, trayIndex0);
}

inline double targetKgphForTray(const DrawModelState& state, int trayIndex0, double feedRate_kgph) {
   return targetFractionForTray(state, trayIndex0) * feedRate_kgph;
}

inline void updateDrawControllers(DrawModelState& state, int iter, int trayCount) {
   if (state.disablePI || state.drawFrac_current.empty() || iter <= 0) return;

   for (auto& kv : state.drawFrac_current) {
      const int tray = kv.first;
      if (tray <= 0 || tray >= trayCount) continue;

      const double target = targetFractionForTray(state, tray);
      const double actual = (tray < static_cast<int>(state.sideDraw_dim_last.size()))
         ? state.sideDraw_dim_last[tray]
         : 0.0;
      const double err = target - actual;

      state.sideDraw_intErr[tray] = stagedcore::clampd(
         state.sideDraw_intErr[tray] + err,
         state.config.intMin,
         state.config.intMax);

      const double proposed = kv.second + state.config.Kp * err + state.config.Ki * state.sideDraw_intErr[tray];
      kv.second = stagedcore::clampd(proposed, state.config.fracMin, state.config.fracMax);
   }
}

inline DrawApplicationResult applyLiquidSideDraw(
   DrawModelState& state,
   int trayIndex0,
   double L_out_before_dim,
   double /*V_out_before_dim*/)
{
   DrawApplicationResult result;
   result.targetFraction = targetFractionForTray(state, trayIndex0);
   result.commandFraction = commandFractionForTray(state, trayIndex0);
   result.L_after_dim = L_out_before_dim;

   if (trayIndex0 == 0 || result.commandFraction <= 0.0) {
      return result;
   }

   result.commandFraction = stagedcore::clampd(
      result.commandFraction,
      state.config.fracMin,
      state.config.fracMax);

   const double draw_dim = std::min(
      result.commandFraction * L_out_before_dim,
      std::max(0.0, L_out_before_dim - 1e-12));

   result.applied = draw_dim > 0.0;
   result.draw_dim = draw_dim;
   result.L_after_dim = std::max(0.0, L_out_before_dim - draw_dim);

   if (trayIndex0 >= 0 && trayIndex0 < static_cast<int>(state.sideDraw_dim.size())) {
      state.sideDraw_dim[trayIndex0] = draw_dim;
   }

   return result;
}

inline void finalizeIteration(DrawModelState& state) {
   state.sideDraw_dim_last = state.sideDraw_dim;
}

inline std::vector<double> toProductBasisKgph(const DrawModelState& state, double mScale_products) {
   std::vector<double> out(state.sideDraw_dim.size(), 0.0);
   for (size_t i = 0; i < state.sideDraw_dim.size(); ++i) {
      out[i] = state.sideDraw_dim[i] * mScale_products;
   }
   return out;
}

} // namespace drawmodels
