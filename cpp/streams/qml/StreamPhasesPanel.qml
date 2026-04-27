import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  StreamPhasesPanel — HYSYS-style 3-column phase comparison.
//
//  Column layout:  [label]  [liquid]  [vapour]  [unit ▾]
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var streamObject: null
    property var unitObject:   null

    // ── Layout constants ──────────────────────────────────────────────────
    // Single source of truth for the label column width. Sized to fit the
    // longest label string in this panel's vocabulary at 11 px Segoe UI
    // (e.g. "Thermal conductivity").
    readonly property int labelColWidth: 148

    property var unitOverrides: ({})
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) { var c = Object.assign({}, unitOverrides); c[q] = u; unitOverrides = c }

    function _siMass(kgph)        { return kgph / 3600.0 }
    function _siMolar(kmolph)     { return kmolph * 1000.0 / 3600.0 }
    function _siVol(m3ph)         { return m3ph / 3600.0 }
    function _siEnth(kJkg)        { return kJkg * 1000.0 }
    function _siEntr(kJkgK)       { return kJkgK * 1000.0 }
    function _siVisc(cP)          { return cP * 0.001 }
    function _siCriticalP(kPa)    { return kPa * 1000.0 }

    // Helper: format a K value safely (avoids parent.parent chains in delegates)
    function _fmtK(k) {
        if (k === undefined || !isFinite(k) || k < 0) return "—"
        return k.toFixed(4)
    }

    readonly property real vf: streamObject ? streamObject.vaporFraction : 0
    readonly property real lf: 1.0 - vf
    readonly property string phase: streamObject ? streamObject.phaseStatus : "—"

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Text { anchors.centerIn: parent; visible: !root.streamObject
               text: "No stream selected"; font.pixelSize: 11; color: "#526571" }

        ScrollView {
            id: phasesScroll
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; bottom: parent.bottom
                topMargin: 4; leftMargin: 4; rightMargin: 4; bottomMargin: 4
            }
            visible: !!root.streamObject; clip: true

            ColumnLayout {
                width: Math.min(parent.width - 8, 760)
                spacing: 6

                // ── Phase status banner ──
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 24
                    color: root.phase === "Liquid"    ? "#dbeafe"
                         : root.phase === "Vapor"     ? "#fef9c3"
                         : root.phase === "Two-Phase" ? "#dcfce7" : "#e8ebef"
                    border.color: "#97a2ad"; border.width: 1
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Phase:  " + root.phase
                              + "     |     Vapour fraction:  " + (root.streamObject ? Number(root.vf).toFixed(4) : "—")
                              + "     |     " + (root.streamObject ? root.streamObject.thermoRegionLabel : "—")
                        font.pixelSize: 11; font.bold: true; color: "#1f2a34"
                    }
                }

                // ── Per-phase comparison: Liquid + Vapour columns ──
                PGroupBox {
                    id: compGroup
                    Layout.fillWidth: true
                    Layout.preferredWidth: 500
                    Layout.preferredHeight: implicitHeight
                    caption: "Per-Phase Properties"
                    contentPadding: 8

                    // Sub-header row (column titles) — direct child of PGroupBox
                    Rectangle {
                        id: compHeader
                        width: compGroup.width - (compGroup.contentPadding * 2) - 2
                        y: 0
                        height: 22; color: "#c8d0d8"
                        Row {
                            anchors.fill: parent
                            Item { width: 148; height: parent.height
                                Text { anchors.left: parent.left; anchors.leftMargin: 6
                                       anchors.verticalCenter: parent.verticalCenter
                                       text: "Property"; font.pixelSize: 11; font.bold: true; color: "#1f2a34" }
                            }
                            Rectangle { width: parent.width - 148 - 72; height: parent.height
                                color: "transparent"
                                Row {
                                    anchors.fill: parent
                                    Item { width: parent.width / 2; height: parent.height
                                        Rectangle { anchors.fill: parent; color: "#dbeafe"; border.color: "#97a2ad"; border.width: 1 }
                                        Text { anchors.centerIn: parent; text: "Liquid"; font.pixelSize: 11; font.bold: true; color: "#1f2a34" }
                                    }
                                    Item { width: parent.width / 2; height: parent.height
                                        Rectangle { anchors.fill: parent; color: "#fef9c3"; border.color: "#97a2ad"; border.width: 1 }
                                        Text { anchors.centerIn: parent; text: "Vapour"; font.pixelSize: 11; font.bold: true; color: "#1f2a34" }
                                    }
                                }
                            }
                            Item { width: 72; height: parent.height
                                Rectangle { anchors.fill: parent; color: "#c8d0d8"; border.color: "#97a2ad"; border.width: 1 }
                                Text { anchors.centerIn: parent; text: "Unit"; font.pixelSize: 11; font.bold: true; color: "#1f2a34" }
                            }
                        }
                    }

                    GridLayout {
                        id: cmpGrid
                        width: compGroup.width - (compGroup.contentPadding * 2) - 2
                        y: compHeader.height
                        columns: 4; columnSpacing: 0; rowSpacing: 0

                        // ── Density ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Density" }
                        PGridValue { quantity: "Density"; alignText: "center"
                                     siValue: root.streamObject ? root.streamObject.liquidDensityKgM3 : NaN
                                     displayUnit: root.unitFor("Density") }
                        PGridValue { quantity: "Density"; alignText: "center"
                                     siValue: root.streamObject ? root.streamObject.vapourDensityKgM3 : NaN
                                     displayUnit: root.unitFor("Density") }
                        PGridUnit  { quantity: "Density"; displayUnit: root.unitFor("Density")
                                     onUnitOverride: function(u) { root.setUnit("Density", u) } }

                        // ── Viscosity ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Viscosity"; alt: true }
                        PGridValue { quantity: "Viscosity"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siVisc(root.streamObject.liquidViscosityCp) : NaN
                                     displayUnit: root.unitFor("Viscosity") }
                        PGridValue { quantity: "Viscosity"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siVisc(root.streamObject.vapourViscosityCp) : NaN
                                     displayUnit: root.unitFor("Viscosity") }
                        PGridUnit  { quantity: "Viscosity"; alt: true; displayUnit: root.unitFor("Viscosity")
                                     onUnitOverride: function(u) { root.setUnit("Viscosity", u) } }

                        // ── Thermal conductivity ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Thermal conductivity" }
                        PGridValue { quantity: "ThermalConductivity"; alignText: "center"
                                     siValue: root.streamObject ? root.streamObject.liquidThermalCondWmK : NaN
                                     displayUnit: root.unitFor("ThermalConductivity") }
                        PGridValue { quantity: "ThermalConductivity"; alignText: "center"
                                     siValue: root.streamObject ? root.streamObject.vapourThermalCondWmK : NaN
                                     displayUnit: root.unitFor("ThermalConductivity") }
                        PGridUnit  { quantity: "ThermalConductivity"; displayUnit: root.unitFor("ThermalConductivity")
                                     onUnitOverride: function(u) { root.setUnit("ThermalConductivity", u) } }

                        // ── Cp ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Heat capacity Cp"; alt: true }
                        PGridValue { quantity: "SpecificHeat"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.liquidCpKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificHeat") }
                        PGridValue { quantity: "SpecificHeat"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.vapourCpKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificHeat") }
                        PGridUnit  { quantity: "SpecificHeat"; alt: true; displayUnit: root.unitFor("SpecificHeat")
                                     onUnitOverride: function(u) { root.setUnit("SpecificHeat", u) } }

                        // ── Enthalpy ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Enthalpy" }
                        PGridValue { quantity: "SpecificEnthalpy"; alignText: "center"
                                     siValue: root.streamObject ? root._siEnth(root.streamObject.liquidEnthalpyKJkg) : NaN
                                     displayUnit: root.unitFor("SpecificEnthalpy") }
                        PGridValue { quantity: "SpecificEnthalpy"; alignText: "center"
                                     siValue: root.streamObject ? root._siEnth(root.streamObject.vapourEnthalpyKJkg) : NaN
                                     displayUnit: root.unitFor("SpecificEnthalpy") }
                        PGridUnit  { quantity: "SpecificEnthalpy"; displayUnit: root.unitFor("SpecificEnthalpy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEnthalpy", u) } }

                        // ── Entropy ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Entropy"; alt: true }
                        PGridValue { quantity: "SpecificEntropy"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.liquidEntropyKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificEntropy") }
                        PGridValue { quantity: "SpecificEntropy"; alt: true; alignText: "center"
                                     siValue: root.streamObject ? root._siEntr(root.streamObject.vapourEntropyKJkgK) : NaN
                                     displayUnit: root.unitFor("SpecificEntropy") }
                        PGridUnit  { quantity: "SpecificEntropy"; alt: true; displayUnit: root.unitFor("SpecificEntropy")
                                     onUnitOverride: function(u) { root.setUnit("SpecificEntropy", u) } }

                        // ── Surface tension (only liquid; vapour is "—") ──
                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Surface tension" }
                        PGridValue { quantity: "SurfaceTension"; alignText: "center"
                                     siValue: root.streamObject ? root.streamObject.surfaceTensionNm : NaN
                                     displayUnit: root.unitFor("SurfaceTension") }
                        PGridValue { quantity: "SurfaceTension"; alignText: "center"
                                     isText: true; textValue: "—"; valueColor: "#aaaaaa" }
                        PGridUnit  { quantity: "SurfaceTension"; displayUnit: root.unitFor("SurfaceTension")
                                     onUnitOverride: function(u) { root.setUnit("SurfaceTension", u) } }
                    }
                }

                // ── Phase envelope ──
                PGroupBox {
                    id: envGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Phase Envelope"
                    contentPadding: 8

                    GridLayout {
                        id: envGrid
                        width: envGroup.width - (envGroup.contentPadding * 2) - 2
                        columns: 3; columnSpacing: 0; rowSpacing: 0

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Bubble point" }
                        PGridValue { quantity: "Temperature"
                                     siValue: root.streamObject ? root.streamObject.bubblePointEstimateK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Dew point"; alt: true }
                        PGridValue { quantity: "Temperature"; alt: true
                                     siValue: root.streamObject ? root.streamObject.dewPointEstimateK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; alt: true; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Critical temperature" }
                        PGridValue { quantity: "Temperature"
                                     siValue: root.streamObject ? root.streamObject.criticalTemperatureK : NaN
                                     displayUnit: root.unitFor("Temperature") }
                        PGridUnit  { quantity: "Temperature"; displayUnit: root.unitFor("Temperature")
                                     onUnitOverride: function(u) { root.setUnit("Temperature", u) } }

                        PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Critical pressure"; alt: true }
                        PGridValue { quantity: "Pressure"; alt: true
                                     siValue: root.streamObject ? root._siCriticalP(root.streamObject.criticalPressureKPa) : NaN
                                     displayUnit: root.unitFor("Pressure") }
                        PGridUnit  { quantity: "Pressure"; alt: true; displayUnit: root.unitFor("Pressure")
                                     onUnitOverride: function(u) { root.setUnit("Pressure", u) } }
                    }
                }

                // ── K-values spreadsheet (Composition-panel style) ──
                PGroupBox {
                    id: kGroup
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Equilibrium K-values  (y / x per component)"
                    contentPadding: 8

                    ColumnLayout {
                        width: kGroup.width - (kGroup.contentPadding * 2) - 2
                        spacing: 4

                        Rectangle {
                            id: kWarning
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 22 : 0
                            visible: root.vf <= 0.0001 || root.vf >= 0.9999
                            color: "#fff4db"; border.color: "#d19a1c"; border.width: 1
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "K-values are only meaningful in the two-phase region.  Current phase: " + root.phase
                            color: "#744f00"; font.pixelSize: 11
                        }
                    }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: kSheet.implicitHeight
                            clip: true

                            PSpreadsheet {
                                id: kSheet
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: implicitHeight

                            readOnly: true
                            readOnlyCols: [0, 1, 2]
                            numericOnlyCells: false
                            alternatingRows: true
                            stretchToWidth: true
                            verticalScrollBarPolicy: ScrollBar.AlwaysOff
                            horizontalScrollBarPolicy: ScrollBar.AlwaysOff
                            cornerLabel: "Component"
                            numCols: 3
                            numRows: 0
                            colLabels: ["x  (liquid)", "y  (vapour)", "K = y/x"]
                            defaultColW: 88

                            function refresh() {
                                var rows = (root.vf > 0.0001 && root.vf < 0.9999 && root.streamObject)
                                           ? root.streamObject.kValuesData : []
                                numRows = rows ? rows.length : 0
                                rowLabels = []
                                clearAll()
                                if (!rows || rows.length === 0)
                                    return

                                var labels = []
                                for (var r = 0; r < rows.length; ++r) {
                                    var row = rows[r] || ({})
                                    labels.push(row["name"] || "")
                                    setCell(r, 0, row["x"] !== undefined ? Number(row["x"]).toFixed(5) : "—")
                                    setCell(r, 1, row["y"] !== undefined ? Number(row["y"]).toFixed(5) : "—")
                                    setCell(r, 2, root._fmtK(row["K"]))
                                }
                                rowLabels = labels
                                Qt.callLater(function() { kSheet.fitToWidth() })
                            }

                            onWheelPassthrough: function(deltaY, deltaX) {
                                var outer = phasesScroll.contentItem
                                if (!outer || outer.contentY === undefined)
                                    return
                                var step = 60
                                if (deltaY !== 0) {
                                    var maxY = Math.max(0, outer.contentHeight - outer.height)
                                    var nextY = outer.contentY - (deltaY / 120) * step
                                    outer.contentY = Math.max(0, Math.min(nextY, maxY))
                                }
                                if (deltaX !== 0 && outer.contentX !== undefined) {
                                    var maxX = Math.max(0, outer.contentWidth - outer.width)
                                    var nextX = outer.contentX - (deltaX / 120) * step
                                    outer.contentX = Math.max(0, Math.min(nextX, maxX))
                                }
                            }

                            Component.onCompleted: Qt.callLater(refresh)
                            Connections {
                                target: root
                                function onStreamObjectChanged()       { Qt.callLater(kSheet.refresh) }
                                function onVfChanged()                  { Qt.callLater(kSheet.refresh) }
                            }
                            Connections {
                                target: root.streamObject
                                ignoreUnknownSignals: true
                                function onDerivedConditionsChanged() { Qt.callLater(kSheet.refresh) }
                            }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
