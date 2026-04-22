import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  HeaterCoolerView — PPropertyView + PGroupBox + GridLayout standard.
//  Three tabs:
//    • Design      — Connections / Specifications / Conditions (editable)
//    • Results     — Calculated Results / Diagnostics (read-only)
//    • Thermo Log  — searchable ListView of thermo + state trace lines
//
//  Bottom action bar contains Solve / Reset PButtons (80 px each, bold,
//  no arrow) and a right-aligned "Status" PGroupBox with a 60×18 colored
//  chip driven by appState.statusLevel (0=gray IDLE, 1=green OK, 2=yellow
//  WARN, 3=red FAIL, 4=blue SOLVING). Chip shows centered status text in
//  contrasting color.
//
//  Unit handling (same pattern as StreamConditionsPanel):
//    duty:        kW ⇄ W
//    pressure:    already Pa
//    temperature: already K
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  465
    implicitHeight: 579

    // ── Type-aware helpers ───────────────────────────────────────────────────
    readonly property bool  isCoolerType: !!appState && appState.type === "cooler"
    readonly property color accentColor:  isCoolerType ? "#1c6ea7" : "#a73c1c"
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath(isCoolerType ? "cooler" : "heater"))
                                    : ""
    readonly property string dutyLabelText: isCoolerType ? "Cooling duty" : "Heating duty"

    readonly property int labelColWidth: 180

    // ── Per-quantity unit overrides ──────────────────────────────────────────
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

    function _siPower(kW)   { return kW * 1000.0 }
    function _kWfromSI(siW) { return siW / 1000.0 }

    // ── Status chip color driven by appState.statusLevel enum ────────────────
    //   0 = None    (neutral gray)
    //   1 = Ok      (green)
    //   2 = Warn    (yellow)
    //   3 = Fail    (red)
    //   4 = Solving (blue — reserved for future async-solve refactor; solve()
    //                is currently synchronous so this value is never emitted)
    function statusChipColor() {
        if (!appState) return "#9ba3ab"
        var lvl = appState.statusLevel
        if (lvl === 1) return "#1a7a3c"
        if (lvl === 2) return "#d6b74a"
        if (lvl === 3) return "#b23b3b"
        if (lvl === 4) return "#2c6fb5"
        return "#9ba3ab"
    }

    // Text label rendered inside the chip. Matches statusChipColor branches.
    function statusChipText() {
        if (!appState) return "IDLE"
        var lvl = appState.statusLevel
        if (lvl === 1) return "OK"
        if (lvl === 2) return "WARN"
        if (lvl === 3) return "FAIL"
        if (lvl === 4) return "SOLVING"
        return "IDLE"
    }

    // Text color inside the chip. WARN's yellow fill needs dark text for
    // legibility; every other state uses white on a dark/mid fill.
    function statusChipTextColor() {
        if (!appState) return "#ffffff"
        return appState.statusLevel === 2 ? "#2a2004" : "#ffffff"
    }

    // ── Thermo-log search state (populated when the Thermo Log tab is active) ─
    property string logSearchText: ""
    property var    logSearchMatches: []
    property int    logCurrentMatchPos: -1
    property bool   logCaseSensitive: false

    function refreshLogSearch() {
        if (!appState || !appState.runLogModel || logSearchText === "") {
            logSearchMatches = []
            logCurrentMatchPos = -1
            return
        }
        logSearchMatches = appState.runLogModel.findMatches(logSearchText, logCaseSensitive)
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

                                // Outlet temperature row (visible in temperature spec mode)
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

                                // Duty row (visible in duty spec mode) — see Heater/Cooler sign convention
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

                                // Outlet vapor fraction row (visible in vapor-fraction spec mode)
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

                // Vertical split: Calculated Results on top (fixed height via
                // implicit sizing), Diagnostics fills the rest.
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6
                    visible: !!root.appState

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
                            // "-7" accounts for caption overhang; matches PGroupBox internal offset.

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

                                    // Level dot
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

                // Unlabelled groupbox fills entire tab area
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

                        // Find bar
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

                        // Log list
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

            // Right-aligned Status groupbox with a small colored chip.
            PGroupBox {
                id: statusBox
                Layout.alignment: Qt.AlignVCenter
                caption: "Status"
                contentPadding: 12

                // Sized by the chip — PGroupBox computes its own implicitWidth/
                // implicitHeight from this child via contentHolder.childrenRect.
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
