import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  MessagesDock — bottom dock holding the Status panel (left, current
//  flowsheet problems) and the Messages/Trace panel (right, chronological
//  log). Single toggle button expands/collapses both together.
//
//  Behaviour spec
//    A. Flash stops on expand (markAllRead). Re-collapse keeps the unread
//       count badge visible.
//    B. Single toggle, both panels move together.
//    C. ~1 Hz smooth pulse. Yellow if only warns are unread; red if any
//       errors are unread.
//    D. Collapsed by default. The Status panel populates from existing
//       unit states on load, so the badge can show non-zero immediately
//       when a saved case has unsolved units.
//    E. Status row click → highlight + select + open property panel.
//    F. Trace row click → embedded clickable unit-id "links" navigate
//       to whichever unit was clicked (option 2).
//
//  AOT-safe: no for...of, no const in JS bodies, no `this` in delegate
//  signal handlers. Uses readonly property where appropriate.
// ─────────────────────────────────────────────────────────────────────────────

Rectangle {
    id: dock

    // ── Public API ───────────────────────────────────────────────────────────
    // The dock owns its own expanded/collapsed state. The host wires
    // navigation callbacks via these signals.
    property var flowsheet: null

    // Emitted when a row click should navigate to a unit. The host wires
    // selectUnit + highlightStream + open-property-panel against this.
    signal navigateToUnit(string unitId)

    // ── Layout sizing ────────────────────────────────────────────────────────
    readonly property int collapsedHeight: 30
    readonly property int expandedHeight:  220

    property bool expanded: false

    // Smooth height animation when toggling.
    Behavior on implicitHeight {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    implicitHeight: expanded ? expandedHeight : collapsedHeight

    color: "#dfe4ee"
    border.color: "#6d7883"
    border.width: 1

    // ── Helpers ──────────────────────────────────────────────────────────────
    function unreadAttentionLevel() {
        // Returns "none" | "warn" | "error" — drives the flash colour.
        // The flash is purely about UNREAD trace events. Persistent status
        // (gFlowsheetStatus) is conveyed by the visible badges, not the
        // flash, so that once the user has expanded the panel the flash
        // stops even if there are still flowsheet issues outstanding.
        if (typeof gMessageLog === "undefined" || !gMessageLog) return "none"
        if (gMessageLog.unreadErrorCount > 0) return "error"
        if (gMessageLog.unreadWarnCount  > 0) return "warn"
        return "none"
    }

    function shouldFlash() {
        if (dock.expanded) return false
        return unreadAttentionLevel() !== "none"
    }

    // When the flowsheet status acquires a new fail/warn (e.g. a stream was
    // just disconnected), bump the trace log's unread counters so the dock
    // flashes. Without this, a status-only event (no trace message) would
    // be silent. In practice every connection severance also posts a trace
    // message, so this is a safety net rather than the primary trigger.
    Connections {
        target: typeof gFlowsheetStatus !== "undefined" ? gFlowsheetStatus : null
        ignoreUnknownSignals: true
        function onCountChanged() {
            // No-op — the trace message that accompanies every status
            // change already drives the flash. Hook is here as a future
            // attachment point if status changes ever become silent.
        }
    }

    // Stop the flash when the user expands the dock.
    onExpandedChanged: {
        if (expanded && typeof gMessageLog !== "undefined" && gMessageLog) {
            gMessageLog.markAllRead()
        }
    }

    // ── Toggle / header bar ──────────────────────────────────────────────────
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: dock.collapsedHeight

        // Background that flashes via the animation below.
        Rectangle {
            id: headerBg
            anchors.fill: parent
            color: "#cfd6e0"

            // Flash colour driven by `unreadAttentionLevel()`.
            readonly property color flashWarnColor:  "#f3d65a"
            readonly property color flashErrorColor: "#ec5b5b"
            readonly property color baseColor:       "#cfd6e0"

            SequentialAnimation on color {
                id: flashAnimation
                running: dock.shouldFlash()
                loops: Animation.Infinite
                ColorAnimation {
                    to: dock.unreadAttentionLevel() === "error"
                          ? headerBg.flashErrorColor
                          : headerBg.flashWarnColor
                    duration: 500
                    easing.type: Easing.InOutQuad
                }
                ColorAnimation {
                    to: headerBg.baseColor
                    duration: 500
                    easing.type: Easing.InOutQuad
                }
                onStopped: headerBg.color = headerBg.baseColor
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dock.expanded = !dock.expanded
        }

        // Disclosure chevron + label + counts on the left
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Chevron — rotates 90° when expanded
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u25B6"
                font.pixelSize: 9
                color: "#1f2226"
                rotation: dock.expanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Status & Messages"
                font.pixelSize: 11
                font.bold: true
                color: "#1f2226"
            }

            // Severity badges — only visible when there's something
            // worth reporting.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: typeof gFlowsheetStatus !== "undefined"
                         && gFlowsheetStatus
                         && gFlowsheetStatus.failCount > 0
                width: failBadgeText.implicitWidth + 14
                height: 16
                radius: 8
                color: "#c63e3e"
                Text {
                    id: failBadgeText
                    anchors.centerIn: parent
                    text: (typeof gFlowsheetStatus !== "undefined" && gFlowsheetStatus
                            ? gFlowsheetStatus.failCount : 0) + " fail"
                    color: "#ffffff"
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: typeof gFlowsheetStatus !== "undefined"
                         && gFlowsheetStatus
                         && gFlowsheetStatus.warnCount > 0
                width: warnBadgeText.implicitWidth + 14
                height: 16
                radius: 8
                color: "#d6b74a"
                Text {
                    id: warnBadgeText
                    anchors.centerIn: parent
                    text: (typeof gFlowsheetStatus !== "undefined" && gFlowsheetStatus
                            ? gFlowsheetStatus.warnCount : 0) + " warn"
                    color: "#2a2004"
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            // Unread-trace count — collapsed only. Disappears once the
            // panel has been expanded (markAllRead).
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !dock.expanded
                         && typeof gMessageLog !== "undefined"
                         && gMessageLog
                         && (gMessageLog.unreadWarnCount + gMessageLog.unreadErrorCount) > 0
                width: unreadBadgeText.implicitWidth + 14
                height: 16
                radius: 8
                color: "#1c4ea7"
                Text {
                    id: unreadBadgeText
                    anchors.centerIn: parent
                    text: ((typeof gMessageLog !== "undefined" && gMessageLog)
                            ? (gMessageLog.unreadWarnCount + gMessageLog.unreadErrorCount)
                            : 0) + " unread"
                    color: "#ffffff"
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }

        // Right-side: total message count
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (typeof gMessageLog !== "undefined" && gMessageLog
                        ? gMessageLog.messageCount : 0) + " message"
                      + ((typeof gMessageLog !== "undefined" && gMessageLog
                          ? gMessageLog.messageCount : 0) === 1 ? "" : "s")
                font.pixelSize: 10
                color: "#526571"
            }
        }
    }

    // ── Body — only visible when expanded ────────────────────────────────────
    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true
        visible: dock.expanded || dock.implicitHeight > dock.collapsedHeight + 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4

            // Status panel — left
            StatusPanel {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.42
                Layout.minimumWidth: 240
                onNavigate: function(unitId) {
                    if (unitId !== "")
                        dock.navigateToUnit(unitId)
                }
            }

            // Vertical separator
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: "#97a2ad"
            }

            // Messages / Trace panel — right
            MessagesPanel {
                Layout.fillHeight: true
                Layout.fillWidth: true
                onNavigate: function(unitId) {
                    if (unitId !== "")
                        dock.navigateToUnit(unitId)
                }
            }
        }
    }
}
