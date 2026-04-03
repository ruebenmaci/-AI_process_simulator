import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Floating, draggable HYSYS-style Equipment Palette.
// Emits placementRequested(type) when the user clicks a palette icon.
// The parent (PfdCanvas) is responsible for entering placement mode.

Item {
    id: root

    property Item boundsItem: parent   // item used to clamp drag position

    signal placementRequested(string unitType)  // "column" or "stream"

    visible: false

    width:  palettePanel.width
    height: palettePanel.height

    // Keep inside boundsItem when it resizes
    onVisibleChanged: {
        if (visible) {
            x = Math.min(x, (boundsItem ? boundsItem.width  : 800) - width  - 8)
            y = Math.min(y, (boundsItem ? boundsItem.height : 600) - height - 8)
        }
    }

    // ── Panel shell ──────────────────────────────────────────────────────────
    Rectangle {
        id: palettePanel
        width:  174
        height: titleBar.height + bodyColumn.implicitHeight + 14
        radius: 7
        color:  "#eef2f4"
        border.color: "#9aaab5"
        border.width: 1

        layer.enabled: true
        layer.effect: null          // shadow via drop-shadow if desired

        // ── Title bar (drag handle) ───────────────────────────────────────
        Rectangle {
            id: titleBar
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right
            height: 28
            radius: 7
            color:  "#2a3b49"

            // Clip the bottom corners so they sit flush with the panel body
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left:   parent.left
                anchors.right:  parent.right
                height: parent.radius
                color:  parent.color
            }

            Label {
                anchors.left:           parent.left
                anchors.leftMargin:     10
                anchors.verticalCenter: parent.verticalCenter
                text:  "Equipment Palette"
                color: "#dce8f1"
                font.pixelSize: 12
                font.bold: true
            }

            // Close button
            Rectangle {
                id: closeBtn
                anchors.right:          parent.right
                anchors.rightMargin:    6
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                radius: 9
                color: closeMa.containsMouse ? "#c0392b" : "#4a5f6e"

                Label {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 10
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.visible = false
                }
            }

            // Drag the whole palette via the title bar
            MouseArea {
                anchors.left:   parent.left
                anchors.right:  closeBtn.left
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                anchors.rightMargin: 4
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                acceptedButtons: Qt.LeftButton

                property real pressX: 0
                property real pressY: 0

                onPressed: function(mouse) {
                    pressX = mouse.x
                    pressY = mouse.y
                }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    const maxX = boundsItem ? boundsItem.width  - root.width  : 9999
                    const maxY = boundsItem ? boundsItem.height - root.height : 9999
                    root.x = Math.max(0, Math.min(root.x + mouse.x - pressX, maxX))
                    root.y = Math.max(0, Math.min(root.y + mouse.y - pressY, maxY))
                }
            }
        }

        // ── Icon grid ─────────────────────────────────────────────────────
        ColumnLayout {
            id: bodyColumn
            anchors.top:        titleBar.bottom
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.margins:    10
            anchors.topMargin:  10
            spacing: 8

            // Section label
            Label {
                text: "Unit Operations"
                font.pixelSize: 10
                color: "#5f6d78"
                font.bold: true
                Layout.fillWidth: true
            }

            // Icon row — Column and Stream side by side
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                PaletteIconButton {
                    iconSource:  Qt.resolvedUrl("../../icons/svg/Equip_Palette/Distillation_Column.svg")
                    label:       "Column"
                    onActivated: root.placementRequested("column")
                }

                PaletteIconButton {
                    iconSource:  Qt.resolvedUrl("../../icons/svg/Equip_Palette/Material_Stream.svg")
                    label:       "Stream"
                    onActivated: root.placementRequested("stream")
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color:  "#c6d0d7"
            }

            // Future equipment (greyed out)
            Label {
                text: "Planned"
                font.pixelSize: 10
                color: "#8a9aa5"
                font.bold: true
                Layout.fillWidth: true
            }

            GridLayout {
                columns: 2
                columnSpacing: 6
                rowSpacing: 4
                Layout.fillWidth: true

                Repeater {
                    model: ["Pump", "HX", "Sep.", "Valve", "Comp.", "Mixer"]
                    delegate: Rectangle {
                        implicitWidth:  72
                        implicitHeight: 22
                        radius: 4
                        color:  "#f0f3f4"
                        border.color: "#d2d8dc"
                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 10
                            color: "#9daab2"
                        }
                    }
                }
            }

            Item { implicitHeight: 2 }   // bottom padding
        }
    }

    // ── Inline sub-component: individual draggable palette button ─────────
    component PaletteIconButton: Item {
        id: btn
        implicitWidth:  68
        implicitHeight: 74

        property url    iconSource: ""
        property string label:      ""

        signal activated()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color:  ma.pressed       ? "#c8d8e8"
                  : ma.containsMouse ? "#dde8f0"
                  : "#f4f7f9"
            border.color: ma.containsMouse ? "#7aaac8" : "#c6d0d7"
            border.width: 1

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                Image {
                    source: btn.iconSource
                    Layout.preferredWidth:  42
                    Layout.preferredHeight: 42
                    Layout.alignment: Qt.AlignHCenter
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text:  btn.label
                    font.pixelSize: 10
                    color: "#31404a"
                }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:    btn.activated()

                ToolTip.visible: containsMouse
                ToolTip.delay:   600
                ToolTip.text:    "Click to place a " + btn.label + " on the PFD"
            }
        }
    }
}
