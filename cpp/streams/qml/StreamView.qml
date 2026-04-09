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
    property string streamTitle:  ""

    readonly property color bgOuter:   "#d8dde2"
    readonly property color cmdBar:    "#c8d0d8"
    readonly property color borderOut: "#6d7883"
    readonly property color borderIn:  "#97a2ad"

    Rectangle { anchors.fill: parent; color: bgOuter }

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        color: bgOuter; border.color: borderOut; border.width: 1

        Rectangle {
            id: tabBar
            x: 0; y: 0; width: parent.width; height: 40
            color: cmdBar; border.color: borderIn; border.width: 1

            Image {
                id: streamIcon
                x: 8
                y: Math.round((parent.height - height) / 2)
                width: 16
                height: 16
                source: Qt.resolvedUrl(gAppTheme.iconPath("Material_Stream"))
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Common.ClassicTabs {
                id: streamTabs
                x: streamIcon.x + streamIcon.width + 8; y: 6
                tabs: [
                    { text: "Conditions",  width: 92 },
                    { text: "Composition", width: 96 },
                    { text: "Properties",  width: 92 },
                    { text: "Phases",      width: 82 }
                ]
                currentIndex: root.currentTab
                onTabClicked: function(index) { root.currentTab = index }
            }
        }

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
            StreamCompositionPanel {
                anchors.fill: parent
                visible: root.currentTab === 1
                streamObject: root.streamObject
                unitObject:   root.unitObject
            }
            StreamPropertiesPanel {
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
