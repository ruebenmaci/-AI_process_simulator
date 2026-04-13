import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

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
    readonly property var thermoSpecNames: ["Temperature", "Pressure", "Enthalpy", "Entropy", "Vapour fraction"]

    property string packageStatusText: ""

    function fmt(v, dec) {
        if (v === undefined || v === null) return "—"
        const n = Number(v)
        if (isNaN(n) || !isFinite(n)) return "—"
        return n.toFixed(dec !== undefined ? dec : 3)
    }

    function fluidPackageStatusText() {
        if (root.packageStatusText && root.packageStatusText !== "")
            return root.packageStatusText
        if (!root.streamObject) return ""
        return root.streamObject.fluidPackageStatus || ""
    }

    function refreshPackageStatusText() {
        if (!root.streamObject) {
            root.packageStatusText = ""
            return
        }
        root.packageStatusText = root.streamObject.fluidPackageStatus || ""
    }

    Rectangle {
        anchors.fill: parent
        color: root.bg

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

        Rectangle {
            id: controlStrip
            x: 0; y: panelHeader.height
            width: parent.width
            color: root.bg

            Column {
                x: 6; y: 4; width: parent.width - 12; spacing: 3

                Row {
                    spacing: 8; height: root.rowH

                    Text {
                        width: 130;
                        text: "Name";
                        font.pixelSize: 10;
                        color: root.textMuted;
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextField {
                        width: 320;
                        height: root.rowH - 4
                        text: root.unitObject ? (root.unitObject.name || root.unitObject.id || "") : ""
                        enabled: !!root.streamObject
                        font.pixelSize: 10;
                        selectByMouse: true
                        padding: 2;
                        leftPadding: 4

                        background: Rectangle {
                            color: "white";
                            border.color: "#dfe5ea";
                            border.width: 1
                        }
                        onEditingFinished: {
                            if (!root.unitObject)
                            return
                            let v = text.trim().replace(/\s+/g, "_").replace(/[^A-Za-z0-9_\-.]/g, "")
                            if (v === "")
                                v = root.unitObject.id
                            if (text !== v)
                                text = v
                            root.unitObject.name = v
                        }
                    }
                }

                Column {
                    width: parent.width - 12
                    spacing: 2

                    Row {
                        spacing: 8; height: root.rowH
                        Text { width: 130; text: "Fluid package"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                        ComboBox {
                            id: packageCombo
                            width: 220; height: root.rowH - 2
                            model: root.streamObject ? root.streamObject.availableFluidPackageIds : []
                            enabled: root.canEdit
                            font.pixelSize: 10
                            Component.onCompleted: {
                                if (!root.streamObject || !model) return
                                const i = model.indexOf(root.streamObject.selectedFluidPackageId)
                                if (i >= 0) currentIndex = i
                            }
                            onActivated: if (root.streamObject) root.streamObject.selectedFluidPackageId = model[index]
                            Connections {
                                target: root.streamObject
                                function onSelectedFluidPackageChanged() {
                                    if (!root.streamObject || !packageCombo.model) return
                                    const i = packageCombo.model.indexOf(root.streamObject.selectedFluidPackageId)
                                    if (i >= 0 && packageCombo.currentIndex !== i) packageCombo.currentIndex = i
                                }
                                ignoreUnknownSignals: true
                            }
                        }
                    }

                    Row {
                        spacing: 8; height: root.rowH

                        Text {
                            width: 130;
                            text: "Package thermo method";
                            font.pixelSize: 10;
                            color: root.textMuted;
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            width: 140
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.streamObject.fluidPackageThermoMethod
                            font.pixelSize: 10
                            color: root.textMuted
                        }
                    }

                    Row {
                        spacing: 8; height: root.rowH
                        Text { width: 130; text: "Package Status"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            width: 250
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fluidPackageStatusText()
                            font.pixelSize: 10
                            color: root.streamObject && root.streamObject.fluidPackageValid ? root.textMuted : root.errCol
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    spacing: 8; height: root.rowH
                    Text { width: 130; text: "Thermo specs"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    ComboBox {
                        width: 150; height: root.rowH - 2
                        model: root.thermoSpecNames
                        currentIndex: root.streamObject ? root.streamObject.primaryThermoSpec : 0
                        enabled: root.canEdit
                        font.pixelSize: 10
                        onActivated: if (root.streamObject) root.streamObject.primaryThermoSpec = currentIndex
                    }
                    Text { text: "+"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 10; color: root.textMuted }
                    ComboBox {
                        width: 150; height: root.rowH - 2
                        model: root.thermoSpecNames
                        currentIndex: root.streamObject ? root.streamObject.secondaryThermoSpec : 1
                        enabled: root.canEdit
                        font.pixelSize: 10
                        onActivated: if (root.streamObject) root.streamObject.secondaryThermoSpec = currentIndex
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.streamObject ? root.streamObject.packageSupportMismatchText : ""
                        font.pixelSize: 9
                        color: root.warnCol
                    }
                }


                Row {
                    spacing: 8; height: root.rowH
                    Text { width: 130; text: "Flash mode"; font.pixelSize: 10; color: root.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {
                        width: 100; height: root.rowH - 4
                        color: "#f8fafc"; border.color: "#dfe5ea"; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: root.streamObject ? root.streamObject.inferredFlashSpecLabel : ""
                            font.pixelSize: 10; color: root.calcCol; font.bold: true
                        }
                    }
                }

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
                }

                Repeater {
                    model: [
                        { lbl: "Mass flow (kg/h)",      prop: "flowRateKgph",                  fmt: 0, editProp: "massFlowEditable" },
                        { lbl: "Molar flow (kmol/h)",   prop: "molarFlowKmolph",               fmt: 3, editProp: "molarFlowEditable" },
                        { lbl: "Std. vol. flow (m³/h)", prop: "standardLiquidVolumeFlowM3ph",  fmt: 3, editProp: "standardLiquidVolumeFlowEditable" },
                        { lbl: "Temperature (K)",       prop: "temperatureK",                  fmt: 3, editProp: "temperatureEditable" },
                        { lbl: "Pressure (bar)",        prop: "_pressureBar",                  fmt: 3, editProp: "pressureEditable" },
                        { lbl: "Vapour fraction (-)",   prop: "specifiedVaporFraction",        fmt: 4, editProp: "vaporFractionEditable" },
                        { lbl: "Enthalpy (kJ/kg)",      prop: "enthalpyKJkg",                  fmt: 3, editProp: "enthalpyEditable" },
                        { lbl: "Entropy (kJ/kg·K)",     prop: "entropyKJkgK",                  fmt: 6, editProp: "entropyEditable" }
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
                                return Number(v).toFixed(modelData.fmt)
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
                Item { height: 4 }
            }

            height: {
                let h = 4
                h += root.rowH + 3 // name
                h += (2 * root.rowH) + 5 // fluid package + package status rows
                h += root.rowH + 3 // flow basis
                h += root.rowH + 3 // thermo spec pair
                h += root.rowH + 3 // flash mode
                h += 8 * (root.rowH + 3) // numeric rows
                h += 8
                return h
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.streamObject
            text: "No stream selected"; font.pixelSize: 11; color: root.textMuted
        }

        Connections {
            target: root
            function onStreamObjectChanged() { root.refreshPackageStatusText() }
        }

        Connections {
            target: root.streamObject
            function onDerivedConditionsChanged() { root.refreshPackageStatusText() }
            function onSelectedFluidPackageChanged() { root.refreshPackageStatusText() }
            function onFluidPackageStatusChanged() { root.refreshPackageStatusText() }
            ignoreUnknownSignals: true
        }

        Component.onCompleted: Qt.callLater(root.refreshPackageStatusText)
    }
}
