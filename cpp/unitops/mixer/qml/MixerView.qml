import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  MixerView — Mixer (HYSYS "Mixer" / Aspen Plus "Mixer" block).
//  Three tabs: Design, Results, Thermo Log.
//
//  Layout shape mirrors SplitterView (variable-N ListView with fixed visible
//  rows so the surrounding controls stay anchored as inletCount changes) but
//  flipped — the variable side is the inlets, plus a single fixed Product
//  row in Connections.
//
//  Design tab:
//    Connections      — N inlet rows (variable height-bounded ListView) + 1
//                       fixed product row.
//    Specifications   — inletCount spinner (2–8), pressureMode combo
//                       (lowestInlet/equalizeAll/specified), conditional
//                       Outlet pressure field (only editable in "specified"
//                       mode), flashPhaseMode combo (vle/massBalanceOnly).
//
//  Results tab:
//    Outlet Conditions — T, P, vapor mole/mass frac, mass flow, pressure
//                        source label.
//    Diagnostics       — fills remaining height.
//
//  Thermo Log tab:
//    Identical to SeparatorView/HeaterCoolerView Thermo Log — searchable
//    monospace ListView with Find / Prev / Next / Clear / Case toggles.
//    Model is appState.runLogModel.
//
//  AOT-safe rules (from project memory):
//    no for...of, no arrow functions, no const, no fractional font.pixelSize,
//    no `this` in Repeater/ListView delegate signal handlers, no `id:` on
//    Repeater delegates' inner items where avoidable.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  465
    implicitHeight: 620

    // ── Visual constants ─────────────────────────────────────────────────────
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("mixer"))
                                    : ""

    readonly property int labelColWidth: 180

    // Variable-N row tuning — same idiom as SplitterView. The Connections
    // "inlets" list reserves vertical space equivalent to N rows so that
    // shrinking/growing inletCount doesn't push the rest of the panel
    // around.
    readonly property int inletRowHeight:    22
    readonly property int inletVisibleRows:  3
    readonly property int inletListHeight:
        inletRowHeight * inletVisibleRows
        + Math.max(0, inletVisibleRows - 1) * 2

    // ── Per-quantity unit overrides ──────────────────────────────────────────
    property var unitOverrides: ({
        "Pressure":      "",
        "Temperature":   "",
        "MassFlow":      "",
        "Dimensionless": ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // ── Status chip helpers (same convention as SplitterView/SeparatorView) ─
    function statusChipColor() {
        if (!appState) return "#9ba3ab"
        var s = appState.statusLevel
        if (s === 1) return "#1f9c5b"
        if (s === 2) return "#d6b74a"
        if (s === 3) return "#c63e3e"
        if (s === 4) return "#1c4ea7"
        return "#9ba3ab"
    }
    function statusChipText() {
        if (!appState) return "—"
        var s = appState.statusLevel
        if (s === 1) return "OK"
        if (s === 2) return "WARN"
        if (s === 3) return "FAIL"
        if (s === 4) return "SOLVING"
        return "IDLE"
    }
    function statusChipTextColor() {
        if (!appState) return "#ffffff"
        return appState.statusLevel === 2 ? "#2a2004" : "#ffffff"
    }

    // ── Spec-mode helpers ────────────────────────────────────────────────────
    // pressureMode is one of three; we map between combo index and string
    // here so the C++ side can keep its readable string-typed property.
    readonly property var pressureModeIds:    [ "lowestInlet", "equalizeAll", "specified" ]
    readonly property var pressureModeLabels: [ "Lowest Inlet", "Equalize All", "Specified" ]

    readonly property var flashPhaseModeIds:    [ "vle", "massBalanceOnly" ]
    readonly property var flashPhaseModeLabels: [ "Vapor-Liquid (PH flash)", "Mass Balance Only" ]

    function pressureModeIndex() {
        if (!appState) return 0
        var s = appState.pressureMode
        for (var i = 0; i < pressureModeIds.length; ++i)
            if (pressureModeIds[i] === s) return i
        return 0
    }
    function flashPhaseModeIndex() {
        if (!appState) return 0
        var s = appState.flashPhaseMode
        for (var i = 0; i < flashPhaseModeIds.length; ++i)
            if (flashPhaseModeIds[i] === s) return i
        return 0
    }

    function pressureModeExplainer() {
        if (!appState) return ""
        var m = appState.pressureMode
        if (m === "lowestInlet")
            return "Outlet pressure = lowest inlet pressure. The HYSYS / Aspen default. No work added."
        if (m === "equalizeAll")
            return "Outlet pressure = highest inlet pressure. Lower-pressure feeds physically need a pump upstream."
        if (m === "specified")
            return "Outlet pressure is user-specified. Setting it above any inlet pressure requires a pump upstream."
        return ""
    }
    function flashPhaseExplainer() {
        if (!appState) return ""
        var m = appState.flashPhaseMode
        if (m === "vle")
            return "Adiabatic PH flash on the combined stream finds outlet T and vapor fraction."
        if (m === "massBalanceOnly")
            return "No flash. Outlet T is mass-weighted average of inlets — approximate; no equilibrium."
        return ""
    }

    // ── Thermo-log search state (identical to SeparatorView) ─────────────────
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

    // ── Tabs definition ──────────────────────────────────────────────────────
    readonly property var tabsModel: [
        { text: "Design"     },
        { text: "Results"    },
        { text: "Thermo Log" }
    ]

    // ─────────────────────────────────────────────────────────────────────────
    PPropertyView {
        id: propView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top

        tabs: root.tabsModel
        currentIndex: root.currentTab
        onTabClicked: function(idx) { root.currentTab = idx }

        leftAccessory: Image {
            visible: source !== ""
            source: root.iconPath
            sourceSize.width:  18
            sourceSize.height: 18
            width:  18
            height: 18
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

        // ── Tab content area ────────────────────────────────────────────────
        Item {
            anchors.fill: parent

            // ── Tab 0: Design ───────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.currentTab === 0

                ScrollView {
                    id: designScroll
                    anchors.fill: parent
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: designScroll.availableWidth
                        spacing: 10

                        // ── Connections ─────────────────────────────────────
                        PGroupBox {
                            id: connBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Connections"
                            contentPadding: 8

                            ColumnLayout {
                                width: connBox.width - (connBox.contentPadding * 2) - 2
                                spacing: 2

                                // Inlet rows — variable count, driven by
                                // appState.connectedInletStreamUnitIds. Wrapped
                                // in a fixed-height ListView (3 visible rows)
                                // so the panel layout doesn't shift as
                                // inletCount changes.
                                ListView {
                                    id: connInletList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.inletListHeight
                                    Layout.minimumHeight:   root.inletListHeight
                                    Layout.maximumHeight:   root.inletListHeight
                                    clip: true
                                    spacing: 2
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: count > root.inletVisibleRows
                                    model: root.appState ? root.appState.connectedInletStreamUnitIds : []
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: RowLayout {
                                        property int inletIdx: index
                                        property string streamId: modelData
                                        width: connInletList.width
                                        height: root.inletRowHeight
                                        spacing: 4

                                        PGridLabel {
                                            Layout.preferredWidth: root.labelColWidth
                                            text: "Inlet " + (inletIdx + 1)
                                            alt: (inletIdx % 2 === 0) ? false : true
                                        }
                                        PGridValue {
                                            Layout.fillWidth: true
                                            alt: (inletIdx % 2 === 0) ? false : true
                                            isText: true
                                            alignText: "left"
                                            textValue: streamId !== ""
                                                        ? streamId
                                                        : "\u2014 not connected \u2014"
                                            valueColor: streamId !== ""
                                                        ? "#1c4ea7" : "#d6b74a"
                                        }
                                    }
                                }

                                // Product row — single, fixed.
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Product stream"
                                        alt: true
                                    }
                                    PGridValue {
                                        Layout.fillWidth: true
                                        alt: true
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
                        }

                        // ── Specifications ──────────────────────────────────
                        PGroupBox {
                            id: specsBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Specifications"
                            contentPadding: 8

                            ColumnLayout {
                                width: specsBox.width - (specsBox.contentPadding * 2) - 2
                                spacing: 6

                                // Inlet count row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Number of inlets"
                                        alt: true
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 22
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#dcd6c8"
                                        }
                                        PSpinner {
                                            id: inletCountSpinner
                                            anchors.left: parent.left
                                            anchors.leftMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 78
                                            from: 2
                                            to: 8
                                            decimals: 0
                                            value: root.appState ? root.appState.inletCount : 2
                                            editable: !!root.appState
                                            onEdited: function(v) {
                                                if (root.appState) root.appState.inletCount = Math.round(v)
                                            }
                                        }
                                    }
                                }

                                // Pressure mode row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Outlet pressure rule"
                                    }
                                    PComboBox {
                                        id: pressureModeCombo
                                        Layout.fillWidth: true
                                        fontSize: 11
                                        model: root.pressureModeLabels
                                        currentIndex: root.pressureModeIndex()
                                        enabled: !!root.appState
                                        onActivated: function(idx) {
                                            if (root.appState && idx >= 0 && idx < root.pressureModeIds.length)
                                                root.appState.pressureMode = root.pressureModeIds[idx]
                                        }
                                        Connections {
                                            target: root.appState
                                            ignoreUnknownSignals: true
                                            function onPressureModeChanged() {
                                                pressureModeCombo.currentIndex = root.pressureModeIndex()
                                            }
                                        }
                                    }
                                }

                                // Pressure mode explainer
                                Text {
                                    Layout.fillWidth: true
                                    text: root.pressureModeExplainer()
                                    font.pixelSize: 10
                                    font.italic: true
                                    color: "#526571"
                                    wrapMode: Text.Wrap
                                }

                                // Specified outlet pressure (only relevant in
                                // "specified" mode; we keep the row visible
                                // but disabled otherwise so the layout
                                // doesn't jump on mode change).
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Specified outlet pressure"
                                        alt: true
                                    }
                                    PGridValue {
                                        Layout.fillWidth: true
                                        alt: true
                                        quantity: "Pressure"
                                        siValue: root.appState ? root.appState.specifiedOutletPressurePa : NaN
                                        displayUnit: root.unitFor("Pressure")
                                        editable: !!root.appState
                                                  && root.appState.pressureMode === "specified"
                                        onEdited: function(siVal) {
                                            if (root.appState) root.appState.specifiedOutletPressurePa = siVal
                                        }
                                    }
                                    PGridUnit {
                                        alt: true
                                        quantity: "Pressure"
                                        siValue: root.appState ? root.appState.specifiedOutletPressurePa : NaN
                                        displayUnit: root.unitFor("Pressure")
                                        onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                    }
                                }

                                // Flash phase mode row
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Flash mode"
                                    }
                                    PComboBox {
                                        id: flashModeCombo
                                        Layout.fillWidth: true
                                        fontSize: 11
                                        model: root.flashPhaseModeLabels
                                        currentIndex: root.flashPhaseModeIndex()
                                        enabled: !!root.appState
                                        onActivated: function(idx) {
                                            if (root.appState && idx >= 0 && idx < root.flashPhaseModeIds.length)
                                                root.appState.flashPhaseMode = root.flashPhaseModeIds[idx]
                                        }
                                        Connections {
                                            target: root.appState
                                            ignoreUnknownSignals: true
                                            function onFlashPhaseModeChanged() {
                                                flashModeCombo.currentIndex = root.flashPhaseModeIndex()
                                            }
                                        }
                                    }
                                }

                                // Flash mode explainer
                                Text {
                                    Layout.fillWidth: true
                                    text: root.flashPhaseExplainer()
                                    font.pixelSize: 10
                                    font.italic: true
                                    color: "#526571"
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ── Tab 1: Results ──────────────────────────────────────────────
            // No ScrollView wrapper — the Diagnostics groupbox uses
            // Layout.fillHeight, which would loop inside an unbounded
            // ScrollView. Same idiom as SplitterView.
            Item {
                anchors.fill: parent
                visible: root.currentTab === 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 10

                    // ── Outlet Conditions ──────────────────────────────────
                    PGroupBox {
                        id: outletCondBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        caption: "Outlet Conditions"
                        contentPadding: 8

                        GridLayout {
                            width: outletCondBox.width - (outletCondBox.contentPadding * 2) - 2
                            columns: 3
                            columnSpacing: 4
                            rowSpacing: 2

                            // Outlet T
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Outlet temperature"
                                alt: true
                            }
                            PGridValue {
                                alt: true
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.solved)
                                          ? root.appState.calcOutletTemperatureK : NaN
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Temperature"
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // Outlet P
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Outlet pressure"
                            }
                            PGridValue {
                                quantity: "Pressure"
                                siValue: (root.appState && root.appState.solved)
                                          ? root.appState.calcOutletPressurePa : NaN
                                displayUnit: root.unitFor("Pressure")
                            }
                            PGridUnit {
                                quantity: "Pressure"
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            // Pressure source label — narrow descriptive
                            // string telling the user where outlet P came
                            // from ("from Inlet 2 (lowest)" etc).
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Pressure source"
                                alt: true
                            }
                            PGridValue {
                                Layout.columnSpan: 2
                                alt: true
                                isText: true
                                alignText: "left"
                                textValue: (root.appState && root.appState.solved
                                             && root.appState.pressureSourceLabel !== "")
                                            ? root.appState.pressureSourceLabel
                                            : "\u2014"
                                valueColor: "#1f2226"
                            }

                            // Outlet mass flow
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Outlet mass flow"
                            }
                            PGridValue {
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.solved)
                                          ? root.appState.calcOutletFlowKgph / 3600.0 : NaN
                                displayUnit: root.unitFor("MassFlow")
                            }
                            PGridUnit {
                                quantity: "MassFlow"
                                displayUnit: root.unitFor("MassFlow")
                                onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                            }

                            // Vapor mole frac
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Vapor fraction (mole)"
                                alt: true
                            }
                            PGridValue {
                                Layout.columnSpan: 2
                                alt: true
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                          ? root.appState.calcOutletVaporMoleFrac : NaN
                                displayUnit: ""
                                decimals: 4
                            }

                            // Vapor mass frac
                            PGridLabel {
                                Layout.preferredWidth: root.labelColWidth
                                text: "Vapor fraction (mass)"
                            }
                            PGridValue {
                                Layout.columnSpan: 2
                                quantity: "Dimensionless"
                                siValue: (root.appState && root.appState.solved)
                                          ? root.appState.calcOutletVaporMassFrac : NaN
                                displayUnit: ""
                                decimals: 4
                            }
                        }
                    }

                    // ── Diagnostics ────────────────────────────────────────
                    PGroupBox {
                        id: diagBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
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

            // ── Tab 2: Thermo Log ───────────────────────────────────────────
            // Identical to SeparatorView's Thermo Log: searchable monospace
            // ListView. Model is appState.runLogModel.
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
                                        placeholderText: "Inlet, [state], ..."
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
