#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVariantMap>
#include <vector>

// A single tray row as displayed in the ColumnView.
struct TrayRow {
   int trayNumber = 0;       // 1=bottom
   double tempK = 0.0;
   double vaporFrac = 0.0;
   double vaporFlow = 0.0;
   double liquidFlow = 0.0;
   bool hasDraw = false;
   QString drawLabel;
   std::vector<double> xLiq;  // liquid mole fractions per component
   std::vector<double> yVap;  // vapor mole fractions per component
};

class TrayModel : public QAbstractListModel {
   Q_OBJECT
public:
   enum Roles {
      TrayNumberRole = Qt::UserRole + 1,
      TempKRole,
      VaporFracRole,
      VaporFlowRole,
      LiquidFlowRole,
      HasDrawRole,
      DrawLabelRole,
      XLiqRole,     // QVariantList of liquid mole fractions
      YVapRole,     // QVariantList of vapor mole fractions
   };

   explicit TrayModel(QObject* parent = nullptr);

   int rowCount(const QModelIndex& parent = QModelIndex()) const override;
   QVariant data(const QModelIndex& index, int role) const override;
   QHash<int, QByteArray> roleNames() const override;

   // Component names (set once after each solve)
   Q_PROPERTY(QStringList componentNames READ componentNames NOTIFY componentNamesChanged)
      QStringList componentNames() const { return componentNames_; }
   void setComponentNames(const QStringList& names);

   // QML helpers
   Q_INVOKABLE int rowCountQml() const { return rowCount(); }
   Q_INVOKABLE QVariantMap get(int i) const;
   Q_INVOKABLE void clear();
   Q_INVOKABLE void resetToDefaults(int trayCount = 32);

signals:
   void componentNamesChanged();

public slots:
   void setTray(int trayIndexZeroBased, double tempK, double vaporFrac,
      double vaporFlow, double liquidFlow);
   // Full setter used by AppState when updating UI rows (extra flags are ignored).
   void setTray(int trayIndexZeroBased, double tempK, double vaporFrac,
      double vaporFlow, double liquidFlow,
      bool hasDraw, bool unusedFlag1,
      const QString& drawLabel, bool unusedFlag2);

   void setTray(int trayIndexZeroBased, const TrayRow& row);
   void setRow(int trayIndexZeroBased, const TrayRow& row);

private:
   void ensureSize(int requiredSize);

   std::vector<TrayRow> rows_;
   QStringList componentNames_;
};