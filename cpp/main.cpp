#include <QGuiApplication>
#include <QCoreApplication>
#include <QtQuickControls2/QQuickStyle>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSettings>
#include <QObject>
#include <QStringList>
#include <QStandardPaths>
#include <QDir>
#include <QUrl>

#include <QDebug>
#include <windows.h>
#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")
#include <QWindow>
#include <QClipboard>

#include "unitops/column/state/ColumnUnitState.h"
#include "flowsheet/state/FlowsheetState.h"
#include "components/ComponentManager.h"
#include "fluid/FluidPackageManager.h"
#include "AppTheme.h"

#include "units/UnitRegistry.h"
#include "units/FormatRegistry.h"

# define QT_QML_DEBUG

// ── Display settings exposed to QML ───────────────────────────────────────────
class DisplaySettings : public QObject
{
   Q_OBJECT
      Q_PROPERTY(double scaleFactor   READ scaleFactor   WRITE setScaleFactor   NOTIFY scaleFactorChanged)
      Q_PROPERTY(QStringList presets  READ presets       CONSTANT)
      Q_PROPERTY(QString restartNote  READ restartNote   CONSTANT)

public:
   explicit DisplaySettings(QObject* parent = nullptr) : QObject(parent)
   {
      QSettings s("AIProcessSimulator", "DisplaySettings");
      m_scaleFactor = s.value("scaleFactor", 1.0).toDouble();
   }

   double scaleFactor() const { return m_scaleFactor; }

   void setScaleFactor(double v) {
      if (qFuzzyCompare(m_scaleFactor, v)) return;
      m_scaleFactor = v;
      QSettings s("AIProcessSimulator", "DisplaySettings");
      s.setValue("scaleFactor", v);
      emit scaleFactorChanged();
   }

   // Handy preset labels shown in a ComboBox
   QStringList presets() const {
      return { "100%  (native)", "110%", "125%", "150%", "175%", "200%" };
   }

   // Corresponding numeric values — called from QML by preset index
   Q_INVOKABLE double presetValue(int index) const {
      static const double vals[] = { 1.0, 1.1, 1.25, 1.5, 1.75, 2.0 };
      if (index < 0 || index >= 6) return 1.0;
      return vals[index];
   }

   // Returns the preset index that best matches the current scale factor
   Q_INVOKABLE int currentPresetIndex() const {
      static const double vals[] = { 1.0, 1.1, 1.25, 1.5, 1.75, 2.0 };
      for (int i = 0; i < 6; ++i)
         if (qAbs(vals[i] - m_scaleFactor) < 0.01) return i;
      return -1;  // custom value
   }

   QString restartNote() const {
      return "Scale change takes effect after restarting the application.";
   }

signals:
   void scaleFactorChanged();

private:
   double m_scaleFactor = 1.0;
};

// ── Message handler ────────────────────────────────────────────────────────────
static void vsMessageHandler(QtMsgType type,
   const QMessageLogContext& ctx, const QString& msg)
{
   Q_UNUSED(type);
   QString context;
   if (ctx.file)
      context = QString(" (%1:%2)").arg(ctx.file).arg(ctx.line);
   const QString out = msg + context + "\n";
   OutputDebugStringW(reinterpret_cast<LPCWSTR>(out.utf16()));
   fprintf(stderr, "%s", out.toLocal8Bit().constData());
}

// ── Set OS title bar color to match window background (#dde4e8) ──────────────
static void applyTitleBarColor(QWindow* window)
{
   if (!window) return;
   const HWND hwnd = reinterpret_cast<HWND>(window->winId());
   if (!hwnd) return;
   // #dde4e8 = R=221 G=228 B=232  (COLORREF is 0x00BBGGRR)
   const COLORREF captionColor = RGB(221, 228, 232);
   DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR,
      &captionColor, sizeof(captionColor));
}

class ClipboardHelper : public QObject
{
   Q_OBJECT
public:
   explicit ClipboardHelper(QObject* parent = nullptr) : QObject(parent) {}

   Q_INVOKABLE void setText(const QString& text)
   {
      if (auto* cb = QGuiApplication::clipboard())
         cb->setText(text, QClipboard::Clipboard);
   }

   Q_INVOKABLE QString text() const
   {
      if (auto* cb = QGuiApplication::clipboard())
         return cb->text(QClipboard::Clipboard);
      return QString();
   }
};

// ── main ──────────────────────────────────────────────────────────────────────
int main(int argc, char* argv[]) {
   qInstallMessageHandler(vsMessageHandler);

   // Read saved scale factor BEFORE QGuiApplication is constructed —
   // QT_SCALE_FACTOR must be set before the application object exists.
   {
      QSettings s("AIProcessSimulator", "DisplaySettings");
      double sf = s.value("scaleFactor", 1.0).toDouble();
      if (sf < 0.5 || sf > 4.0) sf = 1.0;  // clamp sanity check
      qputenv("QT_SCALE_FACTOR", QString::number(sf, 'f', 2).toUtf8());
   }

   QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
      Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

   QQuickStyle::setStyle("Fusion");

   QGuiApplication app(argc, argv);

   QQmlApplicationEngine engine;

   UnitRegistry* gUnits = new UnitRegistry(&engine);
   FormatRegistry* gFormats = new FormatRegistry(&engine);

   // Mutual injection — required so format() and unitOptionsFor() can
   // see each other's registry without going through the QML context.
   // qmlEngine(this) returns nullptr for QObjects parented in C++,
   // so explicit injection is the only path that works reliably.

   gUnits->setFormatRegistry(gFormats);
   gFormats->setUnitRegistry(gUnits);

   engine.rootContext()->setContextProperty("gUnits",   gUnits);
   engine.rootContext()->setContextProperty("gFormats", gFormats);

   // (Optional) restore the active Unit Set from QSettings:
   //
   //   QSettings settings;
   //   QString lastSet = settings.value("units/activeSet", "SI").toString();
   //   gUnits->setActiveUnitSet(lastSet);
   //
   // And on shutdown:
   //
   //   QObject::connect(&app, &QGuiApplication::aboutToQuit, [&]() {
   //       QSettings s;
   //       s.setValue("units/activeSet", gUnits->activeUnitSet());
   //   });

   ClipboardHelper clipboardHelper;
   engine.rootContext()->setContextProperty("gClipboard", &clipboardHelper);

   // Expose display settings to QML
   DisplaySettings displaySettings;
   engine.rootContext()->setContextProperty("gDisplaySettings", &displaySettings);

   AppTheme appTheme;
   engine.rootContext()->setContextProperty("gAppTheme", &appTheme);

   ComponentManager componentManager;
   QObject::connect(&componentManager, &ComponentManager::errorOccurred, [](const QString& msg) {
      qWarning() << "[ComponentManager]" << msg;
      });
   qDebug() << "[ComponentManager]" << componentManager.lastLoadStatus();
   engine.rootContext()->setContextProperty("gComponentManager", &componentManager);

   FluidPackageManager fluidPackageManager;
   QObject::connect(&fluidPackageManager, &FluidPackageManager::errorOccurred, [](const QString& msg) {
      qWarning() << "[FluidPackageManager]" << msg;
      });
   qDebug() << "[FluidPackageManager]" << fluidPackageManager.lastStatus();
   engine.rootContext()->setContextProperty("gFluidPackageManager", &fluidPackageManager);

   // ── Persistence: resolve writable app-data directory ──────────────────────
   // Both managers auto-save on every change signal so the user never needs
   // to click a "Save" button on the manager windows themselves.
   const QString appDataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
   QDir().mkpath(appDataDir);

   const QString componentListsPath = appDataDir + QStringLiteral("/user_component_lists.json");
   const QString fluidPackagesPath = appDataDir + QStringLiteral("/fluid_packages.json");

   // Merge saved user component lists on startup. The starter seed (components
   // + starter lists) is already loaded by the ComponentManager constructor;
   // this overlays only the user-created lists on top without touching the seed.
   if (QFile::exists(componentListsPath)) {
      if (!componentManager.mergeUserListsFromJsonFile(componentListsPath))
         qWarning() << "[ComponentManager] Failed to load user lists from" << componentListsPath;
      else
         qDebug() << "[ComponentManager] Loaded user lists from" << componentListsPath;
   }

   // Load saved fluid packages on startup; if none exist yet, starters are
   // already present from FluidPackageManager construction.
   if (QFile::exists(fluidPackagesPath)) {
      if (!fluidPackageManager.loadFromJsonFile(fluidPackagesPath))
         qWarning() << "[FluidPackageManager] Failed to load packages from" << fluidPackagesPath;
      else
         qDebug() << "[FluidPackageManager] Loaded packages from" << fluidPackagesPath;
   }

   // Auto-save user component lists whenever lists change.
   // Uses saveUserListsToJsonFile so starter lists are never written to the
   // user file — they are always reconstructed from the embedded seed.
   QObject::connect(&componentManager, &ComponentManager::componentListsChanged,
      [&componentManager, componentListsPath]() {
         if (!componentManager.saveUserListsToJsonFile(componentListsPath))
            qWarning() << "[ComponentManager] Auto-save failed:" << componentListsPath;
      });

   // Auto-save FluidPackageManager whenever packages change.
   QObject::connect(&fluidPackageManager, &FluidPackageManager::fluidPackagesChanged,
      [&fluidPackageManager, fluidPackagesPath]() {
         if (!fluidPackageManager.saveToJsonFile(fluidPackagesPath))
            qWarning() << "[FluidPackageManager] Auto-save failed:" << fluidPackagesPath;
      });

   ColumnUnitState state;
   engine.rootContext()->setContextProperty("appState", &state);
   engine.rootContext()->setContextProperty("gAppState", &state);

   FlowsheetState flowsheet;
   engine.rootContext()->setContextProperty("gFlowsheet", &flowsheet);

   // ── Saves folder: <project root>/saves ───────────────────────────────────
   // Exe lives at <root>/out/build/x64-release/ — walk up 3 levels to get root.
   // Falls back to exe dir if the walk-up path doesn't look right.
   const QDir exeDir(QCoreApplication::applicationDirPath());
   const QString projectRoot = QDir::cleanPath(exeDir.absoluteFilePath(QStringLiteral("../../..")));
   const QString savesDir = projectRoot + QStringLiteral("/saves");
   QDir().mkpath(savesDir);
   engine.rootContext()->setContextProperty("gSavesPath", QUrl::fromLocalFile(savesDir));

   // When any fluid package property changes (thermo method, component list
   // assignment, name) OR when a component list's membership changes,
   // FluidPackageManager re-emits fluidPackagesChanged. So one connection
   // here covers both cases — refresh all streams so they immediately pick up
   // the new EOS, component set, and flash results.
   QObject::connect(&fluidPackageManager, &FluidPackageManager::fluidPackagesChanged,
      [&flowsheet]() {
         flowsheet.refreshStreamsForPackage(QString());
      });

   const QUrl url(QStringLiteral("qrc:/qt/qml/chatgpt5_qt_adt_simulator/qml/Main.qml"));
   QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreated, &app,
      [url](QObject* obj, const QUrl& objUrl) {
         if (!obj && url == objUrl) {
            QCoreApplication::exit(-1);
            return;
         }
         // Apply custom title bar color once the window is created
         if (obj && url == objUrl) {
            if (auto* win = qobject_cast<QWindow*>(obj))
               applyTitleBarColor(win);
         }
      },
      Qt::QueuedConnection);

   engine.loadFromModule("ChatGPT5.ADT", "Main");
   //engine.loadFromModule("ChatGPT5.ADT", "PGroupBoxTest");

   if (engine.rootObjects().isEmpty()) {
      qDebug() << "Failed to load QML from module";
      return -1;
   }

   return app.exec();
}

#include "main.moc"