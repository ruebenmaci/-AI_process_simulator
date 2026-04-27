import QtQuick 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PGroupBox.qml
//
//  An etched-border container with a caption embedded in the top edge,
//  matching the dimensional HYSYS-style property view aesthetic.
//
//  Visual anatomy:
//
//        ┌─Caption───────────────────────────────┐  ← caption breaks the top
//        │                                       │     border, sitting on the
//        │   [child content goes here]           │     parent background color
//        │                                       │
//        └───────────────────────────────────────┘  ← 1-px etched border
//
//  Sizing model:
//    — When used with an explicit width/height (e.g. test harness), the
//      border fills that area and children sit in the content area.
//    — When used with Layout.fillWidth + Layout.preferredHeight: implicitHeight,
//      the implicit height is computed from the largest child's natural size
//      plus padding, and the width fills the parent. THIS IS THE CANONICAL USE
//      for forms (PGridLabel/PGridValue grids, etc.).
//
//    The implicit size is driven by `contentHolder.childrenRect` in a ONE-WAY
//    relationship (no binding loops): children declare their own sizes, the
//    holder reads childrenRect, the root reads the holder's childrenRect +
//    padding, the parent layout reads the root's implicitHeight. No back
//    edges. Critical: when fillContent is false, contentHolder has NO anchors
//    and NO size of its own — its size comes purely from its children.
//
//    — When used with Layout.fillWidth + Layout.fillHeight AND fillContent: true,
//      the contentHolder is anchored to fill the root (inside the border and
//      caption), allowing children like ListView or PSpreadsheet to use
//      `anchors.fill: parent` to fill the group. Use this mode when the
//      container holds large content (ListView, PSpreadsheet) that doesn't
//      have a natural height but should fill available space.
//
//  Usage (canonical, child-sized):
//
//    PGroupBox {
//        Layout.fillWidth: true
//        Layout.preferredHeight: implicitHeight   // ← snaps to content
//        caption: "Conditions"
//
//        GridLayout {
//            columns: 6
//            // ... PGridLabel/PGridValue/PGridUnit children ...
//        }
//    }
//
//  Usage (fill-mode, for large content):
//
//    PGroupBox {
//        Layout.fillWidth: true
//        Layout.fillHeight: true
//        caption: "Components"
//        fillContent: true
//
//        ListView {
//            anchors.fill: parent
//            model: ...
//        }
//    }
//
//  Properties:
//    caption          — text shown in the embedded top-edge caption
//    captionPadding   — horizontal padding inside the caption rect (default 5)
//    captionInset     — distance from left edge to start of caption (default 9)
//    contentPadding   — padding inside the border around content (default 9)
//    fillContent      — when true, contentHolder fills the root (use for
//                       ListView/PSpreadsheet children with anchors.fill: parent).
//                       Default false, which keeps the canonical child-sized
//                       behavior for forms.
//    backgroundColor  — color used to "erase" border behind caption.
//                       Defaults to gAppTheme.pvPageBg.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    // ── Public API ───────────────────────────────────────────────────────────
    property string caption: ""
    property int    captionPadding: 5
    property int    captionInset:   9
    property int    contentPadding: 9
    property bool   fillContent: false
    property int    captionBottomPadding: 5    // extra space below caption before content
    property color  backgroundColor: (typeof gAppTheme !== "undefined")
                                     ? gAppTheme.pvPageBg
                                     : "#ebedf0"

    // Default property — children declared inside PGroupBox go into contentHolder.
    default property alias contentItems: contentHolder.data

    // ── Implicit sizing (one-way: children → holder → root) ─────────────────
    // Only used when fillContent is false. In fill-mode, the parent layout
    // dictates size via Layout.fillHeight / Layout.fillWidth.
    readonly property int captionOverhangTop: caption !== "" ? 7 : 0

    implicitWidth:  fillContent ? 0 : contentHolder.childrenRect.width  + (contentPadding * 2) + 2
    implicitHeight: fillContent ? 0 : contentHolder.childrenRect.height + (contentPadding * 2) + 2 + captionOverhangTop + captionBottomPadding

    // ── Etched border ───────────────────────────────────────────────────────
    // Outer highlight rectangle — sits 1px down/right of the inner one
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.captionOverhangTop + 1
        anchors.leftMargin: 1
        color: "transparent"
        border.color: (typeof gAppTheme !== "undefined")
                      ? gAppTheme.pvGroupBorderHi
                      : "#ffffff"
        border.width: 1
        z: 0
    }

    // Inner shadow rectangle — the actual etched border line
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.captionOverhangTop
        anchors.rightMargin: 1
        anchors.bottomMargin: 1
        color: "transparent"
        border.color: (typeof gAppTheme !== "undefined")
                      ? gAppTheme.pvGroupBorder
                      : "#8a8e96"
        border.width: 1
        z: 1
    }

    // ── Caption (embedded in top edge) ───────────────────────────────────────
    Rectangle {
        id: captionRect
        visible: root.caption !== ""
        x: root.captionInset
        y: 0
        height: captionLabel.implicitHeight
        width:  captionLabel.implicitWidth + (root.captionPadding * 2)
        color:  root.backgroundColor
        z: 2

        Text {
            id: captionLabel
            anchors.centerIn: parent
            text: root.caption
            font.pixelSize: (typeof gAppTheme !== "undefined")
                            ? gAppTheme.pvFontSizeCaption
                            : 11
            font.family: "Segoe UI"
            font.bold: true
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvGroupCaption
                   : "#1f2226"
        }
    }

    // ── Content holder ───────────────────────────────────────────────────────
    //
    // Two sizing modes:
    //
    // 1) Default (fillContent: false) — child-sized.
    //    This Item has NO anchors and NO explicit width/height — its size comes
    //    purely from its children via childrenRect. This is the ONLY way to
    //    avoid a binding loop when the root PGroupBox has Layout.fillWidth
    //    (which would otherwise make the content try to size to the parent,
    //    which sizes to the content). Used for forms with PGridLabel/PGridValue
    //    children that have natural sizes.
    //
    // 2) fillContent: true — parent-filling.
    //    This Item is sized to fill the root (inside the border and below
    //    the caption). Children can use `anchors.fill: parent` to fill the
    //    group. Used when the PGroupBox holds a single large child like a
    //    ListView or PSpreadsheet that doesn't have a natural height but
    //    should occupy all available space given to the group.
    //
    // Children placed inside PGroupBox end up here via the `contentItems`
    // default property alias.
    //
    // In fill-mode, contentHolder's width/height track the root. In
    // child-sized mode, they stay at 0 (natural Item default) so that
    // childrenRect — which reads children's bounding box regardless of the
    // Item's own size — drives the root's implicitWidth/Height.
    Item {
        id: contentHolder
        x: root.contentPadding
        y: root.captionOverhangTop + root.captionBottomPadding + root.contentPadding
        z: 3
        clip: root.fillContent
    }

    // Fill-mode sizing. These bindings only activate when fillContent is true;
    // otherwise contentHolder is left at its natural 0 size.
    Binding {
        target: contentHolder
        property: "width"
        value: root.width - (root.contentPadding * 2)
        when: root.fillContent
    }
    Binding {
        target: contentHolder
        property: "height"
        value: root.height - root.captionOverhangTop - root.captionBottomPadding - (root.contentPadding * 2)
        when: root.fillContent
    }
}
