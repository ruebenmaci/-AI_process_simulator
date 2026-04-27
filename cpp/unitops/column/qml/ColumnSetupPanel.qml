import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnSetupPanel.qml — first sub-tab of the column workspace.
//
//  Six PGroupBox sections arranged in two columns:
//
//    ┌─ General Setup ──┐  ┌─ Condenser ──────┐
//    │                  │  │                  │
//    └──────────────────┘  └──────────────────┘
//    ┌─ Murphree Effs. ─┐  ┌─ Reboiler ───────┐
//    │                  │  │                  │
//    └──────────────────┘  └──────────────────┘
//    ┌─ Solver Conv.   ─┐  ┌─ Thermodynamics ─┐
//    │                  │  │                  │
//    └──────────────────┘  └──────────────────┘
//
//  All controls are P-controls. Numeric quantities go through PGridValue with
//  a `quantity` tag so they pick up the active unit set automatically.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    readonly property int labelColWidth: 170

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _safeName() {
        if (!appState) return ""
        return appState.name || appState.id || ""
    }
    function _feedStreamName() {
        if (!appState) return "—"
        return appState.connectedFeedStreamName || "—"
    }
    function _feedFluidName() {
        if (!appState || !appState.feedStream) return "—"
        var pkgName = appState.feedStream.selectedFluidPackageName
        if (pkgName && pkgName !== "") return pkgName
        var fluid = appState.feedStream.selectedFluid
        if (fluid && fluid !== "") return fluid
        return "—"
    }

    // ── Solve / Status helpers (moved from ColumnDrawsPanel when the
    //    Solve / Status block migrated from the Draws tab to here) ────────────
    function _solveStatus() {
        if (!appState) return "—"
        if (appState.solving)    return "Solving…"
        if (appState.solved)     return "Converged"
        if (appState.specsDirty) return "Specs changed – re-run"
        return "Not solved"
    }
    function _solveStatusColor() {
        if (!appState)           return "#526571"
        if (appState.solving)    return "#d6b74a"
        if (appState.solved)     return "#1a7a3c"
        if (appState.specsDirty) return "#d6b74a"
        return "#b23b3b"
    }
    function _fmtMs(ms) {
        var s = Math.floor((ms || 0) / 1000)
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    function _fmt3(x)  { var n = Number(x); return isFinite(n) ? n.toFixed(3) : "—" }

    // ── Per-quantity display unit overrides ────────────────────────────────
    // Mirrors the pattern used in FluidManagerView and ComponentManagerView:
    // when the user clicks a PGridUnit picker on any cell, the chosen unit
    // is stashed here keyed by quantity. Every PGridValue and PGridUnit on
    // this panel binds its `displayUnit` to `unitFor(quantity)` and every
    // PGridUnit emits `onUnitOverride` back into `setUnit(quantity, u)`.
    //
    // The result: picking, say, "°F" on one Temperature cell instantly
    // re-renders every Temperature cell in this panel in °F — the
    // underlying SI value is unchanged, only the display unit flips.
    // Empty string ("") means "fall back to the active Unit Set default".
    property var unitOverrides: ({
        "Temperature": "",
        "Pressure":    "",
        "MassFlow":    "",
        "Power":       ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        // Object.assign is required so QML's reactivity sees a property
        // change. Mutating unitOverrides[q] directly would not fire the
        // unitOverridesChanged signal and the bindings would not update.
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Text {
            anchors.centerIn: parent
            visible: !root.appState
            text: "No column selected"; font.pixelSize: 11; color: "#526571"
        }

        ScrollView {
            id: scrollArea
            anchors {
                left: parent.left; right: parent.right
                top: parent.top;   bottom: parent.bottom
                topMargin: 4; leftMargin: 4; rightMargin: 4; bottomMargin: 4
            }
            visible: !!root.appState
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scrollArea.availableWidth
                spacing: 6

                // ── Row 1: General Setup | Condenser ────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // ── General Setup ───────────────────────────────────────
                    PGroupBox {
                        id: generalBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "General Setup"
                        contentPadding: 8

                        GridLayout {
                            id: generalGrid
                            width: generalBox.width - (generalBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // Column Name
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Column Name" }
                            PTextField {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                text: root._safeName()
                                onEditingFinished: { if (root.appState) root.appState.name = text }
                            }

                            // Feed Stream (read-only display)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed Stream"; alt: true }
                            PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alt: true
                                alignText: "left"
                                textValue: root._feedStreamName()
                            }

                            // Feed fluid (read-only display)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed fluid" }
                            PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root._feedFluidName()
                            }

                            // Total Trays
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Total Trays"; alt: true }
                            PSpinner {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                from: root.appState ? root.appState.minTrays : 1
                                to:   root.appState ? root.appState.maxTrays : 200
                                value: root.appState ? root.appState.trays : 32
                                onEdited: function(v) { if (root.appState) root.appState.trays = v }
                            }

                            // Feed Tray
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed Tray" }
                            PSpinner {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                from: 1
                                to:   root.appState ? Math.max(1, root.appState.trays) : 32
                                value: root.appState ? root.appState.feedTray : 4
                                onEdited: function(v) { if (root.appState) root.appState.feedTray = v }
                            }

                            // Feed Rate (mass flow)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed Rate"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "MassFlow"
                                // The appState exposes flowRateKgph (kg/h) on feedStream;
                                // gUnits expects SI kg/s for MassFlow, so divide by 3600.
                                siValue: (root.appState && root.appState.feedStream)
                                         ? Number(root.appState.feedStream.flowRateKgph) / 3600.0 : NaN
                                editable: true
                                onEdited: function(siVal) {
                                    if (root.appState && root.appState.feedStream)
                                        root.appState.feedStream.flowRateKgph = siVal * 3600.0
                                }
                                displayUnit: root.unitFor("MassFlow")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "MassFlow"
                                siValue: (root.appState && root.appState.feedStream)
                                         ? Number(root.appState.feedStream.flowRateKgph) / 3600.0 : NaN
                                displayUnit: root.unitFor("MassFlow")
                                onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                            }

                            // Feed Temperature
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Feed Temperature" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.feedStream)
                                         ? Number(root.appState.feedStream.temperatureK) : NaN
                                editable: true
                                onEdited: function(siVal) {
                                    if (root.appState && root.appState.feedStream)
                                        root.appState.feedStream.temperatureK = siVal
                                }
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: (root.appState && root.appState.feedStream)
                                         ? Number(root.appState.feedStream.temperatureK) : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // Top Pressure
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Top Pressure"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Pressure"
                                siValue: root.appState ? Number(root.appState.topPressurePa) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.topPressurePa = siVal }
                                displayUnit: root.unitFor("Pressure")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Pressure"
                                siValue: root.appState ? Number(root.appState.topPressurePa) : NaN
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            // Pressure Drop / Tray
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Pressure Drop / Tray" }
                            PGridValue {
                                quantity: "Pressure"
                                siValue: root.appState ? Number(root.appState.dpPerTrayPa) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.dpPerTrayPa = siVal }
                                displayUnit: root.unitFor("Pressure")
                            }
                            PGridUnit {
                                quantity: "Pressure"
                                siValue: root.appState ? Number(root.appState.dpPerTrayPa) : NaN
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            // T Overhead (spec)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Overhead (spec)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.topTsetK) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.topTsetK = siVal }
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.topTsetK) : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // T Bottoms (spec)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Bottoms (spec)" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.bottomTsetK) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.bottomTsetK = siVal }
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.bottomTsetK) : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }
                        }
                    }

                    // ── Condenser ───────────────────────────────────────────
                    PGroupBox {
                        id: condBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Condenser"
                        contentPadding: 8

                        GridLayout {
                            id: condGrid
                            width: condBox.width - (condBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // Condenser Type
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Condenser Type" }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["total", "partial"]
                                currentIndex: root.appState
                                              ? (root.appState.condenserType === "partial" ? 1 : 0)
                                              : 0
                                onActivated: function(index) {
                                    if (root.appState) root.appState.condenserType = model[index]
                                }
                            }

                            // Spec Type
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Spec Type"; alt: true }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["reflux", "duty", "temperature"]
                                currentIndex: {
                                    if (!root.appState) return 0
                                    var s = String(root.appState.condenserSpec || "").toLowerCase()
                                    if (s === "refluxratio" || s === "reflux") return 0
                                    if (s === "duty") return 1
                                    if (s === "temperature") return 2
                                    return 0
                                }
                                onActivated: function(index) {
                                    if (root.appState) root.appState.condenserSpec = model[index]
                                }
                            }

                            // Reflux Ratio
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reflux Ratio" }
                            PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                quantity: "Dimensionless"
                                siValue: root.appState ? Number(root.appState.refluxRatio) : NaN
                                decimals: 3
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.refluxRatio = siVal }
                            }

                            // Fixed Duty (qcKW — appState exposes kW directly)
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Fixed Duty"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Power"
                                // Convert kW → SI W
                                siValue: root.appState ? Number(root.appState.qcKW) * 1000.0 : NaN
                                editable: true
                                onEdited: function(siVal) {
                                    if (root.appState) root.appState.qcKW = siVal / 1000.0
                                }
                                displayUnit: root.unitFor("Power")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Power"
                                siValue: root.appState ? Number(root.appState.qcKW) * 1000.0 : NaN
                                displayUnit: root.unitFor("Power")
                                onUnitOverride: function(u) { root.setUnit("Power", u) }
                            }

                            // T Setpoint
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Setpoint" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.topTsetK) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.topTsetK = siVal }
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.topTsetK) : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }
                        }
                    }
                } // Row 1

                // ── Row 2: Murphree Efficiencies | Reboiler ────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // ── Murphree Efficiencies ───────────────────────────────
                    PGroupBox {
                        id: effBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Murphree Efficiencies"
                        contentPadding: 8

                        GridLayout {
                            id: effGrid
                            width: effBox.width - (effBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // Enable Liquid η
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Enable Liquid η" }
                            PCheckBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                checked: root.appState ? root.appState.enableEtaL : false
                                onToggled: { if (root.appState) root.appState.enableEtaL = checked }
                            }

                            // Top
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Top  (η-V / η-L)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaVTop) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.etaVTop = siVal }
                            }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaLTop) : NaN
                                editable: root.appState ? root.appState.enableEtaL : false
                                onEdited: function(siVal) { if (root.appState) root.appState.etaLTop = siVal }
                            }

                            // Middle
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Middle  (η-V / η-L)" }
                            PGridValue {
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaVMid) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.etaVMid = siVal }
                            }
                            PGridValue {
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaLMid) : NaN
                                editable: root.appState ? root.appState.enableEtaL : false
                                onEdited: function(siVal) { if (root.appState) root.appState.etaLMid = siVal }
                            }

                            // Bottom
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Bottom  (η-V / η-L)"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaVBot) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.etaVBot = siVal }
                            }
                            PGridValue {
                                alt: true
                                quantity: "Dimensionless"
                                decimals: 3
                                siValue: root.appState ? Number(root.appState.etaLBot) : NaN
                                editable: root.appState ? root.appState.enableEtaL : false
                                onEdited: function(siVal) { if (root.appState) root.appState.etaLBot = siVal }
                            }
                        }
                    }

                    // ── Reboiler ────────────────────────────────────────────
                    PGroupBox {
                        id: rebBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Reboiler"
                        contentPadding: 8

                        GridLayout {
                            id: rebGrid
                            width: rebBox.width - (rebBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // Reboiler Type
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reboiler Type" }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["partial", "total"]
                                currentIndex: root.appState
                                              ? (root.appState.reboilerType === "total" ? 1 : 0)
                                              : 0
                                onActivated: function(index) {
                                    if (root.appState) root.appState.reboilerType = model[index]
                                }
                            }

                            // Spec Type
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Spec Type"; alt: true }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["boilup", "duty", "temperature"]
                                currentIndex: {
                                    if (!root.appState) return 0
                                    var s = String(root.appState.reboilerSpec || "").toLowerCase()
                                    if (s === "boilup" || s === "boilupratio") return 0
                                    if (s === "duty") return 1
                                    if (s === "temperature") return 2
                                    return 0
                                }
                                onActivated: function(index) {
                                    if (root.appState) root.appState.reboilerSpec = model[index]
                                }
                            }

                            // Boilup Ratio
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Boilup Ratio" }
                            PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                quantity: "Dimensionless"
                                siValue: root.appState ? Number(root.appState.boilupRatio) : NaN
                                decimals: 3
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.boilupRatio = siVal }
                            }

                            // Fixed Duty
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Fixed Duty"; alt: true }
                            PGridValue {
                                alt: true
                                quantity: "Power"
                                siValue: root.appState ? Number(root.appState.qrKW) * 1000.0 : NaN
                                editable: true
                                onEdited: function(siVal) {
                                    if (root.appState) root.appState.qrKW = siVal / 1000.0
                                }
                                displayUnit: root.unitFor("Power")
                            }
                            PGridUnit {
                                alt: true
                                quantity: "Power"
                                siValue: root.appState ? Number(root.appState.qrKW) * 1000.0 : NaN
                                displayUnit: root.unitFor("Power")
                                onUnitOverride: function(u) { root.setUnit("Power", u) }
                            }

                            // T Setpoint
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Setpoint" }
                            PGridValue {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.bottomTsetK) : NaN
                                editable: true
                                onEdited: function(siVal) { if (root.appState) root.appState.bottomTsetK = siVal }
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridUnit {
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.bottomTsetK) : NaN
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }
                        }
                    }
                } // Row 2

                // ── Row 3: Solver Convergence | Thermodynamics ─────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // ── Solver Convergence ──────────────────────────────────
                    PGroupBox {
                        id: convBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Solver Convergence"
                        contentPadding: 8

                        GridLayout {
                            id: convGrid
                            width: convBox.width - (convBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // Max Outer Iterations
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Max Outer Iterations" }
                            PSpinner {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                from: 1; to: 1000
                                value: root.appState ? root.appState.maxOuterIterations : 100
                                onEdited: function(v) {
                                    if (root.appState) root.appState.maxOuterIterations = v
                                }
                            }

                            // Outer Conv Tolerance — scientific notation, free text.
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Outer Conv Tolerance"; alt: true }
                            PTextField {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                horizontalAlignment: Text.AlignRight
                                text: root.appState
                                      ? Number(root.appState.outerConvergenceTolerance).toExponential(3)
                                      : "1.000e-4"
                                onEditingFinished: {
                                    if (!root.appState) return
                                    var n = Number(text)
                                    if (isFinite(n)) root.appState.outerConvergenceTolerance = n
                                    else text = Number(root.appState.outerConvergenceTolerance).toExponential(3)
                                }
                            }
                        }
                    }

                    // ── Thermodynamics ──────────────────────────────────────
                    PGroupBox {
                        id: thermoBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Thermodynamics"
                        contentPadding: 8

                        GridLayout {
                            id: thermoGrid
                            width: thermoBox.width - (thermoBox.contentPadding * 2) - 2
                            columns: 3; columnSpacing: 0; rowSpacing: 0

                            // EOS Mode
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "EOS Mode" }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["Auto", "Manual"]
                                currentIndex: root.appState
                                              ? (root.appState.eosMode === "manual" ? 1 : 0)
                                              : 0
                                onActivated: function(index) {
                                    if (root.appState) root.appState.eosMode = (index === 1 ? "manual" : "auto")
                                }
                            }

                            // Manual EOS
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Manual EOS"; alt: true }
                            PComboBox {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                widthMode: "fill"
                                model: ["PR", "PRSV", "SRK"]
                                currentIndex: {
                                    if (!root.appState) return 1
                                    var m = ["PR", "PRSV", "SRK"].indexOf(root.appState.eosManual)
                                    return m >= 0 ? m : 1
                                }
                                enabled: root.appState ? root.appState.eosMode === "manual" : false
                                onActivated: function(index) {
                                    if (root.appState) root.appState.eosManual = model[index]
                                }
                            }
                        }
                    }
                } // Row 3

                // ════════════════════════════════════════════════════════════
                //  Row 4 — Solve / Status (full-width, single PGroupBox)
                //
                //  Migrated from the Draws / Strippers tab. Lives at the
                //  bottom of the Setup tab so the user configures the column
                //  spec at the top and runs / monitors solves at the bottom
                //  of the same view.
                //
                //  Layout: Solve + Reset buttons stacked vertically on the
                //  left (fixed 140 px column), then a 4-column status grid
                //  filling the rest with eight label/value pairs across
                //  4 rows × 2 column-pairs.
                // ════════════════════════════════════════════════════════════
                PGroupBox {
                    id: solveBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    Layout.alignment: Qt.AlignTop
                    caption: "Solve / Status"
                    contentPadding: 8

                    RowLayout {
                        width: solveBox.width - (solveBox.contentPadding * 2) - 2
                        spacing: 12

                        // ── Buttons column (fixed 140 px) ──────────────
                        ColumnLayout {
                            Layout.preferredWidth: 140
                            Layout.maximumWidth: 140
                            Layout.minimumWidth: 140
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            PButton {
                                text: "Solve"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                fontPixelSize: 11
                                enabled: root.appState ? !root.appState.solving : false
                                onClicked: {
                                    if (root.appState && !root.appState.solving)
                                        root.appState.solve()
                                }
                            }
                            PButton {
                                text: "Reset"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                fontPixelSize: 11
                                onClicked: {
                                    if (root.appState) root.appState.reset()
                                }
                            }
                        }

                        // ── Status grid: 4 columns (label|value|label|value)
                        //    × 4 rows = 8 fields total. ────────────────────
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            columns: 4
                            columnSpacing: 0
                            rowSpacing: 0

                            // Row 1: Solve Status | Elapsed Time
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Solve Status" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true
                                alignText: "right"
                                textValue: root._solveStatus()
                                valueColor: root._solveStatusColor()
                            }
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Elapsed Time" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true
                                textValue: root.appState ? root._fmtMs(root.appState.solveElapsedMs) : "—"
                            }

                            // Row 2: Condenser Qc | Reboiler Qr
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Condenser Qc"; alt: true }
                            PGridValue {
                                alt: true
                                Layout.fillWidth: true
                                quantity: "Power"
                                siValue: root.appState ? Number(root.appState.qcCalcKW) * 1000.0 : NaN
                                displayUnit: root.unitFor("Power")
                            }
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reboiler Qr"; alt: true }
                            PGridValue {
                                alt: true
                                Layout.fillWidth: true
                                quantity: "Power"
                                siValue: root.appState ? Number(root.appState.qrCalcKW) * 1000.0 : NaN
                                displayUnit: root.unitFor("Power")
                            }

                            // Row 3: Reflux Frac. | Boilup Frac.
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reflux Frac." }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true
                                textValue: root.appState
                                           ? (root._fmt3(root.appState.refluxFraction * 100) + "%") : "—"
                            }
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Boilup Frac." }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true
                                textValue: root.appState
                                           ? (root._fmt3(root.appState.boilupFraction * 100) + "%") : "—"
                            }

                            // Row 4: T Overhead | T Bottoms
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Overhead"; alt: true }
                            PGridValue {
                                alt: true
                                Layout.fillWidth: true
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.tColdK) : NaN
                                displayUnit: root.unitFor("Temperature")
                            }
                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "T Bottoms"; alt: true }
                            PGridValue {
                                alt: true
                                Layout.fillWidth: true
                                quantity: "Temperature"
                                siValue: root.appState ? Number(root.appState.tHotK) : NaN
                                displayUnit: root.unitFor("Temperature")
                            }
                        }
                    }
                } // solveBox (Row 4)

                Item { Layout.fillHeight: true }
            }
        }
    }
}
