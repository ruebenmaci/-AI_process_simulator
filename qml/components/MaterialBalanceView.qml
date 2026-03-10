import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var model
    property var appState
    property real balanceTolKgph: 0.5

    // Qt 6-safe number formatting (Qt.formatNumber is not reliably available)
    function fmtFixed(x, decimals) {
        return Number(x).toLocaleString(Qt.locale(), "f", decimals)
    }

    function fmtK(kgph) {
        return fmtFixed(kgph / 1000.0, 3) + " k kg/h"
    }

    implicitHeight: content.implicitHeight + 16

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.implicitHeight
        color: "#121a24"
        radius: 10
        border.color: "#223041"
        border.width: 1

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Material Balance (product basis)"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#e6eef8"
                    Layout.fillWidth: true
                }
                Label {
                    text: root.model ? ("Feed: " + fmtK(root.model.feedKgph) + " (100.0%)") : ""
                    color: "#c7d2e2"
                    font.pixelSize: 12
                }
            }

            Label {
                text: "Draws:"
                color: "#e6eef8"
                font.pixelSize: 12
            }

            ListView {
                id: list
                Layout.fillWidth: true
                // Keep a stable region even when there are 0 rows or delegate errors.
                Layout.preferredHeight: Math.max(contentHeight, 32)
                interactive: false
                clip: false
                model: root.model

                delegate: RowLayout {
                    width: ListView.view.width
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        Label {
                            text: name
                            color: "#e6eef8"
                            font.bold: true
                            font.pixelSize: 12
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight
                        Label {
                            text: fmtK(kgph)
                            color: "#e6eef8"
                            font.pixelSize: 12
                        }
                        Label {
                            text: "(" + fmtFixed(frac * 100.0, 1) + "%)"
                            color: "#8ea0b5"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Total products"
                    color: "#e6eef8"
                    font.bold: true
                    Layout.fillWidth: true
                }
                Label {
                    text: root.model
                          ? (fmtK(root.model.totalProductsKgph) + " (" + fmtFixed(root.model.totalFrac * 100.0, 1) + "%)")
                          : ""
                    color: "#e6eef8"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Balance error"
                    color: "#e6eef8"
                    font.bold: true
                    Layout.fillWidth: true
                }
                Label {
                    text: {
                        const err = root.model ? root.model.balanceErrKgph : 0;
                        const ok = Math.abs(err) <= root.balanceTolKgph;
                        return fmtFixed(err, 2) + " kg/h" + (ok ? " (balanced)" : "");
                    }
                    color: "#e6eef8"
                }
            }
        }
    }
}
