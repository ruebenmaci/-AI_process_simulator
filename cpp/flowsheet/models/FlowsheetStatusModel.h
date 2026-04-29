#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

class FlowsheetState;

// ─────────────────────────────────────────────────────────────────────────────
// FlowsheetStatusModel
//
// Aggregator that walks every unit op in a FlowsheetState and exposes the
// list of those with a non-OK ConnectivityStatus, for the bottom Status
// panel. One row per non-OK unit.
//
// Refresh strategy
//   The model rebuilds in full whenever:
//     - FlowsheetState emits materialConnectionsChanged (covers all
//       bind/unbind events across all unit ops, including indirect ones
//       triggered by stream displacement).
//     - FlowsheetState emits unitCountChanged (units added or removed).
//   Full rebuild is fine for ≤100 units; per-row diffing would be premature
//   optimization. The QML view reissues its delegate creation cycle on
//   beginResetModel/endResetModel without flicker for typical row counts.
//
// Severity surfaced as int matching ConnectivityStatus.severity:
//   0 = OK (never appears in this model — filtered out)
//   2 = Warn
//   3 = Fail
// ─────────────────────────────────────────────────────────────────────────────

struct FlowsheetStatusItem {
    QString unitId;
    QString unitName;
    QString unitType;
    int     severity = 0;
    QString reason;
};

class FlowsheetStatusModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int count           READ count           NOTIFY countChanged)
    Q_PROPERTY(int warnCount       READ warnCount       NOTIFY countChanged)
    Q_PROPERTY(int failCount       READ failCount       NOTIFY countChanged)

    // True iff there are any warn or fail rows. Drives the Status panel's
    // contribution to the toggle-button flash logic. Symmetric with
    // MessageLog::hasUnreadAttention.
    Q_PROPERTY(bool hasAttention   READ hasAttention    NOTIFY countChanged)

public:
    enum Roles {
        UnitIdRole = Qt::UserRole + 1,
        UnitNameRole,
        UnitTypeRole,
        SeverityRole,
        ReasonRole
    };

    explicit FlowsheetStatusModel(FlowsheetState* flowsheet, QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int  count()        const { return items_.size(); }
    int  warnCount()    const;
    int  failCount()    const;
    bool hasAttention() const { return warnCount() > 0 || failCount() > 0; }

    // Returns the unitId for the row at `index`, or empty if out of range.
    // QML status panel uses this for click-navigation (Option 3: highlight
    // + select + open property panel for the clicked unit).
    Q_INVOKABLE QString unitIdAt(int index) const;

signals:
    void countChanged();

public slots:
    // Recomputes the entire list from the current flowsheet state. Public
    // slot so it can be invoked manually from anywhere if needed (e.g. from
    // unit-internal property changes the aggregator doesn't directly observe).
    void refresh();

private:
    FlowsheetState* flowsheet_ = nullptr;
    QVector<FlowsheetStatusItem> items_;
};
