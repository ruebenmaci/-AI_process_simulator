#pragma once

#include <algorithm>
#include <cmath>
#include <functional>
#include <iomanip>
#include <limits>
#include <numeric>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "CounterCurrentColumnSimulator.hpp"
#include "ColumnDrawModels.hpp"
#include "ColumnBoundaryModels.hpp"
#include "StagedColumnCore.hpp"

#include "../thermo/PH_PS_PT_TS_Flash.hpp"
#include "../thermo/Enthalpy.hpp"

namespace reportingmodels {

inline double mixMW(const std::vector<Component>& comps, const std::vector<double>& z) {
   double mw = 0.0;
   const size_t n = std::min(comps.size(), z.size());
   for (size_t i = 0; i < n; ++i) mw += z[i] * comps[i].MW;
   return mw;
}

inline double mixRhoL(const std::vector<Component>& comps, const std::vector<double>& z) {
   double sg = 0.0;
   double sum = 0.0;
   const size_t n = std::min(comps.size(), z.size());
   for (size_t i = 0; i < n; ++i) {
      const double wi = z[i];
      if (wi <= 0.0) continue;
      if (!std::isfinite(comps[i].SG) || comps[i].SG <= 0.0) continue;
      sg += wi * comps[i].SG;
      sum += wi;
   }
   if (sum <= 0.0) return std::numeric_limits<double>::quiet_NaN();
   sg /= sum;
   return sg * 1000.0;
}

struct MainColumnReportingContext {
   const SimulationOptions* opt = nullptr;
   const drawmodels::DrawModelState* drawState = nullptr;
   const std::function<void(const std::string&)>* logFn = nullptr;

   bool noCondenser = false;
   bool noReboiler = false;
   bool disableSinglePhaseShortCircuit = false;
   bool useSolvedStateForTrayReporting = false;

   double refluxRatio_eff = 0.0;
   double Qc_kW = 0.0;
   double Qr_kW = 0.0;
   double Tc = 0.0;
   double Treb_last = 0.0;
   double Tc_set_K = 0.0;
   double Qc_set_kW = 0.0;
   double Treb_set_K = 0.0;
   double B_dim_last = 0.0;
   double Vfrac_reb_last = 0.0;
   double Vf = 0.0;
   double TfeedSolved = 0.0;
   double Hfeed = 0.0;

   bool rb_hitDutyMax = false;
   bool rb_hitDutyMin = false;
   bool rb_vfracClamped = false;
   double rb_vfracRaw = std::numeric_limits<double>::quiet_NaN();
   double rb_vfracUsed = std::numeric_limits<double>::quiet_NaN();
   bool c_tcAtMin = false;
   bool c_tcAtMax = false;

   int N = 0;
   int f = 0;
   int trayPrint = 0;

   double T_MIN = 250.0;
   double T_MAX = 900.0;

   const std::vector<double>* xf = nullptr;
   const std::vector<double>* yf = nullptr;
   const std::vector<double>* xB_last = nullptr;
   const std::vector<double>* x_ref = nullptr;
   const std::vector<double>* y_boil = nullptr;
   const std::vector<double>* T = nullptr;
   const std::vector<double>* P = nullptr;
   const std::vector<double>* V_up = nullptr;
   const std::vector<std::vector<double>>* Y_up = nullptr;
   const std::vector<double>* L_dn = nullptr;
   const std::vector<std::vector<double>>* X_dn = nullptr;

   const stagedcore::ConvergenceSnapshot* convergence = nullptr;
   const std::unordered_map<int, std::string>* fallbackDrawMap = nullptr;
};

struct ProductScalingData {
   double V_top_final = 0.0;
   double D_dim = 0.0;
   double B_dim = 0.0;
   double totalSide_dim = 0.0;
   double totalProducts_dim = 0.0;
   double mScale_products = 0.0;
   double mScale_internal = 0.0;
   double D_kgph = 0.0;
   double B_kgph = 0.0;
   double L_ref_kgph = 0.0;
   double V_boil_kgph = 0.0;
   std::vector<double> sideDraws_kgph;
};

inline ProductScalingData computeScaling(const MainColumnReportingContext& ctx, double L_ref, double V_boil) {
   const auto& opt = *ctx.opt;
   const auto& drawState = *ctx.drawState;
   const auto& V_up = *ctx.V_up;

   ProductScalingData s;
   s.V_top_final = V_up[ctx.N - 2];
   s.D_dim = ctx.noCondenser ? s.V_top_final : (s.V_top_final / std::max(1e-6, 1.0 + ctx.refluxRatio_eff));
   s.B_dim = std::max(0.0, ctx.B_dim_last);
   s.totalSide_dim = std::accumulate(drawState.sideDraw_dim.begin(), drawState.sideDraw_dim.end(), 0.0);
   s.totalProducts_dim = s.D_dim + s.totalSide_dim + s.B_dim;
   s.mScale_products = (s.totalProducts_dim > 1e-12) ? (opt.feedRate_kgph / s.totalProducts_dim) : 0.0;
   s.mScale_internal = opt.feedRate_kgph;
   s.D_kgph = s.D_dim * s.mScale_products;
   s.B_kgph = s.B_dim * s.mScale_products;
   s.L_ref_kgph = L_ref * s.mScale_internal;
   s.V_boil_kgph = V_boil * s.mScale_internal;
   s.sideDraws_kgph = drawmodels::toProductBasisKgph(drawState, s.mScale_products);
   return s;
}

inline void emitScaleLogs(const MainColumnReportingContext& ctx, const ProductScalingData& s, double L_ref, double V_boil) {
   if (!ctx.logFn || !(*ctx.logFn)) return;
   const auto& opt = *ctx.opt;
   const auto& drawState = *ctx.drawState;
   auto& logFn = *ctx.logFn;

   {
      std::ostringstream oss;
      oss.setf(std::ios::fixed); oss.precision(6);
      oss << "[BASIS_CHECK] L_ref=" << L_ref
         << " V_boil=" << V_boil
         << " V_top_final=" << s.V_top_final
         << " B_dim_last=" << ctx.B_dim_last
         << " totalSide_dim=" << s.totalSide_dim;
      logFn(oss.str());
   }

   {
      std::ostringstream oss;
      oss.setf(std::ios::fixed); oss.precision(6);
      oss << "[SCALE_PRODUCTS]"
         << " D_dim=" << s.D_dim
         << " B_dim_last=" << ctx.B_dim_last
         << " totalSide_dim=" << s.totalSide_dim
         << " totalProducts_dim=" << s.totalProducts_dim
         << " mScale_products=" << s.mScale_products
         << " feedRate_kgph=" << opt.feedRate_kgph;
      logFn(oss.str());

      for (const auto& kv : drawState.drawFrac_target) {
         const int tray = kv.first;
         if (tray <= 0 || tray >= ctx.N)
            continue;
         const double targetFrac = drawmodels::targetFractionForTray(drawState, tray);
         const double target_kgph = drawmodels::targetKgphForTray(drawState, tray, opt.feedRate_kgph);
         const double actual_dim = (tray < static_cast<int>(drawState.sideDraw_dim.size())) ? drawState.sideDraw_dim[tray] : 0.0;
         const double actual_kgph_internalBasis = actual_dim * opt.feedRate_kgph;
         const double actual_kgph_productBasis = actual_dim * s.mScale_products;
         const double cmdFrac = drawmodels::commandFractionForTray(drawState, tray);

         std::ostringstream oss2;
         oss2.setf(std::ios::fixed); oss2.precision(6);
         oss2 << "[DRAW_CHECK] tray=" << (tray + 1)
            << " targetFrac=" << targetFrac
            << " cmdFrac=" << cmdFrac
            << " target_kgph=" << target_kgph
            << " actual_dim=" << actual_dim
            << " actual_kgph_internalBasis=" << actual_kgph_internalBasis
            << " actual_kgph_productBasis=" << actual_kgph_productBasis;
         logFn(oss2.str());
      }
   }

   {
      const double totalSide_kgph = std::accumulate(s.sideDraws_kgph.begin(), s.sideDraws_kgph.end(), 0.0);
      const double totalProducts_kgph = s.D_kgph + s.B_kgph + totalSide_kgph;

      std::ostringstream oss;
      oss.setf(std::ios::fixed); oss.precision(6);
      oss << "[SCALE]"
         << " Vtop_dim=" << s.V_top_final
         << " D_dim=" << s.D_dim
         << " B_dim=" << s.B_dim
         << " side_dim=" << s.totalSide_dim
         << " totalProducts_dim=" << s.totalProducts_dim
         << " mScale_products=" << s.mScale_products
         << " mScale_internal=" << s.mScale_internal
         << " D_kgph=" << s.D_kgph
         << " B_kgph=" << s.B_kgph
         << " side_kgph=" << totalSide_kgph
         << " sumProducts_kgph=" << totalProducts_kgph
         << " feedRate_kgph=" << opt.feedRate_kgph;
      logFn(oss.str());
   }
}

inline std::vector<TrayResult> buildTrayResults(const MainColumnReportingContext& ctx, const ProductScalingData& s, double L_ref, double V_boil) {
   const auto& opt = *ctx.opt;
   const auto& drawState = *ctx.drawState;
   const auto& T = *ctx.T;
   const auto& P = *ctx.P;
   const auto& V_up = *ctx.V_up;
   const auto& Y_up = *ctx.Y_up;
   const auto& L_dn = *ctx.L_dn;
   const auto& X_dn = *ctx.X_dn;
   const auto& xf = *ctx.xf;
   const auto& yf = *ctx.yf;
   const auto& xB_last = *ctx.xB_last;
   const auto& x_ref = *ctx.x_ref;
   const auto& y_boil = *ctx.y_boil;

   std::vector<TrayResult> traysOut(ctx.N);
   for (int i = 0; i < ctx.N; ++i) {
      if (i == 0) {
         const double Vreb = stagedcore::clampd(ctx.Vfrac_reb_last, 0.0, 1.0);
         const double Freb_kgph = s.B_kgph / std::max(1e-12, 1.0 - Vreb);
         TrayResult tr;
         tr.i = 1;
         tr.T = stagedcore::clampd(ctx.Treb_last, ctx.T_MIN, ctx.T_MAX);
         tr.T_internal = tr.T;
         tr.P = P[i];
         tr.V = Vreb;
         tr.x = xB_last;
         tr.y = y_boil;
         tr.m_vap_up_kgph = V_boil * s.mScale_internal;
         tr.m_liq_dn_kgph = s.B_kgph;
         tr.reboilerFeed_kgph = Freb_kgph;
         tr.bottomsFromSplit_kgph = (1.0 - Vreb) * Freb_kgph;
         traysOut[i] = std::move(tr);
         continue;
      }
      if (i == ctx.N - 1) {
         TrayResult tr;
         tr.i = ctx.N;
         tr.P = P[i];
         if (ctx.noCondenser) {
            const int ib = i - 1;
            const double Vtop_dim = std::max(0.0, V_up[ib]);
            const std::vector<double>& ytop = (Y_up[ib].empty() ? opt.feedZ : Y_up[ib]);
            tr.T = stagedcore::clampd(T[i], ctx.T_MIN, ctx.T_MAX);
            tr.T_internal = tr.T;
            tr.V = 1.0;
            tr.x = ytop;
            tr.y = ytop;
            tr.m_vap_up_kgph = Vtop_dim * s.mScale_internal;
            tr.m_liq_dn_kgph = 0.0;
         } else {
            tr.T = ctx.Tc;
            tr.T_internal = ctx.Tc;
            tr.V = 0.0;
            tr.x = x_ref;
            tr.y = (Y_up[i - 1].empty() ? opt.feedZ : Y_up[i - 1]);
            tr.m_vap_up_kgph = 0.0;
            tr.m_liq_dn_kgph = L_ref * s.mScale_internal;
         }
         traysOut[i] = std::move(tr);
         continue;
      }

      const double L_in = (L_dn[i + 1] > 0 ? L_dn[i + 1] : L_ref);
      const std::vector<double>& x_in = (!X_dn[i + 1].empty() ? X_dn[i + 1] : x_ref);
      const double V_in = V_up[i - 1];
      const std::vector<double>& y_in = Y_up[i - 1];

      if (ctx.useSolvedStateForTrayReporting) {
         TrayResult tr;
         tr.i = i + 1;
         tr.T_internal = T[i];
         tr.T = stagedcore::clampd(T[i], ctx.T_MIN, ctx.T_MAX);
         tr.P = P[i];
         const double Vdim = std::max(0.0, V_up[i]);
         const double Ldim = std::max(0.0, L_dn[i]);
         tr.V = stagedcore::clampd(Vdim / std::max(1e-12, Vdim + Ldim), 0.0, 1.0);
         tr.x = (!X_dn[i].empty() ? X_dn[i] : x_in);
         tr.y = (!Y_up[i].empty() ? Y_up[i] : y_in);
         tr.m_vap_up_kgph = V_up[i] * s.mScale_internal;
         tr.m_liq_dn_kgph = L_dn[i] * s.mScale_internal;
         tr.sideDraw_kgph = s.sideDraws_kgph[i];
         tr.sideDraw_target_kgph = drawmodels::targetKgphForTray(drawState, i, opt.feedRate_kgph);
         tr.sideDraw_frac = drawmodels::targetFractionForTray(drawState, i);
         traysOut[i] = std::move(tr);
         continue;
      }

      const double addV = (i == ctx.f) ? ctx.Vf : 0.0;
      const double addL = (i == ctx.f) ? (1.0 - ctx.Vf) : 0.0;
      const double M_raw = V_in + L_in + addV + addL;
      const double M = std::max(1e-12, M_raw);
      std::vector<double> z(opt.feedZ.size(), 0.0);
      for (size_t k = 0; k < z.size(); ++k) {
         const double num = V_in * y_in[k] + L_in * x_in[k] + addV * yf[k] + addL * xf[k];
         z[k] = std::max(0.0, num / M);
      }
      stagedcore::normalize(z);

      const double Tlin = (i < ctx.N - 1) ? T[i + 1] : T[i];
      const double T_liq_in = (i == ctx.N - 1) ? ctx.Tc : Tlin;
      const double hV_in = hVap(y_in, stagedcore::clampd(T[i - 1], ctx.T_MIN, ctx.T_MAX), i, *opt.components, P[i]);
      const double hL_in = hLiq(x_in, T_liq_in, i, *opt.components, P[i]);
      const double hV_feed = hVap(yf, ctx.TfeedSolved, i, *opt.components, P[i]);
      const double hL_feed = hLiq(xf, ctx.TfeedSolved, i, *opt.components, P[i]);
      const double Hnum = V_in * hV_in + L_in * hL_in + addV * hV_feed + addL * hL_feed;
      double Hmix = (M_raw < 1e-6) ? ((V_in >= L_in && V_in > 1e-9) ? hV_in : ((L_in > 1e-9) ? hL_in : ctx.Hfeed)) : (Hnum / M);

      const double etaV = stagedcore::etaBySection(i, ctx.N, ctx.f, opt.murphree.etaV_top, opt.murphree.etaV_mid, opt.murphree.etaV_bot);
      FlashPHInput in;
      in.Htarget = Hmix;
      in.z = z;
      in.P = P[i];
      in.Tseed = T[i];
      in.components = opt.components;
      in.trayIndex = i;
      in.trays = ctx.N;
      in.crudeName = opt.crudeName;
      in.eosMode = opt.eosMode;
      in.eosManual = opt.eosManual;
      in.thermoConfig = opt.thermoConfig;
      in.log = *ctx.logFn;
      in.logLevel = opt.logLevel;
      const bool hasDrawOnThisTray = drawmodels::hasDrawOnTray(drawState, i);
      in.forceTwoPhase = (opt.forceTwoPhase || hasDrawOnThisTray);
      in.disableSinglePhaseShortCircuit = ctx.disableSinglePhaseShortCircuit;
      in.murphreeEtaV = etaV;

      FlashPHResult ans = flashPH(in);
      if (ctx.logFn && *ctx.logFn && (!std::isfinite(ans.T) || !std::isfinite(ans.V) || ans.V < -1e-6 || ans.V > 1 + 1e-6 || !std::isfinite(ans.Htarget) || !std::isfinite(ans.Hcalc) || std::fabs(ans.dH) > 1e-2)) {
         std::ostringstream oss;
         oss.setf(std::ios::fixed); oss.precision(6);
         oss << "[FLASH_WARN] tray=" << i + 1 << " T=" << ans.T << " V=" << ans.V << " Htarget=" << in.Htarget << " P=" << in.P << " M=" << M << " V_in=" << V_in << " L_in=" << L_in << " addV=" << addV << " addL=" << addL;
         (*ctx.logFn)(oss.str());
      }

      const double Vfrac = stagedcore::clampd(ans.V, 0.0, 1.0);
      TrayResult tr;
      tr.i = i + 1;
      tr.T_internal = ans.T;
      tr.T = stagedcore::clampd(ans.T, ctx.T_MIN, ctx.T_MAX);
      tr.P = P[i];
      tr.V = Vfrac;
      tr.x = ans.x;
      tr.y = ans.y;
      tr.m_vap_up_kgph = V_up[i] * s.mScale_internal;
      tr.m_liq_dn_kgph = L_dn[i] * s.mScale_internal;
      tr.Kmin = ans.Kmin;
      tr.Kmax = ans.Kmax;
      tr.Htarget = ans.Htarget;
      tr.Hcalc = ans.Hcalc;
      tr.dH = ans.dH;
      tr.sideDraw_kgph = s.sideDraws_kgph[i];
      tr.sideDraw_target_kgph = drawmodels::targetKgphForTray(drawState, i, opt.feedRate_kgph);
      tr.sideDraw_frac = drawmodels::targetFractionForTray(drawState, i);
      traysOut[i] = std::move(tr);
   }
   return traysOut;
}

inline MassBalance buildMassBalance(const SimulationOptions& opt, const ProductScalingData& s) {
   MassBalance mb;
   mb.feed_kgph = opt.feedRate_kgph;
   mb.overhead_kgph = s.D_kgph;
   mb.sideDraws_kgph = s.sideDraws_kgph;
   mb.bottoms_kgph = s.B_kgph;
   mb.totalProducts_kgph = s.D_kgph + s.B_kgph + std::accumulate(s.sideDraws_kgph.begin(), s.sideDraws_kgph.end(), 0.0);
   return mb;
}

inline void emitDrawEqualityDiagnostics(const MainColumnReportingContext& ctx, const std::vector<TrayResult>& traysOut, const ProductScalingData& s) {
   if (!ctx.logFn || !(*ctx.logFn)) return;
   const auto& opt = *ctx.opt;
   auto& logFn = *ctx.logFn;
   auto labelForTray1 = [&](int tray1) -> std::string {
      auto it = opt.drawLabels.find(tray1);
      return (it != opt.drawLabels.end()) ? it->second : std::string();
   };
   struct DrawInfo { int tray1; double target; double actual; std::string label; };
   std::vector<DrawInfo> draws;
   draws.reserve(opt.trays);
   for (int i = 0; i < opt.trays; ++i) {
      const double actual = (i < static_cast<int>(s.sideDraws_kgph.size())) ? s.sideDraws_kgph[i] : 0.0;
      double target = 0.0; bool hasTarget = false; std::string label;
      for (const auto& ds : opt.drawSpecs) {
         if (ds.trayIndex0 != i) continue;
         if (!ds.phase.empty() && ds.phase != "L") continue;
         double t = 0.0;
         if (ds.basis == "kgph") { t = std::max(0.0, ds.value); hasTarget = true; }
         else if (ds.basis == "feedPct") { t = std::max(0.0, ds.value) * 0.01 * opt.feedRate_kgph; hasTarget = true; }
         else if (ds.basis == "stageLiqPct") {
            const double Ltray = (i < static_cast<int>(traysOut.size())) ? std::max(0.0, traysOut[i].m_liq_dn_kgph) : 0.0;
            t = std::max(0.0, ds.value) * 0.01 * Ltray; hasTarget = true;
         }
         target += t;
         if (!ds.name.empty()) { if (!label.empty()) label += ", "; label += ds.name; }
      }
      if (label.empty()) label = labelForTray1(i + 1);
      if (!hasTarget && !(actual > 0.0)) continue;
      draws.push_back({i + 1, target, actual, label});
   }
   for (const auto& d : draws) {
      if (!(std::isfinite(d.target) && d.target > 1e-9)) continue;
      const double relErr = std::abs(d.actual - d.target) / std::max(1.0, d.target);
      if (relErr > 0.05) {
         std::ostringstream oss;
         oss << "[DRAW_MISMATCH] tray=" << d.tray1;
         if (!d.label.empty()) oss << " (" << d.label << ")";
         oss << "  target=" << std::fixed << std::setprecision(2) << d.target << " kg/h  actual=" << d.actual << " kg/h  relErr=" << (100.0 * relErr) << "%";
         logFn(oss.str());
      }
   }
   const double absTol = 1e-3; const double relTol = 1e-6;
   for (size_t a = 0; a < draws.size(); ++a) {
      for (size_t b = a + 1; b < draws.size(); ++b) {
         const double A = draws[a].actual, B = draws[b].actual;
         if (!(A > 0.0) || !(B > 0.0)) continue;
         const double diff = std::abs(A - B);
         const double tol = std::max(absTol, relTol * std::max(std::abs(A), std::abs(B)));
         if (diff <= tol) {
            std::ostringstream oss;
            oss << "[DRAW_EQUALITY] draws have ~identical actual flow: tray " << draws[a].tray1;
            if (!draws[a].label.empty()) oss << " (" << draws[a].label << ")";
            oss << " and tray " << draws[b].tray1;
            if (!draws[b].label.empty()) oss << " (" << draws[b].label << ")";
            oss << "  actual=" << std::fixed << std::setprecision(2) << A << " kg/h";
            logFn(oss.str());
         }
      }
   }
}

inline EnergySpecSummary buildEnergySummary(const MainColumnReportingContext& ctx, const ProductScalingData& s, const MassBalance& mb, double L_ref, double V_boil) {
   const auto& opt = *ctx.opt;
   EnergySpecSummary energy;
   energy.Qc_calc_kW = ctx.Qc_kW;
   energy.Qr_calc_kW = ctx.Qr_kW;
   energy.Tc_calc_K = ctx.Tc;
   energy.Treb_calc_K = ctx.Treb_last;
   energy.condenserSpec = opt.condenserSpec;
   energy.reboilerSpec = opt.reboilerSpec;
   energy.condenserType = opt.condenserType;
   energy.reboilerType = opt.reboilerType;
   energy.Tc_set_K = ctx.Tc_set_K;
   energy.Qc_set_kW = ctx.Qc_set_kW;
   energy.Treb_set_K = ctx.Treb_set_K;
   energy.Qr_set_kW = ctx.noReboiler ? 0.0 : stagedcore::clampd(opt.Qr_kW_in, 0.0, 80000.0);
   energy.refluxRatio_set = ctx.noCondenser ? 0.0 : opt.refluxRatio;
   energy.refluxRatio_calc = L_ref / std::max(1e-6, s.D_dim);
   energy.boilupRatio_set = ctx.noReboiler ? 0.0 : opt.reboilRatio;
   energy.boilupRatio_calc = V_boil / std::max(1e-6, s.B_dim);
   energy.mScale_internal = s.mScale_internal;
   energy.mScale_products = s.mScale_products;
   energy.D_kgph = s.D_kgph;
   energy.B_kgph = s.B_kgph;
   energy.L_ref_kgph = s.L_ref_kgph;
   energy.V_boil_kgph = s.V_boil_kgph;
   energy.reflux_fraction = stagedcore::clampd((L_ref) / std::max(1e-6, (L_ref + (*ctx.V_up)[ctx.N - 1])), 0.0, 1.0);
   energy.boilup_fraction = stagedcore::clampd((V_boil) / std::max(1e-6, (V_boil + ctx.B_dim_last)), 0.0, 1.0);
   energy.sideDraws_kgph = s.sideDraws_kgph;
   energy.massBalance = mb;
   return energy;
}

inline std::vector<Diagnostic> buildDiagnostics(const MainColumnReportingContext& ctx) {
   const auto& opt = *ctx.opt;
   std::vector<Diagnostic> diagnostics;
   auto addDiag = [&](const std::string& level, const std::string& code, const std::string& msg) { diagnostics.push_back(Diagnostic{ level, code, msg }); };
   const std::string cMode = boundarymodels::trimLower(opt.condenserSpec);
   const std::string rbMode = boundarymodels::trimLower(opt.reboilerSpec);
   const std::string cText = ctx.noCondenser ? "Condenser removed (open-top, Qc=0, no reflux)" : ((cMode == "duty") ? "Condenser spec: Duty (Tc calculated)" : "Condenser spec: Temperature (Qc calculated)");
   const std::string rText = ctx.noReboiler ? "Reboiler removed (open-bottom, Qr=0, no boilup)" : ((rbMode == "temperature") ? "Reboiler spec: Temperature (Qr calculated)" : ((rbMode == "boilup") ? "Reboiler spec: Boilup ratio (Qr calculated)" : "Reboiler spec: Duty (Treb calculated)"));
   addDiag("info", "ACTIVE_SPECS", cText + " | " + rText);
   if (ctx.rb_vfracClamped) {
      std::ostringstream oss; oss.setf(std::ios::fixed); oss.precision(3);
      oss << "Reboiler vapor fraction limited to keep a liquid bottoms draw (V used=" << (std::isfinite(ctx.rb_vfracUsed) ? ctx.rb_vfracUsed : 0.0) << "; raw=" << (std::isfinite(ctx.rb_vfracRaw) ? ctx.rb_vfracRaw : 0.0) << ").";
      addDiag("warning", "REB_VFRAC_CLAMP", oss.str());
   }
   if (ctx.rb_hitDutyMax) addDiag("warning", "REB_Q_MAX", "Reboiler duty hit the upper limit (Qr clamped), so the selected spec may not be fully achievable.");
   if (ctx.rb_hitDutyMin) addDiag("warning", "REB_Q_MIN", "Reboiler duty hit the lower limit (Qr clamped), so the selected spec may not be fully achievable.");
   if (ctx.c_tcAtMin || ctx.c_tcAtMax) addDiag("warning", "COND_T_LIMIT", "Condenser temperature reached an internal safety limit while solving the duty spec.");
   return diagnostics;
}

inline void addStreamSnapshot(SimulationResult& out, const SimulationOptions& opt, const std::string& name, int tray1based, double kgph, double T_K, double P_Pa, double Vfrac, const std::vector<double>& z) {
   if (!(kgph > 0.0)) return;
   StreamSnapshot s;
   s.name = name;
   s.tray = tray1based;
   s.kgph = kgph;
   s.T = T_K;
   s.P = P_Pa;
   s.Vfrac = Vfrac;
   s.MW = (opt.components ? mixMW(*opt.components, z) : 0.0);
   s.rho = (opt.components ? mixRhoL(*opt.components, z) : std::numeric_limits<double>::quiet_NaN());
   s.composition = z;
   out.streams.push_back(std::move(s));
}

inline SimulationResult buildMainColumnResult(const MainColumnReportingContext& ctx, double L_ref, double V_boil) {
   const auto& opt = *ctx.opt;
   ProductScalingData scaling = computeScaling(ctx, L_ref, V_boil);
   emitScaleLogs(ctx, scaling, L_ref, V_boil);
   auto traysOut = buildTrayResults(ctx, scaling, L_ref, V_boil);
   MassBalance mb = buildMassBalance(opt, scaling);
   emitDrawEqualityDiagnostics(ctx, traysOut, scaling);
   EnergySpecSummary energy = buildEnergySummary(ctx, scaling, mb, L_ref, V_boil);
   auto diagnostics = buildDiagnostics(ctx);

   SimulationResult out;
   out.trays = std::move(traysOut);
   out.feedTray = opt.feedTray;
   out.draws = !opt.drawLabels.empty() ? opt.drawLabels : *ctx.fallbackDrawMap;
   out.status = "OK";
   out.diagnostics = std::move(diagnostics);
   out.energy = std::move(energy);
   out.boundary.condenser.T_cold_K = ctx.Tc;
   out.boundary.reboiler.T_hot_K = ctx.Treb_last;

   out.streams.clear();
   out.streams.reserve(ctx.N + 2);
   const auto& top = out.trays[ctx.N - 1];
   if (ctx.noCondenser) addStreamSnapshot(out, opt, "Distillate", ctx.N, out.energy.D_kgph, top.T, top.P, 1.0, top.y);
   else addStreamSnapshot(out, opt, "Distillate", ctx.N, out.energy.D_kgph, top.T, top.P, 0.0, top.x);
   for (int i = ctx.N - 1; i >= 0; --i) {
      if (scaling.sideDraws_kgph[i] <= 0.0) continue;
      const int tray = i + 1;
      std::string nm;
      auto it = out.draws.find(tray);
      nm = (it != out.draws.end()) ? it->second : ("Draw@" + std::to_string(tray));
      const auto& tr = out.trays[i];
      addStreamSnapshot(out, opt, nm, tray, scaling.sideDraws_kgph[i], tr.T, tr.P, tr.V, tr.x);
   }
   const auto& bot = out.trays[0];
   addStreamSnapshot(out, opt, "Bottoms", 1, out.energy.B_kgph, bot.T, bot.P, 0.0, bot.x);
   return out;
}

} // namespace reportingmodels
