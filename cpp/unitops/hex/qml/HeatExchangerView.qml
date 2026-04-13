import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

// ─────────────────────────────────────────────────────────────────────────────
// HeatExchangerView  —  compact Phase-1 panel
// Width target: 350 px (same as heater/cooler)
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: root
    width:  350
    height: 560

    property var appState: null

    // ── Palette ───────────────────────────────────────────────────────────────
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
    readonly property color hotColor:   "#a73c1c"
    readonly property color coldColor:  "#1c6ea7"
    readonly property color accentColor:"#2a6070"   // teal for HEX title bar

    // ── Metrics ───────────────────────────────────────────────────────────────
    readonly property int headH: 20
    readonly property int rowH:  24
    readonly property int lblW:  148
    readonly property int unitW: 44
    readonly property int fsLbl: 10
    readonly property int fsVal: 10
    readonly property int fsSm:  9

    color: bgOuter

    // ── Helpers ───────────────────────────────────────────────────────────────
    function fmt2(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(2) : "\u2014" }
    function fmt1(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(1) : "\u2014" }
    function fmtPa(p) { const n = Number(p); return isFinite(n) ? Math.round(n).toString() : "\u2014" }
    function fmtK(k)  { const n = Number(k); return isFinite(n) ? n.toFixed(2) : "\u2014" }
    function fmtUA(u) {
        const n = Number(u)
        if (!isFinite(n)) return "\u2014"
        return n >= 1000 ? (n / 1000).toFixed(2) + " kW/K" : n.toFixed(1) + " W/K"
    }
    function connStr(id) { return id !== "" ? id : "\u2014 not connected \u2014" }
    function connColor(id) { return id !== "" ? valueBlue : warnAmber }

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
        property color  accent: root.accentColor
        Layout.fillWidth: true
        height: headH
        color: hdrBg
        border.color: borderIn; border.width: 1
        Rectangle { width: 3; height: parent.height; color: parent.accent }
        Text {
            id: lbl
            anchors.left: parent.left; anchors.leftMargin: 8
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
                left: parent.left; leftMargin: lblW + 6
                right: unitLbl.visible ? unitLbl.left : parent.right; rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: parent.value; font.pixelSize: fsVal; color: parent.vColor
            elide: Text.ElideRight
        }
        Text {
            id: unitLbl
            visible: parent.unit !== ""
            text: parent.unit; width: unitW
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            font.pixelSize: fsSm; color: textMuted
            horizontalAlignment: Text.AlignRight
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: borderIn }
    }

    component FormRow : Item {
        property string label: ""
        property string unit:  ""
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
                left: parent.left; leftMargin: lblW + 6
                right: unitSlot.visible ? unitSlot.left : parent.right; rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            height: rowH - 6
        }
        Text {
            id: unitSlot
            visible: parent.unit !== ""
            text: parent.unit; width: unitW
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
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
            text: "Heat Exchanger" + (appState ? "  \u2014  " + (appState.name || appState.id || "") : "")
            color: "white"; font.pixelSize: 12; font.bold: true
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: pillTxt.implicitWidth + 16; height: 20; radius: 10
            color: (appState && appState.solved) ? "#1a7a3c" : "#3a2a1a"
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
            left: parent.left;    leftMargin: 6
            right: parent.right;  rightMargin: 6
            bottom: bottomBar.top; bottomMargin: 6
        }
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy:   ScrollBar.AsNeeded
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 5

            // ── Connections ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: borderIn; border.width: 1
                implicitHeight: connCol.implicitHeight

                ColumnLayout {
                    id: connCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0

                    SectionHeader { text: "Connections"; accent: accentColor }

                    ValueRow {
                        label: "Hot in"
                        value: appState ? connStr(appState.connectedHotInStreamUnitId) : "\u2014"
                        vColor: appState ? connColor(appState.connectedHotInStreamUnitId) : warnAmber
                    }
                    ValueRow {
                        label: "Hot out"
                        value: appState ? connStr(appState.connectedHotOutStreamUnitId) : "\u2014"
                        vColor: appState ? connColor(appState.connectedHotOutStreamUnitId) : warnAmber
                    }
                    ValueRow {
                        label: "Cold in"
                        value: appState ? connStr(appState.connectedColdInStreamUnitId) : "\u2014"
                        vColor: appState ? connColor(appState.connectedColdInStreamUnitId) : warnAmber
                    }
                    ValueRow {
                        label: "Cold out"
                        value: appState ? connStr(appState.connectedColdOutStreamUnitId) : "\u2014"
                        vColor: appState ? connColor(appState.connectedColdOutStreamUnitId) : warnAmber
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

                    SectionHeader { text: "Specifications"; accent: accentColor }

                    FormRow {
                        label: "Specification"
                        control: ComboBox {
                            anchors.fill: parent
                            model: ["Duty", "Hot outlet T", "Cold outlet T"]
                            currentIndex: {
                                if (!appState) return 0
                                if (appState.specMode === "hotOutletT")  return 1
                                if (appState.specMode === "coldOutletT") return 2
                                return 0
                            }
                            font.pixelSize: fsVal
                            onActivated: {
                                if (!appState) return
                                const modes = ["duty", "hotOutletT", "coldOutletT"]
                                appState.specMode = modes[currentIndex]
                            }
                        }
                    }

                    FormRow {
                        label:   "Duty"
                        unit:    "kW"
                        visible: !appState || appState.specMode === "duty"
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmt2(appState.dutyKW) : ""
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v)) appState.dutyKW = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState) text = fmt2(appState.dutyKW)
                            }
                        }
                    }

                    FormRow {
                        label:   "Hot outlet T"
                        unit:    "K"
                        visible: appState ? appState.specMode === "hotOutletT" : false
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmtK(appState.hotOutletTK) : ""
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v)) appState.hotOutletTK = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState) text = fmtK(appState.hotOutletTK)
                            }
                        }
                    }

                    FormRow {
                        label:   "Cold outlet T"
                        unit:    "K"
                        visible: appState ? appState.specMode === "coldOutletT" : false
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? fmtK(appState.coldOutletTK) : ""
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v)) appState.coldOutletTK = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState) text = fmtK(appState.coldOutletTK)
                            }
                        }
                    }

                    FormRow {
                        label:   "Hot-side \u0394P"
                        unit:    "Pa"
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? Math.round(appState.hotSidePressureDropPa).toString() : "0"
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v)) appState.hotSidePressureDropPa = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState)
                                    text = Math.round(appState.hotSidePressureDropPa).toString()
                            }
                        }
                    }

                    FormRow {
                        label:   "Cold-side \u0394P"
                        unit:    "Pa"
                        control: TextField {
                            anchors.fill: parent; font.pixelSize: fsVal
                            text: appState ? Math.round(appState.coldSidePressureDropPa).toString() : "0"
                            onEditingFinished: {
                                const v = parseFloat(text)
                                if (appState && isFinite(v)) appState.coldSidePressureDropPa = v
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && appState)
                                    text = Math.round(appState.coldSidePressureDropPa).toString()
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

                    SectionHeader { text: "Results"; accent: accentColor }

                    // Duty row — coloured by side that was specified
                    ValueRow {
                        label:  "Duty"
                        unit:   "kW"
                        value:  (appState && appState.solved) ? fmt2(appState.calcDutyKW) : "\u2014"
                        vColor: (appState && appState.solved) ? accentColor : textMuted
                    }

                    // Hot side
                    ValueRow {
                        label: "Hot outlet T"
                        unit:  "K"
                        value: (appState && appState.solved) ? fmtK(appState.calcHotOutTK) : "\u2014"
                        vColor: hotColor
                    }
                    ValueRow {
                        label: "Hot outlet VF"
                        unit:  ""
                        value: (appState && appState.solved) ? fmt2(appState.calcHotOutVapFrac) : "\u2014"
                        vColor: hotColor
                    }

                    // Cold side
                    ValueRow {
                        label: "Cold outlet T"
                        unit:  "K"
                        value: (appState && appState.solved) ? fmtK(appState.calcColdOutTK) : "\u2014"
                        vColor: coldColor
                    }
                    ValueRow {
                        label: "Cold outlet VF"
                        unit:  ""
                        value: (appState && appState.solved) ? fmt2(appState.calcColdOutVapFrac) : "\u2014"
                        vColor: coldColor
                    }

                    // Exchanger performance
                    ValueRow {
                        label: "LMTD"
                        unit:  "K"
                        value: (appState && appState.solved) ? fmt1(appState.calcLMTD) : "\u2014"
                    }
                    ValueRow {
                        label: "UA"
                        unit:  ""
                        value: (appState && appState.solved) ? fmtUA(appState.calcUA) : "\u2014"
                    }
                    ValueRow {
                        label: "Approach \u0394T"
                        unit:  "K"
                        value: (appState && appState.solved) ? fmt1(appState.calcApproachT) : "\u2014"
                        vColor: {
                            if (!appState || !appState.solved) return textMuted
                            return appState.calcApproachT < 5 ? errorRed : valueBlue
                        }
                    }
                }
            }

            // ── Error ─────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: frameInner; border.color: errorRed; border.width: 1
                height: errTxt.implicitHeight + 10
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
                color: solveMA.containsMouse ? Qt.lighter(accentColor, 1.2) : accentColor
                Text { anchors.centerIn: parent; text: "\u25b6  Solve"
                       color: "white"; font.pixelSize: 11; font.bold: true }
                MouseArea {
                    id: solveMA; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: if (appState) appState.solve()
                }
            }

            Rectangle {
                width: 70; height: 28; radius: 4
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
