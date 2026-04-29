import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  MessagesPanel — right half of the bottom dock. Shows chronological trace
//  log from gMessageLog. Each row has timestamp, severity icon, source tag,
//  and message text. Unit-id-shaped tokens in the message text are rendered
//  as clickable links that emit navigate(unitId) — option 2 click-nav.
//
//  The link detection is regex-based (\b[a-z_]+_\d+\b matches all our
//  unit-id formats: stream_3, mixer_1, heater_2, dist_column_1,
//  tee_splitter_2, etc.). Tokens that don't correspond to a real unit on
//  the flowsheet still get rendered as links — clicking them just
//  doesn't resolve to anything in the canvas, which is harmless.
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: root
    color: "#ffffff"
    border.color: "#97a2ad"
    border.width: 1

    signal navigate(string unitId)

    // ── Header strip ─────────────────────────────────────────────────────────
    Rectangle {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 22
        color: "#e8ebef"
        border.color: "#97a2ad"
        border.width: 1

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Messages"
            font.pixelSize: 10
            font.bold: true
            color: "#1f2226"
        }

        // "Clear" button on the right
        Rectangle {
            id: clearBtn
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 50
            height: 16
            radius: 2
            color: clearMouse.containsMouse ? "#cfd6e0" : "#dfe4ee"
            border.color: "#97a2ad"
            border.width: 1
            visible: typeof gMessageLog !== "undefined" && gMessageLog
                     && gMessageLog.messageCount > 0
            Text {
                anchors.centerIn: parent
                text: "Clear"
                font.pixelSize: 9
                color: "#1f2226"
            }
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof gMessageLog !== "undefined" && gMessageLog)
                        gMessageLog.clearLog()
                }
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    // Build rich-text body for a message: HTML-escape the raw text, then
    // wrap each unit-id token in <a href="unit:<id>"> markup. The link
    // colour matches the overall blue accent.
    function htmlEscape(s) {
        var t = String(s)
        t = t.replace(/&/g, "&amp;")
        t = t.replace(/</g, "&lt;")
        t = t.replace(/>/g, "&gt;")
        t = t.replace(/"/g, "&quot;")
        return t
    }

    function buildLinkedHtml(text) {
        // Match unit-id-shaped tokens: lowercase letters/underscores then
        // _ digits. Boundary on \b prevents partial-word matches.
        // We escape THEN substitute, so '<' and '>' inside the original
        // text can't break our tags.
        var escaped = htmlEscape(text)
        return escaped.replace(/\b([a-z_]+_\d+)\b/g, function(m) {
            return '<a href="unit:' + m + '" style="color:#1c4ea7;text-decoration:underline">' + m + '</a>'
        })
    }

    // ── List ─────────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0
        model: typeof gMessageLog !== "undefined" ? gMessageLog : null
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Auto-scroll to the latest message when a new one arrives.
        Connections {
            target: typeof gMessageLog !== "undefined" ? gMessageLog : null
            ignoreUnknownSignals: true
            function onMessageAppended(row, level) {
                Qt.callLater(function() { list.positionViewAtEnd() })
            }
        }

        // Empty-state message.
        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "No messages"
            color: "#526571"
            font.pixelSize: 10
            font.italic: true
        }

        delegate: Rectangle {
            width: list.width
            // Variable height — rich-text wrapping needs measured height.
            height: Math.max(20, msgText.implicitHeight + 4)
            color: index % 2 === 0 ? "#ffffff" : "#f5f7fa"

            // Severity colored bar
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: model.level === "error" ? "#c63e3e"
                     : model.level === "warn"  ? "#d6b74a"
                     : "#1c4ea7"
            }

            // Timestamp
            Text {
                id: tsText
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.top: parent.top
                anchors.topMargin: 2
                text: model.timestampDisplay || ""
                font.pixelSize: 9
                font.family: "Consolas, Courier New, monospace"
                color: "#526571"
                width: 56
            }

            // Source tag
            Text {
                id: srcText
                anchors.left: tsText.right
                anchors.leftMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 2
                text: model.source ? "[" + model.source + "]" : ""
                font.pixelSize: 9
                font.bold: true
                color: model.level === "error" ? "#c63e3e"
                     : model.level === "warn"  ? "#a08222"
                     : "#1c4ea7"
                width: 86
            }

            // Message body — rich text with embedded unit-id links.
            //
            // We use Text (not TextEdit) because we need read-only display
            // and Text supports linkActivated for option 2 navigation.
            Text {
                id: msgText
                anchors.left: srcText.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.top: parent.top
                anchors.topMargin: 2
                text: root.buildLinkedHtml(model.text || "")
                font.pixelSize: 11
                color: "#1f2226"
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                onLinkActivated: function(link) {
                    // Link format is "unit:<id>"
                    if (link.indexOf("unit:") === 0) {
                        var unitId = link.substring(5)
                        if (unitId !== "")
                            root.navigate(unitId)
                    }
                }
                // Hand cursor when hovering a link.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink !== ""
                                  ? Qt.PointingHandCursor
                                  : Qt.ArrowCursor
                }
            }
        }
    }
}
