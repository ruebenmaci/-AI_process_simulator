#pragma once

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QString>
#include <QStringList>

// Bounded run log.
// Prevents unbounded QString growth (Qt CacheOverflowException) by keeping only the
// most recent lines and avoiding repeated QStringList::join on every append.
class RunLogModel : public QAbstractListModel {
  Q_OBJECT
  Q_PROPERTY(QString allText READ allText NOTIFY allTextChanged)

public:
  enum Roles { TextRole = Qt::UserRole + 1 };

  explicit RunLogModel(QObject* parent = nullptr);

  int rowCount(const QModelIndex& parent = QModelIndex()) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  Q_INVOKABLE void clear();

  // Convenience wrappers used by AppState / solver.
  void appendLine(const QString& line);
  void append(const QString& line);
  void appendLines(const QStringList& lines);

  QString allText() const;

signals:
  void allTextChanged();
  void lineAppended(const QString& line);
  // Emitted after clear() so QML views that maintain their own text buffer
  // (via Connections/onLineAppended) can reset immediately.
  void cleared();

private:
  void trimIfNeeded();
  void maybeEmitAllTextChanged();

  QStringList m_lines;

  // Cached concatenated text.
  mutable QString m_allTextCache;
  mutable bool m_allTextDirty = true;

  int m_maxLines = 20000;          // keep last N lines
  int m_maxAllTextChars = 750000; // safety cap for allText cache

  QElapsedTimer m_emitTimer;
  int m_pendingAllTextSignals = 0;
};
