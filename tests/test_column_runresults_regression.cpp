#include <catch2/catch_all.hpp>

#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "RunResultsParser.hpp"
#include "../cpp/unitops/column/sim/ColumnSolver.hpp"

namespace {

std::string readAllText(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    REQUIRE(in.is_open());
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

std::optional<double> tryParseNumber(const std::string& s) {
    const std::string t = [&]() {
        const auto b = s.find_first_not_of(" \t\r\n");
        if (b == std::string::npos) return std::string{};
        const auto e = s.find_last_not_of(" \t\r\n");
        return s.substr(b, e - b + 1);
    }();
    if (t.empty()) return std::nullopt;
    if (t == "nan" || t == "NaN" || t == "inf" || t == "-inf" || t == "INF" || t == "-INF") {
        return std::nullopt;
    }
    char* end = nullptr;
    double value = std::strtod(t.c_str(), &end);
    if (end && *end == '\0') return value;
    return std::nullopt;
}

// ---- Minimal JSON parser for the exported solver_inputs schema ----

struct JValue {
    enum class Type { Null, Bool, Number, String, Array, Object };
    using Array = std::vector<JValue>;
    using Object = std::map<std::string, JValue>;

    Type type = Type::Null;
    bool b = false;
    double n = 0.0;
    std::string s;
    Array a;
    Object o;

    bool isNull() const { return type == Type::Null; }
    bool isBool() const { return type == Type::Bool; }
    bool isNumber() const { return type == Type::Number; }
    bool isString() const { return type == Type::String; }
    bool isArray() const { return type == Type::Array; }
    bool isObject() const { return type == Type::Object; }

    const JValue* get(const std::string& key) const {
        if (!isObject()) return nullptr;
        auto it = o.find(key);
        return (it == o.end()) ? nullptr : &it->second;
    }
};

class JsonParser {
public:
    explicit JsonParser(const std::string& text) : t_(text) {}

    JValue parse() {
        skipWs();
        JValue v = parseValue();
        skipWs();
        if (pos_ != t_.size()) throw std::runtime_error("Trailing characters in JSON");
        return v;
    }

private:
    const std::string& t_;
    size_t pos_ = 0;

    void skipWs() {
        while (pos_ < t_.size() && std::isspace(static_cast<unsigned char>(t_[pos_]))) ++pos_;
    }

    char peek() const {
        if (pos_ >= t_.size()) throw std::runtime_error("Unexpected end of JSON");
        return t_[pos_];
    }

    char get() {
        if (pos_ >= t_.size()) throw std::runtime_error("Unexpected end of JSON");
        return t_[pos_++];
    }

    bool consume(char ch) {
        skipWs();
        if (pos_ < t_.size() && t_[pos_] == ch) {
            ++pos_;
            return true;
        }
        return false;
    }

    void expect(char ch) {
        skipWs();
        if (get() != ch) throw std::runtime_error(std::string("Expected '") + ch + "'");
    }

    JValue parseValue() {
        skipWs();
        char ch = peek();
        if (ch == '{') return parseObject();
        if (ch == '[') return parseArray();
        if (ch == '"') return parseString();
        if (ch == 't' || ch == 'f') return parseBool();
        if (ch == 'n') return parseNull();
        return parseNumber();
    }

    JValue parseObject() {
        JValue v; v.type = JValue::Type::Object;
        expect('{');
        skipWs();
        if (consume('}')) return v;
        while (true) {
            JValue key = parseString();
            expect(':');
            JValue val = parseValue();
            v.o[key.s] = std::move(val);
            skipWs();
            if (consume('}')) break;
            expect(',');
        }
        return v;
    }

    JValue parseArray() {
        JValue v; v.type = JValue::Type::Array;
        expect('[');
        skipWs();
        if (consume(']')) return v;
        while (true) {
            v.a.push_back(parseValue());
            skipWs();
            if (consume(']')) break;
            expect(',');
        }
        return v;
    }

    JValue parseString() {
        JValue v; v.type = JValue::Type::String;
        expect('"');
        std::ostringstream os;
        while (true) {
            char ch = get();
            if (ch == '"') break;
            if (ch == '\\') {
                char esc = get();
                switch (esc) {
                    case '"': os << '"'; break;
                    case '\\': os << '\\'; break;
                    case '/': os << '/'; break;
                    case 'b': os << '\b'; break;
                    case 'f': os << '\f'; break;
                    case 'n': os << '\n'; break;
                    case 'r': os << '\r'; break;
                    case 't': os << '\t'; break;
                    case 'u': {
                        // Keep it simple: consume 4 hex digits and ignore Unicode conversion.
                        for (int i = 0; i < 4; ++i) get();
                        break;
                    }
                    default:
                        throw std::runtime_error("Invalid escape in JSON string");
                }
            } else {
                os << ch;
            }
        }
        v.s = os.str();
        return v;
    }

    JValue parseBool() {
        JValue v; v.type = JValue::Type::Bool;
        if (t_.compare(pos_, 4, "true") == 0) {
            pos_ += 4; v.b = true; return v;
        }
        if (t_.compare(pos_, 5, "false") == 0) {
            pos_ += 5; v.b = false; return v;
        }
        throw std::runtime_error("Invalid boolean in JSON");
    }

    JValue parseNull() {
        if (t_.compare(pos_, 4, "null") != 0) throw std::runtime_error("Invalid null in JSON");
        pos_ += 4;
        return JValue{};
    }

    JValue parseNumber() {
        JValue v; v.type = JValue::Type::Number;
        size_t start = pos_;
        if (t_[pos_] == '-') ++pos_;
        while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) ++pos_;
        if (pos_ < t_.size() && t_[pos_] == '.') {
            ++pos_;
            while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) ++pos_;
        }
        if (pos_ < t_.size() && (t_[pos_] == 'e' || t_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < t_.size() && (t_[pos_] == '+' || t_[pos_] == '-')) ++pos_;
            while (pos_ < t_.size() && std::isdigit(static_cast<unsigned char>(t_[pos_]))) ++pos_;
        }
        v.n = std::strtod(t_.substr(start, pos_ - start).c_str(), nullptr);
        return v;
    }
};

double asDouble(const JValue* v, double def = 0.0) {
    return (v && v->isNumber()) ? v->n : def;
}
bool asBool(const JValue* v, bool def = false) {
    return (v && v->isBool()) ? v->b : def;
}
std::string asString(const JValue* v, const std::string& def = {}) {
    return (v && v->isString()) ? v->s : def;
}

std::vector<double> asDoubleArray(const JValue* v) {
    std::vector<double> out;
    if (!v || !v->isArray()) return out;
    for (const auto& x : v->a) out.push_back(x.isNumber() ? x.n : 0.0);
    return out;
}

std::vector<std::vector<double>> asDoubleMatrix(const JValue* v) {
    std::vector<std::vector<double>> out;
    if (!v || !v->isArray()) return out;
    for (const auto& row : v->a) {
        if (!row.isArray()) { out.push_back({}); continue; }
        std::vector<double> vals;
        for (const auto& cell : row.a) vals.push_back(cell.isNumber() ? cell.n : 0.0);
        out.push_back(std::move(vals));
    }
    return out;
}

SolverInputs loadSolverInputsFromJsonText(const std::string& text) {
    const JValue root = JsonParser(text).parse();
    if (!root.isObject()) throw std::runtime_error("solver_inputs root is not an object");

    SolverInputs in{};
    in.fluidName = asString(root.get("fluidName"));
    in.trays = static_cast<int>(asDouble(root.get("trays"), 32.0));
    in.feedRateKgph = asDouble(root.get("feedRateKgph"), 100000.0);
    in.feedTray = static_cast<int>(asDouble(root.get("feedTray"), 4.0));
    in.feedTempK = asDouble(root.get("feedTempK"), 640.0);
    in.topPressurePa = asDouble(root.get("topPressurePa"), 150000.0);
    in.dpPerTrayPa = asDouble(root.get("dpPerTrayPa"), 200.0);

    if (const JValue* tc = root.get("thermoConfig")) {
        in.thermoConfig.thermoMethodId = asString(tc->get("thermoMethodId"));
        in.thermoConfig.displayName = asString(tc->get("displayName"));
        in.thermoConfig.eosName = asString(tc->get("eosName"));
        in.thermoConfig.phaseModelFamily = asString(tc->get("phaseModelFamily"));
        in.thermoConfig.supportsEnthalpy = asBool(tc->get("supportsEnthalpy"), true);
        in.thermoConfig.supportsEntropy = asBool(tc->get("supportsEntropy"), true);
        in.thermoConfig.supportsTwoPhase = asBool(tc->get("supportsTwoPhase"), true);
        if (const JValue* sf = tc->get("supportFlags"); sf && sf->isArray()) {
            for (const auto& x : sf->a) if (x.isString()) in.thermoConfig.supportFlags.push_back(x.s);
        }
    }

    in.eosMode = asString(root.get("eosMode"), "auto");
    in.eosManual = asString(root.get("eosManual"), "PRSV");
    in.condenserType = asString(root.get("condenserType"), "total");
    in.reboilerType = asString(root.get("reboilerType"), "partial");
    in.condenserSpec = asString(root.get("condenserSpec"), "Temperature");
    in.reboilerSpec = asString(root.get("reboilerSpec"), "Duty");
    in.refluxRatio = asDouble(root.get("refluxRatio"));
    in.boilupRatio = asDouble(root.get("boilupRatio"));
    in.qcKW = asDouble(root.get("qcKW"));
    in.qrKW = asDouble(root.get("qrKW"));
    in.topTsetK = asDouble(root.get("topTsetK"));
    in.bottomTsetK = asDouble(root.get("bottomTsetK"));

    if (const JValue* m = root.get("murphree")) {
        in.etaVTop = asDouble(m->get("etaVTop"), 1.0);
        in.etaVMid = asDouble(m->get("etaVMid"), 1.0);
        in.etaVBot = asDouble(m->get("etaVBot"), 1.0);
        in.enableEtaL = asBool(m->get("enableEtaL"), false);
        in.etaLTop = asDouble(m->get("etaLTop"), 1.0);
        in.etaLMid = asDouble(m->get("etaLMid"), 1.0);
        in.etaLBot = asDouble(m->get("etaLBot"), 1.0);
    }

    in.feedComposition = asDoubleArray(root.get("feedComposition"));

    if (const JValue* draws = root.get("drawSpecs"); draws && draws->isArray()) {
        for (const auto& dv : draws->a) {
            if (!dv.isObject()) continue;
            SolverDrawSpec ds;
            ds.trayIndex0 = static_cast<int>(asDouble(dv.get("trayIndex0"), -1));
            ds.name = asString(dv.get("name"));
            ds.basis = asString(dv.get("basis"), "feedPct");
            ds.phase = asString(dv.get("phase"), "L");
            ds.value = asDouble(dv.get("value"));
            in.drawSpecs.push_back(std::move(ds));
        }
    }

    if (const JValue* labels = root.get("drawLabelsByTray1"); labels && labels->isObject()) {
        for (const auto& [k, v] : labels->o) {
            try {
                in.drawLabelsByTray1[std::stoi(k)] = v.isString() ? v.s : std::string{};
            } catch (...) {}
        }
    }

    if (const JValue* ft = root.get("fluidThermo")) {
        in.fluidThermo.hasZDefault = asBool(ft->get("hasZDefault"), false);
        in.fluidThermo.zDefault = asDoubleArray(ft->get("zDefault"));
        in.fluidThermo.kij = asDoubleMatrix(ft->get("kij"));

        if (const JValue* comps = ft->get("components"); comps && comps->isArray()) {
            for (const auto& cv : comps->a) {
                if (!cv.isObject()) continue;
                Component c;
                c.name = asString(cv.get("name"));
                c.Tb = asDouble(cv.get("Tb"));
                c.MW = asDouble(cv.get("MW"));
                c.Tc = asDouble(cv.get("Tc"));
                c.Pc = asDouble(cv.get("Pc"));
                c.omega = asDouble(cv.get("omega"));
                c.SG = asDouble(cv.get("SG"));
                c.delta = asDouble(cv.get("delta"));
                in.fluidThermo.components.push_back(std::move(c));
            }
        }
    }

    return in;
}

std::filesystem::path solverInputsPathFor(const std::filesystem::path& baselinePath) {
    auto name = baselinePath.filename().string();
    const std::string suffix = "_run_results.txt";
    const auto pos = name.rfind(suffix);
    REQUIRE(pos != std::string::npos);
    name.replace(pos, suffix.size(), "_solver_inputs.json");
    return baselinePath.parent_path() / name;
}

std::vector<std::pair<std::string, std::string>> allCrudeRegressionCases() {
    return {
        {"Brent", "brent_run_results.txt"},
        {"West Texas Intermediate", "wti_run_results.txt"},
        {"Western Canadian Select", "wcs_run_results.txt"},
        {"Arab Light", "arab_light_run_results.txt"},
        {"Venezuelan Heavy", "venezuelan_heavy_run_results.txt"},
    };
}

void checkNumberNear(
   double current,
   double baseline,
   double absTol,
   double relTol,
   const std::string& sectionName,
   const std::string& fieldName,
   const std::optional<std::size_t>& rowIndex = std::nullopt)
{
   const double allowed = std::max(absTol, std::abs(baseline) * relTol);
   const double diff = std::abs(current - baseline);

   INFO("Section = " << sectionName);
   INFO("Field = " << fieldName);
   if (rowIndex.has_value()) {
      INFO("Row = " << *rowIndex);
   }
   INFO("Current = " << current);
   INFO("Baseline = " << baseline);
   INFO("Absolute difference = " << diff);
   INFO("Absolute tolerance = " << absTol);
   INFO("Relative tolerance = " << relTol);
   INFO("Allowed difference = " << allowed);

   CHECK(current == Catch::Approx(baseline).margin(allowed));

   if (diff > allowed) {
      UNSCOPED_INFO(
         "Tolerance failure in section '" << sectionName
         << "', field '" << fieldName
         << (rowIndex.has_value() ? "', row " + std::to_string(*rowIndex) : "'")
         << ": current=" << current
         << ", baseline=" << baseline
         << ", diff=" << diff
         << ", allowed=" << allowed
         << " (absTol=" << absTol
         << ", relTol=" << relTol << ")");
   }
}

void compareKeyValueSection(
    const KeyValueSection& current,
    const KeyValueSection& baseline,
    const std::set<std::string>& exactKeys,
    double absTol,
    double relTol,
    const std::string& sectionName)
{
    INFO("Comparing key/value section: " << sectionName);
    REQUIRE(current.values.size() == baseline.values.size());

    for (const auto& [key, baseVal] : baseline.values) {
        INFO("Section = " << sectionName);
        INFO("Key = " << key);

        auto it = current.values.find(key);
        REQUIRE(it != current.values.end());

        const std::string& curVal = it->second;
        INFO("Current raw value = " << curVal);
        INFO("Baseline raw value = " << baseVal);

        if (exactKeys.count(key) > 0) {
            CHECK(curVal == baseVal);
        } else {
            const auto curNum = tryParseNumber(curVal);
            const auto baseNum = tryParseNumber(baseVal);
            if (curNum && baseNum) {
                checkNumberNear(*curNum, *baseNum, absTol, relTol, sectionName, key);
            } else {
                CHECK(curVal == baseVal);
            }
        }
    }
}

void compareTableSection(
   const TableSection& current,
   const TableSection& baseline,
   const std::set<std::string>& exactColumns,
   double absTol,
   double relTol,
   const std::string& sectionName)
{
   INFO("Comparing table section: " << sectionName);
   REQUIRE(current.headers == baseline.headers);
   REQUIRE(current.rows.size() == baseline.rows.size());

   for (std::size_t r = 0; r < baseline.rows.size(); ++r) {
      const auto& baseRow = baseline.rows[r];
      const auto& curRow = current.rows[r];

      INFO("Section = " << sectionName);
      INFO("Row = " << r);
      REQUIRE(curRow.size() == baseRow.size());

      for (std::size_t c = 0; c < baseline.headers.size(); ++c) {
         const auto& col = baseline.headers[c];
         const std::string& curVal = curRow[c];
         const std::string& baseVal = baseRow[c];

         INFO("Section = " << sectionName);
         INFO("Row = " << r);
         INFO("Column = " << col);
         INFO("Current raw value = " << curVal);
         INFO("Baseline raw value = " << baseVal);

         if (exactColumns.count(col) > 0) {
            CHECK(curVal == baseVal);
            if (curVal != baseVal) {
               UNSCOPED_INFO(
                  "Exact-column mismatch in section '" << sectionName
                  << "', row " << r
                  << ", column '" << col
                  << "': current='" << curVal
                  << "', baseline='" << baseVal << "'");
            }
         }
         else {
            const auto curNum = tryParseNumber(curVal);
            const auto baseNum = tryParseNumber(baseVal);
            if (curNum && baseNum) {
               checkNumberNear(*curNum, *baseNum, absTol, relTol, sectionName, col, r);
            }
            else {
               CHECK(curVal == baseVal);
               if (curVal != baseVal) {
                  UNSCOPED_INFO(
                     "String-column mismatch in section '" << sectionName
                     << "', row " << r
                     << ", column '" << col
                     << "': current='" << curVal
                     << "', baseline='" << baseVal << "'");
               }
            }
         }
      }
   }
}

} // namespace

TEST_CASE("Column crude run-results regression baselines stay stable", "[column][regression][runresults]") {
    const auto caseDef = GENERATE(from_range(allCrudeRegressionCases()));
    CAPTURE(caseDef.first, caseDef.second);

    const auto baselinePath = std::filesystem::path(__FILE__).parent_path() / "baselines" / caseDef.second;
    const auto solverInputsPath = solverInputsPathFor(baselinePath);
    CAPTURE(solverInputsPath.string());

    const std::string solverInputsText = readAllText(solverInputsPath);
    SolverInputs in = loadSolverInputsFromJsonText(solverInputsText);
    in.suppressLogs = true;

    const SolverOutputs out = solveColumn(in);
    REQUIRE_FALSE(out.runResultsText.empty());

    const std::string baselineText = readAllText(baselinePath);

    const ParsedRunResults current = parseRunResults(out.runResultsText);
    const ParsedRunResults baseline = parseRunResults(baselineText);

    compareKeyValueSection(
        current.solveSummary,
        baseline.solveSummary,
        {"Status", "FluidName", "CondenserType", "ReboilerType", "CondenserSpec", "ReboilerSpec"},
        1e-6,
        1e-6,
        "Solve Summary");

    compareKeyValueSection(
        current.energyBoundary,
        baseline.energyBoundary,
        {},
        1e-2,
        1e-4,
        "Energy / Boundary Summary");

    compareKeyValueSection(
       current.massBalance,
       baseline.massBalance,
       {},
       1e-6,
       1e-6,
       "Mass Balance Summary");

   compareTableSection(
       current.sideDrawSummary,
       baseline.sideDrawSummary,
       {"Name", "Tray"},
       1e-3,
       1e-5,
       "Side Draw Summary");

   compareTableSection(
       current.trayProfile,
       baseline.trayProfile,
       {"Tray"},
       1e-3,
       1e-5,
       "Tray Profile");

   compareTableSection(
       current.streamSummary,
       baseline.streamSummary,
       {"Stream", "Role", "Tray"},
       1e-3,
       1e-5,
       "Stream Summary");

   compareTableSection(
       current.diagnostics,
       baseline.diagnostics,
       {"Level", "Code", "Message"},
       0.0,
       0.0,
       "Diagnostics");
}
