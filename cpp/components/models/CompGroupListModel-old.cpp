#include "components/models/CompGroupListModel.h"

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
    switch (role) {
    case IdRole:     return r.id;
    case NameRole:   return r.name;
    case CountRole:  return r.componentIds.size();
    case NotesRole:  return r.notes;
    case SourceRole: return r.source;
    case RecordRole: return r.toVariantMap();
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
        { RecordRole, "record" }
    };
}

void CompGroupListModel::setLists(const std::vector<sim::ComponentListRecord>* lists)
{
    beginResetModel();
    lists_ = lists;
    endResetModel();
}

void CompGroupListModel::refresh()
{
    beginResetModel();
    endResetModel();
}
