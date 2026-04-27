import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnProductsPanel.qml — Products tab.
//
//  A single PGroupBox containing a material-balance table:
//
//    ┌─ Material Balance ─────────────────────────────────────────┐
//    │  Product              │ Flow (kg/h) │ Feed %                │
//    ├──────────────────────────────────────────────────────────┤
//    │  Light Naphtha        │       6,800 │  6.80 %                │
//    │  Heavy Naphtha        │      14,400 │ 14.40 %                │
//    │  ...                  │             │                        │
//    ├──────────────────────────────────────────────────────────┤
//    │  Total Products       │      60,600 │ 60.60 %                │
//    │  Balance Error        │          12 │  0.01 %                │
//    └──────────────────────────────────────────────────────────┘
//
//  Column widths use the same pattern as ColumnDrawsPanel: header and rows
//  bind to shared properties so they stay aligned. The Product column is
//  the slack-absorbing (fill) column; Flow and Feed % have fixed widths.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    // ── Column-width contract ───────────────────────────────────────────────
    readonly property int productColMinWidth: 200    // fills slack
    readonly property int flowColWidth:       110    // numeric, ~7-digit kg/h
    readonly property int feedPctColWidth:    90     // numeric "100.00 %"

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _fmt0(x) { var n = Number(x); return isFinite(n) ? Math.round(n).toString() : "—" }
    function _fmt2(x) { var n = Number(x); return isFinite(n) ? n.toFixed(2) : "—" }

    // ── Material balance row caching (mirrors original) ─────────────────────
    property var prodMbSorted: []
    function rebuildProdMbSorted() {
        var mbm = appState ? appState.materialBalanceModel : null
        if (!mbm || !appState || !appState.solved) {
            prodMbSorted = []
            return
        }
        var n = mbm.rowCount()
        var rows = []
        for (var i = 0; i < n; i++) {
            var idx = mbm.index(i, 0)
            var nm  = mbm.data(idx, 257) || ""
            var kg  = mbm.data(idx, 258) || 0
            var fr  = mbm.data(idx, 259) || 0
            rows.push({ name: nm, kgph: kg, frac: fr })
        }
        // Preserve backend ordering — re-sorting in QML breaks attached-stripper
        // ordering because labels like "Heavy Naphtha Stripper Bottoms" don't
        // carry a [Tray N] suffix. ColumnUnitState already orders correctly.
        prodMbSorted = rows
    }
    Component.onCompleted: rebuildProdMbSorted()

    Connections {
        target: root.appState ? root.appState.materialBalanceModel : null
        ignoreUnknownSignals: true
        function onTotalsChanged()  { root.rebuildProdMbSorted() }
        function onModelReset()     { root.rebuildProdMbSorted() }
        function onRowsInserted()   { root.rebuildProdMbSorted() }
        function onRowsRemoved()    { root.rebuildProdMbSorted() }
        function onDataChanged()    { root.rebuildProdMbSorted() }
    }
    Connections {
        target: root.appState
        ignoreUnknownSignals: true
        function onSolvedChanged()  { root.rebuildProdMbSorted() }
    }
    onVisibleChanged: if (visible) rebuildProdMbSorted()

    // ── Layout ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Item {
            anchors.fill: parent
            anchors.margins: 4

            PGroupBox {
                anchors.fill: parent
                caption: "Material Balance"
                contentPadding: 8
                fillContent: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ── Header row ─────────────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18

                        RowLayout {
                            anchors.fill: parent
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: root.productColMinWidth
                                text: "Product"
                                font.pixelSize: 10; font.bold: true
                                color: "#1f2a34"
                                horizontalAlignment: Text.AlignLeft
                                leftPadding: 4
                            }
                            Text {
                                Layout.preferredWidth: root.flowColWidth
                                Layout.maximumWidth:   root.flowColWidth
                                text: "Flow (kg/h)"
                                font.pixelSize: 10; font.bold: true
                                color: "#1f2a34"
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 6
                            }
                            Text {
                                Layout.preferredWidth: root.feedPctColWidth
                                Layout.maximumWidth:   root.feedPctColWidth
                                text: "Feed %"
                                font.pixelSize: 10; font.bold: true
                                color: "#1f2a34"
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 6
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#97a2ad"
                        }
                    }

                    // ── Product rows ───────────────────────────────────────
                    ListView {
                        id: productsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.prodMbSorted
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Item {
                            width: ListView.view.width
                            height: 22

                            Rectangle {
                                anchors.fill: parent
                                color: index % 2 === 0 ? "#f4f6f8" : "#ffffff"
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.productColMinWidth
                                    text: modelData.name || "—"
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: "#1f2a34"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    leftPadding: 4
                                }
                                Text {
                                    Layout.preferredWidth: root.flowColWidth
                                    Layout.maximumWidth:   root.flowColWidth
                                    text: root._fmt0(modelData.kgph || 0)
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: "#1c4ea7"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                                Text {
                                    Layout.preferredWidth: root.feedPctColWidth
                                    Layout.maximumWidth:   root.feedPctColWidth
                                    text: root._fmt2((modelData.frac || 0) * 100) + " %"
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: "#1c4ea7"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: "#d8dde2"
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !root.appState || !root.appState.solved
                            text: "Run solver to see material balance"
                            color: "#526571"
                            font.pixelSize: 10
                            font.italic: true
                        }
                    }

                    // ── Totals (Total Products, Balance Error) ─────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        visible: root.appState && root.appState.solved

                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width; height: 1
                            color: "#97a2ad"
                        }

                        // Total Products row
                        Item {
                            id: totalProductsRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 1
                            height: 22

                            Rectangle {
                                anchors.fill: parent
                                color: "#c8d0d8"
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.productColMinWidth
                                    text: "Total Products"
                                    font.pixelSize: 10; font.bold: true
                                    font.family: "Segoe UI"
                                    color: "#1f2a34"
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 4
                                }
                                Text {
                                    Layout.preferredWidth: root.flowColWidth
                                    Layout.maximumWidth:   root.flowColWidth
                                    text: (root.appState && root.appState.materialBalanceModel)
                                          ? root._fmt0(root.appState.materialBalanceModel.totalProductsKgph)
                                          : "—"
                                    font.pixelSize: 10; font.bold: true
                                    font.family: "Segoe UI"
                                    color: "#1c4ea7"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                                Text {
                                    Layout.preferredWidth: root.feedPctColWidth
                                    Layout.maximumWidth:   root.feedPctColWidth
                                    text: (root.appState && root.appState.materialBalanceModel)
                                          ? (root._fmt2(root.appState.materialBalanceModel.totalFrac * 100) + " %")
                                          : "—"
                                    font.pixelSize: 10; font.bold: true
                                    font.family: "Segoe UI"
                                    color: "#1c4ea7"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1
                                color: "#97a2ad"
                            }
                        }

                        // Balance Error row
                        Item {
                            id: balanceErrorRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: totalProductsRow.bottom
                            height: 22

                            property double errKgph: (root.appState && root.appState.materialBalanceModel)
                                                     ? root.appState.materialBalanceModel.balanceErrKgph
                                                     : 0
                            property double feedKgph: (root.appState && root.appState.materialBalanceModel)
                                                      ? root.appState.materialBalanceModel.feedKgph
                                                      : 1
                            property double errPct: (feedKgph > 0)
                                                    ? Math.abs(errKgph) / feedKgph * 100
                                                    : 0
                            property color errColor: Math.abs(errKgph) > 100
                                                     ? "#b23b3b"
                                                     : (Math.abs(errKgph) > 10 ? "#d6b74a" : "#1a7a3c")
                            property color errPctColor: errPct > 1.0
                                                        ? "#b23b3b"
                                                        : (errPct > 0.1 ? "#d6b74a" : "#1a7a3c")

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.productColMinWidth
                                    text: "Balance Error"
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: "#526571"
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 4
                                }
                                Text {
                                    Layout.preferredWidth: root.flowColWidth
                                    Layout.maximumWidth:   root.flowColWidth
                                    text: root._fmt2(Math.abs(balanceErrorRow.errKgph)) + " kg/h"
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: balanceErrorRow.errColor
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                                Text {
                                    Layout.preferredWidth: root.feedPctColWidth
                                    Layout.maximumWidth:   root.feedPctColWidth
                                    text: root._fmt2(balanceErrorRow.errPct) + " %"
                                    font.pixelSize: 10
                                    font.family: "Segoe UI"
                                    color: balanceErrorRow.errPctColor
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
