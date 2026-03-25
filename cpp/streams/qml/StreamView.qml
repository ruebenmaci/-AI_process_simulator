import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property var streamObject: null
    property var unitObject: null
    property string streamTitle: unitObject ? (unitObject.name || unitObject.id || "Stream") : "Stream"
    property int currentTab: 0

    readonly property color bg: "#dfe4ee"
    readonly property color chrome: "#d2d9e6"
    readonly property color panel: "#e9edf5"
    readonly property color panelInset: "#f4f6fa"
    readonly property color border: "#2a2a2a"
    readonly property color activeBlue: "#2e76db"
    readonly property color textDark: "#1f2430"
    readonly property color textBlue: "#1c4ea7"
    readonly property color mutedText: "#5a6472"

    Rectangle {
        anchors.fill: parent
        color: root.panel
        border.color: root.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: ["Conditions", "Properties", "Composition", "Phases"]

                    delegate: Button {
                        text: modelData
                        checkable: true
                        checked: root.currentTab === index
                        onClicked: root.currentTab = index

                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 28

                        contentItem: Text {
                            text: parent.text
                            color: "#1f2430"
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        background: Rectangle {
                            radius: 10
                            color: root.currentTab === index ? "#3b79d8" : "#cfd4dc"
                            border.color: "#3f3f3f"
                            border.width: 1
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentTab

                StreamConditionsPanel {
                    streamObject: root.streamObject
                    unitObject: root.unitObject
                }

                StreamPropertiesPanel {
                    streamObject: root.streamObject
                    unitObject: root.unitObject
                }

                StreamCompositionPanel {
                    streamObject: root.streamObject
                    unitObject: root.unitObject
                }

                StreamPhasesPanel {
                    streamObject: root.streamObject
                    unitObject: root.unitObject
                }
            }
        }
    }
}
