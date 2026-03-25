#pragma once
#include <string>
#include <unordered_map>
#include <vector>

constexpr double R = 8.314462618;

// Port of componentData.js (crudeCompositions)
std::unordered_map<std::string, std::vector<double>> crudeCompositions();

struct Component {
	std::string name;     // e.g. "C5"
	double Tb = 0.0;     // normal boiling point (K) (optional)
	double MW = 0.0;     // kg/kmol
	double Tc = 0.0;     // K
	double Pc = 0.0;     // kPa or Pa (must be consistent with thermo lib)
	double omega = 0.0;  // acentric factor
	double SG = 0.0;     // specific gravity (optional)
	double delta = 0.0;  // volume shift factor (dimensionless) (optional)
};

inline const std::vector<Component>& emptyComponents() {
   static const std::vector<Component> empty;
   return empty;
}