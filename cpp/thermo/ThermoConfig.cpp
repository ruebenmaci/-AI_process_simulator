#include "ThermoConfig.hpp"

#include <algorithm>
#include <cctype>

namespace thermo {
namespace {
std::string trim(std::string text)
{
    auto notSpace = [](unsigned char ch) { return !std::isspace(ch); };
    text.erase(text.begin(), std::find_if(text.begin(), text.end(), notSpace));
    text.erase(std::find_if(text.rbegin(), text.rend(), notSpace).base(), text.end());
    return text;
}

std::string upper(std::string text)
{
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char ch) {
        return static_cast<char>(std::toupper(ch));
    });
    return text;
}

std::string normalizeMethod(std::string method)
{
    method = upper(trim(method));
    if (method == "PENG-ROBINSON") return "PR";
    if (method == "PRSV") return "PRSV";
    if (method == "PR") return "PR";
    if (method == "SRK") return "SRK";
    if (method == "IDEAL" || method == "RAOULT'S LAW") return "IDEAL";
    return method.empty() ? "PRSV" : method;
}

std::vector<std::string> defaultSupportFlagsForMethod(const std::string& method)
{
    const std::string normalized = normalizeMethod(method);
    if (normalized == "IDEAL")
        return {"TP", "PH", "PS"};
    return {"TP", "PH", "PS", "TS", "PVF"};
}

std::string flashToken(FlashSpecType spec)
{
    switch (spec) {
    case FlashSpecType::TP: return "TP";
    case FlashSpecType::PH: return "PH";
    case FlashSpecType::PS: return "PS";
    case FlashSpecType::TS: return "TS";
    case FlashSpecType::PVF: return "PVF";
    default: return {};
    }
}
}

bool ThermoConfig::supportsFlashSpec(FlashSpecType spec) const
{
    const std::string token = flashToken(spec);
    return !token.empty() && std::find(supportFlags.begin(), supportFlags.end(), token) != supportFlags.end();
}

EOSFamily eosFamilyFromMethodId(const std::string& methodId)
{
    const std::string normalized = normalizeMethod(methodId);
    if (normalized == "PRSV") return EOSFamily::PRSV;
    if (normalized == "PR") return EOSFamily::PR;
    if (normalized == "SRK") return EOSFamily::SRK;
    if (normalized == "IDEAL") return EOSFamily::Ideal;
    return EOSFamily::Unknown;
}

std::string eosNameFromMethodId(const std::string& methodId)
{
    switch (eosFamilyFromMethodId(methodId)) {
    case EOSFamily::PRSV: return "PRSV";
    case EOSFamily::PR: return "PR";
    case EOSFamily::SRK: return "SRK";
    case EOSFamily::Ideal: return "Ideal";
    default: return "PRSV";
    }
}

ThermoConfig makeThermoConfig(const std::string& methodId,
                              const std::string& phaseModelFamily,
                              const std::vector<std::string>& explicitSupportFlags)
{
    ThermoConfig cfg;
    cfg.thermoMethodId = normalizeMethod(methodId);
    cfg.displayName = cfg.thermoMethodId;
    cfg.eosName = eosNameFromMethodId(cfg.thermoMethodId);
    cfg.phaseModelFamily = trim(phaseModelFamily).empty() ? "EOS" : trim(phaseModelFamily);
    cfg.supportFlags = explicitSupportFlags.empty() ? defaultSupportFlagsForMethod(cfg.thermoMethodId)
                                                    : explicitSupportFlags;
    cfg.supportsEnthalpy = std::find(cfg.supportFlags.begin(), cfg.supportFlags.end(), "PH") != cfg.supportFlags.end();
    cfg.supportsEntropy = std::find(cfg.supportFlags.begin(), cfg.supportFlags.end(), "PS") != cfg.supportFlags.end()
                       || std::find(cfg.supportFlags.begin(), cfg.supportFlags.end(), "TS") != cfg.supportFlags.end();
    cfg.supportsTwoPhase = std::find(cfg.supportFlags.begin(), cfg.supportFlags.end(), "PVF") != cfg.supportFlags.end()
                        || std::find(cfg.supportFlags.begin(), cfg.supportFlags.end(), "TP") != cfg.supportFlags.end();
    return cfg;
}

FlashSpecType flashSpecTypeFromString(const std::string& text)
{
    const std::string normalized = upper(trim(text));
    if (normalized == "TP") return FlashSpecType::TP;
    if (normalized == "PH") return FlashSpecType::PH;
    if (normalized == "PS") return FlashSpecType::PS;
    if (normalized == "TS") return FlashSpecType::TS;
    if (normalized == "PVF") return FlashSpecType::PVF;
    return FlashSpecType::Unknown;
}

} // namespace thermo
