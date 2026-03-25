import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Pane {
    id: root
    property var flowsheet
    property real mouseSheetX: -1
    property real mouseSheetY: -1
    signal unitDoubleClicked(string unitId)
    signal disconnectCompleted(bool success, string unitId)

    property string connectionMode: "none" // none | feed | distillate | bottoms | disconnect
    property string pendingConnectionUnitId: ""
    property string connectionStatusText: ""

    property real designDrawingWidth: 1180
    property real designDrawingHeight: 760
    property var unitRelPos: ({})
    property real canvasScale: {
        const sx = drawingBorder.width / Math.max(1, designDrawingWidth)
        const sy = drawingBorder.height / Math.max(1, designDrawingHeight)
        return Math.max(0.5, Math.min(Math.min(sx, sy), 2.0))
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function usableWidthForItem(item) {
        return Math.max(0, drawingBorder.width - item.width)
    }

    function usableHeightForItem(item) {
        return Math.max(0, drawingBorder.height - item.height)
    }

    function ensureUnitRelPos(unitId, absX, absY, item) {
        if (unitRelPos[unitId] !== undefined)
            return unitRelPos[unitId]

        const w = item ? usableWidthForItem(item) : Math.max(1, drawingBorder.width)
        const h = item ? usableHeightForItem(item) : Math.max(1, drawingBorder.height)
        const rel = {
            x: clamp((absX - drawingBorder.x) / Math.max(1, w), 0, 1),
            y: clamp((absY - drawingBorder.y) / Math.max(1, h), 0, 1)
        }

        const copy = Object.assign({}, unitRelPos)
        copy[unitId] = rel
        unitRelPos = copy
        return rel
    }

    function updateUnitRelPos(unitId, absX, absY, item) {
        const w = item ? usableWidthForItem(item) : Math.max(1, drawingBorder.width)
        const h = item ? usableHeightForItem(item) : Math.max(1, drawingBorder.height)
        const copy = Object.assign({}, unitRelPos)
        copy[unitId] = {
            x: clamp((absX - drawingBorder.x) / Math.max(1, w), 0, 1),
            y: clamp((absY - drawingBorder.y) / Math.max(1, h), 0, 1)
        }
        unitRelPos = copy
    }

    function applyStoredUnitPosition(item, unitId) {
        if (!item)
            return

        const rel = unitRelPos[unitId] !== undefined
            ? unitRelPos[unitId]
            : ensureUnitRelPos(unitId, item.x, item.y, item)

        const nx = drawingBorder.x + rel.x * usableWidthForItem(item)
        const ny = drawingBorder.y + rel.y * usableHeightForItem(item)
        item.applyConstrainedPosition(nx, ny)
    }

    function repositionUnitsFromStoredCoords() {
        if (!unitRepeater || unitRepeater.count <= 0)
            return

        for (let i = 0; i < unitRepeater.count; ++i) {
            const item = unitRepeater.itemAt(i)
            if (!item)
                continue
            applyStoredUnitPosition(item, item.unitId)
        }
    }


    function unitItemById(unitId) {
        if (!unitRepeater || unitRepeater.count <= 0)
            return null
        for (let i = 0; i < unitRepeater.count; ++i) {
            const item = unitRepeater.itemAt(i)
            if (item && item.unitId === unitId)
                return item
        }
        return null
    }

    function itemCenter(unitId) {
        const item = unitItemById(unitId)
        if (!item)
            return null
        return { x: item.x + item.width / 2, y: item.y + item.height / 2, item: item }
    }

    function itemPortPoint(unitId, portName) {
        const c = itemCenter(unitId)
        if (!c)
            return null

        const item = c.item
        const type = root.flowsheet ? root.flowsheet.unitType(unitId) : ""
        const port = (portName || "").toLowerCase()

        if (type === "column") {
            if (port === "feed")
                return { x: item.x + Math.max(6, item.width * 0.12), y: item.y + item.height * 0.50 }
            if (port === "distillate")
                return { x: item.x + item.width * 0.50, y: item.y + Math.max(4, item.height * 0.06) }
            if (port === "bottoms")
                return { x: item.x + item.width * 0.50, y: item.y + item.height * 0.86 }
        }

        return { x: c.x, y: c.y }
    }

    function drawConnectionLine(ctx, x1, y1, x2, y2) {
        const midX = (x1 + x2) / 2
        ctx.beginPath()
        ctx.moveTo(x1, y1)
        ctx.bezierCurveTo(midX, y1, midX, y2, x2, y2)
        ctx.stroke()
    }

    function handleConnectionClick(unitId) {
        if (!root.flowsheet || root.connectionMode === "none")
            return false

        const clickedType = root.flowsheet.unitType(unitId)
        if (clickedType === "")
            return false

        if (root.connectionMode === "disconnect") {
            if (clickedType !== "stream") {
                root.connectionStatusText = "Disconnect mode: click a stream."
                return true
            }
            const ok = root.flowsheet.disconnectMaterialStream(unitId)
            root.connectionStatusText = ok
                ? (unitId + " disconnected.")
                : (unitId + " had no material binding.")
            root.pendingConnectionUnitId = ""
            connectionOverlay.requestPaint()
            if (ok)
                root.disconnectCompleted(true, unitId)
            return true
        }

        if (root.pendingConnectionUnitId === "") {
            root.pendingConnectionUnitId = unitId
            root.connectionStatusText = "Selected " + unitId + ". Click the matching stream/column to complete the connection."
            connectionOverlay.requestPaint()
            return true
        }

        if (root.pendingConnectionUnitId === unitId) {
            root.connectionStatusText = "Selection cleared."
            root.pendingConnectionUnitId = ""
            connectionOverlay.requestPaint()
            return true
        }

        const firstId = root.pendingConnectionUnitId
        const firstType = root.flowsheet.unitType(firstId)
        let streamId = ""
        let columnId = ""

        if (firstType === "stream" && clickedType === "column") {
            streamId = firstId
            columnId = unitId
        } else if (firstType === "column" && clickedType === "stream") {
            streamId = unitId
            columnId = firstId
        } else {
            root.connectionStatusText = "Connect one stream and one column."
            return true
        }

        let ok = false
        if (root.connectionMode === "feed")
            ok = root.flowsheet.bindColumnFeedStream(columnId, streamId)
        else if (root.connectionMode === "distillate")
            ok = root.flowsheet.bindColumnProductStream(columnId, "distillate", streamId)
        else if (root.connectionMode === "bottoms")
            ok = root.flowsheet.bindColumnProductStream(columnId, "bottoms", streamId)

        root.connectionStatusText = ok
            ? (streamId + " bound to " + columnId + " as " + root.connectionMode + ".")
            : "Binding failed."
        root.pendingConnectionUnitId = ""
        connectionOverlay.requestPaint()
        return true
    }

    function resetConnectionSelection() {
        root.pendingConnectionUnitId = ""
        root.connectionStatusText = ""
        connectionOverlay.requestPaint()
    }

    padding: 12

    background: Rectangle {
        color: "#d8e0e5"
        border.color: "#b9c5cc"
        radius: 10
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: sheet
            anchors.fill: parent
            anchors.margins: 6
            color: "white"
            border.color: "#8f989f"
            border.width: 1
            radius: 2

            MouseArea {
                id: mouseTracker
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                z: -1

                onPositionChanged: function(mouse) {
                    root.mouseSheetX = mouse.x
                    root.mouseSheetY = mouse.y
                }

                onExited: {
                    root.mouseSheetX = -1
                    root.mouseSheetY = -1
                }
            }

            Rectangle {
                id: drawingBorder
                x: 10
                y: 10
                width: sheet.width - 20
                height: sheet.height - 20
                color: "transparent"
                border.color: "#7f8890"
                border.width: 1
            }

            Canvas {
                id: connectionOverlay
                anchors.fill: drawingBorder
                z: 0

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    if (!root.flowsheet)
                        return

                    const connections = root.flowsheet.materialConnections
                    ctx.lineWidth = 2
                    ctx.strokeStyle = "#3e78a8"

                    for (let i = 0; i < connections.length; ++i) {
                        const c = connections[i]
                        const streamId = c.streamUnitId || ""
                        const sourceUnitId = c.sourceUnitId || ""
                        const sourcePort = c.sourcePort || ""
                        const targetUnitId = c.targetUnitId || ""
                        const targetPort = c.targetPort || ""

                        let p1 = null
                        let p2 = null
                        if (targetUnitId !== "") {
                            p1 = root.itemPortPoint(streamId, "")
                            p2 = root.itemPortPoint(targetUnitId, targetPort)
                        } else if (sourceUnitId !== "") {
                            p1 = root.itemPortPoint(sourceUnitId, sourcePort)
                            p2 = root.itemPortPoint(streamId, "")
                        }

                        if (!p1 || !p2)
                            continue

                        root.drawConnectionLine(ctx, p1.x - drawingBorder.x, p1.y - drawingBorder.y, p2.x - drawingBorder.x, p2.y - drawingBorder.y)
                    }

                    if (root.pendingConnectionUnitId !== "") {
                        const pending = root.itemPortPoint(root.pendingConnectionUnitId, root.connectionMode) || root.itemPortPoint(root.pendingConnectionUnitId, "")
                        if (pending) {
                            ctx.beginPath()
                            ctx.setLineDash([5, 5])
                            ctx.arc(pending.x - drawingBorder.x, pending.y - drawingBorder.y, 12, 0, Math.PI * 2)
                            ctx.strokeStyle = "#cc7a00"
                            ctx.stroke()
                            ctx.setLineDash([])
                        }
                    }
                }
            }

            Connections {
                target: drawingBorder
                function onWidthChanged() { resizeSyncTimer.restart() }
                function onHeightChanged() { resizeSyncTimer.restart() }
            }

            Repeater {
                id: unitRepeater
                model: root.flowsheet ? root.flowsheet.unitModel : null

                delegate: UnitNodeItem {
                    property bool initializedRelPos: false

                    x: model.x
                    y: model.y
                    unitId: model.unitId
                    name: model.name
                    unitType: model.type
                    flowsheet: root.flowsheet
                    dragBounds: sheet
                    dragPaddingLeft: drawingBorder.x
                    dragPaddingTop: drawingBorder.y
                    dragPaddingRight: sheet.width - (drawingBorder.x + drawingBorder.width)
                    dragPaddingBottom: sheet.height - (drawingBorder.y + drawingBorder.height)
                    exclusionRect: Qt.rect(titleBlock.x, titleBlock.y, titleBlock.width, titleBlock.height)
                    exclusionRect2: Qt.rect(mouseDebugBox.x, mouseDebugBox.y, mouseDebugBox.width, mouseDebugBox.height)
                    selected: root.flowsheet ? root.flowsheet.selectedUnitId === model.unitId : false
                    pendingConnectionSelection: root.pendingConnectionUnitId === model.unitId
                    canvasScale: root.canvasScale

                    Component.onCompleted: {
                        root.ensureUnitRelPos(unitId, model.x, model.y, this)
                        Qt.callLater(function() { root.applyStoredUnitPosition(this, unitId) }.bind(this))
                    }

                    onWidthChanged: Qt.callLater(root.repositionUnitsFromStoredCoords)
                    onHeightChanged: Qt.callLater(root.repositionUnitsFromStoredCoords)

                    onClicked: function(unitId) {
                        if (root.flowsheet)
                            root.flowsheet.selectUnit(unitId)
                        if (root.handleConnectionClick(unitId))
                            return
                    }

                    onDoubleClicked: function(unitId) {
                        if (root.flowsheet)
                            root.flowsheet.selectUnit(unitId)
                        root.unitDoubleClicked(unitId)
                    }

                    onMoved: function(unitId, nodeX, nodeY) {
                        root.updateUnitRelPos(unitId, nodeX, nodeY, this)
                        if (root.flowsheet)
                            root.flowsheet.moveUnit(unitId, nodeX, nodeY)
                        connectionOverlay.requestPaint()
                    }
                }
            }

            Timer {
                id: resizeSyncTimer
                interval: 0
                repeat: false
                onTriggered: {
                    root.repositionUnitsFromStoredCoords()
                    connectionOverlay.requestPaint()
                }
            }

            Connections {
                target: root.flowsheet
                function onMaterialConnectionsChanged() { connectionOverlay.requestPaint() }
                function onSelectedUnitChanged() { connectionOverlay.requestPaint() }
            }

            Rectangle {
                id: mouseDebugBox
                anchors.left: drawingBorder.left
                anchors.bottom: drawingBorder.bottom
                anchors.margins: 6
                width: 150
                height: 30
                color: "white"
                border.color: "#7f8890"
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    font.pixelSize: 12
                    color: "#31404a"
                    text: root.mouseSheetX >= 0
                          ? "Mouse: " + Math.round(root.mouseSheetX) + ", " + Math.round(root.mouseSheetY)
                          : "Mouse: -, -"
                }
            }

            Rectangle {
                id: titleBlock
                anchors.right: drawingBorder.right
                anchors.bottom: drawingBorder.bottom
                width: 220
                height: 82
                color: "white"
                border.color: "#7f8890"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label {
                            text: "Title"
                            font.bold: true
                            color: "#2f3b44"
                            Layout.preferredWidth: 56
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "transparent" }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#b7bfc5" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "Date"; font.bold: true; color: "#51616c"; Layout.preferredWidth: 56 }
                        Label { text: Qt.formatDate(new Date(), "yyyy-MM-dd"); color: "#31404a"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "Rev"; font.bold: true; color: "#51616c"; Layout.preferredWidth: 56 }
                        Label { text: "0"; color: "#31404a"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "Drawn By"; font.bold: true; color: "#51616c"; Layout.preferredWidth: 56 }
                        Label { text: ""; color: "#31404a"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                }
            }
        }
    }
}
