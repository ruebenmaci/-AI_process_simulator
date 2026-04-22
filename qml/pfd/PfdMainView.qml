import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Dialogs

import ChatGPT5.ADT 1.0
import "../../cpp/unitops/column/qml"
import "../../cpp/unitops/heater/qml"
import "../../cpp/unitops/hex/qml"
import "."

Item {
    id: root
    property var flowsheet
    property var appState
    property var activeUnit: root.flowsheet ? root.flowsheet.selectedUnit : null
    property bool floatingWorkspaceVisible: false
    property point floatingWorkspacePos: Qt.point(40, 40)
    property point floatingWorkspaceRelPos: Qt.point(40 / Math.max(1, width), 40 / Math.max(1, height))
    property bool componentManagerVisible: false
    property point componentManagerPos: Qt.point(80, 80)
    property point componentManagerRelPos: Qt.point(80 / Math.max(1, width), 80 / Math.max(1, height))
    property bool fluidManagerVisible: false
    property point fluidManagerPos: Qt.point(120, 120)
    property point fluidManagerRelPos: Qt.point(120 / Math.max(1, width), 120 / Math.max(1, height))
    property point equipmentPalettePos: Qt.point(0, 0)
    property point equipmentPaletteRelPos: Qt.point(0, 0)
    property bool suppressPanelPosCapture: false
    property int topPanelZ: 100
    property var activePanel: null

    function raisePanel(panel) {
        if (!panel) return
        topPanelZ += 1
        panel.panelZ = topPanelZ
        activePanel = panel
    }
    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function clampPanelX(v, panel) {
        return Math.max(0, Math.min(Math.max(0, width - panel.width), v))
    }

    function clampPanelY(v, panel) {
        return Math.max(0, Math.min(Math.max(0, height - panel.height), v))
    }

    function capturePanelRelativePosition(panel, posPropName, relPropName) {
        if (!panel || suppressPanelPosCapture)
            return
        const px = clampPanelX(panel.x, panel)
        const py = clampPanelY(panel.y, panel)
        root[posPropName] = Qt.point(px, py)
        root[relPropName] = Qt.point(clamp01(px / Math.max(1, width)), clamp01(py / Math.max(1, height)))
    }

    function applyPanelRelativePosition(panel, posPropName, relPropName, fallbackX, fallbackY) {
        if (!panel)
            return
        suppressPanelPosCapture = true
        const rel = root[relPropName]
        const useRel = rel && (rel.x > 0 || rel.y > 0)
        const targetX = useRel ? rel.x * width : fallbackX
        const targetY = useRel ? rel.y * height : fallbackY
        const clampedX = clampPanelX(targetX, panel)
        const clampedY = clampPanelY(targetY, panel)
        panel.x = clampedX
        panel.y = clampedY
        root[posPropName] = Qt.point(clampedX, clampedY)
        root[relPropName] = Qt.point(clamp01(clampedX / Math.max(1, width)), clamp01(clampedY / Math.max(1, height)))
        suppressPanelPosCapture = false
    }

    function applyEquipmentPalettePosition(useCurrent) {
        if (!equipmentPalette.visible)
            return
        suppressPanelPosCapture = true
        const rightMargin = 60
        const topMargin = 40
        const fallbackX = Math.max(8, width - equipmentPalette.width - rightMargin)
        const fallbackY = topMargin
        const rel = equipmentPaletteRelPos
        const hasRel = useCurrent || (rel && (rel.x > 0 || rel.y > 0))
        const targetX = hasRel ? rel.x * width : fallbackX
        const targetY = hasRel ? rel.y * height : fallbackY
        const maxX = Math.max(0, width - equipmentPalette.width)
        const maxY = Math.max(0, height - equipmentPalette.height)
        equipmentPalette.x = Math.max(0, Math.min(maxX, targetX))
        equipmentPalette.y = Math.max(0, Math.min(maxY, targetY))
        equipmentPalettePos = Qt.point(equipmentPalette.x, equipmentPalette.y)
        equipmentPaletteRelPos = Qt.point(clamp01(equipmentPalette.x / Math.max(1, width)), clamp01(equipmentPalette.y / Math.max(1, height)))
        suppressPanelPosCapture = false
    }

    function refreshFloatingPanelPositions() {
        applyPanelRelativePosition(componentManagerPanel, 'componentManagerPos', 'componentManagerRelPos', 80, 80)
        applyPanelRelativePosition(fluidManagerPanel, 'fluidManagerPos', 'fluidManagerRelPos', 120, 120)
        applyPanelRelativePosition(floatingWorkspace, 'floatingWorkspacePos', 'floatingWorkspaceRelPos', 40, 40)
        applyEquipmentPalettePosition(true)
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

    onWidthChanged: Qt.callLater(root.refreshFloatingPanelPositions)
    onHeightChanged: Qt.callLater(root.refreshFloatingPanelPositions)

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
            equipmentPalette.visible = true
            Qt.callLater(function() { root.applyEquipmentPalettePosition(false) })
        }
    }

    function openDisplaySettings() {
        displaySettingsPopup.visible = true
    }

    function openUnitsFormatSettings() {
        unitsFormatSettingsDialog.visible = true
        unitsFormatSettingsDialog.forceActiveFocus()
    }

    function setTheme(themeKey) {
        gAppTheme.currentTheme = themeKey
        pfdCanvas.requestPaint()
    }

    function showAbout() {
        aboutDialog.visible = true
        aboutDialog.forceActiveFocus()
    }

    function showSolverConvergenceHelp() {
        solverConvergenceHelpDialog.visible = true
        solverConvergenceHelpDialog.forceActiveFocus()
    }

    function showStripperStatusHelp() {
        stripperStatusHelpDialog.visible = true
        stripperStatusHelpDialog.forceActiveFocus()
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
        } else if (root.activeUnit.type === "heat_exchanger") {
            return unitName ? "Heat Exchanger  —  " + unitName : "Heat Exchanger"
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
                boundsItem: root
                visible: false
                z: 100
                onXChanged: if (!root.suppressPanelPosCapture) {
                    root.equipmentPalettePos = Qt.point(x, y)
                    root.equipmentPaletteRelPos = Qt.point(root.clamp01(x / Math.max(1, root.width)), root.clamp01(y / Math.max(1, root.height)))
                }
                onYChanged: if (!root.suppressPanelPosCapture) {
                    root.equipmentPalettePos = Qt.point(x, y)
                    root.equipmentPaletteRelPos = Qt.point(root.clamp01(x / Math.max(1, root.width)), root.clamp01(y / Math.max(1, root.height)))
                }
                onVisibleChanged: if (visible) Qt.callLater(function() { root.applyEquipmentPalettePosition(false) })

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
        onVisibleChanged: if (visible) { root.raisePanel(componentManagerPanel); Qt.callLater(function() { root.applyPanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos", 80, 80) }) }
        panelTitle: "Component Manager"
        panelIconSource: Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("component_list"))
        boundsItem: root
        minPanelWidth: 860
        minPanelHeight: 560
        width: Math.min(980, Math.max(860, root.width - 260))
        height: Math.min(640, Math.max(560, root.height - 220))
        active: visible && root.activePanel === componentManagerPanel

        onXChanged: root.capturePanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos")
        onYChanged: root.capturePanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos")
        onWidthChanged: Qt.callLater(function() { root.applyPanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos", 80, 80) })
        onHeightChanged: Qt.callLater(function() { root.applyPanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos", 80, 80) })
        Component.onCompleted: Qt.callLater(function() { root.applyPanelRelativePosition(componentManagerPanel, "componentManagerPos", "componentManagerRelPos", 80, 80) })
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
        onVisibleChanged: if (visible) { root.raisePanel(fluidManagerPanel); Qt.callLater(function() { root.applyPanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos", 120, 120) }) }
        panelTitle: "Fluid Package Manager"
        panelIconSource: Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("fluid_package"))
        boundsItem: root
        minPanelWidth: 1040
        minPanelHeight: 720
        width: Math.min(1240, Math.max(1040, root.width - 100))
        height: Math.min(820, Math.max(720, root.height - 100))
        active: visible && root.activePanel === fluidManagerPanel

        onXChanged: root.capturePanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos")
        onYChanged: root.capturePanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos")
        onWidthChanged: Qt.callLater(function() { root.applyPanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos", 120, 120) })
        onHeightChanged: Qt.callLater(function() { root.applyPanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos", 120, 120) })
        Component.onCompleted: Qt.callLater(function() { root.applyPanelRelativePosition(fluidManagerPanel, "fluidManagerPos", "fluidManagerRelPos", 120, 120) })
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
        onVisibleChanged: if (visible) { root.raisePanel(floatingWorkspace); Qt.callLater(function() { root.applyPanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos", 40, 40) }) }
        panelTitle: root.workspaceTitle()
        // Drive the title-bar icon from the active unit's iconKey so every
        // unit-op type (heater, cooler, heat_exchanger, etc.) picks up its
        // own SVG automatically. Streams and columns keep their existing
        // legacy-key behaviour so their icons don't change.
        panelIconSource: {
            if (!root.activeUnit) return ""
            var t = root.activeUnit.type
            var key
            if (t === "stream")      key = "Material_Stream"
            else if (t === "column") key = "dist_column"
            else                     key = root.activeUnit.iconKey || "dist_column"
            return Qt.resolvedUrl(gAppTheme.iconPath(key))
        }
        boundsItem: root

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
        readonly property int streamWidth:        530
        readonly property int streamHeight:       652
        // Heater/Cooler/HEX panel size derived from ground-up row math:
        //   PGridLabel 180 + PGridValue ~120 + PGridUnit 72 = 372 px row
        //   + PGroupBox padding/bevel (~18) + ScrollView margin (8)
        //   + FloatingPanel contentHost margin (8) = ~410 px wide.
        //   Height accommodates tab strip (32) + Connections (~130)
        //   + Specifications (~90) + Conditions (~55) + paddings/spacings
        //   + bottom bar (40) + chrome + breathing room ≈ 420.
        readonly property int heaterWidth:        410
        readonly property int heaterHeight:       420

        readonly property bool streamMode:  !!root.activeUnit && root.activeUnit.type === "stream"
        readonly property bool heaterMode:  !!root.activeUnit && root.activeUnit.type === "heater"
        readonly property bool coolerMode:  !!root.activeUnit && root.activeUnit.type === "cooler"
        readonly property bool hexMode:     !!root.activeUnit && root.activeUnit.type === "heat_exchanger"

        width:  streamMode  ? streamWidth
              : (heaterMode || coolerMode || hexMode) ? heaterWidth
              : columnNormalWidth
        height: streamMode  ? streamHeight
              : (heaterMode || coolerMode || hexMode) ? heaterHeight
              : columnNormalHeight

        active: visible && root.activePanel === floatingWorkspace

        onXChanged: root.capturePanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos")
        onYChanged: root.capturePanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos")
        onWidthChanged: Qt.callLater(function() { root.applyPanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos", 40, 40) })
        onHeightChanged: Qt.callLater(function() { root.applyPanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos", 40, 40) })
        Component.onCompleted: Qt.callLater(function() { root.applyPanelRelativePosition(floatingWorkspace, "floatingWorkspacePos", "floatingWorkspaceRelPos", 40, 40) })
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
                    if (t === "heater")       return heaterWorkspaceComponent
                    if (t === "cooler")       return coolerWorkspaceComponent
                    if (t === "heat_exchanger") return hexWorkspaceComponent
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

        Component {
            id: hexWorkspaceComponent
            HeatExchangerWorkspaceWindow {
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
        id: unitsFormatSettingsDialog
        visible: false
        z: 560
        width: 760
        height: Math.min(root.height - 48, 560)
        x: Math.max(24, Math.min(root.width - width - 24, (root.width - width) / 2))
        y: Math.max(24, Math.min(root.height - height - 24, (root.height - height) / 2))
        focus: visible

        property int currentTab: 0
        property string unitsStatusText: ""
        property string formatsStatusText: ""

        function refreshSetModels() {
            if (typeof gUnits !== "undefined")
                unitsSetCombo.model = gUnits.unitSetNames()
            if (typeof gFormats !== "undefined")
                formatSetCombo.model = gFormats.formatSetNames()
        }

        function close() {
            visible = false
        }

        onVisibleChanged: if (visible) refreshSetModels()

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#eef3f6"
            border.color: "#7f8f9b"
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

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
                    text: "Units & Number Formats"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#17212b"
                }

                Rectangle {
                    width: 22; height: 22
                    radius: 4
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: closeUnitsSettingsMouse.containsMouse ? "#cdd7de" : "transparent"
                    border.color: closeUnitsSettingsMouse.containsMouse ? "#8fa0ac" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        color: "#31414d"
                    }
                    MouseArea {
                        id: closeUnitsSettingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: unitsFormatSettingsDialog.close()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 124
                    Layout.preferredHeight: 26
                    radius: 4
                    color: unitsFormatSettingsDialog.currentTab === 0 ? "#ffffff" : "#d7e0e6"
                    border.color: unitsFormatSettingsDialog.currentTab === 0 ? "#7f8f9b" : "#a3b0b9"
                    Text {
                        anchors.centerIn: parent
                        text: "Units"
                        font.pixelSize: 11
                        font.bold: unitsFormatSettingsDialog.currentTab === 0
                        color: "#17212b"
                    }
                    MouseArea { anchors.fill: parent; onClicked: unitsFormatSettingsDialog.currentTab = 0 }
                }
                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.preferredHeight: 26
                    radius: 4
                    color: unitsFormatSettingsDialog.currentTab === 1 ? "#ffffff" : "#d7e0e6"
                    border.color: unitsFormatSettingsDialog.currentTab === 1 ? "#7f8f9b" : "#a3b0b9"
                    Text {
                        anchors.centerIn: parent
                        text: "Number Formats"
                        font.pixelSize: 11
                        font.bold: unitsFormatSettingsDialog.currentTab === 1
                        color: "#17212b"
                    }
                    MouseArea { anchors.fill: parent; onClicked: unitsFormatSettingsDialog.currentTab = 1 }
                }
                Item { Layout.fillWidth: true }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: unitsFormatSettingsDialog.currentTab

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Active unit set"
                                font.pixelSize: 11
                                color: "#344451"
                            }
                            ComboBox {
                                id: unitsSetCombo
                                Layout.preferredWidth: 160
                                implicitHeight: 22
                                font.pixelSize: 11
                                model: []
                                background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                                contentItem: Text {
                                    leftPadding: 4
                                    rightPadding: 18
                                    text: unitsSetCombo.displayText
                                    color: "#1c4ea7"
                                    font.pixelSize: 11
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Component.onCompleted: unitsFormatSettingsDialog.refreshSetModels()
                                onActivated: {
                                    if (typeof gUnits !== "undefined")
                                        gUnits.activeUnitSet = model[index]
                                }
                                Connections {
                                    target: (typeof gUnits !== "undefined") ? gUnits : null
                                    ignoreUnknownSignals: true
                                    function onActiveUnitSetChanged() {
                                        if (typeof gUnits === "undefined") return
                                        var names = gUnits.unitSetNames()
                                        unitsSetCombo.model = names
                                        var i = names.indexOf(gUnits.activeUnitSet)
                                        unitsSetCombo.currentIndex = i >= 0 ? i : 0
                                    }
                                }
                            }
                            TextField {
                                id: cloneUnitSetField
                                Layout.preferredWidth: 140
                                implicitHeight: 22
                                font.pixelSize: 11
                                placeholderText: "New set name"
                                selectByMouse: true
                                background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                            }
                            Rectangle {
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 22
                                radius: 4
                                color: cloneUnitSetMouse.containsMouse ? "#d6e6f5" : "#e7edf2"
                                border.color: "#8ea0ad"
                                Text { anchors.centerIn: parent; text: "Clone"; font.pixelSize: 11; color: "#22303a" }
                                MouseArea {
                                    id: cloneUnitSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (typeof gUnits === "undefined") return
                                        var newName = cloneUnitSetField.text.trim()
                                        if (newName.length === 0) {
                                            unitsFormatSettingsDialog.unitsStatusText = "Enter a new unit-set name."
                                        } else if (gUnits.cloneUnitSet(gUnits.activeUnitSet, newName)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            gUnits.activeUnitSet = newName
                                            cloneUnitSetField.text = ""
                                            unitsFormatSettingsDialog.unitsStatusText = "Cloned unit set."
                                        } else {
                                            unitsFormatSettingsDialog.unitsStatusText = "Clone failed. Name may already exist."
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 22
                                radius: 4
                                color: renameUnitSetMouse.containsMouse ? "#d6e6f5" : "#e7edf2"
                                border.color: "#8ea0ad"
                                Text { anchors.centerIn: parent; text: "Rename"; font.pixelSize: 11; color: "#22303a" }
                                MouseArea {
                                    id: renameUnitSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (typeof gUnits === "undefined") return
                                        var newName = cloneUnitSetField.text.trim()
                                        if (newName.length === 0) {
                                            unitsFormatSettingsDialog.unitsStatusText = "Enter a new unit-set name."
                                        } else if (gUnits.renameUnitSet(gUnits.activeUnitSet, newName)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            gUnits.activeUnitSet = newName
                                            cloneUnitSetField.text = ""
                                            unitsFormatSettingsDialog.unitsStatusText = "Renamed unit set."
                                        } else {
                                            unitsFormatSettingsDialog.unitsStatusText = "Rename failed. Built-in sets cannot be renamed."
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 22
                                radius: 4
                                color: deleteUnitSetMouse.containsMouse ? "#f1d9d9" : "#f7e8e8"
                                border.color: "#b88f8f"
                                opacity: (typeof gUnits !== "undefined" && !gUnits.isBuiltInUnitSet(gUnits.activeUnitSet)) ? 1.0 : 0.55
                                Text { anchors.centerIn: parent; text: "Delete"; font.pixelSize: 11; color: "#7a2d2d" }
                                MouseArea {
                                    id: deleteUnitSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: (typeof gUnits !== "undefined" && !gUnits.isBuiltInUnitSet(gUnits.activeUnitSet))
                                    onClicked: {
                                        if (typeof gUnits === "undefined") return
                                        var doomed = gUnits.activeUnitSet
                                        if (gUnits.deleteUnitSet(doomed)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            unitsFormatSettingsDialog.unitsStatusText = "Deleted unit set."
                                        } else {
                                            unitsFormatSettingsDialog.unitsStatusText = "Delete failed."
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.maximumWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                horizontalAlignment: Text.AlignRight
                                text: (typeof gUnits !== "undefined" && gUnits.isBuiltInUnitSet(gUnits.activeUnitSet))
                                      ? "Built-in sets are read-only — clone to edit"
                                      : "Editing active custom set"
                                font.pixelSize: 10
                                color: "#526571"
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: unitsFormatSettingsDialog.unitsStatusText
                            visible: text.length > 0
                            font.pixelSize: 10
                            color: text.indexOf("failed") >= 0 ? "#9c2f2f" : "#526571"
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#f8fbfc"
                            border.color: "#a8b5bf"
                            border.width: 1
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 1
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 24
                                    color: "#dfe7ec"
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 12
                                        Text { width: 200; anchors.verticalCenter: parent.verticalCenter; text: "Quantity"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                        Text { width: 140; anchors.verticalCenter: parent.verticalCenter; text: "Display Unit"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    Column {
                                        width: parent.width
                                        Repeater {
                                            model: (typeof gUnits !== "undefined") ? gUnits.knownQuantities() : []
                                            delegate: Rectangle {
                                                width: parent ? parent.width : 0
                                                height: 22
                                                color: index % 2 === 0 ? "#ffffff" : "#f3f7f9"
                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 12
                                                    Text {
                                                        width: 200
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData
                                                        font.pixelSize: 11
                                                        color: "#17212b"
                                                        elide: Text.ElideRight
                                                    }
                                                    Loader {
                                                        width: 140
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        sourceComponent: (typeof gUnits !== "undefined" && !gUnits.isBuiltInUnitSet(gUnits.activeUnitSet)) ? unitEditorComponent : unitReadOnlyComponent
                                                        onLoaded: {
                                                            if (item) item.quantityName = modelData
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Active format set"
                                font.pixelSize: 11
                                color: "#344451"
                            }
                            ComboBox {
                                id: formatSetCombo
                                Layout.preferredWidth: 170
                                implicitHeight: 22
                                font.pixelSize: 11
                                model: []
                                background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                                contentItem: Text {
                                    leftPadding: 4
                                    rightPadding: 18
                                    text: formatSetCombo.displayText
                                    color: "#1c4ea7"
                                    font.pixelSize: 11
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Component.onCompleted: unitsFormatSettingsDialog.refreshSetModels()
                                onActivated: {
                                    if (typeof gFormats !== "undefined")
                                        gFormats.activeFormatSet = model[index]
                                }
                                Connections {
                                    target: (typeof gFormats !== "undefined") ? gFormats : null
                                    ignoreUnknownSignals: true
                                    function onActiveFormatSetChanged() {
                                        if (typeof gFormats === "undefined") return
                                        var names = gFormats.formatSetNames()
                                        formatSetCombo.model = names
                                        var i = names.indexOf(gFormats.activeFormatSet)
                                        formatSetCombo.currentIndex = i >= 0 ? i : 0
                                    }
                                    function onFormatsChanged() {
                                        formatSetCombo.model = (typeof gFormats !== "undefined") ? gFormats.formatSetNames() : []
                                    }
                                }
                            }
                            TextField {
                                id: cloneFormatSetField
                                Layout.preferredWidth: 140
                                implicitHeight: 22
                                font.pixelSize: 11
                                placeholderText: "New set name"
                                selectByMouse: true
                                background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                            }
                            Rectangle {
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 22
                                radius: 4
                                color: cloneFormatSetMouse.containsMouse ? "#d6e6f5" : "#e7edf2"
                                border.color: "#8ea0ad"
                                Text { anchors.centerIn: parent; text: "Clone"; font.pixelSize: 11; color: "#22303a" }
                                MouseArea {
                                    id: cloneFormatSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (typeof gFormats === "undefined") return
                                        var newName = cloneFormatSetField.text.trim()
                                        if (newName.length === 0) {
                                            unitsFormatSettingsDialog.formatsStatusText = "Enter a new format-set name."
                                        } else if (gFormats.cloneFormatSet(gFormats.activeFormatSet, newName)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            gFormats.activeFormatSet = newName
                                            cloneFormatSetField.text = ""
                                            unitsFormatSettingsDialog.formatsStatusText = "Cloned format set."
                                        } else {
                                            unitsFormatSettingsDialog.formatsStatusText = "Clone failed. Name may already exist."
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 22
                                radius: 4
                                color: renameFormatSetMouse.containsMouse ? "#d6e6f5" : "#e7edf2"
                                border.color: "#8ea0ad"
                                Text { anchors.centerIn: parent; text: "Rename"; font.pixelSize: 11; color: "#22303a" }
                                MouseArea {
                                    id: renameFormatSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (typeof gFormats === "undefined") return
                                        var newName = cloneFormatSetField.text.trim()
                                        if (newName.length === 0) {
                                            unitsFormatSettingsDialog.formatsStatusText = "Enter a new format-set name."
                                        } else if (gFormats.renameFormatSet(gFormats.activeFormatSet, newName)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            gFormats.activeFormatSet = newName
                                            cloneFormatSetField.text = ""
                                            unitsFormatSettingsDialog.formatsStatusText = "Renamed format set."
                                        } else {
                                            unitsFormatSettingsDialog.formatsStatusText = "Rename failed. Built-in sets cannot be renamed."
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 22
                                radius: 4
                                color: deleteFormatSetMouse.containsMouse ? "#f1d9d9" : "#f7e8e8"
                                border.color: "#b88f8f"
                                opacity: (typeof gFormats !== "undefined" && !gFormats.isBuiltInFormatSet(gFormats.activeFormatSet)) ? 1.0 : 0.55
                                Text { anchors.centerIn: parent; text: "Delete"; font.pixelSize: 11; color: "#7a2d2d" }
                                MouseArea {
                                    id: deleteFormatSetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: (typeof gFormats !== "undefined" && !gFormats.isBuiltInFormatSet(gFormats.activeFormatSet))
                                    onClicked: {
                                        if (typeof gFormats === "undefined") return
                                        if (gFormats.deleteFormatSet(gFormats.activeFormatSet)) {
                                            unitsFormatSettingsDialog.refreshSetModels()
                                            unitsFormatSettingsDialog.formatsStatusText = "Deleted format set."
                                        } else {
                                            unitsFormatSettingsDialog.formatsStatusText = "Delete failed."
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.maximumWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                horizontalAlignment: Text.AlignRight
                                text: (typeof gFormats !== "undefined" && gFormats.isBuiltInFormatSet(gFormats.activeFormatSet))
                                      ? "Built-in sets are read-only — clone to edit"
                                      : "Editing active custom set"
                                font.pixelSize: 10
                                color: "#526571"
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: unitsFormatSettingsDialog.formatsStatusText
                            visible: text.length > 0
                            font.pixelSize: 10
                            color: text.indexOf("failed") >= 0 ? "#9c2f2f" : "#526571"
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#f8fbfc"
                            border.color: "#a8b5bf"
                            border.width: 1
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 1
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 24
                                    color: "#dfe7ec"
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 10
                                        Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Quantity"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                        Text { width: 80; anchors.verticalCenter: parent.verticalCenter; text: "Mode"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                        Text { width: 50; anchors.verticalCenter: parent.verticalCenter; text: "Digits"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                        Text { width: 60; anchors.verticalCenter: parent.verticalCenter; text: "Exp sw"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                        Text { width: 100; anchors.verticalCenter: parent.verticalCenter; text: "Sample"; font.pixelSize: 11; font.bold: true; color: "#22303a" }
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    Column {
                                        width: parent.width
                                        Repeater {
                                            model: (typeof gFormats !== "undefined") ? gFormats.knownQuantities() : []
                                            delegate: Rectangle {
                                                width: parent ? parent.width : 0
                                                height: 22
                                                color: index % 2 === 0 ? "#ffffff" : "#f3f7f9"

                                                function modeText(kind) {
                                                    if (kind === 0) return "Fixed"
                                                    if (kind === 1) return "SigFig"
                                                    if (kind === 2) return "Exp"
                                                    return "—"
                                                }

                                                function sampleValueFor(quantity) {
                                                    switch (quantity) {
                                                    case "Temperature": return 25.0
                                                    case "Pressure": return 2175.0
                                                    case "MassFlow": return 100000.0
                                                    case "MolarFlow": return 467.575
                                                    case "VolumeFlow": return 0.1299
                                                    case "MassFraction": return 0.045
                                                    case "MoleFraction": return 0.045
                                                    case "VapourFraction": return 0.5
                                                    case "MolarMass": return 78.11
                                                    case "Density": return 876.45
                                                    case "SpecificEnthalpy": return 123456.0
                                                    case "SpecificEntropy": return 1.765
                                                    case "SpecificHeat": return 2.314
                                                    case "Viscosity": return 0.0008945
                                                    case "ThermalConductivity": return 0.1234
                                                    case "SurfaceTension": return 0.0725
                                                    case "KValue": return 0.001234
                                                    case "SpecificGravity": return 0.543
                                                    case "Acentric": return 0.047
                                                    case "Omega": return 0.047
                                                    default: return 12.3456
                                                    }
                                                }

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 10
                                                    Text {
                                                        width: 160
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData
                                                        font.pixelSize: 11
                                                        color: "#17212b"
                                                        elide: Text.ElideRight
                                                    }
                                                    Loader {
                                                        width: 80
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        sourceComponent: (typeof gFormats !== "undefined" && !gFormats.isBuiltInFormatSet(gFormats.activeFormatSet)) ? formatModeEditorComponent : formatReadOnlyModeComponent
                                                        onLoaded: {
                                                            if (item) item.quantityName = modelData
                                                        }
                                                    }
                                                    Loader {
                                                        width: 50
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        sourceComponent: (typeof gFormats !== "undefined" && !gFormats.isBuiltInFormatSet(gFormats.activeFormatSet)) ? digitsEditorComponent : digitsReadOnlyComponent
                                                        onLoaded: {
                                                            if (item) item.quantityName = modelData
                                                        }
                                                    }
                                                    Loader {
                                                        width: 60
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        sourceComponent: (typeof gFormats !== "undefined" && !gFormats.isBuiltInFormatSet(gFormats.activeFormatSet)) ? expEditorComponent : expReadOnlyComponent
                                                        onLoaded: {
                                                            if (item) item.quantityName = modelData
                                                        }
                                                    }
                                                    Text {
                                                        width: 100
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: (typeof gFormats !== "undefined") ? gFormats.formatValue(modelData, sampleValueFor(modelData)) : ""
                                                        font.pixelSize: 11
                                                        color: "#1c4ea7"
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: unitReadOnlyComponent
                Text {
                    property string quantityName: ""
                    text: (typeof gUnits !== "undefined" && quantityName !== "") ? gUnits.unitForSet(gUnits.activeUnitSet, quantityName) : ""
                    font.pixelSize: 11
                    color: "#1c4ea7"
                    elide: Text.ElideRight
                }
            }

            Component {
                id: unitEditorComponent
                ComboBox {
                    id: unitSetEditorCombo
                    property string quantityName: ""
                    width: 140
                    implicitHeight: 20
                    font.pixelSize: 11
                    model: (typeof gUnits !== "undefined" && quantityName !== "") ? gUnits.unitsFor(quantityName) : []

                    function refreshSelection() {
                        if (typeof gUnits === "undefined" || quantityName === "") {
                            currentIndex = -1
                            return
                        }
                        var u = gUnits.unitForSet(gUnits.activeUnitSet, quantityName)
                        currentIndex = model.indexOf(u)
                    }

                    Component.onCompleted: refreshSelection()
                    onModelChanged: refreshSelection()
                    onQuantityNameChanged: refreshSelection()

                    background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                    contentItem: Text {
                        leftPadding: 4; rightPadding: 18
                        text: (unitSetEditorCombo.currentIndex >= 0 && unitSetEditorCombo.currentIndex < unitSetEditorCombo.model.length) ? unitSetEditorCombo.model[unitSetEditorCombo.currentIndex] : ""
                        font.pixelSize: 11
                        color: "#1c4ea7"
                        verticalAlignment: Text.AlignVCenter
                    }
                    onActivated: {
                        if (typeof gUnits !== "undefined" && quantityName !== "") {
                            gUnits.setUnitForQuantity(gUnits.activeUnitSet, quantityName, model[index])
                            refreshSelection()
                        }
                    }
                    Connections {
                        target: (typeof gUnits !== "undefined") ? gUnits : null
                        ignoreUnknownSignals: true
                        function onActiveUnitSetChanged() { unitSetEditorCombo.refreshSelection() }
                        function onUnitsChanged() { unitSetEditorCombo.refreshSelection() }
                    }
                }
            }

            Component {
                id: formatReadOnlyModeComponent
                Text {
                    property string quantityName: ""
                    text: {
                        if (typeof gFormats === "undefined" || quantityName === "") return ""
                        var k = gFormats.formatKind(quantityName)
                        return k === 0 ? "Fixed" : (k === 1 ? "SigFig" : (k === 2 ? "Exp" : "—"))
                    }
                    font.pixelSize: 11
                    color: "#17212b"
                }
            }

            Component {
                id: formatModeEditorComponent
                ComboBox {
                    id: formatModeCombo
                    property string quantityName: ""
                    width: 80
                    implicitHeight: 20
                    font.pixelSize: 11
                    model: ["Fixed", "SigFig", "Exp"]

                    function refreshSelection() {
                        if (typeof gFormats === "undefined" || quantityName === "") {
                            currentIndex = 0
                            return
                        }
                        currentIndex = gFormats.formatKind(quantityName)
                    }

                    Component.onCompleted: refreshSelection()
                    onModelChanged: refreshSelection()
                    onQuantityNameChanged: refreshSelection()

                    background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
                    contentItem: Text {
                        leftPadding: 4; rightPadding: 18
                        text: (formatModeCombo.currentIndex >= 0 && formatModeCombo.currentIndex < formatModeCombo.model.length) ? formatModeCombo.model[formatModeCombo.currentIndex] : ""
                        font.pixelSize: 11
                        color: "#17212b"
                        verticalAlignment: Text.AlignVCenter
                    }
                    onActivated: if (typeof gFormats !== "undefined" && quantityName !== "") gFormats.setSpec(gFormats.activeFormatSet, quantityName, index, gFormats.decimals(quantityName), gFormats.expSwitch(quantityName))
                    Connections {
                        target: (typeof gFormats !== "undefined") ? gFormats : null
                        ignoreUnknownSignals: true
                        function onActiveFormatSetChanged() { formatModeCombo.refreshSelection() }
                        function onFormatsChanged() { formatModeCombo.refreshSelection() }
                    }
                }
            }

            Component {
                id: digitsReadOnlyComponent
                Text {
                    property string quantityName: ""
                    text: (typeof gFormats !== "undefined" && quantityName !== "") ? String(gFormats.decimals(quantityName)) : ""
                    font.pixelSize: 11
                    color: "#17212b"
                }
            }

            Component {
                id: digitsEditorComponent
                SpinBox {
                    id: digitsSpin
                    property string quantityName: ""
                    width: 50
                    implicitHeight: 20
                    from: 0; to: 12
                    editable: true
                    font.pixelSize: 11

                    function refreshValue() {
                        if (typeof gFormats === "undefined" || quantityName === "") {
                            value = 0
                            return
                        }
                        value = gFormats.decimals(quantityName)
                    }

                    Component.onCompleted: refreshValue()
                    onQuantityNameChanged: refreshValue()

                    contentItem: TextInput {
                        text: digitsSpin.textFromValue(digitsSpin.value, digitsSpin.locale)
                        font.pixelSize: 11
                        color: "#17212b"
                        horizontalAlignment: Qt.AlignHCenter
                        verticalAlignment: Qt.AlignVCenter
                        readOnly: !digitsSpin.editable
                        validator: digitsSpin.validator
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        selectByMouse: true
                    }

                    onValueModified: if (typeof gFormats !== "undefined" && quantityName !== "") gFormats.setSpec(gFormats.activeFormatSet, quantityName, gFormats.formatKind(quantityName), value, gFormats.expSwitch(quantityName))
                    Connections {
                        target: (typeof gFormats !== "undefined") ? gFormats : null
                        ignoreUnknownSignals: true
                        function onActiveFormatSetChanged() { digitsSpin.refreshValue() }
                        function onFormatsChanged() { digitsSpin.refreshValue() }
                    }
                }
            }

            Component {
                id: expReadOnlyComponent
                Text {
                    property string quantityName: ""
                    text: (typeof gFormats !== "undefined" && quantityName !== "") ? String(gFormats.expSwitch(quantityName)) : ""
                    font.pixelSize: 11
                    color: "#17212b"
                }
            }

            Component {
                id: expEditorComponent
                SpinBox {
                    id: expSpin
                    property string quantityName: ""
                    width: 70
                    implicitHeight: 20
                    from: 0; to: 12
                    editable: true
                    font.pixelSize: 11

                    function refreshValue() {
                        if (typeof gFormats === "undefined" || quantityName === "") {
                            value = 5
                            return
                        }
                        value = gFormats.expSwitch(quantityName)
                    }

                    Component.onCompleted: refreshValue()
                    onQuantityNameChanged: refreshValue()

                    contentItem: TextInput {
                        text: expSpin.textFromValue(expSpin.value, expSpin.locale)
                        font.pixelSize: 11
                        color: "#17212b"
                        horizontalAlignment: Qt.AlignHCenter
                        verticalAlignment: Qt.AlignVCenter
                        readOnly: !expSpin.editable
                        validator: expSpin.validator
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        selectByMouse: true
                    }

                    onValueModified: if (typeof gFormats !== "undefined" && quantityName !== "") gFormats.setSpec(gFormats.activeFormatSet, quantityName, gFormats.formatKind(quantityName), gFormats.decimals(quantityName), value)
                    Connections {
                        target: (typeof gFormats !== "undefined") ? gFormats : null
                        ignoreUnknownSignals: true
                        function onActiveFormatSetChanged() { expSpin.refreshValue() }
                        function onFormatsChanged() { expSpin.refreshValue() }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 72
                    height: 24
                    radius: 4
                    color: okUnitsSettingsMouse.containsMouse ? "#d6e6f5" : "#e7edf2"
                    border.color: "#8ea0ad"
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        font.pixelSize: 11
                        color: "#22303a"
                    }
                    MouseArea {
                        id: okUnitsSettingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: unitsFormatSettingsDialog.close()
                    }
                }
            }
        }

        Keys.onEscapePressed: close()
    }


    Item {
        id: stripperStatusHelpDialog
        visible: false
        z: 561
        width: 760
        height: Math.min(root.height - 48, 560)
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
                    text: "Stripper Status Help"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#17212b"
                }

                ClassicButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OK"
                    onClicked: stripperStatusHelpDialog.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: "#f6f9fb"
                border.color: "#c4d0d8"

                Flickable {
                    id: stripperStatusHelpFlick
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    contentWidth: width
                    contentHeight: stripperStatusHelpColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Column {
                        id: stripperStatusHelpColumn
                        width: stripperStatusHelpFlick.width - 8
                        spacing: 10

                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Understanding stripper run status"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#17212b"
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "The Stripper Run Results panel shows a compact status for the selected attached side stripper. The current user-facing statuses are OK, WARN, and FAIL. Detailed message text belongs on the Diagnostics panel."
                            font.pixelSize: 12
                            color: "#17212b"
                        }

                        Label { width: parent.width; wrapMode: Text.WordWrap; text: "Current coupling mode"; font.pixelSize: 13; font.bold: true; color: "#17212b" }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Mode = outer_iteration_reinject means the stripper is solved from the current liquid side-draw feed, then its vapor return is re-injected at the configured return tray on the next outer column iteration. Coupled = No means the inner stripper solve was usable, but the outer vapor-return recoupling did not settle within the current coupling tolerance before the coupled iteration limit was reached."
                            font.pixelSize: 12
                            color: "#17212b"
                        }

                        Label { width: parent.width; wrapMode: Text.WordWrap; text: "WARN statuses and how to fix them"; font.pixelSize: 13; font.bold: true; color: "#17212b" }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "1. Coupling not converged. This is the most common WARN after coupled vapor-return reinjection is enabled. It means Solve Conv = Yes, but Coupled = No because the vapor-return recoupling residual stayed above the coupling tolerance. Typical fixes: increase Max Coupled Iterations, loosen Coupling Tol slightly, or reduce Return Damping if the return is oscillating. If the solve is stable but simply slow, a moderate increase in Return Damping can help. Also review source tray, return tray, number of stripper trays, and heat value, because very aggressive settings can make recoupling harder to settle."
                            font.pixelSize: 12
                            color: "#17212b"
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "2. Warning diagnostics present. The displayed status is also set to WARN whenever the stripper summary contains warning-level diagnostics. Open the Diagnostics panel and look for messages with the selected stripper label. Fix the specific warning shown there. In general, warnings are reduced by using physically reasonable tray locations, modest heat input, positive liquid side-draw feed, and convergence settings that are not tighter than necessary."
                            font.pixelSize: 12
                            color: "#17212b"
                        }

                        Label { width: parent.width; wrapMode: Text.WordWrap; text: "FAIL statuses and how to fix them"; font.pixelSize: 13; font.bold: true; color: "#17212b" }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "1. Internal stripper solve did not converge. This occurs when the stripper itself did not produce a usable result during the coupled solve. Fixes: reduce the severity of the stripper specification, check the return tray and number of trays, reduce extreme heat values, and inspect the Diagnostics panel for the selected stripper. If the case is marginal, a looser coupling tolerance or more coupled iterations may help the outer loop, but the inner stripper spec still needs to be physically reasonable."
                            font.pixelSize: 12
                            color: "#17212b"
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "2. No usable positive liquid side-draw feed. Internally the solver can mark this as SKIPPED, but the user-facing status is shown as FAIL so the Stripper Run Results panel stays within OK / WARN / FAIL. This usually means the selected source tray did not provide a positive liquid draw for that stripper. Fixes: make sure the draw is liquid, move the source tray to a location with real liquid traffic, reduce competing draws, review feed location and column conditions, or reduce an overly aggressive heat setting that strips away the liquid draw."
                            font.pixelSize: 12
                            color: "#17212b"
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "3. Error diagnostics present. The displayed status is also set to FAIL whenever the stripper summary contains error-level diagnostics. Open the Diagnostics panel, find the selected stripper name, and fix the specific error reported there first."
                            font.pixelSize: 12
                            color: "#17212b"
                        }

                        Label { width: parent.width; wrapMode: Text.WordWrap; text: "Recommended tuning order"; font.pixelSize: 13; font.bold: true; color: "#17212b" }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "For a WARN caused by coupling not converging: first increase Max Coupled Iterations, then loosen Coupling Tol slightly, then adjust Return Damping. Lower damping is usually more stable; higher damping may reduce iteration count when the case is already stable, but it can also oscillate and increase total solve time. If the warning persists, review the stripper tray locations and heat setting."
                            font.pixelSize: 12
                            color: "#17212b"
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "For a FAIL: inspect the Diagnostics panel before changing tolerances blindly. FAIL usually indicates either no usable liquid feed at the source tray or that the internal stripper solve could not converge to a usable result. Fixing the physical setup is usually more effective than only increasing iteration limits."
                            font.pixelSize: 12
                            color: "#17212b"
                        }
                    }
                }
            }
        }

        Keys.onEscapePressed: stripperStatusHelpDialog.close()
    }

    Item {
        id: solverConvergenceHelpDialog
        visible: false
        z: 560
        width: 640
        height: solverConvergenceHelpColumn.implicitHeight + 18
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
            id: solverConvergenceHelpColumn
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
                    text: "Solver Convergence Settings"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#17212b"
                }

                ClassicButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OK"
                    onClicked: solverConvergenceHelpDialog.close()
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Column settings\n\nMax Outer Iterations: Maximum number of main column outer iterations before the solve stops. Higher values can help difficult cases converge, but may increase solve time.\n\nOuter Convergence Tolerance: Main column outer-loop convergence target. Smaller values usually give tighter convergence but require more iterations and longer solve times.\n\nAttached side stripper settings\n\nMax Coupled Iterations: Maximum number of coupled stripper iterations allowed during the solve. Higher values can improve coupled return stabilization, but can increase solve time.\n\nCoupling Tolerance: Target tolerance for attached-stripper vapor return stabilization. Smaller values tighten coupling and usually increase solve time.\n\nReturn Damping: Blends the new stripper vapor return with the previous one. Lower values are usually more stable but may converge more slowly. Higher values may reduce iteration count when stable, but can oscillate and sometimes increase total solve time.\n\nRecommended starting values\n\nColumn: Max Outer Iterations = 100, Outer Convergence Tolerance = 1e-4\nStripper: Max Coupled Iterations = 25, Coupling Tolerance = 1e-3, Return Damping = 0.35"
                color: "#17212b"
                font.pixelSize: 12
            }
        }

        Keys.onEscapePressed: solverConvergenceHelpDialog.close()
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
