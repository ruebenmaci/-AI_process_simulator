import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    property var tabs: []
    property int currentIndex: 0
    property int fontPixelSize: 10
    property color textColor: "#1f2a34"
    property color borderColor: "#97a2ad"
    property color dividerColor: "#c7cdd4"
    property color tabFill: "#f2f4f6"
    property color activeTabFill: "#f7f7f8"
    property int leftMargin: 8
    property int topMargin: 2
    property int inactiveTopOffset: 4
    property int activeRaise: 2
    property int inactiveHeight: 20
    property int activeHeight: 23

    signal tabClicked(int index)

    implicitHeight: Math.max(topMargin + inactiveTopOffset + inactiveHeight + 2,
                             topMargin + activeHeight + 2)

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.topMargin + root.inactiveTopOffset + root.inactiveHeight - 1
        height: 1
        color: root.dividerColor
    }

    Row {
        id: row
        x: root.leftMargin
        y: root.topMargin
        spacing: 0

        Repeater {
            model: root.tabs
            delegate: Rectangle {
                required property int index
                required property var modelData

                readonly property bool active: index === root.currentIndex
                readonly property string label: (typeof modelData === "string") ? modelData : (modelData.text || "")
                readonly property int tabWidth: (typeof modelData === "object" && modelData.width) ? modelData.width : Math.max(80, label.length * 8 + 24)

                width: tabWidth
                height: active ? root.activeHeight : root.inactiveHeight
                y: active ? 0 : root.inactiveTopOffset
                z: active ? 2 : 1
                color: active ? root.activeTabFill : root.tabFill
                border.color: root.borderColor
                border.width: 1

                Rectangle {
                    visible: parent.active
                    x: 1
                    y: parent.height - 1
                    width: parent.width - 2
                    height: 2
                    color: parent.color
                }

                Text {
                    anchors.centerIn: parent
                    text: parent.label
                    font.pixelSize: root.fontPixelSize
                    color: root.textColor
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.currentIndex = index
                        root.tabClicked(index)
                    }
                }
            }
        }
    }
}
