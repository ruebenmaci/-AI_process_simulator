#pragma once

class QString;
class ColumnUnitState;
class MaterialStreamState;

#include "unitops/column/sim/ColumnSolver.hpp"

namespace ColumnSolveSpecBuilder
{
   bool build(
      const ColumnUnitState& column,
      const MaterialStreamState* feed,
      SolverInputs& out,
      QString* errorMessage = nullptr);
}