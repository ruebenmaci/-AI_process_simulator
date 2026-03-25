import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var model
    property var appState: null

    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.fill: parent
        color: "#121a24"
        radius: 10
        border.color: "#223041"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Text {
                text: "Solver diagnostics"
                font.pixelSize: 14
                font.bold: true
                color: "#e6eef8"
            }

            Rectangle {
                id: box
                Layout.fillWidth: true
                // Keep this panel short (3 lines) and scroll when longer.
                Layout.preferredHeight: (lineHeight * 3) + 16 // 3 full lines + padding
                radius: 8
                border.color: "#2a3a4f"
                border.width: 1
                color: "#0f151e"

                property int lineHeight: 18

                ListView {
                    anchors.fill: parent
                    anchors.margins: 8
                    model: root.model
                    clip: true
                    spacing: 4

                    delegate: Row {
                        spacing: 8
                        Text {
                            text: (level === "error") ? "⛔" : ((level === "warn") ? "⚠️" : "ℹ️")
                            color: "#e6eef8"
                        }
                        Text {
                            text: message
                            color: "#e6eef8"
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            width: box.width - 40
                        }
                    }

                    ScrollBar.vertical: ScrollBar {}
                }
            }
        }
    }
}
