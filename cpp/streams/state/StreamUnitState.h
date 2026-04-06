#pragma once

#include "flowsheet/state/ProcessUnitState.h"
#include "streams/state/MaterialStreamState.h"

class StreamUnitState : public ProcessUnitState
{
   Q_OBJECT
      Q_PROPERTY(QObject* stream READ stream CONSTANT)

public:
   explicit StreamUnitState(QObject* parent = nullptr);

   QObject* stream() { return &stream_; }
   MaterialStreamState* streamState() { return &stream_; }
   const MaterialStreamState* streamState() const { return &stream_; }

   // Called by FlowsheetState immediately after construction to assign the
   // default fluid package. Separated from the constructor because
   // FluidPackageManager::instance() may not be ready at construction time.
   Q_INVOKABLE void initializeWithDefaultPackage();

private:
   MaterialStreamState stream_;
};