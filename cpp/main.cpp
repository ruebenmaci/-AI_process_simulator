#include <QGuiApplication>
#include <QCoreApplication>
#include <QtQuickControls2/QQuickStyle>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include <QDebug>
#include <windows.h>

#include "unitops/column/state/ColumnUnitState.h"
#include "flowsheet/state/FlowsheetState.h"
#include "components/ComponentManager.h"

# define QT_QML_DEBUG

static void vsMessageHandler(QtMsgType type,
   const QMessageLogContext& ctx, const QString& msg)
{
   Q_UNUSED(type);

   QString context;
   if (ctx.file) {
      context = QString(" (%1:%2)").arg(ctx.file).arg(ctx.line);
   }

   const QString out = msg + context + "\n";

   // Visual Studio Output window
   OutputDebugStringW(reinterpret_cast<LPCWSTR>(out.utf16()));

   // Also stderr (useful if you run from a terminal)
   fprintf(stderr, "%s", out.toLocal8Bit().constData());
}

int main(int argc, char *argv[]) {
  qInstallMessageHandler(vsMessageHandler);

  // Use a non-native Controls style so background/indicator customization works
  QQuickStyle::setStyle("Fusion");

  QGuiApplication app(argc, argv);

  QQmlApplicationEngine engine;

  ComponentManager componentManager;
  engine.rootContext()->setContextProperty("gComponentManager", &componentManager);

  ColumnUnitState state;
  engine.rootContext()->setContextProperty("appState", &state);
  engine.rootContext()->setContextProperty("gAppState", &state);

  FlowsheetState flowsheet;
  engine.rootContext()->setContextProperty("gFlowsheet", &flowsheet);

  const QUrl url(QStringLiteral("qrc:/qt/qml/chatgpt5_qt_adt_simulator/qml/Main.qml"));
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreated, &app,
      [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
          QCoreApplication::exit(-1);
      },
      Qt::QueuedConnection);

  // This loads Main.qml from the qt_add_qml_module URI
  engine.loadFromModule("ChatGPT5.ADT", "Main");

  if (engine.rootObjects().isEmpty()) {
     qDebug() << "Failed to load QML from module";
     return -1;
  }

  return app.exec();
}