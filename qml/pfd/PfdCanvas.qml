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

    // ── Placement mode ────────────────────────────────────────────────────
    // Set placementType to "column" or "stream" to enter placement mode.
    // A ghost icon follows the cursor; left-click drops the unit there.
    property string placementType: ""   // "" = inactive
    readonly property bool inPlacementMode: placementType !== ""

    function beginPlacement(unitType) {
        placementType = unitType
        sheet.forceActiveFocus()
    }

    function cancelPlacement() {
        placementType = ""
    }

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

    function iconBoxSizeForItem(item) {
        return item && item.iconNodeBoxSize ? item.iconNodeBoxSize : 50
    }

    function usableWidthForItem(item) {
        // Use the stable icon box width, not the variable full delegate width.
        return Math.max(0, drawingBorder.width - iconBoxSizeForItem(item))
    }

    function usableHeightForItem(item) {
        // Use the stable icon box height, not the full delegate height including label area.
        return Math.max(0, drawingBorder.height - iconBoxSizeForItem(item))
    }

    function iconBoxCenterFor(absX, absY, item) {
        const box = iconBoxSizeForItem(item)
        return {
            x: absX + (item ? item.width / 2 : box / 2),
            y: absY + box / 2
        }
    }

    function relPosForIconCenter(centerX, centerY, boxSize) {
        const box = boxSize > 0 ? boxSize : 50
        const usableW = Math.max(1, drawingBorder.width - box)
        const usableH = Math.max(1, drawingBorder.height - box)
        const clampedCenterX = clamp(centerX, drawingBorder.x + box / 2, drawingBorder.x + drawingBorder.width - box / 2)
        const clampedCenterY = clamp(centerY, drawingBorder.y + box / 2, drawingBorder.y + drawingBorder.height - box / 2)
        return {
            x: clamp((clampedCenterX - drawingBorder.x - box / 2) / usableW, 0, 1),
            y: clamp((clampedCenterY - drawingBorder.y - box / 2) / usableH, 0, 1)
        }
    }

    function seedUnitRelPosFromClick(unitId, sheetX, sheetY, boxSize) {
        if (!unitId || unitId === "")
            return
        const copy = Object.assign({}, unitRelPos)
        copy[unitId] = relPosForIconCenter(sheetX, sheetY, boxSize)
        unitRelPos = copy
    }

    function ensureUnitRelPos(unitId, absX, absY, item) {
        if (unitRelPos[unitId] !== undefined)
            return unitRelPos[unitId]

        const box = iconBoxSizeForItem(item)
        const center = iconBoxCenterFor(absX, absY, item)
        const w = usableWidthForItem(item)
        const h = usableHeightForItem(item)
        const rel = {
            x: clamp((center.x - drawingBorder.x - box / 2) / Math.max(1, w), 0, 1),
            y: clamp((center.y - drawingBorder.y - box / 2) / Math.max(1, h), 0, 1)
        }

        const copy = Object.assign({}, unitRelPos)
        copy[unitId] = rel
        unitRelPos = copy
        return rel
    }

    function updateUnitRelPos(unitId, absX, absY, item) {
        const box = iconBoxSizeForItem(item)
        const center = iconBoxCenterFor(absX, absY, item)
        const w = usableWidthForItem(item)
        const h = usableHeightForItem(item)
        const copy = Object.assign({}, unitRelPos)
        copy[unitId] = {
            x: clamp((center.x - drawingBorder.x - box / 2) / Math.max(1, w), 0, 1),
            y: clamp((center.y - drawingBorder.y - box / 2) / Math.max(1, h), 0, 1)
        }
        unitRelPos = copy
    }

    function applyStoredUnitPosition(item, unitId) {
        if (!item)
            return

        const rel = unitRelPos[unitId] !== undefined
            ? unitRelPos[unitId]
            : ensureUnitRelPos(unitId, item.x, item.y, item)

        const box = iconBoxSizeForItem(item)
        const centerX = drawingBorder.x + box / 2 + rel.x * usableWidthForItem(item)
        const centerY = drawingBorder.y + box / 2 + rel.y * usableHeightForItem(item)
        const nx = centerX - item.width / 2
        const ny = centerY - box / 2
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
            const iconH = item.height - item.labelAreaHeight - 4
            // visualContainer is horizontally centered in item; icon (42px) centered in 50px box
            const boxLeft = item.x + (item.width - item.iconNodeBoxSize) / 2
            const boxW    = item.iconNodeBoxSize
            if (port === "feed")
                return { x: boxLeft,                   y: item.y + iconH * 0.542 }
            if (port === "distillate")
                return { x: boxLeft + boxW * 0.917,    y: item.y + iconH * 0.146 }
            if (port === "bottoms")
                return { x: boxLeft + boxW * 0.917,    y: item.y + iconH * 0.896 }
        }

        if (type === "heater" || type === "cooler") {
            // Simple box icon: feed enters left-center, product exits right-center
            const boxLeft = item.x + (item.width - item.iconNodeBoxSize) / 2
            const boxW    = item.iconNodeBoxSize
            const midY    = item.y + item.iconNodeBoxSize / 2
            if (port === "feed")    return { x: boxLeft,        y: midY }
            if (port === "product") return { x: boxLeft + boxW, y: midY }
            return { x: item.x + item.width / 2, y: midY }
        }

        if (type === "heat_exchanger") {
            const pp = hexPortPoint(item, port)
            if (pp) return { x: pp.x, y: pp.y }
            return { x: item.x + item.width / 2, y: item.y + item.iconNodeBoxSize / 2 }
        }

        if (type === "stream") {
            // visualContainer (50px) is horizontally centered; icon (42px) centered inside it
            const boxLeft = item.x + (item.width - item.iconNodeBoxSize) / 2
            const iconY   = item.y + item.iconNodeBoxSize / 2
            if (port === "tip")   // outgoing: right edge of icon box
                return { x: boxLeft + item.iconNodeBoxSize, y: iconY }
            if (port === "tail")  // incoming: left edge of icon box
                return { x: boxLeft,                        y: iconY }
            return { x: item.x + item.width / 2, y: iconY }
        }
    }

    function drawConnectionLine(ctx, x1, y1, x2, y2) {
        // Orthogonal routing: horizontal leg then vertical leg (engineering P&ID style)
        const midX = (x1 + x2) / 2
        ctx.beginPath()
        ctx.moveTo(x1, y1)
        ctx.lineTo(midX, y1)   // horizontal leg
        ctx.lineTo(midX, y2)   // vertical leg
        ctx.lineTo(x2, y2)     // final horizontal to target
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
        let equipId  = ""

        const isEquip = (t) => t === "column" || t === "heater" || t === "cooler" || t === "heat_exchanger"

        if (firstType === "stream" && isEquip(clickedType)) {
            streamId = firstId
            equipId  = unitId
        } else if (isEquip(firstType) && clickedType === "stream") {
            streamId = unitId
            equipId  = firstId
        } else {
            root.connectionStatusText = "Connect one stream and one unit."
            return true
        }

        const equipType = root.flowsheet.unitType(equipId)
        let ok = false

        if (equipType === "column") {
            if (root.connectionMode === "feed")
                ok = root.flowsheet.bindColumnFeedStream(equipId, streamId)
            else if (root.connectionMode === "distillate")
                ok = root.flowsheet.bindColumnProductStream(equipId, "distillate", streamId)
            else if (root.connectionMode === "bottoms")
                ok = root.flowsheet.bindColumnProductStream(equipId, "bottoms", streamId)
        } else if (equipType === "heater" || equipType === "cooler") {
            if (root.connectionMode === "feed")
                ok = root.flowsheet.bindHeaterFeedStream(equipId, streamId)
            else if (root.connectionMode === "product")
                ok = root.flowsheet.bindHeaterProductStream(equipId, streamId)
            else
                ok = root.flowsheet.bindHeaterFeedStream(equipId, streamId)
        } else if (equipType === "heat_exchanger") {
            // Map connectionMode to HEX port name
            const hexPortMap = { "hotIn": "hotIn", "hotOut": "hotOut",
                                  "coldIn": "coldIn", "coldOut": "coldOut",
                                  "feed": "hotIn", "product": "hotOut" }
            const hexPort = hexPortMap[root.connectionMode] || "hotIn"
            ok = root.flowsheet.bindHexStream(equipId, hexPort, streamId)
        }

        root.connectionStatusText = ok
            ? (streamId + " bound to " + equipId + " as " + root.connectionMode + ".")
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

    function hideContextMenu() {
        contextMenuRect.visible = false
        root.contextMenuUnitId = ""
        root.contextMenuUnitType = ""
        root.contextMenuConnected = false
    }

    function tryDeleteUnit(unitId) {
        if (!root.flowsheet || unitId === "") return
        root.flowsheet.selectUnit(unitId)
        root.flowsheet.deleteSelectedUnitAndConnections()
        root.hideContextMenu()
        connectionOverlay.requestPaint()
    }

    function isStreamConnected(unitId) {
        if (!root.flowsheet) return false
        const connections = root.flowsheet.materialConnections
        for (let i = 0; i < connections.length; ++i) {
            if (connections[i].streamUnitId === unitId)
                return true
        }
        return false
    }

    function unitHasConnections(unitId) {
        if (!root.flowsheet || unitId === "") return false
        const unitType = root.flowsheet.unitType(unitId)
        const connections = root.flowsheet.materialConnections
        if (unitType === "stream")
            return root.isStreamConnected(unitId)
        for (let i = 0; i < connections.length; ++i) {
            if (connections[i].targetUnitId === unitId || connections[i].sourceUnitId === unitId)
                return true
        }
        return false
    }

    function showContextMenu(unitId, sheetX, sheetY) {
        if (!root.flowsheet) return
        const unitType = root.flowsheet.unitType(unitId)
        if (unitType === "") return

        root.flowsheet.selectUnit(unitId)
        root.contextMenuUnitId = unitId
        root.contextMenuUnitType = unitType
        root.contextMenuConnected = root.unitHasConnections(unitId)
        const menuH = root.contextMenuConnected ? 72 : 38
        contextMenuRect.x = Math.max(4, Math.min(sheetX, sheet.width  - 196))
        contextMenuRect.y = Math.max(4, Math.min(sheetY, sheet.height - menuH - 4))
        contextMenuRect.visible = true
    }

    property string contextMenuUnitId: ""
    property string contextMenuUnitType: ""
    property bool   contextMenuConnected: false

    // ── Drag-to-connect snap state ────────────────────────────────────────
    // When a stream is dragged near a column/heater/cooler port, we highlight
    // that port and auto-connect on drop.
    property string snapColumnId: ""    // equipment unit being snapped to
    property string snapPortName: ""    // "feed" | "distillate" | "bottoms" | "product"
    readonly property bool snapActive: snapColumnId !== "" && snapPortName !== ""
    property string draggingUnitId: ""  // unitId of item currently being dragged

    // How close (px) the stream centre must be to a port to snap
    readonly property real snapRadius: 48

    // Port positions on a column item (mirrors itemPortPoint logic)
    function columnPortPoint(colItem, port) {
        if (!colItem) return null
        const iconH   = colItem.height - colItem.labelAreaHeight - 4
        const boxLeft = colItem.x + (colItem.width - colItem.iconNodeBoxSize) / 2
        const boxW    = colItem.iconNodeBoxSize
        if (port === "feed")
            return Qt.point(boxLeft,
                            colItem.y + iconH * 0.542)
        if (port === "distillate")
            return Qt.point(boxLeft + boxW * 0.917,
                            colItem.y + iconH * 0.146)
        if (port === "bottoms")
            return Qt.point(boxLeft + boxW * 0.917,
                            colItem.y + iconH * 0.896)
        return null
    }

    // Port positions on a heater/cooler item
    function heaterPortPoint(item, port) {
        if (!item) return null
        const boxLeft = item.x + (item.width - item.iconNodeBoxSize) / 2
        const boxW    = item.iconNodeBoxSize
        const midY    = item.y + item.iconNodeBoxSize / 2
        if (port === "feed")    return Qt.point(boxLeft,        midY)
        if (port === "product") return Qt.point(boxLeft + boxW, midY)
        return null
    }

    // Port positions on a heat exchanger item
    // Icon viewBox 48x48: ports at y=19 (upper) and y=29 (lower), x=3 (left) x=45 (right)
    // Normalised: upper=19/48=0.396, lower=29/48=0.604
    function hexPortPoint(item, port) {
        if (!item) return null
        const boxLeft = item.x + (item.width - item.iconNodeBoxSize) / 2
        const boxW    = item.iconNodeBoxSize
        const upperY  = item.y + item.iconNodeBoxSize * 0.396
        const lowerY  = item.y + item.iconNodeBoxSize * 0.604
        if (port === "hotIn")   return Qt.point(boxLeft,        lowerY)
        if (port === "hotOut")  return Qt.point(boxLeft + boxW, upperY)
        if (port === "coldIn")  return Qt.point(boxLeft,        upperY)
        if (port === "coldOut") return Qt.point(boxLeft + boxW, lowerY)
        return null
    }

    // Check all equipment for snap proximity while a stream is being dragged.
    function updateSnapTarget(streamItem) {
        if (!root.flowsheet || !streamItem) {
            snapColumnId = ""; snapPortName = ""; return
        }

        const sx = streamItem.x + streamItem.width  / 2
        const sy = streamItem.y + streamItem.height / 2

        const connections = root.flowsheet.materialConnections

        let bestDist = root.snapRadius
        let bestId   = ""
        let bestPort = ""

        for (let i = 0; i < unitRepeater.count; ++i) {
            const item = unitRepeater.itemAt(i)
            if (!item) continue

            const isCol    = item.unitType === "column"
            const isHeater = item.unitType === "heater" || item.unitType === "cooler"
            const isHex    = item.unitType === "heat_exchanger"
            if (!isCol && !isHeater && !isHex) continue

            const equipId = item.unitId
            const ports = isCol  ? ["feed", "distillate", "bottoms"]
                        : isHex  ? ["hotIn", "hotOut", "coldIn", "coldOut"]
                        : ["feed", "product"]

            for (let p = 0; p < ports.length; ++p) {
                const port = ports[p]
                // Skip already-connected ports
                let alreadyConnected = false
                for (let c = 0; c < connections.length; ++c) {
                    const conn = connections[c]
                    if (conn.targetUnitId === equipId && conn.targetPort === port) {
                        alreadyConnected = true; break
                    }
                    if (conn.sourceUnitId === equipId && conn.sourcePort === port) {
                        alreadyConnected = true; break
                    }
                }
                if (alreadyConnected) continue

                const pp = isCol ? columnPortPoint(item, port) : isHex ? hexPortPoint(item, port) : heaterPortPoint(item, port)
                if (!pp) continue

                const dist = Math.sqrt((sx - pp.x) * (sx - pp.x) + (sy - pp.y) * (sy - pp.y))
                if (dist < bestDist) {
                    bestDist = dist
                    bestId   = equipId
                    bestPort = port
                }
            }
        }

        if (bestId !== snapColumnId || bestPort !== snapPortName) {
            snapColumnId = bestId
            snapPortName = bestPort
            connectionOverlay.requestPaint()
        }
    }

    function clearSnapTarget() {
        if (snapColumnId !== "" || snapPortName !== "") {
            snapColumnId = ""
            snapPortName = ""
            connectionOverlay.requestPaint()
        }
    }

    // Attempt auto-connect on drop
    function trySnapConnect(streamId) {
        if (!snapActive || !root.flowsheet) return false
        const equipType = root.flowsheet.unitType(snapColumnId)
        let ok = false
        if (equipType === "heat_exchanger") {
            ok = root.flowsheet.bindHexStream(snapColumnId, snapPortName, streamId)
        } else if (equipType === "column") {
            if (snapPortName === "feed")
                ok = root.flowsheet.bindColumnFeedStream(snapColumnId, streamId)
            else if (snapPortName === "distillate")
                ok = root.flowsheet.bindColumnProductStream(snapColumnId, "distillate", streamId)
            else if (snapPortName === "bottoms")
                ok = root.flowsheet.bindColumnProductStream(snapColumnId, "bottoms", streamId)
        } else if (equipType === "heater" || equipType === "cooler") {
            if (snapPortName === "feed")
                ok = root.flowsheet.bindHeaterFeedStream(snapColumnId, streamId)
            else if (snapPortName === "product")
                ok = root.flowsheet.bindHeaterProductStream(snapColumnId, streamId)
        }
        clearSnapTarget()
        if (ok) connectionOverlay.requestPaint()
        return ok
    }

    // Called from delegate onMoved — checks snap at final dropped position
    function onStreamDropped(unitId) {
        if (!root.flowsheet) return
        if (root.flowsheet.unitType(unitId) !== "stream") {
            clearSnapTarget()
            return
        }
        const item = unitItemById(unitId)
        if (item) {
            updateSnapTarget(item)
            if (root.snapActive)
                trySnapConnect(unitId)
        }
        clearSnapTarget()
    }

    padding: 12

    background: Rectangle {
        color: gAppTheme.canvasBg
        border.color: gAppTheme.toolbarBorder
        radius: 10
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: sheet
            anchors.fill: parent
            anchors.margins: 6
            color: gAppTheme.sheetBg
            border.color: gAppTheme.sheetBorder
            border.width: 1
            radius: 0

            // Background click handler: clears any active PFD highlight when
            // the user clicks empty canvas. Unit clicks are intercepted by
            // each UnitNodeItem's own MouseArea (preventStealing:true,
            // propagateComposedEvents:false), so this only fires for clicks
            // that miss every unit. Sits below mouseTracker so placement-mode
            // clicks still take priority. Only active when not in placement
            // mode and only when there's actually a highlight to clear.
            MouseArea {
                id: highlightClearArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                z: -2
                enabled: !root.inPlacementMode
                    && root.flowsheet
                    && root.flowsheet.highlightedUnitId !== ""
                onClicked: function(mouse) {
                    if (root.flowsheet) root.flowsheet.clearHighlight()
                    mouse.accepted = false   // let other handlers see it too
                }
            }

            // Escape key clears highlight (and cancels placement mode).
            Keys.onEscapePressed: function(event) {
                if (root.flowsheet && root.flowsheet.highlightedUnitId !== "") {
                    root.flowsheet.clearHighlight()
                    event.accepted = true
                    return
                }
                if (root.inPlacementMode) {
                    root.cancelPlacement()
                    event.accepted = true
                }
            }

            MouseArea {
                id: mouseTracker
                anchors.fill: parent
                acceptedButtons: root.inPlacementMode ? Qt.LeftButton | Qt.RightButton : Qt.NoButton
                hoverEnabled: true
                z: root.inPlacementMode ? 10 : -1
                cursorShape: root.inPlacementMode ? Qt.CrossCursor : Qt.ArrowCursor

                onPositionChanged: function(mouse) {
                    root.mouseSheetX = mouse.x
                    root.mouseSheetY = mouse.y
                    // Live snap detection while a stream is being dragged
                    if (root.draggingUnitId !== "") {
                        const item = root.unitItemById(root.draggingUnitId)
                        if (item)
                            root.updateSnapTarget(item)
                    }
                }

                onExited: {
                    root.mouseSheetX = -1
                    root.mouseSheetY = -1
                    root.draggingUnitId = ""
                    root.clearSnapTarget()
                }

                onClicked: function(mouse) {
                    if (!root.inPlacementMode) return
                    if (mouse.button === Qt.RightButton) {
                        root.cancelPlacement()
                        return
                    }
                    // Place the unit so the click lands on the center of the stable 50x50 icon box.
                    const clickX = Math.max(drawingBorder.x, Math.min(mouse.x, drawingBorder.x + drawingBorder.width))
                    const clickY = Math.max(drawingBorder.y, Math.min(mouse.y, drawingBorder.y + drawingBorder.height))
                    const seedBox = 50
                    const seedX = clickX - seedBox / 2
                    const seedY = clickY - seedBox / 2
                    let unitId = ""
                    if (root.placementType === "column")
                        unitId = root.flowsheet.addColumnAndReturnId(seedX, seedY)
                    else if (root.placementType === "stream")
                        unitId = root.flowsheet.addStreamAndReturnId(seedX, seedY)
                    else if (root.placementType === "heater")
                        unitId = root.flowsheet.addHeaterAndReturnId(seedX, seedY)
                    else if (root.placementType === "cooler")
                        unitId = root.flowsheet.addCoolerAndReturnId(seedX, seedY)
                    else if (root.placementType === "heat_exchanger")
                        unitId = root.flowsheet.addHeatExchangerAndReturnId(seedX, seedY)
                    root.seedUnitRelPosFromClick(unitId, clickX, clickY, seedBox)
                    root.cancelPlacement()
                }
            }

            Rectangle {
                id: drawingBorder
                x: 10
                y: 10
                width: sheet.width - 20
                height: sheet.height - 20
                color: "transparent"
                border.color: gAppTheme.titleBlockBorder
                border.width: 2
            }


            // ── Engineering drawing dot grid ─────────────────────────────
            Canvas {
                id: gridCanvas
                anchors.fill: drawingBorder
                z: -1

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const minorSpacing = 20
                    const majorSpacing = 100

                    // Major grid lines (light)
                    ctx.strokeStyle = gAppTheme.gridLineColor
                    ctx.lineWidth = 0.5
                    ctx.setLineDash([])
                    for (let x = majorSpacing; x < width; x += majorSpacing) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                    }
                    for (let y = majorSpacing; y < height; y += majorSpacing) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                    }

                    // Minor dots
                    ctx.fillStyle = gAppTheme.gridDotColor
                    for (let gx = minorSpacing; gx < width; gx += minorSpacing) {
                        for (let gy = minorSpacing; gy < height; gy += minorSpacing) {
                            if (gx % majorSpacing === 0 && gy % majorSpacing === 0) continue
                            ctx.beginPath()
                            ctx.arc(gx, gy, 0.9, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }

                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            Canvas {
                id: connectionOverlay
                anchors.fill: drawingBorder
                z: 0
                enabled: false

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    if (!root.flowsheet)
                        return

                    const connections = root.flowsheet.materialConnections
                    ctx.lineWidth = 1.5
                    ctx.strokeStyle = gAppTheme.materialStreamColor

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
                            // Stream feeds into a column: line starts at stream arrow tip
                            p1 = root.itemPortPoint(streamId, "tip")
                            p2 = root.itemPortPoint(targetUnitId, targetPort)
                        } else if (sourceUnitId !== "") {
                            // Column feeds into stream: line ends at stream tail (left end)
                            p1 = root.itemPortPoint(sourceUnitId, sourcePort)
                            p2 = root.itemPortPoint(streamId, "tail")
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
                            ctx.strokeStyle = gAppTheme.energyStreamColor
                            ctx.stroke()
                            ctx.setLineDash([])
                        }
                    }

                    // ── Draw port dots on all equipment ───────────────────
                    // Column ports (feed left, distillate/bottoms right)
                    for (let ci = 0; ci < unitRepeater.count; ++ci) {
                        const citem = unitRepeater.itemAt(ci)
                        if (!citem) continue

                        if (citem.unitType === "column") {
                            const colPorts = ["feed", "distillate", "bottoms"]
                            for (let cp = 0; cp < colPorts.length; ++cp) {
                                const pp = root.columnPortPoint(citem, colPorts[cp])
                                if (!pp) continue
                                const px = pp.x - drawingBorder.x
                                const py = pp.y - drawingBorder.y
                                ctx.beginPath()
                                ctx.arc(px, py, 4, 0, Math.PI * 2)
                                ctx.fillStyle = "#2e73b8"
                                ctx.fill()
                            }
                        } else if (citem.unitType === "heater" || citem.unitType === "cooler") {
                            const hPorts = ["feed", "product"]
                            const hColor = citem.unitType === "heater" ? "#a73c1c" : "#1c6ea7"
                            for (let hp = 0; hp < hPorts.length; ++hp) {
                                const pp = root.heaterPortPoint(citem, hPorts[hp])
                                if (!pp) continue
                                const px = pp.x - drawingBorder.x
                                const py = pp.y - drawingBorder.y
                                // Outer white ring for visibility over icon
                                ctx.beginPath()
                                ctx.arc(px, py, 5.5, 0, Math.PI * 2)
                                ctx.fillStyle = "#ffffff"
                                ctx.fill()
                                // Coloured dot
                                ctx.beginPath()
                                ctx.arc(px, py, 4, 0, Math.PI * 2)
                                ctx.fillStyle = hColor
                                ctx.fill()
                            }
                        }
                    }

                    // ── Drag-to-connect snap indicator ────────────────────
                    if (root.snapActive) {
                        const snapEquipType = root.flowsheet ? root.flowsheet.unitType(root.snapColumnId) : ""
                        let pp = null
                        if (snapEquipType === "column") {
                            const colItem = root.unitItemById(root.snapColumnId)
                            pp = colItem ? root.columnPortPoint(colItem, root.snapPortName) : null
                        } else if (snapEquipType === "heater" || snapEquipType === "cooler") {
                            const hItem = root.unitItemById(root.snapColumnId)
                            pp = hItem ? root.heaterPortPoint(hItem, root.snapPortName) : null
                        } else if (snapEquipType === "heat_exchanger") {
                            const hItem = root.unitItemById(root.snapColumnId)
                            pp = hItem ? root.hexPortPoint(hItem, root.snapPortName) : null
                        }
                        if (pp) {
                            const px = pp.x - drawingBorder.x
                            const py = pp.y - drawingBorder.y

                            // Outer glow ring
                            ctx.beginPath()
                            ctx.arc(px, py, 14, 0, Math.PI * 2)
                            ctx.strokeStyle = "#00c080"
                            ctx.lineWidth = 3
                            ctx.setLineDash([])
                            ctx.stroke()

                            // Filled inner dot
                            ctx.beginPath()
                            ctx.arc(px, py, 6, 0, Math.PI * 2)
                            ctx.fillStyle = "#00c080"
                            ctx.fill()

                            // Port label — left-side ports draw label to the LEFT of the dot
                            const label = root.snapPortName.charAt(0).toUpperCase()
                                          + root.snapPortName.slice(1)
                            ctx.font = "bold 11px sans-serif"
                            ctx.fillStyle = "#00802a"
                            const isLeftPort = (root.snapPortName === "feed"   ||
                                                root.snapPortName === "hotIn"  ||
                                                root.snapPortName === "coldIn")
                            if (isLeftPort) {
                                ctx.textAlign = "right"
                                ctx.fillText(label, px - 16, py + 4)
                                ctx.textAlign = "left"   // restore default
                            } else {
                                ctx.fillText(label, px + 16, py + 4)
                            }
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
                    highlighted: root.flowsheet ? root.flowsheet.highlightedUnitId === model.unitId : false
                    canvasScale: root.canvasScale

                    Component.onCompleted: {
                        root.ensureUnitRelPos(unitId, model.x, model.y, this)
                        Qt.callLater(function() { root.applyStoredUnitPosition(this, unitId) }.bind(this))
                    }

                    onWidthChanged: Qt.callLater(root.repositionUnitsFromStoredCoords)
                    onHeightChanged: Qt.callLater(root.repositionUnitsFromStoredCoords)

                    onClicked: function(unitId) {
                        root.hideContextMenu()
                        if (root.flowsheet)
                            root.flowsheet.selectUnit(unitId)
                        // Track which stream is being dragged for live snap detection
                        if (root.flowsheet && root.flowsheet.unitType(unitId) === "stream")
                            root.draggingUnitId = unitId
                        if (root.handleConnectionClick(unitId))
                            return
                    }

                    onRightClicked: function(unitId, mouseX, mouseY) {
                        root.showContextMenu(unitId, mouseX, mouseY)
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
                        // Snap-connect: if a stream was dropped near a column port, auto-connect
                        root.onStreamDropped(unitId)
                        root.draggingUnitId = ""
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

            // Polls item position during drag to update live snap indicator
            Timer {
                id: snapPollTimer
                interval: 33   // ~30 fps
                repeat: true
                running: root.draggingUnitId !== ""
                onTriggered: {
                    if (root.draggingUnitId === "") {
                        stop()
                        return
                    }
                    const item = root.unitItemById(root.draggingUnitId)
                    if (item)
                        root.updateSnapTarget(item)
                    else
                        root.clearSnapTarget()
                }
            }

            Connections {
                target: root.flowsheet
                function onMaterialConnectionsChanged() { connectionOverlay.requestPaint() }
                function onSelectedUnitChanged()        { connectionOverlay.requestPaint() }
                function onUnitCountChanged()           { connectionOverlay.requestPaint() }
            }

            // ── Coordinate readout — engineering drawing style ────────
            Rectangle {
                id: mouseDebugBox
                anchors.left: drawingBorder.left
                anchors.bottom: drawingBorder.bottom
                width: 104
                height: 22
                color: gAppTheme.titleBlockBg
                border.color: gAppTheme.titleBlockBorder
                border.width: 1

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    font.family: "Consolas"
                    font.pixelSize: 10
                    color: gAppTheme.titleBlockText
                    text: root.mouseSheetX >= 0
                          ? "X: " + Math.round(root.mouseSheetX) + "   Y: " + Math.round(root.mouseSheetY)
                          : "X: —   Y: —"
                }
            }

            // ── Engineering drawing title block ───────────────────────
            Rectangle {
                id: titleBlock
                anchors.right: drawingBorder.right
                anchors.bottom: drawingBorder.bottom
                width: 280
                height: 100
                color: gAppTheme.sheetBg
                border.color: gAppTheme.titleBlockBorder
                border.width: 1
                clip: true

                readonly property int lblW: 72
                readonly property int rowH: 20
                readonly property string monoFont: "Consolas"

                // Vertical divider label | value
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: titleBlock.lblW
                    width: 1; color: gAppTheme.titleBlockBorder
                }

                Column {
                    id: tbRows
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    // ── TITLE row ──
                    Rectangle {
                        width: parent.width; height: titleBlock.rowH; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a"; opacity: 0.45 }
                        Text {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: titleBlock.lblW - 6
                            text: "TITLE"; font.family: titleBlock.monoFont; font.pixelSize: 9; font.bold: true; color: gAppTheme.titleBlockLabel
                        }
                        TextInput {
                            anchors.left: parent.left; anchors.leftMargin: titleBlock.lblW + 4
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flowsheet ? root.flowsheet.drawingTitle : ""
                            font.family: titleBlock.monoFont; font.pixelSize: 9; color: gAppTheme.titleBlockText
                            clip: true; selectByMouse: true
                            onEditingFinished: if (root.flowsheet) root.flowsheet.drawingTitle = text
                        }
                    }

                    // ── DRAWING NUMBER row ──
                    Rectangle {
                        width: parent.width; height: titleBlock.rowH; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a"; opacity: 0.45 }
                        Text {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: titleBlock.lblW - 6
                            text: "DRAWING"; font.family: titleBlock.monoFont; font.pixelSize: 9; font.bold: true; color: gAppTheme.titleBlockLabel
                        }
                        TextInput {
                            anchors.left: parent.left; anchors.leftMargin: titleBlock.lblW + 4
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flowsheet ? root.flowsheet.drawingNumber : "PFD-001"
                            font.family: titleBlock.monoFont; font.pixelSize: 9; color: gAppTheme.titleBlockText
                            clip: true; selectByMouse: true
                            onEditingFinished: if (root.flowsheet) root.flowsheet.drawingNumber = text
                        }
                    }

                    // ── DATE row (read-only — set by stamp) ──
                    Rectangle {
                        width: parent.width; height: titleBlock.rowH; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a"; opacity: 0.45 }
                        Text {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: titleBlock.lblW - 6
                            text: "DATE"; font.family: titleBlock.monoFont; font.pixelSize: 9; font.bold: true; color: gAppTheme.titleBlockLabel
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: titleBlock.lblW + 4
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flowsheet ? (root.flowsheet.revisionDate || "—") : "—"
                            font.family: titleBlock.monoFont; font.pixelSize: 9; color: gAppTheme.titleBlockText
                        }
                    }

                    // ── REV row (read-only — set by stamp) ──
                    Rectangle {
                        width: parent.width; height: titleBlock.rowH; color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a"; opacity: 0.45 }
                        Text {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: titleBlock.lblW - 6
                            text: "REV"; font.family: titleBlock.monoFont; font.pixelSize: 9; font.bold: true; color: gAppTheme.titleBlockLabel
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: titleBlock.lblW + 4
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flowsheet ? String(root.flowsheet.revision) : "0"
                            font.family: titleBlock.monoFont; font.pixelSize: 9; color: gAppTheme.titleBlockText
                        }
                    }

                    // ── DRN BY row ──
                    Rectangle {
                        width: parent.width; height: titleBlock.rowH; color: "transparent"
                        Text {
                            x: 4; anchors.verticalCenter: parent.verticalCenter; width: titleBlock.lblW - 6
                            text: "DRN BY"; font.family: titleBlock.monoFont; font.pixelSize: 9; font.bold: true; color: gAppTheme.titleBlockLabel
                        }
                        TextInput {
                            anchors.left: parent.left; anchors.leftMargin: titleBlock.lblW + 4
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flowsheet ? root.flowsheet.drawnBy : ""
                            font.family: titleBlock.monoFont; font.pixelSize: 9; color: gAppTheme.titleBlockText
                            clip: true; selectByMouse: true
                            onEditingFinished: if (root.flowsheet) root.flowsheet.drawnBy = text
                        }
                    }
                }

            }

            // ── Placement ghost icon ──────────────────────────────────────
            // Follows the mouse cursor when placement mode is active.
            // Shows a semi-transparent preview of the icon to be placed.
            Item {
                id: placementGhost
                visible: root.inPlacementMode && root.mouseSheetX >= 0
                z: 20
                width: 50
                height: 50
                x: root.mouseSheetX - width  / 2
                y: root.mouseSheetY - height / 2

                opacity: 0.72

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color:       "transparent"
                    border.color: gAppTheme.nodeSelectionBorder
                    border.width: 2
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    source: {
                        if (root.placementType === "column")
                            return Qt.resolvedUrl(gAppTheme.iconPath("dist_column"))
                        if (root.placementType === "heater")
                            return Qt.resolvedUrl(gAppTheme.iconPath("heater"))
                        if (root.placementType === "cooler")
                            return Qt.resolvedUrl(gAppTheme.iconPath("cooler"))
                        if (root.placementType === "heat_exchanger")
                            return Qt.resolvedUrl(gAppTheme.iconPath("heat_exchanger"))
                        return Qt.resolvedUrl(gAppTheme.iconPath("stream_material"))
                    }
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                // "ESC or right-click to cancel" hint label
                Label {
                    anchors.top:              parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin:        4
                    text:      "Click to place  •  Esc / RMB to cancel"
                    font.pixelSize: 10
                    color:     "#31404a"
                    background: Rectangle {
                        color:        "#ffffffcc"
                        radius:       3
                        border.color: "#c6d0d7"
                        border.width: 1
                    }
                    padding: 3
                }
            }

            // Escape key cancels placement mode
            // ── Right-click context menu ──────────────────────────────────
            MouseArea {
                id: contextMenuDismissArea
                anchors.fill: parent
                visible: contextMenuRect.visible
                enabled: contextMenuRect.visible
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: false
                z: 49
                onPressed: function(mouse) {
                    const insideMenu = mouse.x >= contextMenuRect.x
                                     && mouse.x <= contextMenuRect.x + contextMenuRect.width
                                     && mouse.y >= contextMenuRect.y
                                     && mouse.y <= contextMenuRect.y + contextMenuRect.height
                    if (!insideMenu) {
                        root.hideContextMenu()
                        mouse.accepted = true
                        return
                    }
                    mouse.accepted = false
                }
            }

            Rectangle {
                id: contextMenuRect
                visible: false
                z: 50
                width: 192
                height: root.contextMenuConnected ? 72 : 38
                radius: 4
                color: "#ffffff"
                border.color: "#9aaab5"
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onPressed: function(mouse) { mouse.accepted = true }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: 34
                        visible: root.contextMenuConnected
                        radius: 3
                        color: disconnectHover.containsMouse ? "#ddeeff" : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            text: root.contextMenuUnitType === "stream" ? "Disconnect Stream" : "Disconnect Streams"
                            font.pixelSize: 13
                            color: "#1a2a35"
                        }
                        MouseArea {
                            id: disconnectHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const unitId = root.contextMenuUnitId
                                const unitType = root.contextMenuUnitType
                                root.hideContextMenu()
                                if (root.flowsheet && unitId !== "") {
                                    if (unitType === "stream")
                                        root.flowsheet.disconnectMaterialStream(unitId)
                                    else if (root.flowsheet.disconnectUnitConnections)
                                        root.flowsheet.disconnectUnitConnections(unitId)
                                    connectionOverlay.requestPaint()
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: 3
                        color: deleteHover.containsMouse && !root.contextMenuConnected ? "#ffeeee" : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            text: root.contextMenuUnitType === "column"
                                  ? "Delete Column"
                                  : (root.contextMenuUnitType === "stream" ? "Delete Stream" : "Delete Unit")
                            font.pixelSize: 13
                            color: root.contextMenuConnected ? "#9aaab5" : "#8b1a1a"
                        }
                        MouseArea {
                            id: deleteHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.contextMenuConnected
                            onClicked: {
                                const unitId = root.contextMenuUnitId
                                root.hideContextMenu()
                                if (unitId !== "")
                                    root.tryDeleteUnit(unitId)
                            }
                        }
                    }
                }
            }
        }
    }
}
