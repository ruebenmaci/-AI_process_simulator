#pragma once
#include <vector>
#include <string>
#include <functional>
#include <cmath>
#include <algorithm>
#include <limits>

#include "../cpp/unitops/column/sim/CounterCurrentColumnSimulator.hpp"

// In this project, `Component` is defined in the simulator layer (global namespace).
// Thermo code frequently refers to `thermo::Component`, so keep an alias here to
// prevent signature mismatches across translation units.
using Component = ::Component;

// --- Generic EOS output shape (matches EOSK.js "common shape") ---
struct EOSResult {
	// compressibility roots chosen/returned by EOS
	double ZL = std::numeric_limits<double>::quiet_NaN();
	double ZV = std::numeric_limits<double>::quiet_NaN();

	// fugacity coeff arrays (per component)
	std::vector<double> phiL;   // liquid fugacity coeffs
	std::vector<double> phiV;   // vapor fugacity coeffs

	// departure enthalpy (J/mol)
	double hdepL = 0.0;
	double hdepV = 0.0;

	// optional extras for diagnostics
	bool singlePhase = false;
	std::string phase;          // "L" or "V" if singlePhase
	double Z = std::numeric_limits<double>::quiet_NaN(); // sometimes EOS returns one Z
	double b_mix = std::numeric_limits<double>::quiet_NaN(); // optional

	// convenience: some solvers may set Z only; we keep ZL/ZV too
};

// Optional kij matrix (n×n) flattened row-major, or empty for null.
using KijMatrix = std::vector<double>;

// EOS solver signature (PR / PRSV / SRK)
using EOSSolver = std::function<EOSResult(
	double P, double T,
	const std::vector<double>& x,
	const std::vector<Component>& comps,
	const KijMatrix& kij
)>;

// Small helpers
inline double clamp(double v, double lo, double hi) {
	return std::max(lo, std::min(hi, v));
}
inline bool isFinite(double v) { return std::isfinite(v); }

inline std::vector<double> normalize(const std::vector<double>& z) {
	const int n = (int)z.size();
	if (n <= 0) return {};
	double s = 0.0;
	for (double v : z) s += (isFinite(v) ? v : 0.0);
	if (!isFinite(s) || s <= 0.0) return std::vector<double>(n, 1.0 / n);
	std::vector<double> out(n, 0.0);
	for (int i = 0; i < n; ++i) out[i] = (isFinite(z[i]) ? z[i] / s : 0.0);
	return out;
}
