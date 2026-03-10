import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// TrayRow.qml — "master-like" row layout (React/JS parity)
//
// Goal: match the React tray list row:
//  - Tray header at left (Tray N + optional condenser/reboiler subtitle)
//  - One horizontal bar: vapor fraction segment over liquid base
//  - One single metrics line (T, V*, V↑, L↓, optional Draw pct) — no duplicated "Draw" text
Item {
    id: root

    // ---- Data (bind from TrayModel roles) ----
    property int trayNumber: 0              // 1-based (1 = reboiler/bottom)
    property double tempK: 0.0
    property double vFrac: 0.0              // 0..1
    property double liquidKgph: 0.0         // kg/h
    property double vaporKgph: 0.0          // kg/h


    // Feed tray flag (ColumnView assigns this)
    property bool isFeed: false
    // Flags
    property bool isFlash: false
    property bool isCondenser: false
    property bool isReboiler: false
    property bool isSpike: false

    // Draw info (optional)
    property bool hasDraw: false
    property string drawLabel: ""           // e.g., "Residue"
    property double drawPct: 0.0            // 0..100 (optional; keep 0 if unknown)

    // Context labels (optional)
    property string condenserTypeLabel: ""  // e.g., "total", "partial"
    property string flashZoneLabel: "Flash zone (feed)"

    // ---- Formatting ----
    function clamp01(x) { return Math.max(0.0, Math.min(1.0, x)) }
    function fmtK(v)    { return Number(v).toFixed(2) + " K" }
    function fmtFrac(v) { return Number(v).toFixed(3) }
    function fmtKgphK(v){ return (Number(v) / 1000.0).toFixed(3) + " k kg/h" }
    function fmtPct(v)  { return Number(v).toFixed(1) + "%" }

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        radius: 10
        color: "#0f1620"
        border.width: 1
        border.color: "#1f2b3a"
        implicitHeight: body.implicitHeight + 14

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // ---- Header row ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        id: trayTitle
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        font.bold: true
                        color: "#e6eef8"
                        text: {
                            if (isReboiler) return "Tray " + trayNumber + " (Reboiler)"
                            if (isCondenser) {
                                if (condenserTypeLabel && condenserTypeLabel.length > 0)
                                    return "Tray " + trayNumber + " (Overhead condenser, " + condenserTypeLabel + ")"
                                return "Tray " + trayNumber + " (Overhead condenser)"
                            }
                            return "Tray " + trayNumber
                        }
                    }

                    // Optional secondary line (kept minimal like React)
                    Label {
                        visible: false
                        font.pixelSize: 11
                        opacity: 0.75
                        color: "#b8c6d8"
                        text: ""
                    }
                }

                // Right-side small badges (Flash zone, Spike)
                Rectangle {
                    visible: (isFeed || isFlash) && !isCondenser && !isReboiler
                    radius: 999
                    color: Qt.rgba(56/255, 189/255, 248/255, 0.12)
                    border.color: Qt.rgba(56/255, 189/255, 248/255, 0.30)
                    border.width: 1
                    implicitHeight: 18
                    implicitWidth: flashText.implicitWidth + 12
                    Label {
                        id: flashText
                        anchors.centerIn: parent
                        text: flashZoneLabel
                        font.pixelSize: 11
                        color: "#e6eef8"
                    }
                }

                Rectangle {
                    visible: isSpike
                    radius: 999
                    color: Qt.rgba(245/255, 158/255, 11/255, 0.14)
                    border.color: Qt.rgba(245/255, 158/255, 11/255, 0.35)
                    border.width: 1
                    implicitHeight: 18
                    implicitWidth: spikeText.implicitWidth + 12
                    Label {
                        id: spikeText
                        anchors.centerIn: parent
                        text: "Spike"
                        font.pixelSize: 11
                        color: "#e6eef8"
                    }
                }
            }

            // ---- Bar + metrics ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Bar (liquid base + vapor overlay)
                Rectangle {
                    id: bar
                    Layout.preferredWidth: 210
                    Layout.fillWidth: false
                    Layout.preferredHeight: 10
                    radius: 5
                    color: "#1f3a66"              // liquid base (dark blue-ish)
                    border.width: 0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: clamp01(vFrac) * parent.width
                        radius: 5
                        color: "#7dc3ff"          // vapor (light blue)
                    }
                }

                // Metrics line (single line like React)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label { text: "T=" + fmtK(tempK);         font.pixelSize: 12; color: "#cfe1f3" }
                    Label { text: "V*=" + fmtFrac(vFrac);     font.pixelSize: 12; color: "#cfe1f3" }
                    Label { text: "V↑=" + fmtKgphK(vaporKgph);font.pixelSize: 12; color: "#cfe1f3" }
                    Label { text: "L↓=" + fmtKgphK(liquidKgph);font.pixelSize: 12; color: "#cfe1f3" }

                    Item { Layout.fillWidth: true }

                    // Draw shown ONCE (at far right), master-like
                    Label {
                        visible: hasDraw
                        text: {
                            if (drawPct > 0.0) return "Draw  " + fmtPct(drawPct)
                            // fallback if pct unknown
                            if (drawLabel && drawLabel.length > 0) return "Draw  " + drawLabel
                            return "Draw"
                        }
                        font.pixelSize: 12
                        color: "#cfe1f3"
                        opacity: 0.95
                    }
                }
            }
        }
    }
}
