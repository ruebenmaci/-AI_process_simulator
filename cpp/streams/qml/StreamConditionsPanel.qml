import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common"

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    readonly property bool isProduct: !!streamObject && streamObject.productStream
    readonly property bool canEdit:   !!streamObject && !isProduct
    readonly property var thermoSpecNames:
        ["Temperature", "Pressure", "Enthalpy", "Entropy", "Vapour fraction"]

    // Label column width — matches StreamPropertiesPanel for visual consistency.
    readonly property int labelColWidth: 180

    property var unitOverrides: ({
        "Temperature":      "",
        "Pressure":         "",
        "MassFlow":         "",
        "MolarFlow":        "",
        "VolumeFlow":       "",
        "SpecificEnthalpy": "",
        "SpecificEntropy":  "",
        "Dimensionless":    ""
    })

    function unitFor(q) {
        return unitOverrides[q] !== undefined ? unitOverrides[q] : ""
    }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    function _siMassFlow(kgph)   { return kgph / 3600.0 }
    function _siMolarFlow(kmolph){ return kmolph * 1000.0 / 3600.0 }
    function _siVolFlow(m3ph)    { return m3ph / 3600.0 }
    function _siEnthalpy(kJkg)   { return kJkg * 1000.0 }
    function _siEntropy(kJkgK)   { return kJkgK * 1000.0 }
    function _kgphFromSI(siMassFlow)    { return siMassFlow * 3600.0 }
    function _kmolphFromSI(siMolarFlow) { return siMolarFlow * 3600.0 / 1000.0 }
    function _m3phFromSI(siVolFlow)     { return siVolFlow * 3600.0 }
    function _kJkgFromSI(siH)           { return siH / 1000.0 }
    function _kJkgKFromSI(siS)          { return siS / 1000.0 }

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Text {
            anchors.centerIn: parent
            visible: !root.streamObject
            text: "No stream selected"; font.pixelSize: 11; color: "#526571"
        }

        ScrollView {
            id: scrollArea
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; bottom: parent.bottom
                topMargin: 4; leftMargin: 4; rightMargin: 4; bottomMargin: 4
            }
            visible: !!root.streamObject
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scrollArea.availableWidth
                spacing: 6

                // ── Identification & Fluid Package ────────────────────────
                PGroupBox {
                    id: identBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Identification & Fluid Package"
                    contentPadding: 8

                    GridLayout {
                        id: identGrid
                        width: identBox.width - (identBox.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Name" }
                        PTextField {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            readOnly: !root.streamObject
                            text: root.unitObject ? (root.unitObject.name || root.unitObject.id || "") : ""
                            onEditingFinished: {
                                if (!root.unitObject) return
                                var v = text.trim().replace(/\s+/g, "_").replace(/[^A-Za-z0-9_\-.]/g, "")
                                if (!v.length)
                                    v = root.unitObject.id || "stream"
                                root.unitObject.name = v
                                text = v
                            }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Fluid package"; alt: true }
                        PComboBox {
                            id: packageCombo
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            widthMode: "fill"
                            model: root.streamObject ? root.streamObject.availableFluidPackageIds : []
                            enabled: root.canEdit
                            currentIndex: {
                                if (!root.streamObject || !model) return -1
                                var i = model.indexOf(root.streamObject.selectedFluidPackageId)
                                return i >= 0 ? i : -1
                            }
                            onActivated: function(index) {
                                if (root.streamObject) root.streamObject.selectedFluidPackageId = model[index]
                            }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Package thermo method" }
                        PGridValue {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            isText: true
                            textValue: root.streamObject ? root.streamObject.fluidPackageThermoMethod : ""
                            alignText: "left"
                        }
                    }
                }

                // ── Thermodynamic Specifications ──────────────────────────
                PGroupBox {
                    id: thermoBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Thermodynamic Specifications"
                    contentPadding: 8

                    GridLayout {
                        id: thermoGrid
                        width: thermoBox.width - (thermoBox.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Thermo specs (primary)" }
                        PComboBox {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            widthMode: "fill"
                            model: root.thermoSpecNames
                            currentIndex: root.streamObject ? root.streamObject.primaryThermoSpec : 0
                            enabled: root.canEdit
                            onActivated: function(index) { if (root.streamObject) root.streamObject.primaryThermoSpec = index }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Thermo specs (secondary)"; alt: true }
                        PComboBox {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            widthMode: "fill"
                            model: root.thermoSpecNames
                            currentIndex: root.streamObject ? root.streamObject.secondaryThermoSpec : 1
                            enabled: root.canEdit
                            onActivated: function(index) { if (root.streamObject) root.streamObject.secondaryThermoSpec = index }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Flash mode" }
                        PGridValue {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            isText: true
                            textValue: root.streamObject ? root.streamObject.inferredFlashSpecLabel : ""
                            alignText: "left"
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Flow basis"; alt: true }
                        PComboBox {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            widthMode: "fill"
                            model: ["Mass flow", "Molar flow", "Std. liquid vol. flow"]
                            currentIndex: root.streamObject ? root.streamObject.flowSpecMode : 0
                            enabled: root.canEdit
                            onActivated: function(index) { if (root.streamObject) root.streamObject.flowSpecMode = index }
                        }
                    }
                }

                // ── Conditions ───────────────────────────────────────────
                // Reorganized from the previous 6-column dual layout into a
                // 3-column (label | value | unit) layout matching the
                // StreamPropertiesPanel pattern, so all three groupboxes on
                // this panel have a consistent visual structure and fill
                // the available width.
                PGroupBox {
                    id: conditionsBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Conditions"
                    contentPadding: 8

                    GridLayout {
                        id: condGrid
                        width: conditionsBox.width - (conditionsBox.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Mass flow" }
                        PGridValue {
                            quantity: "MassFlow"
                            siValue: root.streamObject ? root._siMassFlow(root.streamObject.flowRateKgph) : NaN
                            displayUnit: root.unitFor("MassFlow")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.massFlowEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.flowRateKgph = root._kgphFromSI(siVal) }
                        }
                        PGridUnit {
                            quantity: "MassFlow"
                            siValue: root.streamObject ? root._siMassFlow(root.streamObject.flowRateKgph) : NaN
                            displayUnit: root.unitFor("MassFlow")
                            onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Molar flow"; alt: true }
                        PGridValue {
                            alt: true
                            quantity: "MolarFlow"
                            siValue: root.streamObject ? root._siMolarFlow(root.streamObject.molarFlowKmolph) : NaN
                            displayUnit: root.unitFor("MolarFlow")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.molarFlowEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.molarFlowKmolph = root._kmolphFromSI(siVal) }
                        }
                        PGridUnit {
                            alt: true
                            quantity: "MolarFlow"
                            siValue: root.streamObject ? root._siMolarFlow(root.streamObject.molarFlowKmolph) : NaN
                            displayUnit: root.unitFor("MolarFlow")
                            onUnitOverride: function(u) { root.setUnit("MolarFlow", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Std. liq. vol." }
                        PGridValue {
                            quantity: "VolumeFlow"
                            siValue: root.streamObject ? root._siVolFlow(root.streamObject.standardLiquidVolumeFlowM3ph) : NaN
                            displayUnit: root.unitFor("VolumeFlow")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.standardLiquidVolumeFlowEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.standardLiquidVolumeFlowM3ph = root._m3phFromSI(siVal) }
                        }
                        PGridUnit {
                            quantity: "VolumeFlow"
                            siValue: root.streamObject ? root._siVolFlow(root.streamObject.standardLiquidVolumeFlowM3ph) : NaN
                            displayUnit: root.unitFor("VolumeFlow")
                            onUnitOverride: function(u) { root.setUnit("VolumeFlow", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Temperature"; alt: true }
                        PGridValue {
                            alt: true
                            quantity: "Temperature"
                            siValue: root.streamObject ? root.streamObject.temperatureK : NaN
                            displayUnit: root.unitFor("Temperature")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.temperatureEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.temperatureK = siVal }
                        }
                        PGridUnit {
                            alt: true
                            quantity: "Temperature"
                            siValue: root.streamObject ? root.streamObject.temperatureK : NaN
                            displayUnit: root.unitFor("Temperature")
                            onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Pressure" }
                        PGridValue {
                            quantity: "Pressure"
                            siValue: root.streamObject ? root.streamObject.pressurePa : NaN
                            displayUnit: root.unitFor("Pressure")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.pressureEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.pressurePa = siVal }
                        }
                        PGridUnit {
                            quantity: "Pressure"
                            siValue: root.streamObject ? root.streamObject.pressurePa : NaN
                            displayUnit: root.unitFor("Pressure")
                            onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Vap. fraction"; alt: true }
                        PGridValue {
                            alt: true
                            quantity: "VapourFraction"
                            siValue: root.streamObject ? root.streamObject.specifiedVaporFraction : NaN
                            editable: root.canEdit && !!root.streamObject && root.streamObject.vaporFractionEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.specifiedVaporFraction = siVal }
                        }
                        PGridUnit { alt: true; quantity: "Dimensionless" }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Enthalpy" }
                        PGridValue {
                            quantity: "SpecificEnthalpy"
                            siValue: root.streamObject ? root._siEnthalpy(root.streamObject.enthalpyKJkg) : NaN
                            displayUnit: root.unitFor("SpecificEnthalpy")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.enthalpyEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.enthalpyKJkg = root._kJkgFromSI(siVal) }
                        }
                        PGridUnit {
                            quantity: "SpecificEnthalpy"
                            siValue: root.streamObject ? root._siEnthalpy(root.streamObject.enthalpyKJkg) : NaN
                            displayUnit: root.unitFor("SpecificEnthalpy")
                            onUnitOverride: function(u) { root.setUnit("SpecificEnthalpy", u) }
                        }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Entropy"; alt: true }
                        PGridValue {
                            alt: true
                            quantity: "SpecificEntropy"
                            siValue: root.streamObject ? root._siEntropy(root.streamObject.entropyKJkgK) : NaN
                            displayUnit: root.unitFor("SpecificEntropy")
                            editable: root.canEdit && !!root.streamObject && root.streamObject.entropyEditable
                            onEdited: function(siVal) { if (root.streamObject) root.streamObject.entropyKJkgK = root._kJkgKFromSI(siVal) }
                        }
                        PGridUnit {
                            alt: true
                            quantity: "SpecificEntropy"
                            siValue: root.streamObject ? root._siEntropy(root.streamObject.entropyKJkgK) : NaN
                            displayUnit: root.unitFor("SpecificEntropy")
                            onUnitOverride: function(u) { root.setUnit("SpecificEntropy", u) }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
