#pragma once

#include <string>
#include <vector>

namespace thermo {

enum class EOSFamily {
    PRSV,
    PR,
    SRK,
    Ideal,
    Unknown
};

enum class FlashSpecType {
    TP,
    PH,
    PS,
    TS,
    PVF,
    Unknown
};

struct ThermoConfig {
    std::string thermoMethodId;
    std::string displayName;
    std::string eosName;
    std::string phaseModelFamily;
    std::vector<std::string> supportFlags;
    bool supportsEnthalpy = true;
    bool supportsEntropy = true;
    bool supportsTwoPhase = true;

    [[nodiscard]] bool supportsFlashSpec(FlashSpecType spec) const;
};

[[nodiscard]] EOSFamily eosFamilyFromMethodId(const std::string& methodId);
[[nodiscard]] std::string eosNameFromMethodId(const std::string& methodId);
[[nodiscard]] ThermoConfig makeThermoConfig(const std::string& methodId,
                                            const std::string& phaseModelFamily = "EOS",
                                            const std::vector<std::string>& explicitSupportFlags = {});
[[nodiscard]] FlashSpecType flashSpecTypeFromString(const std::string& text);

} // namespace thermo
