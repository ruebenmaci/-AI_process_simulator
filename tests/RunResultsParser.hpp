#pragma once

#include <map>
#include <string>
#include <vector>

struct KeyValueSection {
    std::map<std::string, std::string> values;
};

struct TableSection {
    std::vector<std::string> headers;
    std::vector<std::vector<std::string>> rows;
};

struct ParsedRunResults {
    KeyValueSection solveSummary;
    KeyValueSection energyBoundary;
    KeyValueSection massBalance;
    TableSection sideDrawSummary;
    TableSection trayProfile;
    TableSection streamSummary;
    TableSection diagnostics;
};

ParsedRunResults parseRunResults(const std::string& text);
std::string parsedRunResultsToJson(const ParsedRunResults& parsed, int indent = 2);
