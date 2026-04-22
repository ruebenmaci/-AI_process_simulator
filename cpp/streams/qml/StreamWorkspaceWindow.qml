import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var appState

    anchors.fill: parent

    readonly property color bg: "#dfe4ee"
    readonly property color panel: "#e9edf5"
    readonly property color panelInset: "#f4f6fa"
    readonly property color border: "#2a2a2a"
    readonly property color textDark: "#1f2430"
    readonly property color mutedText: "#5a6472"
    readonly property int   streamViewTargetWidth: 560

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(scrollArea.availableWidth, root.streamViewTargetWidth)
            x: Math.max(0, Math.floor((scrollArea.availableWidth - width) / 2))
            spacing: 0

            StreamView {
                Layout.fillWidth: true
                Layout.preferredHeight: 611
                Layout.topMargin: 0
                streamObject: root.appState ? root.appState.stream : null
                unitObject: root.appState ? root.appState : null
            }
        }
    }
}
