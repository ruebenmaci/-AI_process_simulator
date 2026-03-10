#include <algorithm>
#include <cmath>

#include "CrudeInitialSettings.hpp"

static inline double K_from_C(double c) { return c + 273.15; }

const std::vector<int>& drawTrays32() {
  static const std::vector<int> v = {0, 7, 14, 20, 26, 29, 31};
  return v;
}

const std::unordered_map<int, std::string>& defaultDrawNamesByTray32() {
  static const std::unordered_map<int, std::string> m = {
    {32, "C1–C4 Overhead"},
    {30, "Light Naphtha"},
    {27, "Heavy Naphtha"},
    {21, "Kerosene"},
    {15, "LGO"},
    { 8, "HGO"},
    { 1, "Residue"},
  };
  return m;
}

const std::unordered_map<std::string, CrudeInitialSettings>& crudeInitialSettings() {
  static const std::unordered_map<std::string, CrudeInitialSettings> all = []() {
    std::unordered_map<std::string, CrudeInitialSettings> m;

    // Brent
    {
      CrudeInitialSettings s;
      s.feedRate_kgph = 100000;
      s.feedTray = 3;
      s.Tfeed_K = K_from_C(355);
      s.Ttop_K = K_from_C(125);
      s.Tbottom_K = K_from_C(345);
      s.Ptop_Pa = 150000;
      s.dP_perTray_Pa = 200;
      s.condenserSpec = "temperature";
      s.reboilerSpec = "duty";
      s.Qc_kW = -6000;
      s.Qr_kW = 6000;
      s.refluxRatio = 2.0;
      s.reboilRatio = 0.06;
      s.murphree = {0.75, 0.65, 0.55, 1.0, 1.0, 1.0};
      s.drawSpecsByTrayIndex = {
        {31, 0.027},
        {29, 0.068},
        {26, 0.144},
        {20, 0.133},
        {14, 0.1305},
        { 7, 0.1305},
        { 0, 0.367},
      };
      m.emplace("Brent", s);
    }

    // West Texas Intermediate
    {
      CrudeInitialSettings s;
      s.feedRate_kgph = 100000;
      s.feedTray = 3;
      s.Tfeed_K = K_from_C(350);
      s.Ttop_K = K_from_C(125);
      s.Tbottom_K = K_from_C(342);
      s.Ptop_Pa = 150000;
      s.dP_perTray_Pa = 200;
      s.condenserSpec = "temperature";
      s.reboilerSpec = "duty";
      s.Qc_kW = -5500;
      s.Qr_kW = 5500;
      s.refluxRatio = 2.0;
      s.reboilRatio = 0.05;
      s.murphree = {0.75, 0.65, 0.55, 1.0, 1.0, 1.0};
      s.drawSpecsByTrayIndex = {
        {31, 0.015},
        {29, 0.057},
        {26, 0.241},
        {20, 0.149},
        {14, 0.1175},
        { 7, 0.1175},
        { 0, 0.302},
      };
      m.emplace("West Texas Intermediate", s);
    }

    // Arab Light
    {
      CrudeInitialSettings s;
      s.feedRate_kgph = 100000;
      s.feedTray = 3;
      s.Tfeed_K = K_from_C(355);
      s.Ttop_K = K_from_C(125);
      s.Tbottom_K = K_from_C(345);
      s.Ptop_Pa = 150000;
      s.dP_perTray_Pa = 200;
      s.condenserSpec = "temperature";
      s.reboilerSpec = "duty";
      s.Qc_kW = -6200;
      s.Qr_kW = 6200;
      s.refluxRatio = 2.0;
      s.reboilRatio = 0.06;
      s.murphree = {0.75, 0.65, 0.55, 1.0, 1.0, 1.0};
      s.drawSpecsByTrayIndex = {
        {31, 0.022},
        {29, 0.066},
        {26, 0.139},
        {20, 0.126},
        {14, 0.1315},
        { 7, 0.1315},
        { 0, 0.384},
      };
      m.emplace("Arab Light", s);
    }

    // Western Canadian Select
    {
      CrudeInitialSettings s;
      s.feedRate_kgph = 100000;
      s.feedTray = 3;
      s.Tfeed_K = K_from_C(360);
      s.Ttop_K = K_from_C(130);
      s.Tbottom_K = K_from_C(350);
      s.Ptop_Pa = 150000;
      s.dP_perTray_Pa = 200;
      s.condenserSpec = "temperature";
      s.reboilerSpec = "duty";
      s.Qc_kW = -6500;
      s.Qr_kW = 6500;
      s.refluxRatio = 2.0;
      s.reboilRatio = 0.07;
      s.murphree = {0.75, 0.65, 0.55, 1.0, 1.0, 1.0};
      s.drawSpecsByTrayIndex = {
        {31, 0.02},
        {29, 0.024},
        {26, 0.12},
        {20, 0.12},
        {14, 0.0595},
        { 7, 0.0595},
        { 0, 0.597},
      };
      m.emplace("Western Canadian Select", s);
    }

    // Venezuelan Heavy
    {
      CrudeInitialSettings s;
      s.feedRate_kgph = 100000;
      s.feedTray = 3;
      s.Tfeed_K = K_from_C(365);
      s.Ttop_K = K_from_C(130);
      s.Tbottom_K = K_from_C(350);
      s.Ptop_Pa = 150000;
      s.dP_perTray_Pa = 200;
      s.condenserSpec = "temperature";
      s.reboilerSpec = "duty";
      s.Qc_kW = -6500;
      s.Qr_kW = 6500;
      s.refluxRatio = 2.0;
      s.reboilRatio = 0.07;
      s.murphree = {0.75, 0.65, 0.55, 1.0, 1.0, 1.0};
      s.drawSpecsByTrayIndex = {
        {31, 0.02},
        {29, 0.024},
        {26, 0.12},
        {20, 0.12},
        {14, 0.0595},
        { 7, 0.0595},
        { 0, 0.597},
      };
      m.emplace("Venezuelan Heavy", s);
    }

    return m;
  }();
  return all;
}

CrudeInitialSettings getCrudeInitialSettings(const std::string& crudeName) {
  const auto& m = crudeInitialSettings();
  auto it = m.find(crudeName);
  if (it != m.end()) return it->second;

  // JS fallback: CRUDE_INITIAL_SETTINGS.Brent
  auto it2 = m.find("Brent");
  if (it2 != m.end()) return it2->second;
  return CrudeInitialSettings{};
}

std::vector<std::string> getAvailableCrudeNames() {
    std::vector<std::string> names;
    const auto &m = crudeInitialSettings();
    names.reserve(m.size());
    for (const auto &kv : m) {
        names.push_back(kv.first);
    }
    std::sort(names.begin(), names.end());
    return names;
}

int getRecommendedFeedTray(const std::string& crudeName, int numTrays) {
  const CrudeInitialSettings cfg = getCrudeInitialSettings(crudeName);

  const int rec = cfg.feedTray;
  const int lo = 2;
  const int hi = std::max(lo, numTrays - 1);

  if (std::isfinite(double(rec))) {
    const int r = (int)std::llround((double)rec);
    return std::min(hi, std::max(lo, r));
  }

  // Fallback heuristic: heavier/hotter feeds go lower.
  const double TfeedK = cfg.Tfeed_K;
  const double TfeedC = std::isfinite(TfeedK) ? (TfeedK - 273.15) : 350.0;
  const int base = (int)std::llround(0.6 * numTrays);
  const int shift = (int)std::llround((TfeedC - 350.0) / 5.0);
  return std::min(hi, std::max(lo, base - shift));
}
