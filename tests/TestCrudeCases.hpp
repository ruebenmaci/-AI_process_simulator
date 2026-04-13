#pragma once

#include <algorithm>
#include <stdexcept>
#include <string>
#include <vector>

#include "../cpp/unitops/column/sim/ColumnSolver.hpp"
#include "../cpp/thermo/pseudocomponents/FluidDefinition.hpp"

struct CrudeCaseDef {
    std::string name;
    std::string baselineFileName;
};

struct RegressionCrudeSpec {
    std::string name;
    std::string baselineFileName;
    double feedRateKgph;
    int feedTray;
    double feedTempK;
    double topPressurePa;
    double dpPerTrayPa;
    std::string condenserType;
    std::string reboilerType;
    std::string condenserSpec;
    std::string reboilerSpec;
    double refluxRatio;
    double boilupRatio;
    double qcKW;
    double qrKW;
    double topTsetK;
    double bottomTsetK;

    // side-draw targets as feed percent, keyed by tray index (0-based)
    std::vector<std::pair<int, double>> drawFeedPctByTray0;
};

inline const RegressionCrudeSpec& regressionCrudeSpec(const std::string& crudeName) {
    static const std::vector<RegressionCrudeSpec> specs = {
        {
            "Brent",
            "brent_run_results.txt",
            100000.0, 3, 628.15,
            150000.0, 200.0,
            "total", "partial",
            "temperature", "duty",
            2.0, 0.06,
            -6000.0, 6000.0,
            398.15, 618.15,
            {
                {29, 6.8},   // Light Naphtha, tray 30
                {26, 14.4},  // Heavy Naphtha, tray 27
                {20, 13.3},  // Kerosene, tray 21
                {14, 13.05}, // LGO, tray 15
                {7, 13.05},  // HGO, tray 8
            }
        },
        {
            "West Texas Intermediate",
            "wti_run_results.txt",
            100000.0, 3, 623.15,
            150000.0, 200.0,
            "total", "partial",
            "temperature", "duty",
            2.0, 0.05,
            -5500.0, 5500.0,
            398.15, 615.15,
            {
                {29, 5.7},   // Light Naphtha
                {26, 24.1},  // Heavy Naphtha
                {20, 14.9},  // Kerosene
                {14, 11.75}, // LGO
                {7, 11.75},  // HGO
            }
        },
        {
            "Western Canadian Select",
            "wcs_run_results.txt",
            100000.0, 3, 628.15,
            150000.0, 200.0,
            "total", "partial",
            "temperature", "duty",
            2.0, 0.06,
            -6000.0, 6000.0,
            398.15, 618.15,
            {
                {29, 6.8},
                {26, 14.4},
                {20, 13.3},
                {14, 13.05},
                {7, 13.05},
            }
        },
        {
            "Arab Light",
            "arab_light_run_results.txt",
            100000.0, 3, 628.15,
            150000.0, 200.0,
            "total", "partial",
            "temperature", "duty",
            2.0, 0.06,
            -6200.0, 6200.0,
            398.15, 618.15,
            {
                {29, 6.6},
                {26, 13.9},
                {20, 12.6},
                {14, 13.15},
                {7, 13.15},
            }
        },
        {
            "Venezuelan Heavy",
            "venezuelan_heavy_run_results.txt",
            100000.0, 3, 638.15,
            150000.0, 200.0,
            "total", "partial",
            "temperature", "duty",
            2.0, 0.07,
            -6500.0, 6500.0,
            403.15, 623.15,
            {
                {29, 2.4},
                {26, 12.0},
                {20, 12.0},
                {14, 5.95},
                {7, 5.95},
            }
        }
    };

    auto it = std::find_if(specs.begin(), specs.end(), [&](const RegressionCrudeSpec& s) {
        return s.name == crudeName;
    });
    if (it == specs.end()) {
        throw std::runtime_error("Unknown crude regression case: " + crudeName);
    }
    return *it;
}

inline std::vector<CrudeCaseDef> allCrudeRegressionCases() {
    return {
        {"Brent", "brent_run_results.txt"},
        {"West Texas Intermediate", "wti_run_results.txt"},
        {"Western Canadian Select", "wcs_run_results.txt"},
        {"Arab Light", "arab_light_run_results.txt"},
        {"Venezuelan Heavy", "venezuelan_heavy_run_results.txt"}
    };
}

inline SolverInputs makeCrudeRegressionInputs(const std::string& crudeName) {
    const auto& spec = regressionCrudeSpec(crudeName);
    const auto fluid = getFluidDefinition(crudeName);
    const auto& nameMap = defaultDrawNamesByTray32();

    SolverInputs in{};
    in.fluidName = crudeName;
    in.fluidThermo = fluid.thermo;
    in.feedComposition = fluid.thermo.hasZDefault ? fluid.thermo.zDefault : std::vector<double>{};

    in.trays = 32;
    in.feedRateKgph = spec.feedRateKgph;
    in.feedTray = spec.feedTray;
    in.feedTempK = spec.feedTempK;

    in.topPressurePa = spec.topPressurePa;
    in.dpPerTrayPa = spec.dpPerTrayPa;

    in.condenserType = spec.condenserType;
    in.reboilerType = spec.reboilerType;
    in.condenserSpec = spec.condenserSpec;
    in.reboilerSpec = spec.reboilerSpec;
    in.refluxRatio = spec.refluxRatio;
    in.boilupRatio = spec.boilupRatio;
    in.qcKW = spec.qcKW;
    in.qrKW = spec.qrKW;
    in.topTsetK = spec.topTsetK;
    in.bottomTsetK = spec.bottomTsetK;

    in.eosMode = "auto";
    in.eosManual = "PRSV";

    // Preserve the same Murphree defaults your main column tests have been using.
    // If you later want to baseline efficiencies explicitly, this is the place to do it.
    in.etaVTop = 1.0;
    in.etaVMid = 1.0;
    in.etaVBot = 1.0;
    in.enableEtaL = false;
    in.etaLTop = 1.0;
    in.etaLMid = 1.0;
    in.etaLBot = 1.0;

    in.suppressLogs = true;

    std::vector<std::pair<int, double>> rows = spec.drawFeedPctByTray0;
    std::sort(rows.begin(), rows.end(), [](const auto& a, const auto& b) {
        return a.first > b.first;
    });

    for (const auto& [trayIndex0, feedPct] : rows) {
        const int tray1 = trayIndex0 + 1;
        if (tray1 <= 1 || tray1 >= in.trays) {
            continue;
        }
        SolverDrawSpec ds;
        ds.trayIndex0 = trayIndex0;
        ds.phase = "L";
        ds.basis = "feedPct";
        ds.value = feedPct;
        auto it = nameMap.find(tray1);
        ds.name = (it != nameMap.end()) ? it->second : ("Draw [Tray " + std::to_string(tray1) + "]");
        in.drawSpecs.push_back(ds);
        in.drawLabelsByTray1[tray1] = ds.name;
    }

    return in;
}
