
#include "ProcessUnitState.h"

ProcessUnitState::ProcessUnitState(QObject* parent)
    : QObject(parent)
{
}

void ProcessUnitState::setDisplayName(const QString& v)
{
    if (displayName_ == v) return;
    displayName_ = v;
    emit displayNameChanged();
}
