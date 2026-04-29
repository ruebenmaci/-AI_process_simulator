import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  SplitterView — Tee / Stream Splitter (HYSYS "Tee" / Aspen Plus "FSplit").
//  Same overall skeleton as SeparatorView: PPropertyView with status chip,
//  Solve/Reset action bar. Splitter-specific differences:
//
//    Two tabs only — Design and Results. No Thermo Log, because the splitter
//    performs no flash and has no thermo trace to record.
//
//    Connections (Design tab): one feed row + N outlet rows. The outlet rows
//    are rendered by a fixed-height ListView bound to
//    appState.connectedOutletStreamUnitIds. The list reserves vertical space
//    for `outletVisibleRows` rows (default 3) regardless of the live outlet
//    count, scrolling when more outlets are present. This keeps the
//    surrounding controls anchored as outletCount changes.
//
//    Specifications (Design tab): outletCount PSpinner (range 2–8), then a
//    fixed-height ListView (same `outletListHeight`) where each row has
//    "Outlet i" label + editable fraction PGridValue. Below the list: live
//    "Total: X.XXX" display that turns red when not balanced, plus two
//    buttons:
//      Normalize   → scales existing fractions so sum = 1.0 (preserves split)
//      Even Split  → resets every fraction to 1/N (discards split)
//
//    Conditions: pressure drop only.
//
//  Results tab shows outlet conditions (T, P) and per-outlet calculated mass
//  flows in a fixed-height ListView (same idiom), followed by Diagnostics.
//  No Vessel Conditions group (no thermo).
//
//  AOT-safe rules: no for...of, no arrow functions, no const, no fractional
//  font.pixelSize, no `this` in Repeater/ListView delegate signal handlers.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0

    implicitWidth:  465
    implicitHeight: 620

    // ── Visual constants ─────────────────────────────────────────────────────
    readonly property url iconPath: (typeof gAppTheme !== "undefined")
                                    ? Qt.resolvedUrl(gAppTheme.paletteSvgIconPath("tee_splitter"))
                                    : ""

    readonly property int labelColWidth: 180

    // Variable-N row tuning. The Connections "outlets" list and the
    // Specifications "outlet flow fractions" list both reserve a fixed
    // amount of vertical space equivalent to N rows. When the live outlet
    // count exceeds N, the lists scroll instead of pushing the surrounding
    // controls down. This keeps the "Number of outlets" spinner and the
    // "Total / Normalize / Even Split" row anchored to stable positions
    // even as outletCount changes.
    readonly property int outletRowHeight:    22
    readonly property int outletVisibleRows:  3
    readonly property int outletListHeight:
        outletRowHeight * outletVisibleRows
        + Math.max(0, outletVisibleRows - 1) * 2  // matches list spacing

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

    // ── Status chip helpers (same convention as SeparatorView) ──────────────
    //   0 = None  (neutral gray)
    //   1 = Ok    (green)
    //   2 = Warn  (yellow — uses dark text for legibility on yellow bg)
    //   3 = Fail  (red)
    //   4 = Solving (blue — reserved)
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

    // ── Tabs definition (no Thermo Log — no flash to log) ────────────────────
    readonly property var tabsModel: [
        { text: "Design"  },
        { text: "Results" }
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

                                // Feed row — fixed; not in the Repeater.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Feed stream"
                                        alt: true
                                    }
                                    PGridValue {
                                        Layout.fillWidth: true
                                        alt: true
                                        isText: true
                                        alignText: "left"
                                        textValue: (root.appState && root.appState.connectedFeedStreamUnitId !== "")
                                                    ? root.appState.connectedFeedStreamUnitId
                                                    : "\u2014 not connected \u2014"
                                        valueColor: (root.appState && root.appState.connectedFeedStreamUnitId !== "")
                                                    ? "#1c4ea7" : "#d6b74a"
                                    }
                                }

                                // Outlet rows — variable count, driven by the
                                // appState.connectedOutletStreamUnitIds list.
                                // Wrapped in a ListView so the groupbox keeps
                                // a fixed height (3 rows) regardless of the
                                // live outlet count; scrollbar appears when
                                // outletCount > outletVisibleRows.
                                ListView {
                                    id: connOutletList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.outletListHeight
                                    Layout.minimumHeight:   root.outletListHeight
                                    Layout.maximumHeight:   root.outletListHeight
                                    clip: true
                                    spacing: 2
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: count > root.outletVisibleRows
                                    model: root.appState ? root.appState.connectedOutletStreamUnitIds : []
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: RowLayout {
                                        property int outletIdx: index
                                        property string streamId: modelData
                                        width: connOutletList.width
                                        height: root.outletRowHeight
                                        spacing: 4

                                        PGridLabel {
                                            Layout.preferredWidth: root.labelColWidth
                                            text: "Outlet " + (outletIdx + 1)
                                            alt: (outletIdx % 2 === 0) ? false : true
                                        }
                                        PGridValue {
                                            Layout.fillWidth: true
                                            alt: (outletIdx % 2 === 0) ? false : true
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

                                // Outlet count row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Number of outlets"
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
                                            id: outletCountSpinner
                                            anchors.left: parent.left
                                            anchors.leftMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 78
                                            from: 2
                                            to: 8
                                            decimals: 0
                                            value: root.appState ? root.appState.outletCount : 2
                                            editable: !!root.appState
                                            onEdited: function(v) {
                                                if (root.appState) root.appState.outletCount = Math.round(v)
                                            }
                                        }
                                    }
                                }

                                // Header for the per-outlet fractions table
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Outlet flow fractions"
                                        alt: true
                                        bold: true
                                    }
                                    Item { Layout.fillWidth: true; Layout.preferredHeight: 18 }
                                }

                                // Fraction body rows — one per outlet,
                                // generated by the ListView. Each row carries
                                // its index via the model `index` so the
                                // edit handler can target the correct outlet.
                                // Wrapped in a ListView so the groupbox keeps
                                // a fixed height regardless of the live outlet
                                // count; the "Total / Normalize / Even Split"
                                // row stays at a stable position.
                                ListView {
                                    id: fractionList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.outletListHeight
                                    Layout.minimumHeight:   root.outletListHeight
                                    Layout.maximumHeight:   root.outletListHeight
                                    clip: true
                                    spacing: 2
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: count > root.outletVisibleRows
                                    model: root.appState ? root.appState.outletFractions : []
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: RowLayout {
                                        property int  fracIdx: index
                                        property real fracVal: Number(modelData)
                                        width: fractionList.width
                                        height: root.outletRowHeight
                                        spacing: 4

                                        PGridLabel {
                                            Layout.preferredWidth: root.labelColWidth
                                            text: "    Outlet " + (fracIdx + 1)
                                            alt: (fracIdx % 2 === 0) ? false : true
                                        }
                                        PGridValue {
                                            Layout.fillWidth: true
                                            alt: (fracIdx % 2 === 0) ? false : true
                                            quantity: "Dimensionless"
                                            siValue: fracVal
                                            displayUnit: ""
                                            decimals: 4
                                            editable: !!root.appState
                                            onEdited: function(siVal) {
                                                if (root.appState)
                                                    root.appState.setOutletFraction(fracIdx, siVal)
                                            }
                                        }
                                    }
                                }

                                // Sum + buttons row. The sum colours red
                                // when out of tolerance so the user gets
                                // continuous live feedback as they type.
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 6

                                    Label {
                                        text: "Total:"
                                        font.pixelSize: 11
                                        color: "#3b4651"
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        id: sumLabel
                                        text: root.appState
                                              ? Number(root.appState.outletFractionSum).toFixed(4)
                                              : "0.0000"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: (root.appState && root.appState.outletFractionsBalanced)
                                                ? "#1f9c5b"
                                                : "#c63e3e"
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Item { Layout.fillWidth: true } // spacer

                                    PButton {
                                        text: "Normalize"
                                        enabled: !!root.appState
                                        onClicked: { if (root.appState) root.appState.normalizeFractions() }
                                    }
                                    PButton {
                                        text: "Even Split"
                                        enabled: !!root.appState
                                        onClicked: { if (root.appState) root.appState.distributeFractionsEvenly() }
                                    }
                                }
                            }
                        }

                        // ── Conditions ──────────────────────────────────────
                        PGroupBox {
                            id: condBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Conditions"
                            contentPadding: 8

                            RowLayout {
                                width: condBox.width - (condBox.contentPadding * 2) - 2
                                spacing: 4

                                PGridLabel {
                                    Layout.preferredWidth: root.labelColWidth
                                    text: "Pressure drop"
                                    alt: true
                                }
                                PGridValue {
                                    Layout.fillWidth: true
                                    alt: true
                                    quantity: "Pressure"
                                    siValue: root.appState ? root.appState.pressureDropPa : NaN
                                    displayUnit: root.unitFor("Pressure")
                                    editable: !!root.appState
                                    onEdited: function(siVal) {
                                        if (root.appState) root.appState.pressureDropPa = siVal
                                    }
                                }
                                PGridUnit {
                                    alt: true
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

            // ── Tab 1: Results ──────────────────────────────────────────────
            // Note: no ScrollView wrapper here. The Results tab's bottom
            // groupbox (Diagnostics) uses Layout.fillHeight: true, which
            // would create an unsolvable polish loop inside a scroll
            // container (ScrollView's content height is unbounded, so
            // "fill" has no target). The separator view follows the same
            // pattern.
            Item {
                anchors.fill: parent
                visible: root.currentTab === 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 10

                    // ── Outlet Conditions (T, P) ───────────────────────
                    // Splitter is isothermal and (uniform) isobaric on
                    // every outlet, so a single (T, P) pair tells the
                    // user everything they need about the outlet state.
                    PGroupBox {
                        id: outletCondBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        caption: "Outlet Conditions (all outlets)"
                        contentPadding: 8

                        GridLayout {
                            width: outletCondBox.width - (outletCondBox.contentPadding * 2) - 2
                            columns: 3
                            columnSpacing: 4
                            rowSpacing: 2

                                // Outlet T row — populated from the feed
                                // stream's T during solve() (splitter is
                                // isothermal — no flash performed).
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

                                // Outlet P row
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
                            }
                        }

                        // ── Per-outlet flows ───────────────────────────────
                        PGroupBox {
                            id: outletFlowsBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "Outlet Mass Flows"
                            contentPadding: 8

                            ColumnLayout {
                                width: outletFlowsBox.width - (outletFlowsBox.contentPadding * 2) - 2
                                spacing: 2

                                // Header row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    PGridLabel {
                                        Layout.preferredWidth: root.labelColWidth
                                        text: "Outlet"
                                        alt: true
                                        bold: true
                                    }
                                    PGridLabel {
                                        Layout.fillWidth: true
                                        text: "Mass flow"
                                        alt: true
                                        bold: true
                                    }
                                }

                                // Body rows — ListView over the
                                // calcOutletFlowsKgph projection. Wrapped in
                                // a fixed-height ListView so the groupbox
                                // doesn't grow as outletCount changes; the
                                // Diagnostics groupbox below retains a
                                // stable starting position.
                                ListView {
                                    id: flowList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.outletListHeight
                                    Layout.minimumHeight:   root.outletListHeight
                                    Layout.maximumHeight:   root.outletListHeight
                                    clip: true
                                    spacing: 2
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: count > root.outletVisibleRows
                                    model: root.appState ? root.appState.calcOutletFlowsKgph : []
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: RowLayout {
                                        property int  flowIdx: index
                                        property real flowKgph: Number(modelData)
                                        width: flowList.width
                                        height: root.outletRowHeight
                                        spacing: 4

                                        PGridLabel {
                                            Layout.preferredWidth: root.labelColWidth
                                            text: "Outlet " + (flowIdx + 1)
                                            alt: (flowIdx % 2 === 0) ? false : true
                                        }
                                        // We display kg/h directly without a
                                        // PGridValue/PGridUnit pair because
                                        // the value is read-only and there's
                                        // a header row already establishing
                                        // the units. Keeping it as a Label
                                        // also avoids the extra width the
                                        // PGridUnit picker eats.
                                        Label {
                                            Layout.fillWidth: true
                                            text: (root.appState && root.appState.solved)
                                                  ? flowKgph.toFixed(2) + " kg/h"
                                                  : "\u2014"
                                            font.pixelSize: 11
                                            color: "#1f2226"
                                            verticalAlignment: Text.AlignVCenter
                                            background: Rectangle {
                                                color: (flowIdx % 2 === 0) ? "#f4f6f9" : "#ebeef2"
                                            }
                                            leftPadding: 4
                                            rightPadding: 4
                                        }
                                    }
                                }
                            }
                        }

                        // ── Diagnostics ────────────────────────────────────
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
