import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  StreamPropertiesPanel — read-only summary using PGrid + gUnits.
//
//  Replaces the 5 stacked SimpleSpreadsheets in the original.  Each cell now
//  uses gUnits.format() so the user can change units without leaving the panel.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    // Per-quantity unit overrides (shared with Conditions if you want; this
    // panel uses its own, but you could pass a parent property in).
    property var unitOverrides: ({})
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) { var c = Object.assign({}, unitOverrides); c[q] = u; unitOverrides = c }

    // ── Stream-stored unit → SI conversion helpers ──
    function _siMass(kgph)        { return kgph / 3600.0 }
    function _siMolar(kmolph)     { return kmolph * 1000.0 / 3600.0 }
    function _siVol(m3ph)         { return m3ph / 3600.0 }
    function _siEnth(kJkg)        { return kJkg * 1000.0 }
    function _siEntr(kJkgK)       { return kJkgK * 1000.0 }
    function _siVisc(cP)          { return cP * 0.001 }
    function _siCriticalP(kPa)    { return kPa * 1000.0 }
    function _siMolarMass(kgkmol) { return kgkmol * 0.001 }   // → kg/mol

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Text {
            anchors.centerIn: parent
            visible: !root.streamObject
            text: "No stream selected"; font.pixelSize: 11; color: "#526571"
        }

        Flickable {
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; bottom: parent.bottom
                topMargin: 0; leftMargin: 4; rightMargin: 4; bottomMargin: 4
            }
            visible: !!root.streamObject
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: 6

                // ════ Stream Summary ════
                PGroupBox {
                    id: sumGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Stream Summary"
                    contentPadding: 8

                    GridLayout {
                        id: sumGrid
                        width: sumGroup.width - (sumGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        // Text rows
                        PGridLabel { Layout.preferredWidth: 128; text: "Fluid package" }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"
                                     textValue: root.streamObject ? (root.streamObject.selectedFluidPackageName
                                                                      || root.streamObject.selectedFluidPackageId
                                                                      || "—") : "—" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Thermo method"; alt: true }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"; alt: true
                                     textValue: root.streamObject ? (root.streamObject.fluidPackageThermoMethod || "—") : "—" }


                        PGridLabel { Layout.preferredWidth: 128; text: "Phase"; alt: true }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"; alt: true
                                     textValue: root.streamObject ? (root.streamObject.phaseStatus || "—") : "—" }

                        // Vapour fraction (numeric, dimensionless)
                        PGridLabel { Layout.preferredWidth: 128; text: "Vapour fraction" }
                        PGridValue { quantity: "VapourFraction"
                                     siValue: root.streamObject ? root.streamObject.vaporFraction : NaN }
                        PGridUnit  { quantity: "Dimensionless" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Thermo region"; alt: true }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"; alt: true
                                     textValue: root.streamObject ? (root.streamObject.thermoRegionLabel || "—") : "—" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Flash method" }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"
                                     textValue: root.streamObject ? (root.streamObject.flashMethod || "—") : "—" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Specification"; alt: true }
                        PGridValue { Layout.columnSpan: 2; isText: true; alignText: "left"; alt: true
                                     textValue: root.streamObject ? (root.streamObject.specificationStatus || "—") : "—" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Molar flow" }
                        PGridValue { quantity: "MolarFlow"
                                     siValue: root.streamObject ? root._siMolar(root.streamObject.molarFlowKmolph) : NaN
                                     displayUnit: root.unitFor("MolarFlow") }
                        PGridUnit  { quantity: "MolarFlow"
                                     siValue: root.streamObject ? root._siMolar(root.streamObject.molarFlowKmolph) : NaN
                                     displayUnit: root.unitFor("MolarFlow")
                                     onUnitOverride: function(u) { root.setUnit("MolarFlow", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Volumetric flow"; alt: true }
                        PGridValue { quantity: "VolumeFlow"; alt: true
                                     siValue: root.streamObject ? root._siVol(root.streamObject.volumetricFlowM3ph) : NaN
                                     displayUnit: root.unitFor("VolumeFlow") }
                        PGridUnit  { quantity: "VolumeFlow"; alt: true
                                     siValue: root.streamObject ? root._siVol(root.streamObject.volumetricFlowM3ph) : NaN
                                     displayUnit: root.unitFor("VolumeFlow")
                                     onUnitOverride: function(u) { root.setUnit("VolumeFlow", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Std. vol. flow" }
                        PGridValue { quantity: "VolumeFlow"
                                     siValue: root.streamObject ? root._siVol(root.streamObject.calcStdVolFlowM3ph) : NaN
                                     displayUnit: root.unitFor("VolumeFlow") }
                        PGridUnit  { quantity: "VolumeFlow"
                                     siValue: root.streamObject ? root._siVol(root.streamObject.calcStdVolFlowM3ph) : NaN
                                     displayUnit: root.unitFor("VolumeFlow")
                                     onUnitOverride: function(u) { root.setUnit("VolumeFlow", u) } }
                    }
                }

                // ════ Molecular & Bulk ════
                PGroupBox {
                    id: molGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Molecular & Bulk"
                    contentPadding: 8

                    GridLayout {
                        id: molGrid
                        width: molGroup.width - (molGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        // Avg MW = mass flow / molar flow.  Compute from raw stream values.
                        PGridLabel { Layout.preferredWidth: 128; text: "Avg. molecular weight" }
                        PGridValue { quantity: "MolarMass"
                                     siValue: {
                                         if (!root.streamObject) return NaN
                                         var mol = root.streamObject.molarFlowKmolph
                                         var m   = root.streamObject.flowRateKgph
                                         if (mol > 0 && m > 0) return root._siMolarMass(m / mol)   // kg/kmol → kg/mol
                                         return NaN
                                     }
                                     displayUnit: root.unitFor("MolarMass") }
                        PGridUnit  { quantity: "MolarMass"; displayUnit: root.unitFor("MolarMass")
                                     onUnitOverride: function(u) { root.setUnit("MolarMass", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Bulk liquid density"; alt: true }
                        PGridValue { quantity: "Density"; alt: true
                                     siValue: root.streamObject ? root.streamObject.liquidDensityKgM3 : NaN
                                     displayUnit: root.unitFor("Density") }
                        PGridUnit  { quantity: "Density"; alt: true; displayUnit: root.unitFor("Density")
                                     onUnitOverride: function(u) { root.setUnit("Density", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Vapour density" }
                        PGridValue { quantity: "Density"
                                     siValue: root.streamObject ? root.streamObject.vapourDensityKgM3 : NaN
                                     displayUnit: root.unitFor("Density") }
                        PGridUnit  { quantity: "Density"; displayUnit: root.unitFor("Density")
                                     onUnitOverride: function(u) { root.setUnit("Density", u) } }

                        // Specific gravity = liq density / 999.  Dimensionless.
                        PGridLabel { Layout.preferredWidth: 128; text: "Specific gravity"; alt: true }
                        PGridValue { quantity: "SpecificGravity"; alt: true
                                     siValue: {
                                         if (!root.streamObject) return NaN
                                         var d = root.streamObject.liquidDensityKgM3
                                         return d > 0 ? d / 999.0 : NaN
                                     } }
                        PGridUnit  { quantity: "Dimensionless"; alt: true }

                        // API gravity = 141.5/SG − 131.5
                        PGridLabel { Layout.preferredWidth: 128; text: "API gravity" }
                        PGridValue { quantity: "APIGravity"
                                     siValue: {
                                         if (!root.streamObject) return NaN
                                         var d = root.streamObject.liquidDensityKgM3
                                         var sg = d > 0 ? d / 999.0 : 0
                                         return sg > 0 ? (141.5 / sg - 131.5) : NaN
                                     } }
                        PGridUnit  { quantity: "APIGravity" }

                        PGridLabel { Layout.preferredWidth: 128; text: "Watson K factor"; alt: true }
                        PGridValue { quantity: "WatsonKFactor"; alt: true
                                     siValue: root.streamObject ? root.streamObject.watsonKFactor : NaN }
                        PGridUnit  { quantity: "Dimensionless"; alt: true }
                    }
                }

                // ════ Thermodynamic Properties ════
                PGroupBox {
                    id: thGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Thermodynamic Properties"
                    contentPadding: 8

                    GridLayout {
                        id: thGrid
                        width: thGroup.width - (thGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: 128; text: "Enthalpy — liquid" }
                        PGridValue { quantity: "SpecificEnthalpy"
                                     siValue: root.streamObject ? root._siEnth(root.streamObject.liquidEnthalpyKJkg) : NaN
                                     displayUnit: root.unitFor("SpecificEnthalpy") }
                        PGridUnit  { quantity: "SpecificEnthalpy"; displayUnit: root.unitFor("SpecificEnthalpy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEnthalpy", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Enthalpy — vapour"; alt: true }
                        PGridValue { quantity: "SpecificEnthalpy"; alt: true
                                     siValue: root.streamObject ? root._siEnth(root.streamObject.vapourEnthalpyKJkg) : NaN
                                     displayUnit: root.unitFor("SpecificEnthalpy") }
                        PGridUnit  { quantity: "SpecificEnthalpy"; alt: true; displayUnit: root.unitFor("SpecificEnthalpy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEnthalpy", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Enthalpy — mixture" }
                        PGridValue { quantity: "SpecificEnthalpy"
                                     siValue: root.streamObject ? root._siEnth(root.streamObject.enthalpyKJkg) : NaN
                                     displayUnit: root.unitFor("SpecificEnthalpy") }
                        PGridUnit  { quantity: "SpecificEnthalpy"; displayUnit: root.unitFor("SpecificEnthalpy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEnthalpy", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Entropy — liquid"; alt: true }
                        PGridValue { quantity: "SpecificEntropy"; alt: true
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.liquidEntropyKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificEntropy") }
                        PGridUnit  { quantity: "SpecificEntropy"; alt: true; displayUnit: root.unitFor("SpecificEntropy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEntropy", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Entropy — vapour" }
                        PGridValue { quantity: "SpecificEntropy"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.vapourEntropyKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificEntropy") }
                        PGridUnit  { quantity: "SpecificEntropy"; displayUnit: root.unitFor("SpecificEntropy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEntropy", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Cp liquid"; alt: true }
                        PGridValue { quantity: "SpecificHeat"; alt: true
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.liquidCpKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificHeat") }
                        PGridUnit  { quantity: "SpecificHeat"; alt: true; displayUnit: root.unitFor("SpecificHeat")
                                     onUnitOverride: function(u) { root.setUnit("SpecificHeat", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Cp vapour" }
                        PGridValue { quantity: "SpecificHeat"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.vapourCpKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificHeat") }
                        PGridUnit  { quantity: "SpecificHeat"; displayUnit: root.unitFor("SpecificHeat")
                                     onUnitOverride: function(u) { root.setUnit("SpecificHeat", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Cp/Cv vapour"; alt: true }
                        PGridValue { quantity: "CpCvRatio"; alt: true
                                     siValue: root.streamObject ? root.streamObject.vapourCpCvRatio : NaN }
                        PGridUnit  { quantity: "Dimensionless"; alt: true }
                    }
                }

                // ════ Transport Properties ════
                PGroupBox {
                    id: trGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Transport Properties"
                    contentPadding: 8

                    GridLayout {
                        id: trGrid
                        width: trGroup.width - (trGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: 128; text: "Viscosity — liquid" }
                        PGridValue { quantity: "Viscosity"
                                     siValue: root.streamObject ? root._siVisc(root.streamObject.liquidViscosityCp) : NaN
                                     displayUnit: root.unitFor("Viscosity") }
                        PGridUnit  { quantity: "Viscosity"; displayUnit: root.unitFor("Viscosity")
                                     onUnitOverride: function(u) { root.setUnit("Viscosity", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Viscosity — vapour"; alt: true }
                        PGridValue { quantity: "Viscosity"; alt: true
                                     siValue: root.streamObject ? root._siVisc(root.streamObject.vapourViscosityCp) : NaN
                                     displayUnit: root.unitFor("Viscosity") }
                        PGridUnit  { quantity: "Viscosity"; alt: true; displayUnit: root.unitFor("Viscosity")
                                     onUnitOverride: function(u) { root.setUnit("Viscosity", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Thermal cond. liquid" }
                        PGridValue { quantity: "ThermalConductivity"
                                     siValue: root.streamObject ? root.streamObject.liquidThermalCondWmK : NaN
                                     displayUnit: root.unitFor("ThermalConductivity") }
                        PGridUnit  { quantity: "ThermalConductivity"; displayUnit: root.unitFor("ThermalConductivity")
                                     onUnitOverride: function(u) { root.setUnit("ThermalConductivity", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Thermal cond. vapour"; alt: true }
                        PGridValue { quantity: "ThermalConductivity"; alt: true
                                     siValue: root.streamObject ? root.streamObject.vapourThermalCondWmK : NaN
                                     displayUnit: root.unitFor("ThermalConductivity") }
                        PGridUnit  { quantity: "ThermalConductivity"; alt: true; displayUnit: root.unitFor("ThermalConductivity")
                                     onUnitOverride: function(u) { root.setUnit("ThermalConductivity", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Surface tension" }
                        PGridValue { quantity: "SurfaceTension"
                                     siValue: root.streamObject ? root.streamObject.surfaceTensionNm : NaN
                                     displayUnit: root.unitFor("SurfaceTension") }
                        PGridUnit  { quantity: "SurfaceTension"; displayUnit: root.unitFor("SurfaceTension")
                                     onUnitOverride: function(u) { root.setUnit("SurfaceTension", u) } }
                    }
                }

                // ════ Phase Envelope ════
                PGroupBox {
                    id: enGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Phase Envelope"
                    contentPadding: 8

                    GridLayout {
                        id: enGrid
                        width: enGroup.width - (enGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: 128; text: "Bubble point" }
                        PGridValue { quantity: "Temperature"
                                     siValue: root.streamObject ? root.streamObject.bubblePointEstimateK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Dew point"; alt: true }
                        PGridValue { quantity: "Temperature"; alt: true
                                     siValue: root.streamObject ? root.streamObject.dewPointEstimateK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; alt: true; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Critical temperature" }
                        PGridValue { quantity: "Temperature"
                                     siValue: root.streamObject ? root.streamObject.criticalTemperatureK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: 128; text: "Critical pressure"; alt: true }
                        PGridValue { quantity: "Pressure"; alt: true
                                     siValue: root.streamObject ? root._siCriticalP(root.streamObject.criticalPressureKPa) : NaN
                                     displayUnit: root.unitFor("Pressure") }
                        PGridUnit  { quantity: "Pressure"; alt: true; displayUnit: root.unitFor("Pressure")
                                     onUnitOverride: function(u) { root.setUnit("Pressure", u) } }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
