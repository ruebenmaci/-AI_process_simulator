#include <catch2/catch_all.hpp>

#include "ThermoRoundTripCommon.hpp"

TEST_CASE("TP -> PH/PS/TS round-trip stays close for baseline Brent state", "[thermo][roundtrip]")
{
    const auto row = runThermoRoundTrip("Brent", 150000.0, 628.15);

    REQUIRE(row.tpFinite);

    REQUIRE(row.phFinite);
    CHECK(row.dT_PH == Catch::Approx(0.0).margin(1.0));
    CHECK(row.dV_PH == Catch::Approx(0.0).margin(0.05));
    CHECK(row.dH_PH == Catch::Approx(0.0).margin(1e-3));
    CHECK(row.dS_PH == Catch::Approx(0.0).margin(1e-3));

    REQUIRE(row.psFinite);
    CHECK(row.dT_PS == Catch::Approx(0.0).margin(2.0));
    CHECK(row.dV_PS == Catch::Approx(0.0).margin(0.10));
    CHECK(row.dH_PS == Catch::Approx(0.0).margin(5e-2));
    CHECK(row.dS_PS == Catch::Approx(0.0).margin(1e-3));

    REQUIRE(row.tsFinite);
    CHECK(row.dP_TS == Catch::Approx(0.0).margin(5000.0));
    CHECK(row.dV_TS == Catch::Approx(0.0).margin(0.10));
    CHECK(row.dH_TS == Catch::Approx(0.0).margin(5e-2));
    CHECK(row.dS_TS == Catch::Approx(0.0).margin(1e-3));
}
