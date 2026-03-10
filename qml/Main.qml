import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ChatGPT5.ADT 1.0

ApplicationWindow {
    id: win
    width: 1300
    height: 1050
    visible: true
    title: "ChatGPT5 ADT Simulator (Qt/QML port)"

    property bool showHysysMockup: false

    palette.window: "#0b0f14"
    palette.text: "#e6eef8"

    Rectangle {
        anchors.fill: parent
        color: "#0b0f14"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: showHysysMockup ? "HYSYS Mockup View" : "Detailed Crude Atmospheric Distillation Column"
                    color: "#e6eef8"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.fillWidth: true
                }

                Button {
                    text: showHysysMockup ? "Back to Simulator" : "Open HYSYS Mockup"
                    onClicked: showHysysMockup = !showHysysMockup
                }

                Button {
                    text: "Reset"
                    enabled: !showHysysMockup
                    onClicked: gAppState.reset()
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: showHysysMockup ? hysysMockupPage : simulatorPage
            }
        }

        Component {
            id: hysysMockupPage
            HysysColumnMockup {
                anchors.fill: parent
            }
        }

        Component {
            id: simulatorPage

            // Original page
            ScrollView {
                id: pageScroll
                anchors.fill: parent
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: pageScroll.availableWidth
                    spacing: 8

                    SpecsPanel {
                        Layout.fillWidth: true
                        appState: gAppState
                        onSolveClicked: gAppState.solve()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8

                            DiagnosticsPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 160
                                model: gAppState.diagnosticsModel
                                appState: gAppState
                            }

                            ColumnView {
                                Layout.fillWidth: true
                                appState: gAppState
                                trayModel: gAppState.trayModel
                                materialBalanceModel: gAppState.materialBalanceModel
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 340
                            Layout.maximumWidth: 360
                            Layout.alignment: Qt.AlignTop
                            spacing: 8

                            RunSummaryView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 310
                                appState: gAppState
                                trayModel: gAppState.trayModel
                            }

                            RunResultsView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 300
                                appState: gAppState
                            }

                            RunLogView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 420
                                model: gAppState.runLogModel
                            }
                        }
                    }
                }
            }
        }
    }
}