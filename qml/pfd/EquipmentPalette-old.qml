import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property Item boundsItem: parent

    signal placementRequested(string unitType)

    visible: false
    width: palettePanel.width
    height: palettePanel.height

    readonly property var paletteItems: [
        { iconId: "dist_column", label: "Dist. Column", unitType: "column", enabled: true },
        { iconId: "stream_material",      label: "Stream", unitType: "stream", enabled: true },
        { iconId: "absorber",             label: "Absorber", unitType: "absorber", enabled: false },
        { iconId: "adsorber",             label: "Adsorber", unitType: "adsorber", enabled: false },
        { iconId: "batch_reactor",        label: "Batch Reactor", unitType: "batch_reactor", enabled: false },
        { iconId: "centrifuge",           label: "Centrifuge", unitType: "centrifuge", enabled: false },
        { iconId: "column",          label: "Column", unitType: "dist_column", enabled: false },
        
        { iconId: "compressor",           label: "Compressor", unitType: "compressor", enabled: false },
        { iconId: "condenser",            label: "Condenser", unitType: "condenser", enabled: false },
        { iconId: "cooler",               label: "Cooler", unitType: "cooler", enabled: true },
        { iconId: "cstr",                 label: "CSTR", unitType: "cstr", enabled: false },
        { iconId: "cyclone",              label: "Cyclone", unitType: "cyclone", enabled: false },
        { iconId: "expander",             label: "Expander", unitType: "expander", enabled: false },
        { iconId: "filter",               label: "Filter", unitType: "filter", enabled: false },
        { iconId: "fired_heater",         label: "Fired Heater", unitType: "fired_heater", enabled: false },
        { iconId: "flash_drum",           label: "Flash Drum", unitType: "flash_drum", enabled: false },
        
        { iconId: "heat_exchanger",       label: "Heat Exchanger", unitType: "heat_exchanger", enabled: false },
        { iconId: "heater",               label: "Heater", unitType: "heater", enabled: true },
        { iconId: "hen",                  label: "HEN", unitType: "hen", enabled: false },
        { iconId: "kettle_vaporizer",     label: "Kettle Vaporizer", unitType: "kettle_vaporizer", enabled: false },
        { iconId: "mixer",                label: "Mixer", unitType: "mixer", enabled: false },
        { iconId: "pid_controller",       label: "PID Controller", unitType: "pid_controller", enabled: false },
        { iconId: "pipe_segment",         label: "Pipe Segment", unitType: "pipe_segment", enabled: false },
        { iconId: "plate_heat_exchanger", label: "Plate HX", unitType: "plate_heat_exchanger", enabled: false },
        { iconId: "pump",                 label: "Pump", unitType: "pump", enabled: false },
        { iconId: "reboiler",             label: "Reboiler", unitType: "reboiler", enabled: false },
        { iconId: "recycle",              label: "Recycle", unitType: "recycle", enabled: false },
        { iconId: "sensor",               label: "Sensor", unitType: "sensor", enabled: false },
        { iconId: "shortcut_column",      label: "Shortcut Column", unitType: "shortcut_column", enabled: false },
        { iconId: "stream_energy",        label: "Energy Stream", unitType: "stream_energy", enabled: false },
        { iconId: "stripper",             label: "Stripper", unitType: "stripper", enabled: false },
        { iconId: "tee_splitter",         label: "Tee Splitter", unitType: "tee_splitter", enabled: false },
        { iconId: "three_phase_flash",    label: "3-Phase Flash", unitType: "three_phase_flash", enabled: false },
        { iconId: "valve",                label: "Valve", unitType: "valve", enabled: false }
    ]

    onVisibleChanged: {
        if (visible) {
            x = Math.min(x, (boundsItem ? boundsItem.width  : 800) - width  - 8)
            y = Math.min(y, (boundsItem ? boundsItem.height : 600) - height - 8)
        }
    }

    Rectangle {
        id: palettePanel
        width: 236
        height: 560
        radius: 7
        color: gAppTheme.palettePanelBg
        border.color: gAppTheme.palettePanelBorder
        border.width: 1

        Rectangle {
            id: titleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            radius: 7
            color: gAppTheme.paletteTitleBg

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.radius
                color: parent.color
            }

            Label {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Equipment Palette"
                color: gAppTheme.paletteTitleText
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                id: closeBtn
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
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

            MouseArea {
                anchors.left: parent.left
                anchors.right: closeBtn.left
                anchors.top: parent.top
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

        ColumnLayout {
            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            anchors.topMargin: 6
            spacing: 4

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                GridLayout {
                    anchors.fill: parent
                    columns: 4
                    columnSpacing: 4
                    rowSpacing: 4

                    Repeater {
                        model: root.paletteItems

                        delegate: PaletteIconButton {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 50
                            iconSource: Qt.resolvedUrl(gAppTheme.paletteSvgIconPath(modelData.iconId))
                            label: modelData.label
                            enabled: modelData.enabled
                            onActivated: root.placementRequested(modelData.unitType)
                        }
                    }
                }
            }
        }
    }

    component PaletteIconButton: Item {
        id: btn
        implicitWidth: 50
        implicitHeight: 50

        property url iconSource: ""
        property string label: ""
        property bool enabled: true

        signal activated()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: !btn.enabled ? gAppTheme.palettePlannedBg
                 : hoverHandler.hovered ? gAppTheme.paletteItemBgHover
                 : gAppTheme.paletteItemBg
            border.color: !btn.enabled ? gAppTheme.palettePlannedBorder : gAppTheme.paletteItemBorder
            border.width: 1
            opacity: btn.enabled ? 1.0 : 0.68

            Image {
                anchors.centerIn: parent
                source: btn.iconSource
                width: 24
                height: 24
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                opacity: btn.enabled ? 1.0 : 0.72
            }
        }

        HoverHandler {
            id: hoverHandler
        }

        ToolTip {
            visible: hoverHandler.hovered
            delay: 250
            timeout: 3000
            text: btn.label

            contentItem: Text {
                text: btn.label
                font.pixelSize: 10
                color: "#111111"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.activated()
        }
    }
}
