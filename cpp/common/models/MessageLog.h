#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QString>
#include <QVector>

// ─────────────────────────────────────────────────────────────────────────────
// MessageLog
//
// Application-wide chronological trace log. Wired into QML as the context
// property `gMessageLog`. Used by FlowsheetState (connection events,
// save/load, solver summaries) and any other subsystem that needs to surface
// a message to the user.
//
// Design notes
//   - This is the trace half of the HYSYS-style status+trace pair. It is
//     append-only and chronological. The status half (currently-broken units)
//     is exposed by FlowsheetStatusModel, which queries each unit op's
//     connectivityStatus on demand rather than buffering events.
//   - Trace messages are session-scoped; they are NOT persisted to .sim
//     files. Reopening a case starts the trace fresh, matching HYSYS and
//     Aspen Plus conventions.
//   - The log is capped at kMaxRows entries — the oldest are evicted when
//     the cap is exceeded. 500 is enough to cover a long working session
//     without runaway memory use.
//   - The "unread" counters power the flash-on-warn UI behavior. Calling
//     markAllRead() clears them; this is invoked when the bottom panel is
//     expanded so the toggle stops flashing.
//
// Severity levels
//   "info"   — normal events ("flowsheet saved", "mixer_1 solved OK")
//   "warn"   — events the user should review but didn't break anything
//             ("stream_3 was disconnected from heater_1 because…")
//   "error"  — events that left something broken or failed outright
//             ("Save failed: …", "Solver failed: PH flash diverged")
//
// Source tags (free-form strings; common values)
//   "Connection" — bind/unbind events
//   "Solver"     — solve completion summaries
//   "Save"       — save / load events
//   "Validation" — bind-time consistency / cycle / fluid-package checks
//
// Optional unitId
//   When the message references a specific unit (e.g. the "now-broken" unit
//   in a displacement event), the unitId is recorded so the QML panel can
//   click-navigate back to it via FlowsheetState::highlightStream() and
//   selectUnit().
// ─────────────────────────────────────────────────────────────────────────────

struct MessageItem {
    QDateTime timestamp;
    QString   level;        // "info" | "warn" | "error"
    QString   source;       // free-form tag, e.g. "Connection"
    QString   text;
    QString   unitId;       // optional — empty if no specific unit reference
};

class MessageLog : public QAbstractListModel
{
    Q_OBJECT

    // Total row count, exposed so QML can show "N messages" in the header.
    Q_PROPERTY(int messageCount READ messageCount NOTIFY messageCountChanged)

    // Counts of unread messages by severity. The QML toggle button watches
    // these to decide whether to flash and what colour to flash.
    Q_PROPERTY(int unreadInfoCount  READ unreadInfoCount  NOTIFY unreadCountsChanged)
    Q_PROPERTY(int unreadWarnCount  READ unreadWarnCount  NOTIFY unreadCountsChanged)
    Q_PROPERTY(int unreadErrorCount READ unreadErrorCount NOTIFY unreadCountsChanged)

    // True iff there is at least one unread warn or error. The toggle uses
    // this directly to drive the flash animation.
    Q_PROPERTY(bool hasUnreadAttention READ hasUnreadAttention NOTIFY unreadCountsChanged)

public:
    enum Roles {
        TimestampRole = Qt::UserRole + 1,
        LevelRole,
        SourceRole,
        TextRole,
        UnitIdRole,
        TimestampDisplayRole   // pre-formatted "HH:mm:ss" string for display
    };

    static constexpr int kMaxRows = 500;

    explicit MessageLog(QObject* parent = nullptr);

    // Process-wide accessor, set during construction. Mirrors the
    // FlowsheetState::instance() pattern so non-QML C++ code (notably the
    // FlowsheetState bind routines) can post messages without needing the
    // pointer threaded through every API.
    static MessageLog* instance() { return instance_; }

    // ── QAbstractListModel overrides ─────────────────────────────────────────
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // ── Properties ───────────────────────────────────────────────────────────
    int messageCount()        const { return items_.size(); }
    int unreadInfoCount()     const { return unreadInfo_; }
    int unreadWarnCount()     const { return unreadWarn_; }
    int unreadErrorCount()    const { return unreadError_; }
    bool hasUnreadAttention() const { return unreadWarn_ > 0 || unreadError_ > 0; }

    // ── Append APIs (C++ side) ───────────────────────────────────────────────
    // The four-arg overloads are the canonical entry points. Source defaults
    // to empty when omitted; unitId defaults to empty.
    void info (const QString& source, const QString& text, const QString& unitId = QString{});
    void warn (const QString& source, const QString& text, const QString& unitId = QString{});
    void error(const QString& source, const QString& text, const QString& unitId = QString{});

    // ── QML invokables ───────────────────────────────────────────────────────
    Q_INVOKABLE void infoMsg (const QString& source, const QString& text, const QString& unitId = QString{}) { info(source, text, unitId); }
    Q_INVOKABLE void warnMsg (const QString& source, const QString& text, const QString& unitId = QString{}) { warn(source, text, unitId); }
    Q_INVOKABLE void errorMsg(const QString& source, const QString& text, const QString& unitId = QString{}) { error(source, text, unitId); }

    // Returns the unitId for the row at `index`, or empty if out of range.
    // Used by the QML trace panel for click-to-navigate.
    Q_INVOKABLE QString unitIdAt(int index) const;

    // Returns the full message text at `index`, or empty if out of range.
    // Used by the QML embedded-link parser (option 2 click-navigation).
    Q_INVOKABLE QString textAt(int index) const;

    // Clear all unread counters. Called by QML when the panel is expanded so
    // the flash animation stops. Does not modify the message list itself.
    Q_INVOKABLE void markAllRead();

    // Clear the entire log. Provided as a QML invokable for a future "Clear
    // Messages" button; does not bound the trace's session-scoped lifetime.
    Q_INVOKABLE void clearLog();

signals:
    void messageCountChanged();
    void unreadCountsChanged();

    // Emitted on every new message append, with the row index and the
    // severity. Provided so QML can hook auto-scroll-to-end behavior, even
    // when filters or cap-eviction would otherwise mask the change.
    void messageAppended(int row, const QString& level);

private:
    void append_(const QString& level,
                 const QString& source,
                 const QString& text,
                 const QString& unitId);

    QVector<MessageItem> items_;
    int unreadInfo_  = 0;
    int unreadWarn_  = 0;
    int unreadError_ = 0;

    static MessageLog* instance_;
};
