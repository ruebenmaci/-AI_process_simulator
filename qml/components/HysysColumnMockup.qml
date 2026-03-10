import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    implicitWidth: 1280
    implicitHeight: 860

    readonly property color bg: "#d7dbe1"
    readonly property color panel: "#eceff3"
    readonly property color panelAlt: "#e3e7ec"
    readonly property color border: "#aab2bd"
    readonly property color text: "#1f2730"
    readonly property color muted: "#5f6b79"
    readonly property color accent: "#7d8794"

    Rectangle {
        anchors.fill: parent
        color: bg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // Top title/tool bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 8
                color: panel
                border.color: border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Label {
                        text: "Distillation Column Environment (HYSYS-style mockup)"
                        color: text
                        font.bold: true
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }

                    ComboBox {
                        model: ["Case: ADU-Column-01", "Case: ADU-Column-02"]
                        implicitWidth: 240
                        background: Rectangle {
                            radius: 6
                            color: "#f7f8fa"
                            border.color: "#aeb6c1"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.displayText
                            color: text
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                            rightPadding: 28
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        text: "Run"
                        background: Rectangle {
                            radius: 6
                            color: "#d8dde4"
                            border.color: "#9ea7b2"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            color: text
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Reset"
                        background: Rectangle {
                            radius: 6
                            color: "#d8dde4"
                            border.color: "#9ea7b2"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            color: text
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // Left navigation
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.fillHeight: true
                    radius: 8
                    color: panel
                    border.color: border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Label {
                            text: "Column Pages"
                            color: text
                            font.bold: true
                            font.pixelSize: 13
                        }

                        Repeater {
                            model: [
                                "Configuration",
                                "Parameters",
                                "Specifications",
                                "Estimates",
                                "Profiles",
                                "Convergence",
                                "Worksheet",
                                "Performance",
                                "Hydraulics"
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: 6
                                color: index === 0 ? "#d2d8e0" : "#f7f8fa"
                                border.color: index === 0 ? accent : "#b7bec8"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: text
                                    font.pixelSize: 12
                                    font.bold: index === 0
                                }
                            }
                        }
                    }
                }

                // Center main panel
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: panel
                    border.color: border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Label {
                            text: "Configuration / Specifications"
                            color: text
                            font.bold: true
                            font.pixelSize: 14
                        }

                        // 4-column form block
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 10
                            rowSpacing: 8

                            Repeater {
                                model: [
                                    "Column Name", "Stages", "Condenser Type", "Reboiler Type",
                                    "Feed Stage", "Top Pressure", "Bottom Pressure", "dP/Stage",
                                    "Spec 1", "Spec 2", "Spec 3", "Spec 4"
                                ]
                                delegate: ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Label { text: modelData; color: muted; font.pixelSize: 11 }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        radius: 6
                                        color: "#f8f9fb"
                                        border.color: "#b8bfc9"
                                        border.width: 1
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: border }

                        // Stage profile + tray table area
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 6
                                color: panelAlt
                                border.color: border
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    Label { text: "Profiles (T / P / V-L)"; color: text; font.bold: true; font.pixelSize: 12 }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 4
                                        color: "#f7f8fa"
                                        border.color: "#b6bec8"
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Chart placeholder"
                                            color: muted
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 360
                                Layout.fillHeight: true
                                radius: 6
                                color: panelAlt
                                border.color: border
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    Label { text: "Stage Worksheet"; color: text; font.bold: true; font.pixelSize: 12 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Stage"; color: muted; Layout.preferredWidth: 48 }
                                        Label { text: "Temp"; color: muted; Layout.preferredWidth: 70 }
                                        Label { text: "Press"; color: muted; Layout.preferredWidth: 70 }
                                        Label { text: "Vap"; color: muted; Layout.preferredWidth: 70 }
                                        Label { text: "Liq"; color: muted; Layout.preferredWidth: 70 }
                                    }

                                    Repeater {
                                        model: 12
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 24
                                            color: index % 2 ? "#f2f4f7" : "#e8ecf1"
                                            border.color: "#b6bec8"
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                Label { text: String(32 - index); color: text; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignHCenter }
                                                Label { text: "620.0"; color: text; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
                                                Label { text: "1.50"; color: text; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
                                                Label { text: "0.42"; color: text; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
                                                Label { text: "0.58"; color: text; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right summary panel
                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: 8
                    color: panel
                    border.color: border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Label { text: "Run Summary"; color: text; font.bold: true; font.pixelSize: 13 }

                        Repeater {
                            model: [
                                "Status: Solved",
                                "Iterations: 17",
                                "Qc: 6.2 MW",
                                "Qr: 8.1 MW",
                                "Top T: 398.2 K",
                                "Bottom T: 681.1 K",
                                "Reflux Ratio: 2.0",
                                "Boilup Ratio: 0.06"
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: "#f7f8fa"
                                border.color: "#b7bec8"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: text
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: border }

                        Label { text: "Diagnostics"; color: text; font.bold: true; font.pixelSize: 12 }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#f7f8fa"
                            border.color: "#b7bec8"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Convergence, warnings, and log messages"
                                color: muted
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}