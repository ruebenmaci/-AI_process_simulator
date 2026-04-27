import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnProfilesPanel.qml — Profiles tab.
//
//  Three sub-tabs accessed via a PTabBar at the top:
//
//    1. Tray Table       — per-tray tabular view with V/L bar visualization
//    2. Visual Profiles  — Canvas line chart of Temp/Pressure/VapFrac/etc.
//                          vs. tray number, with profile selector tabs
//    3. Compositions     — per-component x/y composition table with chart
//
//  The component selector in Compositions is a PComboBox; the composition
//  table is a read-only PSpreadsheet with a frozen "Tray" column via
//  rowLabels (matching the stream-side StreamCompositionPanel convention).
//  The composition profile chart preserves the Canvas plotting code from
//  the original DistillationColumn.qml. Visual Profiles likewise uses a
//  Canvas inside a PGroupBox.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    // 0 = Tray Table, 1 = Visual Profiles, 2 = Compositions
    property int currentSubTab: 0

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _fmt0(x) { var n = Number(x); return isFinite(n) ? Math.round(n).toString() : "—" }
    function _fmt2(x) { var n = Number(x); return isFinite(n) ? n.toFixed(2) : "—" }
    function _fmt3(x) { var n = Number(x); return isFinite(n) ? n.toFixed(3) : "—" }

    // Computed pressure at a given tray (top + dp × distance from top).
    function _trayPressurePa(trayNumber) {
        if (!appState) return 0
        return appState.topPressurePa + appState.dpPerTrayPa * (appState.trays - trayNumber)
    }

    // ── Tray Table column-width contract ────────────────────────────────────
    readonly property int trayColW:    50
    readonly property int tempColW:    90
    readonly property int pressColW:   100
    readonly property int vfColW:      75
    readonly property int liqColW:     90
    readonly property int vapColW:     90
    readonly property int drawColMinW: 100
    readonly property int barColW:     150

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4

            // ── Sub-tab strip ───────────────────────────────────────────────
            PTabBar {
                Layout.fillWidth: false
                tabs: [
                    { text: "Tray Table" },
                    { text: "Visual Profiles" },
                    { text: "Compositions" }
                ]
                currentIndex: root.currentSubTab
                onTabClicked: function(i) { root.currentSubTab = i }
            }

            // ── Body ────────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ─────────────────────────────────────────────────────────
                //  Sub-tab 0: Tray Table
                // ─────────────────────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.currentSubTab === 0

                    PGroupBox {
                        anchors.fill: parent
                        caption: "Tray Profiles"
                        contentPadding: 8
                        fillContent: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Legend strip
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                spacing: 8
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 16; height: 8; radius: 2; color: "#67b0ff"
                                            Layout.alignment: Qt.AlignVCenter }
                                Text { text: "Vapor (V*)"; font.pixelSize: 9; color: "#526571"
                                       Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: 16; height: 8; radius: 2; color: "#294f8f"
                                            Layout.alignment: Qt.AlignVCenter }
                                Text { text: "Liquid (1−V*)"; font.pixelSize: 9; color: "#526571"
                                       Layout.alignment: Qt.AlignVCenter }
                            }

                            // Header row
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    spacing: 0
                                    Text { Layout.preferredWidth: root.trayColW;  Layout.maximumWidth: root.trayColW
                                           text: "Tray"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter }
                                    Text { Layout.preferredWidth: root.tempColW;  Layout.maximumWidth: root.tempColW
                                           text: "Temp (K)"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.preferredWidth: root.pressColW; Layout.maximumWidth: root.pressColW
                                           text: "Pressure (Pa)"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.preferredWidth: root.vfColW;    Layout.maximumWidth: root.vfColW
                                           text: "Vap.Frac"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.preferredWidth: root.liqColW;   Layout.maximumWidth: root.liqColW
                                           text: "Liq. Flow"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.preferredWidth: root.vapColW;   Layout.maximumWidth: root.vapColW
                                           text: "Vap. Flow"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.fillWidth: true; Layout.minimumWidth: root.drawColMinW
                                           text: "Draw"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { Layout.preferredWidth: root.barColW; Layout.maximumWidth: root.barColW
                                           text: "V* / L*"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"
                                           verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 1
                                    color: "#97a2ad"
                                }
                            }

                            // Tray rows
                            ListView {
                                id: trayList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                verticalLayoutDirection: ListView.BottomToTop
                                model: root.appState ? root.appState.trayModel : null
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Item {
                                    id: trayRow
                                    width: trayList.width
                                    height: 22
                                    property real vf: Math.max(0, Math.min(1, model.vaporFrac || 0))

                                    Rectangle {
                                        anchors.fill: parent
                                        color: index % 2 === 0 ? "#f4f6f8" : "#ffffff"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        spacing: 0
                                        Text { Layout.preferredWidth: root.trayColW;  Layout.maximumWidth: root.trayColW
                                               text: model.trayNumber || "—"; font.pixelSize: 10; color: "#1f2a34"
                                               verticalAlignment: Text.AlignVCenter }
                                        Text { Layout.preferredWidth: root.tempColW;  Layout.maximumWidth: root.tempColW
                                               text: root._fmt3(model.tempK); font.pixelSize: 10; color: "#1c4ea7"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               rightPadding: 4 }
                                        Text { Layout.preferredWidth: root.pressColW; Layout.maximumWidth: root.pressColW
                                               text: root._fmt0(root._trayPressurePa(model.trayNumber))
                                               font.pixelSize: 10; color: "#1c4ea7"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               rightPadding: 4 }
                                        Text { Layout.preferredWidth: root.vfColW;    Layout.maximumWidth: root.vfColW
                                               text: root._fmt3(model.vaporFrac); font.pixelSize: 10; color: "#1c4ea7"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               rightPadding: 4 }
                                        Text { Layout.preferredWidth: root.liqColW;   Layout.maximumWidth: root.liqColW
                                               text: root._fmt0(model.liquidFlow); font.pixelSize: 10; color: "#1c4ea7"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               rightPadding: 4 }
                                        Text { Layout.preferredWidth: root.vapColW;   Layout.maximumWidth: root.vapColW
                                               text: root._fmt0(model.vaporFlow); font.pixelSize: 10; color: "#1c4ea7"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               rightPadding: 4 }
                                        Text { Layout.fillWidth: true; Layout.minimumWidth: root.drawColMinW
                                               text: model.drawLabel || ""; font.pixelSize: 9; color: "#d6b74a"
                                               verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                               elide: Text.ElideRight; rightPadding: 8 }
                                        Item {
                                            Layout.preferredWidth: root.barColW
                                            Layout.maximumWidth:   root.barColW
                                            Layout.preferredHeight: 22
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 4
                                                anchors.rightMargin: 4
                                                height: 8; radius: 4
                                                color: "#294f8f"
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width * trayRow.vf
                                                    radius: 4
                                                    color: "#67b0ff"
                                                }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1
                                        color: "#d8dde2"
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.appState
                                             || !root.appState.trayModel
                                             || root.appState.trayModel.rowCount() === 0
                                    text: "Run solver to populate tray table"
                                    color: "#526571"
                                    font.pixelSize: 10
                                    font.italic: true
                                }
                            }
                        }
                    }
                }

                // ─────────────────────────────────────────────────────────
                //  Sub-tab 1: Visual Profiles
                // ─────────────────────────────────────────────────────────
                Item {
                    id: visualProfilesItem
                    anchors.fill: parent
                    visible: root.currentSubTab === 1

                    property var profileDefs: [
                        { key: "tempK",      label: "Temperature",     unit: "K",    color: "#2e73b8" },
                        { key: "pressure",   label: "Pressure",        unit: "Pa",   color: "#7c3aed" },
                        { key: "vaporFrac",  label: "Vapour Fraction", unit: "—",    color: "#0891b2" },
                        { key: "liquidFlow", label: "Liquid Flow",     unit: "kg/h", color: "#059669" },
                        { key: "vaporFlow",  label: "Vapour Flow",     unit: "kg/h", color: "#d97706" }
                    ]
                    property int profileIndex: 0
                    property var activeDef: profileDefs[profileIndex]

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        // Profile-selector tab strip
                        PTabBar {
                            Layout.fillWidth: false
                            tabs: visualProfilesItem.profileDefs.map(function(def) {
                                return { text: def.label }
                            })
                            currentIndex: visualProfilesItem.profileIndex
                            onTabClicked: function(i) {
                                visualProfilesItem.profileIndex = i
                                profileCanvas.requestPaint()
                            }
                        }

                        // Plot frame
                        PGroupBox {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            caption: visualProfilesItem.activeDef.label
                                     + " ("
                                     + visualProfilesItem.activeDef.unit
                                     + ")"
                            contentPadding: 8
                            fillContent: true

                            Canvas {
                                id: profileCanvas
                                anchors.fill: parent
                                readonly property int lm: 46
                                readonly property int rm: 16
                                readonly property int tm: 14
                                readonly property int bm: 56

                                property var trayModel: root.appState ? root.appState.trayModel : null
                                property var def: visualProfilesItem.activeDef
                                Connections {
                                    target: profileCanvas.trayModel
                                    ignoreUnknownSignals: true
                                    function onDataChanged() { profileCanvas.requestPaint() }
                                }
                                onDefChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cw = width - lm - rm
                                    var ch = height - tm - bm
                                    ctx.fillStyle = "#ffffff"
                                    ctx.fillRect(lm, tm, cw, ch)
                                    ctx.strokeStyle = "#2a2a2a"
                                    ctx.lineWidth = 1
                                    ctx.strokeRect(lm, tm, cw, ch)

                                    var model = profileCanvas.trayModel
                                    var pdef = profileCanvas.def
                                    if (!model || model.rowCount() === 0 || !pdef) {
                                        ctx.fillStyle = "#9ba8bf"
                                        ctx.font = "13px sans-serif"
                                        ctx.textAlign = "center"
                                        ctx.fillText("No data – run solver", lm + cw / 2, tm + ch / 2)
                                        return
                                    }
                                    var pts = []
                                    var nTrays = root.appState ? root.appState.trays : 0
                                    var p0 = root.appState ? root.appState.topPressurePa : 0
                                    var dp = root.appState ? root.appState.dpPerTrayPa : 0
                                    for (var r = 0; r < model.rowCount(); r++) {
                                        var row = model.get(r)
                                        var xVal = pdef.key === "pressure"
                                                   ? (p0 + dp * (nTrays - row.trayNumber))
                                                   : row[pdef.key]
                                        pts.push({ tray: row.trayNumber, x: Number(xVal || 0) })
                                    }
                                    pts.sort(function(a, b){ return a.tray - b.tray })
                                    if (pts.length === 0) return

                                    var minTray = pts[0].tray
                                    var maxTray = pts[pts.length - 1].tray
                                    var minX = pts[0].x
                                    var maxX = pts[0].x
                                    for (var k = 1; k < pts.length; k++) {
                                        if (pts[k].x < minX) minX = pts[k].x
                                        if (pts[k].x > maxX) maxX = pts[k].x
                                    }
                                    var xPad = (maxX - minX) * 0.06 || Math.abs(maxX) * 0.05 || 1
                                    var xLo = minX - xPad
                                    var xHi = maxX + xPad
                                    var rngX = xHi - xLo || 1
                                    var rngTray = (maxTray - minTray) || 1
                                    var nGX = 6
                                    var nGY = Math.min(pts.length, 10)

                                    // Grid
                                    ctx.strokeStyle = "#dde4f0"
                                    ctx.lineWidth = 1
                                    ctx.setLineDash([3, 3])
                                    for (var gi = 0; gi <= nGX; gi++) {
                                        var gx = lm + gi * (cw / nGX)
                                        ctx.beginPath()
                                        ctx.moveTo(gx, tm)
                                        ctx.lineTo(gx, tm + ch)
                                        ctx.stroke()
                                    }
                                    for (var gj = 0; gj <= nGY; gj++) {
                                        var gy = tm + ch - gj * (ch / nGY)
                                        ctx.beginPath()
                                        ctx.moveTo(lm, gy)
                                        ctx.lineTo(lm + cw, gy)
                                        ctx.stroke()
                                    }
                                    ctx.setLineDash([])

                                    // Y axis labels (tray numbers)
                                    ctx.fillStyle = "#5a6472"
                                    ctx.font = "10px sans-serif"
                                    ctx.textAlign = "right"
                                    var step = Math.max(1, Math.round(pts.length / nGY))
                                    for (var yi = 0; yi < pts.length; yi += step) {
                                        var yp = tm + ch - (pts[yi].tray - minTray) / rngTray * ch
                                        ctx.fillText(pts[yi].tray, lm - 4, yp + 4)
                                    }

                                    // Y axis title (rotated)
                                    ctx.save()
                                    ctx.fillStyle = "#1f2430"
                                    ctx.font = "bold 11px sans-serif"
                                    ctx.textAlign = "center"
                                    ctx.translate(13, tm + ch / 2)
                                    ctx.rotate(-Math.PI / 2)
                                    ctx.fillText("Tray Number (1 = Bottoms)", 0, 0)
                                    ctx.restore()

                                    // X axis labels
                                    ctx.fillStyle = "#5a6472"
                                    ctx.font = "10px sans-serif"
                                    ctx.textAlign = "center"
                                    for (var xi = 0; xi <= nGX; xi++) {
                                        var xv = xLo + xi * rngX / nGX
                                        var xp = lm + xi * (cw / nGX)
                                        var xStr = Math.abs(xv) >= 10000
                                                   ? xv.toExponential(2)
                                                   : Math.abs(xv) >= 100
                                                     ? xv.toFixed(0)
                                                     : Math.abs(xv) >= 1
                                                       ? xv.toFixed(2)
                                                       : xv.toFixed(4)
                                        ctx.fillText(xStr, xp, tm + ch + 14)
                                    }
                                    // X axis title
                                    ctx.fillStyle = "#1f2430"
                                    ctx.font = "bold 11px sans-serif"
                                    ctx.textAlign = "center"
                                    ctx.fillText(pdef.label + " (" + pdef.unit + ")",
                                                 lm + cw / 2, tm + ch + 44)

                                    // Line
                                    ctx.strokeStyle = pdef.color
                                    ctx.lineWidth = 2
                                    ctx.beginPath()
                                    for (var p = 0; p < pts.length; p++) {
                                        var px = lm + (pts[p].x - xLo) / rngX * cw
                                        var py = tm + ch - (pts[p].tray - minTray) / rngTray * ch
                                        if (p === 0) ctx.moveTo(px, py)
                                        else         ctx.lineTo(px, py)
                                    }
                                    ctx.stroke()

                                    // Dots
                                    ctx.fillStyle = pdef.color
                                    for (var d = 0; d < pts.length; d++) {
                                        var dpx = lm + (pts[d].x - xLo) / rngX * cw
                                        var dpy = tm + ch - (pts[d].tray - minTray) / rngTray * ch
                                        ctx.beginPath()
                                        ctx.arc(dpx, dpy, 3.5, 0, 2 * Math.PI)
                                        ctx.fill()
                                    }
                                }
                            }
                        }
                    }
                }

                // ─────────────────────────────────────────────────────────
                //  Sub-tab 2: Compositions
                // ─────────────────────────────────────────────────────────
                Item {
                    id: compositionsItem
                    anchors.fill: parent
                    visible: root.currentSubTab === 2

                    property var  compNames:    root.appState ? root.appState.componentNames : []
                    property int  selectedComp: 0
                    property bool showVapor:    false

                    // Repaint chart and refresh table whenever component, phase,
                    // or upstream models change.
                    onSelectedCompChanged: {
                        compTable.refresh()
                        compChartCanvas.requestPaint()
                    }
                    onShowVaporChanged: compChartCanvas.requestPaint()
                    onCompNamesChanged: {
                        if (selectedComp >= compNames.length) selectedComp = 0
                        compTable.refresh()
                        compChartCanvas.requestPaint()
                    }
                    onVisibleChanged: if (visible) {
                        compTable.refresh()
                        compChartCanvas.requestPaint()
                    }

                    Connections {
                        target: root.appState
                        ignoreUnknownSignals: true
                        function onComponentNamesChanged() {
                            compositionsItem.selectedComp = 0
                            compTable.refresh()
                            compChartCanvas.requestPaint()
                        }
                        function onFeedTrayChanged() { compChartCanvas.requestPaint() }
                    }
                    Connections {
                        target: root.appState ? root.appState.trayModel : null
                        ignoreUnknownSignals: true
                        function onDataChanged()  { compTable.refresh(); compChartCanvas.requestPaint() }
                        function onModelReset()   { compTable.refresh(); compChartCanvas.requestPaint() }
                        function onRowsInserted() { compTable.refresh(); compChartCanvas.requestPaint() }
                        function onRowsRemoved()  { compTable.refresh(); compChartCanvas.requestPaint() }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 6

                        // ── Top half: per-tray composition table ─────────
                        PGroupBox {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: 1   // 50/50 split via fillHeight on both halves
                            caption: "Tray Compositions  (mole fractions)"
                            contentPadding: 8
                            fillContent: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 4

                                // Component selector row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    PGridLabel {
                                        Layout.preferredWidth: 100
                                        text: "Component"
                                    }

                                    PComboBox {
                                        id: compSelectorTbl
                                        Layout.preferredWidth: 200
                                        Layout.minimumWidth: 200
                                        fontSize: 10
                                        minimumContentWidth: 0
                                        model: compositionsItem.compNames
                                        currentIndex: compositionsItem.selectedComp
                                        onActivated: function(i) {
                                            compositionsItem.selectedComp = i
                                        }
                                        onModelChanged: { currentIndex = 0 }
                                    }

                                    PGridLabel {
                                        Layout.fillWidth: true
                                        text: compositionsItem.compNames.length > 0
                                              ? (compositionsItem.compNames.length + " components in system")
                                              : ""
                                    }
                                }

                                // Composition table — frozen "Tray" column via
                                // rowLabels (highest tray on top, mirroring the
                                // physical column layout: condensate top, reboiler
                                // bottom). Read-only since this is a result view.
                                PSpreadsheet {
                                    id: compTable
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    readOnly: true
                                    stretchToWidth: true
                                    cornerLabel: "Tray"
                                    numCols: 2
                                    numRows: 0
                                    defaultColW: 160
                                    hdrColW: 60
                                    colLabels: ["x  (liquid mol frac)", "y  (vapor mol frac)"]

                                    function refresh() {
                                        var model = root.appState ? root.appState.trayModel : null
                                        if (!model || model.rowCount() === 0
                                                || compositionsItem.compNames.length === 0) {
                                            numRows = 0
                                            rowLabels = []
                                            return
                                        }
                                        var ci = compositionsItem.selectedComp
                                        var n  = model.rowCount()

                                        // Build row order top→bottom: highest tray
                                        // number first. This puts the condenser
                                        // tray at the top of the table.
                                        var order = []
                                        for (var i = 0; i < n; i++) {
                                            var row = model.get(i)
                                            order.push({
                                                tray: row.trayNumber,
                                                xArr: row.xLiq || [],
                                                yArr: row.yVap || []
                                            })
                                        }
                                        order.sort(function(a, b) { return b.tray - a.tray })

                                        numRows = order.length

                                        var labels = []
                                        for (var k = 0; k < order.length; k++)
                                            labels.push(String(order[k].tray))
                                        rowLabels = labels

                                        for (var r = 0; r < order.length; r++) {
                                            var xv = order[r].xArr[ci]
                                            var yv = order[r].yArr[ci]
                                            setCell(r, 0,
                                                (xv !== undefined && xv !== null && isFinite(xv))
                                                    ? Number(xv).toFixed(6) : "—")
                                            setCell(r, 1,
                                                (yv !== undefined && yv !== null && isFinite(yv))
                                                    ? Number(yv).toFixed(6) : "—")
                                        }
                                    }

                                    Component.onCompleted: refresh()
                                }
                            }
                        }

                        // ── Bottom half: composition profile chart ────────
                        PGroupBox {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: 1
                            caption: "Composition Profile"
                            contentPadding: 8
                            fillContent: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 4

                                // Controls row: component selector + phase toggle
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    PGridLabel {
                                        Layout.preferredWidth: 100
                                        text: "Component"
                                    }

                                    PComboBox {
                                        id: compSelectorChart
                                        Layout.preferredWidth: 200
                                        Layout.minimumWidth: 200
                                        fontSize: 10
                                        minimumContentWidth: 0
                                        model: compositionsItem.compNames
                                        currentIndex: compositionsItem.selectedComp
                                        onActivated: function(i) {
                                            compositionsItem.selectedComp = i
                                        }
                                        onModelChanged: { currentIndex = 0 }
                                    }

                                    Item { Layout.preferredWidth: 12 }

                                    PGridLabel {
                                        Layout.preferredWidth: 50
                                        text: "Phase"
                                    }

                                    PTabBar {
                                        Layout.fillWidth: false
                                        tabs: [
                                            { text: "Liquid (x)" },
                                            { text: "Vapor (y)"  }
                                        ]
                                        currentIndex: compositionsItem.showVapor ? 1 : 0
                                        onTabClicked: function(i) {
                                            compositionsItem.showVapor = (i === 1)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                // Chart canvas — line plot of selected component
                                // mole fraction (x or y) versus tray number, with
                                // dashed feed-tray marker.
                                Canvas {
                                    id: compChartCanvas
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    readonly property int lm: 52
                                    readonly property int rm: 20
                                    readonly property int tm: 14
                                    readonly property int bm: 46

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var cw = width  - lm - rm
                                        var ch = height - tm - bm
                                        if (cw < 10 || ch < 10) return

                                        ctx.fillStyle = "#ffffff"
                                        ctx.fillRect(lm, tm, cw, ch)
                                        ctx.strokeStyle = "#2a2a2a"
                                        ctx.lineWidth = 1
                                        ctx.strokeRect(lm + 0.5, tm + 0.5, cw, ch)

                                        var model = root.appState ? root.appState.trayModel : null
                                        var compIdx = compositionsItem.selectedComp
                                        var vapor   = compositionsItem.showVapor
                                        var compNames = compositionsItem.compNames
                                        var compName  = compIdx < compNames.length
                                                        ? compNames[compIdx] : "?"

                                        if (!model || model.rowCount() === 0
                                                || compNames.length === 0) {
                                            ctx.fillStyle = "#9ba8bf"
                                            ctx.font = "13px sans-serif"
                                            ctx.textAlign = "center"
                                            ctx.fillText("No data – run solver",
                                                         lm + cw / 2, tm + ch / 2)
                                            return
                                        }

                                        var pts = []
                                        for (var r = 0; r < model.rowCount(); r++) {
                                            var row = model.get(r)
                                            var arr = vapor ? row.yVap : row.xLiq
                                            if (!arr || compIdx >= arr.length) continue
                                            var v = Number(arr[compIdx])
                                            if (!isFinite(v)) continue
                                            pts.push({ tray: row.trayNumber, v: v })
                                        }
                                        pts.sort(function(a, b) { return a.tray - b.tray })

                                        if (pts.length === 0) {
                                            ctx.fillStyle = "#9ba8bf"
                                            ctx.font = "13px sans-serif"
                                            ctx.textAlign = "center"
                                            ctx.fillText("No composition data",
                                                         lm + cw / 2, tm + ch / 2)
                                            return
                                        }

                                        var minTray = pts[0].tray
                                        var maxTray = pts[pts.length - 1].tray
                                        var rngTray = Math.max(1, maxTray - minTray)

                                        // Grid (5×5)
                                        ctx.strokeStyle = "#dde4f0"
                                        ctx.lineWidth = 0.7
                                        ctx.setLineDash([3, 3])
                                        for (var gi = 0; gi <= 5; gi++) {
                                            var gx = lm + gi * (cw / 5)
                                            ctx.beginPath()
                                            ctx.moveTo(gx, tm)
                                            ctx.lineTo(gx, tm + ch)
                                            ctx.stroke()
                                        }
                                        for (var gj = 0; gj <= 5; gj++) {
                                            var gy = tm + gj * (ch / 5)
                                            ctx.beginPath()
                                            ctx.moveTo(lm, gy)
                                            ctx.lineTo(lm + cw, gy)
                                            ctx.stroke()
                                        }
                                        ctx.setLineDash([])

                                        // X axis labels (mole fraction 0..1)
                                        ctx.fillStyle = "#5a6472"
                                        ctx.font = "9px sans-serif"
                                        ctx.textAlign = "center"
                                        for (var xi = 0; xi <= 5; xi++) {
                                            ctx.fillText((xi / 5).toFixed(2),
                                                         lm + xi * (cw / 5),
                                                         tm + ch + 12)
                                        }

                                        // Y axis labels (tray numbers, sparse)
                                        ctx.textAlign = "right"
                                        var step = Math.max(1, Math.round(pts.length / 8))
                                        for (var yi = 0; yi < pts.length; yi += step) {
                                            var yp = tm + ch - (pts[yi].tray - minTray) / rngTray * ch
                                            ctx.fillText(pts[yi].tray, lm - 4, yp + 4)
                                        }

                                        // Y axis title (rotated)
                                        ctx.save()
                                        ctx.fillStyle = "#1f2430"
                                        ctx.font = "bold 10px sans-serif"
                                        ctx.textAlign = "center"
                                        ctx.translate(14, tm + ch / 2)
                                        ctx.rotate(-Math.PI / 2)
                                        ctx.fillText("Tray  (1 = Bottoms)", 0, 0)
                                        ctx.restore()

                                        // X axis title
                                        ctx.fillStyle = "#1f2430"
                                        ctx.font = "bold 10px sans-serif"
                                        ctx.textAlign = "center"
                                        ctx.fillText(
                                            compName + "  —  " + (vapor
                                                ? "Vapor mole fraction  y"
                                                : "Liquid mole fraction  x"),
                                            lm + cw / 2, tm + ch + 34)

                                        // Plot line
                                        var lineColor = vapor ? "#b45309" : "#1e6fb5"
                                        ctx.strokeStyle = lineColor
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        for (var p = 0; p < pts.length; p++) {
                                            var px = lm + pts[p].v * cw
                                            var py = tm + ch - (pts[p].tray - minTray) / rngTray * ch
                                            if (p === 0) ctx.moveTo(px, py)
                                            else         ctx.lineTo(px, py)
                                        }
                                        ctx.stroke()

                                        // Dots
                                        ctx.fillStyle = lineColor
                                        for (var d = 0; d < pts.length; d++) {
                                            var dpx = lm + pts[d].v * cw
                                            var dpy = tm + ch - (pts[d].tray - minTray) / rngTray * ch
                                            ctx.beginPath()
                                            ctx.arc(dpx, dpy, 3.5, 0, 2 * Math.PI)
                                            ctx.fill()
                                        }

                                        // Feed-tray dashed marker
                                        if (root.appState && root.appState.feedTray) {
                                            var ft = root.appState.feedTray
                                            if (ft >= minTray && ft <= maxTray) {
                                                var fy = tm + ch - (ft - minTray) / rngTray * ch
                                                ctx.strokeStyle = "#d4720a"
                                                ctx.lineWidth = 1.5
                                                ctx.setLineDash([4, 3])
                                                ctx.beginPath()
                                                ctx.moveTo(lm, fy)
                                                ctx.lineTo(lm + cw, fy)
                                                ctx.stroke()
                                                ctx.setLineDash([])
                                                ctx.fillStyle = "#d4720a"
                                                ctx.font = "9px sans-serif"
                                                ctx.textAlign = "left"
                                                ctx.fillText("Feed tray " + ft,
                                                             lm + 3, fy - 3)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
