#include <catch2/catch_all.hpp>
#include <cmath>
#include <string>
#include <vector>

#include "TestData.hpp"

static bool finite(double x) { return std::isfinite(x); }

TEST_CASE("Products sum is near feed (loose tolerance)", "[balance]") {
   SolverInputs in = makeBaselineInputs();

   LogCollector log;
   ProgressCollector prog;

   SolverOutputs out = solveColumn(in,
      [&](const std::string& s) { log(s); },
      [&](const ProgressEvent& ev) { prog(ev); }
   );

   REQUIRE(finite(out.energy.massBalance.totalProducts_kgph));
   REQUIRE(out.energy.massBalance.totalProducts_kgph > 0.0);

   REQUIRE(out.energy.massBalance.totalProducts_kgph ==
      Catch::Approx(in.feedRateKgph).margin(in.feedRateKgph * 0.05));
}

#include <sstream>

static double drawTargetFromRunResults(const std::string& rr, int tray1)
{
   std::istringstream iss(rr);
   std::string line;
   while (std::getline(iss, line)) {
      if (line.empty()) continue;
      if (line.rfind("Tray,TempK", 0) == 0) continue;
      if (line.rfind("Stream,", 0) == 0) break;

      std::vector<std::string> cols;
      std::stringstream ls(line);
      std::string tok;
      while (std::getline(ls, tok, ',')) cols.push_back(tok);

      // Expected:
      // Tray,TempK,PressurePa,Vfrac,L_kgph,V_kgph,DrawTarget_kgph,DrawActual_kgph,...
      if (cols.size() < 8) continue;
      const int t = std::stoi(cols[0]);
      if (t != tray1) continue;
      return std::stod(cols[6]);
   }
   return std::numeric_limits<double>::quiet_NaN();
}

TEST_CASE("Draw target uses basis: feedPct vs kgph", "[basis][draw]") {
   constexpr int tray1 = 21;

   // feedPct case: 12% of 100000 = 12000 kg/h
   SolverInputs a = makeBaselineInputs();
   a.drawSpecs.clear();
   a.drawLabelsByTray1.clear();
   a.drawSpecs.push_back(SolverDrawSpec{ tray1 - 1, "Kero", "feedPct", "L", 12.0 });

   SolverOutputs outA = solveColumn(a);
   const double tA = drawTargetFromRunResults(outA.runResultsText, tray1);
   REQUIRE(finite(tA));
   REQUIRE(tA == Catch::Approx(12000.0).margin(1.0));

   // kgph case: explicit 12000 kg/h
   SolverInputs b = makeBaselineInputs();
   b.drawSpecs.clear();
   b.drawLabelsByTray1.clear();
   b.drawSpecs.push_back(SolverDrawSpec{ tray1 - 1, "Kero", "kgph", "L", 12000.0 });

   SolverOutputs outB = solveColumn(b);
   const double tB = drawTargetFromRunResults(outB.runResultsText, tray1);
   REQUIRE(finite(tB));
   REQUIRE(tB == Catch::Approx(12000.0).margin(1.0));
}

TEST_CASE("kgph basis is feed-rate independent target", "[basis][kgph]") {
   constexpr int tray1 = 21;

   SolverInputs in1 = makeBaselineInputs();
   in1.feedRateKgph = 100000.0;
   in1.drawSpecs.clear();
   in1.drawSpecs.push_back(SolverDrawSpec{ tray1 - 1, "Kero", "kgph", "L", 12000.0 });

   SolverInputs in2 = in1;
   in2.feedRateKgph = 200000.0; // double feed

   const double t1 = drawTargetFromRunResults(solveColumn(in1).runResultsText, tray1);
   const double t2 = drawTargetFromRunResults(solveColumn(in2).runResultsText, tray1);

   REQUIRE(finite(t1));
   REQUIRE(finite(t2));
   REQUIRE(t1 == Catch::Approx(12000.0).margin(1.0));
   REQUIRE(t2 == Catch::Approx(12000.0).margin(1.0));
}

static double parseKeyValue(const std::string& line, const std::string& key)
{
   const std::string needle = key + "=";
   const size_t p = line.find(needle);
   if (p == std::string::npos) return std::numeric_limits<double>::quiet_NaN();
   const size_t b = p + needle.size();
   size_t e = b;
   while (e < line.size() && line[e] != ' ' && line[e] != '\t') ++e;
   return std::stod(line.substr(b, e - b));
}

static bool lastSideDrawLogForTray(const std::vector<std::string>& lines, int tray1, std::string& outLine)
{
   const std::string trayTag = "tray=" + std::to_string(tray1);
   for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
      if (it->find("[SIDE_DRAW]") != std::string::npos &&
         it->find(trayTag) != std::string::npos) {
         outLine = *it;
         return true;
      }
   }
   return false;
}

TEST_CASE("stageLiqPct basis commands tray-liquid fraction", "[basis][stageLiqPct]") {
   constexpr int tray1 = 21;
   constexpr double specFrac = 0.20;

   auto runAndRead = [&](double feedKgph, double& targetFrac, double& cmdFrac, double& appliedFrac) {
      SolverInputs in = makeBaselineInputs();
      in.feedRateKgph = feedKgph;
      in.drawSpecs.clear();
      in.drawLabelsByTray1.clear();
      in.drawSpecs.push_back(SolverDrawSpec{ tray1 - 1, "Kero", "stageLiqPct", "L", 20.0 });

      LogCollector log;
      ProgressCollector prog;
      (void)solveColumn(in,
         [&](const std::string& s) { log(s); },
         [&](const ProgressEvent& ev) { prog(ev); });

      std::string line;
      REQUIRE(lastSideDrawLogForTray(log.lines, tray1, line));

      targetFrac = parseKeyValue(line, "targetFrac");
      cmdFrac = parseKeyValue(line, "cmdFrac");
      const double L_before = parseKeyValue(line, "L_out_before");
      const double L_draw = parseKeyValue(line, "L_draw");

      REQUIRE(finite(targetFrac));
      REQUIRE(finite(cmdFrac));
      REQUIRE(finite(L_before));
      REQUIRE(finite(L_draw));
      REQUIRE(L_before > 1e-12);

      appliedFrac = L_draw / L_before;
   };

   double t1 = NAN, c1 = NAN, a1 = NAN;
   double t2 = NAN, c2 = NAN, a2 = NAN;

   runAndRead(100000.0, t1, c1, a1);
   runAndRead(200000.0, t2, c2, a2);

   REQUIRE(t1 == Catch::Approx(specFrac).margin(0.02));
   REQUIRE(t2 == Catch::Approx(specFrac).margin(0.02));
   REQUIRE(c1 == Catch::Approx(specFrac).margin(0.03));
   REQUIRE(c2 == Catch::Approx(specFrac).margin(0.03));
   REQUIRE(a1 == Catch::Approx(c1).margin(0.05));
   REQUIRE(a2 == Catch::Approx(c2).margin(0.05));
}