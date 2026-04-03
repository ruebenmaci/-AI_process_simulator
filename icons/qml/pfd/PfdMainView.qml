import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

import ChatGPT5.ADT 1.0
import "../../cpp/unitops/column/qml"
import "."

Item {
    id: root
    property var flowsheet
    property var appState
    property var activeUnit: root.flowsheet ? root.flowsheet.selectedUnit : null
    property bool floatingWorkspaceVisible: false
    property point floatingWorkspacePos: Qt.point(40, 40)
    property string connectionMode: "none"

    implicitWidth: 1200
    implicitHeight: 900
    focus: true

    function tryDeleteSelectedUnit() {
        if (!root.flowsheet || !root.flowsheet.selectedUnitId || root.flowsheet.selectedUnitId === "")
            return
        const ok = root.flowsheet.deleteSelectedUnitAndConnections()
        if (!ok && root.flowsheet.lastOperationMessage !== "") {
            deleteWarningDialog.text = root.flowsheet.lastOperationMessage
            deleteWarningDialog.open()
        } else if (ok) {
            root.connectionMode = "none"
        }
    }

    function applyMinimumHostSize() {
        if (Window.window) {
            Window.window.minimumWidth = 1200
            Window.window.minimumHeight = 900
        }
    }

    function workspaceTitle() {
        if (!root.activeUnit || !root.flowsheet || root.flowsheet.selectedUnitId === "")
            return "Workspace"
        const unitName = root.activeUnit.name || root.activeUnit.id || ""
        if (root.activeUnit.type === "stream") {
            return unitName ? "Material Stream  —  " + unitName : "Material Stream"
        } else {
            return unitName ? "Distillation Column  —  " + unitName : "Distillation Column"
        }
    }

    Component.onCompleted: applyMinimumHostSize()
    onWindowChanged: applyMinimumHostSize()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Frame {
            Layout.fillWidth: true
            background: Rectangle {
                color: "#0f1720"
                border.color: "#2a3b49"
                radius: 10
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Item { Layout.fillWidth: true }

                Button { text: "New"; enabled: false }
                Button { text: "Open"; enabled: false }
                Button { text: "Save"; enabled: false }

                Button {
                    text: "Equipment Palette"
                    checkable: true
                    checked: equipmentPalette.visible
                    onClicked: {
                        if (equipmentPalette.visible) {
                            equipmentPalette.visible = false
                        } else {
                            // Default position: near top-left of PFD canvas area
                            equipmentPalette.x = 16
                            equipmentPalette.y = 16
                            equipmentPalette.visible = true
                        }
                    }
                }

                Frame {
                    background: Rectangle {
                        color: "#15202a"
                        border.color: "#31404d"
                        radius: 8
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        Label {
                            text: "Connect"
                            color: "#dce8f1"
                            font.bold: true
                        }

                        Button {
                            text: "Feed"
                            checkable: true
                            checked: root.connectionMode === "feed"
                            onClicked: root.connectionMode = checked ? "feed" : "none"
                        }
                        Button {
                            text: "Distillate"
                            checkable: true
                            checked: root.connectionMode === "distillate"
                            onClicked: root.connectionMode = checked ? "distillate" : "none"
                        }
                        Button {
                            text: "Bottoms"
                            checkable: true
                            checked: root.connectionMode === "bottoms"
                            onClicked: root.connectionMode = checked ? "bottoms" : "none"
                        }
                        Button {
                            text: "Disconnect Stream"
                            checkable: true
                            checked: root.connectionMode === "disconnect"
                            onClicked: root.connectionMode = checked ? "disconnect" : "none"
                        }
                        Button {
                            text: "Cancel"
                            enabled: root.connectionMode !== "none"
                            onClicked: root.connectionMode = "none"
                        }
                    }
                }

                Button {
                    text: "Delete Selected"
                    enabled: !!root.activeUnit
                    onClicked: root.tryDeleteSelectedUnit()
                }

                Button {
                    text: "Clear Worksheet"
                    enabled: root.flowsheet && root.flowsheet.unitCount > 0
                    onClicked: if (root.flowsheet) root.flowsheet.clear()
                }

                Button {
                    text: root.activeUnit && root.activeUnit.type === "stream" ? "Open Stream Workspace" : "Open Workspace"
                    enabled: !!root.activeUnit
                    onClicked: root.floatingWorkspaceVisible = true
                }
            }
        }

        // PFD area — full width now that the left sidebar is removed
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    visible: root.connectionMode !== "none"
                    text: root.connectionMode === "disconnect"
                          ? "Disconnect mode: click a stream on the PFD."
                          : ("Connection mode: click one stream and one column to bind the " + root.connectionMode + " port.")
                    color: "#44535f"
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    visible: pfdCanvas.connectionStatusText !== ""
                    text: pfdCanvas.connectionStatusText
                    color: "#6a4a00"
                    wrapMode: Text.WordWrap
                }

                PfdCanvas {
                    id: pfdCanvas
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    flowsheet: root.flowsheet
                    connectionMode: root.connectionMode

                    onConnectionModeChanged: resetConnectionSelection()

                    onUnitDoubleClicked: function(unitId) {
                    if (root.flowsheet)
                        root.flowsheet.selectUnit(unitId)
                    root.floatingWorkspaceVisible = true
                    floatingWorkspace.active = true
                    }
                }
            }

            // ── Floating Equipment Palette ─────────────────────────────────
            // Overlays the PFD area; draggable via its title bar.
            EquipmentPalette {
                id: equipmentPalette
                boundsItem: parent
                visible: false
                z: 100

                onPlacementRequested: function(unitType) {
                    pfdCanvas.beginPlacement(unitType)
                }
            }
        }
    }

    Keys.onDeletePressed: root.tryDeleteSelectedUnit()

    Item {
        id: deleteWarningDialog
        visible: false
        z: 200
        width: 560
        height: dialogColumn.implicitHeight + 18
        x: Math.max(24, Math.min(root.width - width - 24, (root.width - width) / 2))
        y: Math.max(24, Math.min(root.height - height - 24, (root.height - height) / 2))
        property string text: ""

        function open() {
            visible = true
            forceActiveFocus()
        }

        function close() {
            visible = false
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#eef3f6"
            border.color: "#7f8f9b"
            border.width: 1
        }

        ColumnLayout {
            id: dialogColumn
            anchors.fill: parent
            anchors.margins: 9
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 6
                color: "#d8e1e7"
                border.color: "#93a3ae"

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Delete blocked"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#17212b"
                }

                Button {
                    id: deleteWarningOkButton
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OK"
                    onClicked: deleteWarningDialog.close()
                }

                MouseArea {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: deleteWarningOkButton.left
                    anchors.rightMargin: 8
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.SizeAllCursor
                    drag.target: deleteWarningDialog
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 8
                    drag.minimumY: 8
                    drag.maximumX: Math.max(8, root.width - deleteWarningDialog.width - 8)
                    drag.maximumY: Math.max(8, root.height - deleteWarningDialog.height - 8)
                }
            }

            Label {
                Layout.fillWidth: true
                text: deleteWarningDialog.text
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                color: "#17212b"
                padding: 8
                background: Rectangle {
                    color: "transparent"
                }
            }
        }
    }

    FloatingPanel {
        id: floatingWorkspace
        visible: root.floatingWorkspaceVisible && !!root.activeUnit
        panelTitle: root.workspaceTitle()
        boundsItem: root
        x: Math.min(root.floatingWorkspacePos.x, Math.max(0, root.width - width))
        y: Math.min(root.floatingWorkspacePos.y, Math.max(0, root.height - height))

        // Update title whenever the selected unit changes (type switch stream↔column)
        Connections {
            target: root.flowsheet
            function onSelectedUnitChanged() {
                floatingWorkspace.panelTitle = Qt.binding(function() { return root.workspaceTitle() })
            }
            ignoreUnknownSignals: true
        }

        // Update title whenever the current unit's name changes (live typing)
        Connections {
            target: root.activeUnit
            function onNameChanged() {
                floatingWorkspace.panelTitle = Qt.binding(function() { return root.workspaceTitle() })
            }
            ignoreUnknownSignals: true
        }

        readonly property int columnNormalWidth: 1320
        readonly property int columnNormalHeight: 860
        readonly property int columnMockupWidth: 924
        readonly property int columnMockupHeight: 652
        readonly property int streamWidth: 924
        readonly property int streamHeight: 652
        readonly property bool streamMode: !!root.activeUnit && root.activeUnit.type === "stream"

        width: streamMode ? streamWidth : (showHysysMockup ? columnMockupWidth : columnNormalWidth)
        height: streamMode ? streamHeight : (showHysysMockup ? columnMockupHeight : columnNormalHeight)

        active: visible
        showViewSwitcher: !streamMode
        showHysysMockup: streamMode ? false : showHysysMockup

        onXChanged: root.floatingWorkspacePos = Qt.point(x, y)
        onYChanged: root.floatingWorkspacePos = Qt.point(x, y)

        onCloseRequested: root.floatingWorkspaceVisible = false

        contentItem: [
            Loader {
                anchors.fill: parent
                sourceComponent: floatingWorkspace.streamMode ? streamWorkspaceComponent : columnWorkspaceComponent
            }
        ]

        Component {
            id: columnWorkspaceComponent
            ColumnWorkspaceWindow {
                anchors.fill: parent
                appState: root.activeUnit
                showHysysMockup: floatingWorkspace.showHysysMockup
            }
        }

        Component {
            id: streamWorkspaceComponent
            StreamWorkspaceWindow {
                anchors.fill: parent
                appState: root.activeUnit
            }
        }
    }
}
