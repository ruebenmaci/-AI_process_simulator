import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  StreamView — outer shell holding the 4 stream tabs.
//
//  Uses PPropertyView for the raised outer frame, tab strip, and sunken page
//  area. The stream icon and Unit Set selector are placed in PPropertyView's
//  left and right accessory slots (HYSYS-style: commands live in the tab
//  strip on the right side).
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var    streamObject: null
    property var    unitObject:   null
    property int    currentTab:   0

    implicitWidth: 560
    implicitHeight: 611

    PPropertyView {
        id: pview
        anchors.fill: parent
        tabs: [
            { text: "Conditions" },
            { text: "Composition" },
            { text: "Properties" },
            { text: "Phases" }
        ]
        currentIndex: root.currentTab
        onTabClicked: function(index) { root.currentTab = index }

        // The stream type icon is shown in the parent FloatingPanel's title
        // bar (panelIconSource), so there's no need to duplicate it in the
        // tab strip. The tab bar can use the full strip width.

        // ── Right accessory: the Unit Set selector ─────────────────────
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

        // ── Page content: the four stream panels ───────────────────────
        StreamConditionsPanel  { anchors.fill: parent; visible: root.currentTab === 0
                                 streamObject: root.streamObject; unitObject: root.unitObject }
        StreamCompositionPanel { anchors.fill: parent; visible: root.currentTab === 1
                                 streamObject: root.streamObject; unitObject: root.unitObject }
        StreamPropertiesPanel  { anchors.fill: parent; visible: root.currentTab === 2
                                 streamObject: root.streamObject; unitObject: root.unitObject }
        StreamPhasesPanel      { anchors.fill: parent; visible: root.currentTab === 3
                                 streamObject: root.streamObject; unitObject: root.unitObject }
    }
}
