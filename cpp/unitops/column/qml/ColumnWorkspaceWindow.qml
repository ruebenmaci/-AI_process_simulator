import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ChatGPT5.ADT 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnWorkspaceWindow — floating-panel host for the distillation column.
//
//  ColumnView fills the available area directly, without a fixed-height
//  floor, so the floating panel's bottom edge isn't visually cut off by a
//  tall ColumnView claiming more vertical space than the panel has.
//  Horizontal scrolling kicks in only when the panel narrows below the
//  ColumnView's natural minimum width (~940 px).
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState
    anchors.fill: parent

    readonly property color bg: "#dfe4ee"
    readonly property int   columnViewMinWidth: 940

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy:   ScrollBar.AlwaysOff
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

        ColumnView {
            width:  Math.max(scrollArea.availableWidth, root.columnViewMinWidth)
            height: scrollArea.availableHeight
            appState: root.appState
        }
    }
}
