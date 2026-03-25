import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ChatGPT5.ADT 1.0

Item {
    id: root
    property var appState
    property bool showHysysMockup: false  // Controlled by parent FloatingPanel

    anchors.fill: parent

    // Direct loader without header frame
    Loader {
        anchors.fill: parent
        active: true
        sourceComponent: root.showHysysMockup ? hysysViewComponent : workspaceViewComponent
    }

    Component {
        id: workspaceViewComponent

        ScrollView {
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: Math.max(root.width - 12, 1200)
                spacing: 8

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle { color: "#e9edf5"; border.color: "#2a2a2a"; radius: 10 }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        Label { text: "Name"; font.bold: true }
                        TextField {
                            Layout.fillWidth: true
                            text: root.appState ? (root.appState.name || root.appState.id || "") : ""
                            maximumLength: 100
                            validator: RegularExpressionValidator { regularExpression: /^[A-Za-z0-9_\-.]{0,100}$/ }
                            onEditingFinished: {
                                if (!root.appState) return
                                let value = String(text || "").trim().replace(/\s+/g, "_")
                                value = value.replace(/[^A-Za-z0-9_\-.]/g, "")
                                if (value.length > 100)
                                    value = value.substring(0, 100)
                                if (value === "")
                                    value = root.appState.id
                                text = value
                                root.appState.name = value
                            }
                        }
                    }
                }

                SpecsPanel {
                    Layout.fillWidth: true
                    appState: root.appState
                    enabled: !!root.appState
                    onSolveClicked: if (root.appState) root.appState.solve()
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
                            model: root.appState ? root.appState.diagnosticsModel : null
                            appState: root.appState
                        }

                        ColumnView {
                            Layout.fillWidth: true
                            appState: root.appState
                            trayModel: root.appState ? root.appState.trayModel : null
                            materialBalanceModel: root.appState ? root.appState.materialBalanceModel : null
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
                            appState: root.appState
                            trayModel: root.appState ? root.appState.trayModel : null
                        }

                        RunResultsView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 240
                            appState: root.appState
                        }

                        StreamView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 380
                            streamObject: root.appState ? root.appState.feedStream : null
                            streamTitle: streamObject && streamObject.streamName ? streamObject.streamName : "Feed Stream"
                        }

                        RunLogView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 420
                            model: root.appState ? root.appState.runLogModel : null
                        }
                    }
                }
            }
        }
    }

    Component {
        id: hysysViewComponent

        Flickable {
            clip: true
            contentWidth: Math.max(width, mockup.implicitWidth)
            contentHeight: height

            HysysColumnMockup {
                id: mockup
                appState: root.appState
                width: Math.max(parent.width, implicitWidth)
                height: parent.height
            }
        }
    }
}
