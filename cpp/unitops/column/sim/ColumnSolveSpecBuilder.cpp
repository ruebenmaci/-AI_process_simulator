#include "unitops/column/sim/ColumnSolveSpecBuilder.hpp"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

#include "unitops/column/state/ColumnUnitState.h"
#include "streams/state/MaterialStreamState.h"
#include "unitops/column/sim/ColumnSolver.hpp"
#include "../../../fluid/FluidPackageManager.h"

#include "unitops/column/sim/ColumnSideOperations.hpp"

static std::vector<SideDrawSpec> parseSideDrawSpecs(const ColumnUnitState& column)
{
   std::vector<SideDrawSpec> out;

   const QVariantList rawDraws = column.drawSpecs();
   out.reserve(rawDraws.size());

   for (const auto& v : rawDraws)
   {
      const QVariantMap m = v.toMap();

      const QString name = m.value("name").toString().trimmed();
      const int tray1 = m.value("tray").toInt();

      const QString basis = m.value("basis").toString().trimmed().isEmpty()
         ? QString("feedPct")
         : m.value("basis").toString().trimmed();

      const QString phase = m.value("phase").toString().trimmed().isEmpty()
         ? QString("L")
         : m.value("phase").toString().trimmed();

      const double value = m.contains("value")
         ? m.value("value").toDouble()
         : m.value("pct").toDouble();

      if (name.isEmpty())
         continue;
      if (tray1 <= 0 || tray1 > column.trays())
         continue;
      if (!std::isfinite(value) || value <= 0.0)
         continue;
      if (phase.compare("L", Qt::CaseInsensitive) != 0)
         continue;

      SideDrawSpec d;
      d.name = name.toStdString();
      d.trayIndex0 = tray1 - 1;
      d.basis = basis.toStdString();
      d.phase = phase.toStdString();
      d.value = value;

      out.push_back(std::move(d));
   }

   return out;
}

static std::vector<SimulationAttachedStripperSpec> parseAttachedStripperSpecs(const ColumnUnitState& column)
{
   std::vector<SimulationAttachedStripperSpec> out;

   const QVariantList rawDraws = column.drawSpecs();
   out.reserve(rawDraws.size());

   for (const auto& v : rawDraws)
   {
      const QVariantMap m = v.toMap();
      if (!m.value("stripperEnabled").toBool())
         continue;

      const int tray1 = m.value("tray").toInt();
      if (tray1 <= 1 || tray1 >= column.trays())
         continue;

      SimulationAttachedStripperSpec s;
      s.stripperId = m.value("stripperId").toString().trimmed().toStdString();
      const QString drawName = m.value("name").toString().trimmed();
      const QString label = m.value("stripperLabel").toString().trimmed();
      s.label = (label.isEmpty() ? QStringLiteral("%1 Stripper").arg(drawName.isEmpty() ? QStringLiteral("Draw") : drawName) : label).toStdString();
      s.sourceTrayIndex0 = tray1 - 1;
      s.returnTrayIndex0 = std::clamp(m.value("stripperReturnTray").toInt() - 1, 0, std::max(0, column.trays() - 1));
      s.trays = std::max(2, m.value("stripperTrays", 4).toInt());
      s.feedTrayIndex0 = std::clamp(s.trays - 2, 0, s.trays - 1);
      s.topPressurePa = column.topPressurePa() + column.dpPerTrayPa() * std::max(0, column.trays() - tray1);
      s.dpPerStagePa = std::max(0.0, column.dpPerTrayPa());
      s.maxCoupledIterations = std::max(1, m.value("stripperMaxCoupledIterations", 25).toInt());
      s.couplingTolerance = std::max(1e-8, m.value("stripperCouplingTolerance", 1e-3).toDouble());
      s.returnDamping = std::clamp(m.value("stripperReturnDamping", 0.35).toDouble(), 0.0, 1.0);

      const QString heatMode = m.value("stripperHeatMode").toString().trimmed();
      const double heatValue = m.value("stripperHeatValue").toDouble();
      if (heatMode.compare(QStringLiteral("Steam"), Qt::CaseInsensitive) == 0) {
         s.heatMode = "steam";
         s.steamRateKgph = std::max(0.0, heatValue);
      } else if (heatMode.compare(QStringLiteral("ReboilerDuty"), Qt::CaseInsensitive) == 0 ||
                 heatMode.compare(QStringLiteral("Duty"), Qt::CaseInsensitive) == 0) {
         s.heatMode = "reboiler_duty";
         s.reboilerDutyKW = std::max(0.0, heatValue);
      } else {
         s.heatMode = "none";
      }

      out.push_back(std::move(s));
   }

   return out;
}

namespace ColumnSolveSpecBuilder
{
   bool build(
      const ColumnUnitState& column,
      const MaterialStreamState* feed,
      SolverInputs& out,
      QString* errorMessage)
   {
      if (!feed) {
         if (errorMessage)
            *errorMessage = QStringLiteral("Column solve failed: no active feed stream.");
         return false;
      }

      out = SolverInputs{};

      out.fluidName = feed->selectedFluid().toStdString();
      out.fluidThermo = feed->fluidDefinition().thermo;
      out.feedComposition = feed->compositionStd();

      out.trays = column.trays();
      out.feedRateKgph = column.feedRateKgph();
      out.feedTray = std::clamp(column.feedTray(), 1, out.trays);
      out.feedTempK = column.feedTempK();
      out.maxIter = column.maxOuterIterations();
      out.outerConvergenceTolerance = column.outerConvergenceTolerance();

      out.topPressurePa = column.topPressurePa();
      out.dpPerTrayPa = column.dpPerTrayPa();

      // Keep current logging behavior exactly the same.
      const int uiLogLevel = column.solverLogLevel();          // 0=None, 1=Summary, 2=Debug
      const int solverEmitLevel = (uiLogLevel <= 0) ? 1 : uiLogLevel;
      out.logLevel = static_cast<LogLevel>(solverEmitLevel);

      // Resolve ThermoConfig from package if available, otherwise preserve legacy EOS path.
      const QString pkgId = feed->selectedFluidPackageId().trimmed();
      if (!pkgId.isEmpty() && feed->fluidPackageValid()) {
         auto* fpm = FluidPackageManager::instance();
         if (fpm) {
            out.thermoConfig = fpm->thermoConfigForPackageResolved(pkgId);
            const QString packageThermoMethod = fpm->thermoMethodIdForPackage(pkgId).trimmed();
            if (!packageThermoMethod.isEmpty()) {
               out.eosMode = "manual";
               out.eosManual = packageThermoMethod.toStdString();
            }
            else {
               out.eosMode = column.eosMode().toStdString();
               out.eosManual = column.eosManual().toStdString();
            }
         }
         else {
            out.eosMode = column.eosMode().toStdString();
            out.eosManual = column.eosManual().toStdString();
         }
      }
      else {
         out.eosMode = column.eosMode().toStdString();
         out.eosManual = column.eosManual().toStdString();
      }

      out.condenserType = column.condenserType().toStdString();
      out.reboilerType = column.reboilerType().toStdString();
      out.condenserSpec = column.condenserSpec().toStdString();
      out.reboilerSpec = column.reboilerSpec().toStdString();

      out.refluxRatio = column.refluxRatio();
      out.boilupRatio = column.boilupRatio();
      out.qcKW = column.qcKW();
      out.qrKW = column.qrKW();
      out.topTsetK = column.topTsetK();
      out.bottomTsetK = column.bottomTsetK();

      out.etaVTop = column.etaVTop();
      out.etaVMid = column.etaVMid();
      out.etaVBot = column.etaVBot();

      out.enableEtaL = column.enableEtaL();
      out.etaLTop = column.etaLTop();
      out.etaLMid = column.etaLMid();
      out.etaLBot = column.etaLBot();

      out.drawSpecs.clear();
      out.drawLabelsByTray1.clear();
      out.attachedStripperSpecs.clear();

      const auto sideDraws = parseSideDrawSpecs(column);
      const auto attachedStrippers = parseAttachedStripperSpecs(column);

      for (const auto& d : sideDraws)
      {
         SolverDrawSpec solverDraw;
         solverDraw.trayIndex0 = d.trayIndex0;
         solverDraw.name = d.name;
         solverDraw.basis = d.basis;
         solverDraw.phase = d.phase;
         solverDraw.value = d.value;

         out.drawSpecs.push_back(std::move(solverDraw));

         if (!d.name.empty())
            out.drawLabelsByTray1[d.trayIndex0 + 1] = d.name;
      }

      out.attachedStripperSpecs = attachedStrippers;

      return true;
   }
}