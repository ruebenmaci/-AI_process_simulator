#pragma once

#include <string>
#include <vector>

struct SideDrawSpec
{
   std::string name;
   int trayIndex0 = -1;
   std::string basis = "feedPct";
   std::string phase = "L";
   double value = 0.0;
};