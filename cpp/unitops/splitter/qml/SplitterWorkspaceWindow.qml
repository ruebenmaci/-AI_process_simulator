import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  SplitterWorkspaceWindow — hosts SplitterView inside a floating panel.
//  Matches HeaterWorkspaceWindow / HeatExchangerWorkspaceWindow / Separator-
//  WorkspaceWindow exactly: full-height view, capped at viewTargetWidth
//  (465 px), horizontally centered when the panel is wider.
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

    SplitterView {
        width:  Math.min(parent.width, root.viewTargetWidth)
        height: parent.height
        x: Math.max(0, Math.floor((parent.width - width) / 2))
        appState: root.appState
    }
}
