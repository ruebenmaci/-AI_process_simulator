import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Dialogs

import ChatGPT5.ADT 1.0
import "../../cpp/unitops/column/qml"
import "../../cpp/unitops/heater/qml"
import "."

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
    property var activePanel: null

    function raisePanel(panel) {
        if (!panel) return
        topPanelZ += 1
        panel.panelZ = topPanelZ
        activePanel = panel
    }

    function defaultSaveFileName() {
        // Build a filename from the drawing title + timestamp, no spaces
        const title = root.flowsheet ? root.flowsheet.drawingTitle : "simulation"
        const safe  = (title || "simulation").replace(/\s+/g, "_").replace(/[^A-Za-z0-9_\-]/g, "")
        const now   = new Date()
        const pad   = n => String(n).padStart(2, "0")
        const stamp = String(now.getFullYear()) +
                      pad(now.getMonth() + 1) +
                      pad(now.getDate()) + "_" +
                      pad(now.getHours()) +
                      pad(now.getMinutes())
        return safe + "_" + stamp   // e.g. AI_Process_sim-001_20260407_1432
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

    function newFlowsheet() {
        if (root.flowsheet) root.flowsheet.newFlowsheet()
    }

    function openFlowsheet() {
        openDialog.open()
    }

    function saveFlowsheet() {
        if (!root.flowsheet) return
        if (root.flowsheet.currentFilePath !== "")
            root.flowsheet.saveToFile(root.flowsheet.currentFilePath)
        else {
            saveDialog.selectedFile = ""
            saveDialog.currentFile  = (typeof gSavesPath !== "undefined" ? gSavesPath : "") + "/" + root.defaultSaveFileName() + ".sim"
            saveDialog.open()
        }
    }

    function saveFlowsheetAs() {
        saveDialog.currentFile = (typeof gSavesPath !== "undefined" ? gSavesPath : "") + "/" + root.defaultSaveFileName() + ".sim"
        saveDialog.open()
    }

    function toggleComponentManager() {
        root.componentManagerVisible = !root.componentManagerVisible
        if (root.componentManagerVisible) root.raisePanel(componentManagerPanel)
    }

    function toggleFluidManager() {
        root.fluidManagerVisible = !root.fluidManagerVisible
        if (root.fluidManagerVisible) root.raisePanel(fluidManagerPanel)
    }

    function toggleEquipmentPalette() {
        if (equipmentPalette.visible) {
            equipmentPalette.visible = false
        } else {
            const rightMargin = 60
            const topMargin = 40
            equipmentPalette.x = Math.max(8, root.width - equipmentPalette.width - rightMargin)
            equipmentPalette.y = topMargin
            equipmentPalette.visible = true
        }
    }

    function openDisplaySettings() {
        displaySettingsPopup.visible = true
    }

    function setTheme(themeKey) {
        gAppTheme.currentTheme = themeKey
        pfdCanvas.requestPaint()
    }

    function showAbout() {
        aboutDialog.visible = true
        aboutDialog.forceActiveFocus()
    }

    function workspaceTitle() {
        if (!root.activeUnit || !root.flowsheet || root.flowsheet.selectedUnitId === "")
            return "Workspace"
        const unitName = root.activeUnit.name || root.activeUnit.id || ""
        if (root.activeUnit.type === "stream") {
            return unitName ? "Material Stream  —  " + unitName : "Material Stream"
        } else if (root.activeUnit.type === "heater") {
            return unitName ? "Heater  —  " + unitName : "Heater"
        } else if (root.activeUnit.type === "cooler") {
            return unitName ? "Cooler  —  " + unitName : "Cooler"
        } else {
            return unitName ? "Distillation Column  —  " + unitName : "Distillation Column"
        }
    }

    Component.onCompleted: applyMinimumHostSize()
    onWindowChanged: applyMinimumHostSize()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 0

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
        panelIconSource: Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("component_list"))
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
        panelIconSource: Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("fluid_package"))
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
        panelIconSource: root.activeUnit && root.activeUnit.type === "stream"
                         ? Qt.resolvedUrl(gAppTheme.iconPath("Material_Stream"))
                         : Qt.resolvedUrl(gAppTheme.iconPath("dist_column"))
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

        readonly property int columnNormalWidth:  960
        readonly property int columnNormalHeight: 780
        readonly property int streamWidth:        664
        readonly property int streamHeight:       652
        readonly property int heaterWidth:        350
        readonly property int heaterHeight:       465

        readonly property bool streamMode:  !!root.activeUnit && root.activeUnit.type === "stream"
        readonly property bool heaterMode:  !!root.activeUnit && root.activeUnit.type === "heater"
        readonly property bool coolerMode:  !!root.activeUnit && root.activeUnit.type === "cooler"

        width:  streamMode  ? streamWidth
              : (heaterMode || coolerMode) ? heaterWidth
              : columnNormalWidth
        height: streamMode  ? streamHeight
              : (heaterMode || coolerMode) ? heaterHeight
              : columnNormalHeight

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
                sourceComponent: {
                    const t = root.activeUnit ? root.activeUnit.type : ""
                    if (t === "stream")  return streamWorkspaceComponent
                    if (t === "heater")  return heaterWorkspaceComponent
                    if (t === "cooler")  return coolerWorkspaceComponent
                    return columnWorkspaceComponent
                }
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

        Component {
            id: heaterWorkspaceComponent
            HeaterWorkspaceWindow {
                anchors.fill: parent
                appState: root.activeUnit
            }
        }

        Component {
            id: coolerWorkspaceComponent
            CoolerWorkspaceWindow {
                anchors.fill: parent
                appState: root.activeUnit
            }
        }
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


    Item {
        id: aboutDialog
        visible: false
        z: 550
        width: 520
        height: aboutColumn.implicitHeight + 18
        x: Math.max(24, Math.min(root.width - width - 24, (root.width - width) / 2))
        y: Math.max(24, Math.min(root.height - height - 24, (root.height - height) / 2))

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
            id: aboutColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 6
                color: "#d8e1e7"
                border.color: "#93a3ae"

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "About AI Process Simulator"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#17212b"
                }

                ClassicButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OK"
                    onClicked: aboutDialog.close()
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "AI Process Simulator\n\nA desktop process simulation workbench for building and testing flowsheets, material streams, fluid packages, and distillation column models.\n\nCurrent workspace features include:\n• Flowsheet editing with drag-and-drop equipment placement\n• Material stream and distillation column workspaces\n• Component and fluid package management\n• Theme and display customization\n\nThis About dialog can be expanded later with version, build date, author, and license details."
                color: "#17212b"
                font.pixelSize: 12
            }
        }

        Keys.onEscapePressed: aboutDialog.close()
    }

    // ── File dialogs ───────────────────────────────────────────────────────
    FileDialog {
        id: openDialog
        title: "Open Simulation File"
        nameFilters: ["Simulation files (*.sim)", "All files (*)"]
        fileMode: FileDialog.OpenFile
        currentFolder: typeof gSavesPath !== "undefined" ? gSavesPath : ""
        onAccepted: {
            if (root.flowsheet) {
                const path = selectedFile.toString().replace(/^file:\/\/\//, "")
                const ok = root.flowsheet.loadFromFile(path)
                if (!ok) errorDialog.open()
            }
        }
    }

    FileDialog {
        id: saveDialog
        title: "Save Simulation File"
        nameFilters: ["Simulation files (*.sim)", "All files (*)"]
        fileMode: FileDialog.SaveFile
        defaultSuffix: "sim"
        currentFolder: typeof gSavesPath !== "undefined" ? gSavesPath : ""
        onAccepted: {
            if (root.flowsheet) {
                const path = selectedFile.toString().replace(/^file:\/\/\//, "")
                const ok = root.flowsheet.saveToFile(path)
                if (!ok) errorDialog.open()
            }
        }
    }

    // Error dialog for save/load failures
    Item {
        id: errorDialog
        visible: false
        z: 300
        width: 400; height: 120
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        function open() { visible = true }
        Rectangle {
            anchors.fill: parent; radius: 6
            color: "#eef3f6"; border.color: "#7f8f9b"; border.width: 1
            Column {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                Text {
                    text: "File Error"
                    font.pixelSize: 13; font.bold: true; color: "#17212b"
                }
                Text {
                    width: parent.width
                    text: root.flowsheet ? (root.flowsheet.lastSaveError() || "Unknown error") : ""
                    wrapMode: Text.WordWrap; font.pixelSize: 11; color: "#5a2020"
                }
                ClassicButton {
                    text: "OK"
                    onClicked: errorDialog.visible = false
                }
            }
        }
    }

}
