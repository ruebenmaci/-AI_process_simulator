import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

import ChatGPT5.ADT 1.0
import "../../cpp/unitops/column/qml"
import "."
import "../spreadsheet"

Item {
    id: root
    property var flowsheet
    property var appState
    property var activeUnit: root.flowsheet ? root.flowsheet.selectedUnit : null
    property bool floatingWorkspaceVisible: false
    property point floatingWorkspacePos: Qt.point(40, 40)
    property bool componentManagerVisible: false
    property point componentManagerPos: Qt.point(80, 80)
    property bool fluidManagerVisible: false
    property point fluidManagerPos: Qt.point(120, 120)
    property int topPanelZ: 100
    property bool spreadsheetVisible: false
    property point spreadsheetPos: Qt.point(160, 160)
    property var activePanel: null

    function raisePanel(panel) {
        if (!panel) return
        topPanelZ += 1
        panel.panelZ = topPanelZ
        activePanel = panel
    }

    implicitWidth: 1200
    implicitHeight: 900
    focus: true

    function tryDeleteSelectedUnit() {
        if (!root.flowsheet || !root.flowsheet.selectedUnitId || root.flowsheet.selectedUnitId === "")
            return
        const ok = root.flowsheet.deleteSelectedUnit()
        if (!ok && root.flowsheet.lastOperationMessage !== "") {
            deleteWarningDialog.text = root.flowsheet.lastOperationMessage
            deleteWarningDialog.open()
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

                ClassicButton { text: "New"; enabled: false }
                ClassicButton { text: "Open"; enabled: false }
                ClassicButton { text: "Save"; enabled: false }

                ClassicButton {
                    text: "Components"
                    checkable: true
                    checked: root.componentManagerVisible
                    onClicked: {
                        root.componentManagerVisible = !root.componentManagerVisible
                        if (root.componentManagerVisible) root.raisePanel(componentManagerPanel)
                    }
                }

                ClassicButton {
                    text: "Fluid Packages"
                    checkable: true
                    checked: root.fluidManagerVisible
                    onClicked: {
                        root.fluidManagerVisible = !root.fluidManagerVisible
                        if (root.fluidManagerVisible) root.raisePanel(fluidManagerPanel)
                    }
                }

                ClassicButton {
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

                ClassicButton {
                    text: "Spreadsheet"
                    checkable: true
                    checked: root.spreadsheetVisible
                    onClicked: {
                        root.spreadsheetVisible = !root.spreadsheetVisible
                        if (root.spreadsheetVisible) root.raisePanel(spreadsheetPanel)
                    }
                }

                ClassicButton {
                    text: "Clear Worksheet"
                    enabled: root.flowsheet && root.flowsheet.unitCount > 0
                    onClicked: if (root.flowsheet) root.flowsheet.clear()
                }

                ClassicButton {
                    id: displayBtn
                    text: "Display"
                    checkable: true
                    checked: displaySettingsPopup.visible
                    onClicked: displaySettingsPopup.visible = !displaySettingsPopup.visible
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

                PfdCanvas {
                    id: pfdCanvas
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    flowsheet: root.flowsheet
                    onUnitDoubleClicked: function(unitId) {
                    if (root.flowsheet)
                        root.flowsheet.selectUnit(unitId)
                    root.floatingWorkspaceVisible = true
                    root.raisePanel(floatingWorkspace)
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

                ClassicButton {
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
        id: componentManagerPanel
        visible: root.componentManagerVisible
        onVisibleChanged: if (visible) root.raisePanel(componentManagerPanel)
        panelTitle: "Component Manager"
        boundsItem: root
        minPanelWidth: 860
        minPanelHeight: 560
        width: Math.min(980, Math.max(860, root.width - 260))
        height: Math.min(640, Math.max(560, root.height - 220))
        x: Math.min(root.componentManagerPos.x, Math.max(0, root.width - width))
        y: Math.min(root.componentManagerPos.y, Math.max(0, root.height - height))
        active: visible && root.activePanel === componentManagerPanel

        onXChanged: root.componentManagerPos = Qt.point(x, y)
        onYChanged: root.componentManagerPos = Qt.point(x, y)
        onActivated: root.raisePanel(componentManagerPanel)
        onCloseRequested: {
            root.componentManagerVisible = false
            if (root.activePanel === componentManagerPanel) root.activePanel = null
        }

        contentItem: [
            ComponentManagerView {
                anchors.fill: parent
                manager: gComponentManager
            }
        ]
    }


    FloatingPanel {
        id: fluidManagerPanel
        visible: root.fluidManagerVisible
        onVisibleChanged: if (visible) root.raisePanel(fluidManagerPanel)
        panelTitle: "Fluid Package Manager"
        boundsItem: root
        minPanelWidth: 1040
        minPanelHeight: 720
        width: Math.min(1240, Math.max(1040, root.width - 100))
        height: Math.min(820, Math.max(720, root.height - 100))
        x: Math.min(root.fluidManagerPos.x, Math.max(0, root.width - width))
        y: Math.min(root.fluidManagerPos.y, Math.max(0, root.height - height))
        active: visible && root.activePanel === fluidManagerPanel

        onXChanged: root.fluidManagerPos = Qt.point(x, y)
        onYChanged: root.fluidManagerPos = Qt.point(x, y)
        onActivated: root.raisePanel(fluidManagerPanel)
        onCloseRequested: {
            root.fluidManagerVisible = false
            if (root.activePanel === fluidManagerPanel) root.activePanel = null
        }

        contentItem: [
            FluidManagerView {
                anchors.fill: parent
                fluidManager: gFluidPackageManager
                componentManager: gComponentManager
            }
        ]
    }

    FloatingPanel {
        id: floatingWorkspace
        visible: root.floatingWorkspaceVisible && !!root.activeUnit
        onVisibleChanged: if (visible) root.raisePanel(floatingWorkspace)
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
        readonly property int streamWidth: 924
        readonly property int streamHeight: 652
        readonly property bool streamMode: !!root.activeUnit && root.activeUnit.type === "stream"

        width: streamMode ? streamWidth : columnNormalWidth
        height: streamMode ? streamHeight : columnNormalHeight

        active: visible && root.activePanel === floatingWorkspace

        onXChanged: root.floatingWorkspacePos = Qt.point(x, y)
        onYChanged: root.floatingWorkspacePos = Qt.point(x, y)
        onActivated: root.raisePanel(floatingWorkspace)

        onCloseRequested: {
            root.floatingWorkspaceVisible = false
            if (root.activePanel === floatingWorkspace) root.activePanel = null
        }

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

    FloatingPanel {
        id: spreadsheetPanel
        visible: root.spreadsheetVisible
        onVisibleChanged: if (visible) root.raisePanel(spreadsheetPanel)
        panelTitle: "Spreadsheet"
        boundsItem: root
        minPanelWidth: 800
        minPanelHeight: 500
        width: Math.min(1200, Math.max(800, root.width - 120))
        height: Math.min(700, Math.max(500, root.height - 160))
        x: Math.min(root.spreadsheetPos.x, Math.max(0, root.width - width))
        y: Math.min(root.spreadsheetPos.y, Math.max(0, root.height - height))
        active: visible && root.activePanel === spreadsheetPanel

        onXChanged: root.spreadsheetPos = Qt.point(x, y)
        onYChanged: root.spreadsheetPos = Qt.point(x, y)
        onActivated: root.raisePanel(spreadsheetPanel)
        onCloseRequested: {
            root.spreadsheetVisible = false
            if (root.activePanel === spreadsheetPanel) root.activePanel = null
        }

        contentItem: [
            SpreadsheetWorkspaceWindow {
                anchors.fill: parent
            }
        ]
    }

    // ── Display Settings popup ─────────────────────────────────────
    Rectangle {
        id: displaySettingsPopup
        visible: false
        z: 500
        // Position below the toolbar in the top-right corner
        x: root.width - width - 12
        y: 60
        width: 300
        height: popupCol.implicitHeight + 1
        color: "#e8ebef"
        border.color: "#97a2ad"
        border.width: 1

        Column {
            id: popupCol
            width: parent.width

            // Header
            Rectangle {
                width: parent.width; height: 20
                color: "#c8d0d8"; border.color: "#97a2ad"; border.width: 1
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Display Settings"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; font.pixelSize: 10; color: "#526571"
                    MouseArea { anchors.fill: parent; onClicked: displaySettingsPopup.visible = false }
                }
            }

            // Scale preset
            Item {
                width: parent.width; height: 22
                Text { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 100
                       text: "UI Scale"; font.pixelSize: 10; color: "#526571" }
                ComboBox {
                    id: scaleCombo
                    anchors { left: parent.left; leftMargin: 108; right: parent.right
                              rightMargin: 6; verticalCenter: parent.verticalCenter }
                    implicitHeight: 18; font.pixelSize: 10
                    model: ["100%  (native)", "110%", "125%", "150%", "175%", "200%"]
                    background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                    contentItem: Text { leftPadding: 4; text: parent.displayText
                                        color: "#1c4ea7"; font.pixelSize: 10
                                        verticalAlignment: Text.AlignVCenter }
                    Component.onCompleted: {
                        if (!gDisplaySettings) return
                        var idx = gDisplaySettings.currentPresetIndex()
                        currentIndex = (idx >= 0) ? idx : 0
                    }
                    onActivated: {
                        if (gDisplaySettings)
                            gDisplaySettings.scaleFactor = gDisplaySettings.presetValue(index)
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
            }

            // Current saved value
            Item {
                width: parent.width; height: 22
                Text { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 100
                       text: "Saved scale"; font.pixelSize: 10; color: "#526571" }
                Text { anchors { left: parent.left; leftMargin: 108; verticalCenter: parent.verticalCenter }
                       text: gDisplaySettings ? (Math.round(gDisplaySettings.scaleFactor * 100) + "%") : "—"
                       font.pixelSize: 10; color: "#1c4ea7" }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
            }

            // Restart note
            Item {
                width: parent.width; height: restartNote.implicitHeight + 10
                Text {
                    id: restartNote
                    x: 6; y: 5; width: parent.width - 12
                    text: "Scale change takes effect after restarting the app."
                    font.pixelSize: 9; color: "#526571"; wrapMode: Text.WordWrap
                }
            }
        }
    }

}
