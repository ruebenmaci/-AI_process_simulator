import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import "./" as Components

Item {
    id: root
    // Let this view grow to fit its contents (browser-page style)
    implicitHeight: content.implicitHeight + 24
    // Inputs from Main.qml
    property var appState
    // Allow Main.qml to override these, but default to AppState models.
    // This prevents "results not updating" when Main.qml forgets to wire models.
    property bool solved: appState ? appState.solved : false
    property var trayModel: null
    property var materialBalanceModel: null

    readonly property var effectiveTrayModel: (trayModel !== null && trayModel !== undefined)
                                          ? trayModel
                                          : (appState ? appState.trayModel : null)
    readonly property var effectiveMaterialBalanceModel: (materialBalanceModel !== null && materialBalanceModel !== undefined)
                                          ? materialBalanceModel
                                          : (appState ? appState.materialBalanceModel : null)

    // Column numerics (filled by AppState once the solver runs)
    property real qc: appState ? appState.qcCalcKW : 0
    property real qr: appState ? appState.qrCalcKW : 0
    property real refluxFraction: appState ? appState.refluxFraction : 0
    property real boilupFraction: appState ? appState.boilupFraction : 0
    property real tColdK: appState ? appState.tColdK : 0
    property real tHotK: appState ? appState.tHotK : 0

    function fmt3(x) {
        if (x === undefined || x === null) return "—";
        const n = Number(x);
        if (!isFinite(n)) return "—";
        return n.toFixed(3);
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.implicitHeight
        radius: 10
        color: "#0f1a24"
        border.color: "#1f2b3a"

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Material Balance is part of the Column panel in the React app,
            // and only appears once a valid solve has been produced.
            Components.MaterialBalanceView {
                Layout.fillWidth: true
                visible: root.solved && root.effectiveMaterialBalanceModel
                model: root.effectiveMaterialBalanceModel
                appState: root.appState
            }

            // Condenser + Reboiler summary cards
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 8
                    color: "#0b1624"
                    border.color: "#1f2b3a"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 2
                        Text { text: "Condenser (Overhead)"; color: "white"; font.pixelSize: 12; font.bold: true }
                        Text {
                            text: "Qc: " + Math.round(root.qc) + " kW"
                            color: "#cfe3ff"; font.pixelSize: 11
                        }
                        Text {
                            text: "Reflux frac " + fmt3(root.refluxFraction * 100) + "%   T (cold) " + fmt3(root.tColdK) + " K"
                            color: "#98b3d6"; font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    radius: 8
                    color: "#0b1624"
                    border.color: "#1f2b3a"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 2
                        Text { text: "Reboiler (Bottoms)"; color: "white"; font.pixelSize: 12; font.bold: true }
                        Text {
                            text: "Qr: " + Math.round(root.qr) + " kW"
                            color: "#cfe3ff"; font.pixelSize: 11
                        }
                        Text {
                            text: "Boil-up frac " + fmt3(root.boilupFraction * 100) + "%   T (hot) " + fmt3(root.tHotK) + " K"
                            color: "#98b3d6"; font.pixelSize: 10
                        }
                    }
                }
            }

            // Legend row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Vapor bar (V*)"; color: "#98b3d6"; font.pixelSize: 10 }
                Text { text: "Liquid bar (1 - V*)"; color: "#98b3d6"; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Text { text: "φ = vapor fraction"; color: "#98b3d6"; font.pixelSize: 10 }
            }

            // Tray list (only after solve)
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                interactive: false
                clip: false
                verticalLayoutDirection: ListView.BottomToTop
                visible: root.solved && root.effectiveTrayModel
                model: root.effectiveTrayModel
                spacing: 6
                delegate: Components.TrayRow {
                    width: ListView.view.width
                    // Bind using TrayModel role names (TrayModel.h / TrayModel.cpp::roleNames)
                    trayNumber: model.trayNumber
                    tempK: model.tempK
                    vFrac: model.vaporFrac
                    vaporKgph: model.vaporFlow
                    liquidKgph: model.liquidFlow
                    isFeed: (model.isFeed === true)
                    hasDraw: (model.hasDraw === true)
                    drawLabel: model.drawLabel
                    isFlash: (model.isFlash === true)

                    // UI accents inferred from tray index (0 = bottom, N-1 = top)
                    isReboiler: model.trayNumber === 1
                    isCondenser: {
                        const m = ListView.view && ListView.view.model ? ListView.view.model : null;
                        const n = m && m.count !== undefined ? m.count : 0;
                        return n > 0 && model.trayNumber === (n - 1);
                    }
                }
            }

            // Empty placeholder to match React “no results yet” behavior
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                radius: 8
                color: "transparent"
                border.color: "#1f2b3a"
                visible: !root.solved
                Text {
                    anchors.centerIn: parent
                    text: "Run the solver to show Material Balance and tray results."
                    color: "#98b3d6"
                    font.pixelSize: 12
                }
            }
        }
    }
}