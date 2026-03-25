import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var appState

    property color fg: "#e6eef8"
    property color fgMuted: "#a9bfd6"
    property color border: "#223041"
    property color panel: "#121a24"
    property color inputBg: "#0f1620"

    Rectangle {
        id: card
        anchors.fill: parent
        color: root.panel
        radius: 10
        border.color: root.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Label {
                text: "Run Results"
                color: root.fg
                font.bold: true
                font.pixelSize: 14
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.border; opacity: 0.9 }

            // Multi-line selection + horizontal/vertical scrolling (same behavior as Run Log)
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                contentWidth: resultsText.contentWidth
                contentHeight: resultsText.contentHeight

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Rectangle {
                    // White background only for the text area (textarea-like)
                    x: 0
                    y: 0
                    width: Math.max(flick.width, flick.contentWidth)
                    height: Math.max(flick.height, flick.contentHeight)
                    color: "white"
                    z: -1
                }

                TextEdit {
                    id: resultsText
                    width: Math.max(flick.width, contentWidth)
                    text: root.appState ? root.appState.runResults : ""
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    color: "black"
                    selectionColor: "#ffeb3b"
                    selectedTextColor: "black"
                    font.family: "Courier New"
                    font.pixelSize: 11
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText

                    function _ensureCursorVisible() {
                        var r = cursorRectangle;

                        // Vertical
                        if (r.y < flick.contentY) {
                            flick.contentY = Math.max(0, r.y);
                        } else if (r.y + r.height > flick.contentY + flick.height) {
                            var maxY = Math.max(0, flick.contentHeight - flick.height);
                            flick.contentY = Math.min(maxY, r.y + r.height - flick.height);
                        }

                        // Horizontal
                        if (r.x < flick.contentX) {
                            flick.contentX = Math.max(0, r.x);
                        } else if (r.x + r.width > flick.contentX + flick.width) {
                            var maxX = Math.max(0, flick.contentWidth - flick.width);
                            flick.contentX = Math.min(maxX, r.x + r.width - flick.width);
                        }
                    }

                    onCursorRectangleChanged: _ensureCursorVisible()
                    onSelectionStartChanged: _ensureCursorVisible()
                    onSelectionEndChanged: _ensureCursorVisible()
                }
            }
        }
    }
}
