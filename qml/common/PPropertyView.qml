import QtQuick 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  PPropertyView.qml
//
//  Content-area chrome for a property view — the raised outer frame, the
//  tab strip, and the sunken page area where PGroupBox instances live.
//  Does NOT provide a title bar: the parent Window's native title bar is
//  used (option B from the design discussion — gives us OS window management
//  for free).
//
//  Optional accessories can be placed at the left and right edges of the
//  tab strip. Typical use: a small icon on the left identifying the view,
//  and a Unit Set selector on the right.
//
//  Usage:
//
//    PPropertyView {
//        anchors.fill: parent
//        tabs: [ { text: "Conditions" }, { text: "Composition" }, ... ]
//        currentIndex: currentTab
//        onTabClicked: function(i) { currentTab = i }
//
//        leftAccessory: Image {
//            width: 16; height: 16
//            source: "qrc:/icons/stream.svg"
//        }
//
//        rightAccessory: Row {
//            spacing: 4
//            Text { text: "Unit Set:" }
//            PComboBox { ... }
//        }
//
//        // Content area: typically panels visible based on currentTab.
//        StreamConditionsPanel  { anchors.fill: parent; visible: currentTab === 0 }
//        StreamCompositionPanel { anchors.fill: parent; visible: currentTab === 1 }
//    }
//
//  Structure (top to bottom):
//    ┌─ outer frame (raised) ──────────────────────────┐
//    │ ┌─ tab strip ──────────────────────────────────┐ │
//    │ │ [icon] [Cond] [Comp] [Prop] ...    [unit] ▾ │ │
//    │ └──────────────────────────────────────────────┘ │
//    │ ╔═ page area (sunken into frame) ═════════════╗ │
//    │ ║                                              ║ │
//    │ ║   <content>                                  ║ │
//    │ ║                                              ║ │
//    │ ╚══════════════════════════════════════════════╝ │
//    └──────────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    // ── Public API ───────────────────────────────────────────────────────────
    property var    tabs: []             // [{ text: "…" }, …]
    property int    currentIndex: 0
    property alias  content: contentArea.data   // default-properly place content here
    property int    pageTopPadding:   14  // breathing room between tabs and first group
    property int    pageSidePadding:  8
    property int    pageBottomPadding: 8

    // Optional accessory slots in the tab strip:
    //   • leftAccessory  — placed at the strip's left edge, vertically centered
    //                      (typical use: a small icon identifying the view)
    //   • rightAccessory — placed at the strip's right edge, vertically centered
    //                      (typical use: a Unit Set selector or other commands)
    // Pass an Item (or a Row of items). Default property `data` so that any
    // children declared inline go into the page area, not the accessory slot.
    property alias leftAccessory:  leftAcc.children
    property alias rightAccessory: rightAcc.children

    // Tab-strip height — needs to fit the tab bar plus optional accessories
    // (Unit Set combos, icons). Default sized for a 22px PTabBar plus padding.
    property int tabStripHeight: 32
    property int tabStripSidePadding: 8

    signal tabClicked(int index)

    // Default property so children declared inside PPropertyView go into
    // the page area automatically.
    default property alias contentItems: contentArea.data

    // ── Outer raised frame ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrame : "#d8dade"
        // Outer bevel — raised (light top+left, dark bottom+right)
        Rectangle { x: 0; y: 0; width: parent.width;  height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#5a5e66" }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#5a5e66" }
    }

    // ── Tab strip with optional left/right accessories ─────────────────────
    Item {
        id: tabStrip
        x: 2
        y: 2
        width: parent.width - 4
        height: root.tabStripHeight

        // Left accessory holder — anchored at the left edge of the strip.
        Item {
            id: leftAcc
            anchors.left: parent.left
            anchors.leftMargin: root.tabStripSidePadding
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }

        // Right accessory holder — anchored at the right edge of the strip.
        Item {
            id: rightAcc
            anchors.right: parent.right
            anchors.rightMargin: root.tabStripSidePadding
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }

        // Tab bar — sits between the two accessories. Anchored to leftAcc's
        // right edge (with a small gap) and constrained to leave room for
        // rightAcc on its right.
        PTabBar {
            id: tabBar
            anchors.left: leftAcc.right
            anchors.leftMargin: leftAcc.children.length > 0 ? 8 : 0
            anchors.right: rightAcc.left
            anchors.rightMargin: rightAcc.children.length > 0 ? 8 : 0
            anchors.bottom: parent.bottom
            tabs: root.tabs
            currentIndex: root.currentIndex
            onTabClicked: function(i) { root.tabClicked(i) }
        }
    }

    // ── Page area (sunken) ──────────────────────────────────────────────────
    Rectangle {
        id: pageFrame
        x: 2
        y: tabStrip.y + tabStrip.height - 1   // overlap the bottom 1px of the tab strip
        width: parent.width - 4
        height: parent.height - y - 2
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvPageBg : "#ebedf0"
        // Sunken bevel — dark top+left, light bottom+right
        Rectangle { x: 0; y: 0; width: parent.width;  height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }

        // Content area — where PGroupBox instances go
        Item {
            id: contentArea
            x: root.pageSidePadding
            y: root.pageTopPadding
            width:  parent.width - (root.pageSidePadding * 2)
            height: parent.height - root.pageTopPadding - root.pageBottomPadding
        }
    }
}
