#include "TrayModel.h"

#include <QVariantMap>

TrayModel::TrayModel(QObject* parent)
    : QAbstractListModel(parent) {
  // Start with empty; AppState/sim fills trays.
}

int TrayModel::rowCount(const QModelIndex& parent) const {
  if (parent.isValid()) return 0;
  return static_cast<int>(rows_.size());
}

QVariant TrayModel::data(const QModelIndex& index, int role) const {
  const int i = index.row();
  if (!index.isValid() || i < 0 || i >= static_cast<int>(rows_.size()))
    return {};

  const TrayRow& r = rows_[static_cast<size_t>(i)];

  switch (role) {
    case TrayNumberRole:   return r.trayNumber;
    case TempKRole:        return r.tempK;
    case VaporFracRole:    return r.vaporFrac;
    case VaporFlowRole:    return r.vaporFlow;
    case LiquidFlowRole:   return r.liquidFlow;
    case HasDrawRole:      return r.hasDraw;
    case DrawLabelRole:    return r.drawLabel;
    default:               return {};
  }
}

QHash<int, QByteArray> TrayModel::roleNames() const {
  QHash<int, QByteArray> roles;
  roles[TrayNumberRole] = "trayNumber";
  roles[TempKRole]      = "tempK";
  roles[VaporFracRole]  = "vaporFrac";
  roles[VaporFlowRole]  = "vaporFlow";
  roles[LiquidFlowRole] = "liquidFlow";
  roles[HasDrawRole]    = "hasDraw";
  roles[DrawLabelRole]  = "drawLabel";
  return roles;
}

void TrayModel::clear() {
  if (rows_.empty()) return;
  beginResetModel();
  rows_.clear();
  endResetModel();
}

void TrayModel::resetToDefaults(int trayCount)
{
  if (trayCount < 0) trayCount = 0;
  beginResetModel();
  rows_.clear();
  rows_.resize(static_cast<size_t>(trayCount));
  for (int i = 0; i < trayCount; ++i) {
    rows_[static_cast<size_t>(i)].trayNumber = i + 1; // 1=bottom
    rows_[static_cast<size_t>(i)].tempK = 0.0;
    rows_[static_cast<size_t>(i)].vaporFrac = 0.0;
    rows_[static_cast<size_t>(i)].vaporFlow = 0.0;
    rows_[static_cast<size_t>(i)].liquidFlow = 0.0;
    rows_[static_cast<size_t>(i)].hasDraw = false;
    rows_[static_cast<size_t>(i)].drawLabel.clear();
  }
  endResetModel();
}


static TrayRow makeDefaultRow(int trayIndexZeroBased) {
  TrayRow r;
  r.trayNumber = trayIndexZeroBased + 1;  // 1=bottom
  r.tempK = 0.0;
  r.vaporFrac = 0.0;
  r.vaporFlow = 0.0;
  r.liquidFlow = 0.0;
  r.hasDraw = false;
  r.drawLabel.clear();
  return r;
}

void TrayModel::ensureSize(int requiredSize) {
  const int oldSize = static_cast<int>(rows_.size());
  if (requiredSize <= oldSize) return;

  beginInsertRows(QModelIndex(), oldSize, requiredSize - 1);
  rows_.resize(static_cast<size_t>(requiredSize));
  for (int i = oldSize; i < requiredSize; ++i) {
    rows_[static_cast<size_t>(i)] = makeDefaultRow(i);
  }
  endInsertRows();
}

void TrayModel::setTray(int trayIndexZeroBased, double tempK, double vaporFrac,
                        double vaporFlow, double liquidFlow) {
  if (trayIndexZeroBased < 0) return;
  ensureSize(trayIndexZeroBased + 1);

  TrayRow& r = rows_[static_cast<size_t>(trayIndexZeroBased)];
  r.trayNumber = trayIndexZeroBased + 1;
  r.tempK = tempK;
  r.vaporFrac = vaporFrac;
  r.vaporFlow = vaporFlow;
  r.liquidFlow = liquidFlow;

  const QModelIndex idx = index(trayIndexZeroBased);
  emit dataChanged(idx, idx,
                   {TrayNumberRole, TempKRole, VaporFracRole, VaporFlowRole, LiquidFlowRole});
}

void TrayModel::setTray(int trayIndexZeroBased, double tempK, double vaporFrac,
                     double vaporFlow, double liquidFlow,
                     bool hasDraw, bool unusedFlag1,
                     const QString& drawLabel, bool unusedFlag2)
{
  Q_UNUSED(unusedFlag1);
  Q_UNUSED(unusedFlag2);
  TrayRow row;
  row.trayNumber = trayIndexZeroBased + 1;
  row.tempK = tempK;
  row.vaporFrac = vaporFrac;
  row.vaporFlow = vaporFlow;
  row.liquidFlow = liquidFlow;
  row.hasDraw = hasDraw;
  row.drawLabel = drawLabel;
  setRow(trayIndexZeroBased, row);
}


void TrayModel::setTray(int trayIndexZeroBased, const TrayRow& row) {
  if (trayIndexZeroBased < 0) return;
  ensureSize(trayIndexZeroBased + 1);

  rows_[static_cast<size_t>(trayIndexZeroBased)] = row;
  // Keep numbering consistent with index
  rows_[static_cast<size_t>(trayIndexZeroBased)].trayNumber = trayIndexZeroBased + 1;

  const QModelIndex idx = index(trayIndexZeroBased);
  emit dataChanged(idx, idx);
}

void TrayModel::setRow(int trayIndexZeroBased, const TrayRow& row) {
  setTray(trayIndexZeroBased, row);
}

QVariantMap TrayModel::get(int i) const {
  QVariantMap m;
  if (i < 0 || i >= rowCount()) return m;

  const QModelIndex idx = index(i);
  const auto roles = roleNames();
  for (auto it = roles.constBegin(); it != roles.constEnd(); ++it) {
    m[QString::fromUtf8(it.value())] = data(idx, it.key());
  }
  return m;
}
