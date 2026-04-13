#include "RunResultsParser.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <stdexcept>

namespace {

std::string trim(const std::string& s) {
    const auto begin = s.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return "";
    const auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(begin, end - begin + 1);
}

std::vector<std::string> splitCsvLoose(const std::string& line, std::size_t expectedColumns = 0) {
    std::vector<std::string> out;
    std::string current;
    std::size_t commasSeen = 0;

    for (char ch : line) {
        const bool allowSplit = (expectedColumns == 0) || (commasSeen + 1 < expectedColumns);
        if (ch == ',' && allowSplit) {
            out.push_back(trim(current));
            current.clear();
            ++commasSeen;
        } else {
            current.push_back(ch);
        }
    }
    out.push_back(trim(current));
    return out;
}

void parseKeyValueLine(const std::string& line, KeyValueSection& section) {
    const auto parts = splitCsvLoose(line, 2);
    if (parts.size() >= 2) {
        section.values[parts[0]] = parts[1];
    }
}

std::string jsonEscape(const std::string& s) {
    std::ostringstream oss;
    for (unsigned char ch : s) {
        switch (ch) {
        case '\\': oss << "\\\\"; break;
        case '"':  oss << "\\\""; break;
        case '\b': oss << "\\b"; break;
        case '\f': oss << "\\f"; break;
        case '\n': oss << "\\n"; break;
        case '\r': oss << "\\r"; break;
        case '\t': oss << "\\t"; break;
        default:
            if (ch < 0x20) {
                static const char* hex = "0123456789abcdef";
                oss << "\\u00" << hex[(ch >> 4) & 0x0f] << hex[ch & 0x0f];
            } else {
                oss << static_cast<char>(ch);
            }
            break;
        }
    }
    return oss.str();
}

bool isLikelyNumber(const std::string& s) {
    const std::string t = trim(s);
    if (t.empty()) return false;
    if (t == "nan" || t == "NaN" || t == "inf" || t == "-inf" || t == "INF" || t == "-INF") {
        return false;
    }
    char* end = nullptr;
    const auto value = std::strtod(t.c_str(), &end);
    (void)value;
    return end && *end == '\0';
}

void appendIndent(std::ostringstream& oss, int indent, int level) {
    oss << std::string(static_cast<std::size_t>(indent * level), ' ');
}

void appendJsonValue(std::ostringstream& oss, const std::string& value) {
    if (isLikelyNumber(value)) {
        oss << trim(value);
    } else {
        oss << '"' << jsonEscape(value) << '"';
    }
}

void appendKeyValueSectionJson(std::ostringstream& oss, const KeyValueSection& section, int indent, int level) {
    oss << "{\n";
    bool first = true;
    for (const auto& [key, value] : section.values) {
        if (!first) oss << ",\n";
        first = false;
        appendIndent(oss, indent, level + 1);
        oss << '"' << jsonEscape(key) << "\": ";
        appendJsonValue(oss, value);
    }
    oss << '\n';
    appendIndent(oss, indent, level);
    oss << '}';
}

void appendTableSectionJson(std::ostringstream& oss, const TableSection& section, int indent, int level) {
    oss << "[\n";
    for (std::size_t rowIdx = 0; rowIdx < section.rows.size(); ++rowIdx) {
        appendIndent(oss, indent, level + 1);
        oss << '{';
        const auto& row = section.rows[rowIdx];
        for (std::size_t i = 0; i < section.headers.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << '"' << jsonEscape(section.headers[i]) << "\": ";
            const std::string value = (i < row.size()) ? row[i] : std::string{};
            appendJsonValue(oss, value);
        }
        oss << '}';
        if (rowIdx + 1 < section.rows.size()) oss << ',';
        oss << '\n';
    }
    appendIndent(oss, indent, level);
    oss << ']';
}

} // namespace

ParsedRunResults parseRunResults(const std::string& text) {
    ParsedRunResults result;

    enum class Section {
        None,
        SolveSummary,
        EnergyBoundary,
        MassBalance,
        SideDrawSummary,
        TrayProfile,
        StreamSummary,
        Diagnostics
    };

    Section current = Section::None;
    TableSection* currentTable = nullptr;

    std::istringstream iss(text);
    std::string line;
    while (std::getline(iss, line)) {
        line = trim(line);
        if (line.empty()) {
            currentTable = nullptr;
            continue;
        }

        if (line == "Solve Summary") {
            current = Section::SolveSummary;
            currentTable = nullptr;
            continue;
        }
        if (line == "Energy / Boundary Summary") {
            current = Section::EnergyBoundary;
            currentTable = nullptr;
            continue;
        }
        if (line == "Mass Balance Summary") {
            current = Section::MassBalance;
            currentTable = nullptr;
            continue;
        }
        if (line == "Side Draw Summary") {
            current = Section::SideDrawSummary;
            currentTable = &result.sideDrawSummary;
            continue;
        }
        if (line == "Tray Profile") {
            current = Section::TrayProfile;
            currentTable = &result.trayProfile;
            continue;
        }
        if (line == "Stream Summary") {
            current = Section::StreamSummary;
            currentTable = &result.streamSummary;
            continue;
        }
        if (line == "Diagnostics") {
            current = Section::Diagnostics;
            currentTable = &result.diagnostics;
            continue;
        }

        switch (current) {
        case Section::SolveSummary:
            if (line != "Key,Value") parseKeyValueLine(line, result.solveSummary);
            break;
        case Section::EnergyBoundary:
            if (line != "Key,Value") parseKeyValueLine(line, result.energyBoundary);
            break;
        case Section::MassBalance:
            if (line != "Key,Value") parseKeyValueLine(line, result.massBalance);
            break;
        case Section::SideDrawSummary:
        case Section::TrayProfile:
        case Section::StreamSummary:
        case Section::Diagnostics:
            if (!currentTable) break;
            if (currentTable->headers.empty()) {
                currentTable->headers = splitCsvLoose(line);
            } else {
                currentTable->rows.push_back(splitCsvLoose(line, currentTable->headers.size()));
            }
            break;
        case Section::None:
            break;
        }
    }

    return result;
}

std::string parsedRunResultsToJson(const ParsedRunResults& parsed, int indent) {
    std::ostringstream oss;
    oss << "{\n";

    appendIndent(oss, indent, 1);
    oss << "\"solveSummary\": ";
    appendKeyValueSectionJson(oss, parsed.solveSummary, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"energyBoundary\": ";
    appendKeyValueSectionJson(oss, parsed.energyBoundary, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"massBalance\": ";
    appendKeyValueSectionJson(oss, parsed.massBalance, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"sideDrawSummary\": ";
    appendTableSectionJson(oss, parsed.sideDrawSummary, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"trayProfile\": ";
    appendTableSectionJson(oss, parsed.trayProfile, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"streamSummary\": ";
    appendTableSectionJson(oss, parsed.streamSummary, indent, 1);
    oss << ",\n";

    appendIndent(oss, indent, 1);
    oss << "\"diagnostics\": ";
    appendTableSectionJson(oss, parsed.diagnostics, indent, 1);
    oss << '\n';

    oss << "}\n";
    return oss.str();
}
