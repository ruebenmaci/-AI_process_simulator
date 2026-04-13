// test_benzene_toluene_column.cpp
//
// Validates the column solver against the known-good benzene/toluene results
// captured on 2026-04-06 using the UI:
//
//   20 trays, feed tray 10, feed 100000 kg/h at 373 K
//   Top pressure 150000 Pa, dP/tray 200 Pa
//   Total condenser, temperature spec 362 K, reflux ratio 2.0
//   Partial reboiler, duty spec 6000 kW
//   Feed: 50/50 mass fraction Benzene/Toluene
//   EOS: PRSV
//
// Expected results (from UI screenshots):
//   Distillate:  18184 kg/h  (18.18% of feed)
//   Bottoms:     81816 kg/h  (81.82% of feed)
//   Balance error: 0.00%
//   Tray 20 (top):  362.0 K,  x_benz=0.9137, y_benz=0.9150
//   Tray 10 (feed): 380.8 K,  x_benz=0.4743, y_benz=0.6715
//   Tray  1 (bot):  385.9 K,  x_benz≈0.11  (from chart)
//   y > x on every tray (benzene more volatile)

#include <catch2/catch_all.hpp>
#include <cmath>
#include <string>
#include <vector>

#include "../cpp/unitops/column/sim/ColumnSolver.hpp"

// ── Build benzene/toluene FluidThermoData from DIPPR critical properties ──────
// These are the exact values stored in the component database (starter-seed).
// Pc is in Pa (as used by the EOS layer).

static FluidThermoData makeBenzeneTolueneThermo()
{
    FluidThermoData thermo;

    Component benzene;
    benzene.name  = "Benzene";
    benzene.MW    = 78.114;
    benzene.Tb    = 353.24;
    benzene.Tc    = 562.05;
    benzene.Pc    = 4895000.0;   // Pa
    benzene.omega = 0.212;
    benzene.SG    = 0.0;
    benzene.delta = 0.0;

    Component toluene;
    toluene.name  = "Toluene";
    toluene.MW    = 92.14;
    toluene.Tb    = 383.78;
    toluene.Tc    = 591.75;
    toluene.Pc    = 4109000.0;   // Pa
    toluene.omega = 0.264;
    toluene.SG    = 0.0;
    toluene.delta = 0.0;

    thermo.components = { benzene, toluene };

    // Binary interaction parameters — zero for benzene/toluene (ideal mixing)
    thermo.kij = { {0.0, 0.0}, {0.0, 0.0} };

    // Feed composition: 50/50 mass fractions → stored as mass fracs
    // The solver converts to mole fracs internally via normalizedComposition_()
    thermo.zDefault     = { 0.5, 0.5 };
    thermo.hasZDefault  = true;

    return thermo;
}

static SolverInputs makeBTInputs()
{
    SolverInputs in{};

    in.fluidName      = "BenzeneToluene";
    in.fluidThermo    = makeBenzeneTolueneThermo();
    in.feedComposition = in.fluidThermo.zDefault;   // 50/50 mass fracs

    in.trays          = 20;
    in.feedTray       = 10;
    in.feedRateKgph   = 100000.0;
    in.feedTempK      = 373.0;

    in.topPressurePa  = 150000.0;
    in.dpPerTrayPa    = 200.0;

    in.condenserType  = "total";
    in.condenserSpec  = "Temperature";
    in.topTsetK       = 362.0;
    in.refluxRatio    = 2.0;
    in.qcKW           = -6000.0;   // ignored when spec=Temperature

    in.reboilerType   = "partial";
    in.reboilerSpec   = "Duty";
    in.qrKW           = 6000.0;
    in.boilupRatio    = 0.06;      // ignored when spec=Duty
    in.bottomTsetK    = 393.0;

    in.eosMode        = "auto";
    in.eosManual      = "PRSV";

    // Murphree efficiency = 1.0 (ideal trays, matches UI default)
    in.etaVTop  = 1.0;
    in.etaVMid  = 1.0;
    in.etaVBot  = 1.0;
    in.enableEtaL = false;
    in.etaLTop  = 1.0;
    in.etaLMid  = 1.0;
    in.etaLBot  = 1.0;

    in.drawSpecs.clear();
    in.drawLabelsByTray1.clear();

    return in;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

static bool finite_val(double x) { return std::isfinite(x); }

// trays are stored index 0 = tray 1 (bottoms), index N-1 = tray N (top)
static const SolverTrayOut& trayByNumber(const SolverOutputs& out, int tray1)
{
    // tray1 is 1-based from bottom; index = tray1 - 1
    return out.trays.at(static_cast<std::size_t>(tray1 - 1));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

TEST_CASE("BT column: solver runs and produces finite outputs", "[benzene_toluene][smoke]")
{
    SolverInputs in = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    REQUIRE(out.trays.size() == static_cast<std::size_t>(in.trays));
    REQUIRE(finite_val(out.energy.massBalance.totalProducts_kgph));
    REQUIRE(out.energy.massBalance.totalProducts_kgph > 0.0);
}

TEST_CASE("BT column: mass balance error < 0.1%", "[benzene_toluene][balance]")
{
    SolverInputs in = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    const double total = out.energy.massBalance.totalProducts_kgph;
    const double error = std::abs(total - in.feedRateKgph) / in.feedRateKgph;

    INFO("Feed:          " << in.feedRateKgph << " kg/h");
    INFO("Total products:" << total           << " kg/h");
    INFO("Balance error: " << error * 100.0   << " %");

    REQUIRE(finite_val(total));
    // UI showed 0.00% — allow up to 0.1% for floating-point tolerance
    CHECK(error == Catch::Approx(0.0).margin(0.001));
}

TEST_CASE("BT column: distillate and bottoms splits match UI results", "[benzene_toluene][products]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // UI result: Distillate 18184 kg/h, Bottoms 81816 kg/h
    // Allow ±500 kg/h (0.5% of feed) — accounts for minor EOS iteration differences
    const double distillate = out.energy.massBalance.overhead_kgph;
    const double bottoms    = out.energy.massBalance.bottoms_kgph;

    INFO("Distillate (overhead): " << distillate << " kg/h  (expected ~18184)");
    INFO("Bottoms:    " << bottoms    << " kg/h  (expected ~81816)");

    REQUIRE(finite_val(distillate));
    REQUIRE(finite_val(bottoms));
    CHECK(distillate == Catch::Approx(18184.0).margin(500.0));
    CHECK(bottoms    == Catch::Approx(81816.0).margin(500.0));
}

TEST_CASE("BT column: temperature profile is monotonically increasing bottom to top", "[benzene_toluene][temperature]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // Tray 1 (bottoms) must be hottest, tray 20 (top) must be coolest
    // (excluding condenser tray which is spec'd at 362 K)
    for (int t = 2; t <= in.trays; ++t) {
        const double T_below = trayByNumber(out, t - 1).tempK;
        const double T_above = trayByNumber(out, t    ).tempK;
        INFO("Tray " << (t-1) << " T=" << T_below << "  Tray " << t << " T=" << T_above);
        CHECK(T_above <= T_below + 0.5);   // allow tiny numerical noise
    }
}

TEST_CASE("BT column: tray temperatures within expected range", "[benzene_toluene][temperature]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // Top tray (20): condenser spec 362 K — should be close
    const double T_top = trayByNumber(out, 20).tempK;
    INFO("Tray 20 T = " << T_top << " K  (expected 362.0)");
    CHECK(T_top == Catch::Approx(362.0).margin(2.0));

    // Feed tray (10): UI showed 380.757 K
    const double T_feed = trayByNumber(out, 10).tempK;
    INFO("Tray 10 T = " << T_feed << " K  (expected ~380.8)");
    CHECK(T_feed == Catch::Approx(380.8).margin(3.0));

    // Bottoms tray (1): UI showed 385.909 K
    const double T_bot = trayByNumber(out, 1).tempK;
    INFO("Tray  1 T = " << T_bot << " K  (expected ~385.9)");
    CHECK(T_bot == Catch::Approx(385.9).margin(3.0));
}

TEST_CASE("BT column: condenser is total (vFrac=0 at tray 20)", "[benzene_toluene][condenser]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    const double vFrac_top = trayByNumber(out, 20).vFrac;
    INFO("Tray 20 vFrac = " << vFrac_top << "  (expected 0.0 for total condenser)");
    CHECK(vFrac_top == Catch::Approx(0.0).margin(0.01));
}

TEST_CASE("BT column: vapor fraction consistent within sections", "[benzene_toluene][vfrac]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // Rectifying section (trays 19 down to 11): UI showed ~0.595-0.597
    for (int t = 11; t <= 19; ++t) {
        const double vf = trayByNumber(out, t).vFrac;
        INFO("Tray " << t << " vFrac = " << vf);
        CHECK(vf == Catch::Approx(0.596).margin(0.05));
    }

    // Stripping section (trays 2-9): UI showed ~0.292-0.294
    for (int t = 2; t <= 9; ++t) {
        const double vf = trayByNumber(out, t).vFrac;
        INFO("Tray " << t << " vFrac = " << vf);
        CHECK(vf == Catch::Approx(0.293).margin(0.05));
    }
}

TEST_CASE("BT column: benzene y > x on every tray (more volatile)", "[benzene_toluene][vle]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // Benzene is component index 0
    constexpr std::size_t benz = 0;

    for (int t = 1; t <= in.trays; ++t) {
        const auto& tray = trayByNumber(out, t);
        if (tray.xLiq.size() <= benz || tray.yVap.size() <= benz) continue;
        const double x = tray.xLiq[benz];
        const double y = tray.yVap[benz];
        INFO("Tray " << t << "  x_benz=" << x << "  y_benz=" << y);
        // y > x always (benzene enriches in vapor phase)
        CHECK(y >= x - 0.01);   // small tolerance for near-pure trays
    }
}

TEST_CASE("BT column: benzene mole fractions match UI at key trays", "[benzene_toluene][composition]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    constexpr std::size_t benz = 0;

    // Tray 20 (top): UI x=0.9137, y=0.9150
    {
        const auto& tray = trayByNumber(out, 20);
        REQUIRE(tray.xLiq.size() > benz);
        REQUIRE(tray.yVap.size() > benz);
        INFO("Tray 20 x_benz=" << tray.xLiq[benz] << " y_benz=" << tray.yVap[benz]);
        CHECK(tray.xLiq[benz] == Catch::Approx(0.9137).margin(0.02));
        CHECK(tray.yVap[benz] == Catch::Approx(0.9150).margin(0.02));
    }

    // Tray 10 (feed): UI x=0.4743, y=0.6715
    {
        const auto& tray = trayByNumber(out, 10);
        REQUIRE(tray.xLiq.size() > benz);
        REQUIRE(tray.yVap.size() > benz);
        INFO("Tray 10 x_benz=" << tray.xLiq[benz] << " y_benz=" << tray.yVap[benz]);
        CHECK(tray.xLiq[benz] == Catch::Approx(0.4743).margin(0.02));
        CHECK(tray.yVap[benz] == Catch::Approx(0.6715).margin(0.02));
    }

    // Tray 12 (rectifying): UI x=0.5078, y=0.7010
    {
        const auto& tray = trayByNumber(out, 12);
        REQUIRE(tray.xLiq.size() > benz);
        REQUIRE(tray.yVap.size() > benz);
        INFO("Tray 12 x_benz=" << tray.xLiq[benz] << " y_benz=" << tray.yVap[benz]);
        CHECK(tray.xLiq[benz] == Catch::Approx(0.5078).margin(0.02));
        CHECK(tray.yVap[benz] == Catch::Approx(0.7010).margin(0.02));
    }
}

TEST_CASE("BT column: benzene enriches top-to-bottom correctly", "[benzene_toluene][composition]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    constexpr std::size_t benz = 0;

    // x_benzene should decrease from top (tray 20) to bottom (tray 1)
    for (int t = 2; t <= in.trays; ++t) {
        const auto& above = trayByNumber(out, t    );
        const auto& below = trayByNumber(out, t - 1);
        if (above.xLiq.size() <= benz || below.xLiq.size() <= benz) continue;
        INFO("Tray " << t << " x=" << above.xLiq[benz]
             << "  Tray " << (t-1) << " x=" << below.xLiq[benz]);
        CHECK(above.xLiq[benz] >= below.xLiq[benz] - 0.01);
    }
}

TEST_CASE("BT column: liquid flow jump at feed tray", "[benzene_toluene][flows]")
{
    SolverInputs in  = makeBTInputs();
    in.suppressLogs = true;
    const SolverOutputs out = solveColumn(in);

    // Liquid flow below feed tray should be substantially higher than above
    // UI: ~140000 kg/h below vs ~37000 kg/h above
    const double L_above_feed = trayByNumber(out, 11).L_kgph;
    const double L_below_feed = trayByNumber(out, 10).L_kgph;

    INFO("L above feed (tray 11): " << L_above_feed << " kg/h");
    INFO("L below feed (tray 10): " << L_below_feed << " kg/h");

    CHECK(L_below_feed > L_above_feed * 2.0);   // at least double — feed adds liquid
}
