import QtQuick 2.15
import QtQuick.Controls 2.15
import ChatGPT5.ADT 1.0

Item {
    id: root

    property alias panelTitle: titleLabel.text
    property bool closable: true
    property bool resizable: false
    property real minPanelWidth: 900
    property real minPanelHeight: 560
    property Item boundsItem: parent
    property alias contentItem: contentHost.data
    property bool active: true
    property real panelZ: 0

    signal closeRequested()
    signal activated()

    width: 1220
    height: 824
    z: panelZ + (active ? 1 : 0)

    readonly property int titleBarH: 32
    readonly property int cornerR: 8

    function clampX(v) {
        if (!boundsItem) return v
        return Math.max(0, Math.min(Math.max(0, boundsItem.width - width), v))
    }
    function clampY(v) {
        if (!boundsItem) return v
        return Math.max(0, Math.min(Math.max(0, boundsItem.height - height), v))
    }
    function clampWidth(v) {
        if (!boundsItem) return Math.max(minPanelWidth, v)
        return Math.max(minPanelWidth, Math.min(v, boundsItem.width - x))
    }
    function clampHeight(v) {
        if (!boundsItem) return Math.max(minPanelHeight, v)
        return Math.max(minPanelHeight, Math.min(v, boundsItem.height - y))
    }

    // ── Layer 1: clipping container — rounds all children to the panel corners ──
    // clip:true here masks the titleBar colour from painting over the rounded corners.
    // The border is NOT drawn here (clip would eat half of it); see Layer 3 below.
    Rectangle {
        id: clipContainer
        anchors.fill: parent
        radius: root.cornerR
        color: "#dfe4ee"   // content background — visible at bottom/sides
        clip: true         // THIS is the key: children are clipped to the rounded shape

        // ── Title bar ──
        Rectangle {
            id: titleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.titleBarH
            color: "#f0f0f0"
            // No radius needed — clipContainer rounds the top corners for us

            // Drag area
            MouseArea {
                id: titleDragArea
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: winButtonRow.left
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.SizeAllCursor
                hoverEnabled: true
                propagateComposedEvents: false
                preventStealing: true
                drag.target: root
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 0
                drag.minimumY: 0
                drag.maximumX: root.boundsItem ? Math.max(0, root.boundsItem.width - root.width) : 100000
                drag.maximumY: root.boundsItem ? Math.max(0, root.boundsItem.height - root.height) : 100000
                onPressed:  function(mouse) { root.activated(); mouse.accepted = true }
                onReleased: { root.x = root.clampX(root.x); root.y = root.clampY(root.y) }
            }

            // App icon
            Rectangle {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                color: "#0078d4"
                radius: 2
            }

            // Title text
            Text {
                id: titleLabel
                anchors.left: appIcon.right
                anchors.leftMargin: 8
                anchors.right: winButtonRow.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                text: "Column Workspace"
                color: active ? "#1a1a1a" : "#888888"
                font.pixelSize: 12
                font.family: "Segoe UI"
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            // Win-style min / max / close buttons
            Row {
                id: winButtonRow
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 0

                Rectangle {
                    width: 46; height: parent.height
                    color: minHover.containsMouse ? "#e5e5e5" : "transparent"
                    Text { anchors.centerIn: parent; text: "\u2013"; font.pixelSize: 12; color: "#1a1a1a" }
                    MouseArea { id: minHover; anchors.fill: parent; hoverEnabled: true }
                }
                Rectangle {
                    width: 46; height: parent.height
                    color: maxHover.containsMouse ? "#e5e5e5" : "transparent"
                    Text { anchors.centerIn: parent; text: "\u25a1"; font.pixelSize: 11; color: "#1a1a1a" }
                    MouseArea { id: maxHover; anchors.fill: parent; hoverEnabled: true }
                }
                Rectangle {
                    width: 46; height: parent.height
                    visible: root.closable
                    color: closeHover.containsMouse ? "#c42b1c" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        font.pixelSize: 11
                        color: closeHover.containsMouse ? "white" : "#1a1a1a"
                    }
                    MouseArea { id: closeHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.closeRequested() }
                }
            }

            // Title bar bottom separator
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#aaaaaa"
            }
        }

        // ── Content host ──
        Item {
            id: contentHost
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBar.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 4
            anchors.topMargin: 1
        }
    }


    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.activated()
    }

    // ── Layer 2: border drawn ON TOP of the clip container so it's never clipped ──
    Rectangle {
        anchors.fill: parent
        radius: root.cornerR
        color: "transparent"
        border.width: 2
        border.color: active ? "#333333" : "#999999"
    }
}
