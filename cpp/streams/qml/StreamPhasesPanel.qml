import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property var streamObject: null
    property var unitObject: null

    readonly property color bg:        "#f4f6fa"
    readonly property color chrome:    "#d2d9e6"
    readonly property color rowEven:   "#eef2f8"
    readonly property color rowOdd:    "#f4f6fa"
    readonly property color borderCol: "#b0b8c8"
    readonly property color textDark:  "#1f2430"
    readonly property color mutedText: "#5a6472"
    readonly property color calcColor: "#1c4ea7"
    readonly property color dashColor: "#aaaaaa"
    readonly property color liqHdr:    "#dbeafe"
    readonly property color vapHdr:    "#fef9c3"
    readonly property color warnBg:    "#fff4db"
    readonly property color warnText:  "#744f00"

    readonly property int lw:   160
    readonly property int rh:   26
    readonly property int lpad: 10

    function fmt(v, dec) {
        if (v === undefined || v === null) return "—"
        const n = Number(v)
        if (isNaN(n) || !isFinite(n)) return "—"
        return n.toFixed(dec !== undefined ? dec : 3)
    }
    function fmtTK(K) {
        if (!K || !isFinite(K) || K <= 0) return "—"
        return fmt(K - 273.15, 1) + " °C   (" + fmt(K, 1) + " K)"
    }
    function has() { return !!root.streamObject }

    readonly property real massFlow:  has() ? root.streamObject.flowRateKgph        : 0
    readonly property real molarFlow: has() ? root.streamObject.molarFlowKmolph      : 0
    readonly property real volFlow:   has() ? root.streamObject.volumetricFlowM3ph   : 0
    readonly property real vf:        has() ? root.streamObject.vaporFraction         : 0
    readonly property real lf:        1.0 - vf
    readonly property string phase:   has() ? root.streamObject.phaseStatus           : "—"
    readonly property string thermoR: has() ? root.streamObject.thermoRegionLabel     : "—"
    readonly property real bpK:       has() ? root.streamObject.bubblePointEstimateK  : 0
    readonly property real dpK:       has() ? root.streamObject.dewPointEstimateK     : 0

    // Comparison table rows — computed from streamObject so they react to flash results.
    // Returns an array of { label, liq, vap, unit } objects.
    function buildCompRows() {
        if (!root.has()) {
            return [
                { label: "Density",              liq: "—", vap: "—", unit: "kg/m³"   },
                { label: "Viscosity",            liq: "—", vap: "—", unit: "cP"       },
                { label: "Thermal conductivity", liq: "—", vap: "—", unit: "W/m·K"   },
                { label: "Heat capacity Cp",     liq: "—", vap: "—", unit: "kJ/kg·K" },
                { label: "Enthalpy",             liq: "—", vap: "—", unit: "kJ/kg"   },
                { label: "Entropy",              liq: "—", vap: "—", unit: "kJ/kg·K" },
                { label: "Surface tension",      liq: "—", vap: "—", unit: "N/m"     },
            ]
        }
        const s = root.streamObject
        return [
            { label: "Density",              liq: fmt(s.liquidDensityKgM3,    2), vap: fmt(s.vapourDensityKgM3,    2), unit: "kg/m³"   },
            { label: "Viscosity",            liq: fmt(s.liquidViscosityCp,    4), vap: fmt(s.vapourViscosityCp,    4), unit: "cP"       },
            { label: "Thermal conductivity", liq: fmt(s.liquidThermalCondWmK, 4), vap: fmt(s.vapourThermalCondWmK, 4), unit: "W/m·K"   },
            { label: "Heat capacity Cp",     liq: fmt(s.liquidCpKJkgK,        3), vap: fmt(s.vapourCpKJkgK,        3), unit: "kJ/kg·K" },
            { label: "Enthalpy",             liq: fmt(s.liquidEnthalpyKJkg,   2), vap: fmt(s.vapourEnthalpyKJkg,   2), unit: "kJ/kg"   },
            { label: "Entropy",              liq: fmt(s.liquidEntropyKJkgK,   4), vap: fmt(s.vapourEntropyKJkgK,   4), unit: "kJ/kg·K" },
            { label: "Surface tension",      liq: fmt(s.surfaceTensionNm,     5), vap: "—",                            unit: "N/m"     },
        ]
    }

    // Reactive array — rebuilt whenever the stream's derived conditions change.
    property var compRows: []

    function refreshCompRows() { compRows = buildCompRows() }

    onStreamObjectChanged: Qt.callLater(refreshCompRows)
    Component.onCompleted:  Qt.callLater(refreshCompRows)
    Connections {
        target: root.streamObject
        function onDerivedConditionsChanged() { Qt.callLater(refreshCompRows) }
        ignoreUnknownSignals: true
    }

    // ── UI ──────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.bg
        radius: 8
        border.color: "#2a2a2a"
        border.width: 1

        Label {
            anchors.centerIn: parent
            visible: !root.has()
            text: "No stream selected."
            color: root.mutedText
            font.pixelSize: 12
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 6
            visible: root.has()
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy:   ScrollBar.AsNeeded

            Column {
                width: Math.max(parent.width, 500)
                spacing: 6

                // ── Phase status banner ──────────────────────────
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 6
                    color: {
                        if (root.phase === "Liquid")    return "#dbeafe"
                        if (root.phase === "Vapor")     return "#fef9c3"
                        if (root.phase === "Two-Phase") return "#dcfce7"
                        return "#f3f4f6"
                    }
                    border.color: "#9ca3af"
                    border.width: 1

                    Label {
                        x: 12; width: parent.width - 24; height: parent.height
                        text: "Phase:  " + root.phase
                              + "     |     Vapour fraction:  " + fmt(root.vf, 4)
                              + "     |     " + root.thermoR
                        font.pixelSize: 11; font.bold: true
                        color: root.textDark
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                // ── Side-by-side phase cards ─────────────────────
                Item {
                    width: parent.width
                    height: cardH
                    readonly property int cardH: 28 + 6 * root.rh

                    // ── Liquid card ──────────────────────────────
                    Rectangle {
                        id: liqCard
                        x: 0; y: 0
                        width: Math.floor((parent.width - 8) / 2)
                        height: parent.height
                        radius: 6
                        color: root.bg
                        border.color: root.borderCol
                        border.width: 1
                        opacity: root.lf > 0.0001 ? 1.0 : 0.4

                        // Header
                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: 26
                            color: root.liqHdr
                            topLeftRadius: 5; topRightRadius: 5
                            Label {
                                x: 8; width: parent.width - 16; height: parent.height
                                text: "Liquid phase   (" + fmt(root.lf * 100, 1) + " %)"
                                font.pixelSize: 11; font.bold: true
                                color: root.textDark; verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Rows
                        Repeater {
                            model: [
                                ["Mass flow",  fmt(root.massFlow  * root.lf, 1) + " kg/h"],
                                ["Molar flow", fmt(root.molarFlow * root.lf, 3) + " kmol/h"],
                                ["Vol. flow",  fmt(root.volFlow   * root.lf, 3) + " m³/h"],
                                ["Density",    has() ? fmt(root.streamObject.liquidDensityKgM3,  2) + " kg/m³" : "—"],
                                ["Viscosity",  has() ? fmt(root.streamObject.liquidViscosityCp,  4) + " cP"    : "—"],
                                ["Enthalpy",   has() ? fmt(root.streamObject.liquidEnthalpyKJkg, 2) + " kJ/kg" : "—"],
                            ]
                            Rectangle {
                                x: 1; y: 28 + index * root.rh
                                width: liqCard.width - 2; height: root.rh
                                color: index % 2 === 0 ? root.rowEven : root.rowOdd
                                border.color: root.borderCol; border.width: 1
                                Label {
                                    x: root.lpad; width: 90; height: parent.height
                                    text: modelData[0]; color: root.mutedText
                                    font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                }
                                Label {
                                    x: 100; width: parent.width - 104; height: parent.height
                                    text: modelData[1]
                                    color: modelData[1] === "—" ? root.dashColor : root.calcColor
                                    font.pixelSize: 10
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // ── Vapour card ──────────────────────────────
                    Rectangle {
                        id: vapCard
                        x: Math.floor((parent.width - 8) / 2) + 8
                        y: 0
                        width: Math.floor((parent.width - 8) / 2)
                        height: parent.height
                        radius: 6
                        color: root.bg
                        border.color: root.borderCol
                        border.width: 1
                        opacity: root.vf > 0.0001 ? 1.0 : 0.4

                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: 26
                            color: root.vapHdr
                            topLeftRadius: 5; topRightRadius: 5
                            Label {
                                x: 8; width: parent.width - 16; height: parent.height
                                text: "Vapour phase   (" + fmt(root.vf * 100, 1) + " %)"
                                font.pixelSize: 11; font.bold: true
                                color: root.textDark; verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Repeater {
                            model: [
                                ["Mass flow",  fmt(root.massFlow  * root.vf, 1) + " kg/h"],
                                ["Molar flow", fmt(root.molarFlow * root.vf, 3) + " kmol/h"],
                                ["Vol. flow",  fmt(root.volFlow   * root.vf, 3) + " m³/h"],
                                ["Density",    has() ? fmt(root.streamObject.vapourDensityKgM3,  2) + " kg/m³" : "—"],
                                ["Viscosity",  has() ? fmt(root.streamObject.vapourViscosityCp,  4) + " cP"    : "—"],
                                ["Enthalpy",   has() ? fmt(root.streamObject.vapourEnthalpyKJkg, 2) + " kJ/kg" : "—"],
                            ]
                            Rectangle {
                                x: 1; y: 28 + index * root.rh
                                width: vapCard.width - 2; height: root.rh
                                color: index % 2 === 0 ? root.rowEven : root.rowOdd
                                border.color: root.borderCol; border.width: 1
                                Label {
                                    x: root.lpad; width: 90; height: parent.height
                                    text: modelData[0]; color: root.mutedText
                                    font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
                                }
                                Label {
                                    x: 100; width: parent.width - 104; height: parent.height
                                    text: modelData[1]
                                    color: modelData[1] === "—" ? root.dashColor : root.calcColor
                                    font.pixelSize: 10
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // ── Phase comparison table ───────────────────────
                Column {
                    width: parent.width
                    spacing: 0

                    // Section header
                    Rectangle {
                        width: parent.width; height: root.rh + 2
                        color: root.chrome; border.color: root.borderCol; border.width: 1; radius: 3
                        Label {
                            x: root.lpad; width: parent.width - root.lpad * 2; height: parent.height
                            text: "Phase property comparison"
                            color: root.textDark; font.pixelSize: 11; font.bold: true
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Column headers
                    Rectangle {
                        width: parent.width; height: root.rh
                        color: root.chrome; border.color: root.borderCol; border.width: 1
                        Label { x: root.lpad;                                                            width: root.lw;                               height: parent.height; text: "Property"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                        Label { x: root.lw + root.lpad;                                                  width: (parent.width-root.lw-root.lpad)/3;    height: parent.height; text: "Liquid";   color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Label { x: root.lw + root.lpad +     (parent.width-root.lw-root.lpad)/3;         width: (parent.width-root.lw-root.lpad)/3;    height: parent.height; text: "Vapour";   color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Label { x: root.lw + root.lpad + 2 * (parent.width-root.lw-root.lpad)/3;         width: (parent.width-root.lw-root.lpad)/3-4;  height: parent.height; text: "Unit";     color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                    }

                    Repeater {
                        model: root.compRows
                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.borderCol; border.width: 1
                            Label { x: root.lpad;                                                        width: root.lw;                              height: parent.height; text: modelData.label; color: root.mutedText;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Label { x: root.lw + root.lpad;                                              width: (parent.width-root.lw-root.lpad)/3;   height: parent.height; text: modelData.liq;   color: modelData.liq === "—" ? root.dashColor : root.calcColor;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Label { x: root.lw + root.lpad +     (parent.width-root.lw-root.lpad)/3;     width: (parent.width-root.lw-root.lpad)/3;   height: parent.height; text: modelData.vap;   color: modelData.vap === "—" ? root.dashColor : root.calcColor;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Label { x: root.lw + root.lpad + 2 * (parent.width-root.lw-root.lpad)/3;     width: (parent.width-root.lw-root.lpad)/3-4; height: parent.height; text: modelData.unit;  color: root.mutedText;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                // ── Phase envelope ───────────────────────────────
                Column {
                    width: parent.width
                    spacing: 0

                    Rectangle {
                        width: parent.width; height: root.rh + 2
                        color: root.chrome; border.color: root.borderCol; border.width: 1; radius: 3
                        Label {
                            x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                            text: "Phase envelope"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Repeater {
                        model: [
                            { label: "Bubble point",         val: (root.bpK > 0 && isFinite(root.bpK)) ? fmtTK(root.bpK) : "—" },
                            { label: "Dew point",            val: (root.dpK > 0 && isFinite(root.dpK)) ? fmtTK(root.dpK) : "—" },
                            { label: "Critical temperature", val: has() ? fmtTK(root.streamObject.criticalTemperatureK) : "—" },
                            { label: "Critical pressure",    val: has() ? (fmt(root.streamObject.criticalPressureKPa / 100, 4) + " bar   (" + fmt(root.streamObject.criticalPressureKPa, 1) + " kPa)") : "—" },
                        ]
                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.borderCol; border.width: 1
                            Label { x: root.lpad;               width: root.lw;                           height: parent.height; text: modelData.label; color: root.mutedText;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                            Label { x: root.lw + root.lpad;     width: parent.width-root.lw-root.lpad-6; height: parent.height; text: modelData.val;   color: modelData.val === "—" ? root.dashColor : root.calcColor; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }
                    }
                }

                // ── K-values table ───────────────────────────────
                Column {
                    width: parent.width
                    spacing: 0

                    // Section header
                    Rectangle {
                        width: parent.width; height: root.rh + 2
                        color: root.chrome; border.color: root.borderCol; border.width: 1; radius: 3
                        Label {
                            x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                            text: "Equilibrium K-values  (y/x per component)"
                            color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Column headers
                    Rectangle {
                        width: parent.width; height: root.rh
                        color: root.chrome; border.color: root.borderCol; border.width: 1
                        readonly property real colW: (parent.width - root.lw - root.lpad) / 3
                        Label { x: root.lpad;                    width: root.lw;  height: parent.height; text: "Component"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter }
                        Label { x: root.lw + root.lpad;          width: parent.colW; height: parent.height; text: "x  (liquid)"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Label { x: root.lw + root.lpad + parent.colW;     width: parent.colW; height: parent.height; text: "y  (vapour)"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Label { x: root.lw + root.lpad + 2 * parent.colW; width: parent.colW - 4; height: parent.height; text: "K  =  y / x"; color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                    }

                    // Single-phase notice — shown instead of rows when not two-phase
                    Rectangle {
                        visible: root.vf <= 0.0001 || root.vf >= 0.9999
                        width: parent.width; height: 36
                        radius: 4; color: root.warnBg
                        border.color: "#d19a1c"; border.width: 1
                        Label {
                            x: 8; width: parent.width - 16; height: parent.height
                            text: "K-values are only meaningful in the two-phase region.  Current phase: " + root.phase
                            color: root.warnText; font.pixelSize: 11
                            wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Per-component rows — only visible in two-phase region
                    Repeater {
                        model: (root.vf > 0.0001 && root.vf < 0.9999 && root.has())
                               ? root.streamObject.kValuesData : []

                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.borderCol; border.width: 1

                            readonly property real colW: (parent.width - root.lw - root.lpad) / 3
                            readonly property string kStr: {
                                var k = modelData["K"]
                                return (k !== undefined && isFinite(k) && k >= 0)
                                    ? k.toFixed(4) : "—"
                            }

                            Label { x: root.lpad;                      width: root.lw;         height: parent.height; text: modelData["name"] || ""; color: root.mutedText; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Label { x: root.lw + root.lpad;            width: parent.colW;     height: parent.height; text: (modelData["x"] !== undefined) ? Number(modelData["x"]).toFixed(5) : "—"; color: root.calcColor; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Label { x: root.lw + root.lpad + parent.colW;     width: parent.colW;     height: parent.height; text: (modelData["y"] !== undefined) ? Number(modelData["y"]).toFixed(5) : "—"; color: root.calcColor; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Label { x: root.lw + root.lpad + 2 * parent.colW; width: parent.colW - 4; height: parent.height; text: parent.kStr; color: parent.kStr === "—" ? root.dashColor : root.calcColor; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                Item { height: 10 }
            }
        }
    }
}
