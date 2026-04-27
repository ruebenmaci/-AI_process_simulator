import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PCheckBox.qml
//
//  Styled checkbox that matches the HYSYS-style control vocabulary used by
//  PGridValue, PComboBox, PButton, etc. Integrates with the app's custom
//  tab-chain walker:
//    • tabStop: true when enabled
//    • Tab/Backtab routed through _moveToNextTabStop (skips labels/read-only)
//    • Left/Right/Up/Down advance focus along the tab chain
//    • Enter/Return/Space toggle the check (matching mouse click)
//    • Visible focus ring when the checkbox has keyboard focus
//
//  Usage mirrors Qt's built-in CheckBox:
//
//    PCheckBox {
//        text: "Show nonzero only"
//        checked: someProperty
//        onToggled: someProperty = checked
//    }
// ─────────────────────────────────────────────────────────────────────────────

CheckBox {
    id: control

    property int fontPixelSize: 11

    // Tab-stop advertisement for the cell-navigation system.
    property bool tabStop: enabled

    implicitHeight: 22
    font.pixelSize: fontPixelSize
    font.family: "Segoe UI"
    padding: 0
    spacing: 6

    // Layout contract: content-sized — the natural width is indicator + spacing
    // + label text + padding (computed by Qt from the contentItem). The minimum
    // never drops below the implicit size, so the box+label never clip. The
    // floor on label text is the responsibility of the label string itself
    // (short labels are intentional). Panels that need a checkbox to fill a
    // row can override Layout.fillWidth at the use site.
    Layout.minimumWidth:   implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight:   implicitHeight
    Layout.fillWidth:       false

    property color boxFill: "#ffffff"
    property color boxBorder: "#97a2ad"
    property color boxCheckColor: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7"
    property color textColor: enabled ? "#1f2a34" : "#6f7f8a"
    property color focusColor: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"

    function _moveToNextTabStop(forward) {
        var item = control
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === control) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        control._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        control._moveToNextTabStop(false); event.accepted = true
    }

    // Enter/Return/Space toggle the check (same as a mouse click). Arrow
    // keys advance focus along the tab chain. We call our walker explicitly
    // so Qt's default directional focus navigation never runs — that default
    // can cause enclosing scroll containers to shift unexpectedly.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            control.toggle()
            control.toggled()
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            control._moveToNextTabStop(true); event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            control._moveToNextTabStop(false); event.accepted = true
        }
    }

    indicator: Rectangle {
        implicitWidth: 14
        implicitHeight: 14
        x: control.leftPadding
        y: Math.round((control.height - height) / 2)
        color: control.enabled ? control.boxFill : "#f0f0f0"
        border.color: control.boxBorder
        border.width: 1

        // Checkmark: two-segment polyline drawn with two thin rectangles for
        // a crisp pixel look at 14×14 without relying on Canvas.
        Item {
            anchors.fill: parent
            visible: control.checked

            Rectangle {
                // short leg, bottom-left
                x: 3; y: 7
                width: 4; height: 2
                color: control.boxCheckColor
                rotation: 45
                transformOrigin: Item.TopLeft
            }
            Rectangle {
                // long leg, up-right
                x: 6; y: 8
                width: 7; height: 2
                color: control.boxCheckColor
                rotation: -45
                transformOrigin: Item.TopLeft
            }
        }

        // Focus ring — inset so it doesn't overlap the box border.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: "transparent"
            border.color: control.focusColor
            border.width: 1
            visible: control.activeFocus
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.textColor
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
        renderType: Text.NativeRendering
    }

    background: Item {
        implicitWidth: control.contentItem.implicitWidth
                     + control.indicator.width
                     + control.spacing
                     + control.leftPadding + control.rightPadding
        implicitHeight: control.implicitHeight
    }
}
