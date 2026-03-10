#include "MaterialBalanceModel.h"

#include <QHash>

MaterialBalanceModel::MaterialBalanceModel(QObject* parent) : QAbstractListModel(parent) {
}

int MaterialBalanceModel::rowCount(const QModelIndex& parent) const {
  if (parent.isValid()) return 0;
  return lines_.size();
}

QVariant MaterialBalanceModel::data(const QModelIndex& index, int role) const {
  if (!index.isValid()) return {};
  const int i = index.row();
  if (i < 0 || i >= lines_.size()) return {};
  const auto& l = lines_[i];
  switch (role) {
    case NameRole: return l.name;
    case KgphRole: return l.kgph;
    case FracRole: return l.frac;
    default: return {};
  }
}

QHash<int, QByteArray> MaterialBalanceModel::roleNames() const {
  QHash<int, QByteArray> roles;
  roles[NameRole] = "name";
  roles[KgphRole] = "kgph";
  roles[FracRole] = "frac";
  return roles;
}

void MaterialBalanceModel::reset() {
  beginResetModel();
  lines_.clear();
  feedKgph_ = 0.0;
  totalProductsKgph_ = 0.0;
  totalFrac_ = 0.0;
  balanceErrKgph_ = 0.0;
  endResetModel();
  emit totalsChanged();
}

void MaterialBalanceModel::setFeedKg(double kgph) {
  feedKgph_ = kgph;
  recomputeTotals();
}

void MaterialBalanceModel::setDraw(const QString& name, double kgph) {
  // replace or append by name
  for (int i = 0; i < lines_.size(); ++i) {
    if (lines_[i].name == name) {
      lines_[i].kgph = kgph;
      recomputeTotals();
      const QModelIndex mi = index(i, 0);
      emit dataChanged(mi, mi);
      return;
    }
  }
  const int n = lines_.size();
  beginInsertRows(QModelIndex(), n, n);
  MaterialBalanceLine l;
  l.name = name;
  l.kgph = kgph;
  lines_.push_back(l);
  endInsertRows();
  recomputeTotals();
}

void MaterialBalanceModel::finalize() {
  recomputeTotals();
}

void MaterialBalanceModel::setLines(const std::vector<MaterialBalanceLine>& lines) {
  beginResetModel();
  lines_.clear();
  lines_.reserve(static_cast<int>(lines.size()));
  for (const auto& l : lines) {
    lines_.push_back(MaterialBalanceLine{l.name, l.kgph, l.frac});
  }
  endResetModel();
  recomputeTotals();
}

void MaterialBalanceModel::recomputeTotals() {
  totalProductsKgph_ = 0.0;
  for (auto& l : lines_) {
    totalProductsKgph_ += l.kgph;
  }

  if (feedKgph_ > 0.0) {
    for (auto& l : lines_) {
      l.frac = l.kgph / feedKgph_;
    }
    totalFrac_ = totalProductsKgph_ / feedKgph_;
    balanceErrKgph_ = feedKgph_ - totalProductsKgph_;
  } else {
    for (auto& l : lines_) {
      l.frac = 0.0;
    }
    totalFrac_ = 0.0;
    balanceErrKgph_ = 0.0;
  }

  if (!lines_.isEmpty()) {
    emit dataChanged(index(0,0), index(lines_.size()-1,0));
  }
  emit totalsChanged();
}
