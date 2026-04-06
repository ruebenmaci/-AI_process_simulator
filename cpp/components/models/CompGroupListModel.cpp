#include "components/models/CompGroupListModel.h"

#include "components/ComponentManager.h"

CompGroupListModel::CompGroupListModel(QObject* parent)
    : QAbstractListModel(parent)
{}

int CompGroupListModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid() || !lists_) return 0;
    return static_cast<int>(lists_->size());
}

QVariant CompGroupListModel::data(const QModelIndex& index, int role) const
{
    if (!lists_ || !index.isValid() || index.row() < 0 ||
        index.row() >= static_cast<int>(lists_->size()))
        return {};

    const auto& r = (*lists_)[static_cast<std::size_t>(index.row())];
    const QVariantMap summary = manager_ ? manager_->componentListSummary(r.id) : QVariantMap{};
    switch (role) {
    case IdRole:     return r.id;
    case NameRole:   return r.name;
    case CountRole:  return r.componentIds.size();
    case NotesRole:  return r.notes;
    case SourceRole: return r.source;
    case ListTypeRole: return summary.value(QStringLiteral("listType"), r.listType);
    case SourceFluidNameRole: return summary.value(QStringLiteral("sourceFluidName"), r.sourceFluidName);
    case ResolvedCountRole: return summary.value(QStringLiteral("resolvedComponentCount"), r.componentIds.size());
    case ValidRole: return summary.value(QStringLiteral("valid"), true);
    case StatusTextRole: return summary.value(QStringLiteral("statusText"));
    case MissingCountRole: return summary.value(QStringLiteral("missingComponentCount"), 0);
    case RecordRole: return summary.isEmpty() ? r.toVariantMap() : summary;
    case Qt::DisplayRole: return r.name;
    default: return {};
    }
}

QHash<int, QByteArray> CompGroupListModel::roleNames() const
{
    return {
        { IdRole,     "id"     },
        { NameRole,   "name"   },
        { CountRole,  "count"  },
        { NotesRole,  "notes"  },
        { SourceRole, "source" },
        { ListTypeRole, "listType" },
        { SourceFluidNameRole, "sourceFluidName" },
        { ResolvedCountRole, "resolvedComponentCount" },
        { ValidRole, "valid" },
        { StatusTextRole, "statusText" },
        { MissingCountRole, "missingComponentCount" },
        { RecordRole, "record" }
    };
}

void CompGroupListModel::setLists(const std::vector<sim::ComponentListRecord>* lists)
{
    beginResetModel();
    lists_ = lists;
    endResetModel();
}

void CompGroupListModel::setManager(const ComponentManager* manager)
{
    beginResetModel();
    manager_ = manager;
    endResetModel();
}

void CompGroupListModel::refresh()
{
    beginResetModel();
    endResetModel();
}
