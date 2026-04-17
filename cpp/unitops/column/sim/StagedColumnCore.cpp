#include "StagedColumnCore.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>

namespace stagedcore {

   double clampd(double x, double lo, double hi) {
      return std::min(std::max(x, lo), hi);
   }

   void normalize(std::vector<double>& v) {
      double s = 0.0;
      for (double a : v) s += a;
      if (s <= 0.0) return;
      for (double& a : v) a = std::max(0.0, a / s);
   }

   std::vector<double> blendVec(const std::vector<double>& a, const std::vector<double>& b, double w) {
      if (a.empty()) return b;
      if (b.empty()) return a;
      const size_t n = std::min(a.size(), b.size());
      std::vector<double> out(n, 0.0);
      const double wa = 1.0 - w;
      for (size_t i = 0; i < n; ++i) out[i] = wa * a[i] + w * b[i];
      normalize(out);
      return out;
   }

   double etaBySection(int i, int N, int f, double etaTop, double etaMid, double etaBot) {
      if (i <= static_cast<int>(std::floor(f / 2.0))) return clampd(std::isfinite(etaBot) ? etaBot : 1.0, 0.0, 1.0);
      if (i >= static_cast<int>(std::ceil((f + N - 1) / 2.0))) return clampd(std::isfinite(etaTop) ? etaTop : 1.0, 0.0, 1.0);
      return clampd(std::isfinite(etaMid) ? etaMid : 1.0, 0.0, 1.0);
   }

   std::vector<double> initTrayPressures(int N, double Ptop, double Pdrop) {
      std::vector<double> P(N, 0.0);
      for (int i = 0; i < N; ++i) {
         P[i] = Ptop + (N - 1 - i) * Pdrop;
      }
      return P;
   }

   std::vector<double> initTrayTempsTwoSegment(int N, double Ttop, double Tbottom, double Tfeed, int f) {
      std::vector<double> T(N, 0.0);
      for (int i = 0; i <= f; ++i) {
         const double a = (f <= 0) ? 0.0 : double(i) / double(f);
         T[i] = (1.0 - a) * Tbottom + a * Tfeed;
      }
      for (int i = f; i < N; ++i) {
         const double denom = std::max(1, (N - 1 - f));
         const double a = double(i - f) / double(denom);
         T[i] = (1.0 - a) * Tfeed + a * Ttop;
      }
      return T;
   }

   void projectMonotoneTemps(std::vector<double>& T, int f) {
      const int N = static_cast<int>(T.size());
      if (N <= 1) return;
      for (int i = 0; i < f; ++i) {
         if (T[i + 1] > T[i]) T[i + 1] = T[i];
      }
      for (int i = f; i < N - 1; ++i) {
         if (T[i + 1] > T[i]) T[i + 1] = T[i];
      }
   }

   void smoothVectorMidpoint(std::vector<double>& v, int passes, bool keepEnds) {
      const int n = static_cast<int>(v.size());
      if (n < 3) return;
      std::vector<double> tmp(v);
      for (int p = 0; p < passes; ++p) {
         tmp = v;
         for (int i = 1; i < n - 1; ++i) tmp[i] = 0.25 * v[i - 1] + 0.5 * v[i] + 0.25 * v[i + 1];
         if (keepEnds) { tmp[0] = v[0]; tmp[n - 1] = v[n - 1]; }
         v.swap(tmp);
      }
   }

   StagedColumnCoreState makeInitialCoreState(
      int N,
      int feedTrayIndex0,
      const std::vector<double>& feedZ,
      double Ttop,
      double Tbottom,
      double Tfeed,
      double Ptop,
      double Pdrop) {
      StagedColumnCoreState s;
      s.T = initTrayTempsTwoSegment(N, Ttop, Tbottom, Tfeed, feedTrayIndex0);
      s.P = initTrayPressures(N, Ptop, Pdrop);
      s.V_up.assign(N, 0.2);
      s.Y_up.assign(N, feedZ);
      s.L_dn.assign(N, 0.8);
      s.X_dn.assign(N, feedZ);
      return s;
   }

   void applyRelaxedDownflow(
      const std::vector<double>& next_L_dn,
      const std::vector<std::vector<double>>& next_X_dn,
      double relax,
      std::vector<double>& L_dn,
      std::vector<std::vector<double>>& X_dn,
      double Lref_new,
      const std::vector<double>& xref_new)
   {
      const int N = static_cast<int>(L_dn.size());
      std::vector<double> L_dn_next(N, 0.0);
      std::vector<std::vector<double>> X_dn_next(N);

      for (int i = 0; i < N - 1; ++i) {
         L_dn_next[i] = (1.0 - relax) * L_dn[i] + relax * next_L_dn[i];
         X_dn_next[i] = (!next_X_dn[i].empty())
            ? blendVec(X_dn[i].empty() ? next_X_dn[i] : X_dn[i], next_X_dn[i], relax)
            : X_dn[i];
      }

      if (N > 0) {
         L_dn_next[N - 1] = Lref_new;
         X_dn_next[N - 1] = xref_new;
      }

      L_dn.swap(L_dn_next);
      X_dn.swap(X_dn_next);
   }

   void applyRelaxedBoundaryRecycle(
      double relax,
      double Lref_new,
      const std::vector<double>& xref_new,
      double Vboil_new,
      const std::vector<double>& yboil_new,
      BoundaryRecycleState& state)
   {
      state.L_ref = (1.0 - relax) * state.L_ref + relax * Lref_new;
      state.x_ref = blendVec(state.x_ref, xref_new, relax);
      state.V_boil = (1.0 - relax) * state.V_boil + relax * Vboil_new;
      state.y_boil = blendVec(state.y_boil, yboil_new, relax);
   }

   void clampTrafficDim(
      BoundaryRecycleState& state,
      std::vector<double>& V_up,
      std::vector<double>& L_dn,
      double kMaxTrafficDim,
      const std::function<void(const std::string&)>& logFn,
      const char* where)
   {
      auto maxAbsVec = [](const std::vector<double>& v) -> double {
         double m = 0.0;
         for (double x : v) {
            if (std::isfinite(x)) m = std::max(m, std::abs(x));
         }
         return m;
         };

      const double kMinTrafficDim = 1e-12;
      const double maxAbs = std::max({
         std::abs(state.V_boil),
         std::abs(state.L_ref),
         maxAbsVec(V_up),
         maxAbsVec(L_dn),
         kMinTrafficDim
         });

      if (maxAbs > kMaxTrafficDim && std::isfinite(maxAbs)) {
         const double scale = kMaxTrafficDim / maxAbs;
         state.V_boil *= scale;
         state.L_ref *= scale;
         for (auto& v : V_up) v *= scale;
         for (auto& v : L_dn) v *= scale;

         if (logFn) {
            std::ostringstream oss;
            oss.setf(std::ios::fixed);
            oss << "[TRAFFIC_CLAMP] where=" << where
               << " maxAbsDim=" << maxAbs
               << " scale=" << scale;
            logFn(oss.str());
         }
      }
   }

   bool updateConvergence(
      ConvergenceSnapshot& conv,
      int iter,
      double residSplit,
      double dTend,
      double tolSplit,
      double tolTemp)
   {
      conv.residLast = residSplit;
      conv.dTLast = dTend;

      const bool splitOK = (residSplit < tolSplit);
      const bool tempOK = (dTend < tolTemp);

      if (splitOK && tempOK && iter > 10) {
         conv.didConverge = true;
         conv.iterFinal = iter;
         conv.residFinal = residSplit;
         conv.dTFinal = dTend;
         return true;
      }
      return false;
   }

} // namespace stagedcore