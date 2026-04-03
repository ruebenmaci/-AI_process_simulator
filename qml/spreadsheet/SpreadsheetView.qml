// SpreadsheetView.qml
// Excel-style spreadsheet – pure QML, no C++ model required.
// Features:
//   • Frozen column/row headers with letter/number labels
//   • Drag-to-resize column widths and row heights
//   • Click to select cell, double-click or F2 to edit inline
//   • Arrow / Tab / Enter navigation
//   • Ctrl+C copy (tab-separated) / Ctrl+V paste (Excel-compatible)
//   • Delete / Backspace to clear a cell
//   • Basic formula support: =A1+B2*3, =SUM A1:C5
//   • Formula bar showing raw content of current cell

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    // ── tunables ──────────────────────────────────────────────────────────────
    property int  numRows           : 50
    property int  numCols           : 26
    property int  defaultColW  : 90
    property int  defaultRowH  : 24
    property int  hdrColW      : 80     // wide enough for labels like "Formula"
    property int  hdrRowH      : 24

    property color gridColor    : "#b0b0b0"
    property color headerBg     : "#e8e8e8"
    property color headerBorder : "#999999"
    property color cellBg       : "#ffffff"
    property color selColor     : "#cce0ff"
    property color curColor     : "#99c4ff"
    property color editBg       : "#fffbe6"
    property color toolbarBg    : "#f2f2f2"

    property font  cellFont: Qt.font({ family: "Segoe UI", pixelSize: 12 })

    // ── state ─────────────────────────────────────────────────────────────────
    property var colW     : []
    property var rowH     : []
    property var store    : []    // store[r][c] = { raw: string, val: string }

    // Bindable label arrays — set by the parent to customise headers.
    // If left empty, defaults are used (A/B/C… for columns, 1/2/3… for rows).
    // Example:  colLabels: ["Property", "Value"]
    //           rowLabels: ["ID", "Name", "Formula", "MW", "BP"]
    property var colLabels: []
    property var rowLabels: []

    property int  curRow   : 0
    property int  curCol   : 0
    property bool editing  : false
    property string editText: ""

    // Selection range anchor (selR1/C1 = anchor corner, curRow/curCol = active corner)
    property int  selAnchorRow: 0
    property int  selAnchorCol: 0

    // Derived selection extents (always min/max of anchor and cursor)
    readonly property int selR1: Math.min(curRow, selAnchorRow)
    readonly property int selC1: Math.min(curCol, selAnchorCol)
    readonly property int selR2: Math.max(curRow, selAnchorRow)
    readonly property int selC2: Math.max(curCol, selAnchorCol)
    readonly property bool hasMultiSel: selR1 !== selR2 || selC1 !== selC2

    Component.onCompleted: _init()

    function _init() {
        var cw = [], rh = []
        for (var c = 0; c < numCols; c++) cw.push(defaultColW)
        for (var r = 0; r < numRows; r++) rh.push(defaultRowH)
        colW = cw;  rowH = rh
        var s = []
        for (r = 0; r < numRows; r++) {
            var row = []
            for (c = 0; c < numCols; c++) row.push({ raw: "", val: "" })
            s.push(row)
        }
        store = s
    }

    // Returns the display label for a column header
    function _colHdrLabel(c) {
        return (colLabels && c < colLabels.length && colLabels[c] !== "") ? colLabels[c] : colLabel(c)
    }

    // Returns the display label for a row header
    function _rowHdrLabel(r) {
        return (rowLabels && r < rowLabels.length && rowLabels[r] !== "") ? rowLabels[r] : String(r + 1)
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    function colLabel(idx) {
        var lbl = "", n = idx + 1
        while (n > 0) {
            lbl = String.fromCharCode(64 + ((n - 1) % 26 + 1)) + lbl
            n = Math.floor((n - 1) / 26)
        }
        return lbl
    }

    function colIdxOf(str) {
        str = str.toUpperCase()
        var idx = 0
        for (var i = 0; i < str.length; i++) idx = idx * 26 + str.charCodeAt(i) - 64
        return idx - 1
    }

    function colX(c) { var x = 0; for (var i = 0; i < c; i++) x += colW[i]; return x }
    function rowY(r) { var y = 0; for (var i = 0; i < r; i++) y += rowH[i]; return y }
    function totalW() { var x = 0; for (var i = 0; i < numCols; i++) x += colW[i]; return x }
    function totalH() { var y = 0; for (var i = 0; i < numRows; i++) y += rowH[i]; return y }

    // ── public API for external population ───────────────────────────────────
    // Set cell (r, c) to a plain string value (no formula evaluation)
    function setCell(r, c, text) {
        _set(r, c, text)
    }

    // Get the raw string value of cell (r, c)
    function getCell(r, c) {
        return _getRaw(r, c)
    }

    // Clear all cells
    function clearAll() {
        _init()
    }
    function _getRaw(r, c) { return (r >= 0 && r < numRows && c >= 0 && c < numCols) ? store[r][c].raw : "" }
    function _getVal(r, c) { return (r >= 0 && r < numRows && c >= 0 && c < numCols) ? store[r][c].val : "" }

    function _eval(raw) {
        if (!raw || raw === "" || raw[0] !== "=") return raw
        var expr = raw.slice(1).trim().toUpperCase()
        var m = expr.match(/^SUM\s+([A-Z]+)(\d+):([A-Z]+)(\d+)$/)
        if (m) {
            var c1 = colIdxOf(m[1]), r1 = parseInt(m[2]) - 1
            var c2 = colIdxOf(m[3]), r2 = parseInt(m[4]) - 1
            var sum = 0
            for (var rr = r1; rr <= r2; rr++)
                for (var cc = c1; cc <= c2; cc++) sum += parseFloat(_getVal(rr, cc)) || 0
            return String(sum)
        }
        expr = expr.replace(/([A-Z]+)(\d+)/g, function(_, cs, rs) {
            var v = parseFloat(_getVal(parseInt(rs) - 1, colIdxOf(cs)))
            return isNaN(v) ? "0" : String(v)
        })
        try {
            var res = eval(expr)
            return (res === undefined || isNaN(res)) ? "#ERR" : String(res)
        } catch (e) { return "#ERR" }
    }

    function _set(r, c, raw) {
        if (r < 0 || r >= numRows || c < 0 || c >= numCols) return
        var ns = store.slice()
        var nr = ns[r].slice()
        nr[c] = { raw: raw, val: _eval(raw) }
        ns[r] = nr
        store = ns
    }

    // ── clipboard ─────────────────────────────────────────────────────────────
    function _paste() {
        var lines = clipText.text.split("\n")
        for (var ri = 0; ri < lines.length; ri++) {
            var cols = lines[ri].split("\t")
            for (var ci = 0; ci < cols.length; ci++)
                _set(curRow + ri, curCol + ci, cols[ci])
        }
        gridCanvas.requestPaint()
    }

    // ── edit helpers ──────────────────────────────────────────────────────────
    function _beginEdit(r, c) {
        curRow   = r;  curCol = c
        editText = _getRaw(r, c)
        editing  = true
        Qt.callLater(function() { cellInput.forceActiveFocus(); cellInput.selectAll() })
    }

    function _commitEdit() {
        if (!editing) return
        _set(curRow, curCol, editText)
        editing  = false
        editText = ""
        focusCatcher.forceActiveFocus()
        gridCanvas.requestPaint()
    }

    function _cancelEdit() {
        editing  = false
        editText = ""
        focusCatcher.forceActiveFocus()
        gridCanvas.requestPaint()
    }

    // Move cursor, optionally extending selection (shift=true) or resetting anchor
    function _navigate(dr, dc, extendSel) {
        if (editing) _commitEdit()
        var nr = Math.max(0, Math.min(numRows - 1, curRow + dr))
        var nc = Math.max(0, Math.min(numCols - 1, curCol + dc))
        curRow = nr; curCol = nc
        if (!extendSel) { selAnchorRow = nr; selAnchorCol = nc }
        _scrollTo(nr, nc)
        gridCanvas.requestPaint()
        colHeaderCanvas.requestPaint()
        rowHeaderCanvas.requestPaint()
    }

    // Jump directly to a cell and reset selection anchor
    function _moveTo(r, c) {
        if (editing) _commitEdit()
        curRow = r; curCol = c
        selAnchorRow = r; selAnchorCol = c
        _scrollTo(r, c)
        gridCanvas.requestPaint()
    }

    // ── auto-fit helpers ──────────────────────────────────────────────────────
    // Measures the pixel width needed to display the widest cell in column c.
    // Uses a hidden Canvas context for text measurement.
    function _autoFitCol(c) {
        var ctx = measureCanvas.getContext("2d")
        ctx.font = "12px 'Segoe UI'"
        var minW = 28
        var best = minW
        for (var r = 0; r < numRows; r++) {
            var txt = _getVal(r, c)
            if (txt === "") continue
            var w = ctx.measureText(txt).width + 12   // 6px padding each side
            if (w > best) best = w
        }
        // Also measure the column header label
        var hdrW = ctx.measureText(colLabel(c)).width + 16
        if (hdrW > best) best = hdrW
        var arr = colW.slice()
        arr[c] = Math.ceil(best)
        colW = arr
        colHeaderCanvas.requestPaint()
        gridCanvas.requestPaint()
    }

    // Measures the pixel height needed for the tallest content in row r.
    // With single-line text this is simply the font height + padding.
    function _autoFitRow(r) {
        var minH = 16
        var best = minH
        for (var c = 0; c < numCols; c++) {
            var txt = _getVal(r, c)
            if (txt === "") continue
            // Single-line: font height ~14px + 6px padding
            var h = 20
            if (h > best) best = h
        }
        var arr = rowH.slice()
        arr[r] = Math.ceil(best)
        rowH = arr
        rowHeaderCanvas.requestPaint()
        gridCanvas.requestPaint()
    }

    function _scrollTo(r, c) {
        var cx = colX(c), cw2 = colW[c]
        var cy = rowY(r),  rh2 = rowH[r]
        if (cx < flick.contentX)
            flick.contentX = cx
        else if (cx + cw2 > flick.contentX + flick.width)
            flick.contentX = cx + cw2 - flick.width
        if (cy < flick.contentY)
            flick.contentY = cy
        else if (cy + rh2 > flick.contentY + flick.height)
            flick.contentY = cy + rh2 - flick.height
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Formula / toolbar bar ─────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 30
            color: root.toolbarBg
            border.color: root.gridColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 4

                Rectangle {
                    width: 56; height: 22
                    border.color: root.headerBorder
                    color: "white"; radius: 2
                    Text {
                        anchors.centerIn: parent
                        text: root.colLabel(root.curCol) + (root.curRow + 1)
                        font: root.cellFont; color: "#333"
                    }
                }

                Text { text: "fx"; font: Qt.font({ family: "Segoe UI", pixelSize: 12, italic: true }); color: "#777" }

                Rectangle {
                    Layout.fillWidth: true; height: 22
                    border.color: formulaBar.activeFocus ? "#0078d4" : root.headerBorder
                    color: "white"; radius: 2; clip: true

                    TextInput {
                        id: formulaBar
                        anchors.fill: parent; anchors.margins: 3
                        font: root.cellFont; color: "#111"; clip: true; selectByMouse: true
                        text: root.editing ? root.editText : root._getRaw(root.curRow, root.curCol)
                        onTextEdited: {
                            if (!root.editing) root._beginEdit(root.curRow, root.curCol)
                            root.editText = text
                        }
                        onAccepted:               root._commitEdit()
                        Keys.onEscapePressed:     root._cancelEdit()
                    }
                }
            }
        }

        // ── Sheet body ────────────────────────────────────────────────────────
        Item {
            id: sheetBody
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Corner
            Rectangle {
                x: 0; y: 0; z: 4
                width: root.hdrColW; height: root.hdrRowH
                color: root.headerBg; border.color: root.headerBorder
            }

            // Column header canvas
            Item {
                id: colHdrArea
                x: root.hdrColW; y: 0; z: 3
                width: sheetBody.width - root.hdrColW; height: root.hdrRowH; clip: true

                Canvas {
                    id: colHeaderCanvas
                    anchors.fill: parent
                    property real ox: 0
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (var c = 0; c < root.numCols; c++) {
                            var cw = root.colW[c]
                            var x  = root.colX(c) - ox
                            if (x + cw < 0 || x > width) continue
                            ctx.fillStyle = root.headerBg
                            ctx.fillRect(x, 0, cw, height)
                            ctx.strokeStyle = root.headerBorder; ctx.lineWidth = 1
                            ctx.strokeRect(x + 0.5, 0.5, cw - 1, height - 1)
                            ctx.fillStyle = "#333"; ctx.font = "bold 12px 'Segoe UI'"
                            ctx.textAlign = "center"; ctx.textBaseline = "middle"
                            ctx.fillText(root._colHdrLabel(c), x + cw / 2, height / 2)
                        }
                    }
                }

                // Column resize drag handles
                Repeater {
                    model: root.numCols
                    delegate: Item {
                        id: colRH
                        x: root.colX(index) + root.colW[index] - 3 - flick.contentX
                        y: 0; width: 6; height: root.hdrRowH
                        property int colIdx: index
                        property real _sx: 0; property real _sw: 0
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.SizeHorCursor; hoverEnabled: true
                            onPressed:  function(e) { colRH._sx = e.x + colRH.x; colRH._sw = root.colW[colRH.colIdx] }
                            onPositionChanged: function(e) {
                                if (!pressed) return
                                var arr = root.colW.slice()
                                arr[colRH.colIdx] = Math.max(24, colRH._sw + (e.x + colRH.x - colRH._sx))
                                root.colW = arr
                                colHeaderCanvas.requestPaint(); gridCanvas.requestPaint()
                            }
                            onDoubleClicked: function(e) { root._autoFitCol(colRH.colIdx) }
                        }
                    }
                }
            }

            // Row header canvas
            Item {
                id: rowHdrArea
                x: 0; y: root.hdrRowH; z: 3
                width: root.hdrColW; height: sheetBody.height - root.hdrRowH; clip: true

                Canvas {
                    id: rowHeaderCanvas
                    anchors.fill: parent
                    property real oy: 0
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (var r = 0; r < root.numRows; r++) {
                            var rh = root.rowH[r]
                            var y  = root.rowY(r) - oy
                            if (y + rh < 0 || y > height) continue
                            ctx.fillStyle = root.headerBg; ctx.fillRect(0, y, width, rh)
                            ctx.strokeStyle = root.headerBorder; ctx.lineWidth = 1
                            ctx.strokeRect(0.5, y + 0.5, width - 1, rh - 1)
                            ctx.fillStyle = "#333"; ctx.font = "bold 12px 'Segoe UI'"
                            ctx.textAlign = "center"; ctx.textBaseline = "middle"
                            ctx.fillText(root._rowHdrLabel(r), width / 2, y + rh / 2)
                        }
                    }
                }

                // Row resize drag handles
                Repeater {
                    model: root.numRows
                    delegate: Item {
                        id: rowRH
                        x: 0; y: root.rowY(index) + root.rowH[index] - 3 - flick.contentY
                        width: root.hdrColW; height: 6
                        property int rowIdx: index
                        property real _sy: 0; property real _sh: 0
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.SizeVerCursor; hoverEnabled: true
                            onPressed:  function(e) { rowRH._sy = e.y + rowRH.y; rowRH._sh = root.rowH[rowRH.rowIdx] }
                            onPositionChanged: function(e) {
                                if (!pressed) return
                                var arr = root.rowH.slice()
                                arr[rowRH.rowIdx] = Math.max(16, rowRH._sh + (e.y + rowRH.y - rowRH._sy))
                                root.rowH = arr
                                rowHeaderCanvas.requestPaint(); gridCanvas.requestPaint()
                            }
                            onDoubleClicked: function(e) { root._autoFitRow(rowRH.rowIdx) }
                        }
                    }
                }
            }

            // Main Flickable + Canvas grid
            Flickable {
                id: flick
                x: root.hdrColW; y: root.hdrRowH
                width:  sheetBody.width  - root.hdrColW
                height: sheetBody.height - root.hdrRowH
                clip: true; boundsBehavior: Flickable.StopAtBounds
                interactive: false   // scrollbars + mousewheel only; no finger/mouse panning
                contentWidth:  root.totalW()
                contentHeight: root.totalH()

                onContentXChanged: { colHeaderCanvas.ox = contentX; colHeaderCanvas.requestPaint() }
                onContentYChanged: { rowHeaderCanvas.oy = contentY; rowHeaderCanvas.requestPaint() }

                // Main cell grid
                Canvas {
                    id: gridCanvas
                    width:  Math.max(flick.width,  root.totalW())
                    height: Math.max(flick.height, root.totalH())

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var cX = flick.contentX, cY = flick.contentY
                        var vW = flick.width,     vH = flick.height

                        for (var r = 0; r < root.numRows; r++) {
                            var ry = root.rowY(r), rh = root.rowH[r]
                            if (ry + rh < cY || ry > cY + vH) continue
                            for (var c = 0; c < root.numCols; c++) {
                                var cx = root.colX(c), cw = root.colW[c]
                                if (cx + cw < cX || cx > cX + vW) continue
                                var isCur = (r === root.curRow && c === root.curCol)
                                var inSel = (r >= root.selR1 && r <= root.selR2 &&
                                             c >= root.selC1 && c <= root.selC2)
                                if (root.editing && isCur)       ctx.fillStyle = root.editBg
                                else if (isCur)                  ctx.fillStyle = root.curColor
                                else if (inSel)                  ctx.fillStyle = root.selColor
                                else                             ctx.fillStyle = root.cellBg
                                ctx.fillRect(cx, ry, cw, rh)
                                ctx.strokeStyle = root.gridColor; ctx.lineWidth = 0.5
                                ctx.strokeRect(cx + 0.5, ry + 0.5, cw - 1, rh - 1)
                                if (!(root.editing && isCur)) {
                                    var txt = root._getVal(r, c)
                                    if (txt !== "") {
                                        ctx.fillStyle = "#111"
                                        ctx.font = "12px 'Segoe UI'"
                                        ctx.textBaseline = "middle"; ctx.textAlign = "left"
                                        ctx.save()
                                        ctx.beginPath()
                                        ctx.rect(cx + 1, ry, cw - 4, rh)
                                        ctx.clip()
                                        ctx.fillText(txt, cx + 4, ry + rh / 2)
                                        ctx.restore()
                                    }
                                }
                            }
                        }
                        // Current cell highlight border
                        var hx = root.colX(root.curCol), hy = root.rowY(root.curRow)
                        var hw = root.colW[root.curCol],  hh = root.rowH[root.curRow]
                        ctx.strokeStyle = "#0078d4"; ctx.lineWidth = 2
                        ctx.strokeRect(hx + 1, hy + 1, hw - 2, hh - 2)
                        // Selection range border (when multi-cell)
                        if (root.hasMultiSel) {
                            var sx = root.colX(root.selC1), sy = root.rowY(root.selR1)
                            var sw = root.colX(root.selC2) + root.colW[root.selC2] - sx
                            var sh = root.rowY(root.selR2) + root.rowH[root.selR2] - sy
                            ctx.strokeStyle = "#0078d4"; ctx.lineWidth = 2
                            ctx.strokeRect(sx + 1, sy + 1, sw - 2, sh - 2)
                        }
                    }
                }

                // Inline cell editor (positioned over current cell)
                TextInput {
                    id: cellInput
                    x: root.colX(root.curCol)
                    y: root.rowY(root.curRow)
                    width:  root.colW[root.curCol]
                    height: root.rowH[root.curRow]
                    visible: root.editing
                    font: root.cellFont; color: "#111"
                    clip: true; selectByMouse: true
                    leftPadding: 4; verticalAlignment: TextInput.AlignVCenter
                    text: root.editText
                    onTextEdited: { root.editText = text; formulaBar.text = text }
                    Keys.onReturnPressed:  function(e) { root._commitEdit(); e.accepted = true }
                    Keys.onTabPressed:     function(e) { root._navigate(0, 1) }
                    Keys.onEscapePressed:  function(e) { root._cancelEdit() }
                    Keys.onUpPressed:      function(e) { root._navigate(-1, 0) }
                    Keys.onDownPressed:    function(e) { root._navigate(1, 0) }
                    Keys.onLeftPressed:    function(e) { if (cursorPosition === 0) root._navigate(0, -1) }
                    Keys.onRightPressed:   function(e) { if (cursorPosition === length) root._navigate(0, 1) }
                }

                // Mouse interaction on the grid
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true

                    // Hit-test pixel coordinates → { r, c }
                    function _hitTest(px, py) {
                        var r = 0, c = 0, acc = 0
                        for (var i = 0; i < root.numRows; i++) {
                            if (acc + root.rowH[i] > py) { r = i; break }
                            acc += root.rowH[i]
                        }
                        acc = 0
                        for (var j = 0; j < root.numCols; j++) {
                            if (acc + root.colW[j] > px) { c = j; break }
                            acc += root.colW[j]
                        }
                        return { r: r, c: c }
                    }

                    onPressed: function(e) {
                        focusCatcher.forceActiveFocus()
                        if (root.editing) root._commitEdit()
                        var hit = _hitTest(e.x + flick.contentX, e.y + flick.contentY)
                        root.curRow = hit.r; root.curCol = hit.c
                        // Shift+click extends selection from existing anchor
                        if (!(e.modifiers & Qt.ShiftModifier)) {
                            root.selAnchorRow = hit.r
                            root.selAnchorCol = hit.c
                        }
                        gridCanvas.requestPaint()
                        e.accepted = true
                    }

                    onPositionChanged: function(e) {
                        if (!pressed) return
                        var hit = _hitTest(e.x + flick.contentX, e.y + flick.contentY)
                        // Drag extends active corner without moving anchor
                        if (hit.r !== root.curRow || hit.c !== root.curCol) {
                            root.curRow = hit.r; root.curCol = hit.c
                            gridCanvas.requestPaint()
                        }
                    }

                    onDoubleClicked: function(e) {
                        root._beginEdit(root.curRow, root.curCol)
                        gridCanvas.requestPaint()
                    }
                }
            }

            // Scrollbars
            ScrollBar {
                id: vBar; z: 5
                anchors { right: sheetBody.right; top: sheetBody.top; topMargin: root.hdrRowH; bottom: sheetBody.bottom; bottomMargin: hBar.height }
                orientation: Qt.Vertical; policy: ScrollBar.AsNeeded
                size: flick.height / Math.max(1, flick.contentHeight)
                position: flick.contentY / Math.max(1, flick.contentHeight)
                onPositionChanged: if (pressed) flick.contentY = position * flick.contentHeight
            }
            ScrollBar {
                id: hBar; z: 5
                anchors { left: sheetBody.left; leftMargin: root.hdrColW; right: sheetBody.right; rightMargin: vBar.width; bottom: sheetBody.bottom }
                orientation: Qt.Horizontal; policy: ScrollBar.AsNeeded
                size: flick.width / Math.max(1, flick.contentWidth)
                position: flick.contentX / Math.max(1, flick.contentWidth)
                onPositionChanged: if (pressed) flick.contentX = position * flick.contentWidth
            }
        }
    }

    // Keyboard focus when not editing
    Item {
        id: focusCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_F2) {
                root._beginEdit(root.curRow, root.curCol); e.accepted = true; return
            }
            // Ctrl+C — copy full selection range (tab/newline separated)
            if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
                var lines = []
                for (var r = root.selR1; r <= root.selR2; r++) {
                    var cols = []
                    for (var c = root.selC1; c <= root.selC2; c++) cols.push(root._getRaw(r, c))
                    lines.push(cols.join("\t"))
                }
                clipText.text = lines.join("\n")
                e.accepted = true; return
            }
            // Ctrl+V
            if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier)) {
                root._paste(); e.accepted = true; return
            }
            // Delete / Backspace — clear entire selection
            if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                for (var dr = root.selR1; dr <= root.selR2; dr++)
                    for (var dc = root.selC1; dc <= root.selC2; dc++)
                        root._set(dr, dc, "")
                gridCanvas.requestPaint(); e.accepted = true; return
            }
            // Arrow keys — Shift extends selection, plain resets anchor
            var drow = 0, dcol = 0
            if      (e.key === Qt.Key_Up)    drow = -1
            else if (e.key === Qt.Key_Down)  drow =  1
            else if (e.key === Qt.Key_Left)  dcol = -1
            else if (e.key === Qt.Key_Right) dcol =  1
            else if (e.key === Qt.Key_Tab)   dcol =  1
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) drow = 1
            if (drow || dcol) {
                var shift = !!(e.modifiers & Qt.ShiftModifier)
                root._navigate(drow, dcol, shift)
                e.accepted = true; return
            }
            // Printable key → start editing
            if (e.text.length > 0 && !root.editing) {
                root._beginEdit(root.curRow, root.curCol)
                root.editText = e.text; e.accepted = true
            }
        }
    }

    // Hidden clipboard buffer
    TextEdit { id: clipText; visible: false; width: 0; height: 0 }

    // Hidden canvas used only for text measurement in _autoFitCol
    Canvas { id: measureCanvas; visible: false; width: 1; height: 1 }

    // Repaint triggers
    onStoreChanged:       { gridCanvas.requestPaint() }
    onColWChanged:        { gridCanvas.requestPaint(); colHeaderCanvas.requestPaint() }
    onRowHChanged:        { gridCanvas.requestPaint(); rowHeaderCanvas.requestPaint() }
    onColLabelsChanged:   colHeaderCanvas.requestPaint()
    onRowLabelsChanged:   rowHeaderCanvas.requestPaint()
    onCurRowChanged:      gridCanvas.requestPaint()
    onCurColChanged:      gridCanvas.requestPaint()
    onSelAnchorRowChanged:gridCanvas.requestPaint()
    onSelAnchorColChanged:gridCanvas.requestPaint()
    onEditingChanged:     gridCanvas.requestPaint()
}
