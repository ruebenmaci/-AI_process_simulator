#include "FluidPackageListModel.h"

FluidPackageListModel::FluidPackageListModel(QObject* parent)
    : QAbstractListModel(parent)
{}

int FluidPackageListModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid() || !packages_) return 0;
    return static_cast<int>(packages_->size());
}

QVariant FluidPackageListModel::data(const QModelIndex& index, int role) const
{
    if (!packages_ || !index.isValid() ||
        index.row() < 0 || index.row() >= static_cast<int>(packages_->size()))
        return {};

    const auto& p = (*packages_)[static_cast<std::size_t>(index.row())];
    switch (role) {
    case IdRole:              return p.id;
    case NameRole:            return p.name;
    case PropertyMethodRole:  return p.propertyMethod;
    case ComponentListIdRole: return p.componentListId;
    case IsDefaultRole:       return p.isDefault;
    case SourceRole:          return p.source;
    case NotesRole:           return p.notes;
    case TagsRole:            return p.tags;
    case RecordRole:          return p.toVariantMap();
    case Qt::DisplayRole:     return p.name;
    default: return {};
    }
}

QHash<int, QByteArray> FluidPackageListModel::roleNames() const
{
    return {
        { IdRole,              "id"              },
        { NameRole,            "name"            },
        { PropertyMethodRole,  "propertyMethod"  },
        { ComponentListIdRole, "componentListId" },
        { IsDefaultRole,       "isDefault"       },
        { SourceRole,          "source"          },
        { NotesRole,           "notes"           },
        { TagsRole,            "tags"            },
        { RecordRole,          "record"          }
    };
}

void FluidPackageListModel::setPackages(const std::vector<sim::FluidPackageRecord>* packages)
{
    beginResetModel();
    packages_ = packages;
    endResetModel();
}

void FluidPackageListModel::refresh()
{
    beginResetModel();
    endResetModel();
}
