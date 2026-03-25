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

private:
    MaterialStreamState stream_;
};
