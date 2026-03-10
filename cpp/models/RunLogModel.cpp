#include "RunLogModel.h"

#include <QDebug>

RunLogModel::RunLogModel(QObject* parent) : QAbstractListModel(parent) {
  m_emitTimer.start();
}

int RunLogModel::rowCount(const QModelIndex& parent) const {
  if (parent.isValid()) return 0;
  return m_lines.size();
}

QVariant RunLogModel::data(const QModelIndex& index, int role) const {
  if (!index.isValid()) return {};
  const int row = index.row();
  if (row < 0 || row >= m_lines.size()) return {};

  switch (role) {
    case Qt::DisplayRole:
    case TextRole:
      return m_lines.at(row);
    default:
      return {};
  }
}

QHash<int, QByteArray> RunLogModel::roleNames() const {
  QHash<int, QByteArray> roles;
  roles[TextRole] = "text";
  return roles;
}

void RunLogModel::clear() {
  beginResetModel();
  m_lines.clear();
  endResetModel();
  m_allTextCache.clear();
  m_allTextDirty = true;
  m_pendingAllTextSignals = 0;
  m_emitTimer.restart();
  emit allTextChanged();
  emit cleared();
}

void RunLogModel::appendLine(const QString& line) {
   append(line);
}

void RunLogModel::appendLines(const QStringList& lines) {
  if (lines.isEmpty()) return;

  // Filter empty lines (preserve ordering).
  QStringList filtered;
  filtered.reserve(lines.size());
  for (const auto& s : lines) {
    if (!s.isEmpty()) filtered.append(s);
  }
  if (filtered.isEmpty()) return;

  const int first = m_lines.size();
  const int last = first + filtered.size() - 1;
  beginInsertRows(QModelIndex(), first, last);
  m_lines.append(filtered);
  endInsertRows();

  trimIfNeeded();
  m_allTextDirty = true;

  // Preserve the existing signal behavior (best-effort): emit once with the last line.
  emit lineAppended(filtered.back());
  maybeEmitAllTextChanged();
}

void RunLogModel::append(const QString& line) {
  if (line.isEmpty()) return;

  // Add line
  const int insertRow = m_lines.size();
  beginInsertRows(QModelIndex(), insertRow, insertRow);
  m_lines.append(line);
  endInsertRows();

  // Bounded storage
  trimIfNeeded();

  // Mark cache dirty (but don't rebuild giant strings here).
  m_allTextDirty = true;

  emit lineAppended(line);
  maybeEmitAllTextChanged();
}

void RunLogModel::trimIfNeeded() {
  if (m_lines.size() <= m_maxLines) return;

  const int extra = m_lines.size() - m_maxLines;
  beginRemoveRows(QModelIndex(), 0, extra - 1);
  for (int i = 0; i < extra; ++i)
      m_lines.removeFirst();
  endRemoveRows();

  m_allTextDirty = true;
}

void RunLogModel::maybeEmitAllTextChanged() {
  // Throttle allTextChanged so QML bindings don't force constant joins.
  // Emit at most ~10 times/sec or every 50 new lines, whichever comes first.
  ++m_pendingAllTextSignals;

  const qint64 ms = m_emitTimer.elapsed();
  if (ms >= 100 || m_pendingAllTextSignals >= 50) {
    m_emitTimer.restart();
    m_pendingAllTextSignals = 0;
    emit allTextChanged();
  }
}

QString RunLogModel::allText() const {
  if (!m_allTextDirty) return m_allTextCache;

  // Join bounded lines.
  QString joined = m_lines.join("\n");

  // Safety cap for huge allocations (should rarely trigger thanks to m_maxLines).
  if (joined.size() > m_maxAllTextChars) {
    joined = joined.right(m_maxAllTextChars);
  }

  m_allTextCache = std::move(joined);
  m_allTextDirty = false;
  return m_allTextCache;
}
