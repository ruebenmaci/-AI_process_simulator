import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnView.qml — outer shell holding the 7 distillation-column tabs.
//
//  Mirrors the StreamView pattern: PPropertyView provides the raised outer
//  frame, the tab strip, and the sunken page area. Each top-level tab is a
//  separate panel file (ColumnSetupPanel, ColumnDrawsPanel, etc.) anchored
//  to the page area and toggled by `visible`.
//
//  The right accessory carries the Unit Set selector (HYSYS-style: commands
//  live in the tab strip).
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var appState: null
    property int currentTab: 0   // 0=Setup 1=Draws 2=Performance 3=Profiles 4=Products 5=RunLog 6=Diagnostics 7=RunResults

    implicitWidth: 940
    implicitHeight: 760

    PPropertyView {
        id: pview
        anchors.fill: parent
        tabs: [
            { text: "Setup" },
            { text: "Draws / Strippers" },
            { text: "Performance" },
            { text: "Profiles" },
            { text: "Products" },
            { text: "Run Log" },
            { text: "Diagnostics" },
            { text: "Run Results" }
        ]
        currentIndex: root.currentTab
        onTabClicked: function(index) { root.currentTab = index }

        // ── Right accessory: Unit Set selector ─────────────────────────
        rightAccessory: Row {
            spacing: 4

            Text {
                text: "Unit Set:"
                font.pixelSize: 11
                color: "#526571"
                anchors.verticalCenter: parent.verticalCenter
            }

            PComboBox {
                id: unitSetCombo
                width: 100
                fontSize: 11
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                model: typeof gUnits !== "undefined" ? gUnits.availableUnitSets : ["SI", "Field", "British"]
                currentIndex: {
                    var s = (typeof gUnits !== "undefined") ? gUnits.activeUnitSet : "SI"
                    var idx = model.indexOf(s)
                    return idx >= 0 ? idx : 0
                }
                onActivated: function(index) {
                    if (typeof gUnits !== "undefined")
                        gUnits.activeUnitSet = model[index]
                }
                Connections {
                    target: typeof gUnits !== "undefined" ? gUnits : null
                    ignoreUnknownSignals: true
                    function onActiveUnitSetChanged() {
                        var i = unitSetCombo.model.indexOf(gUnits.activeUnitSet)
                        if (i >= 0 && unitSetCombo.currentIndex !== i)
                            unitSetCombo.currentIndex = i
                    }
                }
            }
        }

        // ── Page content: the eight column panels ──────────────────────
        ColumnSetupPanel        { anchors.fill: parent; visible: root.currentTab === 0
                                  appState: root.appState }
        ColumnDrawsPanel        { anchors.fill: parent; visible: root.currentTab === 1
                                  appState: root.appState }
        ColumnPerformancePanel  { anchors.fill: parent; visible: root.currentTab === 2
                                  appState: root.appState }
        ColumnProfilesPanel     { anchors.fill: parent; visible: root.currentTab === 3
                                  appState: root.appState }
        ColumnProductsPanel     { anchors.fill: parent; visible: root.currentTab === 4
                                  appState: root.appState }
        ColumnRunLogPanel       { anchors.fill: parent; visible: root.currentTab === 5
                                  appState: root.appState }
        ColumnDiagnosticsPanel  { anchors.fill: parent; visible: root.currentTab === 6
                                  appState: root.appState }
        ColumnRunResultsPanel   { anchors.fill: parent; visible: root.currentTab === 7
                                  appState: root.appState }
    }
}
