import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common" as Common

Item {
    id: root

    property var    streamObject: null
    property var    unitObject:   null
    property int    currentTab:   0
    property string streamTitle:  ""   // legacy property — callers may set this directly

    // ── Palette (mirrors ComponentManagerView exactly) ─────────────────
    readonly property color bgOuter:   "#d8dde2"
    readonly property color cmdBar:    "#c8d0d8"
    readonly property color borderOut: "#6d7883"
    readonly property color borderIn:  "#97a2ad"

    // ── Shared primitives ──────────────────────────────────────────────

    // ── Root background ────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: bgOuter }

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        color: bgOuter; border.color: borderOut; border.width: 1

        // ── Tab / command bar ──────────────────────────────────────────
        Rectangle {
            id: tabBar
            x: 0; y: 0; width: parent.width; height: 40
            color: cmdBar; border.color: borderIn; border.width: 1

            Common.ClassicTabs {
                id: streamTabs
                x: 8; y: 6
                tabs: [
                    { text: "Conditions",  width: 92 },
                    { text: "Properties",  width: 86 },
                    { text: "Composition", width: 96 },
                    { text: "Phases",      width: 74 }
                ]
                currentIndex: root.currentTab
                onTabClicked: function(index) { root.currentTab = index }
            }

        }

        // ── Panel area ─────────────────────────────────────────────────
        Item {
            x: 6; y: tabBar.height + 6
            width: parent.width - 12
            height: parent.height - tabBar.height - 12

            StreamConditionsPanel {
                anchors.fill: parent
                visible: root.currentTab === 0
                streamObject: root.streamObject
                unitObject:   root.unitObject
            }
            StreamPropertiesPanel {
                anchors.fill: parent
                visible: root.currentTab === 1
                streamObject: root.streamObject
                unitObject:   root.unitObject
            }
            StreamCompositionPanel {
                anchors.fill: parent
                visible: root.currentTab === 2
                streamObject: root.streamObject
                unitObject:   root.unitObject
            }
            StreamPhasesPanel {
                anchors.fill: parent
                visible: root.currentTab === 3
                streamObject: root.streamObject
                unitObject:   root.unitObject
            }
        }
    }
}
