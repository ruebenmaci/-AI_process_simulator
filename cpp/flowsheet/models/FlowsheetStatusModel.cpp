#include "FlowsheetStatusModel.h"

#include "flowsheet/state/FlowsheetState.h"
#include "flowsheet/state/ProcessUnitState.h"

FlowsheetStatusModel::FlowsheetStatusModel(FlowsheetState* flowsheet, QObject* parent)
    : QAbstractListModel(parent)
    , flowsheet_(flowsheet)
{
    if (flowsheet_) {
        // Refresh on any connection change anywhere in the flowsheet —
        // bind/unbind, displacement, dynamic-port shrink. This single signal
        // covers the case where a stream is moved from heater_1's product
        // to mixer_2's inlet (heater_1's connectivityStatus drops to Fail
        // simultaneously with the displacement).
        connect(flowsheet_, &FlowsheetState::materialConnectionsChanged,
                this, &FlowsheetStatusModel::refresh);

        // Refresh on unit add/delete — needed because a brand-new unit
        // typically has missing connections, so it should appear in the
        // panel immediately on creation, and a deleted unit should
        // disappear from it immediately.
        connect(flowsheet_, &FlowsheetState::unitCountChanged,
                this, &FlowsheetStatusModel::refresh);
    }

    // Initial population.
    refresh();
}

// ─────────────────────────────────────────────────────────────────────────────
// QAbstractListModel
// ─────────────────────────────────────────────────────────────────────────────

int FlowsheetStatusModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid()) return 0;
    return items_.size();
}

QVariant FlowsheetStatusModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= items_.size())
        return {};

    const FlowsheetStatusItem& it = items_[index.row()];
    switch (role) {
    case UnitIdRole:   return it.unitId;
    case UnitNameRole: return it.unitName;
    case UnitTypeRole: return it.unitType;
    case SeverityRole: return it.severity;
    case ReasonRole:   return it.reason;
    default:           return {};
    }
}

QHash<int, QByteArray> FlowsheetStatusModel::roleNames() const
{
    QHash<int, QByteArray> r;
    r[UnitIdRole]   = "unitId";
    r[UnitNameRole] = "unitName";
    r[UnitTypeRole] = "unitType";
    r[SeverityRole] = "severity";
    r[ReasonRole]   = "reason";
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// Properties (computed on demand — list is small enough that scanning is cheap)
// ─────────────────────────────────────────────────────────────────────────────

int FlowsheetStatusModel::warnCount() const
{
    int n = 0;
    for (const auto& it : items_)
        if (it.severity == 2) ++n;
    return n;
}

int FlowsheetStatusModel::failCount() const
{
    int n = 0;
    for (const auto& it : items_)
        if (it.severity == 3) ++n;
    return n;
}

QString FlowsheetStatusModel::unitIdAt(int index) const
{
    if (index < 0 || index >= items_.size()) return {};
    return items_[index].unitId;
}

// ─────────────────────────────────────────────────────────────────────────────
// Refresh
//
// Full rebuild from current flowsheet state. Streams are skipped (they don't
// have connectivity-completeness — they're either bound or not, and that's
// surfaced via the unit op they're connected to).
//
// Sort order is by severity descending (Fail rows first, then Warn), with
// units of equal severity in flowsheet creation order. This way the most
// urgent problems are at the top of the panel.
// ─────────────────────────────────────────────────────────────────────────────
void FlowsheetStatusModel::refresh()
{
    if (!flowsheet_) {
        if (!items_.isEmpty()) {
            beginResetModel();
            items_.clear();
            endResetModel();
            emit countChanged();
        }
        return;
    }

    QVector<FlowsheetStatusItem> newItems;
    const QStringList ids = flowsheet_->allUnitIds();
    for (const QString& id : ids) {
        ProcessUnitState* unit = flowsheet_->findUnitById(id);
        if (!unit) continue;

        // Skip stream nodes — they aren't unit ops with connectivity rules.
        // Streams contribute to unit-op statuses indirectly.
        if (unit->type() == QStringLiteral("stream")) continue;

        const ConnectivityStatus s = unit->connectivityStatus();
        if (s.severity == 0) continue;   // OK — not surfaced

        FlowsheetStatusItem item;
        item.unitId   = id;
        item.unitName = unit->name();
        item.unitType = unit->type();
        item.severity = s.severity;
        item.reason   = s.reason;
        newItems.push_back(item);
    }

    // Stable sort: Fail (3) before Warn (2), preserving creation order
    // within each severity class.
    std::stable_sort(newItems.begin(), newItems.end(),
        [](const FlowsheetStatusItem& a, const FlowsheetStatusItem& b) {
            return a.severity > b.severity;
        });

    // Replace contents. beginResetModel/endResetModel is heavier than
    // begin/endRemove + begin/endInsert, but flicker-free for ≤100 rows
    // and dramatically simpler than diffing.
    beginResetModel();
    items_ = std::move(newItems);
    endResetModel();
    emit countChanged();
}
