import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnPerformancePanel.qml — Performance tab.
//
//  Three read-only summary cards arranged in two rows:
//
//    ┌─ Solve Summary ───────┐  ┌─ Top / Bottom Conditions ─┐
//    │  Solve Status   ...   │  │  Overhead Temperature ... │
//    │  Elapsed Time   ...   │  │  Bottoms Temperature  ... │
//    │  Specs Dirty    ...   │  │  Reflux Fraction      ... │
//    └───────────────────────┘  │  Boilup Fraction      ... │
//    ┌─ Energy Summary ──────┐  └───────────────────────────┘
//    │  Condenser Duty ...   │
//    │  Reboiler Duty  ...   │
//    │  Net Duty       ...   │
//    └───────────────────────┘
//
//  All values are plain text (no live editing). Numeric values use PGridValue
//  with isText:true so they pick up the panel chrome but stay read-only.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    readonly property int labelColWidth: 170

    // ── Helpers (mirrors DistillationColumn.qml originals) ──────────────────
    function _fmt0(x) { var n = Number(x); return isFinite(n) ? Math.round(n).toString() : "—" }
    function _fmt3(x) { var n = Number(x); return isFinite(n) ? n.toFixed(3) : "—" }
    function _fmtMs(ms) {
        var s = Math.floor((ms || 0) / 1000)
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    function _solveStatus() {
        if (!appState) return "—"
        if (appState.solving)    return "Solving…"
        if (appState.solved)     return "Converged"
        if (appState.specsDirty) return "Specs changed – re-run"
        return "Not solved"
    }

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        ScrollView {
            id: scrollArea
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scrollArea.availableWidth
                spacing: 6

                // ── Row 1: Solve Summary | Top / Bottom Conditions ──────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // ── Solve Summary ───────────────────────────────────────
                    PGroupBox {
                        id: solveBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Solve Summary"
                        contentPadding: 8

                        GridLayout {
                            width: solveBox.width - (solveBox.contentPadding * 2) - 2
                            columns: 2; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Solve Status" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "left"
                                textValue: root._solveStatus()
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Elapsed Time"; alt: true }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "left"; alt: true
                                textValue: root.appState ? root._fmtMs(root.appState.solveElapsedMs) : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Specs Dirty" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "left"
                                textValue: root.appState
                                           ? (root.appState.specsDirty ? "Yes" : "No")
                                           : "—"
                            }
                        }
                    }

                    // ── Top / Bottom Conditions ─────────────────────────────
                    PGroupBox {
                        id: topBotBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Top / Bottom Conditions"
                        contentPadding: 8

                        GridLayout {
                            width: topBotBox.width - (topBotBox.contentPadding * 2) - 2
                            columns: 2; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Overhead Temperature" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"
                                textValue: root.appState ? (root._fmt3(root.appState.tColdK) + " K") : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Bottoms Temperature"; alt: true }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"; alt: true
                                textValue: root.appState ? (root._fmt3(root.appState.tHotK) + " K") : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reflux Fraction" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"
                                textValue: root.appState
                                           ? (root._fmt3(root.appState.refluxFraction * 100) + " %")
                                           : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Boilup Fraction"; alt: true }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"; alt: true
                                textValue: root.appState
                                           ? (root._fmt3(root.appState.boilupFraction * 100) + " %")
                                           : "—"
                            }
                        }
                    }
                }

                // ── Row 2: Energy Summary (single, half-width) ──────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    PGroupBox {
                        id: energyBox
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.alignment: Qt.AlignTop
                        caption: "Energy Summary"
                        contentPadding: 8

                        GridLayout {
                            width: energyBox.width - (energyBox.contentPadding * 2) - 2
                            columns: 2; columnSpacing: 0; rowSpacing: 0

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Condenser Duty" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"
                                textValue: root.appState ? (root._fmt0(root.appState.qcCalcKW) + " kW") : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Reboiler Duty"; alt: true }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"; alt: true
                                textValue: root.appState ? (root._fmt0(root.appState.qrCalcKW) + " kW") : "—"
                            }

                            PGridLabel { Layout.preferredWidth: root.labelColWidth; text: "Net Duty" }
                            PGridValue {
                                Layout.fillWidth: true
                                isText: true; alignText: "right"
                                textValue: root.appState
                                           ? (root._fmt0(root.appState.qrCalcKW
                                                         - Math.abs(root.appState.qcCalcKW)) + " kW")
                                           : "—"
                            }
                        }
                    }

                    // Spacer so energy box stays half-width
                    Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
                }

                // Bottom spacer
                Item { Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 1 }
            }
        }
    }
}
