import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

// StreamConditionsPanel — restyled to match ComponentManagerView palette.
// Layout: CompactFrame containing a two-column SimpleSpreadsheet for all
// scalar fields, plus the Name / FlowBasis / ThermoSpec / CrudeCombo
// controls rendered as lightweight inline rows above the sheet.

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    // ── Palette ────────────────────────────────────────────────────────
    readonly property color bg:      "#e8ebef"
    readonly property color hdrBg:   "#c8d0d8"
    readonly property color hdrBdr:  "#97a2ad"
    readonly property color textMain:"#1f2a34"
    readonly property color textMuted: "#526571"
    readonly property color calcCol: "#1c4ea7"
    readonly property color warnCol: "#a05a00"
    readonly property color errCol:  "#b23b3b"

    property int headH: 20
    property int rowH:  22

    readonly property bool isProduct:   !!streamObject && streamObject.productStream
    readonly property bool canEdit:     !!streamObject && !isProduct
    readonly property bool canEditCrude: canEdit && !!streamObject && streamObject.isCrudeFeed

    function fmt0(v) { return Number(v || 0).toFixed(0) }
    function fmt3(v) { return Number(v || 0).toFixed(3) }
    function fmt4(v) { return Number(v || 0).toFixed(4) }
    function fmt6(v) { return Number(v || 0).toFixed(6) }
    function orFallback(text, fb) { const v = Number(text); return isNaN(v) ? fb : v }



    // ── Root frame ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.bg; border.color: root.hdrBdr; border.width: 1

        // Section header
        Rectangle {
            id: panelHeader
            x: 0; y: 0; width: parent.width; height: root.headH
            color: root.hdrBg; border.color: root.hdrBdr; border.width: 1
            Text {
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Conditions"; font.pixelSize: 10; font.bold: true; color: root.textMain
            }
        }

        // ── Controls strip (editable inputs) ──────────────────────────
        Rectangle {
            id: controlStrip
            x: 0; y: panelHeader.height
            width: parent.width
            color: root.bg; border.color: root.hdrBdr; border.width: 1

            Column {
                x: 6; y: 4; width: parent.width - 12; spacing: 3

                // Name
                Row {
                    spacing: 8; height: root.rowH
                    Text { width: 130; text: "Name"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    TextField {
                        id: nameField
                        width: 260; height: root.rowH - 4
                        text: root.unitObject ? (root.unitObject.name || root.unitObject.id || "") : ""
                        enabled: !!root.streamObject
                        font.pixelSize: 10; selectByMouse: true
                        padding: 2; leftPadding: 4
                        background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
                        onEditingFinished: {
                            if (!root.unitObject) return
                            let v = text.trim().replace(/\s+/g, "_").replace(/[^A-Za-z0-9_\-.]/g, "")
                            if (v === "") v = root.unitObject.id
                            if (text !== v) text = v
                            root.unitObject.name = v
                        }
                    }
                }

                // Crude selector (crude feed only)
                Row {
                    spacing: 8; height: root.rowH
                    visible: root.canEdit && !!root.streamObject && root.streamObject.isCrudeFeed
                    Text { width: 130; text: "Crude assay"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    ComboBox {
                        id: crudeCombo
                        width: 220; height: root.rowH - 2
                        model: root.streamObject ? root.streamObject.fluidNames : []
                        enabled: root.canEditCrude
                        font.pixelSize: 10
                        Component.onCompleted: {
                            if (root.streamObject && root.streamObject.fluidNames) {
                                const i = root.streamObject.fluidNames.indexOf(root.streamObject.selectedFluid)
                                if (i >= 0) currentIndex = i
                            }
                        }
                        onActivated: if (root.streamObject) root.streamObject.selectedFluid = model[index]
                        Connections {
                            target: root.streamObject
                            function onSelectedFluidChanged() {
                                if (!root.streamObject || !root.streamObject.fluidNames) return
                                const i = root.streamObject.fluidNames.indexOf(root.streamObject.selectedFluid)
                                if (i >= 0 && crudeCombo.currentIndex !== i) crudeCombo.currentIndex = i
                            }
                            ignoreUnknownSignals: true
                        }
                    }
                }

                // Flow basis + Thermo spec on one row
                Row {
                    spacing: 24; height: root.rowH
                    Row {
                        spacing: 8; height: parent.height
                        Text { width: 130; text: "Flow basis"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                        ComboBox {
                            width: 160; height: root.rowH - 2
                            model: ["Mass flow", "Molar flow", "Std. liquid vol. flow"]
                            currentIndex: root.streamObject ? root.streamObject.flowSpecMode : 0
                            enabled: root.canEdit; font.pixelSize: 10
                            onActivated: if (root.streamObject) root.streamObject.flowSpecMode = currentIndex
                        }
                    }
                    Row {
                        spacing: 8; height: parent.height
                        Text { width: 90; text: "Thermo spec"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                        ComboBox {
                            width: 100; height: root.rowH - 2
                            model: ["TP", "PH", "PS", "PVF", "TS"]
                            currentIndex: root.streamObject ? root.streamObject.thermoSpecMode : 0
                            enabled: root.canEdit; font.pixelSize: 10
                            onActivated: if (root.streamObject) root.streamObject.thermoSpecMode = currentIndex
                        }
                    }
                }

                // Editable numeric inputs
                Repeater {
                    model: [
                        { lbl: "Mass flow (kg/h)",      prop: "flowRateKgph",                  fmtFn: "fmt0", editProp: "massFlowEditable" },
                        { lbl: "Molar flow (kmol/h)",   prop: "molarFlowKmolph",               fmtFn: "fmt3", editProp: "molarFlowEditable" },
                        { lbl: "Std. vol. flow (m³/h)", prop: "standardLiquidVolumeFlowM3ph",  fmtFn: "fmt3", editProp: "standardLiquidVolumeFlowEditable" },
                        { lbl: "Temperature (K)",        prop: "temperatureK",                  fmtFn: "fmt3", editProp: "temperatureEditable" },
                        { lbl: "Pressure (bar)",         prop: "_pressureBar",                  fmtFn: "fmt3", editProp: "pressureEditable" },
                        { lbl: "Vapour fraction (-)",    prop: "specifiedVaporFraction",        fmtFn: "fmt4", editProp: "vaporFractionEditable" },
                        { lbl: "Enthalpy (kJ/kg)",       prop: "enthalpyKJkg",                  fmtFn: "fmt3", editProp: "enthalpyEditable" },
                        { lbl: "Entropy (kJ/kg·K)",      prop: "entropyKJkgK",                  fmtFn: "fmt6", editProp: "entropyEditable" },
                    ]

                    Row {
                        spacing: 8; height: root.rowH
                        Text {
                            width: 130; text: modelData.lbl
                            font.pixelSize: 10; color: root.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        TextField {
                            width: 140; height: root.rowH - 4
                            font.pixelSize: 10; selectByMouse: true
                            padding: 2; leftPadding: 4; horizontalAlignment: Text.AlignRight
                            enabled: root.canEdit && !!root.streamObject && !!root.streamObject[modelData.editProp]
                            background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
                            text: {
                                if (!root.streamObject) return ""
                                if (modelData.prop === "_pressureBar")
                                    return (Number(root.streamObject.pressurePa || 0) / 1e5).toFixed(3)
                                const v = root.streamObject[modelData.prop]
                                if (v === undefined || !isFinite(v)) return ""
                                if (modelData.fmtFn === "fmt0") return Number(v).toFixed(0)
                                if (modelData.fmtFn === "fmt3") return Number(v).toFixed(3)
                                if (modelData.fmtFn === "fmt4") return Number(v).toFixed(4)
                                return Number(v).toFixed(6)
                            }
                            onEditingFinished: {
                                if (!root.streamObject) return
                                const n = Number(text)
                                if (isNaN(n)) return
                                if (modelData.prop === "_pressureBar")
                                    root.streamObject.pressurePa = n * 1e5
                                else
                                    root.streamObject[modelData.prop] = n
                            }
                        }
                    }
                }

                // Spec error message
                Text {
                    visible: !!root.streamObject && !!root.streamObject.specificationError
                    text: root.streamObject ? (root.streamObject.specificationError || "") : ""
                    font.pixelSize: 9; color: root.errCol; wrapMode: Text.Wrap
                    width: parent.width
                }

                Item { height: 4 }
            }

            // Dynamic height
            height: {
                let h = 4
                h += root.rowH + 3   // name
                if (root.streamObject && root.streamObject.isCrudeFeed) h += root.rowH + 3  // crude
                h += root.rowH + 3   // flow+thermo
                h += 8 * (root.rowH + 3)  // numeric inputs
                if (root.streamObject && root.streamObject.specificationError) h += 20
                h += 8
                return h
            }
        }



        // No-stream placeholder
        Text {
            anchors.centerIn: parent
            visible: !root.streamObject
            text: "No stream selected"; font.pixelSize: 11; color: root.textMuted
        }
    }
}
