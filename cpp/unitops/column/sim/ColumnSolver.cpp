#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <optional>
#include <sstream>
#include <unordered_set>
#include <streambuf>


#include "ColumnSolver.hpp"
#include "../unitops/column/sim/CounterCurrentColumnSimulator.hpp"

namespace {

std::string jsonEscape_(const std::string& s) {
   std::ostringstream os;
   for (unsigned char ch : s) {
      switch (ch) {
      case '\"': os << "\\\""; break;
      case '\\': os << "\\\\"; break;
      case '\b': os << "\\b"; break;
      case '\f': os << "\\f"; break;
      case '\n': os << "\\n"; break;
      case '\r': os << "\\r"; break;
      case '\t': os << "\\t"; break;
      default:
         if (ch < 0x20) {
            os << "\\u"
               << std::hex << std::setw(4) << std::setfill('0')
               << static_cast<int>(ch)
               << std::dec << std::setfill(' ');
         }
         else {
            os << static_cast<char>(ch);
         }
         break;
      }
   }
   return os.str();
}

const char* logLevelToString_(LogLevel lvl) {
   switch (lvl) {
   case LogLevel::None: return "None";
   case LogLevel::Summary: return "Summary";
   case LogLevel::Debug: return "Debug";
   default: return "Unknown";
   }
}

LogLevel logLevelFromString_(const std::string& s) {
   if (s == "None") return LogLevel::None;
   if (s == "Debug") return LogLevel::Debug;
   return LogLevel::Summary;
}

void writeIndent_(std::ostringstream& os, int level, bool pretty) {
   if (!pretty) return;
   for (int i = 0; i < level; ++i) os << "  ";
}

void writeDoubleArray_(std::ostringstream& os, const std::vector<double>& vals, int level, bool pretty) {
   os << "[";
   if (pretty && !vals.empty()) os << "\n";
   for (size_t i = 0; i < vals.size(); ++i) {
      writeIndent_(os, level + 1, pretty);
      if (std::isfinite(vals[i])) os << std::setprecision(17) << vals[i];
      else os << "null";
      if (i + 1 < vals.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, level, pretty);
   os << "]";
}

void writeStringArray_(std::ostringstream& os, const std::vector<std::string>& vals, int level, bool pretty) {
   os << "[";
   if (pretty && !vals.empty()) os << "\n";
   for (size_t i = 0; i < vals.size(); ++i) {
      writeIndent_(os, level + 1, pretty);
      os << "\"" << jsonEscape_(vals[i]) << "\"";
      if (i + 1 < vals.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, level, pretty);
   os << "]";
}

void writeKijMatrix_(std::ostringstream& os, const std::vector<std::vector<double>>& vals, int level, bool pretty) {
   os << "[";
   if (pretty && !vals.empty()) os << "\n";
   for (size_t r = 0; r < vals.size(); ++r) {
      writeIndent_(os, level + 1, pretty);
      writeDoubleArray_(os, vals[r], level + 1, pretty);
      if (r + 1 < vals.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, level, pretty);
   os << "]";
}

class ScopedStdStreamSilencer {
public:
    explicit ScopedStdStreamSilencer(bool enabled)
        : enabled_(enabled), coutBuf_(nullptr), cerrBuf_(nullptr) {
        if (!enabled_) return;
        coutBuf_ = std::cout.rdbuf(nullStream_.rdbuf());
        cerrBuf_ = std::cerr.rdbuf(nullStream_.rdbuf());
    }

    ~ScopedStdStreamSilencer() {
        if (!enabled_) return;
        std::cout.rdbuf(coutBuf_);
        std::cerr.rdbuf(cerrBuf_);
    }

    ScopedStdStreamSilencer(const ScopedStdStreamSilencer&) = delete;
    ScopedStdStreamSilencer& operator=(const ScopedStdStreamSilencer&) = delete;

private:
    bool enabled_;
    std::ostringstream nullStream_;
    std::streambuf* coutBuf_;
    std::streambuf* cerrBuf_;
};

} // namespace

std::string serializeSolverInputsToJson(const SolverInputs& in, bool pretty)
{
   const auto& core = in.core;
   const auto& boundary = in.boundary;
   std::ostringstream os;
   if (pretty) os << "{\n";
   else os << "{";

   auto nl = [&](bool comma) {
      if (comma) os << ",";
      if (pretty) os << "\n";
   };

   writeIndent_(os, 1, pretty); os << "\"schemaVersion\": 1"; nl(true);
   writeIndent_(os, 1, pretty); os << "\"fluidName\": \"" << jsonEscape_(core.fluidName) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"trays\": " << core.trays; nl(true);
   writeIndent_(os, 1, pretty); os << "\"feedRateKgph\": " << std::setprecision(17) << core.feedRateKgph; nl(true);
   writeIndent_(os, 1, pretty); os << "\"feedTray\": " << core.feedTray; nl(true);
   writeIndent_(os, 1, pretty); os << "\"feedTempK\": " << std::setprecision(17) << core.feedTempK; nl(true);
   writeIndent_(os, 1, pretty); os << "\"topPressurePa\": " << std::setprecision(17) << core.topPressurePa; nl(true);
   writeIndent_(os, 1, pretty); os << "\"dpPerTrayPa\": " << std::setprecision(17) << core.dpPerTrayPa; nl(true);

   writeIndent_(os, 1, pretty); os << "\"thermoConfig\": {"; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"thermoMethodId\": \"" << jsonEscape_(core.thermoConfig.thermoMethodId) << "\","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"displayName\": \"" << jsonEscape_(core.thermoConfig.displayName) << "\","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"eosName\": \"" << jsonEscape_(core.thermoConfig.eosName) << "\","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"phaseModelFamily\": \"" << jsonEscape_(core.thermoConfig.phaseModelFamily) << "\","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"supportFlags\": "; writeStringArray_(os, core.thermoConfig.supportFlags, 2, pretty); os << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"supportsEnthalpy\": " << (core.thermoConfig.supportsEnthalpy ? "true" : "false") << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"supportsEntropy\": " << (core.thermoConfig.supportsEntropy ? "true" : "false") << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"supportsTwoPhase\": " << (core.thermoConfig.supportsTwoPhase ? "true" : "false"); if (pretty) os << "\n";
   writeIndent_(os, 1, pretty); os << "}"; nl(true);

   writeIndent_(os, 1, pretty); os << "\"eosMode\": \"" << jsonEscape_(core.eosMode) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"eosManual\": \"" << jsonEscape_(core.eosManual) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"condenserType\": \"" << jsonEscape_(boundary.condenserType) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"reboilerType\": \"" << jsonEscape_(boundary.reboilerType) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"condenserSpec\": \"" << jsonEscape_(boundary.condenserSpec) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"reboilerSpec\": \"" << jsonEscape_(boundary.reboilerSpec) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"refluxRatio\": " << std::setprecision(17) << boundary.refluxRatio; nl(true);
   writeIndent_(os, 1, pretty); os << "\"boilupRatio\": " << std::setprecision(17) << boundary.boilupRatio; nl(true);
   writeIndent_(os, 1, pretty); os << "\"qcKW\": " << std::setprecision(17) << boundary.qcKW; nl(true);
   writeIndent_(os, 1, pretty); os << "\"qrKW\": " << std::setprecision(17) << boundary.qrKW; nl(true);
   writeIndent_(os, 1, pretty); os << "\"topTsetK\": " << std::setprecision(17) << boundary.topTsetK; nl(true);
   writeIndent_(os, 1, pretty); os << "\"bottomTsetK\": " << std::setprecision(17) << boundary.bottomTsetK; nl(true);

   writeIndent_(os, 1, pretty); os << "\"murphree\": {"; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaVTop\": " << std::setprecision(17) << core.etaVTop << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaVMid\": " << std::setprecision(17) << core.etaVMid << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaVBot\": " << std::setprecision(17) << core.etaVBot << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"enableEtaL\": " << (core.enableEtaL ? "true" : "false") << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaLTop\": " << std::setprecision(17) << core.etaLTop << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaLMid\": " << std::setprecision(17) << core.etaLMid << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"etaLBot\": " << std::setprecision(17) << core.etaLBot; if (pretty) os << "\n";
   writeIndent_(os, 1, pretty); os << "}"; nl(true);

   writeIndent_(os, 1, pretty); os << "\"logLevel\": \"" << logLevelToString_(core.logLevel) << "\""; nl(true);
   writeIndent_(os, 1, pretty); os << "\"suppressLogs\": " << (core.suppressLogs ? "true" : "false"); nl(true);

   writeIndent_(os, 1, pretty); os << "\"feedComposition\": ";
   writeDoubleArray_(os, core.feedComposition, 1, pretty); nl(true);

   writeIndent_(os, 1, pretty); os << "\"drawSpecs\": [";
   if (pretty && !core.drawSpecs.empty()) os << "\n";
   for (size_t i = 0; i < core.drawSpecs.size(); ++i) {
      const auto& ds = core.drawSpecs[i];
      writeIndent_(os, 2, pretty); os << "{";
      if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "\"trayIndex0\": " << ds.trayIndex0 << ","; if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "\"name\": \"" << jsonEscape_(ds.name) << "\","; if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "\"basis\": \"" << jsonEscape_(ds.basis) << "\","; if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "\"phase\": \"" << jsonEscape_(ds.phase) << "\","; if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "\"value\": " << std::setprecision(17) << ds.value; if (pretty) os << "\n";
      writeIndent_(os, 2, pretty); os << "}";
      if (i + 1 < core.drawSpecs.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, 1, pretty); os << "]"; nl(true);

   writeIndent_(os, 1, pretty); os << "\"drawLabelsByTray1\": {";
   if (pretty && !core.drawLabelsByTray1.empty()) os << "\n";
   size_t labelCount = 0;
   for (const auto& kv : core.drawLabelsByTray1) {
      writeIndent_(os, 2, pretty);
      os << "\"" << kv.first << "\": \"" << jsonEscape_(kv.second) << "\"";
      if (++labelCount < core.drawLabelsByTray1.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, 1, pretty); os << "}"; nl(true);

   writeIndent_(os, 1, pretty); os << "\"fluidThermo\": {"; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"hasZDefault\": " << (core.fluidThermo.hasZDefault ? "true" : "false") << ","; if (pretty) os << "\n";
   writeIndent_(os, 2, pretty); os << "\"zDefault\": ";
   writeDoubleArray_(os, core.fluidThermo.zDefault, 2, pretty); os << ","; if (pretty) os << "\n";

   writeIndent_(os, 2, pretty); os << "\"components\": [";
   if (pretty && !core.fluidThermo.components.empty()) os << "\n";
   for (size_t i = 0; i < core.fluidThermo.components.size(); ++i) {
      const auto& c = core.fluidThermo.components[i];
      writeIndent_(os, 3, pretty); os << "{";
      if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"name\": \"" << jsonEscape_(c.name) << "\","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"Tb\": " << std::setprecision(17) << c.Tb << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"MW\": " << std::setprecision(17) << c.MW << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"Tc\": " << std::setprecision(17) << c.Tc << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"Pc\": " << std::setprecision(17) << c.Pc << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"omega\": " << std::setprecision(17) << c.omega << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"SG\": " << std::setprecision(17) << c.SG << ","; if (pretty) os << "\n";
      writeIndent_(os, 4, pretty); os << "\"delta\": " << std::setprecision(17) << c.delta; if (pretty) os << "\n";
      writeIndent_(os, 3, pretty); os << "}";
      if (i + 1 < core.fluidThermo.components.size()) os << ",";
      if (pretty) os << "\n";
   }
   writeIndent_(os, 2, pretty); os << "],"; if (pretty) os << "\n";

   writeIndent_(os, 2, pretty); os << "\"kij\": ";
   writeKijMatrix_(os, core.fluidThermo.kij, 2, pretty); if (pretty) os << "\n";
   writeIndent_(os, 1, pretty); os << "}"; nl(false);

   os << "}";
   if (pretty) os << "\n";
   return os.str();
}

bool writeSolverInputsJsonFile(
   const SolverInputs& in,
   const std::string& filePath,
   std::string* errorMessage,
   bool pretty)
{
   std::ofstream out(filePath, std::ios::binary);
   if (!out.is_open()) {
      if (errorMessage) *errorMessage = "Failed to open file for writing: " + filePath;
      return false;
   }
   out << serializeSolverInputsToJson(in, pretty);
   if (!out.good()) {
      if (errorMessage) *errorMessage = "Failed while writing solver inputs JSON: " + filePath;
      return false;
   }
   return true;
}

SolverOutputs solveColumn(
   const SolverInputs& in,
   const std::function<void(const std::string&)>& onLog,
   const std::function<void(const ProgressEvent&)>& onProgress) {
   const auto& core = in.core;
   const auto& boundary = in.boundary;
   const FluidThermoData& thermo = core.fluidThermo;

   SimulationOptions opt;
   opt.thermoConfig = core.thermoConfig;
   opt.crudeName = core.fluidName;
   opt.trays = std::max(2, core.trays);
   opt.feedRate_kgph = std::max(0.0, core.feedRateKgph);

   opt.components = &thermo.components;
   opt.kij = &thermo.kij;

   const size_t NC = thermo.components.size();
   if (core.feedComposition.size() == NC) {
      opt.feedZ = core.feedComposition;
   }
   else if (thermo.hasZDefault && thermo.zDefault.size() == NC) {
      opt.feedZ = thermo.zDefault;
   }
   else {
      opt.feedZ.assign(NC, NC ? 1.0 / (double)NC : 0.0);
   }

   opt.feedTray = std::clamp(core.feedTray, 1, opt.trays);
   opt.Tfeed = core.feedTempK;
   opt.Ttop = boundary.topTsetK;
   opt.maxIter = std::max(1, core.maxIter);
   opt.outerConvergenceTolerance = std::max(1e-8, core.outerConvergenceTolerance);
   opt.Tbottom = boundary.bottomTsetK;

   opt.Ptop = core.topPressurePa;
   opt.Pdrop = core.dpPerTrayPa;

   opt.eosMode = core.eosMode;
   opt.eosManual = core.eosManual;

   const bool suppressLogs = core.suppressLogs;
   opt.onLog = ((core.logLevel == LogLevel::None) || suppressLogs)
      ? std::function<void(const std::string&)>{}
      : onLog;
   opt.onProgress = onProgress;

   opt.logLevel = suppressLogs ? LogLevel::None : core.logLevel;
   opt.reportTrayFlashDiagnostics = true;

   opt.drawSpecs.clear();
   opt.drawSpecs.reserve(core.drawSpecs.size());
   for (const auto& ds : core.drawSpecs) {
      SimulationDrawSpec s;
      s.trayIndex0 = ds.trayIndex0;
      s.name = ds.name;
      s.basis = ds.basis;
      s.phase = ds.phase;
      s.value = ds.value;
      opt.drawSpecs.push_back(std::move(s));
   }
   opt.drawLabels = core.drawLabelsByTray1;
   opt.attachedStripperSpecs = core.attachedStripperSpecs;

   opt.condenserType = boundary.condenserType;
   opt.reboilerType = boundary.reboilerType;

   auto trimLower = [](std::string s) {
      auto isSpace = [](unsigned char c) { return std::isspace(c) != 0; };
      while (!s.empty() && isSpace((unsigned char)s.front())) s.erase(s.begin());
      while (!s.empty() && isSpace((unsigned char)s.back())) s.pop_back();
      std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
      return s;
   };

   const std::string cSpec = trimLower(boundary.condenserSpec);
   const std::string rSpec = trimLower(boundary.reboilerSpec);

   opt.condenserSpec = cSpec.empty() ? "none" : cSpec;
   opt.reboilerSpec = rSpec.empty() ? "none" : rSpec;

   opt.refluxRatio = boundary.refluxRatio;
   opt.reboilRatio = boundary.boilupRatio;

   opt.Qc_kW_in = boundary.qcKW;
   opt.Qr_kW_in = boundary.qrKW;

   opt.murphree.etaV_top = core.etaVTop;
   opt.murphree.etaV_mid = core.etaVMid;
   opt.murphree.etaV_bot = core.etaVBot;
   opt.murphree.etaL_top = core.enableEtaL ? core.etaLTop : 1.0;
   opt.murphree.etaL_mid = core.enableEtaL ? core.etaLMid : 1.0;
   opt.murphree.etaL_bot = core.enableEtaL ? core.etaLBot : 1.0;

   SimulationResult sim;
   {
      ScopedStdStreamSilencer silenceStdStreams(suppressLogs);
      sim = simulateColumn(opt);
   }

   SolverOutputs out;
   out.trays.resize((size_t)opt.trays);
   for (int i = 0; i < opt.trays && i < (int)sim.trays.size(); ++i) {
      const auto& t = sim.trays[(size_t)i];
      out.trays[(size_t)i].tempK = std::isfinite(t.T) ? t.T : t.T_internal;
      out.trays[(size_t)i].vFrac = t.V;
      out.trays[(size_t)i].pressurePa = t.P;
      out.trays[(size_t)i].L_kgph = t.m_liq_dn_kgph;
      out.trays[(size_t)i].V_kgph = t.m_vap_up_kgph;
      out.trays[(size_t)i].drawFlow = t.sideDraw_kgph;
      out.trays[(size_t)i].xLiq = t.x;
      out.trays[(size_t)i].yVap = t.y;
   }

   std::ostringstream ss;
   ss << sim.status;
   if (!sim.diagnostics.empty()) ss << " (" << sim.diagnostics.size() << " diagnostics)";
   out.summary = ss.str();

   out.diagnostics = sim.diagnostics;
   out.Tcond_K = sim.boundary.condenser.T_cold_K;
   out.Treb_K = sim.boundary.reboiler.T_hot_K;
   out.condenserType = sim.energy.condenserType;
   out.energy = sim.energy;
   out.streams = sim.streams;
   out.attachedStrippers = sim.attachedStrippers;

   if (opt.components) {
      out.componentNames.clear();
      out.componentNames.reserve(opt.components->size());
      for (const auto& c : *opt.components) out.componentNames.push_back(c.name);
   }

   {
      std::ostringstream rr;
      rr.setf(std::ios::fixed);
      rr.precision(6);

      const auto& e = sim.energy;
      const auto& mb = sim.energy.massBalance;

      auto isInternalStripperReturn = [](const std::string& name) {
         return name.find(" Vapor Return") != std::string::npos;
      };

      auto stripperBottomsBaseName = [](const std::string& name) -> std::string {
         static constexpr const char* suffix = " Stripper Bottoms";
         const std::size_t suffixLen = std::char_traits<char>::length(suffix);
         if (name.size() >= suffixLen && name.compare(name.size() - suffixLen, suffixLen, suffix) == 0) {
            return name.substr(0, name.size() - suffixLen);
         }
         return {};
      };

      std::unordered_set<std::string> strippedBaseNames;
      strippedBaseNames.reserve(sim.streams.size());
      for (const auto& s : sim.streams) {
         const std::string baseName = stripperBottomsBaseName(s.name);
         if (!baseName.empty()) strippedBaseNames.insert(baseName);
      }

      auto isFinalExternalProduct = [&](const StreamSnapshot& s) {
         if (s.name == "Distillate" || s.name == "Bottoms") return true;
         if (isInternalStripperReturn(s.name)) return false;
         if (strippedBaseNames.find(s.name) != strippedBaseNames.end()) return false;
         return true;
      };

      auto streamSortRank = [](const StreamSnapshot& s) {
         if (s.name == "Distillate") return 0;
         if (s.name == "Bottoms") return 2;
         return 1;
      };

      std::vector<const StreamSnapshot*> displayedStreams;
      displayedStreams.reserve(sim.streams.size());
      double displayedProductsKgph = 0.0;
      for (const auto& s : sim.streams) {
         if (!isFinalExternalProduct(s)) continue;
         displayedProductsKgph += s.kgph;
         displayedStreams.push_back(&s);
      }
      std::sort(displayedStreams.begin(), displayedStreams.end(), [&](const StreamSnapshot* a, const StreamSnapshot* b) {
         const int rankA = streamSortRank(*a);
         const int rankB = streamSortRank(*b);
         if (rankA != rankB) return rankA < rankB;
         if (rankA == 1 && a->tray != b->tray) return a->tray > b->tray;
         if (a->name != b->name) return a->name < b->name;
         return a->kgph > b->kgph;
      });

      rr << "Solve Summary\n";
      rr << "Key,Value\n";
      rr << "Status," << sim.status << "\n";
      rr << "DiagnosticsCount," << sim.diagnostics.size() << "\n";
      rr << "FluidName," << core.fluidName << "\n";
      rr << "Trays," << opt.trays << "\n";
      rr << "FeedTray," << opt.feedTray << "\n";
      rr << "ComponentCount," << out.componentNames.size() << "\n";
      rr << "CondenserType," << e.condenserType << "\n";
      rr << "ReboilerType," << e.reboilerType << "\n";
      rr << "CondenserSpec," << e.condenserSpec << "\n";
      rr << "ReboilerSpec," << e.reboilerSpec << "\n\n";

      rr << "Energy / Boundary Summary\n";
      rr << "Key,Value\n";
      rr << "Tc_set_K," << e.Tc_set_K << "\n";
      rr << "Tc_calc_K," << e.Tc_calc_K << "\n";
      rr << "Qc_set_kW," << e.Qc_set_kW << "\n";
      rr << "Qc_calc_kW," << e.Qc_calc_kW << "\n";
      rr << "Treb_set_K," << e.Treb_set_K << "\n";
      rr << "Treb_calc_K," << e.Treb_calc_K << "\n";
      rr << "Qr_set_kW," << e.Qr_set_kW << "\n";
      rr << "Qr_calc_kW," << e.Qr_calc_kW << "\n";
      rr << "RefluxRatio_set," << e.refluxRatio_set << "\n";
      rr << "RefluxRatio_calc," << e.refluxRatio_calc << "\n";
      rr << "BoilupRatio_set," << e.boilupRatio_set << "\n";
      rr << "BoilupRatio_calc," << e.boilupRatio_calc << "\n";
      rr << "RefluxFraction," << e.reflux_fraction << "\n";
      rr << "BoilupFraction," << e.boilup_fraction << "\n";
      rr << "D_kgph," << e.D_kgph << "\n";
      rr << "B_kgph," << e.B_kgph << "\n";
      rr << "L_ref_kgph," << e.L_ref_kgph << "\n";
      rr << "V_boil_kgph," << e.V_boil_kgph << "\n\n";

      rr << "Mass Balance Summary\n";
      rr << "Key,Value\n";
      rr << "Feed_kgph," << mb.feed_kgph << "\n";
      rr << "Overhead_kgph," << mb.overhead_kgph << "\n";
      rr << "Bottoms_kgph," << mb.bottoms_kgph << "\n";
      rr << "TotalProducts_kgph," << displayedProductsKgph << "\n";
      const double closureError = mb.feed_kgph - displayedProductsKgph;
      const double closurePct = (std::abs(mb.feed_kgph) > 1e-12) ? (100.0 * closureError / mb.feed_kgph) : 0.0;
      rr << "MassClosureError_kgph," << closureError << "\n";
      rr << "MassClosureRelativePct," << closurePct << "\n\n";

      rr << "Side Draw Summary\n";
      rr << "Name,Tray,kgph\n";
      bool wroteSideDraw = false;
      for (const auto* sp : displayedStreams) {
         const auto& s = *sp;
         if (s.name == "Distillate" || s.name == "Bottoms") continue;
         rr << s.name << "," << s.tray << "," << s.kgph << "\n";
         wroteSideDraw = true;
      }
      if (!wroteSideDraw) rr << "(none),0,0.000000\n";
      rr << "\n";

      rr << "Tray Profile\n";
      rr << "Tray,TempK,PressurePa,Vfrac,L_kgph,V_kgph,DrawTarget_kgph,DrawActual_kgph,Kmin,Kmax,Htarget,Hcalc,dH\n";
      for (int i = 0; i < opt.trays && i < (int)sim.trays.size(); ++i) {
         const auto& t = sim.trays[(size_t)i];
         rr << t.i << "," << t.T << "," << t.P << "," << t.V
            << "," << t.m_liq_dn_kgph << "," << t.m_vap_up_kgph << "," << t.sideDraw_target_kgph << "," << t.sideDraw_kgph
            << "," << t.Kmin << "," << t.Kmax
            << "," << t.Htarget << "," << t.Hcalc << "," << t.dH << "\n";
      }
      rr << "\n";

      rr << "Stream Summary\n";
      rr << "Stream,Role,Tray,kgph,TempK,PressurePa,Vfrac,MW,rhoL_kgm3\n";
      rr << "Feed,Feed," << opt.feedTray << "," << opt.feedRate_kgph << "," << opt.Tfeed << ","
         << ((opt.feedTray >= 1 && opt.feedTray <= (int)sim.trays.size()) ? sim.trays[(size_t)(opt.feedTray - 1)].P : opt.Ptop)
         << "," << 0.000000 << "," << 0.000000 << "," << 0.000000 << "\n";
      for (const auto* sp : displayedStreams) {
         const auto& s = *sp;
         std::string role = "SideDraw";
         if (s.name == "Distillate") role = "Distillate";
         else if (s.name == "Bottoms") role = "Bottoms";
         rr << s.name << "," << role << "," << s.tray << "," << s.kgph << "," << s.T << "," << s.P << "," << s.Vfrac
            << "," << s.MW << "," << s.rho << "\n";
      }
      rr << "\nDiagnostics\n";
      rr << "Level,Code,Message\n";
      if (sim.diagnostics.empty()) rr << "info,none,No diagnostics\n";
      else {
         for (const auto& d : sim.diagnostics) rr << d.level << "," << d.code << "," << d.message << "\n";
      }

      out.runResultsText = rr.str();
   }

   return out;
}
