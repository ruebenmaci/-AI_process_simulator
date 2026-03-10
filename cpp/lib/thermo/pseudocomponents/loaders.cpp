#include "loaders.hpp"
#include "pseudoComponents.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <stdexcept>

// ---- Unit helpers (ported) ----
static inline double MPa_to_Pa(double x) { return x * 1e6; }
static inline double bar_to_Pa(double x) { return x * 1e5; }
static inline double C_to_K(double x) { return x + 273.15; }

struct SourceMeta { std::string PcUnit; std::string TbUnit; };

static const std::unordered_map<std::string, SourceMeta> sourceMeta = {
  {"Western Canadian Select", {"bar", "C"}},
  {"Arab Light", {"bar", "C"}},
  {"Brent", {"bar", "C"}},
  {"Venezuelan Heavy", {"bar", "C"}},
  {"West Texas Intermediate", {"bar", "C"}},
};

// Volume shift placeholder (ported 1:1)
static double estimateVolumeShift(double omega, double SG, double MW) {
  const double w = std::max(-0.1, std::min(std::isfinite(omega) ? omega : 0.0, 1.0));
  const double heaviness = std::max(0.0, (std::isfinite(SG) ? SG : 0.7) - 0.6);
  const double size = std::max(0.0, (std::isfinite(MW) ? MW : 200.0) - 100.0) / 400.0;
  return 0.05 + 0.25*w + 0.2*heaviness + 0.1*size;
}

// Build coarse kij block matrix by TBP cuts (ported)
static std::vector<std::vector<double>>
buildKijMatrix(const std::vector<Component>& components) {
  const int n = static_cast<int>(components.size());
  std::vector<std::vector<double>> kij(n, std::vector<double>(n, 0.0));

  auto idx = [&](double p)->int {
    return std::min(n-1, std::max(0, static_cast<int>(std::floor(p * (n - 1)))));
  };

  const std::vector<std::pair<int,int>> blocks = {
    {0, idx(0.10)},
    {idx(0.10)+1, idx(0.25)},
    {idx(0.25)+1, idx(0.45)},
    {idx(0.45)+1, idx(0.70)},
    {idx(0.70)+1, n-1},
  };

  auto val = [&](int A, int B)->double {
    if (A == B) return 0.0;
    const int d = std::abs(A - B);
    if (d == 1) return 0.015;
    if (d == 2) return 0.02;
    if (d >= 3) return 0.03;
    return 0.0;
  };

  for (int A=0; A<(int)blocks.size(); ++A) {
    for (int B=A; B<(int)blocks.size(); ++B) {
      const double kijAB = val(A,B);
      for (int i=blocks[A].first; i<=blocks[A].second; ++i) {
        if (i < 0 || i >= n) continue;
        for (int j=blocks[B].first; j<=blocks[B].second; ++j) {
          if (j < 0 || j >= n) continue;
          kij[i][j] = kij[j][i] = kijAB;
        }
      }
    }
  }
  return kij;
}

// Normalize one set (ported 1:1)
static std::pair<std::vector<Component>, std::vector<std::vector<double>>>
normalizeSet(const std::vector<Component>& raw, const SourceMeta& meta) {
  const auto toPa = [&](double Pc)->double {
    if (meta.PcUnit == "MPa") return MPa_to_Pa(Pc);
    if (meta.PcUnit == "bar") return bar_to_Pa(Pc);
    return Pc;
  };
  const auto TbConv = [&](double Tb)->double {
    if (meta.TbUnit == "C") return C_to_K(Tb);
    return Tb;
  };

  std::vector<Component> pcs;
  pcs.reserve(raw.size());

  for (size_t i=0;i<raw.size();++i) {
    const auto& c = raw[i];
    Component n;
    n.name = !c.name.empty() ? c.name : ("PC" + std::to_string(i+1));
    n.Tc = c.Tc;           // already K in your files
    n.Pc = toPa(c.Pc);
    n.Tb = TbConv(c.Tb);
    n.MW = c.MW;
    n.omega = c.omega;
    n.SG = c.SG;
    n.delta = estimateVolumeShift(n.omega, n.SG, n.MW);
    pcs.push_back(n);
  }

  // sort by TBP
  std::sort(pcs.begin(), pcs.end(), [](const auto& a, const auto& b){ return a.Tb < b.Tb; });

  // sanity clamps (ported)
  for (auto& c : pcs) {
    c.Tc = std::max(200.0, std::min(1200.0, c.Tc));
    c.Pc = std::max(1e5, std::min(2e8, c.Pc));
    c.omega = std::max(-0.15, std::min(1.2, c.omega));
    c.MW = std::max(12.0, std::min(1500.0, c.MW));
  }

  auto kij = buildKijMatrix(pcs);
  return {pcs, kij};
}

// Registry of raw sets (ported)
static std::vector<Component> RAW(const std::string& name) {
  if (name == "Western Canadian Select") return pseudoComponents_WCS();
  if (name == "Brent") return pseudoComponents_Brent();
  if (name == "West Texas Intermediate") return pseudoComponents_WTI();
  if (name == "Arab Light") return pseudoComponents_ArabLight();
  if (name == "Venezuelan Heavy") return pseudoComponents_VenezHeavy();
  throw std::runtime_error("Unknown crude: " + name);
}

CrudeSet getCrudeSet(const std::string& name) {
  const auto raw = RAW(name);

  auto it = sourceMeta.find(name);
  SourceMeta meta = (it != sourceMeta.end()) ? it->second : SourceMeta{"MPa","C"};

  auto [components, kij] = normalizeSet(raw, meta);

  // optional default feed z
  CrudeSet out;
  out.name = name;
  out.components = std::move(components);
  out.kij = std::move(kij);

  try {
    const auto compMap = crudeCompositions();
    auto itz = compMap.find(name);
    if (itz != compMap.end() && itz->second.size() == out.components.size()) {
      out.hasZDefault = true;
      out.zDefault = itz->second;
    }
  } catch (...) {
    // ignore
  }

  return out;
}

std::vector<std::string> listCrudes() {
  return {
    "Western Canadian Select",
    "Brent",
    "West Texas Intermediate",
    "Arab Light",
    "Venezuelan Heavy",
  };
}
