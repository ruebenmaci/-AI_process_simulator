#pragma once

#include <QAbstractListModel>
#include <QVector>

struct MaterialBalanceLine {
  QString name;
  double kgph = 0.0;
  double frac = 0.0; // kgph / feedKgph
};

class MaterialBalanceModel : public QAbstractListModel {
  Q_OBJECT
  Q_PROPERTY(double feedKgph READ feedKgph NOTIFY totalsChanged)
  Q_PROPERTY(double totalProductsKgph READ totalProductsKgph NOTIFY totalsChanged)
  Q_PROPERTY(double totalFrac READ totalFrac NOTIFY totalsChanged)
  Q_PROPERTY(double balanceErrKgph READ balanceErrKgph NOTIFY totalsChanged)

public:
  enum Roles {
    NameRole = Qt::UserRole + 1,
    KgphRole,
    FracRole
  };

  explicit MaterialBalanceModel(QObject* parent = nullptr);

  int rowCount(const QModelIndex& parent = QModelIndex()) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  // Used by AppState
  Q_INVOKABLE void reset();
  Q_INVOKABLE void setFeedKg(double kgph);
  Q_INVOKABLE void setDraw(const QString& name, double kgph);
  Q_INVOKABLE void finalize();

  // Utility
  void setLines(const std::vector<MaterialBalanceLine>& lines);

  double feedKgph() const { return feedKgph_; }
  double totalProductsKgph() const { return totalProductsKgph_; }
  double totalFrac() const { return totalFrac_; }
  double balanceErrKgph() const { return balanceErrKgph_; }

signals:
  void totalsChanged();

private:
  void recomputeTotals();

  QVector<MaterialBalanceLine> lines_;
  double feedKgph_ = 0.0;
  double totalProductsKgph_ = 0.0;
  double totalFrac_ = 0.0;
  double balanceErrKgph_ = 0.0;
};
