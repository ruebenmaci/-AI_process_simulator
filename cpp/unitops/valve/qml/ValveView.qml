import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ValveView — same PPropertyView + PGroupBox + GridLayout shell as the
//  Pump view, retargeted at the ValveUnitState API.
//
//  Three tabs:
//    • Design      — Connections / Specifications (editable)
//                    Specifications block adapts based on specMode:
//                       outletPressure → Outlet pressure row visible
//                       deltaP         → ΔP (drop) row visible
//                    There is no efficiency or power input — the valve is a
//                    passive isenthalpic throttle.
//    • Results     — Calculated Results / Diagnostics
//    • Thermo Log  — searchable ListView of thermo + state trace lines
//
//  Bottom action bar: Solve / Reset PButtons + status chip — identical
//  treatment to PumpView. Status chip color comes from
//  appState.statusLevel (0=IDLE gray, 1=OK green, 2=WARN yellow, 3=FAIL red).
//
//  Unit handling:
//    pressure:    Pa
//    temperature: K
//    Dimensionless for vapor fraction
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  465
    implicitHeight: 579

    // Valve accent — orange/amber, suggestive of a throttling/letdown action.
    // Pump uses blue (#1c6ea7) for "lift", Cooler uses blue for "remove heat",
    // Heater uses red. Orange differentiates the valve from those at a glance.
    readonly property color accentColor: "#c97a1f"
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("valve"))
                                    : ""

    readonly property int labelColWidth: 180

    // ── Per-quantity unit overrides ──────────────────────────────────────────
    property var unitOverrides: ({
        "Temperature":   "",
        "Pressure":      "",
        "Dimensionless": ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // ── Status chip color/text driven by appState.statusLevel ────────────────
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

    // ── Thermo-log search state ──────────────────────────────────────────────
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

        // ── Design tab ──────────────────────────────────────────────────────
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

                        // ── Connections ─────────────────────────────────────
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
                            }
                        }

                        // ── Specifications ──────────────────────────────────
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
                                    model: ["Outlet pressure", "Delta P (drop)"]
                                    enabled: !!root.appState
                                    currentIndex: {
                                        if (!root.appState) return 1
                                        if (root.appState.specMode === "outletPressure") return 0
                                        return 1   // deltaP — default
                                    }
                                    onActivated: function(index) {
                                        if (!root.appState) return
                                        var modes = ["outletPressure", "deltaP"]
                                        root.appState.specMode = modes[index]
                                    }
                                }

                                // Outlet-pressure row (visible in outletPressure spec mode)
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Outlet pressure"
                                    alt: true
                                    visible: !root.appState || root.appState.specMode === "outletPressure"
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.outletPressurePa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    visible: !root.appState || root.appState.specMode === "outletPressure"
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.outletPressurePa = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.outletPressurePa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    visible: !root.appState || root.appState.specMode === "outletPressure"
                                    onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                }

                                // ΔP-drop row (visible in deltaP spec mode)
                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "ΔP (drop)"
                                    alt: true
                                    visible: root.appState ? (root.appState.specMode === "deltaP") : false
                                }
                                PGridValue {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.deltaPPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    visible: root.appState ? (root.appState.specMode === "deltaP") : false
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.deltaPPa = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.deltaPPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    visible: root.appState ? (root.appState.specMode === "deltaP") : false
                                    onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ── Results tab ─────────────────────────────────────────────────────
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

                            // Outlet pressure
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

                            // ΔP (drop)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "ΔP (drop)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Pressure"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcDeltaPPa : NaN
                                displayUnit: root.unitFor("Pressure")
                                editable: false
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Pressure"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcDeltaPPa : NaN
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            // Outlet temperature
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Outlet temperature" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcOutletTempK : NaN
                                displayUnit: root.unitFor("Temperature")
                                editable: false
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcOutletTempK : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // ΔT — JT temperature change. Signed value: typically
                            // negative for hydrocarbons (cooling on expansion),
                            // positive for H₂ / He near room T.
                            //
                            // Rendered as Dimensionless to avoid the absolute-T
                            // vs interval-T unit-conversion ambiguity (a 5 K
                            // interval is NOT the same as 5 K → 5 °F via offset
                            // transform). The label spells out "(K)" so the
                            // user knows the magnitude is in Kelvin (which is
                            // the same magnitude as a °C interval).
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "ΔT (K, Joule-Thomson)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcDeltaTK : NaN
                                editable: false
                            }
                            PGridUnit { alt: true; quantity: "Dimensionless" }

                            // Inlet vapor fraction — shown so the user can see
                            // at a glance whether the feed was sub-cooled
                            // liquid, two-phase, or superheated, and compare
                            // with the outlet vapor fraction directly below.
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Inlet vapor fraction" }
                            PGridValue {
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                         ? root.appState.calcInletVapFrac : NaN
                                editable: false
                            }
                            PGridUnit { quantity: "Dimensionless" }

                            // Outlet vapor fraction — the headline result for
                            // letdown service. ΔV = V_out − V_in is the flash
                            // fraction generated by the throttle.
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
                                    text: "\u25bc  Pressure dropped — isenthalpic throttle (H_out = H_in)"
                                    color: root.accentColor
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // ── Diagnostics ────────────────────────────────────────
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
                                    width: 180
                                    height: 20
                                    text: root.logSearchText
                                    anchors.verticalCenter: parent.verticalCenter
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

    // ── Bottom action bar (Solve / Reset + Status chip) ─────────────────────
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
