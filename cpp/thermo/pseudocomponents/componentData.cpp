#include <numeric>
#include <stdexcept>
#include <unordered_map>
#include <vector>

static std::vector<double> normalize(const std::vector<double>& w) {
  const double s = std::accumulate(w.begin(), w.end(), 0.0);
  if (s == 0.0) throw std::runtime_error("crudeCompositions: zero-sum weights");
  std::vector<double> out(w.size());
  for (size_t i=0;i<w.size();++i) out[i] = w[i] / s;
  return out;
}

static std::vector<double> makeLightCrude(const std::vector<double>& baseWeights) {
  return normalize(baseWeights);
}

std::unordered_map<std::string, std::vector<double>> crudeCompositions() {
  // WCS_30
  const std::vector<double> WCS_30 = {
    0, 0, // C1–C2
    0.01, 0.01, // C3–C4
    0.02, 0.02, // C5–C6
    0.02, 0.02, // C7–C8
    0.03, 0.03, 0.03, 0.03, // C9–C12
    0.04, 0.04, 0.04, 0.04, // C13–C16
    0.05, 0.05, 0.05, 0.05, // C17–C20
    0.05, 0.05, 0.05, 0.05, // C21–C25
    0.05, 0.05, 0.05, 0.05, // C26–C35
    0.04, 0.04, // C36+
  };
  const auto WCS_30_norm = normalize(WCS_30);

  // VenezuelanHeavy_30
  const std::vector<double> VenezuelanHeavy_30 = {
    0, 0, // C1–C2
    0.005, 0.005, // C3–C4
    0.01, 0.01, // C5–C6
    0.015, 0.015, // C7–C8
    0.02, 0.02, 0.02, 0.02, // C9–C12
    0.03, 0.03, 0.03, 0.03, // C13–C16
    0.04, 0.04, 0.04, 0.04, // C17–C20
    0.06, 0.06, 0.06, 0.06, // C21–C25
    0.07, 0.07, 0.07, 0.07, // C26–C29
    0.08, 0.08, // C30+
  };
  const auto VenezuelanHeavy_30_norm = normalize(VenezuelanHeavy_30);

  // Brent_30
  const auto Brent_30 = makeLightCrude({
    0, 0,
    0.005, 0.005,
    0.02, 0.02,
    0.03, 0.03,
    0.04, 0.04, 0.04, 0.04,
    0.05, 0.05, 0.05, 0.05,
    0.06, 0.06, 0.06, 0.06,
    0.05, 0.05, 0.05, 0.05,
    0.04, 0.04, 0.03, 0.03,
    0.02, 0.02,
  });

  // WTI_30
  const auto WTI_30 = makeLightCrude({
    0, 0, 0.01, 0.01, 0.03, 0.03, 0.04, 0.04, 0.05, 0.05,
    0.05, 0.05, 0.06, 0.06, 0.06, 0.06, 0.05, 0.05, 0.05, 0.05,
    0.04, 0.04, 0.03, 0.03, 0.025, 0.025, 0.02, 0.02, 0.01, 0.01
  });

  // ArabLight_30
  const auto ArabLight_30 = makeLightCrude({
    0, 0, 0.01, 0.01, 0.03, 0.03, 0.05, 0.05, 0.06, 0.06,
    0.06, 0.06, 0.07, 0.07, 0.07, 0.07, 0.05, 0.05, 0.05, 0.05,
    0.04, 0.04, 0.03, 0.03, 0.02, 0.02, 0.015, 0.015, 0.005, 0.005
  });

  return {
    {"Western Canadian Select", WCS_30_norm},
    {"Brent", Brent_30},
    {"West Texas Intermediate", WTI_30},
    {"Arab Light", ArabLight_30},
    {"Venezuelan Heavy", VenezuelanHeavy_30_norm},
  };
}
