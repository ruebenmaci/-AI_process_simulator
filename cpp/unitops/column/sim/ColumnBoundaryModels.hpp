#pragma once

#include <algorithm>
#include <cmath>
#include <functional>
#include <string>
#include <vector>

#include "CounterCurrentColumnSimulator.hpp"
#include "StagedColumnCore.hpp"
#include "../thermo/PH_PS_PT_TS_Flash.hpp"
#include "../thermo/Enthalpy.hpp"

namespace boundarymodels {

inline std::string trimLower(std::string s) {
   auto isSpace = [](unsigned char c) { return std::isspace(c) != 0; };
   while (!s.empty() && isSpace((unsigned char)s.front())) s.erase(s.begin());
   while (!s.empty() && isSpace((unsigned char)s.back())) s.pop_back();
   for (char& c : s) c = (char)std::tolower((unsigned char)c);
   return s;
}

inline bool isNoneSpec(const std::string& specRaw) {
   const std::string s = trimLower(specRaw);
   return s.empty() || s == "none" || s.rfind("none", 0) == 0;
}

enum class TopBoundaryMode { TotalCondenser, PartialCondenser, OpenTop };
enum class BottomBoundaryMode { PartialReboiler, TotalReboiler, OpenBottom };

struct TopBoundarySpec {
   TopBoundaryMode mode = TopBoundaryMode::TotalCondenser;
   std::string condenserType = "total";
   std::string controlMode = "temperature";
   double refluxRatio = 0.0;
   double Tc_set_K = NAN;
   double Qc_set_kW = 0.0;
};

struct BottomBoundarySpec {
   BottomBoundaryMode mode = BottomBoundaryMode::PartialReboiler;
   std::string reboilerType = "partial";
   std::string controlMode = "duty";
   double reboilRatio = 0.0;
   double Treb_set_K = NAN;
   double Qr_set_kW = 0.0;
};

struct CondenserBoundaryResult {
   double Qc_kW = 0.0;
   double Tc = NAN;
   bool tcAtMin = false;
   bool tcAtMax = false;
};

struct ReboilerBoundaryResult {
   double Treb = NAN;
   double Vfrac_reb = 0.0;
   double Vboil_new = 0.0;
   double B_new = 0.0;
   std::vector<double> yboil_new;
   std::vector<double> xB_new;
   double Qr_kW = 0.0;
   bool rb_hitDutyMax = false;
   bool rb_hitDutyMin = false;
   bool rb_vfracClamped = false;
   double rb_vfracRaw = NAN;
   double rb_vfracUsed = NAN;
};

inline TopBoundarySpec makeTopBoundarySpec(const SimulationOptions& opt, double Tmin, double Tmax) {
   TopBoundarySpec s;
   s.condenserType = trimLower(opt.condenserType);
   s.controlMode = trimLower(opt.condenserSpec);
   s.refluxRatio = isNoneSpec(opt.condenserSpec) ? 0.0 : opt.refluxRatio;
   s.Tc_set_K = stagedcore::clampd(opt.Ttop, Tmin, Tmax);
   s.Qc_set_kW = isNoneSpec(opt.condenserSpec) ? 0.0 : stagedcore::clampd(opt.Qc_kW_in, -80000.0, 0.0);
   if (isNoneSpec(opt.condenserSpec)) s.mode = TopBoundaryMode::OpenTop;
   else if (s.condenserType == "partial") s.mode = TopBoundaryMode::PartialCondenser;
   else s.mode = TopBoundaryMode::TotalCondenser;
   return s;
}

inline BottomBoundarySpec makeBottomBoundarySpec(const SimulationOptions& opt, double Tmin, double Tmax) {
   BottomBoundarySpec s;
   s.reboilerType = trimLower(opt.reboilerType);
   s.controlMode = trimLower(opt.reboilerSpec);
   s.reboilRatio = isNoneSpec(opt.reboilerSpec) ? 0.0 : opt.reboilRatio;
   s.Treb_set_K = stagedcore::clampd(opt.Tbottom, Tmin, Tmax);
   s.Qr_set_kW = isNoneSpec(opt.reboilerSpec) ? 0.0 : stagedcore::clampd(opt.Qr_kW_in, 0.0, 80000.0);
   if (isNoneSpec(opt.reboilerSpec)) s.mode = BottomBoundaryMode::OpenBottom;
   else if (s.reboilerType == "total") s.mode = BottomBoundaryMode::TotalReboiler;
   else s.mode = BottomBoundaryMode::PartialReboiler;
   return s;
}

inline double solveCondenserTcFromDuty(const std::vector<double>& y, const std::vector<Component>& comps, double P, int trayIndex, double mV_in_kgps, double hV_in, double Qc_target_kW, double Tseed, double T_MIN, double T_MAX) {
   auto QcAt = [&](double Tc) -> double {
      const double hL_out = hLiq(y, Tc, trayIndex, comps, P);
      const double Qc_HB_kW = -mV_in_kgps * (hV_in - hL_out);
      return Qc_HB_kW;
   };
   auto f = [&](double Tc) -> double { return QcAt(Tc) - Qc_target_kW; };
   double lo = T_MIN, hi = T_MAX;
   double flo = f(lo), fhi = f(hi);
   if (!(std::isfinite(flo) && std::isfinite(fhi)) || (flo > 0 && fhi > 0) || (flo < 0 && fhi < 0)) {
      return stagedcore::clampd(Tseed, T_MIN, T_MAX);
   }
   double mid = 0.5 * (lo + hi);
   for (int it = 0; it < 60; ++it) {
      mid = 0.5 * (lo + hi);
      const double fmid = f(mid);
      if (!std::isfinite(fmid)) break;
      if (std::abs(fmid) < 1e-3) break;
      if ((flo <= 0 && fmid <= 0) || (flo >= 0 && fmid >= 0)) { lo = mid; flo = fmid; }
      else { hi = mid; fhi = fmid; }
      if (std::abs(hi - lo) < 1e-6) break;
   }
   return stagedcore::clampd(mid, T_MIN, T_MAX);
}

inline CondenserBoundaryResult computeCondenserBoundary(const TopBoundarySpec& spec, const std::vector<double>& y_top, const std::vector<Component>& comps, double P, double mV_in_kgps, double hV_in, double Tc_current, double topTrayT, double T_MIN, double T_MAX) {
   CondenserBoundaryResult r;
   if (spec.mode == TopBoundaryMode::OpenTop) {
      r.Qc_kW = 0.0;
      r.Tc = std::isfinite(topTrayT) ? topTrayT : spec.Tc_set_K;
      return r;
   }
   if (spec.controlMode == "duty") {
      r.Qc_kW = spec.Qc_set_kW;
      r.Tc = solveCondenserTcFromDuty(y_top, comps, P, 0, mV_in_kgps, hV_in, r.Qc_kW, Tc_current, T_MIN, T_MAX);
      r.tcAtMin = (r.Tc <= T_MIN + 1e-6);
      r.tcAtMax = (r.Tc >= T_MAX - 1e-6);
   } else {
      r.Tc = spec.Tc_set_K;
      const double hL_out = hLiq(y_top, r.Tc, 0, comps, P);
      const double Qc_HB_kW = -mV_in_kgps * (hV_in - hL_out);
      r.Qc_kW = stagedcore::clampd(Qc_HB_kW, -80000.0, 0.0);
   }
   return r;
}

inline ReboilerBoundaryResult computeReboilerBoundary(const BottomBoundarySpec& spec, double L_to_reb, const std::vector<double>& x_to_reb, double feed_kgps, double P0, double Tseed, double Qr_current, double& ei_bot_int, const std::vector<Component>& comps, const std::vector<Component>* compsPtr, const std::string& eos, const std::function<void(const std::string&)>& logFn, LogLevel logLevel, double T_MIN, double T_MAX, double Kr_Q, double Ki_Q) {
   ReboilerBoundaryResult r;
   r.Qr_kW = Qr_current;
   r.Treb = stagedcore::clampd(Tseed, T_MIN, T_MAX);
   r.B_new = L_to_reb;
   r.yboil_new = x_to_reb;
   r.xB_new = x_to_reb;
   if (spec.mode == BottomBoundaryMode::OpenBottom) {
      r.Qr_kW = 0.0;
      r.rb_vfracRaw = 0.0;
      r.rb_vfracUsed = 0.0;
      return r;
   }
   const double mL_in_kgps = L_to_reb * feed_kgps;
   const double Hin_reb = hLiq(x_to_reb, stagedcore::clampd(Tseed, T_MIN, T_MAX), 0, comps, P0);
   const double Htarget_reb = Hin_reb + r.Qr_kW / std::max(1e-12, mL_in_kgps);
   FlashPHSatInput in;
   in.Htarget = Htarget_reb;
   in.z = x_to_reb;
   in.P = P0;
   in.Tseed = stagedcore::clampd(Tseed, T_MIN, T_MAX);
   in.components = compsPtr;
   in.trayIndex = 0;
   in.eos = eos;
   in.Tmin = T_MIN;
   in.Tmax = T_MAX;
   in.maxIter = 80;
   in.log = logFn;
   in.logLevel = logLevel;
   FlashPHSatResult reb = flashPH_saturated(in);
   r.Treb = stagedcore::clampd(reb.T, T_MIN, T_MAX);
   const double VFRAC_REB_MAX_USER = (spec.mode == BottomBoundaryMode::TotalReboiler) ? 0.999 : 0.95;
   const double MIN_B_DIM = 1e-4;
   const double maxVByBmin = 1.0 - MIN_B_DIM / std::max(1e-12, L_to_reb);
   const double VFRAC_REB_MAX = std::min(VFRAC_REB_MAX_USER, maxVByBmin);
   const double Vfrac_raw = stagedcore::clampd(reb.V, 0.0, 1.0);
   r.Vfrac_reb = std::min(VFRAC_REB_MAX, Vfrac_raw);
   r.rb_vfracRaw = Vfrac_raw;
   r.rb_vfracUsed = r.Vfrac_reb;
   r.rb_vfracClamped = (Vfrac_raw > VFRAC_REB_MAX + 1e-8);
   r.Vboil_new = std::max(1e-12, L_to_reb * r.Vfrac_reb);
   r.B_new = std::max(1e-12, L_to_reb * (1.0 - r.Vfrac_reb));
   r.yboil_new = (!reb.y.empty() ? reb.y : x_to_reb);
   r.xB_new = (!reb.x.empty() ? reb.x : x_to_reb);
   if (spec.controlMode == "temperature") {
      const double eT = spec.Treb_set_K - r.Treb;
      ei_bot_int += eT;
      const double Qr_proposed = r.Qr_kW + Kr_Q * eT + Ki_Q * ei_bot_int;
      r.Qr_kW = stagedcore::clampd(Qr_proposed, 0.0, 80000.0);
      r.rb_hitDutyMin = (r.Qr_kW <= 1e-9 && Qr_proposed < 0);
      r.rb_hitDutyMax = (r.Qr_kW >= 80000.0 - 1e-9 && Qr_proposed > 80000.0);
   } else if (spec.controlMode == "boilup") {
      const double ratio = r.Vboil_new / std::max(1e-12, r.B_new);
      const double eR = spec.reboilRatio - ratio;
      ei_bot_int += eR;
      const double K_ratio = 20000.0;
      const double Ki_ratio = 2000.0;
      const double Qr_proposed = r.Qr_kW + K_ratio * eR + Ki_ratio * ei_bot_int;
      r.Qr_kW = stagedcore::clampd(Qr_proposed, 0.0, 80000.0);
      r.rb_hitDutyMin = (r.Qr_kW <= 1e-9 && Qr_proposed < 0);
      r.rb_hitDutyMax = (r.Qr_kW >= 80000.0 - 1e-9 && Qr_proposed > 80000.0);
   } else {
      r.Qr_kW = spec.Qr_set_kW;
   }
   return r;
}

} // namespace boundarymodels
