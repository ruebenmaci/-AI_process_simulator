import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Drop this anywhere in your UI — e.g. in a Settings menu or a toolbar popup.
// It reads/writes gDisplaySettings (registered in main.cpp).
//
// Usage example in Main.qml:
//   DisplaySettingsPanel { anchors.centerIn: parent; visible: showSettings }

Rectangle {
    id: root
    width: 320; height: col.implicitHeight + 24
    color: "#e8ebef"; border.color: "#97a2ad"; border.width: 1
    radius: 0

    readonly property color hdrBg:   "#c8d0d8"
    readonly property color hdrBdr:  "#97a2ad"
    readonly property color textMain:"#1f2a34"
    readonly property color textMuted:"#526571"
    readonly property color inputBg: "#ffffff"
    readonly property int   rowH:    22
    readonly property int   headH:   20

    // Section header
    Rectangle {
        id: hdr
        x: 0; y: 0; width: parent.width; height: headH
        color: hdrBg; border.color: hdrBdr; border.width: 1
        Text {
            anchors.left: parent.left; anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Display Settings"
            font.pixelSize: 10; font.bold: true; color: textMain
        }
    }

    Column {
        id: col
        x: 0; y: hdr.height
        width: parent.width
        spacing: 0

        // ── Scale preset row ──────────────────────────────────
        Item {
            width: parent.width; height: rowH
            Text {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 110; text: "UI Scale"
                font.pixelSize: 10; color: textMuted
            }
            ComboBox {
                id: presetCombo
                anchors { left: parent.left; leftMargin: 118
                          right: parent.right; rightMargin: 6
                          verticalCenter: parent.verticalCenter }
                implicitHeight: rowH - 4
                font.pixelSize: 10
                model: gDisplaySettings ? gDisplaySettings.presets : []
                background: Rectangle { color: inputBg; border.color: "#97a2ad"; border.width: 1 }
                contentItem: Text {
                    leftPadding: 4; text: parent.displayText
                    color: "#1c4ea7"; font.pixelSize: 10
                    verticalAlignment: Text.AlignVCenter
                }
                Component.onCompleted: {
                    if (!gDisplaySettings) return
                    var idx = gDisplaySettings.currentPresetIndex()
                    currentIndex = idx >= 0 ? idx : 0
                }
                onActivated: {
                    if (gDisplaySettings)
                        gDisplaySettings.scaleFactor = gDisplaySettings.presetValue(index)
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
        }

        // ── Current value display ─────────────────────────────
        Item {
            width: parent.width; height: rowH
            Text {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 110; text: "Saved value"
                font.pixelSize: 10; color: textMuted
            }
            Text {
                anchors { left: parent.left; leftMargin: 118
                          verticalCenter: parent.verticalCenter }
                text: gDisplaySettings
                      ? (Math.round(gDisplaySettings.scaleFactor * 100) + "%")
                      : "—"
                font.pixelSize: 10; color: "#1c4ea7"
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
        }

        // ── Restart note ──────────────────────────────────────
        Item {
            width: parent.width; height: noteText.implicitHeight + 10
            Text {
                id: noteText
                x: 6; y: 5; width: parent.width - 12
                text: gDisplaySettings ? gDisplaySettings.restartNote : ""
                font.pixelSize: 9; color: textMuted
                wrapMode: Text.WordWrap
            }
        }
    }
}
