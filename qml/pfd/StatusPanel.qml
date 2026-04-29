import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  StatusPanel — left half of the bottom dock. Shows current connection-
//  completeness issues for the flowsheet (one row per non-OK unit). Backed
//  by gFlowsheetStatus, which auto-refreshes on materialConnectionsChanged
//  and unitCountChanged.
//
//  Click behaviour: option 3 — emits navigate(unitId), the host wires it
//  to selectUnit + highlightStream + open-property-panel.
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: root
    color: "#ffffff"
    border.color: "#97a2ad"
    border.width: 1

    signal navigate(string unitId)

    // ── Header strip ─────────────────────────────────────────────────────────
    Rectangle {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 22
        color: "#e8ebef"
        border.color: "#97a2ad"
        border.width: 1

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Status"
            font.pixelSize: 10
            font.bold: true
            color: "#1f2226"
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: typeof gFlowsheetStatus !== "undefined" && gFlowsheetStatus
                    ? (gFlowsheetStatus.count + " issue" + (gFlowsheetStatus.count === 1 ? "" : "s"))
                    : ""
            font.pixelSize: 9
            color: "#526571"
        }
    }

    // ── List ─────────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0
        model: typeof gFlowsheetStatus !== "undefined" ? gFlowsheetStatus : null
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Empty-state message.
        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "No issues"
            color: "#526571"
            font.pixelSize: 10
            font.italic: true
        }

        delegate: Rectangle {
            width: list.width
            height: 24
            color: rowMouse.containsMouse
                    ? "#dfe4ee"
                    : (index % 2 === 0 ? "#ffffff" : "#f5f7fa")

            // Severity dot
            Rectangle {
                id: sevDot
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 2
                color: model.severity === 3 ? "#c63e3e"
                     : model.severity === 2 ? "#d6b74a"
                     : "#1c4ea7"
            }

            // Unit name (click target visual cue: blue + underlined on hover)
            Text {
                id: unitText
                anchors.left: sevDot.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: model.unitName || model.unitId
                font.pixelSize: 11
                font.bold: true
                font.underline: rowMouse.containsMouse
                color: "#1c4ea7"
            }

            // Reason text — fills remaining width
            Text {
                anchors.left: unitText.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: model.reason || ""
                font.pixelSize: 11
                color: "#1f2226"
                elide: Text.ElideRight
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (model.unitId && model.unitId !== "")
                        root.navigate(model.unitId)
                }
            }
        }
    }
}
