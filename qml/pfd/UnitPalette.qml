import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Pane {
    id: root
    property var flowsheet
    signal openWorkspaceRequested()

    padding: 12

    background: Rectangle {
        color: "#eef2f4"
        border.color: "#c6d0d7"
        radius: 10
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Label {
            text: "Equipment Palette"
            font.pixelSize: 18
            font.bold: true
            color: "#22303a"
        }

        Label {
            text: "Start with the atmospheric distillation column or add a standalone material stream. Additional equipment can be enabled later without changing the PFD shell."
            wrapMode: Text.WordWrap
            color: "#5f6d78"
            Layout.fillWidth: true
        }

        Frame {
            Layout.fillWidth: true
            background: Rectangle {
                color: "#f9faf7"
                border.color: "#d2d8dc"
                radius: 8
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: "Add Atmospheric Distillation Column"
                    onClicked: if (root.flowsheet) root.flowsheet.addColumn(140, 120)
                }

                Button {
                    Layout.fillWidth: true
                    text: "Add Stream"
                    onClicked: if (root.flowsheet) root.flowsheet.addStream(260, 160)
                }

                Button {
                    Layout.fillWidth: true
                    text: "Open Current Workspace"
                    onClicked: root.openWorkspaceRequested()
                }
            }
        }

        Label {
            text: "Planned palette"
            font.bold: true
            color: "#22303a"
        }

        Repeater {
            model: [
                "Pump",
                "Heat Exchanger",
                "Separator",
                "Valve",
                "Compressor",
                "Mixer / Splitter"
            ]

            delegate: Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 6
                color: "#f7f8f9"
                border.color: "#d7dde2"

                Label {
                    anchors.centerIn: parent
                    text: modelData + "  (future)"
                    color: "#7b8791"
                }
            }
        }

        Item { Layout.fillHeight: true }

        Frame {
            Layout.fillWidth: true
            background: Rectangle {
                color: "#fffdf5"
                border.color: "#d8ceb0"
                radius: 8
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Label {
                    text: "Worksheet note"
                    font.bold: true
                    color: "#4d3d12"
                }

                Label {
                    Layout.fillWidth: true
                    text: root.flowsheet ? "Placed units: " + root.flowsheet.unitCount : "Placed units: 0"
                    color: "#6c5922"
                }
            }
        }
    }
}
