import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Button {
    id: control

    // Tab-stop advertisement for the cell-navigation system.
    property bool tabStop: enabled

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

    // Enter / Return / Space trigger the button's click, matching what the
    // mouse does. Qt's AbstractButton already handles Space by default, but
    // Enter behavior is style-dependent — wiring both explicitly guarantees
    // consistent keyboard activation.
    //
    // Arrow keys advance focus along the tabstop chain (same as Tab /
    // Shift+Tab). We call our walker explicitly so Qt's default directional
    // focus navigation never runs; that default can cause enclosing scroll
    // containers to shift unexpectedly.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            control.clicked()
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            control._moveToNextTabStop(true); event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            control._moveToNextTabStop(false); event.accepted = true
        }
    }

    // Slightly lighter grey than the panel chrome, but darker than PComboBox.
    property color baseColor: "#d3d8de"
    property color hoverColor: "#dbe0e5"
    property color pressedColor: "#c8d0d8"
    property color disabledColor: "#d7dce1"

    // Classic chiseled border colors.
    property color darkEdge: "#7f8a95"
    property color lightEdge: "#f7f9fb"
    property color midEdge: "#a6b0ba"

    property color textColor: "#1f2a34"
    property color disabledTextColor: "#6f7f8a"

    property int fontPixelSize: 11
    property int contentHPadding: 12
    property int contentVPadding: 0
    property int minButtonWidth: 0

    // ── Icon-glyph mode ────────────────────────────────────────────────────
    // When iconText is non-empty, the button renders the glyph (in iconColor
    // at iconFontSize) instead of `text`. Used for compact icon buttons like
    // the red ✕ delete button on draw-spec rows. iconText takes precedence
    // over text. Defaults preserve existing PButton callers exactly.
    property string iconText:     ""
    property color  iconColor:    "#c5422c"   // HYSYS-style red
    property int    iconFontSize: 12

    readonly property bool _isIconMode: iconText !== ""

    implicitWidth: _isIconMode
                   ? Math.max(minButtonWidth,
                              Math.ceil(iconMetrics.advanceWidth) + leftPadding + rightPadding)
                   : Math.max(minButtonWidth,
                              Math.ceil(textMetrics.advanceWidth) + leftPadding + rightPadding)
    implicitHeight: 22

    // Layout contract: content-sized by default. The button never shrinks
    // below its label width + padding (or the caller's minButtonWidth).
    // Panels that want equal-share buttons in a row can override
    // Layout.fillWidth: true at the use site.
    Layout.minimumWidth:   implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight:   implicitHeight
    Layout.fillWidth:       false

    leftPadding: contentHPadding
    rightPadding: contentHPadding
    topPadding: contentVPadding
    bottomPadding: contentVPadding
    spacing: 4
    hoverEnabled: true
    font.pixelSize: fontPixelSize

    contentItem: Text {
        text: control._isIconMode ? control.iconText : control.text
        font.family: control.font.family
        font.pixelSize: control._isIconMode ? control.iconFontSize : control.font.pixelSize
        font.bold: control._isIconMode
        color: control._isIconMode
               ? (control.enabled ? control.iconColor : control.disabledTextColor)
               : (control.enabled ? control.textColor : control.disabledTextColor)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideNone
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (control.down || control.checked) ? 1 : 0
        renderType: Text.NativeRendering
    }

    background: Rectangle {
        implicitWidth: control.implicitWidth
        implicitHeight: control.implicitHeight
        color: !control.enabled
               ? control.disabledColor
               : ((control.down || control.checked)
                  ? control.pressedColor
                  : (control.hovered ? control.hoverColor : control.baseColor))
        border.width: 1
        border.color: control.midEdge

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.right: parent.right
            height: 1
            color: (control.down || control.checked) ? control.darkEdge : control.lightEdge
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: (control.down || control.checked) ? control.darkEdge : control.lightEdge
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: (control.down || control.checked) ? control.lightEdge : control.darkEdge
        }
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 1
            color: (control.down || control.checked) ? control.lightEdge : control.darkEdge
        }

        // Focus ring — inset so it doesn't overlap the bevel edges.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "transparent"
            border.color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"
            border.width: 1
            visible: control.activeFocus
        }
    }

    TextMetrics {
        id: textMetrics
        font: control.font
        text: control.text || ""
    }

    TextMetrics {
        id: iconMetrics
        font.family: control.font.family
        font.pixelSize: control.iconFontSize
        font.bold: true
        text: control.iconText || ""
    }
}
