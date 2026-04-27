import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PMessageDialog.qml
//
//  HYSYS-style modal Delete Error dialog with a Windows-classic 3D raised
//  frame. Title bar, stop icon, message, clickable sunken list, OK button.
//
//  Auto-sizes width to fit the longest item name (or the message, whichever
//  is longer). Falls back to minWidth = 380 when content is short, and caps
//  at ~85% of the parent width to handle pathologically long names.
// ─────────────────────────────────────────────────────────────────────────────

Popup {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────
    property string title: "Delete Error"
    property string message: ""
    property var items: []
    property string iconSource: Qt.resolvedUrl("../../icons/svg/stop.svg")
    property string okButtonText: "OK"
    property int minWidth: 380

    signal itemClicked(int index, string label)

    // ── Modal positioning ───────────────────────────────────────────────────
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    // ── Content-aware width ─────────────────────────────────────────────────
    // Auto-size to fit the widest item name (since those can be arbitrarily
    // long stream/package names). Chrome layout overhead is ~78px on the
    // horizontal axis (icon 40 + outer margins 16 + inner paddings 12 +
    // scrollbar headroom 10). We add that to the longest text width so the
    // list column is wide enough for the longest item without ellipsis.
    readonly property int maxItemTextWidth: {
        let w = 0
        for (let i = 0; i < itemMetricsRep.count; ++i) {
            const it = itemMetricsRep.itemAt(i)
            if (it && it.itemWidth > w) w = it.itemWidth
        }
        return w
    }
    readonly property int measuredContentWidth: Math.max(
        maxItemTextWidth + 78,
        messageMetrics.contentWidth + 78)
    readonly property int maxAllowedWidth: parent ? Math.floor(parent.width * 0.85) : 1200

    width: Math.min(Math.max(minWidth, measuredContentWidth), maxAllowedWidth)
    implicitHeight: chrome.implicitHeight
    height: Math.min(implicitHeight, parent ? parent.height - 40 : 600)

    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 3) : 0

    padding: 0
    background: Rectangle { color: "transparent" }

    // ── Invisible metrics passes for auto-width ─────────────────────────────
    // Each Text is visible:false so it contributes no layout; contentWidth
    // still reflects the natural rendered width of the string at the dialog's
    // font settings.
    Text {
        id: messageMetrics
        visible: false
        text: root.message
        font.pixelSize: 12
        textFormat: Text.PlainText
    }
    Repeater {
        id: itemMetricsRep
        model: root.items
        delegate: Item {
            readonly property int itemWidth: metricsText.contentWidth
            visible: false
            Text {
                id: metricsText
                text: modelData
                font.pixelSize: 12
                textFormat: Text.PlainText
            }
        }
    }

    // ── Raised outer chrome ─────────────────────────────────────────────────
    contentItem: Item {
        id: chrome
        implicitHeight: outerColumn.implicitHeight + 4

        // Base fill
        Rectangle { anchors.fill: parent; color: gAppTheme.pvFrame }

        // Outer 3D bevel — bright top+left, dark bottom+right
        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: gAppTheme.pvFrameHi }
        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameHi }
        Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameLo }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: gAppTheme.pvFrameLo }

        // Inner secondary bevel (chisel depth)
        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 1; anchors.leftMargin: 1; anchors.rightMargin: 1; height: 1; color: Qt.lighter(gAppTheme.pvFrame, 1.05) }
        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.topMargin: 1; anchors.leftMargin: 1; anchors.bottomMargin: 1; width: 1; color: Qt.lighter(gAppTheme.pvFrame, 1.05) }
        Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.topMargin: 1; anchors.rightMargin: 1; anchors.bottomMargin: 1; width: 1; color: Qt.darker(gAppTheme.pvFrame, 1.08) }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.leftMargin: 1; anchors.rightMargin: 1; anchors.bottomMargin: 1; height: 1; color: Qt.darker(gAppTheme.pvFrame, 1.08) }

        ColumnLayout {
            id: outerColumn
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0

            // Title bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: gAppTheme.pvTitleBg

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: gAppTheme.pvFrameLo
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    color: gAppTheme.pvTitleText
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            // Body
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: bodyRow.implicitHeight + 16
                color: gAppTheme.pvFrame

                RowLayout {
                    id: bodyRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Image {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        source: root.iconSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: root.message
                            color: gAppTheme.pvLabelText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                        }

                        // Sunken list (inverse bevel)
                        Item {
                            visible: root.items && root.items.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(
                                140, Math.max(22, (root.items ? root.items.length : 0) * 20 + 6))

                            Rectangle { anchors.fill: parent; color: "white" }
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: gAppTheme.pvFrameLo }
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameLo }
                            Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameHi }
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: gAppTheme.pvFrameHi }

                            ListView {
                                id: itemList
                                anchors.fill: parent
                                anchors.margins: 2
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.items
                                delegate: Rectangle {
                                    width: itemList.width
                                    height: 20
                                    color: itemMouse.containsMouse
                                        ? gAppTheme.pvButtonHover
                                        : "transparent"
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        font.pixelSize: 12
                                        font.underline: itemMouse.containsMouse
                                        color: "#1c4ea7"
                                        elide: Text.ElideRight
                                    }
                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.itemClicked(index, modelData)
                                    }
                                }
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }
                    }
                }
            }

            // Button row
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: gAppTheme.pvFrame

                PButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    text: root.okButtonText
                    onClicked: root.close()
                }
            }
        }
    }
}
