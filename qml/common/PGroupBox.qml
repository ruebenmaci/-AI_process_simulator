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
//      plus padding, and the width fills the parent. THIS IS THE CANONICAL USE.
//
//    The implicit size is driven by `contentHolder.childrenRect` in a ONE-WAY
//    relationship (no binding loops): children declare their own sizes, the
//    holder reads childrenRect, the root reads the holder's childrenRect +
//    padding, the parent layout reads the root's implicitHeight. No back
//    edges. Critical: contentHolder has NO anchors and NO size of its own —
//    its size comes purely from its children.
//
//  Usage:
//
//    PGroupBox {
//        Layout.fillWidth: true
//        Layout.preferredHeight: implicitHeight   // ← important, snaps to content
//        caption: "Conditions"
//
//        GridLayout {
//            columns: 6
//            // ... PGridLabel/PGridValue/PGridUnit children ...
//        }
//    }
//
//  Properties:
//    caption          — text shown in the embedded top-edge caption
//    captionPadding   — horizontal padding inside the caption rect (default 5)
//    captionInset     — distance from left edge to start of caption (default 9)
//    contentPadding   — padding inside the border around content (default 9)
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
    property color  backgroundColor: (typeof gAppTheme !== "undefined")
                                     ? gAppTheme.pvPageBg
                                     : "#ebedf0"

    // Default property — children declared inside PGroupBox go into contentHolder.
    default property alias contentItems: contentHolder.data

    // ── Implicit sizing (one-way: children → holder → root) ─────────────────
    readonly property int captionOverhangTop: caption !== "" ? 7 : 0

    implicitWidth:  contentHolder.childrenRect.width  + (contentPadding * 2) + 2
    implicitHeight: contentHolder.childrenRect.height + (contentPadding * 2) + 2 + captionOverhangTop

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
    // This Item has NO anchors and NO explicit width/height — its size comes
    // purely from its children. This is the ONLY way to avoid a binding loop
    // when the root PGroupBox has Layout.fillWidth (which would otherwise make
    // the content try to size to the parent, which sizes to the content).
    //
    // Children placed inside PGroupBox end up here via the `contentItems`
    // default property alias.
    Item {
        id: contentHolder
        x: root.contentPadding
        y: root.captionOverhangTop + root.contentPadding
        z: 3
        // No width/height/anchors — size comes from children.
    }
}
