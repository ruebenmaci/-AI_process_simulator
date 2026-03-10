#include "DiagnosticsModel.h"

DiagnosticsModel::DiagnosticsModel(QObject* parent) : QAbstractListModel(parent) {}

int DiagnosticsModel::rowCount(const QModelIndex& parent) const {
  if (parent.isValid()) return 0;
  return items_.size();
}

QVariant DiagnosticsModel::data(const QModelIndex& index, int role) const {
  if (!index.isValid()) return {};
  const int i = index.row();
  if (i < 0 || i >= items_.size()) return {};
  const auto& it = items_[i];
  switch (role) {
    case LevelRole: return it.level;
    case MessageRole: return it.message;
    default: return {};
  }
}

QHash<int, QByteArray> DiagnosticsModel::roleNames() const {
  QHash<int, QByteArray> roles;
  roles[LevelRole] = "level";
  roles[MessageRole] = "message";
  return roles;
}

void DiagnosticsModel::clear() {
  beginResetModel();
  items_.clear();
  endResetModel();
}

void DiagnosticsModel::append(const QString& level, const QString& message) {
  const int n = items_.size();
  beginInsertRows(QModelIndex(), n, n);
  items_.push_back({level, message});
  endInsertRows();
}