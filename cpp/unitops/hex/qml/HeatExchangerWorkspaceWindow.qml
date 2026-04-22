import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  HeatExchangerWorkspaceWindow — hosts HeatExchangerView inside a floating
//  panel.
//
//  The view is given the panel's full height so its anchored layout
//  (PPropertyView on top, Solve/Reset bar pinned at bottom) stays intact
//  at any panel size. Horizontally the view is capped at viewTargetWidth
//  and centered when the panel is wider. Each tab has its own ScrollView,
//  so no outer scroll container is needed here.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState

    anchors.fill: parent

    readonly property color bg: "#dfe4ee"
    readonly property int   viewTargetWidth: 410

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    // Centered, full-height container — the view's own anchored layout
    // (PPropertyView on top, Solve/Reset bar pinned at bottom) handles
    // vertical distribution, so the bottom bar is always visible regardless
    // of the floating panel's height.
    HeatExchangerView {
        width:  Math.min(parent.width, root.viewTargetWidth)
        height: parent.height
        x: Math.max(0, Math.floor((parent.width - width) / 2))
        appState: root.appState
    }
}
