import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  CoolerWorkspaceWindow — hosts HeaterCoolerView inside a floating panel.
//
//  Identical to HeaterWorkspaceWindow; the underlying HeaterCoolerView
//  detects whether this is a cooler via appState.type === "cooler" and
//  adapts its icon, accent colour, and duty label accordingly. This separate
//  file exists only because FlowsheetState's cooler wiring references it
//  by name — there is no behavioural difference at this layer.
//
//  The view is given the panel's full height so its anchored layout
//  (PPropertyView on top, Solve/Reset bar pinned at bottom) stays intact
//  at any panel size.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState

    anchors.fill: parent

    readonly property color bg: "#dfe4ee"
    readonly property int   viewTargetWidth: 465

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    // Centered, full-height container — the view's own anchored layout
    // (PPropertyView on top, bottom action bar pinned to bottom) handles
    // vertical distribution, so the bottom bar is always visible regardless
    // of the floating panel's height.
    HeaterCoolerView {
        width:  Math.min(parent.width, root.viewTargetWidth)
        height: parent.height
        x: Math.max(0, Math.floor((parent.width - width) / 2))
        appState: root.appState
    }
}
