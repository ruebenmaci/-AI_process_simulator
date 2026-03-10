#pragma once

#include <QAbstractListModel>
#include <QVector>

struct DiagnosticItem {
  QString level;
  QString message;
};

class DiagnosticsModel : public QAbstractListModel {
  Q_OBJECT
public:
  enum Roles { LevelRole = Qt::UserRole + 1, MessageRole };

  explicit DiagnosticsModel(QObject* parent = nullptr);

  int rowCount(const QModelIndex& parent = QModelIndex()) const override;
  QVariant data(const QModelIndex& index, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

  Q_INVOKABLE void clear();
  Q_INVOKABLE void append(const QString& level, const QString& message);
  Q_INVOKABLE void info(const QString& message) { append("info", message); }
  Q_INVOKABLE void warn(const QString& message) { append("warn", message); }
  Q_INVOKABLE void error(const QString& message) { append("error", message); }

private:
  QVector<DiagnosticItem> items_;
};
