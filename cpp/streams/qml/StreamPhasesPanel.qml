import QtQuick 2.15
import QtQuick.Controls 2.15
import ChatGPT5.ADT 1.0

// StreamPhasesPanel — restyled to ComponentManagerView palette.
// The phase cards and K-values table are kept as custom renderers
// since they have structured multi-column layouts; everything else
// uses CompactFrame / SectionHeader style rectangles.

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    // ── Palette ────────────────────────────────────────────────────────
    readonly property color bg:       "#e8ebef"
    readonly property color hdrBg:    "#c8d0d8"
    readonly property color hdrBdr:   "#97a2ad"
    readonly property color rowEven:  "#f4f6f8"
    readonly property color rowOdd:   "#ffffff"
    readonly property color textMain: "#1f2a34"
    readonly property color textMuted:"#526571"
    readonly property color calcCol:  "#1c4ea7"
    readonly property color dashCol:  "#aaaaaa"
    readonly property color liqHdr:   "#dbeafe"
    readonly property color vapHdr:   "#fef9c3"
    readonly property color warnBg:   "#fff4db"
    readonly property color warnText: "#744f00"

    readonly property int rh:   22
    readonly property int lpad: 8
    readonly property int headH: 20

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
    function has() { return !!streamObject }

    readonly property real massFlow:  has() ? streamObject.flowRateKgph       : 0
    readonly property real molarFlow: has() ? streamObject.molarFlowKmolph     : 0
    readonly property real volFlow:   has() ? streamObject.volumetricFlowM3ph  : 0
    readonly property real vf:        has() ? streamObject.vaporFraction        : 0
    readonly property real lf:        1.0 - vf
    readonly property string phase:   has() ? streamObject.phaseStatus          : "—"
    readonly property string thermoR: has() ? streamObject.thermoRegionLabel    : "—"
    readonly property real bpK:       has() ? streamObject.bubblePointEstimateK : 0
    readonly property real dpK:       has() ? streamObject.dewPointEstimateK    : 0

    // Comparison table rows
    function buildCompRows() {
        if (!has()) return [
            { label: "Density",              liq: "—", vap: "—", unit: "kg/m³"   },
            { label: "Viscosity",            liq: "—", vap: "—", unit: "cP"       },
            { label: "Thermal conductivity", liq: "—", vap: "—", unit: "W/m·K"   },
            { label: "Heat capacity Cp",     liq: "—", vap: "—", unit: "kJ/kg·K" },
            { label: "Enthalpy",             liq: "—", vap: "—", unit: "kJ/kg"   },
            { label: "Entropy",              liq: "—", vap: "—", unit: "kJ/kg·K" },
            { label: "Surface tension",      liq: "—", vap: "—", unit: "N/m"     },
        ]
        const s = streamObject
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

    property var compRows: []
    function refreshCompRows() { compRows = buildCompRows() }

    onStreamObjectChanged: Qt.callLater(refreshCompRows)
    Component.onCompleted:  Qt.callLater(refreshCompRows)
    Connections {
        target: root.streamObject
        function onDerivedConditionsChanged() { Qt.callLater(refreshCompRows) }
        ignoreUnknownSignals: true
    }

    // ── UI ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.bg; border.color: root.hdrBdr; border.width: 1

        // Panel header
        Rectangle {
            id: panelHdr
            x: 0; y: 0; width: parent.width; height: root.headH
            color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
            Text {
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Phases"; font.pixelSize: 10; font.bold: true; color: root.textMain
            }
        }

        Text {
            anchors.centerIn: parent; visible: !root.has()
            text: "No stream selected"; font.pixelSize: 11; color: root.textMuted
        }

        ScrollView {
            x: 0; y: panelHdr.height
            width: parent.width; height: parent.height - panelHdr.height
            visible: root.has(); clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy:   ScrollBar.AsNeeded

            Column {
                width: Math.max(parent.width, 480)
                spacing: 4
                topPadding: 4
                leftPadding: 4
                rightPadding: 4
                bottomPadding: 4

                // ── Phase status banner ────────────────────────────────
                Rectangle {
                    width: parent.width - 8; height: root.rh + 6
                    color: {
                        if (root.phase === "Liquid")    return "#dbeafe"
                        if (root.phase === "Vapor")     return "#fef9c3"
                        if (root.phase === "Two-Phase") return "#dcfce7"
                        return root.bg
                    }
                    border.color: root.hdrBdr; border.width: 1
                    Text {
                        x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                        text: "Phase:  " + root.phase
                              + "     |     Vapour fraction:  " + root.fmt(root.vf, 4)
                              + "     |     " + root.thermoR
                        font.pixelSize: 10; font.bold: true; color: root.textMain
                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    }
                }

                // ── Phase cards (liquid | vapour side-by-side) ─────────
                Item {
                    width: parent.width - 8
                    height: 28 + 6 * root.rh + 4

                    // Liquid card
                    Rectangle {
                        id: liqCard
                        x: 0; y: 0
                        width: Math.floor((parent.width - 6) / 2)
                        height: parent.height
                        color: root.bg; border.color: root.hdrBdr; border.width: 1
                        opacity: root.lf > 0.0001 ? 1.0 : 0.4

                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: root.headH
                            color: root.liqHdr; border.color: root.hdrBdr; border.width: 1
                            Text { x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                                   text: "Liquid phase  (" + root.fmt(root.lf * 100, 1) + " %)"
                                   font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                        }

                        Repeater {
                            model: [
                                ["Mass flow",  root.fmt(root.massFlow  * root.lf, 1) + " kg/h"],
                                ["Molar flow", root.fmt(root.molarFlow * root.lf, 3) + " kmol/h"],
                                ["Vol. flow",  root.fmt(root.volFlow   * root.lf, 3) + " m³/h"],
                                ["Density",    root.has() ? root.fmt(root.streamObject.liquidDensityKgM3,  2) + " kg/m³" : "—"],
                                ["Viscosity",  root.has() ? root.fmt(root.streamObject.liquidViscosityCp,  4) + " cP"    : "—"],
                                ["Enthalpy",   root.has() ? root.fmt(root.streamObject.liquidEnthalpyKJkg, 2) + " kJ/kg" : "—"],
                            ]
                            Rectangle {
                                x: 1; y: root.headH + index * root.rh
                                width: liqCard.width - 2; height: root.rh
                                color: index % 2 === 0 ? root.rowEven : root.rowOdd
                                border.color: root.hdrBdr; border.width: 1
                                Text { x: root.lpad; width: 90; height: parent.height; text: modelData[0]; color: root.textMuted; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { x: 96; width: parent.width - 100; height: parent.height; text: modelData[1];
                                       color: modelData[1] === "—" ? root.dashCol : root.calcCol
                                       font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                            }
                        }
                    }

                    // Vapour card
                    Rectangle {
                        id: vapCard
                        x: Math.floor((parent.width - 6) / 2) + 6
                        y: 0
                        width: Math.floor((parent.width - 6) / 2)
                        height: parent.height
                        color: root.bg; border.color: root.hdrBdr; border.width: 1
                        opacity: root.vf > 0.0001 ? 1.0 : 0.4

                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: root.headH
                            color: root.vapHdr; border.color: root.hdrBdr; border.width: 1
                            Text { x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                                   text: "Vapour phase  (" + root.fmt(root.vf * 100, 1) + " %)"
                                   font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                        }

                        Repeater {
                            model: [
                                ["Mass flow",  root.fmt(root.massFlow  * root.vf, 1) + " kg/h"],
                                ["Molar flow", root.fmt(root.molarFlow * root.vf, 3) + " kmol/h"],
                                ["Vol. flow",  root.fmt(root.volFlow   * root.vf, 3) + " m³/h"],
                                ["Density",    root.has() ? root.fmt(root.streamObject.vapourDensityKgM3,  2) + " kg/m³" : "—"],
                                ["Viscosity",  root.has() ? root.fmt(root.streamObject.vapourViscosityCp,  4) + " cP"    : "—"],
                                ["Enthalpy",   root.has() ? root.fmt(root.streamObject.vapourEnthalpyKJkg, 2) + " kJ/kg" : "—"],
                            ]
                            Rectangle {
                                x: 1; y: root.headH + index * root.rh
                                width: vapCard.width - 2; height: root.rh
                                color: index % 2 === 0 ? root.rowEven : root.rowOdd
                                border.color: root.hdrBdr; border.width: 1
                                Text { x: root.lpad; width: 90; height: parent.height; text: modelData[0]; color: root.textMuted; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                                Text { x: 96; width: parent.width - 100; height: parent.height; text: modelData[1];
                                       color: modelData[1] === "—" ? root.dashCol : root.calcCol
                                       font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                // ── Phase comparison table ─────────────────────────────
                Column {
                    width: parent.width - 8; spacing: 0

                    // Section header
                    Rectangle {
                        width: parent.width; height: root.headH
                        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
                        Text { x: root.lpad; width: parent.width - root.lpad*2; height: parent.height
                               text: "Phase property comparison"; font.pixelSize: 10; font.bold: true
                               color: root.textMain; verticalAlignment: Text.AlignVCenter }
                    }
                    // Column headers
                    Rectangle {
                        width: parent.width; height: root.rh
                        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
                        readonly property real cw: (parent.width - 160 - root.lpad) / 3
                        Text { x: root.lpad;              width: 160;         height: parent.height; text: "Property"; font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                        Text { x: 160 + root.lpad;        width: parent.cw;   height: parent.height; text: "Liquid";   font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Text { x: 160 + root.lpad + parent.cw;     width: parent.cw;   height: parent.height; text: "Vapour";  font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Text { x: 160 + root.lpad + 2*parent.cw;   width: parent.cw-4; height: parent.height; text: "Unit";    font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                    }
                    Repeater {
                        model: root.compRows
                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.hdrBdr; border.width: 1
                            readonly property real cw: (parent.width - 160 - root.lpad) / 3
                            Text { x: root.lpad;             width: 160;         height: parent.height; text: modelData.label; color: root.textMuted;  font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { x: 160+root.lpad;         width: parent.cw;   height: parent.height; text: modelData.liq; color: modelData.liq === "—" ? root.dashCol : root.calcCol; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { x: 160+root.lpad+parent.cw;     width: parent.cw;   height: parent.height; text: modelData.vap; color: modelData.vap === "—" ? root.dashCol : root.calcCol; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { x: 160+root.lpad+2*parent.cw;   width: parent.cw-4; height: parent.height; text: modelData.unit; color: root.textMuted; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                // ── Phase envelope ─────────────────────────────────────
                Column {
                    width: parent.width - 8; spacing: 0

                    Rectangle {
                        width: parent.width; height: root.headH
                        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
                        Text { x: root.lpad; width: parent.width-root.lpad*2; height: parent.height
                               text: "Phase envelope"; font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                    }
                    Repeater {
                        model: [
                            { label: "Bubble point",         val: (root.bpK > 0 && isFinite(root.bpK)) ? root.fmtTK(root.bpK) : "—" },
                            { label: "Dew point",            val: (root.dpK > 0 && isFinite(root.dpK)) ? root.fmtTK(root.dpK) : "—" },
                            { label: "Critical temperature", val: root.has() ? root.fmtTK(root.streamObject.criticalTemperatureK) : "—" },
                            { label: "Critical pressure",    val: root.has() ? (root.fmt(root.streamObject.criticalPressureKPa/100, 4) + " bar   (" + root.fmt(root.streamObject.criticalPressureKPa, 1) + " kPa)") : "—" },
                        ]
                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.hdrBdr; border.width: 1
                            Text { x: root.lpad; width: 160; height: parent.height; text: modelData.label; color: root.textMuted; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter }
                            Text { x: 160+root.lpad; width: parent.width-164-root.lpad; height: parent.height; text: modelData.val;
                                   color: modelData.val === "—" ? root.dashCol : root.calcCol
                                   font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }
                    }
                }

                // ── K-values table ─────────────────────────────────────
                Column {
                    width: parent.width - 8; spacing: 0

                    Rectangle {
                        width: parent.width; height: root.headH
                        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
                        Text { x: root.lpad; width: parent.width-root.lpad*2; height: parent.height
                               text: "Equilibrium K-values  (y / x per component)"
                               font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                    }
                    // Column headers
                    Rectangle {
                        width: parent.width; height: root.rh
                        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
                        readonly property real cw: (parent.width - 160 - root.lpad) / 3
                        Text { x: root.lpad;               width: 160;         height: parent.height; text: "Component";  font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter }
                        Text { x: 160+root.lpad;           width: parent.cw;   height: parent.height; text: "x  (liquid)"; font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Text { x: 160+root.lpad+parent.cw; width: parent.cw;   height: parent.height; text: "y  (vapour)"; font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        Text { x: 160+root.lpad+2*parent.cw; width: parent.cw-4; height: parent.height; text: "K = y/x";  font.pixelSize: 10; font.bold: true; color: root.textMain; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                    }
                    // Single-phase notice
                    Rectangle {
                        visible: root.vf <= 0.0001 || root.vf >= 0.9999
                        width: parent.width; height: root.rh + 4
                        color: root.warnBg; border.color: "#d19a1c"; border.width: 1
                        Text { x: root.lpad; width: parent.width-root.lpad*2; height: parent.height
                               text: "K-values are only meaningful in the two-phase region.  Current phase: " + root.phase
                               color: root.warnText; font.pixelSize: 10; wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter }
                    }
                    Repeater {
                        model: (root.vf > 0.0001 && root.vf < 0.9999 && root.has())
                               ? root.streamObject.kValuesData : []
                        Rectangle {
                            width: parent.width; height: root.rh
                            color: index % 2 === 0 ? root.rowEven : root.rowOdd
                            border.color: root.hdrBdr; border.width: 1
                            readonly property real cw: (parent.width - 160 - root.lpad) / 3
                            readonly property string kStr: {
                                const k = modelData["K"]
                                return (k !== undefined && isFinite(k) && k >= 0) ? k.toFixed(4) : "—"
                            }
                            Text { x: root.lpad;               width: 160;     height: parent.height; text: modelData["name"] || ""; color: root.textMuted; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { x: 160+root.lpad;           width: parent.cw; height: parent.height; text: modelData["x"] !== undefined ? Number(modelData["x"]).toFixed(5) : "—"; color: root.calcCol; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { x: 160+root.lpad+parent.cw; width: parent.cw; height: parent.height; text: modelData["y"] !== undefined ? Number(modelData["y"]).toFixed(5) : "—"; color: root.calcCol; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { x: 160+root.lpad+2*parent.cw; width: parent.cw-4; height: parent.height; text: parent.kStr;
                                   color: parent.kStr === "—" ? root.dashCol : root.calcCol; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                Item { height: 8 }
            }
        }
    }
}
