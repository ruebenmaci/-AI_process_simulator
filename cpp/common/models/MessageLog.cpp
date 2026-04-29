#include "MessageLog.h"

MessageLog* MessageLog::instance_ = nullptr;

MessageLog::MessageLog(QObject* parent)
    : QAbstractListModel(parent)
{
    instance_ = this;
}

// ─────────────────────────────────────────────────────────────────────────────
// QAbstractListModel
// ─────────────────────────────────────────────────────────────────────────────

int MessageLog::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid()) return 0;
    return items_.size();
}

QVariant MessageLog::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= items_.size())
        return {};

    const MessageItem& m = items_[index.row()];

    switch (role) {
    case TimestampRole:        return m.timestamp;
    case LevelRole:            return m.level;
    case SourceRole:           return m.source;
    case TextRole:             return m.text;
    case UnitIdRole:           return m.unitId;
    case TimestampDisplayRole: return m.timestamp.toString(QStringLiteral("HH:mm:ss"));
    default:                   return {};
    }
}

QHash<int, QByteArray> MessageLog::roleNames() const
{
    QHash<int, QByteArray> r;
    r[TimestampRole]        = "timestamp";
    r[LevelRole]            = "level";
    r[SourceRole]           = "source";
    r[TextRole]             = "text";
    r[UnitIdRole]           = "unitId";
    r[TimestampDisplayRole] = "timestampDisplay";
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// Append
//
// The cap-eviction logic is non-trivial: when we're at kMaxRows and need to
// evict the oldest before appending, we must do beginRemoveRows / endRemove-
// Rows around the eviction AND beginInsertRows / endInsertRows around the
// append. Mixing the two into a single emit would lie about the model's row
// numbering and break QML view bindings.
//
// Unread accounting:
//   - "info" appends increment unreadInfo_ but never trigger flashing.
//   - "warn" / "error" appends increment their counters and feed the flash.
//   - Eviction does NOT decrement unread counts. Eviction is bounded
//     scrollback, not user acknowledgment — if a user has 500 unread
//     warnings and 10 more arrive, they still have unread warnings, even
//     if the oldest 10 fall out of the buffer.
// ─────────────────────────────────────────────────────────────────────────────

void MessageLog::append_(const QString& level,
                         const QString& source,
                         const QString& text,
                         const QString& unitId)
{
    if (items_.size() >= kMaxRows) {
        beginRemoveRows(QModelIndex(), 0, 0);
        items_.removeFirst();
        endRemoveRows();
    }

    MessageItem m;
    m.timestamp = QDateTime::currentDateTime();
    m.level     = level;
    m.source    = source;
    m.text      = text;
    m.unitId    = unitId;

    const int row = items_.size();
    beginInsertRows(QModelIndex(), row, row);
    items_.append(m);
    endInsertRows();

    if      (level == QStringLiteral("error")) ++unreadError_;
    else if (level == QStringLiteral("warn"))  ++unreadWarn_;
    else                                       ++unreadInfo_;

    emit messageCountChanged();
    emit unreadCountsChanged();
    emit messageAppended(row, level);
}

void MessageLog::info(const QString& source, const QString& text, const QString& unitId)
{
    append_(QStringLiteral("info"), source, text, unitId);
}

void MessageLog::warn(const QString& source, const QString& text, const QString& unitId)
{
    append_(QStringLiteral("warn"), source, text, unitId);
}

void MessageLog::error(const QString& source, const QString& text, const QString& unitId)
{
    append_(QStringLiteral("error"), source, text, unitId);
}

// ─────────────────────────────────────────────────────────────────────────────
// QML invokables
// ─────────────────────────────────────────────────────────────────────────────

QString MessageLog::unitIdAt(int index) const
{
    if (index < 0 || index >= items_.size()) return {};
    return items_[index].unitId;
}

QString MessageLog::textAt(int index) const
{
    if (index < 0 || index >= items_.size()) return {};
    return items_[index].text;
}

void MessageLog::markAllRead()
{
    if (unreadInfo_ == 0 && unreadWarn_ == 0 && unreadError_ == 0)
        return;
    unreadInfo_  = 0;
    unreadWarn_  = 0;
    unreadError_ = 0;
    emit unreadCountsChanged();
}

void MessageLog::clearLog()
{
    if (items_.isEmpty() && unreadInfo_ == 0 && unreadWarn_ == 0 && unreadError_ == 0)
        return;

    beginResetModel();
    items_.clear();
    unreadInfo_  = 0;
    unreadWarn_  = 0;
    unreadError_ = 0;
    endResetModel();

    emit messageCountChanged();
    emit unreadCountsChanged();
}
