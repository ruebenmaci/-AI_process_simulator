#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

#include "RunResultsParser.hpp"

namespace {
std::string readAll(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in.is_open()) {
        throw std::runtime_error("Could not open input file: " + path);
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}
}

int main(int argc, char** argv) {
    if (argc < 2 || argc > 3) {
        std::cerr << "Usage: runresults_to_json <input_run_results.txt> [output_baseline.json]\n";
        return 2;
    }

    try {
        const std::string inputPath = argv[1];
        const std::string outputPath = (argc == 3) ? argv[2] : std::string{};

        const ParsedRunResults parsed = parseRunResults(readAll(inputPath));
        const std::string json = parsedRunResultsToJson(parsed, 2);

        if (outputPath.empty()) {
            std::cout << json;
        } else {
            std::ofstream out(outputPath, std::ios::binary);
            if (!out.is_open()) {
                throw std::runtime_error("Could not open output file: " + outputPath);
            }
            out << json;
        }
        return 0;
    } catch (const std::exception& ex) {
        std::cerr << ex.what() << '\n';
        return 1;
    }
}
