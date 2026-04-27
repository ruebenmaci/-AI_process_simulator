import QtQuick 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PGridSection.qml  —  labeled section divider inside a PGroupBox
//
//  A small labeled separator that visually subdivides a PGroupBox into
//  named regions (e.g., a Conditions group might have "Flow", "Thermo",
//  "Phase" sections under one captioned PGroupBox). Renders as:
//
//      ─── Section Title ──────────────────────────────────────────
//
//  The horizontal rule on each side of the title is drawn with the
//  same etched-line treatment as PGroupBox borders (1 px shadow line
//  with 1 px highlight underneath), giving the section a chiseled
//  HYSYS-style look that integrates with the surrounding chrome.
//
//  Default property is `rows` — children declared inside the section
//  go into a ColumnLayout below the header, indented 8 px to imply
//  hierarchy. This lets PGridSection act as both a separator and a
//  thin container in one element:
//
//      PGroupBox {
//          caption: "Worksheet"
//          ColumnLayout {
//              anchors.fill: parent
//              spacing: 4
//
//              PGridSection { title: "Identification" }
//              RowLayout {
//                  PGridLabel { text: "Name" }
//                  PTextField { /* ... */ }
//              }
//
//              PGridSection { title: "Conditions" }
//              RowLayout { /* T row */ }
//              RowLayout { /* P row */ }
//          }
//      }
//
//  Or use the default-property `rows` slot to nest rows inside the
//  section directly:
//
//      PGridSection {
//          title: "Conditions"
//          RowLayout { /* T row */ }
//          RowLayout { /* P row */ }
//      }
//
//  Sizing: Layout.fillWidth by default; height derived from header +
//  contents. No horizontal floor of its own — it inherits whatever
//  minimum width its rows declare.
//
//  AOT-safe: no for...of, no arrow functions, no `const`, no fractional
//  font.pixelSize, no shadowed FINAL properties.
// ─────────────────────────────────────────────────────────────────────────────

ColumnLayout {
    id: section

    // ── Public API ──────────────────────────────────────────────────────────
    property string title:        ""
    property string aux:          ""    // optional right-aligned annotation
    property int    headerHeight: 18
    property int    rowsIndent:   8     // left indent for nested rows
    property int    rowsSpacing:  2

    // Default property — children go into the rows column below the header.
    default property alias rows: rowsColumn.data

    // ── Layout contract ─────────────────────────────────────────────────────
    Layout.fillWidth: true
    spacing: 0

    // ── Header bar (etched separator + label + optional aux text) ──────────
    Item {
        id: headerBar
        Layout.fillWidth: true
        Layout.preferredHeight: section.headerHeight
        Layout.minimumHeight:   section.headerHeight

        // Left etched line — runs from the left edge to just before the title.
        // Two 1-px rectangles stacked vertically: a darker shadow line on top
        // and a lighter highlight underneath, matching PGroupBox border style.
        Rectangle {
            id: leftLineLo
            anchors.left: parent.left
            anchors.right: titleLabel.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            height: 1
            visible: section.title !== ""
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvGroupBorder
                   : "#8a8e96"
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: titleLabel.left
            anchors.rightMargin: 6
            anchors.top: leftLineLo.bottom
            height: 1
            visible: section.title !== ""
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvGroupBorderHi
                   : "#ffffff"
        }

        // Title label — sized to its text, anchored 8 px from the left edge
        // of the section. When title is empty, the section degrades to a
        // simple full-width separator (both lines run edge-to-edge).
        Text {
            id: titleLabel
            text: section.title
            visible: section.title !== ""
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: (typeof gAppTheme !== "undefined")
                            ? gAppTheme.pvFontSize
                            : 11
            font.family: "Segoe UI"
            font.italic: true
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvLabelText
                   : "#1f2226"
        }

        // Right etched line — fills from after the title (or after the aux
        // text, if present) all the way to the right edge.
        Rectangle {
            id: rightLineLo
            anchors.left: titleLabel.visible ? titleLabel.right : parent.left
            anchors.leftMargin: titleLabel.visible ? 6 : 0
            anchors.right: auxLabel.visible ? auxLabel.left : parent.right
            anchors.rightMargin: auxLabel.visible ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            height: 1
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvGroupBorder
                   : "#8a8e96"
        }
        Rectangle {
            anchors.left: titleLabel.visible ? titleLabel.right : parent.left
            anchors.leftMargin: titleLabel.visible ? 6 : 0
            anchors.right: auxLabel.visible ? auxLabel.left : parent.right
            anchors.rightMargin: auxLabel.visible ? 6 : 0
            anchors.top: rightLineLo.bottom
            height: 1
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvGroupBorderHi
                   : "#ffffff"
        }

        // Optional right-aligned aux annotation (e.g., a count or status).
        Text {
            id: auxLabel
            text: section.aux
            visible: section.aux !== ""
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: (typeof gAppTheme !== "undefined")
                            ? gAppTheme.pvFontSizeSmall
                            : 10
            font.family: "Segoe UI"
            color: (typeof gAppTheme !== "undefined")
                   ? gAppTheme.pvLabelText
                   : "#526571"
        }
    }

    // ── Rows column — default-property slot for nested content ─────────────
    // Indented to imply hierarchy. Rows inherit Layout.fillWidth from this
    // ColumnLayout, so they expand naturally.
    ColumnLayout {
        id: rowsColumn
        Layout.fillWidth: true
        Layout.leftMargin: section.rowsIndent
        spacing: section.rowsSpacing
    }
}
