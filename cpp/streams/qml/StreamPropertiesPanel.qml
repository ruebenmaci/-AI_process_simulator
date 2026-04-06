import QtQuick 2.15
import QtQuick.Controls 2.15
import ChatGPT5.ADT 1.0

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    readonly property color bg:       "#e8ebef"
    readonly property color hdrBg:    "#c8d0d8"
    readonly property color hdrBdr:   "#97a2ad"
    readonly property color textMain: "#1f2a34"
    readonly property color textMuted:"#526571"

    property int headH: 20
    property int secGap: 6

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
    function has() { return !!streamObject }

    component SecHdr : Rectangle {
        property alias text: lbl.text
        width: parent.width; height: root.headH
        color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
        Text {
            id: lbl
            anchors.left: parent.left; anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 10; font.bold: true; color: root.textMain
        }
    }

    // ── Each sheet self-populates via its own Connections ──────────────
    // This avoids the root-id-before-instantiation timing problem entirely.

    Rectangle {
        anchors.fill: parent
        color: root.bg; border.color: root.hdrBdr; border.width: 1

        Rectangle {
            id: panelHdr
            x: 0; y: 0; width: parent.width; height: root.headH
            color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
            Text {
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Properties"; font.pixelSize: 10; font.bold: true; color: root.textMain
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.has()
            text: "No stream selected"; font.pixelSize: 11; color: root.textMuted
        }

        ScrollView {
            x: 0; y: panelHdr.height
            width: parent.width; height: parent.height - panelHdr.height
            visible: root.has(); clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy:   ScrollBar.AsNeeded

            Column {
                width: parent.width
                spacing: root.secGap

                // ── Stream Summary ────────────────────────────────────
                SecHdr { text: "Stream Summary" }
                SimpleSpreadsheet {
                    id: sheetSummary
                    readOnly: true
                    x: 4; width: parent.width - 8; numRows: 11; numCols: 1
                    defaultColW: Math.max(180, width - hdrColW - 4)
                    colLabels: ["Value"]
                    cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })

                    function refresh() {
                        clearAll()
                        if (!root.has()) return
                        const s = root.streamObject
                        const mf = s.flowRateKgph; const mol = s.molarFlowKmolph; const vf = s.volumetricFlowM3ph
                        rowLabels = ["Fluid package", "Thermo method", "Package status", "Phase", "Vapour fraction", "Thermo region", "Flash method",
                                     "Specification", "Molar flow", "Volumetric flow", "Std. vol. flow"]
                        colLabels = ["Value"]
                        const vals = [s.selectedFluidPackageName || s.selectedFluidPackageId || "—",
                                      s.fluidPackageThermoMethod || "—",
                                      s.fluidPackageStatus || "—",
                                      s.phaseStatus || "—", root.fmt(s.vaporFraction, 4),
                                      s.thermoRegionLabel || "—", s.flashMethod || "—",
                                      s.specificationStatus || "—",
                                      root.fmt(mol, 3) + " kmol/h",
                                      root.fmt(vf,  3) + " m³/h",
                                      root.fmt(s.calcStdVolFlowM3ph, 3) + " m³/h"]
                        for (let i = 0; i < vals.length; ++i) setCell(i, 0, vals[i])
                    }

                    Component.onCompleted: Qt.callLater(refresh)
                    Connections {
                        target: root
                        function onStreamObjectChanged() { Qt.callLater(sheetSummary.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onDerivedConditionsChanged() { Qt.callLater(sheetSummary.refresh) }
                        function onFlowRateKgphChanged()      { Qt.callLater(sheetSummary.refresh) }
                        function onTemperatureKChanged()       { Qt.callLater(sheetSummary.refresh) }
                        function onPressurePaChanged()         { Qt.callLater(sheetSummary.refresh) }
                        ignoreUnknownSignals: true
                    }
                }

                // ── Molecular & Bulk ──────────────────────────────────
                SecHdr { text: "Molecular & Bulk" }
                SimpleSpreadsheet {
                    id: sheetMolecular
                    readOnly: true
                    x: 4; width: parent.width - 8; numRows: 6; numCols: 1
                    defaultColW: Math.max(180, width - hdrColW - 4)
                    colLabels: ["Value"]
                    cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })

                    function refresh() {
                        clearAll()
                        if (!root.has()) return
                        const s = root.streamObject
                        const mf = s.flowRateKgph; const mol = s.molarFlowKmolph; const vf = s.volumetricFlowM3ph
                        const avgMw   = (mol > 0 && mf > 0) ? mf / mol : 0
                        const density = (vf  > 0 && mf > 0) ? mf / vf  : 0
                        const sg      = density > 0 ? density / 999.0 : 0
                        const api     = sg > 0 ? (141.5 / sg - 131.5) : 0
                        rowLabels = ["Avg. molecular weight", "Bulk liquid density", "Vapour density",
                                     "Specific gravity", "API gravity", "Watson K factor"]
                        colLabels = ["Value"]
                        const vals = [avgMw   > 0 ? root.fmt(avgMw,   2) + " kg/kmol" : "—",
                                      density > 0 ? root.fmt(density, 2) + " kg/m³"   : "—",
                                      root.fmt(s.vapourDensityKgM3, 2) + " kg/m³",
                                      sg      > 0 ? root.fmt(sg,      4)               : "—",
                                      sg      > 0 ? root.fmt(api,     1) + " °API"     : "—",
                                      root.fmt(s.watsonKFactor, 3)]
                        for (let i = 0; i < vals.length; ++i) setCell(i, 0, vals[i])
                    }

                    Component.onCompleted: Qt.callLater(refresh)
                    Connections {
                        target: root
                        function onStreamObjectChanged() { Qt.callLater(sheetMolecular.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onDerivedConditionsChanged() { Qt.callLater(sheetMolecular.refresh) }
                        function onFlowRateKgphChanged()      { Qt.callLater(sheetMolecular.refresh) }
                        ignoreUnknownSignals: true
                    }
                }

                // ── Thermodynamic Properties ──────────────────────────
                SecHdr { text: "Thermodynamic Properties" }
                SimpleSpreadsheet {
                    id: sheetThermo
                    readOnly: true
                    x: 4; width: parent.width - 8; numRows: 8; numCols: 1
                    defaultColW: Math.max(180, width - hdrColW - 4)
                    colLabels: ["Value"]
                    cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })

                    function refresh() {
                        clearAll()
                        if (!root.has()) return
                        const s = root.streamObject
                        rowLabels = ["Enthalpy — liquid", "Enthalpy — vapour", "Enthalpy — mixture",
                                     "Entropy — liquid",  "Entropy — vapour",
                                     "Cp liquid", "Cp vapour", "Cp/Cv vapour"]
                        colLabels = ["Value"]
                        const vals = [root.fmt(s.liquidEnthalpyKJkg,  2) + " kJ/kg",
                                      root.fmt(s.vapourEnthalpyKJkg,  2) + " kJ/kg",
                                      root.fmt(s.enthalpyKJkg,        2) + " kJ/kg",
                                      root.fmt(s.liquidEntropyKJkgK,  4) + " kJ/kg·K",
                                      root.fmt(s.vapourEntropyKJkgK,  4) + " kJ/kg·K",
                                      root.fmt(s.liquidCpKJkgK,       3) + " kJ/kg·K",
                                      root.fmt(s.vapourCpKJkgK,       3) + " kJ/kg·K",
                                      root.fmt(s.vapourCpCvRatio,     4)]
                        for (let i = 0; i < vals.length; ++i) setCell(i, 0, vals[i])
                    }

                    Component.onCompleted: Qt.callLater(refresh)
                    Connections {
                        target: root
                        function onStreamObjectChanged() { Qt.callLater(sheetThermo.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onDerivedConditionsChanged() { Qt.callLater(sheetThermo.refresh) }
                        ignoreUnknownSignals: true
                    }
                }

                // ── Transport Properties ──────────────────────────────
                SecHdr { text: "Transport Properties" }
                SimpleSpreadsheet {
                    id: sheetTransport
                    readOnly: true
                    x: 4; width: parent.width - 8; numRows: 5; numCols: 1
                    defaultColW: Math.max(180, width - hdrColW - 4)
                    colLabels: ["Value"]
                    cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })

                    function refresh() {
                        clearAll()
                        if (!root.has()) return
                        const s = root.streamObject
                        rowLabels = ["Viscosity — liquid", "Viscosity — vapour",
                                     "Thermal cond. liquid", "Thermal cond. vapour",
                                     "Surface tension"]
                        colLabels = ["Value"]
                        const vals = [root.fmt(s.liquidViscosityCp,    4) + " cP",
                                      root.fmt(s.vapourViscosityCp,    4) + " cP",
                                      root.fmt(s.liquidThermalCondWmK, 4) + " W/m·K",
                                      root.fmt(s.vapourThermalCondWmK, 4) + " W/m·K",
                                      root.fmt(s.surfaceTensionNm,     5) + " N/m"]
                        for (let i = 0; i < vals.length; ++i) setCell(i, 0, vals[i])
                    }

                    Component.onCompleted: Qt.callLater(refresh)
                    Connections {
                        target: root
                        function onStreamObjectChanged() { Qt.callLater(sheetTransport.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onDerivedConditionsChanged() { Qt.callLater(sheetTransport.refresh) }
                        ignoreUnknownSignals: true
                    }
                }

                // ── Phase Envelope ────────────────────────────────────
                SecHdr { text: "Phase Envelope" }
                SimpleSpreadsheet {
                    id: sheetEnvelope
                    readOnly: true
                    x: 4; width: parent.width - 8; numRows: 4; numCols: 1
                    defaultColW: Math.max(180, width - hdrColW - 4)
                    colLabels: ["Value"]
                    cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })

                    function refresh() {
                        clearAll()
                        if (!root.has()) return
                        const s = root.streamObject
                        rowLabels = ["Bubble point", "Dew point",
                                     "Critical temperature", "Critical pressure"]
                        colLabels = ["Value"]
                        const vals = [
                            (s.bubblePointEstimateK > 0 && isFinite(s.bubblePointEstimateK))
                                ? root.fmtTK(s.bubblePointEstimateK) : "—",
                            (s.dewPointEstimateK > 0 && isFinite(s.dewPointEstimateK))
                                ? root.fmtTK(s.dewPointEstimateK) : "—",
                            root.fmtTK(s.criticalTemperatureK),
                            root.fmtP(s.criticalPressureKPa * 1000)
                        ]
                        for (let i = 0; i < vals.length; ++i) setCell(i, 0, vals[i])
                    }

                    Component.onCompleted: Qt.callLater(refresh)
                    Connections {
                        target: root
                        function onStreamObjectChanged() { Qt.callLater(sheetEnvelope.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onDerivedConditionsChanged() { Qt.callLater(sheetEnvelope.refresh) }
                        ignoreUnknownSignals: true
                    }
                }

                Item { height: root.secGap }
            }
        }
    }
}
