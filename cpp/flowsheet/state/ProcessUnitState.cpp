
#include "ProcessUnitState.h"

#include <QRegularExpression>

ProcessUnitState::ProcessUnitState(QObject* parent)
    : QObject(parent)
    , guid_(QUuid::createUuid().toString(QUuid::WithoutBraces))
{
}

void ProcessUnitState::setName(const QString& v)
{
    QString normalized = v.trimmed();
    normalized.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("_"));
    normalized.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9_\\-.]")));
    if (normalized.size() > 100)
        normalized = normalized.left(100);
    if (normalized.isEmpty())
        normalized = id_.isEmpty() ? QStringLiteral("unit") : id_;

    if (name_ == normalized)
        return;

    name_ = normalized;
    emit nameChanged();
    emit displayNameChanged();
}
