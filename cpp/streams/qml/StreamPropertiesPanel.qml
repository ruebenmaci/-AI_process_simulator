import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property var streamObject: null
    property var unitObject: null

    // ── colours ──────────────────────────────────────────────────
    readonly property color bg:        "#f4f6fa"
    readonly property color chrome:    "#d2d9e6"
    readonly property color rowEven:   "#eef2f8"
    readonly property color rowOdd:    "#f4f6fa"
    readonly property color borderCol: "#b0b8c8"
    readonly property color textDark:  "#1f2430"
    readonly property color mutedText: "#5a6472"
    readonly property color calcColor: "#1c4ea7"
    readonly property color dashColor: "#aaaaaa"

    // ── sizing ───────────────────────────────────────────────────
    readonly property int lw:   220   // label column fixed width
    readonly property int rh:   26    // row height
    readonly property int lpad: 10    // left padding

    // ── helpers ──────────────────────────────────────────────────
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
    function fmtP(Pa) {
        if (!Pa || !isFinite(Pa)) return "—"
        return fmt(Pa / 1e5, 4) + " bar   (" + fmt(Pa / 1000, 1) + " kPa)"
    }
    function has() { return !!root.streamObject }

    // ── derived values (all in root scope) ───────────────────────
    readonly property real massFlow:  has() ? root.streamObject.flowRateKgph        : 0
    readonly property real molarFlow: has() ? root.streamObject.molarFlowKmolph      : 0
    readonly property real volFlow:   has() ? root.streamObject.volumetricFlowM3ph   : 0
    readonly property real tempK:     has() ? root.streamObject.temperatureK         : 0
    readonly property real pressPa:   has() ? root.streamObject.pressurePa           : 0
    readonly property real vf:        has() ? root.streamObject.vaporFraction         : 0
    readonly property real avgMw:     (molarFlow > 0 && massFlow > 0) ? massFlow / molarFlow : 0
    readonly property real density:   (volFlow > 0 && massFlow > 0)   ? massFlow / volFlow   : 0
    readonly property real sg:        density > 0 ? density / 999.0 : 0
    readonly property real apiGrav:   sg      > 0 ? (141.5 / sg - 131.5) : 0
    readonly property real bpK:       has() ? root.streamObject.bubblePointEstimateK : 0
    readonly property real dpK:       has() ? root.streamObject.dewPointEstimateK    : 0

    // ── all section data as a flat list ──────────────────────────
    // Each entry: { hdr: bool, label: string, value: string, calc: bool }
    // We build this as a property so it reacts to changes
    property var allRows: []

    function buildRows() {
        if (!root.has()) { allRows = []; return }
        var r = []
        function hdr(t)              { r.push({ hdr: true,  label: t,   value: "",   calc: false }) }
        function row(l, v, c)        { r.push({ hdr: false, label: l,   value: v,    calc: !!c   }) }

        hdr("Stream summary")
        row("Phase",                root.streamObject.phaseStatus,                              false)
        row("Vapour fraction",      fmt(root.vf, 4),                                            true)
        row("Thermo region",        root.streamObject.thermoRegionLabel,                        true)
        row("Flash method",         root.streamObject.flashMethod,                              true)
        row("Molar flow",           fmt(root.molarFlow, 3) + " kmol/h",                        true)
        row("Volumetric flow",      fmt(root.volFlow,   3) + " m³/h",                          true)
        row("Std. vol. flow",       "—",                                                        true)

        hdr("Molecular & bulk properties")
        row("Avg. molecular weight",root.avgMw   > 0 ? fmt(root.avgMw,   2) + " kg/kmol" : "—", true)
        row("Bulk liquid density",  root.density > 0 ? fmt(root.density, 2) + " kg/m³"   : "—", true)
        row("Vapour density",       "—",                                                        true)
        row("Specific gravity",     root.sg      > 0 ? fmt(root.sg,      4)               : "—", true)
        row("API gravity",          root.sg      > 0 ? fmt(root.apiGrav, 1) + " °API"     : "—", true)
        row("Watson K factor",      "—",                                                        true)

        hdr("Thermodynamic properties  (available after flash)")
        row("Enthalpy — liquid",    "—", true)
        row("Enthalpy — vapour",    "—", true)
        row("Enthalpy — mixture",   "—", true)
        row("Entropy — liquid",     "—", true)
        row("Entropy — vapour",     "—", true)
        row("Heat capacity Cp (liq.)", "—", true)
        row("Heat capacity Cp (vap.)", "—", true)
        row("Cp/Cv ratio (vap.)",   "—", true)

        hdr("Transport properties  (available after flash)")
        row("Viscosity — liquid",           "—", true)
        row("Viscosity — vapour",           "—", true)
        row("Thermal conductivity (liq.)",  "—", true)
        row("Thermal conductivity (vap.)",  "—", true)
        row("Surface tension",              "—", true)

        hdr("Phase envelope estimates")
        row("Bubble point",         (root.bpK > 0 && isFinite(root.bpK)) ? fmtTK(root.bpK) : "—", true)
        row("Dew point",            (root.dpK > 0 && isFinite(root.dpK)) ? fmtTK(root.dpK) : "—", true)
        row("Critical temperature", "—", true)
        row("Critical pressure",    "—", true)

        allRows = r
    }

    // Rebuild whenever stream data changes
    onStreamObjectChanged:  Qt.callLater(buildRows)
    Component.onCompleted:  Qt.callLater(buildRows)

    Connections {
        target: root.streamObject
        function onDerivosConditionsChanged() { Qt.callLater(buildRows) }
        function onDerivedConditionsChanged()  { Qt.callLater(buildRows) }
        function onFlowRateKgphChanged()       { Qt.callLater(buildRows) }
        function onTemperatureKChanged()       { Qt.callLater(buildRows) }
        function onPressurePaChanged()         { Qt.callLater(buildRows) }
        ignoreUnknownSignals: true
    }

    // ── UI ───────────────────────────────────────────────────────
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

            // A single Column containing all rows - no nested layouts
            Column {
                width: Math.max(parent.width, 500)
                spacing: 0

                Repeater {
                    model: root.allRows

                    // Each item is either a section header or a data row
                    // We use a single delegate that switches appearance
                    Item {
                        width: parent.width
                        height: modelData.hdr ? root.rh + 4 : root.rh

                        // ── Section header ──
                        Rectangle {
                            visible: modelData.hdr
                            x: 0; y: modelData.hdr ? 4 : 0
                            width: parent.width
                            height: root.rh
                            color: root.chrome
                            border.color: root.borderCol
                            border.width: 1
                            radius: 3
                            Label {
                                x: root.lpad
                                width: parent.width - root.lpad * 2
                                height: parent.height
                                text: modelData.label
                                color: root.textDark
                                font.pixelSize: 11
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        // ── Data row ──
                        Rectangle {
                            visible: !modelData.hdr
                            x: 0; y: 0
                            width: parent.width
                            height: root.rh
                            color: {
                                // Count non-header rows to alternate colours
                                var c = 0
                                for (var i = 0; i < index; i++) {
                                    if (!root.allRows[i].hdr) c++
                                }
                                return c % 2 === 0 ? root.rowEven : root.rowOdd
                            }
                            border.color: root.borderCol
                            border.width: 1

                            // Label column
                            Label {
                                x: root.lpad
                                width: root.lw
                                height: parent.height
                                text: modelData.label
                                color: root.mutedText
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            // Value column
                            Label {
                                x: root.lw + root.lpad
                                width: parent.width - root.lw - root.lpad - 6
                                height: parent.height
                                text: modelData.value
                                color: modelData.value === "—" ? root.dashColor
                                       : modelData.calc        ? root.calcColor
                                       : root.textDark
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
