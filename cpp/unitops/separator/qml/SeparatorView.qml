import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  SeparatorView — 2-phase vapor-liquid separator (HYSYS "Separator" /
//  Aspen Plus "Flash2"). Mirrors HeaterCoolerView's PPropertyView + PGroupBox
//  + GridLayout structure, with separator-specific differences:
//
//    Connections:    feed (left), vapor outlet (right top), liquid outlet
//                    (right bottom). Vapor and liquid rows carry a small
//                    coloured V/L badge so the role is glanceable without
//                    reading the row label.
//
//    Specifications: spec-mode dropdown drives row visibility —
//                      "adiabatic"   → no editable spec; explainer line shown
//                      "duty"        → shows duty (kW)
//                      "temperature" → shows vessel T (K)
//
//    Conditions:     pressure drop only (matches heater).
//
//  Results tab is split into three stacked groupboxes — Vessel Conditions
//  (T, P, duty), Vapor Outlet (mass flow + mole/mass fraction), Liquid Outlet
//  (mass flow + mass fraction) — followed by a Diagnostics ListView that
//  fills the remaining height. The two outlet groupboxes carry the same
//  V/L badge as the Connections rows for visual continuity.
//
//  Thermo Log tab is identical to HeaterCoolerView's — searchable monospace
//  ListView of [state] and thermo trace lines, with Find / Prev / Next /
//  Clear / Case toggles.
//
//  Bottom action bar: Solve / Reset PButtons + right-aligned Status chip,
//  identical pattern to HeaterCoolerView.
//
//  Unit handling (same as StreamConditionsPanel):
//    duty:        kW ⇄ W
//    pressure:    already Pa
//    temperature: already K
//    mass flow:   kg/h ⇄ kg/s
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  465
    implicitHeight: 620

    // ── Visual constants ─────────────────────────────────────────────────────
    // Icon path for the property-view leftAccessory. Uses the separator key
    // so AppTheme resolves the new SVG correctly.
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("separator"))
                                    : ""

    readonly property int labelColWidth: 180

    // ── Per-quantity unit overrides ──────────────────────────────────────────
    property var unitOverrides: ({
        "Temperature":   "",
        "Pressure":      "",
        "Power":         "",
        "MassFlow":      "",
        "Dimensionless": ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // SI conversion helpers — see HeaterCoolerView for rationale.
    function _siPower(kW)        { return kW * 1000.0 }
    function _kWfromSI(siW)      { return siW / 1000.0 }
    function _siMassFlow(kgph)   { return kgph / 3600.0 }   // kg/h → kg/s
    function _kgphFromSI(kgps)   { return kgps * 3600.0 }

    // ── Status chip helpers (identical convention to HeaterCoolerView) ──────
    //   0 = None    (neutral gray)
    //   1 = Ok      (green)
    //   2 = Warn    (yellow)
    //   3 = Fail    (red)
    //   4 = Solving (blue — reserved)
    function statusChipColor() {
        if (!appState) return "#9ba3ab"
        var lvl = appState.statusLevel
        if (lvl === 1) return "#1a7a3c"
        if (lvl === 2) return "#d6b74a"
        if (lvl === 3) return "#b23b3b"
        if (lvl === 4) return "#2c6fb5"
        return "#9ba3ab"
    }
    function statusChipText() {
        if (!appState) return "IDLE"
        var lvl = appState.statusLevel
        if (lvl === 1) return "OK"
        if (lvl === 2) return "WARN"
        if (lvl === 3) return "FAIL"
        if (lvl === 4) return "SOLVING"
        return "IDLE"
    }
    function statusChipTextColor() {
        if (!appState) return "#ffffff"
        return appState.statusLevel === 2 ? "#2a2004" : "#ffffff"
    }

    // ── Spec-mode helper: contextual explainer text for the Specifications
    // groupbox. Changes per mode so the panel doesn't look empty in
    // adiabatic mode. Returns "" for unknown modes (fallback).
    function specExplainer() {
        if (!appState) return ""
        var m = appState.specMode
        if (m === "adiabatic")
            return "Adiabatic: no duty added. Vessel T and phase split are found from a PH flash at the inlet enthalpy."
        if (m === "duty")
            return "Duty: user specifies Q in kW. Vessel T and phase split are found from a PH flash at (H_in + Q·3600/ṁ)."
        if (m === "temperature")
            return "Temperature: user specifies vessel T. Phase split is from a PT flash; duty is back-calculated."
        return ""
    }

    // ── Thermo-log search state (identical to HeaterCoolerView) ──────────────
    property string logSearchText: ""
    property var    logSearchMatches: []
    property int    logCurrentMatchPos: -1
    property bool   logCaseSensitive: false

    function refreshLogSearch() {
        if (!appState || !appState.runLogModel) {
            logSearchMatches = []
            logCurrentMatchPos = -1
            return
        }
        var matches = []
        if (logSearchText !== "") {
            var n = appState.runLogModel.rowCount()
            for (var i = 0; i < n; ++i) {
                var line = appState.runLogModel.lineAt(i)
                if (logLineMatches(line))
                    matches.push(i)
            }
        }
        logSearchMatches = matches
        if (!logSearchMatches || logSearchMatches.length === 0) {
            logCurrentMatchPos = -1
            return
        }
        if (logCurrentMatchPos < 0 || logCurrentMatchPos >= logSearchMatches.length)
            logCurrentMatchPos = 0
        positionAtLogMatch()
    }
    function positionAtLogMatch() {
        if (!logSearchMatches || logCurrentMatchPos < 0 || logCurrentMatchPos >= logSearchMatches.length)
            return
        if (typeof logListView !== "undefined" && logListView)
            logListView.positionViewAtIndex(logSearchMatches[logCurrentMatchPos], ListView.Center)
    }
    function nextLogMatch() {
        if (!logSearchMatches || logSearchMatches.length === 0) return
        logCurrentMatchPos = (logCurrentMatchPos + 1) % logSearchMatches.length
        positionAtLogMatch()
    }
    function prevLogMatch() {
        if (!logSearchMatches || logSearchMatches.length === 0) return
        logCurrentMatchPos = (logCurrentMatchPos - 1 + logSearchMatches.length) % logSearchMatches.length
        positionAtLogMatch()
    }
    function clearLogSearch() {
        logSearchText = ""
        logSearchMatches = []
        logCurrentMatchPos = -1
    }
    function logLineMatches(lineText) {
        if (logSearchText === "") return false
        var line = String(lineText || "")
        if (logCaseSensitive) return line.indexOf(logSearchText) >= 0
        return line.toLowerCase().indexOf(logSearchText.toLowerCase()) >= 0
    }

    // ── Property view shell ──────────────────────────────────────────────────
    PPropertyView {
        id: pview
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top

        tabs: [ { text: "Design" }, { text: "Results" }, { text: "Thermo Log" } ]
        currentIndex: root.currentTab
        onTabClicked: function(i) { root.currentTab = i }

        leftAccessory: Image {
            width: 16; height: 16
            source: root.iconPath
            sourceSize.width: 32
            sourceSize.height: 32
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

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

                                // Feed row — no badge needed
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

                                // Vapor outlet row
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Vapor outlet"
                                    alt: true
                                }
                                PGridValue {
                                    alt: true
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedVaporStreamUnitId !== "")
                                                ? root.appState.connectedVaporStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedVaporStreamUnitId !== "")
                                                ? "#1c4ea7" : "#d6b74a"
                                }

                                // Liquid outlet row
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Liquid outlet"
                                }
                                PGridValue {
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    isText: true
                                    alignText: "left"
                                    textValue: (root.appState && root.appState.connectedLiquidStreamUnitId !== "")
                                                ? root.appState.connectedLiquidStreamUnitId
                                                : "\u2014 not connected \u2014"
                                    valueColor: (root.appState && root.appState.connectedLiquidStreamUnitId !== "")
                                                ? "#1c4ea7" : "#d6b74a"
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

                            ColumnLayout {
                                width: specBox.width - (specBox.contentPadding * 2) - 2
                                spacing: 0

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3; columnSpacing: 0; rowSpacing: 0

                                    PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Specification" }
                                    PComboBox {
                                        id: specCombo
                                        Layout.columnSpan: 2
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 22
                                        widthMode: "fill"
                                        model: ["Adiabatic", "Duty", "Temperature"]
                                        enabled: !!root.appState
                                        currentIndex: {
                                            if (!root.appState) return 0
                                            if (root.appState.specMode === "duty")        return 1
                                            if (root.appState.specMode === "temperature") return 2
                                            return 0
                                        }
                                        onActivated: function(index) {
                                            if (!root.appState) return
                                            var modes = ["adiabatic", "duty", "temperature"]
                                            root.appState.specMode = modes[index]
                                        }
                                    }

                                    // Duty row (visible only in "duty" mode)
                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Vessel duty"
                                        alt: true
                                        visible: root.appState ? (root.appState.specMode === "duty") : false
                                    }
                                    PGridValue {
                                        alt: true
                                        quantity: "Power"
                                        siValue: root.appState ? root._siPower(root.appState.dutyKW) : NaN
                                        displayUnit: root.unitFor("Power")
                                        editable: !!root.appState
                                        visible: root.appState ? (root.appState.specMode === "duty") : false
                                        onEdited: function(siVal) {
                                            if (root.appState) root.appState.dutyKW = root._kWfromSI(siVal)
                                        }
                                    }
                                    PGridUnit {
                                        alt: true
                                        quantity: "Power"
                                        siValue: root.appState ? root._siPower(root.appState.dutyKW) : NaN
                                        displayUnit: root.unitFor("Power")
                                        visible: root.appState ? (root.appState.specMode === "duty") : false
                                        onUnitOverride: function(u) { root.setUnit("Power", u) }
                                    }

                                    // Vessel-T row (visible only in "temperature" mode)
                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Vessel temperature"
                                        alt: true
                                        visible: root.appState ? (root.appState.specMode === "temperature") : false
                                    }
                                    PGridValue {
                                        alt: true
                                        quantity: "Temperature"
                                        siValue: root.appState ? root.appState.vesselTemperatureK : NaN
                                        displayUnit: root.unitFor("Temperature")
                                        editable: !!root.appState
                                        visible: root.appState ? (root.appState.specMode === "temperature") : false
                                        onEdited: function(siVal) {
                                            if (root.appState) root.appState.vesselTemperatureK = siVal
                                        }
                                    }
                                    PGridUnit {
                                        alt: true
                                        quantity: "Temperature"
                                        siValue: root.appState ? root.appState.vesselTemperatureK : NaN
                                        displayUnit: root.unitFor("Temperature")
                                        visible: root.appState ? (root.appState.specMode === "temperature") : false
                                        onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                    }
                                }

                                // Contextual explainer line — visible whenever appState exists.
                                // Sits below the spec grid so users always see what the
                                // selected mode means, especially valuable in "adiabatic"
                                // mode which has no editable rows.
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: explainerText.implicitHeight + 12
                                    Layout.topMargin: 4
                                    color: "#f3efe6"
                                    border.color: "#bdb6a7"
                                    border.width: 1
                                    visible: !!root.appState

                                    Text {
                                        id: explainerText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: 6
                                        text: root.specExplainer()
                                        font.pixelSize: 10
                                        font.italic: true
                                        color: "#5f6770"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // ── Conditions ─────────────────────────────────────
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

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6
                    visible: !!root.appState

                    // ── Vessel Conditions ─────────────────────────────────
                    PGroupBox {
                        id: vesselBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        caption: "Vessel Conditions"
                        contentPadding: 8

                        GridLayout {
                            width: vesselBox.width - (vesselBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vessel temperature" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVesselTempK : NaN
                                displayUnit: root.unitFor("Temperature")
                                editable: false
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVesselTempK : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vessel pressure"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Pressure"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVesselPressurePa : NaN
                                displayUnit: root.unitFor("Pressure")
                                editable: false
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Pressure"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVesselPressurePa : NaN
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vessel duty" }
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
                        }
                    }

                    // ── Vapor Outlet ─────────────────────────────────────
                    PGroupBox {
                        id: vaporBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        caption: "Vapor Outlet"
                        contentPadding: 8

                        GridLayout {
                            width: vaporBox.width - (vaporBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Mass flow" }
                            PGridValue {
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.solved)
                                         ? root._siMassFlow(root.appState.calcVaporFlowKgph) : NaN
                                displayUnit: root.unitFor("MassFlow")
                                editable: false
                            }
                            PGridUnit {
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.solved)
                                         ? root._siMassFlow(root.appState.calcVaporFlowKgph) : NaN
                                displayUnit: root.unitFor("MassFlow")
                                onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vapor fraction (mole)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVaporMoleFrac : NaN
                                editable: false
                            }
                            PGridUnit { alt: true; quantity: "Dimensionless" }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vapor fraction (mass)" }
                            PGridValue {
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcVaporMassFrac : NaN
                                editable: false
                            }
                            PGridUnit { quantity: "Dimensionless" }
                        }
                    }

                    // ── Liquid Outlet ────────────────────────────────────
                    PGroupBox {
                        id: liquidBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        caption: "Liquid Outlet"
                        contentPadding: 8

                        GridLayout {
                            width: liquidBox.width - (liquidBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Mass flow" }
                            PGridValue {
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.solved)
                                         ? root._siMassFlow(root.appState.calcLiquidFlowKgph) : NaN
                                displayUnit: root.unitFor("MassFlow")
                                editable: false
                            }
                            PGridUnit {
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.solved)
                                         ? root._siMassFlow(root.appState.calcLiquidFlowKgph) : NaN
                                displayUnit: root.unitFor("MassFlow")
                                onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Liquid fraction (mass)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                         ? (1.0 - root.appState.calcVaporMassFrac) : NaN
                                editable: false
                            }
                            PGridUnit { alt: true; quantity: "Dimensionless" }
                        }
                    }

                    // ── Diagnostics (fills remaining height) ──────────────
                    PGroupBox {
                        id: diagBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        caption: "Diagnostics"
                        contentPadding: 8

                        Item {
                            width:  diagBox.width  - (diagBox.contentPadding * 2) - 2
                            height: diagBox.height - (diagBox.contentPadding * 2) - 2 - 7

                            ListView {
                                id: diagList
                                anchors.fill: parent
                                clip: true
                                model: root.appState ? root.appState.diagnosticsModel : null
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Item {
                                    width: diagList.width
                                    height: Math.max(20, diagMsg.implicitHeight + 6)

                                    Rectangle {
                                        anchors.fill: parent
                                        color: index % 2 === 0 ? "#f4f6f9" : "#ebeef2"
                                    }

                                    Rectangle {
                                        width: 8; height: 8; radius: 2
                                        x: 4; y: 6
                                        color: model.level === "error" ? "#b23b3b"
                                             : model.level === "warn"  ? "#d6b74a"
                                             : "#1c4ea7"
                                    }

                                    Text {
                                        id: diagMsg
                                        x: 18
                                        y: 3
                                        width: parent.width - 22
                                        text: model.message || ""
                                        font.pixelSize: 11
                                        font.family: "Segoe UI"
                                        color: "#1f2226"
                                        wrapMode: Text.Wrap
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.appState || !root.appState.diagnosticsModel || diagList.count === 0
                                    text: "No diagnostics"
                                    color: "#526571"
                                    font.pixelSize: 11
                                    font.italic: true
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Thermo Log tab ─────────────────────────────────────────────────
        // Identical to HeaterCoolerView's Thermo Log: searchable monospace
        // ListView with Find / Prev / Next / Clear / Case toggles. The model
        // is appState.runLogModel (RunLogModel) which streams [state] and
        // thermo trace lines as the solve runs.
        Item {
            anchors.fill: parent
            visible: root.currentTab === 2

            Rectangle {
                anchors.fill: parent
                color: "#e8ebef"

                Text {
                    anchors.centerIn: parent
                    visible: !root.appState
                    text: "No unit selected"
                    font.pixelSize: 11; color: "#526571"
                }

                PGroupBox {
                    id: logBox
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: !!root.appState
                    caption: ""
                    contentPadding: 6

                    Item {
                        width:  logBox.width  - (logBox.contentPadding * 2) - 2
                        height: logBox.height - (logBox.contentPadding * 2) - 2

                        Rectangle {
                            id: findBar
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 26
                            color: "#d8dde2"
                            border.color: "#97a2ad"
                            border.width: 1

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: "Find"
                                    font.pixelSize: 11
                                    color: "#1f2226"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                PTextField {
                                    id: logSearchField
                                    width: 160
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.logSearchText
                                    placeholderText: "PH_FLASH, [state], ..."
                                    onTextChanged: {
                                        root.logSearchText = text
                                        root.refreshLogSearch()
                                    }
                                }

                                PCheckBox {
                                    id: logCaseBox
                                    text: "Case"
                                    checked: root.logCaseSensitive
                                    fontPixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    onToggled: {
                                        root.logCaseSensitive = checked
                                        root.refreshLogSearch()
                                    }
                                }

                                PButton {
                                    text: "Prev"
                                    minButtonWidth: 40
                                    fontPixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: root.logSearchMatches.length > 0
                                    onClicked: root.prevLogMatch()
                                }

                                PButton {
                                    text: "Next"
                                    minButtonWidth: 40
                                    fontPixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: root.logSearchMatches.length > 0
                                    onClicked: root.nextLogMatch()
                                }

                                PButton {
                                    text: "Clear"
                                    minButtonWidth: 42
                                    fontPixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: root.logSearchText !== ""
                                    onClicked: {
                                        logSearchField.text = ""
                                        root.clearLogSearch()
                                    }
                                }

                                Text {
                                    text: root.logSearchText === "" ? ""
                                         : (root.logSearchMatches.length === 0
                                            ? "0 matches"
                                            : ((root.logCurrentMatchPos + 1) + " of " + root.logSearchMatches.length))
                                    font.pixelSize: 10
                                    color: "#526571"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: findBar.bottom
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 4
                            color: "#ffffff"
                            border.color: "#97a2ad"
                            border.width: 1

                            ListView {
                                id: logListView
                                anchors.fill: parent
                                anchors.margins: 1
                                clip: true
                                model: root.appState ? root.appState.runLogModel : null
                                spacing: 0
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Item {
                                    width: logListView.width
                                    height: 16

                                    property bool rowIsMatch: root.logLineMatches(model.text || "")
                                    property bool rowIsCurrent: root.logSearchMatches.length > 0
                                                                && root.logCurrentMatchPos >= 0
                                                                && index === root.logSearchMatches[root.logCurrentMatchPos]

                                    Rectangle {
                                        anchors.fill: parent
                                        color: rowIsCurrent ? "#ffe79a"
                                             : rowIsMatch   ? "#fff4c7"
                                             : (index % 2 === 0 ? "#ffffff" : "#f5f7fa")
                                    }

                                    Text {
                                        x: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: model.text || ""
                                        font.pixelSize: 10
                                        font.family: "Consolas, Courier New, monospace"
                                        color: "#1f2226"
                                    }
                                }

                                onCountChanged: {
                                    if (root.logSearchText !== "")
                                        Qt.callLater(function() { root.refreshLogSearch() })
                                    else
                                        Qt.callLater(function() { logListView.positionViewAtEnd() })
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.appState || !root.appState.runLogModel || logListView.count === 0
                                    text: "No log entries yet — run Solve"
                                    color: "#526571"
                                    font.pixelSize: 11
                                    font.italic: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Bottom action bar (Solve / Reset + Status chip) ──────────────────────
    Rectangle {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        color: "#c8d0d8"
        border.color: "#6d7883"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            PButton {
                text: "Solve"
                minButtonWidth: 80
                font.bold: true
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

            PGroupBox {
                id: statusBox
                Layout.alignment: Qt.AlignVCenter
                caption: "Status"
                contentPadding: 12

                Rectangle {
                    id: statusChip
                    width: 60
                    height: 14
                    color: root.statusChipColor()
                    border.color: "#3a3f47"
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: root.statusChipText()
                        color: root.statusChipTextColor()
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }
        }
    }
}
