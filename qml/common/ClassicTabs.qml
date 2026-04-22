import QtQuick 2.15
import QtQuick.Controls 2.15

FocusScope {
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

    // Tab-chain integration: ClassicTabs is a Tab destination, and we intercept
    // Tab/Backtab to skip labels/read-only cells via our walker pattern.
    activeFocusOnTab: true
    property bool tabStop: true

    // Separate "focused tab index" used only while keyboard focus is in the
    // tab bar. Left/Right arrows move this indicator without changing the
    // active tab; Enter/Space then activates it.
    property int focusedIndex: currentIndex
    onCurrentIndexChanged: focusedIndex = currentIndex
    onActiveFocusChanged: if (activeFocus) focusedIndex = currentIndex

    function _moveToNextTabStop(forward) {
        var item = root
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === root) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        root._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        root._moveToNextTabStop(false); event.accepted = true
    }
    Keys.onPressed: function(event) {
        // Left/Right move the focus indicator; past the boundaries, advance
        // focus to the next tabstop explicitly. Always accept the event so
        // Qt's default directional navigation never runs (it can cause
        // enclosing scroll containers to shift unexpectedly).
        if (event.key === Qt.Key_Left) {
            if (root.focusedIndex > 0) {
                root.focusedIndex = root.focusedIndex - 1
            } else {
                root._moveToNextTabStop(false)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            if (root.focusedIndex < root.tabs.length - 1) {
                root.focusedIndex = root.focusedIndex + 1
            } else {
                root._moveToNextTabStop(true)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            // Emit tabClicked only — assigning currentIndex directly here
            // would break the host's binding (e.g. `currentIndex: parent.foo`)
            // and future host-driven updates would stop working.
            root.tabClicked(root.focusedIndex)
            event.accepted = true
        }
    }

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

                // Focus ring on the currently-selected tab when ClassicTabs
                // has active focus (e.g. user tabbed here from elsewhere).
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: "transparent"
                    border.color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"
                    border.width: 1
                    visible: parent.active && root.activeFocus
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // Clicking releases keyboard focus so the arrow-nav
                        // focus ring disappears; the active tab's own visual
                        // state identifies the selected tab.
                        if (root.activeFocus) root.focus = false
                        // Emit tabClicked only — the host will set its own
                        // state and the binding back to currentIndex updates
                        // our visuals. Direct assignment would break that.
                        root.tabClicked(index)
                    }
                }
            }
        }
    }
}
