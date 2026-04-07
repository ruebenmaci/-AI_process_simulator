#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#include "ThermoRoundTripCommon.hpp"

int main(int argc, char** argv)
{
    std::string outPath = "thermo_roundtrip.csv";
    if (argc > 1 && argv[1] && std::string(argv[1]).size() > 0) {
        outPath = argv[1];
    }

    const std::vector<std::string> fluids = {"Brent", "Western Canadian Select"};
    const std::vector<double> pressures = {101325.0, 150000.0, 300000.0};
    const std::vector<double> temperatures = {380.0, 500.0, 628.15, 725.0, 850.0};

    std::ofstream out(outPath);
    if (!out) {
        std::cerr << "Failed to open output file: " << outPath << "\n";
        return 1;
    }

    out << std::setprecision(15);
    out << "fluid,P_Pa,T_inputK,"
           "tpFinite,tpV,tpH,tpS,"
           "phFinite,phT,phV,phH,phS,phStatus,dT_PH,dV_PH,dH_PH,dS_PH,"
           "psFinite,psT,psV,psH,psS,psStatus,dT_PS,dV_PS,dH_PS,dS_PS,"
           "tsFinite,tsP,tsV,tsH,tsS,tsStatus,dP_TS,dV_TS,dH_TS,dS_TS\n";

    for (const auto& fluid : fluids) {
        for (double P : pressures) {
            for (double T : temperatures) {
                const auto row = runThermoRoundTrip(fluid, P, T);
                out << row.fluid << ','
                    << row.P_Pa << ','
                    << row.T_inputK << ','
                    << (row.tpFinite ? 1 : 0) << ','
                    << row.tpV << ','
                    << row.tpH << ','
                    << row.tpS << ','
                    << (row.phFinite ? 1 : 0) << ','
                    << row.phT << ','
                    << row.phV << ','
                    << row.phH << ','
                    << row.phS << ','
                    << '"' << row.phStatus << '"' << ','
                    << row.dT_PH << ','
                    << row.dV_PH << ','
                    << row.dH_PH << ','
                    << row.dS_PH << ','
                    << (row.psFinite ? 1 : 0) << ','
                    << row.psT << ','
                    << row.psV << ','
                    << row.psH << ','
                    << row.psS << ','
                    << '"' << row.psStatus << '"' << ','
                    << row.dT_PS << ','
                    << row.dV_PS << ','
                    << row.dH_PS << ','
                    << row.dS_PS << ','
                    << (row.tsFinite ? 1 : 0) << ','
                    << row.tsP << ','
                    << row.tsV << ','
                    << row.tsH << ','
                    << row.tsS << ','
                    << '"' << row.tsStatus << '"' << ','
                    << row.dP_TS << ','
                    << row.dV_TS << ','
                    << row.dH_TS << ','
                    << row.dS_TS << '\n';
            }
        }
    }

    std::cout << "Wrote thermo regression CSV to " << outPath << "\n";
    return 0;
}
