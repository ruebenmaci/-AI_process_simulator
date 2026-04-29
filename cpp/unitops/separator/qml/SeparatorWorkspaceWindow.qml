import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  SeparatorWorkspaceWindow — hosts SeparatorView inside a floating panel.
//  Matches HeaterWorkspaceWindow / HeatExchangerWorkspaceWindow exactly:
//  full-height view, capped at viewTargetWidth (465 px), horizontally
//  centered when the panel is wider. Each tab has its own ScrollView, so
//  no outer scroll container is needed here.
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

    SeparatorView {
        width:  Math.min(parent.width, root.viewTargetWidth)
        height: parent.height
        x: Math.max(0, Math.floor((parent.width - width) / 2))
        appState: root.appState
    }
}
