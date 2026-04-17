#pragma once

#include <string>
#include <vector>
#include <functional>

namespace stagedcore {

double clampd(double x, double lo, double hi);
void normalize(std::vector<double>& v);
std::vector<double> blendVec(const std::vector<double>& a, const std::vector<double>& b, double w);
double etaBySection(int i, int N, int f, double etaTop, double etaMid, double etaBot);
std::vector<double> initTrayPressures(int N, double Ptop, double Pdrop);
std::vector<double> initTrayTempsTwoSegment(int N, double Ttop, double Tbottom, double Tfeed, int f);
void projectMonotoneTemps(std::vector<double>& T, int f);
void smoothVectorMidpoint(std::vector<double>& v, int passes, bool keepEnds);

struct StagedColumnCoreState {
   std::vector<double> T;
   std::vector<double> P;
   std::vector<double> V_up;
   std::vector<std::vector<double>> Y_up;
   std::vector<double> L_dn;
   std::vector<std::vector<double>> X_dn;
};

struct BoundaryRecycleState {
   double L_ref = 0.0;
   std::vector<double> x_ref;
   double V_boil = 0.0;
   std::vector<double> y_boil;
};

struct ConvergenceSnapshot {
   bool didConverge = false;
   int iterFinal = -1;
   double residFinal = 0.0;
   double dTFinal = 0.0;
   double residLast = 0.0;
   double dTLast = 0.0;
   double TtopFinal = 0.0;
   double TbotFinal = 0.0;
};

void applyRelaxedDownflow(
   const std::vector<double>& next_L_dn,
   const std::vector<std::vector<double>>& next_X_dn,
   double relax,
   std::vector<double>& L_dn,
   std::vector<std::vector<double>>& X_dn,
   double Lref_new,
   const std::vector<double>& xref_new);

void applyRelaxedBoundaryRecycle(
   double relax,
   double Lref_new,
   const std::vector<double>& xref_new,
   double Vboil_new,
   const std::vector<double>& yboil_new,
   BoundaryRecycleState& state);

void clampTrafficDim(
   BoundaryRecycleState& state,
   std::vector<double>& V_up,
   std::vector<double>& L_dn,
   double maxTrafficDim,
   const std::function<void(const std::string&)>& logFn,
   const char* where);

bool updateConvergence(
   ConvergenceSnapshot& snapshot,
   int iter,
   double residSplit,
   double dTend,
   double tolSplit,
   double tolTemp);

StagedColumnCoreState makeInitialCoreState(
   int N,
   int feedTrayIndex0,
   const std::vector<double>& feedZ,
   double Ttop,
   double Tbottom,
   double Tfeed,
   double Ptop,
   double Pdrop);

} // namespace stagedcore
