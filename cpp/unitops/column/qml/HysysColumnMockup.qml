import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ============================================================
//  HysysColumnMockup.qml
//  A HYSYS-style tabbed column view wired to ColumnUnitState.
//
//  appState  →  ColumnUnitState*  (exposed from C++ as QObject*)
//
//  Worksheet tab is split into two sub-tabs:
//    • "Setup"  – General, Thermodynamics, Efficiencies
//    • "Draws/Solver"  – Draw Specifications, Solve/Status
// ============================================================

Rectangle {
    id: root
    width:  1340
    height: 920
    color: appBg

    // ── State binding ──────────────────────────────────────────
    property var appState: null

    // ── Palette  (mirrors StreamView chrome colours) ───────────
    readonly property color appBg:        "#d7dbe3"
    readonly property color panelBg:      "#e3e7ee"
    readonly property color cardBg:       "#dfe4ec"
    readonly property color cardHeaderBg: "#cfd7e3"
    readonly property color tabIdleBg:    "#cfd5de"
    readonly property color tabActiveBg:  "#2e76db"   // matches StreamView activeBlue
    readonly property color gridLine:     "#9ba8bf"
    readonly property color outerBorder:  "#2a2a2a"   // matches StreamView border
    readonly property color textDark:     "#1f2430"   // matches StreamView textDark
    readonly property color textMuted:    "#5a6472"   // matches StreamView mutedText
    readonly property color valueBlue:    "#1c4ea7"   // matches StreamView textBlue
    readonly property color softBlue:     "#e8eef8"
    readonly property color softYellow:   "#efe6ad"
    readonly property color buttonBg:     "#f0f2f4"
    readonly property color white:        "#ffffff"
    readonly property color warnAmber:    "#d6b74a"
    readonly property color errorRed:     "#b23b3b"

    // ── Font sizes – match StreamConditionsPanel (11–13 px) ───
    readonly property int fsSectionHeader: 13   // card title
    readonly property int fsLabel:         11   // row labels
    readonly property int fsValue:         11   // row values
    readonly property int fsTabBtn:        12   // tab button text
    readonly property int fsSmall:         10   // unit suffix / sub-labels

    // ── Active-tab state ──────────────────────────────────────
    property string activeTab:         "Worksheet/Solver"
    property string worksheetSubTab:   "Setup"       // "Setup" | "Draws/Solver"
    property string profilesSubTab:    "Tray Table"  // "Tray Table" | "Visual Profiles"

    // ── Helpers ───────────────────────────────────────────────
    function isNumericLike(v) {
        if (v === undefined || v === null) return false
        return /[0-9]/.test(String(v))
    }
    function fmt2(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(2)  : "—" }
    function fmt3(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(3)  : "—" }
    function fmtMs(ms) {
        const s = Math.floor((ms || 0) / 1000)
        return String(Math.floor(s / 60)).padStart(2,"0") + ":" + String(s % 60).padStart(2,"0")
    }
    function eosLabel() {
        if (!appState) return "—"
        return (appState.eosMode === "manual") ? appState.eosManual : "Auto"
    }
    function condenserSpecLabel() {
        if (!appState) return "—"
        const s = (appState.condenserSpec || "").toLowerCase()
        if (s === "refluxratio" || s === "reflux") return "Reflux Ratio"
        if (s === "duty")        return "Fixed Duty"
        if (s === "temperature") return "Temperature Setpoint"
        return appState.condenserSpec || "—"
    }
    function reboilerSpecLabel() {
        if (!appState) return "—"
        const s = (appState.reboilerSpec || "").toLowerCase()
        if (s === "boilup" || s === "boilupratio") return "Boilup Ratio"
        if (s === "duty")        return "Fixed Duty"
        if (s === "temperature") return "Temperature Setpoint"
        return appState.reboilerSpec || "—"
    }
    function solveStatus() {
        if (!appState) return "—"
        if (appState.solving) return "Solving…"
        if (appState.solved)  return "Converged"
        if (appState.specsDirty) return "Specs changed – re-run"
        return "Not solved"
    }
    function solveStatusColor() {
        if (!appState) return textMuted
        if (appState.solving)    return warnAmber
        if (appState.solved)     return "#1a7a3c"
        if (appState.specsDirty) return warnAmber
        return errorRed
    }

    // ── Outer chrome ──────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "transparent"
        border.color: outerBorder
        border.width: 1
    }

    // ── Top tab bar ───────────────────────────────────────
    Row {
        id: topTabs
        x: 18; y: 8
        spacing: 8

        Repeater {
            model: ["Worksheet/Solver","Performance","Profiles","Products","Run Log","Diagnostics"]
            delegate: Rectangle {
                width:  modelData === "Worksheet/Solver" ? 130 : modelData === "Diagnostics" ? 108 : 100
                height: 30
                radius: 10
                color:  root.activeTab === modelData ? tabActiveBg : tabIdleBg
                border.color: outerBorder; border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: fsTabBtn; font.bold: true
                    color: root.activeTab === modelData ? white : textDark
                }
                MouseArea { anchors.fill: parent; onClicked: root.activeTab = modelData }
            }
        }
    }

    // ── Workspace frame ───────────────────────────────────────
    Rectangle {
        id: workspaceFrame
        x: 18; y: 50
        width: parent.width - 36
        height: parent.height - 60
        radius: 12
        color: panelBg
        border.color: outerBorder; border.width: 1
    }

    // ==========================================================
    //  INLINE COMPONENTS
    // ==========================================================

    // Card frame (header bar + divider + title)
    component CardFrame: Rectangle {
        id: cf
        property string title: ""
        radius: 6; color: cardBg
        border.color: gridLine; border.width: 1

        Rectangle {
            anchors { left:parent.left; right:parent.right; top:parent.top }
            height: 30; radius: 6; color: cardHeaderBg
            // square off bottom corners
            Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:6; color:cardHeaderBg }
        }
        Rectangle {
            anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:29 }
            height: 1; color: gridLine
        }
        Text {
            x: 10; y: 8
            text: cf.title
            font.pixelSize: fsSectionHeader; font.bold: true
            color: textDark
        }
    }

    // A labelled row with a value box on the right (+ optional unit)
    component FieldRow: Item {
        id: fr
        property string label:  ""
        property string value:  ""
        property string unit:   ""
        property bool   editable: false
        signal committed(string newVal)

        height: 28

        Text {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            text: fr.label; color: textMuted
            font.pixelSize: fsLabel
        }

        // unit label (right-most)
        Text {
            visible: fr.unit !== ""
            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
            text: fr.unit; color: textMuted; font.pixelSize: fsSmall
        }

        // value box
        Rectangle {
            id: valueBox
            width:  120; height: parent.height - 8
            anchors {
                right:  fr.unit !== "" ? unitLbl.left : parent.right
                rightMargin: fr.unit !== "" ? 6 : 8
                verticalCenter: parent.verticalCenter
            }
            radius: 3
            color:  fr.editable ? buttonBg : "transparent"
            border.color: fr.editable ? gridLine : "transparent"
            border.width: fr.editable ? 1 : 0

            Text {
                anchors { right:parent.right; rightMargin:6; verticalCenter:parent.verticalCenter }
                text: fr.value; color: valueBlue; font.pixelSize: fsValue
            }
        }

        // invisible unit anchor item so we can reference it above
        Item { id: unitLbl; width:36; anchors { right:parent.right; rightMargin:0; verticalCenter:parent.verticalCenter } }
    }

    // Divider line inside a card
    component HDivider: Rectangle {
        height: 1; color: gridLine
    }

    // Simple column of FieldRows, drawn from a model array
    // model element: { label, value, unit? }
    component FieldTable: Column {
        id: ft
        property var rows: []
        spacing: 0
        anchors.left:  parent ? parent.left  : undefined
        anchors.right: parent ? parent.right : undefined

        Repeater {
            model: ft.rows
            delegate: Column {
                width: ft.width
                FieldRow {
                    width: parent.width
                    label: modelData.label || ""
                    value: modelData.value !== undefined ? String(modelData.value) : "—"
                    unit:  modelData.unit  || ""
                }
                HDivider { width: parent.width; visible: index < ft.rows.length - 1 }
            }
        }
    }

    // ── Tab button for sub-tabs ───────────────────────────────
    component SubTabBtn: Rectangle {
        id: stb
        property string label:    ""
        property bool   isActive: false
        signal clicked()
        width: 120; height: 26; radius: 8
        color: stb.isActive ? tabActiveBg : tabIdleBg
        border.color: outerBorder; border.width: 1
        Text {
            anchors.centerIn: parent; text: stb.label
            font.pixelSize: fsTabBtn; font.bold: true
            color: stb.isActive ? white : textDark
        }
        MouseArea { anchors.fill: parent; onClicked: stb.clicked() }
    }

    // ── Data table (header + scrollable rows) ─────────────────
    component DataGrid: Rectangle {
        id: dg
        property var  columns:      []
        property var  rows:         []
        property var  colRatios:    []   // relative widths; equal if empty
        radius: 6; color: cardBg
        border.color: outerBorder; border.width: 1

        function colW(i) {
            var tot = 0
            for (var t = 0; t < colRatios.length; ++t) tot += colRatios[t]
            if (tot <= 0) return width / Math.max(1, columns.length)
            return width * colRatios[i] / tot
        }

        // Header
        Rectangle {
            id: dgHeader
            anchors { left:parent.left; right:parent.right; top:parent.top }
            height: 32; color: cardHeaderBg
            Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:5; color:cardHeaderBg }

            Repeater {
                model: dg.columns.length
                delegate: Item {
                    x: { var s=0; for(var i=0;i<index;i++) s+=dg.colW(i); return s }
                    width: dg.colW(index); height: 32
                    Text {
                        x:8; anchors.verticalCenter:parent.verticalCenter
                        text: dg.columns[index]
                        font.pixelSize: fsLabel; font.bold: true; color: textDark
                    }
                    Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:gridLine;
                                visible: index < dg.columns.length-1 }
                }
            }
        }
        Rectangle {
            anchors { left:parent.left; right:parent.right; top:dgHeader.bottom }
            height: 1; color: gridLine
        }

        ListView {
            anchors { left:parent.left; right:parent.right; top:dgHeader.bottom; topMargin:1; bottom:parent.bottom }
            clip: true
            model: dg.rows
            delegate: Item {
                width: dg.width
                height: Math.max(30, (dg.height - 33) / Math.max(1, dg.rows.length))

                Rectangle { anchors { left:parent.left; right:parent.right; bottom:parent.bottom }
                            height:1; color:gridLine; visible: index < dg.rows.length-1 }

                Repeater {
                    model: dg.columns.length
                    delegate: Item {
                        x: { var s=0; for(var i=0;i<index;i++) s+=dg.colW(i); return s }
                        width: dg.colW(index); height: parent.height
                        Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:gridLine;
                                    visible: index < dg.columns.length-1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var row = dg.rows[parent.parent.parent.parent.index]  // ListView row data
                                if (!row) return ""
                                if (Array.isArray(row)) return row[index] !== undefined ? String(row[index]) : ""
                                return ""
                            }
                            color: index > 0 ? valueBlue : textDark
                            font.pixelSize: fsValue
                            x: (index > 0) ? parent.width - implicitWidth - 8 : 8
                        }
                    }
                }
            }
        }
    }

    // ==========================================================
    //  WORKSHEET TAB
    // ==========================================================
    Item {
        id: worksheetTab
        visible: root.activeTab === "Worksheet/Solver"
        anchors { fill: workspaceFrame; margins: 10 }

        Row {
            id: wsSubTabs
            spacing: 8
            SubTabBtn { label:"Setup"; isActive: root.worksheetSubTab === "Setup"; onClicked: root.worksheetSubTab = "Setup" }
            SubTabBtn { label:"Draws/Solver"; isActive: root.worksheetSubTab === "Draws/Solver"; onClicked: root.worksheetSubTab = "Draws/Solver" }
        }

        // ── Setup sub-tab ──────────────────────────────────────
        // Left:  General Setup (editable) + Thermodynamics (editable)
        // Right: Condenser (editable) + Reboiler (editable) + Murphree Efficiencies (editable)
        Item {
            id: wsSetup
            visible: root.worksheetSubTab === "Setup"
            anchors { left:parent.left; right:parent.right; top:wsSubTabs.bottom; topMargin:10; bottom:parent.bottom }

            property real colW:    (width - 12) / 2
            property int  rowH:    26
            property int  inputW:  120
            property int  unitW:   34
            readonly property color inputBg: "#f7f8fa"

            // ── LEFT COLUMN ────────────────────────────────────

            // General Setup
            CardFrame {
                id: generalCard
                title: "General Setup"
                x: 0; y: 0; width: wsSetup.colW
                height: generalCol.implicitHeight + 42

                Column {
                    id: generalCol
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                    spacing: 0

                    // Column Name
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Column Name"; color:textMuted; font.pixelSize:fsLabel }
                        TextField {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:Math.round(wsSetup.inputW * 2.5)
                            text: appState ? (appState.name || appState.id || "") : ""
                            font.pixelSize:fsValue; color:valueBlue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.name = text }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Feed Stream (read-only)
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Feed Stream"; color:textMuted; font.pixelSize:fsLabel }
                        Text { anchors { right:parent.right; rightMargin:10; verticalCenter:parent.verticalCenter }
                               text: appState && appState.feedStream ? (appState.feedStream.streamName || "—") : "—"
                               color:valueBlue; font.pixelSize:fsValue }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Fluid / Crude – stretches to fill available width so long crude names are fully visible
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { id:crudeLbl; x:10; anchors.verticalCenter:parent.verticalCenter; text:"Fluid / Crude"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            id: crudeCombo
                            anchors { left:crudeLbl.right; leftMargin:12; right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            implicitHeight: wsSetup.rowH
                            model: appState && appState.feedStream ? appState.feedStream.fluidNames : []
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; rightPadding:20; text:crudeCombo.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            Component.onCompleted: {
                                if (!appState || !appState.feedStream) return
                                var i = appState.feedStream.fluidNames.indexOf(appState.feedStream.selectedFluid)
                                if (i >= 0) currentIndex = i
                            }
                            onActivated: { if (appState && appState.feedStream) appState.feedStream.selectedFluid = model[index] }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Total Trays
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Total Trays"; color:textMuted; font.pixelSize:fsLabel }
                        SpinBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            from: appState ? appState.minTrays : 1
                            to:   appState ? appState.maxTrays : 200
                            value: appState ? appState.trays : 32
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onValueModified: { if (appState) appState.trays = value }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Feed Tray
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Feed Tray"; color:textMuted; font.pixelSize:fsLabel }
                        SpinBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            from:1; to: appState ? Math.max(1, appState.trays) : 32
                            value: appState ? appState.feedTray : 4
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onValueModified: { if (appState) appState.feedTray = value }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Feed Rate
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Feed Rate"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "kg/h"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState && appState.feedStream ? String(Math.round(appState.feedStream.flowRateKgph)) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState && appState.feedStream) appState.feedStream.flowRateKgph = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Feed Temperature
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Feed Temperature"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState && appState.feedStream ? fmt3(appState.feedStream.temperatureK) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState && appState.feedStream) appState.feedStream.temperatureK = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Top Pressure
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Top Pressure"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Pa"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? String(Math.round(appState.topPressurePa)) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.topPressurePa = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Pressure Drop/Tray
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Pressure Drop/Tray"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Pa"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? String(Math.round(appState.dpPerTrayPa)) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.dpPerTrayPa = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // T Overhead spec (editable)
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"T Overhead (spec)"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.topTsetK) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.topTsetK = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // T Bottoms spec (editable)
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"T Bottoms (spec)"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.bottomTsetK) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.bottomTsetK = Number(text) }
                        }
                    }
                }
            }

            // Murphree Efficiencies
            CardFrame {
                id: effCard
                title: "Murphree Efficiencies"
                x: 0
                y: generalCard.y + generalCard.height + 10
                width: wsSetup.colW
                height: wsSetup.height - y

                // Enable liquid efficiency toggle
                Item {
                    id: etaEnableRow
                    x:0; y:36; width:parent.width; height:wsSetup.rowH
                    Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Enable Liquid η"; color:textMuted; font.pixelSize:fsLabel }
                    CheckBox {
                        anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                        checked: appState ? appState.enableEtaL : false
                        onToggled: { if (appState) appState.enableEtaL = checked }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // Column headers
                Item {
                    id: etaHdrRow
                    anchors { left:parent.left; right:parent.right; top:etaEnableRow.bottom }
                    height: 26
                    property real secW: width * 0.22
                    property real etaW: width * 0.25
                    Text { x:10; anchors.verticalCenter:parent.verticalCenter; width:etaHdrRow.secW; text:"Section"; font.bold:true; font.pixelSize:fsSmall; color:textDark }
                    Text { x:10+etaHdrRow.secW; anchors.verticalCenter:parent.verticalCenter; width:etaHdrRow.etaW; text:"Vapour η"; font.bold:true; font.pixelSize:fsSmall; color:textDark; horizontalAlignment:Text.AlignRight }
                    Text { x:10+etaHdrRow.secW+etaHdrRow.etaW; anchors.verticalCenter:parent.verticalCenter; width:etaHdrRow.etaW; text:"Liquid η"; font.bold:true; font.pixelSize:fsSmall; color:textDark; horizontalAlignment:Text.AlignRight }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // Top
                Item {
                    id: etaTopRow
                    anchors { left:parent.left; right:parent.right; top:etaHdrRow.bottom }
                    height: wsSetup.rowH
                    property real secW: width * 0.22
                    property real etaW: width * 0.25
                    Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Top"; color:textMuted; font.pixelSize:fsLabel }
                    TextField {
                        x: 10+etaTopRow.secW; anchors.verticalCenter:parent.verticalCenter
                        width:etaTopRow.etaW-6
                        text: appState ? fmt3(appState.etaVTop) : ""
                        font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaVTop = Number(text) }
                    }
                    TextField {
                        x: 10+etaTopRow.secW+etaTopRow.etaW; anchors.verticalCenter:parent.verticalCenter
                        width:etaTopRow.etaW-6
                        enabled: appState ? appState.enableEtaL : false
                        text: appState ? fmt3(appState.etaLTop) : ""
                        font.pixelSize:fsValue; color:enabled ? valueBlue : textMuted; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:enabled ? wsSetup.inputBg : cardBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaLTop = Number(text) }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // Middle
                Item {
                    id: etaMidRow
                    anchors { left:parent.left; right:parent.right; top:etaTopRow.bottom }
                    height: wsSetup.rowH
                    property real secW: width * 0.22
                    property real etaW: width * 0.25
                    Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Middle"; color:textMuted; font.pixelSize:fsLabel }
                    TextField {
                        x: 10+etaMidRow.secW; anchors.verticalCenter:parent.verticalCenter
                        width:etaMidRow.etaW-6
                        text: appState ? fmt3(appState.etaVMid) : ""
                        font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaVMid = Number(text) }
                    }
                    TextField {
                        x: 10+etaMidRow.secW+etaMidRow.etaW; anchors.verticalCenter:parent.verticalCenter
                        width:etaMidRow.etaW-6
                        enabled: appState ? appState.enableEtaL : false
                        text: appState ? fmt3(appState.etaLMid) : ""
                        font.pixelSize:fsValue; color:enabled ? valueBlue : textMuted; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:enabled ? wsSetup.inputBg : cardBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaLMid = Number(text) }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // Bottom
                Item {
                    id: etaBotRow
                    anchors { left:parent.left; right:parent.right; top:etaMidRow.bottom }
                    height: wsSetup.rowH
                    property real secW: width * 0.22
                    property real etaW: width * 0.25
                    Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Bottom"; color:textMuted; font.pixelSize:fsLabel }
                    TextField {
                        x: 10+etaBotRow.secW; anchors.verticalCenter:parent.verticalCenter
                        width:etaBotRow.etaW-6
                        text: appState ? fmt3(appState.etaVBot) : ""
                        font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaVBot = Number(text) }
                    }
                    TextField {
                        x: 10+etaBotRow.secW+etaBotRow.etaW; anchors.verticalCenter:parent.verticalCenter
                        width:etaBotRow.etaW-6
                        enabled: appState ? appState.enableEtaL : false
                        text: appState ? fmt3(appState.etaLBot) : ""
                        font.pixelSize:fsValue; color:enabled ? valueBlue : textMuted; horizontalAlignment:Text.AlignRight
                        background: Rectangle { radius:3; color:enabled ? wsSetup.inputBg : cardBg; border.color:gridLine; border.width:1 }
                        onEditingFinished: { if (appState) appState.etaLBot = Number(text) }
                    }
                }
            }
            // ── RIGHT COLUMN ───────────────────────────────────

            // Condenser
            CardFrame {
                id: condCard
                title: "Condenser"
                x: wsSetup.colW + 12; y: 0
                width: wsSetup.colW
                height: condCol.implicitHeight + 42

                Column {
                    id: condCol
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                    spacing: 0

                    // Condenser Type
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Condenser Type"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["total","partial"]
                            currentIndex: appState ? (appState.condenserType === "partial" ? 1 : 0) : 0
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.condenserType = model[index] }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Condenser Spec
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Spec Type"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["reflux","duty","temperature"]
                            currentIndex: {
                                if (!appState) return 0
                                var s = (appState.condenserSpec || "").toLowerCase()
                                if (s === "refluxratio" || s === "reflux") return 0
                                if (s === "duty") return 1
                                if (s === "temperature") return 2
                                return 0
                            }
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.condenserSpec = model[index] }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Reflux Ratio
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Reflux Ratio"; color:textMuted; font.pixelSize:fsLabel }
                        TextField {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.refluxRatio) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.refluxRatio = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Fixed Duty Qc
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Fixed Duty"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "kW"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? String(Math.round(appState.qcKW)) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.qcKW = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // T Setpoint condenser
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"T Setpoint"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.topTsetK) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.topTsetK = Number(text) }
                        }
                    }

                }
            }

            // Reboiler
            CardFrame {
                id: rebCard
                title: "Reboiler"
                x: wsSetup.colW + 12
                y: condCard.y + condCard.height + 10
                width: wsSetup.colW
                height: rebCol.implicitHeight + 42

                Column {
                    id: rebCol
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                    spacing: 0

                    // Reboiler Type
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Reboiler Type"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["partial","total"]
                            currentIndex: appState ? (appState.reboilerType === "total" ? 1 : 0) : 0
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.reboilerType = model[index] }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Reboiler Spec
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Spec Type"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["boilup","duty","temperature"]
                            currentIndex: {
                                if (!appState) return 0
                                var s = (appState.reboilerSpec || "").toLowerCase()
                                if (s === "boilup" || s === "boilupratio") return 0
                                if (s === "duty") return 1
                                if (s === "temperature") return 2
                                return 0
                            }
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.reboilerSpec = model[index] }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Boilup Ratio
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Boilup Ratio"; color:textMuted; font.pixelSize:fsLabel }
                        TextField {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.boilupRatio) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.boilupRatio = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Fixed Duty Qr
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Fixed Duty"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "kW"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? String(Math.round(appState.qrKW)) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.qrKW = Number(text) }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // T Setpoint reboiler
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"T Setpoint"; color:textMuted; font.pixelSize:fsLabel }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K"
                            color: textMuted
                            font.pixelSize: fsSmall
                        }
                        TextField {
                            anchors { right:parent.right; rightMargin:wsSetup.unitW; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            text: appState ? fmt3(appState.bottomTsetK) : ""
                            font.pixelSize:fsValue; color:valueBlue; horizontalAlignment:Text.AlignRight
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            onEditingFinished: { if (appState) appState.bottomTsetK = Number(text) }
                        }
                    }

                }
            }

            // Thermodynamics
            CardFrame {
                id: thermoCard
                title: "Thermodynamics"
                x: wsSetup.colW + 12
                y: rebCard.y + rebCard.height + 10
                width: wsSetup.colW
                height: thermoCol.implicitHeight + 42

                Column {
                    id: thermoCol
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                    spacing: 0

                    // EOS Mode
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"EOS Mode"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["Auto","Manual"]
                            currentIndex: appState ? (appState.eosMode === "manual" ? 1 : 0) : 0
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:valueBlue; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.eosMode = (index === 1 ? "manual" : "auto") }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    // Manual EOS
                    Item { width:parent.width; height:wsSetup.rowH
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Manual EOS"; color:textMuted; font.pixelSize:fsLabel }
                        ComboBox {
                            anchors { right:parent.right; rightMargin:8; verticalCenter:parent.verticalCenter }
                            width:wsSetup.inputW
                            implicitHeight: wsSetup.rowH
                            model: ["PR","PRSV","SRK"]
                            currentIndex: {
                                if (!appState) return 1
                                var m = ["PR","PRSV","SRK"].indexOf(appState.eosManual)
                                return m >= 0 ? m : 1
                            }
                            enabled: appState ? appState.eosMode === "manual" : false
                            font.pixelSize:fsValue
                            background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                            contentItem: Text { leftPadding:6; text:parent.displayText; color:parent.enabled ? valueBlue : textMuted; font.pixelSize:fsValue; verticalAlignment:Text.AlignVCenter }
                            onActivated: { if (appState) appState.eosManual = model[index] }
                        }
                    }
                }
            }

        } // wsSetup

        // ── Draws/Solver sub-tab ──────────────────────────────────────
        // Left:  Draw Specifications (full height)
        // Right: Solve / Status  +  Material Balance
        Item {
            id: wsDrawsSolver
            visible: root.worksheetSubTab === "Draws/Solver"
            anchors { left:parent.left; right:parent.right; top:wsSubTabs.bottom; topMargin:10; bottom:parent.bottom }

            property real drawColW:  (width - 12) * 2 / 3
            property real solveColW: (width - 12) * 1 / 3

            // ── LEFT COLUMN (2/3): Draw Specs full height ──

            // Draw Specifications – full height, 2/3 width
            CardFrame {
                id: drawCard
                title: "Draw Specifications"
                x: 0; y: 0
                width: wsDrawsSolver.drawColW
                height: wsDrawsSolver.height

                // ── helpers ──────────────────────────────────
                function feedKgph() {
                    return (appState && appState.feedStream) ? Number(appState.feedStream.flowRateKgph) : 0
                }
                function totalTargetPct() {
                    if (!appState || !appState.drawSpecs) return 0
                    var tot = 0
                    var specs = appState.drawSpecs
                    for (var i = 0; i < specs.length; i++) {
                        var s = specs[i]
                        var v = Number(s.value)
                        if (s.basis === "feedPct" && isFinite(v)) tot += v
                    }
                    return tot
                }
                function commitSpecs(newSpecs) {
                    if (appState) appState.drawSpecs = newSpecs
                }

                // ── column headers ────────────────────────────
                Item {
                    id: drawHdr
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                    height: 26
                    Row {
                        anchors { left:parent.left; right:parent.right; leftMargin:10; rightMargin:8 }
                        height: parent.height; spacing: 4
                        Text { width:parent.width - 300; text:"Name";  font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height }
                        Text { width:60;  text:"Tray";  font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height; horizontalAlignment:Text.AlignHCenter }
                        Text { width:52; text:"Phase"; font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height; horizontalAlignment:Text.AlignHCenter }
                        Text { width:78; text:"Basis"; font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height; horizontalAlignment:Text.AlignHCenter }
                        Text { width:68; text:"Value"; font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height; horizontalAlignment:Text.AlignRight }
                        Text { width:26;   text:"";      font.bold:true; font.pixelSize:fsSmall; color:textDark; verticalAlignment:Text.AlignVCenter; height:parent.height }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // ── scrollable editable rows ──────────────────
                ScrollView {
                    id: drawScrollView
                    anchors { left:parent.left; right:parent.right; top:drawHdr.bottom; bottom:drawFooter.top }
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    Column {
                        width: drawScrollView.width
                        spacing: 0

                        Repeater {
                            id: drawRepeater
                            model: appState ? appState.drawSpecs : []

                            delegate: Item {
                                width: drawScrollView.width
                                height: 26
                                property var spec: modelData
                                property int rowIdx: index

                                Row {
                                    anchors { left:parent.left; right:parent.right; leftMargin:10; rightMargin:8 }
                                    height: parent.height; spacing: 4

                                    // Name – fills all remaining width
                                    TextField {
                                        width: parent.width - 300; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: spec.name || ""
                                        font.pixelSize: fsSmall; color: valueBlue
                                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                                        onEditingFinished: {
                                            var s = appState.drawSpecs; var copy = []
                                            for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                            copy[rowIdx].name = text; drawCard.commitSpecs(copy)
                                        }
                                    }

                                    // Tray
                                    SpinBox {
                                        width: 60; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        from: 2; to: appState ? Math.max(2, appState.trays - 1) : 30
                                        value: spec.tray || 1
                                        font.pixelSize: fsSmall
                                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                                        onValueModified: {
                                            var s = appState.drawSpecs; var copy = []
                                            for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                            copy[rowIdx].tray = value; drawCard.commitSpecs(copy)
                                        }
                                    }

                                    // Phase
                                    ComboBox {
                                        width: 52; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        model: ["L","V"]
                                        currentIndex: (spec.phase === "V") ? 1 : 0
                                        font.pixelSize: fsSmall; implicitHeight: 26
                                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                                        contentItem: Text { leftPadding:4; text:parent.displayText; color:valueBlue; font.pixelSize:fsSmall; verticalAlignment:Text.AlignVCenter }
                                        onActivated: {
                                            var s = appState.drawSpecs; var copy = []
                                            for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                            copy[rowIdx].phase = model[index]; drawCard.commitSpecs(copy)
                                        }
                                    }

                                    // Basis
                                    ComboBox {
                                        width: 78; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        model: ["feedPct","kg/h"]
                                        currentIndex: (spec.basis === "kg/h") ? 1 : 0
                                        font.pixelSize: fsSmall; implicitHeight: 26
                                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                                        contentItem: Text { leftPadding:4; text:parent.displayText; color:valueBlue; font.pixelSize:fsSmall; verticalAlignment:Text.AlignVCenter }
                                        onActivated: {
                                            var s = appState.drawSpecs; var copy = []
                                            for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                            copy[rowIdx].basis = model[index]; drawCard.commitSpecs(copy)
                                        }
                                    }

                                    // Value
                                    TextField {
                                        width: 68; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: spec.value !== undefined ? fmt2(Number(spec.value)) : "0.00"
                                        font.pixelSize: fsSmall; color: valueBlue; horizontalAlignment: Text.AlignRight
                                        background: Rectangle { radius:3; color:wsSetup.inputBg; border.color:gridLine; border.width:1 }
                                        onEditingFinished: {
                                            var s = appState.drawSpecs; var copy = []
                                            for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                            copy[rowIdx].value = Number(text); drawCard.commitSpecs(copy)
                                        }
                                    }

                                    // Delete ×
                                    Rectangle {
                                        width: 26; height: parent.height - 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "transparent"
                                        Text { anchors.centerIn:parent; text:"×"; font.pixelSize:12; color:errorRed; font.bold:true }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var s = appState.drawSpecs; var copy = []
                                                for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                                copy.splice(rowIdx, 1); drawCard.commitSpecs(copy)
                                            }
                                        }
                                    }
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                        }
                    }
                }

                // ── footer ────────────────────────────────────
                Item {
                    id: drawFooter
                    anchors { left:parent.left; right:parent.right; bottom:parent.bottom }
                    height: 36
                    HDivider { anchors.top:parent.top; width:parent.width }
                    Row {
                        anchors { left:parent.left; right:parent.right; leftMargin:10; rightMargin:10; verticalCenter:parent.verticalCenter }
                        spacing: 8

                        Rectangle {
                            width: 80; height: 24; radius: 5
                            color: tabActiveBg; border.color: outerBorder; border.width: 1
                            Text { anchors.centerIn:parent; text:"+ Add Draw"; color:white; font.pixelSize:fsSmall; font.bold:true }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (!appState) return
                                    var s = appState.drawSpecs; var copy = []
                                    for (var k=0;k<s.length;k++) copy.push(Object.assign({},s[k]))
                                    copy.push({ name:"New Draw", tray: appState.feedTray || 16, basis:"feedPct", phase:"L", value:0 })
                                    drawCard.commitSpecs(copy)
                                }
                            }
                        }

                        Rectangle {
                            width: 52; height: 24; radius: 5
                            color: buttonBg; border.color: gridLine; border.width: 1
                            Text { anchors.centerIn:parent; text:"Reset"; color:textDark; font.pixelSize:fsSmall }
                            MouseArea { anchors.fill:parent; onClicked: { if (appState) appState.resetDrawSpecsToDefaults() } }
                        }

                        Item { width: 1; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var tot = drawCard.totalTargetPct()
                                var kgph = tot * drawCard.feedKgph() / 100.0
                                return "Total: " + tot.toFixed(1) + "%  (" + Math.round(kgph) + " kg/h)"
                            }
                            font.pixelSize: fsSmall; color: textMuted
                        }
                    }
                }
            }


            // ── RIGHT COLUMN: Solve / Status (full height) ────

            CardFrame {
                id: solveCard
                title: "Solve / Status"
                x: wsDrawsSolver.drawColW + 12; y: 0
                width: wsDrawsSolver.solveColW; height: wsDrawsSolver.height

                Row {
                    x:12; y:40; spacing:8
                    Rectangle {
                        width:130; height:28; radius:6
                        color: appState && !appState.solving ? "#2e76db" : "#9ba8bf"
                        border.color:outerBorder; border.width:1
                        Text { anchors.centerIn:parent; text:"Solve Column"; color:white; font.pixelSize:fsLabel; font.bold:true }
                        MouseArea { anchors.fill:parent; onClicked: { if (appState && !appState.solving) appState.solve() } }
                    }
                    Rectangle {
                        width:120; height:28; radius:6
                        color:buttonBg; border.color:gridLine; border.width:1
                        Text { anchors.centerIn:parent; text:"Clear / Reset"; color:textDark; font.pixelSize:fsLabel }
                        MouseArea { anchors.fill:parent; onClicked: { if (appState) appState.reset() } }
                    }
                }

                Column {
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:86 }
                    spacing:0

                    Item {
                        width:parent.width; height:26
                        Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:"Solve Status"; color:textMuted; font.pixelSize:fsLabel }
                        Text { anchors { right:parent.right; rightMargin:10; verticalCenter:parent.verticalCenter }
                               text:solveStatus(); color:solveStatusColor(); font.pixelSize:fsValue; font.bold:true }
                    }
                    HDivider { width:parent.width }

                    Repeater {
                        model: [
                            { label:"Elapsed Time",    value: appState ? fmtMs(appState.solveElapsedMs) : "—" },
                            { label:"Condenser Qc",    value: appState ? (String(Math.round(appState.qcCalcKW)) + " kW") : "—" },
                            { label:"Reboiler Qr",     value: appState ? (String(Math.round(appState.qrCalcKW)) + " kW") : "—" },
                            { label:"Reflux Fraction", value: appState ? (fmt3(appState.refluxFraction * 100) + "%") : "—" },
                            { label:"Boilup Fraction", value: appState ? (fmt3(appState.boilupFraction * 100) + "%") : "—" },
                            { label:"T Overhead",      value: appState ? (fmt3(appState.tColdK) + " K") : "—" },
                            { label:"T Bottoms",       value: appState ? (fmt3(appState.tHotK)  + " K") : "—" }
                        ]
                        delegate: Column {
                            width:parent.width
                            Item {
                                width:parent.width; height:26
                                Text { x:10; anchors.verticalCenter:parent.verticalCenter; text:modelData.label; color:textMuted; font.pixelSize:fsLabel }
                                Text { anchors { right:parent.right; rightMargin:10; verticalCenter:parent.verticalCenter }
                                       text:modelData.value; color:valueBlue; font.pixelSize:fsValue }
                            }
                            HDivider { width:parent.width; visible: index < 6 }
                        }
                    }
                }
            }
        } // wsDrawsSolver
    } // worksheetTab

    // ==========================================================
    //  PERFORMANCE TAB
    // ==========================================================
    Item {
        id: performanceTab
        visible: root.activeTab === "Performance"
        anchors { fill: workspaceFrame; margins: 10 }
        property real colW: (width - 12) / 2

        // Solve summary
        CardFrame {
            id: perfSolveCard
            title: "Solve Summary"
            x:0; y:0; width:performanceTab.colW; height:170

            Column {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38; margins:0 }
                spacing:0
                Repeater {
                    model: [
                        { label:"Solve Status",   value: solveStatus() },
                        { label:"Elapsed Time",   value: appState ? fmtMs(appState.solveElapsedMs) : "—" },
                        { label:"Specs Dirty",    value: appState ? (appState.specsDirty ? "Yes" : "No") : "—" }
                    ]
                    delegate: Column {
                        width: parent.width
                        FieldRow { width:parent.width; height:26; label:modelData.label; value:modelData.value }
                        HDivider { width:parent.width; visible: index < 2 }
                    }
                }
            }
        }

        // Energy summary
        CardFrame {
            title: "Energy Summary"
            x:0; y:perfSolveCard.height + 10; width:performanceTab.colW; height:170

            Column {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38; margins:0 }
                spacing:0
                Repeater {
                    model: [
                        { label:"Condenser Duty", value: appState ? (Math.round(appState.qcCalcKW)+" kW") : "—" },
                        { label:"Reboiler Duty",  value: appState ? (Math.round(appState.qrCalcKW)+" kW") : "—" },
                        { label:"Net Duty",       value: appState ? (Math.round(appState.qrCalcKW - Math.abs(appState.qcCalcKW))+" kW") : "—" }
                    ]
                    delegate: Column {
                        width: parent.width
                        FieldRow { width:parent.width; height:26; label:modelData.label; value:modelData.value }
                        HDivider { width:parent.width; visible: index < 2 }
                    }
                }
            }
        }

        // Top / Bottom conditions
        CardFrame {
            title: "Top / Bottom Conditions"
            x: performanceTab.colW + 12; y:0; width: performanceTab.colW; height:170

            Column {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38; margins:0 }
                spacing:0
                Repeater {
                    model: [
                        { label:"Overhead Temperature", value: appState ? (fmt3(appState.tColdK)+" K") : "—" },
                        { label:"Bottoms Temperature",  value: appState ? (fmt3(appState.tHotK) +" K") : "—" },
                        { label:"Reflux Fraction",      value: appState ? (fmt3(appState.refluxFraction*100)+"%") : "—" },
                        { label:"Boilup Fraction",      value: appState ? (fmt3(appState.boilupFraction*100)+"%") : "—" }
                    ]
                    delegate: Column {
                        width: parent.width
                        FieldRow { width:parent.width; height:26; label:modelData.label; value:modelData.value }
                        HDivider { width:parent.width; visible: index < 3 }
                    }
                }
            }
        }

        // Diagnostics warnings panel
        CardFrame {
            title: "Solver Warnings"
            x: performanceTab.colW + 12
            y: 180
            width: performanceTab.colW
            height: performanceTab.height - 180

            ListView {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38; bottom:parent.bottom; margins:0; leftMargin:10; rightMargin:10 }
                clip:true
                model: appState ? appState.diagnosticsModel : null
                delegate: Item {
                    width: parent ? parent.width : 0; height: 32
                    Row {
                        anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter }
                        spacing: 8
                        Rectangle { width:10; height:10; radius:2; color:warnAmber; anchors.verticalCenter:parent.verticalCenter }
                        Text { text: model.message || ""; color: textDark; font.pixelSize:fsLabel; wrapMode:Text.Wrap; width:parent.width-30 }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }
                Text {
                    anchors.centerIn:parent
                    visible: !appState || !appState.diagnosticsModel || appState.diagnosticsModel.rowCount() === 0
                    text:"No warnings"; color:textMuted; font.pixelSize:fsLabel; font.italic:true
                }
            }
        }
    }

    // ==========================================================
    //  PROFILES TAB  (tray table + simple visual)
    // ==========================================================
    Item {
        id: profilesTab
        visible: root.activeTab === "Profiles"
        anchors { fill: workspaceFrame; margins: 10 }

        Row {
            id: profilesSubTabs; spacing:8
            SubTabBtn { label:"Tray Table";     isActive: root.profilesSubTab==="Tray Table";     onClicked: root.profilesSubTab="Tray Table" }
            SubTabBtn { label:"Visual Profiles"; isActive: root.profilesSubTab==="Visual Profiles"; onClicked: root.profilesSubTab="Visual Profiles" }
        }

        // ── Tray Table ──────────────────────────────────────
        Item {
            visible: root.profilesSubTab === "Tray Table"
            anchors { left:parent.left; right:parent.right; top:profilesSubTabs.bottom; topMargin:10; bottom:parent.bottom }

            CardFrame {
                anchors.fill: parent
                title: "Tray Profiles"

                // ── Legend ───────────────────────────────────────────────
                Row {
                    anchors { right:parent.right; rightMargin:12; top:parent.top; topMargin:8 }
                    spacing: 10

                    Rectangle { width:18; height:10; radius:3; color:"#67b0ff"; anchors.verticalCenter:parent.verticalCenter }
                    Text { text:"Vapor (V*)"; font.pixelSize:fsSmall; color:textMuted; anchors.verticalCenter:parent.verticalCenter }
                    Rectangle { width:18; height:10; radius:3; color:"#294f8f"; anchors.verticalCenter:parent.verticalCenter }
                    Text { text:"Liquid (1−V*)"; font.pixelSize:fsSmall; color:textMuted; anchors.verticalCenter:parent.verticalCenter }
                }

                // ── Header row ────────────────────────────────────────────
                Item {
                    id: trayHdr
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38 }
                    height: 28
                    // colWs: Tray, Temp, Pressure, VapFrac, LiqFlow, VapFlow, Draw (no bar col – bar is right-anchored outside Row)
                    property var hdrs:  ["Tray","Temp (K)","Pressure (Pa)","Vap.Frac","Liq. Flow","Vap. Flow","Draw","V* / L*"]
                    property var colWs: [50,    100,       110,            80,        100,        100,        120,   150]
                    Row {
                        anchors { left:parent.left; right:parent.right; leftMargin:10 }
                        Repeater {
                            model: trayHdr.hdrs.length
                            delegate: Text {
                                width: trayHdr.colWs[index]
                                text: trayHdr.hdrs[index]
                                font.pixelSize:fsLabel; font.bold:true; color:textDark
                                horizontalAlignment: index > 0 ? Text.AlignRight : Text.AlignLeft
                                height:28; verticalAlignment:Text.AlignVCenter
                            }
                        }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }

                // ── Tray rows ─────────────────────────────────────────────
                ListView {
                    anchors { left:parent.left; right:parent.right; top:trayHdr.bottom; bottom:parent.bottom }
                    clip: true
                    verticalLayoutDirection: ListView.BottomToTop
                    model: appState ? appState.trayModel : null

                    delegate: Item {
                        width: parent ? parent.width : 0
                        height: 28
                        property var colWs: [50,100,110,80,100,100,120]
                        property real vf: Math.max(0, Math.min(1, model.vaporFrac || 0))

                        // Text columns in a Row; bar is separately right-anchored
                        Row {
                            id: trayRowContent
                            anchors { left:parent.left; right:trayBar.left; rightMargin:8; leftMargin:10 }
                            height: parent.height

                            // Tray number
                            Text { width:colWs[0]; text:model.trayNumber||"—"; font.pixelSize:fsValue; color:textDark; height:parent.height; verticalAlignment:Text.AlignVCenter }

                            // Temperature
                            Text { width:colWs[1]; text:fmt3(model.tempK); font.pixelSize:fsValue; color:valueBlue; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }

                            // Pressure (computed)
                            Text {
                                width: colWs[2]
                                text: {
                                    if (!appState) return "—"
                                    var tN = model.trayNumber
                                    var p0 = appState.topPressurePa
                                    var dp = appState.dpPerTrayPa
                                    var nT = appState.trays
                                    return String(Math.round(p0 + dp*(nT - tN)))
                                }
                                font.pixelSize:fsValue; color:valueBlue; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                            }

                            // Vapour fraction
                            Text { width:colWs[3]; text:fmt3(model.vaporFrac); font.pixelSize:fsValue; color:valueBlue; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }

                            // Liquid flow
                            Text { width:colWs[4]; text:Math.round(model.liquidFlow)+""; font.pixelSize:fsValue; color:valueBlue; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }

                            // Vapour flow
                            Text { width:colWs[5]; text:Math.round(model.vaporFlow)+""; font.pixelSize:fsValue; color:valueBlue; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }

                            // Draw label – elide if too long
                            Text { width:colWs[6]; text:model.drawLabel||""; font.pixelSize:fsSmall; color:warnAmber; height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight; elide:Text.ElideRight }
                        }

                        // V*/L* bar – right-anchored, always 140px, separated from text columns
                        Item {
                            id: trayBar
                            anchors { right:parent.right; rightMargin:10; verticalCenter:parent.verticalCenter }
                            width: 140
                            height: parent.height

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 10
                                radius: 5
                                color: "#294f8f"

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * vf
                                    radius: 5
                                    color: "#67b0ff"
                                }
                            }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !appState || !appState.trayModel || appState.trayModel.rowCount() === 0
                        text: "Run solver to populate tray table"
                        color: textMuted; font.pixelSize: fsLabel; font.italic: true
                    }
                }
            }
        }

        // ── Visual Profiles ──────────────────────────────────
        Item {
            id: visualProfilesPanel
            visible: root.profilesSubTab === "Visual Profiles"
            anchors { left:parent.left; right:parent.right; top:profilesSubTabs.bottom; topMargin:10; bottom:parent.bottom }

            // Profile selector definitions: key into TrayModel.get(), label, unit, colour
            // Profile definitions.
            // key: TrayModel role name (tempK, vaporFrac, vaporFlow, liquidFlow)
            //      OR "pressure" (computed from appState.topPressurePa + dpPerTrayPa * (N-tray))
            //         "hasDraw"  (0/1 flag per tray – shows draw trays)
            property var profileDefs: [
                { key:"tempK",      label:"Temperature",     unit:"K",    color:"#2e76db" },
                { key:"pressure",   label:"Pressure",        unit:"Pa",   color:"#7c3aed" },
                { key:"vaporFrac",  label:"Vapour Fraction", unit:"—",    color:"#0891b2" },
                { key:"liquidFlow", label:"Liquid Flow",     unit:"kg/h", color:"#059669" },
                { key:"vaporFlow",  label:"Vapour Flow",     unit:"kg/h", color:"#d97706" }
            ]
            property int profileIndex: 0
            property var activeDef: profileDefs[profileIndex]

            // Profile selector row
            Row {
                id: profileSelRow
                x: 0; y: 0; spacing: 6
                Repeater {
                    model: visualProfilesPanel.profileDefs.length
                    delegate: Rectangle {
                        width: 110; height: 26; radius: 8
                        color: visualProfilesPanel.profileIndex === index ? tabActiveBg : tabIdleBg
                        border.color: outerBorder; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: visualProfilesPanel.profileDefs[index].label
                            font.pixelSize: 10; font.bold: visualProfilesPanel.profileIndex === index
                            color: visualProfilesPanel.profileIndex === index ? white : textDark
                            elide: Text.ElideRight
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea { anchors.fill: parent; onClicked: {
                            visualProfilesPanel.profileIndex = index
                            profileCanvas.requestPaint()
                        }}
                    }
                }
            }

            // Chart area
            Rectangle {
                id: chartOuter
                anchors { left:parent.left; right:parent.right; top:profileSelRow.bottom; topMargin:8; bottom:parent.bottom }
                radius: 8; color: white; border.color: gridLine; border.width: 1

                // Fixed margins for axes
                // Y = tray number, X = profile value
                readonly property int leftMargin:   46   // Y-axis: tray numbers (small integers)
                readonly property int rightMargin:  16
                readonly property int topMargin:    14
                readonly property int bottomMargin: 56   // X-axis: profile value labels + title

                Canvas {
                    id: profileCanvas
                    anchors.fill: parent
                    property var trayModel: appState ? appState.trayModel : null
                    property var def: visualProfilesPanel.activeDef

                    Connections {
                        target: profileCanvas.trayModel
                        function onDataChanged() { profileCanvas.requestPaint() }
                        ignoreUnknownSignals: true
                    }
                    onDefChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()

                        var lm = chartOuter.leftMargin
                        var rm = chartOuter.rightMargin
                        var tm = chartOuter.topMargin
                        var bm = chartOuter.bottomMargin
                        var cw = width - lm - rm   // chart width
                        var ch = height - tm - bm  // chart height

                        // ── Background ───────────────────────────────────
                        ctx.fillStyle = "#ffffff"
                        ctx.fillRect(lm, tm, cw, ch)
                        ctx.strokeStyle = "#2a2a2a"; ctx.lineWidth = 1
                        ctx.strokeRect(lm, tm, cw, ch)

                        // ── Collect data points ───────────────────────────
                        var model = profileCanvas.trayModel
                        var pdef = profileCanvas.def

                        if (!model || model.rowCount() === 0 || !pdef) {
                            ctx.fillStyle = "#9ba8bf"
                            ctx.font = "13px sans-serif"
                            ctx.textAlign = "center"
                            ctx.fillText("No data – run solver", lm + cw/2, tm + ch/2)
                            return
                        }

                        // ── Collect points: Y = tray, X = profile value ──
                        var pts = []
                        var nTrays = appState ? appState.trays : 0
                        var p0 = appState ? appState.topPressurePa : 0
                        var dp = appState ? appState.dpPerTrayPa : 0
                        for (var r = 0; r < model.rowCount(); r++) {
                            var row = model.get(r)
                            var xVal
                            if (pdef.key === "pressure") {
                                xVal = p0 + dp * (nTrays - row.trayNumber)
                            } else {
                                xVal = row[pdef.key]
                                if (xVal === undefined || xVal === null) xVal = 0
                            }
                            pts.push({ tray: row.trayNumber, x: Number(xVal) })
                        }
                        pts.sort(function(a,b){ return a.tray - b.tray })

                        if (pts.length === 0) return

                        var minTray = pts[0].tray, maxTray = pts[pts.length-1].tray
                        var minX = pts[0].x, maxX = pts[0].x
                        for (var k = 1; k < pts.length; k++) {
                            if (pts[k].x < minX) minX = pts[k].x
                            if (pts[k].x > maxX) maxX = pts[k].x
                        }
                        // Nice X (value) range with padding
                        var xPad = (maxX - minX) * 0.06 || Math.abs(maxX) * 0.05 || 1
                        var xLo = minX - xPad
                        var xHi = maxX + xPad
                        var rngX = xHi - xLo || 1
                        var rngTray = (maxTray - minTray) || 1

                        // ── Grid lines ────────────────────────────────────
                        var nGridX = 6                        // value (horizontal) grid lines
                        var nGridY = Math.min(pts.length, 10) // tray (vertical) grid lines
                        ctx.strokeStyle = "#dde4f0"; ctx.lineWidth = 1
                        ctx.setLineDash([3,3])
                        // Horizontal lines (constant value)
                        for (var gi = 0; gi <= nGridX; gi++) {
                            var gx = lm + gi * (cw / nGridX)
                            ctx.beginPath(); ctx.moveTo(gx, tm); ctx.lineTo(gx, tm+ch); ctx.stroke()
                        }
                        // Vertical lines (constant tray)
                        for (var gj = 0; gj <= nGridY; gj++) {
                            var gy = tm + ch - gj * (ch / nGridY)
                            ctx.beginPath(); ctx.moveTo(lm, gy); ctx.lineTo(lm+cw, gy); ctx.stroke()
                        }
                        ctx.setLineDash([])

                        // ── Y-axis labels (tray numbers) ──────────────────
                        ctx.fillStyle = "#5a6472"
                        ctx.font = "10px sans-serif"
                        ctx.textAlign = "right"
                        var step = Math.max(1, Math.round(pts.length / nGridY))
                        for (var yi = 0; yi < pts.length; yi += step) {
                            var yp = tm + ch - (pts[yi].tray - minTray) / rngTray * ch
                            ctx.fillText(pts[yi].tray, lm - 4, yp + 4)
                        }
                        // Always label top tray
                        var topPt = pts[pts.length-1]
                        ctx.fillText(topPt.tray, lm - 4, tm + ch - (topPt.tray - minTray)/rngTray*ch + 4)

                        // ── Y-axis title (rotated): "Tray Number" ─────────
                        ctx.save()
                        ctx.fillStyle = "#1f2430"
                        ctx.font = "bold 11px sans-serif"
                        ctx.textAlign = "center"
                        ctx.translate(13, tm + ch/2)
                        ctx.rotate(-Math.PI/2)
                        ctx.fillText("Tray Number (1 = Bottoms)", 0, 0)
                        ctx.restore()

                        // ── X-axis labels (profile values) ────────────────
                        ctx.fillStyle = "#5a6472"
                        ctx.font = "10px sans-serif"
                        ctx.textAlign = "center"
                        for (var xi = 0; xi <= nGridX; xi++) {
                            var xv = xLo + xi * rngX / nGridX
                            var xp = lm + xi * (cw / nGridX)
                            var xStr = Math.abs(xv) >= 10000 ? xv.toExponential(2)
                                     : Math.abs(xv) >= 100   ? xv.toFixed(0)
                                     : Math.abs(xv) >= 1     ? xv.toFixed(2)
                                     : xv.toFixed(4)
                            ctx.fillText(xStr, xp, tm + ch + 14)
                        }

                        // ── X-axis title (profile label + unit) ───────────
                        ctx.fillStyle = "#1f2430"
                        ctx.font = "bold 11px sans-serif"
                        ctx.textAlign = "center"
                        ctx.fillText(pdef.label + " (" + pdef.unit + ")", lm + cw/2, tm + ch + 44)

                        // ── Data line ─────────────────────────────────────
                        ctx.strokeStyle = pdef.color; ctx.lineWidth = 2
                        ctx.beginPath()
                        for (var p = 0; p < pts.length; p++) {
                            var px = lm + (pts[p].x - xLo) / rngX * cw
                            var py = tm + ch - (pts[p].tray - minTray) / rngTray * ch
                            if (p === 0) ctx.moveTo(px, py)
                            else ctx.lineTo(px, py)
                        }
                        ctx.stroke()

                        // ── Data dots ─────────────────────────────────────
                        ctx.fillStyle = pdef.color
                        for (var d = 0; d < pts.length; d++) {
                            var dpx = lm + (pts[d].x - xLo) / rngX * cw
                            var dpy = tm + ch - (pts[d].tray - minTray) / rngTray * ch
                            ctx.beginPath(); ctx.arc(dpx, dpy, 3.5, 0, 2*Math.PI); ctx.fill()
                        }
                    }
                }
            }
        }
    }

    // ==========================================================
    //  PRODUCTS TAB  – Material Balance (sorted, with totals)
    // ==========================================================
    Item {
        id: productsTab
        visible: root.activeTab === "Products"
        anchors { fill: workspaceFrame; margins: 10 }

        CardFrame {
            id: prodMbCard
            anchors.fill: parent
            title: "Material Balance"

            // ── Column headers ────────────────────────────────
            Item {
                id: prodMbHdr
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:36 }
                height: 28
                Row {
                    anchors { left:parent.left; right:parent.right; leftMargin:10 }
                    Text { width:parent.width*0.55; text:"Product";     font.bold:true; font.pixelSize:fsLabel; color:textDark; height:28; verticalAlignment:Text.AlignVCenter }
                    Text { width:parent.width*0.25; text:"Flow (kg/h)"; font.bold:true; font.pixelSize:fsLabel; color:textDark; height:28; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                    Text { width:parent.width*0.16; text:"Feed %";      font.bold:true; font.pixelSize:fsLabel; color:textDark; height:28; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                }
                HDivider { anchors.bottom:parent.bottom; width:parent.width }
            }

            // ── Sorted rows ───────────────────────────────────
            property var prodMbSorted: []

            function rebuildProdMbSorted() {
                var mbm = appState ? appState.materialBalanceModel : null
                if (!mbm || !appState || !appState.solved) { prodMbSorted = []; return }
                var n = mbm.rowCount()
                var rows = []
                for (var i = 0; i < n; i++) {
                    var idx = mbm.index(i, 0)
                    var nm  = mbm.data(idx, 257) || ""
                    var kg  = mbm.data(idx, 258) || 0
                    var fr  = mbm.data(idx, 259) || 0
                    var nmL = nm.toLowerCase()
                    var sortKey = 0
                    if (nmL.indexOf("distillate") >= 0 || nmL.indexOf("overhead") >= 0)
                        sortKey = 99999
                    else if (nmL.indexOf("bottoms") >= 0 || nmL.indexOf("residue") >= 0)
                        sortKey = -1
                    else {
                        var parts = nm.match(/Tray\s*(\d+)/i)
                        sortKey = parts ? parseInt(parts[1]) : 0
                    }
                    rows.push({ name: nm, kgph: kg, frac: fr, sortKey: sortKey })
                }
                rows.sort(function(a,b){ return b.sortKey - a.sortKey })
                prodMbSorted = rows
            }

            Connections {
                target: appState ? appState.materialBalanceModel : null
                function onTotalsChanged() { prodMbCard.rebuildProdMbSorted() }
                ignoreUnknownSignals: true
            }
            Connections {
                target: appState
                function onSolvedChanged() { prodMbCard.rebuildProdMbSorted() }
                ignoreUnknownSignals: true
            }

            ListView {
                id: prodMbList
                anchors { left:parent.left; right:parent.right; top:prodMbHdr.bottom; bottom:prodMbTotals.top }
                clip: true
                model: prodMbCard.prodMbSorted
                delegate: Item {
                    width: parent ? parent.width : 0; height: 28
                    Row {
                        anchors { left:parent.left; right:parent.right; leftMargin:10 }
                        Text { width:parent.width*0.55; text:modelData.name||"—";              font.pixelSize:fsValue; color:textDark;  height:28; verticalAlignment:Text.AlignVCenter; elide:Text.ElideRight }
                        Text { width:parent.width*0.25; text:Math.round(modelData.kgph||0)+""; font.pixelSize:fsValue; color:valueBlue; height:28; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                        Text { width:parent.width*0.16; text:fmt2((modelData.frac||0)*100)+"%";font.pixelSize:fsValue; color:valueBlue; height:28; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !appState || !appState.solved
                    text: "Run solver to see material balance"
                    color: textMuted; font.pixelSize: fsLabel; font.italic: true
                }
            }

            // ── Totals + balance error footer ─────────────────
            Item {
                id: prodMbTotals
                anchors { left:parent.left; right:parent.right; bottom:parent.bottom }
                height: 52
                visible: appState && appState.solved

                HDivider { anchors.top:parent.top; width:parent.width }

                Column {
                    anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:1 }
                    spacing: 0

                    Item {
                        width: parent.width; height: 25
                        Row {
                            anchors { left:parent.left; right:parent.right; leftMargin:10 }
                            Text { width:parent.width*0.55; text:"Total Products"; font.bold:true; font.pixelSize:fsLabel; color:textDark; height:25; verticalAlignment:Text.AlignVCenter }
                            Text {
                                width:parent.width*0.25
                                text: appState && appState.materialBalanceModel ? Math.round(appState.materialBalanceModel.totalProductsKgph) + "" : "—"
                                font.bold:true; font.pixelSize:fsLabel; color:valueBlue; height:25; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                            }
                            Text {
                                width:parent.width*0.16
                                text: appState && appState.materialBalanceModel ? fmt2(appState.materialBalanceModel.totalFrac * 100) + "%" : "—"
                                font.bold:true; font.pixelSize:fsLabel; color:valueBlue; height:25; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                            }
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width }
                    }

                    Item {
                        width: parent.width; height: 25
                        Row {
                            anchors { left:parent.left; right:parent.right; leftMargin:10 }
                            Text { width:parent.width*0.55; text:"Balance Error"; font.pixelSize:fsLabel; color:textMuted; height:25; verticalAlignment:Text.AlignVCenter }
                            Text {
                                width:parent.width*0.25
                                property double errKgph: appState && appState.materialBalanceModel ? appState.materialBalanceModel.balanceErrKgph : 0
                                text: fmt2(Math.abs(errKgph)) + " kg/h"
                                font.pixelSize:fsLabel
                                color: Math.abs(errKgph) > 100 ? errorRed : (Math.abs(errKgph) > 10 ? warnAmber : "#1a7a3c")
                                height:25; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                            }
                            Text {
                                width:parent.width*0.16
                                property double feedK: appState && appState.materialBalanceModel ? appState.materialBalanceModel.feedKgph : 1
                                property double errK:  appState && appState.materialBalanceModel ? appState.materialBalanceModel.balanceErrKgph : 0
                                property double errPct: (feedK > 0) ? Math.abs(errK) / feedK * 100 : 0
                                text: fmt2(errPct) + "%"
                                font.pixelSize:fsLabel
                                color: errPct > 1.0 ? errorRed : (errPct > 0.1 ? warnAmber : "#1a7a3c")
                                height:25; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================================
    //  RUN LOG TAB
    // ==========================================================
    Item {
        id: runLogTab
        visible: root.activeTab === "Run Log"
        anchors { fill: workspaceFrame; margins: 10 }

        CardFrame {
            anchors.fill: parent
            title: "Run Log"

            ScrollView {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:38; bottom:parent.bottom; margins:0; leftMargin:10; rightMargin:10 }
                clip:true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ListView {
                    id: runLogList
                    model: appState ? appState.runLogModel : null
                    spacing: 0
                    delegate: Item {
                        width: runLogList.width; height:24
                        Text {
                            x:4; anchors.verticalCenter:parent.verticalCenter
                            text: model.text || ""
                            font.pixelSize: fsValue; color: textDark
                            font.family: "Monospace"
                        }
                        HDivider { anchors.bottom:parent.bottom; width:parent.width; color: "#d0d8e8" }
                    }
                    // Auto-scroll to bottom when new entries arrive
                    onCountChanged: Qt.callLater(function(){ runLogList.positionViewAtEnd() })

                    Text {
                        anchors.centerIn:parent
                        visible: !appState || !appState.runLogModel || appState.runLogModel.rowCount()===0
                        text:"No run log entries yet"; color:textMuted; font.pixelSize:fsLabel; font.italic:true
                    }
                }
            }
        }
    }

    // ==========================================================
    //  DIAGNOSTICS TAB
    // ==========================================================
    Item {
        id: diagnosticsTab
        visible: root.activeTab === "Diagnostics"
        anchors { fill: workspaceFrame; margins: 10 }

        CardFrame {
            anchors.fill: parent
            title: "Diagnostics"

            ListView {
                anchors { left:parent.left; right:parent.right; top:parent.top; topMargin:42; bottom:parent.bottom; margins:0; leftMargin:12; rightMargin:12 }
                clip:true
                model: appState ? appState.diagnosticsModel : null
                spacing: 6
                delegate: Item {
                    width: parent ? parent.width : 0; height:38
                    Row {
                        anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter }
                        spacing: 8
                        Rectangle {
                            width:14; height:14; radius:3
                            color: model.level === "error" ? errorRed : (model.level === "warn" ? warnAmber : softBlue)
                            anchors.verticalCenter:parent.verticalCenter
                        }
                        Text {
                            text: model.message || ""
                            font.pixelSize:fsLabel; color:textDark
                            wrapMode:Text.Wrap
                            width: parent.width - 30
                        }
                    }
                    HDivider { anchors.bottom:parent.bottom; width:parent.width }
                }
                Text {
                    anchors.centerIn:parent
                    visible: !appState || !appState.diagnosticsModel || appState.diagnosticsModel.rowCount()===0
                    text:"No diagnostics"; color:textMuted; font.pixelSize:fsLabel; font.italic:true
                }
            }
        }
    }
}
