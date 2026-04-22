import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  HeatExchangerView — REFACTORED to the PPropertyView + PGroupBox + GridLayout
//  standard (same template as HeaterCoolerView / Stream panels).
//
//  Layout:
//    ┌─ PPropertyView ────────────────────────────────────────────────────┐
//    │ [icon] [Design] [Results]                       Unit Set: [SI ▾]  │
//    │ ╔════════════════════════════════════════════════════════════════╗ │
//    │ ║  ( Design tab )                                                ║ │
//    │ ║    PGroupBox "Connections"  (hot/cold in/out)                  ║ │
//    │ ║    PGroupBox "Specifications"  (spec mode + active value)      ║ │
//    │ ║    PGroupBox "Conditions"      (hot ΔP, cold ΔP)               ║ │
//    │ ║  ( Results tab )                                               ║ │
//    │ ║    PGroupBox "Calculated Results"                              ║ │
//    │ ║    PGroupBox "Solver Status"                                   ║ │
//    │ ╚════════════════════════════════════════════════════════════════╝ │
//    └────────────────────────────────────────────────────────────────────┘
//    [▶ Solve]  [Reset]                                 Solved  ✓
//
//  Unit handling:
//    State stores mixed-scale values (K, kW, Pa). PGridValue/PGridUnit work
//    in true SI, so small helpers convert on read/write:
//      duty:        kW ⇄ W
//      pressure:    already Pa, no conversion
//      temperature: already K,  no conversion
//
//  UA and approach temperature are shown as isText cells with local
//  formatting, because:
//    - UA doesn't have a registered gUnits quantity (W/K).
//    - Approach T is a temperature DIFFERENCE, and converting K→°C via
//      gUnits would subtract 273.15 which is wrong for deltas.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  410
    implicitHeight: 420

    // ── Type-aware helpers ───────────────────────────────────────────────────
    readonly property color hotColor:  "#a73c1c"
    readonly property color coldColor: "#1c6ea7"
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("heat_exchanger"))
                                    : ""

    // Label column width matches HeaterCoolerView for visual consistency.
    readonly property int labelColWidth: 180

    // ── Per-quantity unit overrides (same pattern as stream/heater panels) ──
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

    // ── Local formatting for non-gUnits cells ───────────────────────────────
    function _fmtNum(x, digits) {
        var n = Number(x)
        if (!isFinite(n)) return "\u2014"
        return n.toFixed(digits)
    }
    function _fmtUA(siWperK) {
        // Smart scaling: show kW/K if magnitude >= 1000 W/K, else W/K
        var n = Number(siWperK)
        if (!isFinite(n)) return "\u2014"
        return n >= 1000 ? (n / 1000).toFixed(2) + " kW/K" : n.toFixed(1) + " W/K"
    }
    function _fmtDeltaK(siK) {
        // Temperature DIFFERENCE — always shown in K. Converting to °C would
        // subtract 273.15 which is incorrect for a delta.
        var n = Number(siK)
        if (!isFinite(n)) return "\u2014"
        return n.toFixed(2) + " K"
    }

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

    // Convenience: is the active spec mode "duty" / "hotOutletT" / "coldOutletT"?
    readonly property string _specMode: appState ? appState.specMode : "duty"

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

        // Left accessory — the heat_exchanger icon.
        leftAccessory: Image {
            width: 16; height: 16
            source: root.iconPath
            sourceSize.width: 32
            sourceSize.height: 32
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // Right accessory — Unit Set selector (matches StreamView / HeaterCoolerView).
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

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Hot stream (in)" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedHotInStreamUnitId !== "")
                                                ? root.appState.connectedHotInStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedHotInStreamUnitId !== "")
                                                ? root.hotColor : "#d6b74a"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Hot stream (out)"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedHotOutStreamUnitId !== "")
                                                ? root.appState.connectedHotOutStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedHotOutStreamUnitId !== "")
                                                ? root.hotColor : "#d6b74a"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Cold stream (in)" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedColdInStreamUnitId !== "")
                                                ? root.appState.connectedColdInStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedColdInStreamUnitId !== "")
                                                ? root.coldColor : "#d6b74a"
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Cold stream (out)"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedColdOutStreamUnitId !== "")
                                                ? root.appState.connectedColdOutStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedColdOutStreamUnitId !== "")
                                                ? root.coldColor : "#d6b74a"
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

                                // Spec mode picker
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Specification" }
                                PComboBox {
                                    id: specCombo
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    widthMode: "fill"
                                    model: ["Duty", "Hot outlet T", "Cold outlet T"]
                                    enabled: !!root.appState
                                    currentIndex: {
                                        if (!root.appState) return 0
                                        if (root.appState.specMode === "hotOutletT")  return 1
                                        if (root.appState.specMode === "coldOutletT") return 2
                                        return 0
                                    }
                                    onActivated: function(index) {
                                        if (!root.appState) return
                                        var modes = ["duty", "hotOutletT", "coldOutletT"]
                                        root.appState.specMode = modes[index]
                                    }
                                }

                                // Duty row — visible only in duty spec mode
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Duty"
                                    alt: true
                                    visible: root._specMode === "duty"
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Power"
                                    siValue: root.appState ? root._siPower(root.appState.dutyKW) : NaN
                                    displayUnit: root.unitFor("Power")
                                    editable: !!root.appState
                                    visible: root._specMode === "duty"
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.dutyKW = root._kWfromSI(siVal)
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Power"
                                    siValue: root.appState ? root._siPower(root.appState.dutyKW) : NaN
                                    displayUnit: root.unitFor("Power")
                                    visible: root._specMode === "duty"
                                    onUnitOverride: function(u) { root.setUnit("Power", u) }
                                }

                                // Hot outlet T row — visible only in hotOutletT spec mode
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Hot outlet temperature"
                                    alt: true
                                    visible: root._specMode === "hotOutletT"
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.hotOutletTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: !!root.appState
                                    visible: root._specMode === "hotOutletT"
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.hotOutletTK = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.hotOutletTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    visible: root._specMode === "hotOutletT"
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }

                                // Cold outlet T row — visible only in coldOutletT spec mode
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Cold outlet temperature"
                                    alt: true
                                    visible: root._specMode === "coldOutletT"
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.coldOutletTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: !!root.appState
                                    visible: root._specMode === "coldOutletT"
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.coldOutletTK = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: root.appState ? root.appState.coldOutletTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    visible: root._specMode === "coldOutletT"
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }
                            }
                        }

                        // ── Conditions ─────────────────────────────────────
                        // Hot-side and cold-side pressure drops (always visible).
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

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Hot side ΔP" }
                                PGridValue {
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.hotSidePressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.hotSidePressureDropPa = siVal
                                    }
                                }
                                PGridUnit {
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.hotSidePressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                }

                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Cold side ΔP"; alt: true }
                                PGridValue {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.coldSidePressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.coldSidePressureDropPa = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.coldSidePressureDropPa : NaN
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

                                // Duty
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Duty" }
                                PGridValue {
                                    quantity: "Power"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root._siPower(root.appState.calcDutyKW) : NaN
                                    displayUnit: root.unitFor("Power")
                                    editable: false
                                }
                                PGridUnit {
                                    quantity: "Power"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root._siPower(root.appState.calcDutyKW) : NaN
                                    displayUnit: root.unitFor("Power")
                                    onUnitOverride: function(u) { root.setUnit("Power", u) }
                                }

                                // Hot outlet T
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Hot outlet T"; alt: true }
                                PGridValue {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcHotOutTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: false
                                    valueColor: root.hotColor
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcHotOutTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }

                                // Cold outlet T
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Cold outlet T" }
                                PGridValue {
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcColdOutTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    editable: false
                                    valueColor: root.coldColor
                                }
                                PGridUnit {
                                    quantity: "Temperature"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcColdOutTK : NaN
                                    displayUnit: root.unitFor("Temperature")
                                    onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                }

                                // Hot outlet vapor fraction
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Hot outlet vap. frac."; alt: true }
                                PGridValue {
                                    alt: true
                                    quantity: "Dimensionless"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcHotOutVapFrac : NaN
                                    editable: false
                                }
                                PGridUnit { alt: true; quantity: "Dimensionless" }

                                // Cold outlet vapor fraction
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Cold outlet vap. frac." }
                                PGridValue {
                                    quantity: "Dimensionless"
                                    siValue: (root.appState && root.appState.solved)
                                             ? root.appState.calcColdOutVapFrac : NaN
                                    editable: false
                                }
                                PGridUnit { quantity: "Dimensionless" }

                                // LMTD — text cell (temperature delta, not absolute)
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "LMTD"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    textValue: (root.appState && root.appState.solved)
                                               ? root._fmtDeltaK(root.appState.calcLMTD) : "\u2014"
                                }

                                // UA — text cell (no registered gUnits quantity for W/K)
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "UA" }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    textValue: (root.appState && root.appState.solved)
                                               ? root._fmtUA(root.appState.calcUA) : "\u2014"
                                }

                                // Approach temperature — text cell (delta)
                                PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Approach ΔT"; alt: true }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    textValue: (root.appState && root.appState.solved)
                                               ? root._fmtDeltaK(root.appState.calcApproachT) : "\u2014"
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
