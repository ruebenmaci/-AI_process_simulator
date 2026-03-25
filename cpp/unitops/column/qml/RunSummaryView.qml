import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property var appState

    // Optional override from Main.qml (useful for testing)
    property var trayModel: null

    readonly property var effectiveTrayModel: (trayModel !== null && trayModel !== undefined)
                                          ? trayModel
                                          : (appState ? appState.trayModel : null)

    // Theme
    property color fg: "#e6eef8"
    property color fgMuted: "#a9bfd6"
    property color border: "#223041"
    property color panel: "#121a24"
    property color valuePill: "#fde2e2"

    // Force reactive updates when the C++ model changes (QML can't auto-track rowCount() changes).
    property int modelRevision: 0
    Connections {
        target: root.effectiveTrayModel
        ignoreUnknownSignals: true
        function onModelReset()        { root.modelRevision++ }
        function onLayoutChanged()     { root.modelRevision++ }
        function onDataChanged()       { root.modelRevision++ }
        function onRowsInserted()      { root.modelRevision++ }
        function onRowsRemoved()       { root.modelRevision++ }
    }

    function trayCount() {
        // Prefer an explicit Q_INVOKABLE rowCountQml() if you have it.
        if (!effectiveTrayModel) return 0;
        if (effectiveTrayModel.rowCountQml) return effectiveTrayModel.rowCountQml();
        // Some models expose `count` to QML; fall back if present.
        if (effectiveTrayModel.count !== undefined) return effectiveTrayModel.count;
        return 0;
    }

    function topTrayTempK() {
        // include modelRevision to create a dependency
        const _rev = modelRevision;
        const n = trayCount();
        if (!effectiveTrayModel || n <= 0 || !effectiveTrayModel.get) return 0;
        const m = effectiveTrayModel.get(n - 1);
        return (m && m.tempK) ? m.tempK : 0;
    }

    function bottomTrayTempK() {
        const _rev = modelRevision;
        const n = trayCount();
        if (!effectiveTrayModel || n <= 0 || !effectiveTrayModel.get) return 0;
        const m = effectiveTrayModel.get(0);
        return (m && m.tempK) ? m.tempK : 0;
    }

    function fmt1(v) { return Number(v || 0).toFixed(1) }
    function fmt0(v) { return Number(v || 0).toFixed(0) }
    function fmtBarFromPa(pa) { return (Number(pa || 0) / 100000.0).toFixed(3) + " bar" }

    // React-like row widget
    Component {
        id: summaryRow
        Item {
            id: rowRoot
            property string label: ""
            property string value: ""
            property bool valuePillStyle: false

            // IMPORTANT: give the loaded item a real width, or RowLayout can behave oddly
            width: parent ? parent.width : implicitWidth
            implicitHeight: row.implicitHeight

            RowLayout {
                id: row
                anchors.fill: parent
                spacing: 8

                // left column
                Label {
                    text: rowRoot.label
                    Layout.alignment: Qt.AlignVCenter
                    color: root.fgMuted
                    font.pixelSize: 12
                    Layout.preferredWidth: 120
                    Layout.maximumWidth: 120
                    elide: Text.ElideRight
                }

                // right column
                Item {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                    Loader {
                        id: valueLoader
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: rowRoot.valuePillStyle ? pillComp : plainComp

                        // Loader tends to size the loaded item to the Loader's width.
                        // For pills we want "hug content"; for plain text we want it to use the full available width.
                        onLoaded: {
                            if (!item) return;
                            if (rowRoot.valuePillStyle) {
                                item.width = item.implicitWidth;
                            } else {
                                item.width = parent.width;
                            }
                            item.height = item.implicitHeight;
                        }
                    }
                }
            }

            Component {
                id: pillComp
                Rectangle {
                    radius: 6
                    width: implicitWidth
                    color: root.valuePill
                    border.color: "#eab"
                    border.width: 1
                    implicitWidth: Math.min(180, Math.max(64, txt.implicitWidth + 16))
                    implicitHeight: 24

                    Text {
                        id: txt
                        anchors.centerIn: parent
                        text: rowRoot.value
                        color: "#0b0f14"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            Component {
                id: plainComp
                Label {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: rowRoot.value
                    color: root.fg
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                }
            }
        }
    }

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
                text: "Run summary"
                color: root.fg
                font.bold: true
                font.pixelSize: 14
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Loader {
                    id: topT
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Top Tray T"
                        item.valuePillStyle = true
                        item.value = Qt.binding(function(){ return fmt1(topTrayTempK()) + " K" })
                    }
                }

                Loader {
                    id: botT
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Bottom Tray T"
                        item.valuePillStyle = true
                        item.value = Qt.binding(function(){ return fmt1(bottomTrayTempK()) + " K" })
                    }
                }

                Loader {
                    id: topP
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Top P"
                        item.value = Qt.binding(function(){
                            return appState ? fmtBarFromPa(appState.topPressurePa) : "—"
                        })
                    }
                }

                Loader {
                    id: feedTrayRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Feed tray"
                        item.value = Qt.binding(function(){
                            return appState ? String(appState.feedTray + 1) : "—"
                        })
                    }
                }

                Loader {
                    id: statusRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Status"
                        item.value = Qt.binding(function(){
                            return appState ? (appState.solved ? "Solved" : "Not solved") : "—"
                        })
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: root.border; opacity: 0.8 }

                Loader {
                    id: qcRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Qc"
                        item.value = Qt.binding(function(){
                            return appState ? (fmt0(appState.qcCalcKW) + " kW") : "—"
                        })
                    }
                }

                Loader {
                    id: qrRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Qr"
                        item.value = Qt.binding(function(){
                            return appState ? (fmt0(appState.qrCalcKW) + " kW") : "—"
                        })
                    }
                }

                Loader {
                    id: rrRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Reflux frac"
                        item.value = Qt.binding(function(){
                            if (!appState) return "—";
                            // appState.refluxRatio is typically L/D (ratio). Convert to fraction L/(L+D) and percent.
                            const R = Number(appState.refluxRatio);
                            if (!isFinite(R) || R < 0) return "—";
                            const frac = R / (1.0 + R);
                            return (frac * 100.0).toFixed(3) + " %";
                        })
                    }
                }

                Loader {
                    id: buRow
                    Layout.fillWidth: true
                    sourceComponent: summaryRow
                    onLoaded: {
                        item.label = "Boil-up frac"
                        item.value = Qt.binding(function(){
                            if (!appState) return "—";
                            // appState.boilupRatio is typically V/Btm (ratio). Convert to fraction V/(V+B) and percent.
                            const B = Number(appState.boilupRatio);
                            if (!isFinite(B) || B < 0) return "—";
                            const frac = B / (1.0 + B);
                            return (frac * 100.0).toFixed(3) + " %";
                        })
                    }
                }
            }
        }
    }
}
