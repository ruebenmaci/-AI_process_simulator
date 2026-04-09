#pragma once
#include <QObject>
#include <QColor>
#include <QString>
#include <QHash>

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme  –  Theme manager exposed to QML as the context property "gAppTheme"
//
// Registered in main.cpp exactly like gDisplaySettings:
//   AppTheme appTheme;
//   engine.rootContext()->setContextProperty("gAppTheme", &appTheme);
//
// Used in QML like:
//   color:  gAppTheme.canvasBg
//   source: Qt.resolvedUrl(gAppTheme.iconPath("Distillation_Column"))
// ─────────────────────────────────────────────────────────────────────────────
class AppTheme : public QObject
{
   Q_OBJECT

      // The active theme name — changing this emits themeChanged() and
      // all the derived property notifiers, which causes QML bindings to update.
      Q_PROPERTY(QString currentTheme READ currentTheme WRITE setCurrentTheme
         NOTIFY themeChanged)

      // ── PFD Canvas ──────────────────────────────────────────────────────────
      Q_PROPERTY(QColor  canvasBg            READ canvasBg            NOTIFY themeChanged)
      Q_PROPERTY(QColor  sheetBg             READ sheetBg             NOTIFY themeChanged)
      Q_PROPERTY(QColor  sheetBorder         READ sheetBorder         NOTIFY themeChanged)

      // ── Grid ────────────────────────────────────────────────────────────────
      Q_PROPERTY(QString gridLineColor       READ gridLineColor       NOTIFY themeChanged)
      Q_PROPERTY(QString gridDotColor        READ gridDotColor        NOTIFY themeChanged)

      // ── Streams ─────────────────────────────────────────────────────────────
      Q_PROPERTY(QString materialStreamColor READ materialStreamColor NOTIFY themeChanged)
      Q_PROPERTY(QString energyStreamColor   READ energyStreamColor   NOTIFY themeChanged)

      // ── Snap / port highlights (constant) ───────────────────────────────────
      Q_PROPERTY(QString snapRingColor       READ snapRingColor       CONSTANT)
      Q_PROPERTY(QString snapDotColor        READ snapDotColor        CONSTANT)
      Q_PROPERTY(QString snapLabelColor      READ snapLabelColor      CONSTANT)
      Q_PROPERTY(QString pendingPortColor    READ pendingPortColor    CONSTANT)

      // ── Title block ─────────────────────────────────────────────────────────
      Q_PROPERTY(QColor  titleBlockBg        READ titleBlockBg        NOTIFY themeChanged)
      Q_PROPERTY(QColor  titleBlockBorder    READ titleBlockBorder    NOTIFY themeChanged)
      Q_PROPERTY(QColor  titleBlockText      READ titleBlockText      NOTIFY themeChanged)
      Q_PROPERTY(QColor  titleBlockLabel     READ titleBlockLabel     NOTIFY themeChanged)

      // ── Unit node ───────────────────────────────────────────────────────────
      Q_PROPERTY(QColor  nodeSelectionBorder READ nodeSelectionBorder NOTIFY themeChanged)
      Q_PROPERTY(QColor  nodeLabelColor      READ nodeLabelColor      NOTIFY themeChanged)

      // ── Status bar ──────────────────────────────────────────────────────────
      Q_PROPERTY(QColor  statusBarBg         READ statusBarBg         NOTIFY themeChanged)
      Q_PROPERTY(QColor  statusBarText       READ statusBarText       NOTIFY themeChanged)

      // ── Equipment Palette ───────────────────────────────────────────────────
      Q_PROPERTY(QColor  palettePanelBg        READ palettePanelBg        NOTIFY themeChanged)
      Q_PROPERTY(QColor  palettePanelBorder    READ palettePanelBorder    NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteTitleBg        READ paletteTitleBg        NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteTitleText      READ paletteTitleText      NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteSectionText    READ paletteSectionText    NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteDivider        READ paletteDivider        NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteItemBgHover    READ paletteItemBgHover    NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteItemBgPressed  READ paletteItemBgPressed  NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteItemBorder     READ paletteItemBorder     NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteItemBorderHover READ paletteItemBorderHover NOTIFY themeChanged)
      Q_PROPERTY(QColor  paletteItemLabelColor READ paletteItemLabelColor NOTIFY themeChanged)
      Q_PROPERTY(QColor  palettePlannedBg      READ palettePlannedBg      NOTIFY themeChanged)
      Q_PROPERTY(QColor  palettePlannedBorder  READ palettePlannedBorder  NOTIFY themeChanged)
      Q_PROPERTY(QColor  palettePlannedText    READ palettePlannedText    NOTIFY themeChanged)

      // ── Toolbar ─────────────────────────────────────────────────────────────
      Q_PROPERTY(QColor  toolbarBg           READ toolbarBg           NOTIFY themeChanged)
      Q_PROPERTY(QColor  toolbarBorder       READ toolbarBorder       NOTIFY themeChanged)

public:
   explicit AppTheme(QObject* parent = nullptr) : QObject(parent) {}

   // ── Theme accessor / mutator ─────────────────────────────────────────────
   QString currentTheme() const { return m_theme; }

   void setCurrentTheme(const QString& theme) {
      if (m_theme == theme) return;
      m_theme = theme;
      emit themeChanged();
   }

   // ── Icon path helpers (callable from QML) ───────────────────────────────
   Q_INVOKABLE QString paletteSvgIconPath(const QString& iconName) const {
      return QStringLiteral("../../icons/svg/2D_Light_Icons/")
         + normalizeIconName(iconName) + QStringLiteral(".svg");
   }

   Q_INVOKABLE QString iconPath(const QString& iconName) const {
      return paletteSvgIconPath(iconName);
   }

   // ── PFD Canvas ──────────────────────────────────────────────────────────
   QColor canvasBg() const {
      if (m_theme == "HYSYS")     return QColor("#2b3828");   // authentic HYSYS dark olive green
      if (m_theme == "AspenPlus") return QColor("#eaeef2");
      return QColor("#2b3a47");
   }
   QColor sheetBg() const {
      if (m_theme == "HYSYS")     return QColor("#2f3d2c");   // slightly lighter olive green sheet
      if (m_theme == "AspenPlus") return QColor("#f5f7f9");
      return QColor("#f5f2eb");
   }
   QColor sheetBorder() const {
      if (m_theme == "HYSYS")     return QColor("#3d5238");   // muted green border
      if (m_theme == "AspenPlus") return QColor("#b0bcc8");
      return QColor("#8f989f");
   }

   // ── Grid ────────────────────────────────────────────────────────────────
   QString gridLineColor() const {
      if (m_theme == "HYSYS")     return "#323f2f";           // subtle dark green grid lines
      if (m_theme == "AspenPlus") return "#d0d8e0";
      return "#ccc8b8";
   }
   QString gridDotColor() const {
      if (m_theme == "HYSYS")     return "#374434";           // slightly lighter green dots
      if (m_theme == "AspenPlus") return "#c0ccd8";
      return "#c4bfae";
   }

   // ── Streams ─────────────────────────────────────────────────────────────
   QString materialStreamColor() const {
      if (m_theme == "HYSYS")     return "#00D4FF";           // HYSYS cyan streams
      if (m_theme == "AspenPlus") return "#003087";
      return "#3a8fd1";
   }
   QString energyStreamColor() const {
      if (m_theme == "HYSYS")     return "#FF8C00";           // HYSYS orange energy streams
      if (m_theme == "AspenPlus") return "#CC0000";
      return "#cc7a00";
   }

   // ── Snap / port (constant) ───────────────────────────────────────────────
   QString snapRingColor()    const { return "#00c080"; }
   QString snapDotColor()     const { return "#00c080"; }
   QString snapLabelColor()   const { return "#00802a"; }
   QString pendingPortColor() const { return "#cc7a00"; }

   // ── Title block ─────────────────────────────────────────────────────────
   QColor titleBlockBg() const {
      if (m_theme == "HYSYS")     return QColor("#232e21");   // darkest green for title block
      if (m_theme == "AspenPlus") return QColor("#e8edf2");
      return QColor("#e8e4d8");
   }
   QColor titleBlockBorder() const {
      if (m_theme == "HYSYS")     return QColor("#4a6040");   // medium green border
      if (m_theme == "AspenPlus") return QColor("#2255A4");
      return QColor("#2a2a2a");
   }
   QColor titleBlockText() const {
      if (m_theme == "HYSYS")     return QColor("#a8c8a0");   // light green text
      if (m_theme == "AspenPlus") return QColor("#1a3a6a");
      return QColor("#1a1a2e");
   }
   QColor titleBlockLabel() const {
      if (m_theme == "HYSYS")     return QColor("#5a7850");   // muted green label
      if (m_theme == "AspenPlus") return QColor("#5577aa");
      return QColor("#4a4a4a");
   }

   // ── Unit node ───────────────────────────────────────────────────────────
   QColor nodeSelectionBorder() const {
      if (m_theme == "HYSYS")     return QColor("#00D4FF");   // cyan selection highlight
      if (m_theme == "AspenPlus") return QColor("#2255A4");
      return QColor("#2f6fa3");
   }
   QColor nodeLabelColor() const {
      if (m_theme == "HYSYS")     return QColor("#c8e0c0");   // light green-tinted label text
      if (m_theme == "AspenPlus") return QColor("#1a3060");
      return QColor("#31404a");
   }

   // ── Status bar ──────────────────────────────────────────────────────────
   QColor statusBarBg() const {
      if (m_theme == "HYSYS")     return QColor("#1c2419");   // very dark green status bar
      if (m_theme == "AspenPlus") return QColor("#dce4ec");
      return QColor("#1a1a2e");
   }
   QColor statusBarText() const {
      if (m_theme == "HYSYS")     return QColor("#7ab87a");   // muted green status text
      if (m_theme == "AspenPlus") return QColor("#1a3060");
      return QColor("#31404a");
   }

   // ── Equipment Palette ───────────────────────────────────────────────────
   QColor palettePanelBg() const {
      if (m_theme == "HYSYS")     return QColor("#232e21");   // dark green palette background
      if (m_theme == "AspenPlus") return QColor("#dce8f4");
      return QColor("#eef2f4");
   }
   QColor palettePanelBorder() const {
      if (m_theme == "HYSYS")     return QColor("#3a4e36");   // green panel border
      if (m_theme == "AspenPlus") return QColor("#7aaad4");
      return QColor("#9aaab5");
   }
   QColor paletteTitleBg() const {
      if (m_theme == "HYSYS")     return QColor("#1a2418");   // darkest green title bar
      if (m_theme == "AspenPlus") return QColor("#2255A4");
      return QColor("#2a3b49");
   }
   QColor paletteTitleText() const {
      if (m_theme == "HYSYS")     return QColor("#7ab87a");   // green-tinted title text
      if (m_theme == "AspenPlus") return QColor("#ffffff");
      return QColor("#dce8f1");
   }
   QColor paletteSectionText() const {
      if (m_theme == "HYSYS")     return QColor("#4a7848");   // muted green section headers
      if (m_theme == "AspenPlus") return QColor("#2255A4");
      return QColor("#5f6d78");
   }
   QColor paletteDivider() const {
      if (m_theme == "HYSYS")     return QColor("#323f2f");   // subtle green divider
      if (m_theme == "AspenPlus") return QColor("#8ab4d8");
      return QColor("#c6d0d7");
   }
   QColor paletteItemBgHover() const {
      if (m_theme == "HYSYS")     return QColor("#2f3d2c");   // lighter green on hover
      if (m_theme == "AspenPlus") return QColor("#c4d8ee");
      return QColor("#dde8f0");
   }
   QColor paletteItemBgPressed() const {
      if (m_theme == "HYSYS")     return QColor("#1f2b1d");   // darker green on press
      if (m_theme == "AspenPlus") return QColor("#aac4e0");
      return QColor("#c8d8e8");
   }
   QColor paletteItemBorder() const {
      if (m_theme == "HYSYS")     return QColor("#3a4e36");   // green item border
      if (m_theme == "AspenPlus") return QColor("#5588c0");
      return QColor("#c6d0d7");
   }
   QColor paletteItemBorderHover() const {
      if (m_theme == "HYSYS")     return QColor("#7ab87a");   // bright green hover border
      if (m_theme == "AspenPlus") return QColor("#2255A4");
      return QColor("#7aaac8");
   }
   QColor paletteItemLabelColor() const {
      if (m_theme == "HYSYS")     return QColor("#a8c8a0");   // light green label text
      if (m_theme == "AspenPlus") return QColor("#1a3060");
      return QColor("#31404a");
   }
   QColor palettePlannedBg() const {
      if (m_theme == "HYSYS")     return QColor("#1f2b1d");   // dark green planned item bg
      if (m_theme == "AspenPlus") return QColor("#e8f0f8");
      return QColor("#f0f3f4");
   }
   QColor palettePlannedBorder() const {
      if (m_theme == "HYSYS")     return QColor("#2e3c2b");   // subtle planned border
      if (m_theme == "AspenPlus") return QColor("#b0c8e0");
      return QColor("#d2d8dc");
   }
   QColor palettePlannedText() const {
      if (m_theme == "HYSYS")     return QColor("#3a5038");   // dim green planned text
      if (m_theme == "AspenPlus") return QColor("#8aaac8");
      return QColor("#9daab2");
   }

   // ── Toolbar ─────────────────────────────────────────────────────────────
   QColor toolbarBg() const {
      if (m_theme == "HYSYS")     return QColor("#181f16");   // very dark green toolbar
      if (m_theme == "AspenPlus") return QColor("#d0dce8");
      return QColor("#0f1720");
   }
   QColor toolbarBorder() const {
      if (m_theme == "HYSYS")     return QColor("#2a3828");   // canvas-matching toolbar border
      if (m_theme == "AspenPlus") return QColor("#8aaac8");
      return QColor("#2a3b49");
   }

signals:
   void themeChanged();

private:
   static QString normalizeIconName(QString iconName) {
      QString key = iconName.trimmed();
      if (key.isEmpty())
         return QStringLiteral("dist_column");

      static const QHash<QString, QString> legacyMap{
         { QStringLiteral("Distillation_Column"), QStringLiteral("dist_column") },
         { QStringLiteral("Material_Stream"),     QStringLiteral("stream_material") },
         { QStringLiteral("Energy_Stream"),       QStringLiteral("stream_energy") },
         { QStringLiteral("Column"),              QStringLiteral("dist_column") },
         { QStringLiteral("Stream"),              QStringLiteral("stream_material") }
      };

      if (legacyMap.contains(key))
         return legacyMap.value(key);

      QString normalized = key.toLower();
      normalized.replace('-', '_');
      normalized.replace(' ', '_');
      while (normalized.contains(QStringLiteral("__")))
         normalized.replace(QStringLiteral("__"), QStringLiteral("_"));
      return normalized;
   }

   QString m_theme{ "Default" };
};