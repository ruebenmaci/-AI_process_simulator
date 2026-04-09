pragma Singleton
import QtQuick 2.15

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme  –  Central theme singleton for the AI Process Simulator
//
// Usage anywhere in QML:
//   import "." as Local          (or whatever relative path reaches this file)
//   color: AppTheme.canvasBg
//   source: AppTheme.iconPath("Distillation_Column")
//
// Add to CMakeLists qt_add_qml_module SOURCES list and register as singleton:
//   QML_SINGLETON in the qmldir, or via the pragma above.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // ── Active theme  ("Default" | "HYSYS" | "AspenPlus") ────────────────
    property string currentTheme: "Default"

    // ── Icon helpers ──────────────────────────────────────────────────────
    function normalizeIconName(iconName) {
        if (!iconName || iconName === "")
            return "dist_column"

        const legacyMap = {
            "Distillation_Column": "dist_column",
            "Material_Stream": "stream_material",
            "Energy_Stream": "stream_energy",
            "Column": "dist_column",
            "Stream": "stream_material"
        }

        if (legacyMap[iconName] !== undefined)
            return legacyMap[iconName]

        return iconName.toLowerCase().replace(/[-\s]+/g, "_")
    }

    function paletteSvgIconPath(iconName) {
        return "../../icons/svg/2D_Light_Icons/" + normalizeIconName(iconName) + ".svg"
    }

    function iconPath(iconName) {
        return paletteSvgIconPath(iconName)
    }

    // ── PFD Canvas ────────────────────────────────────────────────────────
    // HYSYS uses the classic dark olive-green PFD canvas colour
    readonly property color canvasBg: {
        if (currentTheme === "HYSYS")     return "#2b3828"   // authentic HYSYS dark olive green
        if (currentTheme === "AspenPlus") return "#eaeef2"
        return "#2b3a47"          // Default (dark slate)
    }

    // The inner drawing sheet
    readonly property color sheetBg: {
        if (currentTheme === "HYSYS")     return "#2f3d2c"   // slightly lighter olive green sheet
        if (currentTheme === "AspenPlus") return "#f5f7f9"
        return "#f5f2eb"          // Default (warm off-white)
    }

    readonly property color sheetBorder: {
        if (currentTheme === "HYSYS")     return "#3d5238"   // muted green border
        if (currentTheme === "AspenPlus") return "#b0bcc8"
        return "#8f989f"
    }

    // ── Grid / canvas overlay ─────────────────────────────────────────────
    readonly property string gridLineColor: {
        if (currentTheme === "HYSYS")     return "#323f2f"   // subtle dark green grid lines
        if (currentTheme === "AspenPlus") return "#d0d8e0"
        return "#ccc8b8"
    }

    readonly property string gridDotColor: {
        if (currentTheme === "HYSYS")     return "#374434"   // slightly lighter green dots
        if (currentTheme === "AspenPlus") return "#c0ccd8"
        return "#c4bfae"
    }

    // ── Stream connection lines ───────────────────────────────────────────
    readonly property string materialStreamColor: {
        if (currentTheme === "HYSYS")     return "#00D4FF"   // HYSYS cyan streams
        if (currentTheme === "AspenPlus") return "#003087"
        return "#0a3d8f"
    }

    readonly property string energyStreamColor: {
        if (currentTheme === "HYSYS")     return "#FF8C00"   // HYSYS orange energy streams
        if (currentTheme === "AspenPlus") return "#CC0000"
        return "#cc7a00"
    }

    // ── Snap / port highlight colours (unchanged across themes) ──────────
    readonly property string snapRingColor:    "#00c080"
    readonly property string snapDotColor:     "#00c080"
    readonly property string snapLabelColor:   "#00802a"
    readonly property string pendingPortColor: "#cc7a00"

    // ── Title block (drawing border box) ─────────────────────────────────
    readonly property color titleBlockBg: {
        if (currentTheme === "HYSYS")     return "#232e21"   // darkest green for title block
        if (currentTheme === "AspenPlus") return "#e8edf2"
        return "#e8e4d8"
    }

    readonly property color titleBlockBorder: {
        if (currentTheme === "HYSYS")     return "#4a6040"   // medium green border
        if (currentTheme === "AspenPlus") return "#2255A4"
        return "#2a2a2a"
    }

    readonly property color titleBlockText: {
        if (currentTheme === "HYSYS")     return "#a8c8a0"   // light green text
        if (currentTheme === "AspenPlus") return "#1a3a6a"
        return "#1a1a2e"
    }

    readonly property color titleBlockLabel: {
        if (currentTheme === "HYSYS")     return "#5a7850"   // muted green label
        if (currentTheme === "AspenPlus") return "#5577aa"
        return "#4a4a4a"
    }

    // ── Unit node (equipment icon on canvas) ─────────────────────────────
    readonly property color nodeSelectionBorder: {
        if (currentTheme === "HYSYS")     return "#00D4FF"   // cyan selection highlight
        if (currentTheme === "AspenPlus") return "#2255A4"
        return "#2f6fa3"
    }

    readonly property color nodeLabelColor: {
        if (currentTheme === "HYSYS")     return "#c8e0c0"   // light green-tinted label text
        if (currentTheme === "AspenPlus") return "#1a3060"
        return "#31404a"
    }

    // ── Status bar ────────────────────────────────────────────────────────
    readonly property color statusBarBg: {
        if (currentTheme === "HYSYS")     return "#1c2419"   // very dark green status bar
        if (currentTheme === "AspenPlus") return "#dce4ec"
        return "#1a1a2e"
    }

    readonly property color statusBarText: {
        if (currentTheme === "HYSYS")     return "#7ab87a"   // muted green status text
        if (currentTheme === "AspenPlus") return "#1a3060"
        return "#31404a"
    }

    // ── Equipment Palette panel ───────────────────────────────────────────
    readonly property color palettePanelBg: {
        if (currentTheme === "HYSYS")     return "#232e21"   // dark green palette background
        if (currentTheme === "AspenPlus") return "#dce8f4"
        return "#eef2f4"
    }

    readonly property color palettePanelBorder: {
        if (currentTheme === "HYSYS")     return "#3a4e36"   // green panel border
        if (currentTheme === "AspenPlus") return "#7aaad4"
        return "#9aaab5"
    }

    readonly property color paletteTitleBg: {
        if (currentTheme === "HYSYS")     return "#1a2418"   // darkest green title bar
        if (currentTheme === "AspenPlus") return "#2255A4"
        return "#2a3b49"
    }

    readonly property color paletteTitleText: {
        if (currentTheme === "HYSYS")     return "#7ab87a"   // green-tinted title text
        if (currentTheme === "AspenPlus") return "#ffffff"
        return "#dce8f1"
    }

    readonly property color paletteSectionText: {
        if (currentTheme === "HYSYS")     return "#4a7848"   // muted green section headers
        if (currentTheme === "AspenPlus") return "#2255A4"
        return "#5f6d78"
    }

    readonly property color paletteDivider: {
        if (currentTheme === "HYSYS")     return "#323f2f"   // subtle green divider
        if (currentTheme === "AspenPlus") return "#8ab4d8"
        return "#c6d0d7"
    }

    readonly property color paletteItemBg:        { return "transparent" }
    readonly property color paletteItemBgHover: {
        if (currentTheme === "HYSYS")     return "#2f3d2c"   // lighter green on hover
        if (currentTheme === "AspenPlus") return "#c4d8ee"
        return "#dde8f0"
    }
    readonly property color paletteItemBgPressed: {
        if (currentTheme === "HYSYS")     return "#1f2b1d"   // darker green on press
        if (currentTheme === "AspenPlus") return "#aac4e0"
        return "#c8d8e8"
    }
    readonly property color paletteItemBorder: {
        if (currentTheme === "HYSYS")     return "#3a4e36"   // green item border
        if (currentTheme === "AspenPlus") return "#5588c0"
        return "#c6d0d7"
    }
    readonly property color paletteItemBorderHover: {
        if (currentTheme === "HYSYS")     return "#7ab87a"   // bright green hover border
        if (currentTheme === "AspenPlus") return "#2255A4"
        return "#7aaac8"
    }
    readonly property color paletteItemLabelColor: {
        if (currentTheme === "HYSYS")     return "#a8c8a0"   // light green label text
        if (currentTheme === "AspenPlus") return "#1a3060"
        return "#31404a"
    }

    readonly property color palettePlannedBg: {
        if (currentTheme === "HYSYS")     return "#1f2b1d"   // dark green planned item bg
        if (currentTheme === "AspenPlus") return "#e8f0f8"
        return "#f0f3f4"
    }
    readonly property color palettePlannedBorder: {
        if (currentTheme === "HYSYS")     return "#2e3c2b"   // subtle planned border
        if (currentTheme === "AspenPlus") return "#b0c8e0"
        return "#d2d8dc"
    }
    readonly property color palettePlannedText: {
        if (currentTheme === "HYSYS")     return "#3a5038"   // dim green planned text
        if (currentTheme === "AspenPlus") return "#8aaac8"
        return "#9daab2"
    }

    // ── Toolbar / top bar (PfdMainView) ───────────────────────────────────
    readonly property color toolbarBg: {
        if (currentTheme === "HYSYS")     return "#181f16"   // very dark green toolbar
        if (currentTheme === "AspenPlus") return "#d0dce8"
        return "#0f1720"
    }

    readonly property color toolbarBorder: {
        if (currentTheme === "HYSYS")     return "#2a3828"   // canvas-matching toolbar border
        if (currentTheme === "AspenPlus") return "#8aaac8"
        return "#2a3b49"
    }
}
