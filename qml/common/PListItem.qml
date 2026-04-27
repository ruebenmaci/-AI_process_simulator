import QtQuick 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  PListItem.qml
//
//  Beveled list item for ListView delegates, matching the HYSYS-style
//  P-control aesthetic. Provides:
//    — Alternating row fills (white / light tint) driven by altIndex
//    — Raised 1-px bevel when unselected
//    — Sunken 1-px bevel + solid blue fill when selected
//    — Hover highlight fill
//
//  Sizing: Caller sets width/height explicitly (typically
//  `width: listView.width - 2; height: 40` in a ListView delegate).
//
//  Usage:
//
//    ListView {
//        id: myList
//        delegate: PListItem {
//            id: li
//            width: myList.width - 2
//            height: 40
//            altIndex: index
//            selected: model.id === selectedId
//
//            MouseArea {
//                anchors.fill: parent
//                hoverEnabled: true
//                onEntered: li.hovered = true
//                onExited:  li.hovered = false
//                onClicked: /* ... selection logic ... */
//            }
//
//            // Child content positioned inside the item
//            Column {
//                anchors.fill: parent
//                anchors.leftMargin: 8
//                // ...
//            }
//        }
//    }
//
//  Properties:
//    selected — when true, renders sunken + selected fill (blue)
//    hovered  — when true (and not selected), renders hover fill
//    altIndex — row index used to pick between normal/alt fill when not
//               selected. Typically bound to the delegate's `index`.
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────
    property bool selected: false
    property bool hovered:  false
    property int  altIndex: 0

    // ── Theme-driven colors (fall back to sensible defaults if gAppTheme absent) ──
    readonly property color normalFill: (typeof gAppTheme !== "undefined")
                                        ? (gAppTheme.pvCellBg || "#f4f6f8")
                                        : "#f4f6f8"
    readonly property color altFill:    "#ffffff"
    readonly property color hoverFill:  (typeof gAppTheme !== "undefined")
                                        ? (gAppTheme.pvCellHoverBg || "#e8eef5")
                                        : "#e8eef5"
    readonly property color selFill:    (typeof gAppTheme !== "undefined")
                                        ? (gAppTheme.pvCellSelectedBg || "#2e73b8")
                                        : "#2e73b8"
    readonly property color borderHi:   (typeof gAppTheme !== "undefined")
                                        ? (gAppTheme.pvFrameHi || "#ffffff")
                                        : "#ffffff"
    readonly property color borderLo:   (typeof gAppTheme !== "undefined")
                                        ? (gAppTheme.pvFrameLo || "#8a8e96")
                                        : "#8a8e96"

    // Fill color selection: selected > hovered > alternating
    color: selected ? selFill
                    : (hovered ? hoverFill
                               : (altIndex % 2 ? normalFill : altFill))

    // 1-px bevel:
    //   Unselected → raised (highlight on top/left, shadow on bottom/right)
    //   Selected   → sunken (shadow on top/left, highlight on bottom/right)
    Rectangle { x: 0; y: 0; width: parent.width;    height: 1; color: root.selected ? root.borderLo : root.borderHi }
    Rectangle { x: 0; y: 0; width: 1;               height: parent.height; color: root.selected ? root.borderLo : root.borderHi }
    Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: root.selected ? root.borderHi : root.borderLo }
    Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: root.selected ? root.borderHi : root.borderLo }
}
