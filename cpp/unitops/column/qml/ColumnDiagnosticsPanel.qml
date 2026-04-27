import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnDiagnosticsPanel.qml — Diagnostics tab.
//
//  Displays appState.diagnosticsModel as a single PGroupBox containing a
//  scrollable ListView. Each row has a severity dot (info / warn / error)
//  followed by the message text.
//
//  Severity colors stay literal in this panel because they're carrying
//  semantic meaning (red = error, amber = warning, blue = info), not chrome.
//  The surrounding chrome uses PGroupBox theming.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    // Severity colors — semantic, not chrome.
    readonly property color sevError: "#b23b3b"
    readonly property color sevWarn:  "#d6b74a"
    readonly property color sevInfo:  "#2e73b8"

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Item {
            anchors.fill: parent
            anchors.margins: 4

            PGroupBox {
                anchors.fill: parent
                caption: "Diagnostics"
                contentPadding: 8
                fillContent: true

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.appState ? root.appState.diagnosticsModel : null
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        width: ListView.view.width
                        height: Math.max(22, diagText.implicitHeight + 8)

                        Rectangle {
                            anchors.fill: parent
                            color: index % 2 === 0 ? "#f4f6f8" : "#ffffff"
                        }

                        // Severity dot
                        Rectangle {
                            width: 8; height: 8; radius: 2
                            x: 4; y: 6
                            color: model.level === "error" ? root.sevError
                                 : model.level === "warn"  ? root.sevWarn
                                                           : root.sevInfo
                        }

                        Text {
                            id: diagText
                            x: 18
                            y: 4
                            width: parent.width - 24
                            text: model.message || ""
                            font.pixelSize: 10
                            font.family: "Segoe UI"
                            color: "#1f2a34"
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#d8dde2"
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.appState
                                 || !root.appState.diagnosticsModel
                                 || root.appState.diagnosticsModel.rowCount() === 0
                        text: "No diagnostics"
                        color: "#526571"
                        font.pixelSize: 10
                        font.italic: true
                    }
                }
            }
        }
    }
}
