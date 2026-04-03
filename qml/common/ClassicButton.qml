import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: control

    property color baseColor: "#d8dde3"
    property color hoverColor: "#e4e8ed"
    property color pressedColor: "#b0b8c2"
    property color disabledColor: "#d0d5da"
    property color borderColor: "#97a2ad"
    property color pressedBorderColor: "#6a7880"
    property color textColor: "#1f2a34"
    property int minButtonWidth: 64
    property int fontPixelSize: 10

    implicitWidth: Math.max(minButtonWidth,
                            Math.ceil(textMetrics.advanceWidth) + leftPadding + rightPadding)
    implicitHeight: 24
    leftPadding: 12
    rightPadding: 12
    topPadding: 4
    bottomPadding: 4
    spacing: 6
    hoverEnabled: true
    opacity: enabled ? 1.0 : 0.45
    font.pixelSize: fontPixelSize

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideNone
        anchors.centerIn: parent
        anchors.verticalCenterOffset: control.down ? 1 : 0
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
        border.color: (control.down || control.checked)
                      ? control.pressedBorderColor
                      : control.borderColor
    }

    TextMetrics {
        id: textMetrics
        font: control.font
        text: control.text || ""
    }
}
