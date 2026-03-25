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

    // Comparison table rows (static - values are all "—" until flash is implemented)
    readonly property var compRows: [
        { label: "Density",              liq: "—", vap: "—", unit: "kg/m³"   },
        { label: "Viscosity",            liq: "—", vap: "—", unit: "cP"       },
        { label: "Thermal conductivity", liq: "—", vap: "—", unit: "W/m·K"   },
        { label: "Heat capacity Cp",     liq: "—", vap: "—", unit: "kJ/kg·K" },
        { label: "Enthalpy",             liq: "—", vap: "—", unit: "kJ/kg"   },
        { label: "Entropy",              liq: "—", vap: "—", unit: "kJ/kg·K" },
        { label: "Surface tension",      liq: "—", vap: "—", unit: "N/m"     },
    ]

    readonly property var envelopeRows: [
        { label: "Bubble point",          value: "" },
        { label: "Dew point",             value: "" },
        { label: "Critical temperature",  value: "—" },
        { label: "Critical pressure",     value: "—" },
    ]

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
                                ["Density",    "—"],
                                ["Viscosity",  "—"],
                                ["Enthalpy",   "—"],
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
                                ["Density",    "—"],
                                ["Viscosity",  "—"],
                                ["Enthalpy",   "—"],
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
                            Label { x: root.lw + root.lpad;                                              width: (parent.width-root.lw-root.lpad)/3;   height: parent.height; text: modelData.liq;   color: root.dashColor;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Label { x: root.lw + root.lpad +     (parent.width-root.lw-root.lpad)/3;     width: (parent.width-root.lw-root.lpad)/3;   height: parent.height; text: modelData.vap;   color: root.dashColor;  font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
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
                            { label: "Critical temperature", val: "—" },
                            { label: "Critical pressure",    val: "—" },
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

                // ── K-values note ────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 0

                    Rectangle {
                        width: parent.width; height: root.rh + 2
                        color: root.chrome; border.color: root.borderCol; border.width: 1; radius: 3
                        Label {
                            x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                            text: "Equilibrium K-values  (y/x per component)"
                            color: root.textDark; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 44
                        radius: 4; color: root.warnBg
                        border.color: "#d19a1c"; border.width: 1
                        Label {
                            x: 8; width: parent.width - 16; height: parent.height
                            text: (root.vf <= 0.0001 || root.vf >= 0.9999)
                                  ? "K-values are only meaningful in the two-phase region.  Current phase: " + root.phase
                                  : "K-values available after full flash calculation is implemented."
                            color: root.warnText; font.pixelSize: 11
                            wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item { height: 10 }
            }
        }
    }
}
