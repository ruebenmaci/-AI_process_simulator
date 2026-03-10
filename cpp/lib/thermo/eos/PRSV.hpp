#pragma once

#include <vector>
#include <cmath>
#include <string>
#include <functional>

#include "../pseudocomponents/componentData.hpp"

struct PRSVResult {
   bool singlePhase = false;
   std::string phase;  // "L" or "V" when singlePhase==true

   double ZL = NAN;
   double ZV = NAN;

   std::vector<double> phiL;
   std::vector<double> phiV;

   double hdepL = 0.0;
   double hdepV = 0.0;

   std::vector<double> a_i;
   std::vector<double> b_i;

   double a_mix = 0.0;
   double b_mix = 0.0;

   bool fallbackUsed = false;          // ? NEW
   std::string fallbackReason;         // ? optional but super useful
};

double kappaPRSV(double omega);
double alphaPRSV(double T, double Tc, double omega);

PRSVResult solvePRSV(
   double P,
   double T,
   const std::vector<double>& x,
   int trayIndex,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij = nullptr,
   const std::function<void(const std::string&)>& log = nullptr
);

// Flush/clear PRSV log coalescing state.
// See EOSK.hpp flushEOSKCoalescer() for the motivation.
void flushPRSVCoalescer(const std::function<void(const std::string&)>& logger = {});

PRSVResult solvePRSV_withLogger(
   double P,
   double T,
   const std::vector<double>& z,
   const std::vector<Component>& comps,
   const std::vector<std::vector<double>>* kij,
   const std::function<void(const std::string&)>& logger,
   bool diag,
   int trayIndex);