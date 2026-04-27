import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnRunResultsPanel.qml — Run Results tab.
//
//  A single PGroupBox with:
//    • An action row at top: PButton to export SolverInputs JSON, plus a
//      status text showing the last export path or a hint to run the solver.
//    • A scrollable read-only monospaced TextArea showing appState.runResults.
//
//  This is essentially a read-only log view, so no per-control width math
//  applies — the TextArea fills the body and scrolls in both axes.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Item {
            anchors.fill: parent
            anchors.margins: 4

            PGroupBox {
                anchors.fill: parent
                caption: "Run Results"
                contentPadding: 8
                fillContent: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    // ── Action row ───────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        PButton {
                            text: "Export Solver Inputs JSON"
                            onClicked: {
                                if (root.appState && root.appState.exportLatestSolverInputsJson) {
                                    var p = root.appState.exportLatestSolverInputsJson("")
                                    if (p && p.length > 0)
                                        console.log("Exported SolverInputs JSON:", p)
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: root.appState && root.appState.lastSolverInputsExportPath
                                  ? "Last export: " + root.appState.lastSolverInputsExportPath
                                  : "Run the solver, then export the exact SolverInputs JSON used for that run."
                            color: "#526571"
                            font.pixelSize: 10
                            font.family: "Segoe UI"
                            elide: Text.ElideMiddle
                        }
                    }

                    // ── Run-results text body ────────────────────────────────
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                        TextArea {
                            id: runResultsTextArea
                            width: Math.max(parent ? parent.width : 0, implicitWidth)
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            textFormat: TextEdit.PlainText
                            text: root.appState && root.appState.runResults ? root.appState.runResults : ""
                            font.family: "Monospace"
                            font.pixelSize: 10
                            color: "#1f2a34"
                            placeholderText: "Run solver to populate run results"
                            padding: 6

                            background: Rectangle {
                                color: "#ffffff"
                                // Sunken bevel matching PTextField vocabulary
                                Rectangle { x: 0; y: 0; width: parent.width; height: 1;  color: "#6c7079" }
                                Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: "#6c7079" }
                                Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: "#ffffff" }
                                Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: "#ffffff" }
                            }
                        }
                    }
                }
            }
        }
    }
}
