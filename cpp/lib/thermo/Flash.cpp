#include <iostream>
#include <sstream>
#include <algorithm>
#include <numeric>

#include "Flash.hpp"

#include <functional>

// --- RR diagnostics state (module-local) ---
struct RRDiagState {
  std::unordered_map<std::string, std::string> lastKey; // uses a single "global slot" in JS; here just store last full key
};
static RRDiagState g_rrState;

static inline bool isFinite(double x) { return std::isfinite(x); }

static std::pair<double,double> kStats(const std::vector<double>& K) {
  double kmin = std::numeric_limits<double>::infinity();
  double kmax = -std::numeric_limits<double>::infinity();
  for (double k : K) {
    if (isFinite(k)) {
      kmin = std::min(kmin, k);
      kmax = std::max(kmax, k);
    }
  }
  return {kmin, kmax};
}

static void emitRR(const RRDiag* diag,
                   const std::string& reason,
                   double chosenV,
                   double f0, double f1, double f0n, double f1n,
                   double sumz, double SzK, double SzOverK,
                   const std::vector<double>& K,
                   const std::function<void(const std::string&)>& log)
{
  if (!diag || !diag->enable)
     return;

  const int tray = diag->tray;
  const double T = diag->T;
  const double P = diag->P;

  auto [kmin, kmax] = kStats(K);

  auto fmtT = [&](double v){ std::ostringstream os; if (isFinite(v)) { os.setf(std::ios::fixed); os.precision(2); os<<v; } else os<<"?"; return os.str(); };
  auto fmtP = [&](double v){ std::ostringstream os; if (isFinite(v)) { os.setf(std::ios::fixed); os.precision(0); os<<v; } else os<<"?"; return os.str(); };
  auto fmte = [&](double v){ std::ostringstream os; if (isFinite(v)) { os.setf(std::ios::scientific); os.precision(3); os<<v; } else os<<"?"; return os.str(); };
  auto fmte2 = [&](double v){ std::ostringstream os; if (isFinite(v)) { os.setf(std::ios::scientific); os.precision(2); os<<v; } else os<<"?"; return os.str(); };

  const std::string tKey = fmtT(T);
  const std::string pKey = fmtP(P);
  const std::string kminKey = isFinite(kmin) ? fmte2(kmin) : std::string("?");
  const std::string kmaxKey = isFinite(kmax) ? fmte2(kmax) : std::string("?");

  const std::string key = std::to_string(tray) + "|" + reason + "|" + tKey + "|" + pKey + "|" + kminKey + "|" + kmaxKey;
  const std::string& prev = g_rrState.lastKey["_global"];
  if (!diag->force && prev == key) return;
  g_rrState.lastKey["_global"] = key;

  std::ostringstream osV; if (isFinite(chosenV)) { osV.setf(std::ios::fixed); osV.precision(3); osV<<chosenV; } else osV<<"?";

  if (log) {
     std::ostringstream os;
     os.setf(std::ios::fixed); os.precision(6);
     os << "[RRDIAG] tray=" << tray + 1
        << " T=" << tKey
        << " P=" << pKey
        << " f0=" << fmte(f0)
        << " f1=" << fmte(f1)
        << " sumz=" << fmte(sumz)
        << " SzK=" << fmte(SzK)
        << " SzOverK=" << fmte(SzOverK)
        << " f0n=" << fmte(f0n)
        << " f1n=" << fmte(f1n)
        << " Kmin=" << kminKey
        << " Kmax=" << kmaxKey
        << " chosenV=" << osV.str()
        << " reason=" << reason;
     log(os.str());
  }
}

RRResult rachfordRice(const std::vector<double>& z,
                      const std::vector<double>& K,
                      const RRDiag* diag,
                      const std::function<void(const std::string&)>& log) {
  RRResult out;
  if (z.empty() || K.empty() || z.size() != K.size()) {
    out.V = 0.5;
    out.status = "fail";
    out.reason = "BAD_INPUT";
    return out;
  }

  const auto f = [&](double V)->double {
    double s = 0.0;
    for (size_t i=0;i<z.size();++i) {
      const double denom = 1.0 + V*(K[i]-1.0);
      if (std::fabs(denom) < 1e-12)
         return std::numeric_limits<double>::quiet_NaN();
      s += (z[i]*(K[i]-1.0))/denom;
    }
    return s;
  };

  const double zsum_raw = std::accumulate(z.begin(), z.end(), 0.0);
  const double zsum = (isFinite(zsum_raw) && zsum_raw != 0.0) ? zsum_raw : 1.0;

  std::vector<double> zn(z.size());
  for (size_t i=0;i<z.size();++i) zn[i] = z[i]/zsum;

  double SzK = 0.0, SzOverK = 0.0;
  for (size_t i = 0; i < zn.size(); ++i) {
    SzK += zn[i] * K[i];
    SzOverK += zn[i]/std::max(1e-30, K[i]);
  }
  const double f0n = SzK - 1.0;
  const double f1n = 1.0 - SzOverK;

  double f0 = f(0.0);
  double f1 = f(1.0);
  const double f0_init = f0;
  const double f1_init = f1;

  out.f0 = f0_init;
  out.f1 = f1_init;
  out.f0n = f0n;
  out.f1n = f1n;

  if (!isFinite(f0) || !isFinite(f1)) {
    double chosenV = 0.5;
    if (f0n > 0 && f1n > 0) chosenV = 1.0;
    else if (f0n < 0 && f1n < 0) chosenV = 0.0;
    emitRR(diag, "NONFINITE_F0F1", chosenV, f0, f1, f0n, f1n, zsum, SzK, SzOverK, K, log);
    out.V = chosenV;
    out.status = "fail";
    out.reason = "NONFINITE_F0F1";
    return out;
  }

  if (f0 > 0 && f1 > 0) {
    emitRR(diag, "SINGLEPHASE_V", 1.0, f0, f1, f0n, f1n, zsum, SzK, SzOverK, K, log);
    out.V = 1.0;
    out.status = "singlePhase";
    out.phase = "V";
    out.reason = "F0F1_POS";
    return out;
  }

  if (f0 < 0 && f1 < 0) {
    emitRR(diag, "SINGLEPHASE_L", 0.0, f0, f1, f0n, f1n, zsum, SzK, SzOverK, K, log);
    out.V = 0.0;
    out.status = "singlePhase";
    out.phase = "L";
    out.reason = "F0F1_NEG";
    return out;
  }

  double lo = 0.0, hi = 1.0;
  double flo = f0, fhi = f1;

  for (int it=0; it<120; ++it) {
    const double mid = 0.5*(lo+hi);
    const double fm = f(mid);
    if (!isFinite(fm)) {
      const double chosenV = (flo > 0) ? 1.0 : 0.0;
      emitRR(diag, "NONFINITE_FM", chosenV, flo, fhi, f0n, f1n, zsum, SzK, SzOverK, K, log);
      out.V = chosenV;
      out.status = "fail";
      out.reason = "NONFINITE_FM";
      out.iters = it;
      return out;
    }

    if (std::fabs(fm) < 1e-10) {
      emitRR(diag, "TWOPHASE_CONVERGED", mid, f0_init, f1_init, f0n, f1n, zsum, SzK, SzOverK, K, log);
      out.V = mid;
      out.status = "twoPhase";
      out.reason = "CONVERGED";
      out.iters = it+1;
      return out;
    }

    if (fm * flo < 0) {
      hi = mid;
      fhi = fm;
    } else {
      lo = mid;
      flo = fm;
    }
  }

  const double V = 0.5*(lo+hi);
  emitRR(diag, "TWOPHASE_ITER_MAX", V, f0_init, f1_init, f0n, f1n, zsum, SzK, SzOverK, K, log);
  out.V = V;
  out.status = "twoPhase";
  out.reason = "ITER_MAX";
  out.iters = 120;
  return out;
}

std::pair<std::vector<double>, std::vector<double>>
phaseCompositions(const std::vector<double>& z,
                  const std::vector<double>& K,
                  double V) {
  const double eps = 1e-12;
  std::vector<double> x(z.size(), 0.0);
  std::vector<double> y(z.size(), 0.0);

  for (size_t i=0;i<z.size();++i) {
    const double d = 1.0 + V*(K[i]-1.0);
    x[i] = (std::fabs(d) > eps) ? (z[i]/d) : 0.0;
  }
  for (size_t i=0;i<z.size();++i) y[i] = K[i]*x[i];

  double sx = std::accumulate(x.begin(), x.end(), 0.0);
  double sy = std::accumulate(y.begin(), y.end(), 0.0);
  if (sx == 0.0) sx = 1.0;
  if (sy == 0.0) sy = 1.0;

  for (double& v : x) v /= sx;
  for (double& v : y) v /= sy;
  return {x,y};
}

std::vector<double>
forceTwoPhaseK(const std::vector<double>& z,
               const std::vector<double>& K) {
  // Be defensive: higher-level callers may ask us to "force" two-phase
  // even when the EOS decided to short-circuit (single-phase) and did not
  // provide a usable K-vector. In that case, synthesize a reasonable K set
  // (log-spread around 1) so RR has a root.
  if (z.empty())
    throw std::runtime_error("forceTwoPhaseK: empty z");

  std::vector<double> Kuse = K;
  if (Kuse.empty() || Kuse.size() != z.size()) {
    const double N = static_cast<double>(z.size());
    const double mid = (N - 1.0) / 2.0;
    Kuse.assign(z.size(), 1.0);
    for (size_t i = 0; i < z.size(); ++i) {
      // +/- ~1 order of magnitude across the components
      const double t = (static_cast<double>(i) - mid) / std::max(1.0, mid);
      Kuse[i] = std::exp(2.0 * t); // exp(-2) .. exp(2)
    }
  }

  const double sum = std::accumulate(z.begin(), z.end(), 0.0);
  const double s = (sum != 0.0) ? sum : 1.0;

  std::vector<double> Zi(z.size());
  for (size_t i=0;i<z.size();++i) Zi[i] = z[i]/s;

  double lnKg = 0.0;
  for (size_t i=0;i<Kuse.size();++i)
    lnKg += Zi[i] * std::log(std::max(1e-12, std::min(1e12, Kuse[i])));

  const double g = std::exp(lnKg);
  std::vector<double> Kc(Kuse.size());
  for (size_t i=0;i<Kuse.size();++i) Kc[i] = Kuse[i]/std::max(1e-12, g);

  auto all_ge_1 = std::all_of(Kc.begin(), Kc.end(), [](double k){ return k >= 1.0; });
  auto all_le_1 = std::all_of(Kc.begin(), Kc.end(), [](double k){ return k <= 1.0; });

  if (all_ge_1 || all_le_1) {
    const double N = static_cast<double>(Kc.size());
    const double mid = (N-1.0)/2.0;
    const double beta = 0.12;
    for (size_t i=0;i<Kc.size();++i) {
      const double tilt = std::exp((beta * (static_cast<double>(i) - mid)) / std::max(1.0, mid));
      Kc[i] *= tilt;
    }
    double lnKg2 = 0.0;
    for (size_t i=0;i<Kc.size();++i)
      lnKg2 += Zi[i] * std::log(std::max(1e-12, Kc[i]));
    const double g2 = std::exp(lnKg2);
    for (size_t i=0;i<Kc.size();++i) Kc[i] = Kc[i]/std::max(1e-12, g2);
  }

  for (double& k : Kc) k = std::min(std::max(k, 1e-3), 1e3);
  return Kc;
}
