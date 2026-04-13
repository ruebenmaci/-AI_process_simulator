import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

// ─────────────────────────────────────────────────────────────────────────────
// HeaterCoolerView  —  single-column full-width layout
// Shared by "heater" and "cooler"; accent colour and labels adapt to type.
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: root
    width:  640
    height: 560

    property var appState: null

    // ── Colour palette ────────────────────────────────────────────────────────
    readonly property color bgOuter:    "#d8dde2"
    readonly property color cmdBar:     "#c8d0d8"
    readonly property color frameInner: "#e8ebef"
    readonly property color hdrBg:      "#c8d0d8"
    readonly property color borderOut:  "#6d7883"
    readonly property color borderIn:   "#97a2ad"
    readonly property color textMain:   "#1f2a34"
    readonly property color textMuted:  "#526571"
    readonly property color valueBlue:  "#1c4ea7"
    readonly property color warnAmber:  "#d6b74a"
    readonly property color errorRed:   "#b23b3b"
    readonly property color okGreen:    "#1a7a3c"

    readonly property bool  isCoolerType: appState && appState.type === "cooler"
    readonly property color accentColor:  isCoolerType ? "#1c6ea7" : "#a73c1c"

    // ── Metrics ───────────────────────────────────────────────────────────────
    readonly property int headH: 20
    readonly property int rowH:  24
    readonly property int lblW:  160
    readonly property int unitW: 48
    readonly property int fsLbl: 10
    readonly property int fsVal: 10
    readonly property int fsSm:  9

    color: bgOuter

    // ── Helpers ───────────────────────────────────────────────────────────────
    function fmt2(x)   { const n = Number(x); return isFinite(n) ? n.toFixed(2) : "\u2014" }
    function fmtPa(p)  { const n = Number(p); return isFinite(n) ? Math.round(n).toString() : "\u2014" }
    function fmtK(k)   { const n = Number(k); return isFinite(n) ? n.toFixed(2) : "\u2014" }
    function unitLabel()  { return isCoolerType ? "Cooler" : "Heater" }
    function dutyLabel()  { return isCoolerType ? "Cooling duty" : "Heating duty" }
    function solveStatusText() {
        if (!appState)           return "\u2014"
        if (appState.solved)     return "Solved  \u2713"
        if (appState.solveStatus && appState.solveStatus !== "") return appState.solveStatus
        return "Not solved"
    }
    function solveStatusColor() {
        if (!appState)       return textMuted
        if (appState.solved) return okGreen
        return errorRed
    }

    // ── Inline components ─────────────────────────────────────────────────────

    component SectionHeader : Rectangle {
        property alias text: lbl.text
        Layout.fillWidth: true
        height: headH
        color: hdrBg
        border.color: borderIn; border.width: 1
        Text {
            id: lbl
            anchors.left: parent.left; anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: fsLbl; font.bold: true; color: textMain
        }
    }

    component ValueRow : Item {
        property string label:  ""
        property string value:  "\u2014"
        property string unit:   ""
        property color  vColor: valueBlue
        Layout.fillWidth: true
        height: rowH
        Text {
            x: 6; width: lblW
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label; font.pixelSize: fsLbl; color: textMuted
            elide: Text.ElideRight
        }
        Text {
            anchors {
                left: parent.left; leftMargin: lblW + 8
                right: unitLbl.visible ? unitLbl.left : parent.right; rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: parent.value; font.pixelSize: fsVal; color: parent.vColor
        }
        Text {
            id: unitLbl
            visible: parent.unit !== ""
            text: parent.unit; width: unitW
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            font.pixelSize: fsSm; color: textMuted
            horizontalAlignment: Text.AlignRight
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: borderIn }
    }

    component FormRow : Item {
        property string label:  ""
        property string unit:   ""
        property alias  control: slot.data
        Layout.fillWidth: true
        height: rowH
        Text {
            x: 6; width: lblW
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label; font.pixelSize: fsLbl; color: textMuted
            elide: Text.ElideRight
        }
        Item {
            id: slot
            anchors {
                left: parent.left; leftMargin: lblW + 8
                right: unitSlot.visible ? unitSlot.left : parent.right; rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            height: rowH - 6
        }
        Text {
            id: unitSlot
            visible: parent.unit !== ""
            text: parent.unit; width: unitW
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            font.pixelSize: fsSm; color: textMuted
            horizontalAlignment: Text.AlignRight
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: borderIn }
    }

    // ── Title bar ─────────────────────────────────────────────────────────────
    Rectangle {
        id: titleBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 32; color: accentColor

        Text {
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: unitLabel() + (appState ? "  \u2014  " + (appState.name || appState.id || "") : "")
            color: "white"; font.pixelSize: 12; font.bold: true
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: pillTxt.implicitWidth + 16; height: 20; radius: 10
            color: (appState && appState.solved) ? "#1a7a3c" : "#5a2a1a"
            Text {
                id: pillTxt
                anchors.centerIn: parent
                text: solveStatusText()
                color: "white"; font.pixelSize: 9
            }
        }
    }

    // ── Scrollable body ───────────────────────────────────────────────────────
    ScrollView {
        anchors {
            top: titleBar.bottom; topMargin: 6
            left: parent.left;    leftMargin: 8
            right: parent.right;  rightMargin: 8
            bottom: bottomBar.top; bottomMargin: 6
        }
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy:   ScrollBar.AsNeeded

        // Must set this so ColumnLayout children get a real width
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 6

            // ── Connections ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: borderIn; border.width: 1
                implicitHeight: connCol.implicitHeight

                ColumnLayout {
                    id: connCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0

                    SectionHeader { text: "Connections" }

                    ValueRow {
                        label:  "Feed stream"
                        value:  (appState && appState.connectedFeedStreamUnitId !== "")
                                ? appState.connectedFeedStreamUnitId : "\u2014 not connected \u2014"
                        vColor: (appState && appState.connectedFeedStreamUnitId !== "")
                                ? valueBlue : warnAmber
                    }
                    ValueRow {
                        label:  "Product stream"
                        value:  (appState && appState.connectedProductStreamUnitId !== "")
                                ? appState.connectedProductStreamUnitId : "\u2014 not connected \u2014"
                        vColor: (appState && appState.connectedProductStreamUnitId !== "")
                                ? valueBlue : warnAmber
                    }
                    ValueRow {
                        label:  "Energy stream (out)"
                        value:  (appState && appState.connectedEnergyOutStreamUnitId !== "")
                                ? appState.connectedEnergyOutStreamUnitId : "\u2014 not connected \u2014"
                        vColor: (appState && appState.connectedEnergyOutStreamUnitId !== "")
                                ? valueBlue : textMuted
                    }
                }
            }

            // ── Specifications ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: borderIn; border.width: 1
                implicitHeight: specCol.implicitHeight

                ColumnLayout {
                    id: specCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0

                    SectionHeader { text: "Specifications" }

                    FormRow {
                        label: "Specification"
                        control: ComboBox {
                            anchors.fill: parent
                            model: ["Temperature", "Duty", "Vapor fraction"]
                            currentIndex: {
                                if (!appState) return 0
                                if (appState.specMode === "duty")          return 1
                                if (appState.specMode === "vaporFraction") return 2
                                return 0
                            }
                            font.pixelSize: fsVal
                            onActivated: {
                                if (!appState) return
                                const modes = ["temperature", "duty", "vaporFraction"]
                                appState.specMode = modes[currentIndex]
                            }
                        }
                    }

                    FormRow {
                        label:   "Outlet temperature"
                        unit:    "K"
                        visible: !appState || appState.specMode === "temperature"
                        control: TextField {
                            id: outletTempField
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmtK(appState.outletTemperatureK) : ""
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v))
                                    appState.outletTemperatureK = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState)
                                    text = fmtK(appState.outletTemperatureK)
                            }
                        }
                    }

                    FormRow {
                        label:   dutyLabel()
                        unit:    "kW"
                        visible: appState ? (appState.specMode === "duty") : false
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmt2(Math.abs(appState.dutyKW)) : ""
                            onEditingFinished: {
                                if (!appState) return
                                const mag = parseFloat(text)
                                appState.dutyKW = isCoolerType ? -Math.abs(mag) : Math.abs(mag)
                            }
                        }
                    }

                    FormRow {
                        label:   "Outlet vapor fraction"
                        unit:    "\u2014"
                        visible: appState ? (appState.specMode === "vaporFraction") : false
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmt2(appState.outletVaporFraction) : ""
                            onEditingFinished: {
                                if (appState) appState.outletVaporFraction = parseFloat(text)
                            }
                        }
                    }

                    FormRow {
                        label:   "Pressure drop"
                        unit:    "Pa"
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? Math.round(appState.pressureDropPa).toString() : ""
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v))
                                    appState.pressureDropPa = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState)
                                    text = Math.round(appState.pressureDropPa).toString()
                            }
                        }
                    }
                }
            }

            // ── Calculated results ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: borderIn; border.width: 1
                implicitHeight: resultsCol.implicitHeight

                ColumnLayout {
                    id: resultsCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0

                    SectionHeader { text: "Calculated results" }

                    ValueRow {
                        label:  dutyLabel()
                        unit:   "kW"
                        value:  (appState && appState.solved) ? fmt2(Math.abs(appState.calcDutyKW)) : "\u2014"
                        vColor: (appState && appState.solved)
                                ? (appState.isCooling ? "#1c6ea7" : "#a73c1c")
                                : textMuted
                    }
                    ValueRow {
                        label: "Outlet temperature"
                        unit:  "K"
                        value: (appState && appState.solved) ? fmtK(appState.calcOutletTempK) : "\u2014"
                    }
                    ValueRow {
                        label: "Outlet pressure"
                        unit:  "Pa"
                        value: (appState && appState.solved) ? fmtPa(appState.calcOutletPressurePa) : "\u2014"
                    }
                    ValueRow {
                        label: "Outlet vapor fraction"
                        unit:  "\u2014"
                        value: (appState && appState.solved) ? fmt2(appState.calcOutletVapFrac) : "\u2014"
                    }

                    Item {
                        Layout.fillWidth: true
                        height: rowH + 4
                        visible: appState ? appState.solved : false
                        Text {
                            anchors.centerIn: parent
                            text: (appState && appState.isCooling)
                                  ? "\u25bc  Heat removed from process stream"
                                  : "\u25b2  Heat added to process stream"
                            color: (appState && appState.isCooling) ? "#1c6ea7" : "#a73c1c"
                            font.pixelSize: fsLbl; font.bold: true
                        }
                    }
                }
            }

            // ── Error message (only when not solved and status is set) ─────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: errorRed; border.width: 1
                height: errTxt.implicitHeight + 12
                visible: appState ? (!appState.solved && appState.solveStatus !== "") : false

                Text {
                    id: errTxt
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    text: appState ? appState.solveStatus : ""
                    font.pixelSize: fsSm; color: errorRed
                    wrapMode: Text.WordWrap
                }
            }

            Item { Layout.fillWidth: true; height: 4 }
        }
    }

    // ── Bottom action bar ─────────────────────────────────────────────────────
    Rectangle {
        id: bottomBar
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 40; color: cmdBar
        border.color: borderOut; border.width: 1

        RowLayout {
            anchors.fill: parent; anchors.margins: 6; spacing: 8

            Rectangle {
                width: 100; height: 28; radius: 4
                color: solveMA.containsMouse ? Qt.lighter(accentColor, 1.15) : accentColor
                Text { anchors.centerIn: parent; text: "\u25b6  Solve"
                       color: "white"; font.pixelSize: 11; font.bold: true }
                MouseArea {
                    id: solveMA; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: if (appState) appState.solve()
                }
            }

            Rectangle {
                width: 80; height: 28; radius: 4
                color: resetMA.containsMouse ? "#b0bac5" : "#97a2ad"
                Text { anchors.centerIn: parent; text: "Reset"
                       color: textMain; font.pixelSize: 11 }
                MouseArea {
                    id: resetMA; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: if (appState) appState.reset()
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: solveStatusText()
                color: solveStatusColor()
                font.pixelSize: 10
                font.bold: appState ? appState.solved : false
            }
        }
    }
}
