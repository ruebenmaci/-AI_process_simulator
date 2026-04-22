import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  HeaterCoolerView — REFACTORED to the PPropertyView + PGroupBox + GridLayout
//  standard used by the Stream view panels.
//
//  Shared by "heater" and "cooler" (single HeaterCoolerUnitState class). The
//  accent colour, icon, and a couple of labels adapt to appState.type.
//
//  Layout:
//    ┌─ PPropertyView ────────────────────────────────────────────────────┐
//    │ [Design] [Results]                             Unit Set: [SI ▾]   │
//    │ ╔════════════════════════════════════════════════════════════════╗ │
//    │ ║  ( Design tab )                                                ║ │
//    │ ║    PGroupBox "Connections"                                     ║ │
//    │ ║    PGroupBox "Specifications"                                  ║ │
//    │ ║    PGroupBox "Conditions"                                      ║ │
//    │ ║  ( Results tab )                                               ║ │
//    │ ║    PGroupBox "Calculated Results"                              ║ │
//    │ ║    PGroupBox "Solver Status"                                   ║ │
//    │ ╚════════════════════════════════════════════════════════════════╝ │
//    └────────────────────────────────────────────────────────────────────┘
//    [▶ Solve]  [Reset]                                 Solved  ✓
//
//  Unit handling (same pattern as StreamConditionsPanel):
//    State stores mixed-scale values (K, kW, Pa). PGridValue/PGridUnit work
//    in true SI (K, W, Pa), so small helper functions convert on read/write.
//
//      duty:        kW ⇄ W   (siDutyW = dutyKW * 1000 ; kW = siW / 1000)
//      pressure:    already Pa, no conversion needed
//      temperature: already K,  no conversion needed
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  410
    implicitHeight: 420

    // ── Type-aware helpers ───────────────────────────────────────────────────
    readonly property bool  isCoolerType: !!appState && appState.type === "cooler"
    readonly property color accentColor:  isCoolerType ? "#1c6ea7" : "#a73c1c"
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath(isCoolerType ? "cooler" : "heater"))
                                    : ""
    readonly property string dutyLabelText: isCoolerType ? "Cooling duty" : "Heating duty"

    // Label column width matches StreamConditionsPanel for visual consistency.
    readonly property int labelColWidth: 180

    // ── Per-quantity unit overrides (same pattern as stream panels) ─────────
    property var unitOverrides: ({
        "Temperature":   "",
        "Pressure":      "",
        "Power":         "",
        "Dimensionless": ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // ── kW ⇄ W helpers ───────────────────────────────────────────────────────
    function _siPower(kW)   { return kW * 1000.0 }
    function _kWfromSI(siW) { return siW / 1000.0 }

    // ── Solve-status helpers ─────────────────────────────────────────────────
    function solveStatusText() {
        if (!appState)       return "\u2014"
        if (appState.solved) return "Solved  \u2713"
        if (appState.solveStatus && appState.solveStatus !== "") return appState.solveStatus
        return "Not solved"
    }
    function solveStatusColor() {
        if (!appState)       return "#526571"
        if (appState.solved) return "#1a7a3c"
        return "#b23b3b"
    }

    // ── Property view shell ──────────────────────────────────────────────────
    PPropertyView {
        id: pview
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top

        tabs: [ { text: "Design" }, { text: "Results" } ]
        currentIndex: root.currentTab
        onTabClicked: function(i) { root.currentTab = i }

        // Left accessory — the heater/cooler icon.
        leftAccessory: Image {
            width: 16; height: 16
            source: root.iconPath
            sourceSize.width: 32
            sourceSize.height: 32
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // Right accessory — Unit Set selector (matches StreamView).
        rightAccessory: Row {
            spacing: 4

            Text {
                text: "Unit Set:"
                font.pixelSize: 11
                color: "#526571"
                anchors.verticalCenter: parent.verticalCenter
            }

            PComboBox {
                id: unitSetCombo
                width: 100
                fontSize: 11
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                model: typeof gUnits !== "undefined" ? gUnits.availableUnitSets : ["SI", "Field", "British"]
                currentIndex: {
                    var s = (typeof gUnits !== "undefined") ? gUnits.activeUnitSet : "SI"
                    var idx = model.indexOf(s)
                    return idx >= 0 ? idx : 0
                }
                onActivated: function(index) {
                    if (typeof gUnits !== "undefined")
                        gUnits.activeUnitSet = model[index]
                }
                Connections {
                    target: typeof gUnits !== "undefined" ? gUnits : null
                    ignoreUnknownSignals: true
                    function onActiveUnitSetChanged() {
                        var i = unitSetCombo.model.indexOf(gUnits.activeUnitSet)
                        if (i >= 0 && unitSetCombo.currentIndex !== i)
                            unitSetCombo.currentIndex = i
                    }
                }
            }
        }

        // ── Design tab ─────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: root.currentTab === 0

            Rectangle {
                anchors.fill: parent
                color: "#e8ebef"

                Text {
                    anchors.centerIn: parent
                    visible: !root.appState
                    text: "No unit selected"
                    font.pixelSize: 11; color: "#526571"
                }

                ScrollView {
                    id: designScroll
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: !!root.appState
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: designScroll.availableWidth
                        spacing: 6

                        // ── Connections ────────────────────────────────────
                        PGroupBox {
                            id: connBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Connections"
                            contentPadding: 8

                            GridLayout {
                                id: connGrid
                                width: connBox.width - (connBox.contentPadding * 2) - 2
                                columns: 3; columnSpacing: 0; rowSpacing: 0

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed stream" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedFeedStreamUnitId !== "")
                                                ? root.appState.connectedFeedStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedFeedStreamUnitId !== "")
                                                ? "#1c4ea7" : "#d6b74a"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Product stream"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedProductStreamUnitId !== "")
                                                ? root.appState.connectedProductStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedProductStreamUnitId !== "")
                                                ? "#1c4ea7" : "#d6b74a"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Energy stream (in)" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedEnergyInStreamUnitId !== "")
                                                ? root.appState.connectedEnergyInStreamUnitId
                                                : "\u2014 optional \u2014"
                                    valueColor: (root.appState && root.appState.connectedEnergyInStreamUnitId !== "")
                                                ? "#1c4ea7" : "#526571"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Energy stream (out)"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedEnergyOutStreamUnitId !== "")
                                                ? root.appState.connectedEnergyOutStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedEnergyOutStreamUnitId !== "")
                                                ? "#1c4ea7" : "#526571"
                                }
                            }
                        }

                        // ── Specifications ─────────────────────────────────
                        PGroupBox {
                            id: specBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Specifications"
                            contentPadding: 8

                            GridLayout {
                                id: specGrid
                                width: specBox.width - (specBox.contentPadding * 2) - 2
                                columns: 3; columnSpacing: 0; rowSpacing: 0

                                // Spec mode picker — full-width combo (label | combo spanning 2 cols)
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Specification" }
                                PComboBox {
                                    id: specCombo
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    widthMode: "fill"
                                    model: ["Temperature", "Duty", "Vapor fraction"]
                                    enabled: !!root.appState
                                    currentIndex: {
                                        if (!root.appState) return 0
                                        if (root.appState.specMode === "duty")          return 1
                                        if (root.appState.specMode === "vaporFraction") return 2
                                        return 0
                                    }
                                    onActivated: function(index) {
                                        if (!root.appState) return
                                        var modes = ["temperature", "duty", "vaporFraction"]
                                        root.appState.specMode = modes[index]
                                    }
                                }

                                // Outlet temperature row — visible only in temperature spec mode
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Outlet temperature"
                                    alt: true
                                    visible: !root.appState || root.appState.specMode === "temperature"
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.outletTemperatureK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: !!root.appState
                                    visible: !root.appState || root.appState.specMode === "temperature"
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.outletTemperatureK = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.outletTemperatureK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    visible: !root.appState || root.appState.specMode === "temperature"
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }

                                // Duty row — visible only in duty spec mode.
                                // The state stores a signed kW (negative for coolers); the UI shows |Q|.
                                // On write we restore the sign based on the unit type.
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: root.dutyLabelText
                                    alt: true
                                    visible: root.appState ? (root.appState.specMode === "duty") : false
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Power"
                                    siValue: root.appState ? root._siPower(Math.abs(root.appState.dutyKW)) : NaN
                                    displayUnit: root.unitFor("Power")
                                    editable: !!root.appState
                                    visible: root.appState ? (root.appState.specMode === "duty") : false
                                    onEdited: function(siVal) {
                                        if (!root.appState) return
                                        var kW = root._kWfromSI(siVal)
                                        root.appState.dutyKW = root.isCoolerType
                                            ? -Math.abs(kW) : Math.abs(kW)
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Power"
                                    siValue: root.appState ? root._siPower(Math.abs(root.appState.dutyKW)) : NaN
                                    displayUnit: root.unitFor("Power")
                                    visible: root.appState ? (root.appState.specMode === "duty") : false
                                    onUnitOverride: function(u) { root.setUnit("Power", u) }
                                }

                                // Outlet vapor fraction row — visible only in vapor-fraction spec mode
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Outlet vapor fraction"
                                    alt: true
                                    visible: root.appState ? (root.appState.specMode === "vaporFraction") : false
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Dimensionless"
                                    siValue: root.appState ? root.appState.outletVaporFraction : NaN
                                    editable: !!root.appState
                                    visible: root.appState ? (root.appState.specMode === "vaporFraction") : false
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.outletVaporFraction = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Dimensionless"
                                    visible: root.appState ? (root.appState.specMode === "vaporFraction") : false
                                }
                            }
                        }

                        // ── Conditions ─────────────────────────────────────
                        // Always-visible operating conditions (pressure drop
                        // is independent of the active spec mode).
                        PGroupBox {
                            id: condBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Conditions"
                            contentPadding: 8

                            GridLayout {
                                id: condGrid
                                width: condBox.width - (condBox.contentPadding * 2) - 2
                                columns: 3; columnSpacing: 0; rowSpacing: 0

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Pressure drop" }
                                PGridValue {
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.pressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.pressureDropPa = siVal
                                    }
                                }
                                PGridUnit {
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.pressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ── Results tab ────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: root.currentTab === 1

            Rectangle {
                anchors.fill: parent
                color: "#e8ebef"

                Text {
                    anchors.centerIn: parent
                    visible: !root.appState
                    text: "No unit selected"
                    font.pixelSize: 11; color: "#526571"
                }

                ScrollView {
                    id: resultsScroll
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: !!root.appState
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: resultsScroll.availableWidth
                        spacing: 6

                        // ── Calculated Results ─────────────────────────────
                        PGroupBox {
                            id: resultsBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Calculated Results"
                            contentPadding: 8

                            GridLayout {
                                id: resultsGrid
                                width: resultsBox.width - (resultsBox.contentPadding * 2) - 2
                                columns: 3; columnSpacing: 0; rowSpacing: 0

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: root.dutyLabelText }
                                PGridValue {
                                    quantity: "Power"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root._siPower(Math.abs(root.appState.calcDutyKW)) : NaN
                                    displayUnit: root.unitFor("Power")
                                    editable: false
                                }
                                PGridUnit {
                                    quantity: "Power"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root._siPower(Math.abs(root.appState.calcDutyKW)) : NaN
                                    displayUnit: root.unitFor("Power")
                                    onUnitOverride: function(u) { root.setUnit("Power", u) }
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Outlet temperature"; alt: true }
                                PGridValue {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcOutletTempK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: false
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcOutletTempK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Outlet pressure" }
                                PGridValue {
                                    quantity: "Pressure"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcOutletPressurePa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: false
                                }
                                PGridUnit {
                                    quantity: "Pressure"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcOutletPressurePa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Outlet vapor fraction"; alt: true }
                                PGridValue {
                                    alt: true
                                    quantity: "Dimensionless"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcOutletVapFrac : NaN
                                    editable: false
                                }
                                PGridUnit { alt: true; quantity: "Dimensionless" }

                                // Direction banner — only shown when solved.
                                Item {
                                    Layout.columnSpan: 3
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.appState && root.appState.solved ? 28 : 0
                                    visible: !!(root.appState && root.appState.solved)

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.appState && root.appState.isCooling)
                                              ? "\u25bc  Heat removed from process stream"
                                              : "\u25b2  Heat added to process stream"
                                        color: (root.appState && root.appState.isCooling) ? "#1c6ea7" : "#a73c1c"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // ── Solver Status ──────────────────────────────────
                        PGroupBox {
                            id: statusBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Solver Status"
                            contentPadding: 8

                            GridLayout {
                                id: statusGrid
                                width: statusBox.width - (statusBox.contentPadding * 2) - 2
                                columns: 3; columnSpacing: 0; rowSpacing: 0

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Status" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: root.solveStatusText()
                                    valueColor: root.solveStatusColor()
                                }

                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Message"
                                    alt: true
                                    visible: !!(root.appState
                                                && !root.appState.solved
                                                && root.appState.solveStatus !== "")
                                }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: root.appState ? root.appState.solveStatus : ""
                                    valueColor: "#b23b3b"
                                    visible: !!(root.appState
                                                && !root.appState.solved
                                                && root.appState.solveStatus !== "")
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ── Bottom action bar (Solve / Reset + status text) ──────────────────────
    Rectangle {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40
        color: "#c8d0d8"
        border.color: "#6d7883"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            PButton {
                text: "\u25b6  Solve"
                minButtonWidth: 100
                enabled: !!root.appState
                onClicked: if (root.appState) root.appState.solve()
            }

            PButton {
                text: "Reset"
                minButtonWidth: 80
                enabled: !!root.appState
                onClicked: if (root.appState) root.appState.reset()
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.solveStatusText()
                color: root.solveStatusColor()
                font.pixelSize: 10
                font.bold: !!(root.appState && root.appState.solved)
            }
        }
    }
}
