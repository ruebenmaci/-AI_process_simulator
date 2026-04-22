import QtQuick 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  PTabBar.qml
//
//  Raised tab strip in the dimensional HYSYS-style vocabulary. Each tab is
//  a small rectangle with 1-px highlight+shadow borders. The active tab is
//  "lifted" (raised bevel + lighter fill + border's bottom edge erased so it
//  visually connects to the page area beneath it). Inactive tabs sit slightly
//  recessed.
//
//  Keyboard support: Tab focuses the tab bar, Left/Right arrows switch
//  between tabs, Enter/Space re-fires the click signal for the current tab,
//  and Tab/Backtab continue the focus chain past the tab bar. A focus ring
//  appears on the active tab when the tab bar has keyboard focus.
//
//  Usage:
//
//    PTabBar {
//        tabs: [
//            { text: "Conditions" },
//            { text: "Composition" },
//            { text: "Properties" },
//            { text: "Phases" }
//        ]
//        currentIndex: 0
//        onTabClicked: function(index) { ... }
//    }
//
//  Each tab sizes to its content plus horizontal padding. Heights are fixed.
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: root

    // ── Public API ───────────────────────────────────────────────────────────
    property var    tabs: []              // array of { text: "…" } objects
    property int    currentIndex: 0
    property int    tabHPadding: 11       // horizontal padding inside each tab
    property int    tabHeight: 22         // fixed tab height

    signal tabClicked(int index)

    // Separate "focused tab index" used only while keyboard focus is in the
    // tab bar. Left/Right arrows move this indicator without changing the
    // active tab; Enter/Space then activates it (emits tabClicked). This
    // mirrors native Windows tab-bar accessibility behaviour.
    property int focusedIndex: currentIndex
    onCurrentIndexChanged: focusedIndex = currentIndex
    onActiveFocusChanged: if (activeFocus) focusedIndex = currentIndex

    // ── Keyboard accessibility ──────────────────────────────────────────────
    activeFocusOnTab: true
    property bool tabStop: true

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
        if (event.key === Qt.Key_Left) {
            if (root.focusedIndex > 0) {
                root.focusedIndex = root.focusedIndex - 1
            } else {
                // At the first tab: advance focus backward past the tab bar.
                // We call the walker explicitly so Qt's default directional
                // navigation (which can cause enclosing scroll containers to
                // shift) never runs.
                root._moveToNextTabStop(false)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            if (root.focusedIndex < root.tabs.length - 1) {
                root.focusedIndex = root.focusedIndex + 1
            } else {
                // At the last tab: advance focus forward past the tab bar.
                root._moveToNextTabStop(true)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            // Emit tabClicked only — the host updates its state (e.g.
            // StreamView's currentTab), which flows back to currentIndex
            // through the existing binding. Assigning currentIndex directly
            // here would break that binding, stopping future updates.
            root.tabClicked(root.focusedIndex)
            event.accepted = true
        }
    }

    // Overall height includes the 3-px strip above the tabs + tab height + 1-px
    // overlap that seals the active tab's bottom edge against the page area.
    implicitHeight: tabHeight + 3
    implicitWidth:  tabRow.width + 6

    // ── Background strip ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvTabStripBg : "#d8dade"
    }

    // ── Row of tabs ─────────────────────────────────────────────────────────
    Row {
        id: tabRow
        x: 3
        y: 3
        spacing: 1

        Repeater {
            model: root.tabs

            delegate: Item {
                id: tabItem
                width: tabText.width + (root.tabHPadding * 2)
                height: root.tabHeight

                property bool isActive: index === root.currentIndex

                // Border rectangles — the chiseled look.
                // Active tab: raised (highlight on top+left, shadow on right).
                //             Bottom edge is "erased" by overlapping the page area.
                // Inactive tab: raised with all 4 sides, slightly darker fill.
                Rectangle {
                    anchors.fill: parent
                    color: tabItem.isActive
                           ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvTabActive   : "#ebedf0")
                           : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvTabInactive : "#c5c8ce")
                    // Light on top+left, dark on right. Bottom edge handled below.
                    Rectangle {
                        // top highlight
                        x: 0; y: 0
                        width: parent.width; height: 1
                        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff"
                    }
                    Rectangle {
                        // left highlight
                        x: 0; y: 0
                        width: 1; height: parent.height
                        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff"
                    }
                    Rectangle {
                        // right shadow
                        x: parent.width - 1; y: 0
                        width: 1; height: parent.height
                        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079"
                    }
                    Rectangle {
                        // bottom shadow — only on inactive tabs (active tabs seal into page)
                        x: 0; y: parent.height - 1
                        width: parent.width; height: 1
                        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079"
                        visible: !tabItem.isActive
                    }
                }

                Text {
                    id: tabText
                    anchors.centerIn: parent
                    text: modelData.text || ""
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    font.family: "Segoe UI"
                    color: tabItem.isActive
                           ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvTabActiveText   : "#1f2226")
                           : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvTabInactiveText : "#555a64")
                }

                // Focus ring — shows on the tab that currently has keyboard
                // focus. This may differ from the active tab while the user
                // is arrow-navigating before pressing Enter to commit.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: "transparent"
                    border.color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"
                    border.width: 1
                    visible: index === root.focusedIndex && root.activeFocus
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Clicking a tab is a mouse interaction — release any
                        // keyboard focus the tab bar had so the arrow-nav
                        // focus ring goes away. The newly clicked tab is
                        // identified by its own active visual state, not by
                        // the keyboard focus ring.
                        if (root.activeFocus) root.focus = false
                        root.tabClicked(index)
                    }
                }
            }
        }
    }
}
