// ─────────────────────────────────────────────────────────────────────────────
//  PSpreadsheet.qml
//
//  Drop-in PGrid-styled replacement for SimpleSpreadsheet.qml.
//
//  ─── Architecture ──────────────────────────────────────────────────────────
//  Hybrid rendering for crispness:
//    • Canvas draws backgrounds, grid lines, alternating row tints, selection
//      fills/borders, and the blue active-cell rule.
//    • Qt Text elements (via Repeater over the visible viewport) draw the
//      actual cell text and header labels — pixel-perfect with native font
//      hinting, no Canvas text softness.
//    • All Canvas strokes use coord + 0.5 to land on pixel centers, not
//      between pixels (the #1 cause of fuzzy grid lines).
//    • Qt's Canvas in Qt 6.x handles devicePixelRatio internally — we
//      do not manually scale the backing store (manual DPR scaling
//      double-applies on Windows scaled displays).
//
//  ─── API parity with SimpleSpreadsheet ────────────────────────────────────
//  Every public property, function, and signal of SimpleSpreadsheet is
//  preserved verbatim:
//    Properties: numRows, numCols, defaultColW, defaultRowH, hdrColW, hdrRowH,
//                cornerLabel, readOnly, readOnlyCols, numericOnlyCells,
//                colLabels, rowLabels, stretchToWidth, cellFont,
//                verticalScrollBarPolicy, horizontalScrollBarPolicy
//    Functions:  setCell(r,c,text), getCell(r,c), clearAll(), fitToWidth(),
//                colLabel(idx), colIdxOf(str)
//    Signals:    cellEdited(int row, int col, string text)
//                wheelPassthrough(real deltaY, real deltaX)
//    Behaviors:  drag-resize cols/rows, dbl-click autofit, click/Shift+click/
//                drag selection, Ctrl+C/Ctrl+V Excel-compatible (with header
//                awareness), Delete/Backspace clear, arrow/Tab/Enter nav,
//                F2/dbl-click edit, Esc cancel, formulas (=A1+B2, =SUM A1:C5),
//                numeric validator, per-column readOnly, full row/col select,
//                wheel passthrough on overflow.
//
//  ─── New (opt-in) features ────────────────────────────────────────────────
//    • alternatingRows: true (default) — even rows white, odd rows #f4f6f8
//    • columnQuantities: []          — per-column unit-quantity tag for
//                                       header-mounted UnitToken pickers.
//                                       e.g. ["Dimensionless", "Temperature",
//                                       "MolarMass", "Pressure"]
//    • columnUnitChanged(int col, string unit) signal — fires when a column
//      header unit picker changes selection.
//
//  ─── Drop-in migration ────────────────────────────────────────────────────
//  Just rename SimpleSpreadsheet → PSpreadsheet at the call site. Everything
//  else stays the same.
// ─────────────────────────────────────────────────────────────────────────────

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    clip: true

    // ── Tab-chain integration ────────────────────────────────────────────────
    // Without these, our custom tabstop walker (used by PGrid* and PTextField)
    // skips right past the spreadsheet entirely — so Tab/arrows from a grid
    // never enter the sheet. The root opts into the focus chain; when it
    // gains active focus we forward it to the internal focusCatcher so arrow
    // keys / Ctrl+C / etc. work. Tab/Backtab out are intercepted here (at the
    // root level, before the inner handler runs) so we honor the tabStop
    // convention (skip labels and read-only cells) instead of letting Qt's
    // default focus-chain nav pick the next activeFocusOnTab item.
    activeFocusOnTab: true
    property bool tabStop: true

    onActiveFocusChanged: {
        if (activeFocus && !focusCatcher.activeFocus)
            focusCatcher.forceActiveFocus()
    }

    function _moveToNextTabStop(forward) {
        var item = root
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === root) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        root._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        root._moveToNextTabStop(false); event.accepted = true
    }

    // ── Public API: dimensions ────────────────────────────────────────────
    property int  numRows      : 50
    property int  numCols      : 26
    property int  defaultColW  : 84
    property int  defaultRowH  : 22
    property int  hdrColW      : 72
    property int  hdrRowH      : 40

    // Embedded-table options (opt-in; preserve spreadsheet defaults)
    property bool showRowHeaders      : true
    property bool showCornerCell      : true
    property bool tightEmbeddedHeader : false
    property int  tightHdrColW        : 56
    property int  tightHdrRowH        : 22

    readonly property int effectiveHdrColW: showRowHeaders
                                             ? (tightEmbeddedHeader ? Math.min(hdrColW, tightHdrColW) : hdrColW)
                                             : 0
    readonly property int effectiveHdrRowH: tightEmbeddedHeader ? Math.min(hdrRowH, tightHdrRowH) : hdrRowH

    // ── Public API: appearance (PGrid-aligned defaults) ───────────────────
    property color gridColor      : "#d9dee3"   // PGridValue row divider
    property color headerBg       : "#c8d0d8"   // PGridSection header
    property color rowHdrBg       : "#f4f6f8"   // PGrid alt row tint
    property color headerBorder   : "#97a2ad"   // PGrid borders
    property color cellBg         : "#ffffff"
    property color cellBgAlt      : "#f4f6f8"   // alternating rows
    property color selFill        : "#dde9f3"   // PComboBox highlight
    property color cursorFill     : "#c6daee"   // active cell, soft blue
    property color cursorRule     : "#1c4ea7"   // PGridValue valueBlue
    property color editBg         : "#fbfcfe"   // PGridValue editable bg
    property color valueBlue      : "#1c4ea7"   // editable cell text
    property color textMain       : "#1f2a34"   // read-only cell text
    property color textMuted      : "#526571"   // header label text

    property font  cellFont   : Qt.font({ family: "Segoe UI", pixelSize: 11 })
    property font  headerFont : Qt.font({ family: "Segoe UI", pixelSize: 11, bold: true })

    property string cornerLabel: "Property"
    property bool   readOnly: false
    property var    readOnlyCols: []
    property bool   numericOnlyCells: true
    property bool   alternatingRows: true

    // Header bindable label arrays (defaults: A,B,C... and 1,2,3...)
    property var colLabels: []
    property var rowLabels: []

    // Per-column unit quantity tags. If non-empty, the column header for
    // columns whose tag is non-"" gets a clickable ▾ UnitToken next to its
    // label. The current unit is fetched from the gUnits singleton.
    // Example: ["", "Temperature", "MolarMass", "Temperature", "Pressure"]
    property var columnQuantities: []
    // Optional per-column unit override selected from the header UnitToken.
    // Empty string means use the current Unit Set default for that quantity.
    property var columnUnits: []

    property bool stretchToWidth: true
    property int  verticalScrollBarPolicy:   ScrollBar.AsNeeded
    property int  horizontalScrollBarPolicy: ScrollBar.AsNeeded

    // ── Public API: signals ───────────────────────────────────────────────
    signal cellEdited(int row, int col, string text)
    signal wheelPassthrough(real deltaY, real deltaX)
    signal columnUnitChanged(int col, string unit)

    // ── Internal state ────────────────────────────────────────────────────
    property var colW   : []
    property var rowH   : []
    property var store  : []        // store[r][c] = { raw: string, val: string }

    property int  curRow   : 0
    property int  curCol   : 0
    property bool editing  : false
    property string editText: ""

    // Selection range (anchor + cursor → derived min/max)
    property int  selAnchorRow: 0
    property int  selAnchorCol: 0

    readonly property int selR1: Math.min(curRow, selAnchorRow)
    readonly property int selC1: Math.min(curCol, selAnchorCol)
    readonly property int selR2: Math.max(curRow, selAnchorRow)
    readonly property int selC2: Math.max(curCol, selAnchorCol)
    readonly property bool hasMultiSel: selR1 !== selR2 || selC1 !== selC2

    // Discrete full-row selection support for Ctrl+click on row headers.
    // When non-empty, these rows are treated as the active selection.
    property var selectedRows: []
    property int selectedRowAnchor: -1
    readonly property bool hasDiscreteRowSelection: selectedRows && selectedRows.length > 0

    // Discrete full-column selection support for Ctrl+click on column headers.
    // When non-empty, these columns are treated as the active selection.
    property var selectedCols: []
    property int selectedColAnchor: -1
    readonly property bool hasDiscreteColSelection: selectedCols && selectedCols.length > 0

    // Bumped when the unit set changes — forces visible-text repopulation
    property int _unitRev: 0

    // Natural height: header row + all data rows
    implicitHeight: effectiveHdrRowH + numRows * defaultRowH

    // Reactive content dimensions for Flickable
    readonly property real contentH: {
        var y = 0
        for (var i = 0; i < numRows; i++) y += (rowH[i] || defaultRowH)
        return y
    }
    readonly property real contentW: {
        var x = 0
        for (var i = 0; i < numCols; i++) x += (colW[i] || defaultColW)
        return x
    }

    // Reserve scrollbar space only when that scrollbar is actually enabled.
    // This is important for embedded read-only tables where the caller may
    // want panel-only scrolling and no inner spreadsheet gutter.
    readonly property int effectiveVBarW: (verticalScrollBarPolicy === ScrollBar.AlwaysOff) ? 0 : vBar.width
    readonly property int effectiveHBarH: (horizontalScrollBarPolicy === ScrollBar.AlwaysOff) ? 0 : hBar.height

    Component.onCompleted: _init()
    onNumRowsChanged: _init()
    onNumColsChanged: _init()

    // React to gUnits changes (column-header unit pickers)
    Connections {
        target: typeof gUnits !== "undefined" ? gUnits : null
        ignoreUnknownSignals: true
        function onUnitsChanged()          { root._unitRev++; _repaintAll() }
        function onActiveUnitSetChanged()  { root._unitRev++; _repaintAll() }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  INIT / DATA HELPERS
    // ─────────────────────────────────────────────────────────────────────
    function _init() {
        var cw = [], rh = []
        for (var c = 0; c < numCols; c++) cw.push(defaultColW)
        for (var r = 0; r < numRows; r++) rh.push(defaultRowH)
        colW = cw; rowH = rh

        var s = []
        for (r = 0; r < numRows; r++) {
            var row = []
            for (c = 0; c < numCols; c++) row.push({ raw: "", val: "" })
            s.push(row)
        }
        store = s

        Qt.callLater(function() {
            _updateHdrColW()
            if (stretchToWidth) fitToWidth()
            _repaintAll()
        })
    }

    function _updateHdrColW() {
        if (!showRowHeaders) return
        var ctx = measureCanvas.getContext("2d")
        if (!ctx) return
        ctx.font = cellFont.pixelSize + "px '" + cellFont.family + "'"
        var maxW = ctx.measureText(String(cornerLabel)).width
        for (var i = 0; i < rowLabels.length; i++) {
            var w = ctx.measureText(String(rowLabels[i])).width
            if (w > maxW) maxW = w
        }
        var minW = tightEmbeddedHeader ? Math.max(32, tightHdrColW) : 60
        var newW = Math.max(minW, Math.ceil(maxW) + 18)
        if (newW !== hdrColW) hdrColW = newW
    }

    function _colHdrLabel(c) {
        if (colLabels && c < colLabels.length && colLabels[c] !== undefined)
            return colLabels[c]
        return colLabel(c)
    }
    function _rowHdrLabel(r) {
        if (rowLabels && r < rowLabels.length && rowLabels[r] !== undefined)
            return rowLabels[r]
        return String(r + 1)
    }

    function colLabel(idx) {
        var s = ""
        idx = idx + 1
        while (idx > 0) {
            var rem = (idx - 1) % 26
            s = String.fromCharCode(65 + rem) + s
            idx = Math.floor((idx - 1) / 26)
        }
        return s
    }
    function colIdxOf(str) {
        var n = 0
        for (var i = 0; i < str.length; i++)
            n = n * 26 + (str.charCodeAt(i) - 64)
        return n - 1
    }

    function colX(c) { var x = 0; for (var i = 0; i < c; i++) x += colW[i]; return x }
    function rowY(r) { var y = 0; for (var i = 0; i < r; i++) y += rowH[i]; return y }
    function totalW() { var x = 0; for (var i = 0; i < numCols; i++) x += colW[i]; return x }
    function totalH() { var y = 0; for (var i = 0; i < numRows; i++) y += rowH[i]; return y }

    // ─────────────────────────────────────────────────────────────────────
    //  PUBLIC DATA API
    // ─────────────────────────────────────────────────────────────────────
    function setCell(r, c, text) {
        if (r < 0 || r >= numRows || c < 0 || c >= numCols) return
        _set(r, c, String(text))
        _repaintGrid()
    }

    function getCell(r, c) {
        if (r < 0 || r >= numRows || c < 0 || c >= numCols) return ""
        return store[r][c].raw
    }

    function clearAll() {
        var s = []
        for (var r = 0; r < numRows; r++) {
            var row = []
            for (var c = 0; c < numCols; c++) row.push({ raw: "", val: "" })
            s.push(row)
        }
        store = s
        _repaintGrid()
    }

    function fitToWidth() {
        if (root.width <= 0 || numCols <= 0) return
        var available = Math.max(24 * numCols, root.width - effectiveHdrColW - effectiveVBarW - 2)
        var arr = []
        if (numCols === 1) {
            arr.push(Math.max(24, available))
        } else {
            var base = Math.floor(available / numCols)
            var used = 0
            for (var c = 0; c < numCols - 1; c++) {
                arr.push(base)
                used += base
            }
            arr.push(Math.max(24, available - used))
        }
        colW = arr
        _repaintAll()
    }

    function _getRaw(r, c) { return (r >= 0 && r < numRows && c >= 0 && c < numCols) ? store[r][c].raw : "" }
    function _getVal(r, c) { return (r >= 0 && r < numRows && c >= 0 && c < numCols) ? store[r][c].val : "" }

    function _set(r, c, raw) {
        if (r < 0 || r >= numRows || c < 0 || c >= numCols) return
        var ns = store.slice()
        var nr = ns[r].slice()
        nr[c] = { raw: raw, val: _eval(raw) }
        ns[r] = nr
        store = ns
    }

    // ─────────────────────────────────────────────────────────────────────
    //  FORMULA EVAL (=A1+B2, =SUM A1:C5)
    // ─────────────────────────────────────────────────────────────────────
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

    // ─────────────────────────────────────────────────────────────────────
    //  SELECTION HELPERS
    // ─────────────────────────────────────────────────────────────────────
    function _sortedUniqueRows(rows) {
        var out = []
        var seen = {}
        for (var i = 0; i < rows.length; i++) {
            var r = Math.max(0, Math.min(numRows - 1, rows[i]))
            if (!seen[r]) { seen[r] = true; out.push(r) }
        }
        out.sort(function(a, b) { return a - b })
        return out
    }
    function _sortedUniqueCols(cols) {
        var out = []
        var seen = {}
        for (var i = 0; i < cols.length; i++) {
            var c = Math.max(0, Math.min(numCols - 1, cols[i]))
            if (!seen[c]) { seen[c] = true; out.push(c) }
        }
        out.sort(function(a, b) { return a - b })
        return out
    }
    function _isRowSelectedDiscrete(r) {
        return selectedRows && selectedRows.indexOf(r) >= 0
    }
    function _isColSelectedDiscrete(c) {
        return selectedCols && selectedCols.indexOf(c) >= 0
    }
    function _clearDiscreteRowSelection() {
        if (selectedRows.length || selectedRowAnchor >= 0) {
            selectedRows = []
            selectedRowAnchor = -1
        }
    }
    function _clearDiscreteColSelection() {
        if (selectedCols.length || selectedColAnchor >= 0) {
            selectedCols = []
            selectedColAnchor = -1
        }
    }
    function _selectRow(r, extendSel, toggleSel) {
        if (editing) _commitEdit()
        _clearDiscreteColSelection()
        r = Math.max(0, Math.min(numRows - 1, r))

        if (toggleSel) {
            var rows = selectedRows.slice()
            if (!rows.length) rows = [selAnchorRow]
            var idx = rows.indexOf(r)
            if (idx >= 0) {
                if (rows.length === 1) {
                    rows = [r]
                } else {
                    rows.splice(idx, 1)
                }
            } else {
                rows.push(r)
            }
            selectedRows = _sortedUniqueRows(rows)
            if (selectedRowAnchor < 0) selectedRowAnchor = r
            curRow = r; curCol = numCols - 1
            selAnchorRow = r; selAnchorCol = 0
            _scrollTo(r, 0)
            _repaintAll()
            return
        }

        if (extendSel) {
            var anchor = selectedRowAnchor >= 0 ? selectedRowAnchor : selAnchorRow
            var lo = Math.min(anchor, r)
            var hi = Math.max(anchor, r)
            var rangeRows = []
            for (var rr = lo; rr <= hi; rr++) rangeRows.push(rr)
            selectedRows = rangeRows
            selectedRowAnchor = anchor
            curRow = r; curCol = numCols - 1
            selAnchorRow = anchor; selAnchorCol = 0
            _scrollTo(r, 0)
            _repaintAll()
            return
        }

        selectedRows = [r]
        selectedRowAnchor = r
        curRow = r; curCol = numCols - 1
        selAnchorRow = r; selAnchorCol = 0
        _scrollTo(r, 0)
        _repaintAll()
    }
    function _selectColumn(c, extendSel, toggleSel) {
        if (editing) _commitEdit()
        _clearDiscreteRowSelection()
        // Keep existing discrete column selection for Ctrl/Shift column-header
        // interactions. Only row-based discrete selection should be cleared here.
        c = Math.max(0, Math.min(numCols - 1, c))

        if (toggleSel) {
            var cols = selectedCols.slice()
            if (!cols.length) cols = [selAnchorCol]
            var idx = cols.indexOf(c)
            if (idx >= 0) {
                if (cols.length === 1) {
                    cols = [c]
                } else {
                    cols.splice(idx, 1)
                }
            } else {
                cols.push(c)
            }
            selectedCols = _sortedUniqueCols(cols)
            if (selectedColAnchor < 0) selectedColAnchor = c
            curRow = numRows - 1; curCol = c
            selAnchorRow = 0; selAnchorCol = c
            _scrollTo(0, c)
            _repaintAll()
            return
        }

        if (extendSel) {
            var anchor = selectedColAnchor >= 0 ? selectedColAnchor : selAnchorCol
            var lo = Math.min(anchor, c)
            var hi = Math.max(anchor, c)
            var rangeCols = []
            for (var cc = lo; cc <= hi; cc++) rangeCols.push(cc)
            selectedCols = rangeCols
            selectedColAnchor = anchor
            curRow = numRows - 1; curCol = c
            selAnchorRow = 0; selAnchorCol = anchor
            _scrollTo(0, c)
            _repaintAll()
            return
        }

        selectedCols = [c]
        selectedColAnchor = c
        curRow = numRows - 1; curCol = c
        selAnchorRow = 0; selAnchorCol = c
        _scrollTo(0, c)
        _repaintAll()
    }
    function _selectAll() {
        if (editing) _commitEdit()
        _clearDiscreteRowSelection()
        _clearDiscreteColSelection()
        curRow = numRows - 1; curCol = numCols - 1
        selAnchorRow = 0; selAnchorCol = 0
        _repaintAll()
    }

    // ─────────────────────────────────────────────────────────────────────
    //  CLIPBOARD (Excel-compatible, header-aware)
    // ─────────────────────────────────────────────────────────────────────
    function _selectedTextWithHeaders() {
        var lines = []

        if (root.hasDiscreteRowSelection) {
            var rowHeader = [String(root.cornerLabel)]
            for (var dc = 0; dc < root.numCols; dc++)
                rowHeader.push(String(root._colHdrLabel(dc)))
            lines.push(rowHeader.join("	"))
            for (var dri = 0; dri < root.selectedRows.length; dri++) {
                var rr = root.selectedRows[dri]
                var rowVals = [String(root._rowHdrLabel(rr))]
                for (var dcc = 0; dcc < root.numCols; dcc++)
                    rowVals.push(root._getRaw(rr, dcc))
                lines.push(rowVals.join("	"))
            }
            return lines.join("
")
        }

        if (root.hasDiscreteColSelection) {
            var discreteColHeader = [String(root.cornerLabel)]
            for (var dci = 0; dci < root.selectedCols.length; dci++) {
                var dc2 = root.selectedCols[dci]
                discreteColHeader.push(String(root._colHdrLabel(dc2)))
            }
            lines.push(discreteColHeader.join("	"))
            for (var rr2 = 0; rr2 < root.numRows; rr2++) {
                var discreteColRow = [String(root._rowHdrLabel(rr2))]
                for (var dci2 = 0; dci2 < root.selectedCols.length; dci2++) {
                    var dc3 = root.selectedCols[dci2]
                    discreteColRow.push(root._getRaw(rr2, dc3))
                }
                lines.push(discreteColRow.join("	"))
            }
            return lines.join("
")
        }

        var allRowsSelected = (root.selR1 === 0 && root.selR2 === root.numRows - 1)
        var allColsSelected = (root.selC1 === 0 && root.selC2 === root.numCols - 1)

        if (allRowsSelected && allColsSelected) {
            var fullHeader = [String(root.cornerLabel)]
            for (var c = root.selC1; c <= root.selC2; c++)
                fullHeader.push(String(root._colHdrLabel(c)))
            lines.push(fullHeader.join("	"))
            for (var r = root.selR1; r <= root.selR2; r++) {
                var fullRow = [String(root._rowHdrLabel(r))]
                for (var c2 = root.selC1; c2 <= root.selC2; c2++)
                    fullRow.push(root._getRaw(r, c2))
                lines.push(fullRow.join("	"))
            }
            return lines.join("
")
        }

        if (allRowsSelected) {
            var colHeader = []
            for (var c3 = root.selC1; c3 <= root.selC2; c3++)
                colHeader.push(String(root._colHdrLabel(c3)))
            lines.push(colHeader.join("	"))
            for (var r2 = root.selR1; r2 <= root.selR2; r2++) {
                var valueRow = []
                for (var c4 = root.selC1; c4 <= root.selC2; c4++)
                    valueRow.push(root._getRaw(r2, c4))
                lines.push(valueRow.join("	"))
            }
            return lines.join("
")
        }

        if (allColsSelected) {
            for (var r3 = root.selR1; r3 <= root.selR2; r3++) {
                var selectedRow = [String(root._rowHdrLabel(r3))]
                for (var c5 = root.selC1; c5 <= root.selC2; c5++)
                    selectedRow.push(root._getRaw(r3, c5))
                lines.push(selectedRow.join("	"))
            }
            return lines.join("
")
        }

        var headerCols = [String(root.cornerLabel)]
        for (var c6 = root.selC1; c6 <= root.selC2; c6++)
            headerCols.push(String(root._colHdrLabel(c6)))
        lines.push(headerCols.join("	"))
        for (var r4 = root.selR1; r4 <= root.selR2; r4++) {
            var cols = [String(root._rowHdrLabel(r4))]
            for (var c7 = root.selC1; c7 <= root.selC2; c7++)
                cols.push(root._getRaw(r4, c7))
            lines.push(cols.join("	"))
        }
        return lines.join("
")
    }

    function _copyToClipboard(text) {
        if (typeof gClipboard !== "undefined" && gClipboard) {
            gClipboard.setText(text)
        } else {
            clipBridge.text = text
            clipBridge.selectAll()
            clipBridge.copy()
        }
    }
    function _pasteFromClipboard() {
        if (typeof gClipboard !== "undefined" && gClipboard)
            return gClipboard.text() || ""
        clipBridge.selectAll()
        clipBridge.paste()
        return clipBridge.text || ""
    }
    function _isNumericText(text) {
        var s = String(text === undefined || text === null ? "" : text).trim()
        if (s === "") return true
        return /^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/.test(s)
    }
    function _isEditableColumn(c) {
        return !(readOnlyCols && readOnlyCols.indexOf(c) >= 0)
    }
    function _isValidCellInput(r, c, text) {
        if (!_isEditableColumn(c)) return false
        if (!numericOnlyCells) return true
        return _isNumericText(text)
    }

    function _paste() {
        if (readOnly) return
        var text = _pasteFromClipboard()
        var lines = String(text).replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n")
        for (var ri = 0; ri < lines.length; ri++) {
            var cols = lines[ri].split("\t")
            for (var ci = 0; ci < cols.length; ci++) {
                var rr = curRow + ri
                var cc = curCol + ci
                if (rr < 0 || rr >= numRows || cc < 0 || cc >= numCols) continue
                if (!_isEditableColumn(cc)) continue
                if (!_isValidCellInput(rr, cc, cols[ci])) continue
                _set(rr, cc, cols[ci])
            }
        }
        _repaintGrid()
    }

    // ─────────────────────────────────────────────────────────────────────
    //  EDIT HELPERS
    // ─────────────────────────────────────────────────────────────────────
    function _beginEdit(r, c) {
        if (readOnly) return
        if (readOnlyCols && readOnlyCols.indexOf(c) >= 0) return
        curRow = r; curCol = c
        editText = _getRaw(r, c)
        editing = true
        Qt.callLater(function() { cellInput.forceActiveFocus(); cellInput.selectAll() })
    }
    function _commitEdit() {
        if (!editing) return
        var r = curRow; var c = curCol; var txt = editText
        if (!_isValidCellInput(r, c, txt)) {
            cellInput.forceActiveFocus()
            cellInput.selectAll()
            return
        }
        _set(r, c, txt)
        editing = false
        editText = ""
        focusCatcher.forceActiveFocus()
        _repaintGrid()
        root.cellEdited(r, c, txt)
    }
    function _cancelEdit() {
        editing = false
        editText = ""
        focusCatcher.forceActiveFocus()
        _repaintGrid()
    }

    function _navigate(dr, dc, extendSel) {
        if (editing) _commitEdit()
        if (!extendSel) { _clearDiscreteRowSelection(); _clearDiscreteColSelection() }

        // Boundary-exit policy: only exit the spreadsheet when the user is
        // trying to move past the top-left or bottom-right corner. This
        // keeps the spreadsheet feeling like a single large cell in the
        // surrounding layout — you can drive the cursor freely within it,
        // and only step outside by pressing "past" a corner.
        //
        //   dr = -1 and we're at row 0, col 0  → exit backward
        //   dr = +1 and we're at last row, last col  → exit forward
        //   dc = -1 and we're at row 0, col 0  → exit backward
        //   dc = +1 and we're at last row, last col  → exit forward
        //
        // Otherwise clamp (stay put at the respective edge).
        if (!extendSel) {
            var atTopLeft     = (curRow === 0)             && (curCol === 0)
            var atBottomRight = (curRow === numRows - 1)   && (curCol === numCols - 1)
            if (dr < 0 && atTopLeft)     { root._moveToNextTabStop(false); return }
            if (dr > 0 && atBottomRight) { root._moveToNextTabStop(true);  return }
            if (dc < 0 && atTopLeft)     { root._moveToNextTabStop(false); return }
            if (dc > 0 && atBottomRight) { root._moveToNextTabStop(true);  return }
        }

        var r = Math.max(0, Math.min(numRows - 1, curRow + dr))
        var c = Math.max(0, Math.min(numCols - 1, curCol + dc))
        curRow = r; curCol = c
        if (!extendSel) { selAnchorRow = r; selAnchorCol = c }
        _scrollTo(r, c)
        _ensureVisibleInParent(r, c)
        _repaintAll()
    }
    function _moveTo(r, c) {
        if (editing) _commitEdit()
        _clearDiscreteRowSelection()
        r = Math.max(0, Math.min(numRows - 1, r))
        c = Math.max(0, Math.min(numCols - 1, c))
        curRow = r; curCol = c
        selAnchorRow = r; selAnchorCol = c
        _scrollTo(r, c)
        _ensureVisibleInParent(r, c)
        _repaintAll()
    }

    // When the spreadsheet lives inside an outer Flickable/ScrollView that
    // does the actual vertical scrolling (e.g. the Phases panel, where all
    // sheet rows are rendered inline and the outer panel scrolls), walk up
    // the parent chain to find that scroller and nudge its contentY so the
    // current cell is visible. Only vertical scrolling is adjusted — the
    // spreadsheet manages its own horizontal scrollbar internally, and
    // touching the outer's contentX causes the entire enclosing panel to
    // shift unexpectedly. Harmless when not embedded in a scroller.
    function _ensureVisibleInParent(r, c) {
        var outer = null
        var p = root.parent
        while (p) {
            // Flickable ducktype
            if (p.contentY !== undefined && p.contentHeight !== undefined
                    && p.height !== undefined && p.contentItem !== undefined) {
                outer = p
                break
            }
            p = p.parent
        }
        if (!outer) return

        // Compute the cell's sheet-space rect, then map to outer contentItem.
        var cellX = root.effectiveHdrColW + colX(c)      - flick.contentX
        var cellY = root.effectiveHdrRowH + rowY(r)      - flick.contentY
        var cellH = rowH[r]

        var topLeft = root.mapToItem(outer.contentItem, cellX, cellY)
        var cellTop = topLeft.y
        var cellBot = topLeft.y + cellH

        if (cellTop < outer.contentY) {
            outer.contentY = Math.max(0, cellTop)
        } else if (cellBot > outer.contentY + outer.height) {
            outer.contentY = Math.min(Math.max(0, outer.contentHeight - outer.height),
                                       cellBot - outer.height)
        }
    }

    function _autoFitCol(c) {
        var ctx = measureCanvas.getContext("2d")
        if (!ctx) return
        ctx.font = cellFont.pixelSize + "px '" + cellFont.family + "'"
        var minW = 28
        var best = minW
        for (var r = 0; r < numRows; r++) {
            var txt = _getVal(r, c)
            if (txt === "") continue
            var w = ctx.measureText(txt).width + 14
            if (w > best) best = w
        }
        var hdrW = ctx.measureText(_colHdrLabel(c)).width + 18
        if (hdrW > best) best = hdrW
        var arr = colW.slice()
        arr[c] = Math.ceil(best)
        colW = arr
        _repaintAll()
    }
    function _autoFitRow(r) {
        var arr = rowH.slice()
        arr[r] = Math.max(20, defaultRowH)
        rowH = arr
        _repaintAll()
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

    // ─────────────────────────────────────────────────────────────────────
    //  REPAINT TRIGGERS
    // ─────────────────────────────────────────────────────────────────────
    function _repaintGrid() {
        gridCanvas.requestPaint()
    }
    function _repaintAll() {
        gridCanvas.requestPaint()
        colHeaderCanvas.requestPaint()
        rowHeaderCanvas.requestPaint()
    }

    onStoreChanged:        gridCanvas.requestPaint()
    onColWChanged:         _repaintAll()
    onRowHChanged:         _repaintAll()
    onColLabelsChanged:    colHeaderCanvas.requestPaint()
    onRowLabelsChanged:    Qt.callLater(function() { _updateHdrColW(); rowHeaderCanvas.requestPaint(); if (stretchToWidth) fitToWidth() })
    onHdrColWChanged:      Qt.callLater(function() { if (stretchToWidth) fitToWidth() })
    onShowRowHeadersChanged: Qt.callLater(function() { _updateHdrColW(); if (stretchToWidth) fitToWidth(); _repaintAll() })
    onShowCornerCellChanged: _repaintAll()
    onTightEmbeddedHeaderChanged: Qt.callLater(function() { _updateHdrColW(); if (stretchToWidth) fitToWidth(); _repaintAll() })
    onTightHdrColWChanged:  Qt.callLater(function() { _updateHdrColW(); if (stretchToWidth) fitToWidth(); _repaintAll() })
    onTightHdrRowHChanged:  _repaintAll()
    onWidthChanged:        Qt.callLater(function() { if (stretchToWidth) fitToWidth() })
    onCurRowChanged:       _repaintAll()
    onCurColChanged:       _repaintAll()
    onSelAnchorRowChanged: _repaintAll()
    onSelAnchorColChanged: _repaintAll()
    onEditingChanged:      _repaintGrid()

    // Numeric input validator
    RegularExpressionValidator {
        id: numericCellValidator
        regularExpression: /[-+]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][-+]?\d+)?|[-+]?|[-+]?\.|[-+]?\d+[eE]?|[-+]?\d+(?:\.\d*)?[eE][-+]?/
    }

    // Hidden Canvas used only for text measurement (autofit, header sizing)
    Canvas {
        id: measureCanvas
        visible: false; width: 1; height: 1
        onAvailableChanged: if (available) Qt.callLater(root._updateHdrColW)
    }

    // Hidden TextEdit for clipboard bridging when gClipboard not present
    TextEdit { id: clipBridge; visible: false; width: 0; height: 0 }

    // ═════════════════════════════════════════════════════════════════════
    //  UI LAYOUT
    //
    //  ┌──────────┬──────────────────────────────────┐
    //  │ Corner   │ Column header strip              │
    //  ├──────────┼──────────────────────────────────┤
    //  │ Row hdr  │ Grid (Flickable)                 │
    //  │ strip    │                                  │
    //  └──────────┴──────────────────────────────────┘
    // ═════════════════════════════════════════════════════════════════════
    Item {
        id: sheetBody
        anchors.fill: parent

        // ── Corner cell ──────────────────────────────────────────────────
        Rectangle {
            id: cornerCell
            visible: root.showCornerCell && root.showRowHeaders
            x: 0; y: 0; z: 4
            width: root.effectiveHdrColW; height: root.effectiveHdrRowH
            color: ((!root.hasDiscreteRowSelection && !root.hasDiscreteColSelection && root.selR1 === 0 && root.selR2 === root.numRows - 1 &&
                    root.selC1 === 0 && root.selC2 === root.numCols - 1) ||
                    (root.hasDiscreteRowSelection && root.selectedRows.length === root.numRows))
                   ? root.selFill : root.headerBg
            border.color: root.headerBorder
            border.width: 1

            Text {
                anchors.fill: parent
                anchors.leftMargin: 8
                verticalAlignment: Text.AlignVCenter
                text: root.cornerLabel
                font: root.headerFont
                color: root.textMuted
                elide: Text.ElideRight
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { root._selectAll(); focusCatcher.forceActiveFocus() }
            }
        }

        // ── Column header strip ──────────────────────────────────────────
        Item {
            id: colHeaderStrip
            x: root.effectiveHdrColW; y: 0; z: 3
            width: sheetBody.width - root.effectiveHdrColW - root.effectiveVBarW
            height: root.effectiveHdrRowH
            clip: true

            Canvas {
                id: colHeaderCanvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Cooperative

                onPaint: {
                    var ctx = getContext("2d")
                    if (!ctx) return
                    ctx.clearRect(0, 0, width, height)

                    // Background
                    ctx.fillStyle = root.headerBg
                    ctx.fillRect(0, 0, width, height)

                    // Selection-tinted columns
                    ctx.fillStyle = root.selFill
                    if (root.hasDiscreteColSelection) {
                        for (var dci = 0; dci < root.selectedCols.length; dci++) {
                            var cc = root.selectedCols[dci]
                            var csx = root.colX(cc) - flick.contentX
                            ctx.fillRect(csx, 0, root.colW[cc], height)
                        }
                    } else if (!root.hasDiscreteRowSelection) {
                        var sx = root.colX(root.selC1) - flick.contentX
                        var sw = 0
                        for (var sc = root.selC1; sc <= root.selC2; sc++)
                            sw += root.colW[sc]
                        if (sw > 0) {
                            ctx.fillRect(sx, 0, sw, height)
                        }
                    }

                    // Vertical separators between columns
                    ctx.strokeStyle = root.headerBorder
                    ctx.lineWidth = 1
                    var x = -flick.contentX
                    ctx.beginPath()
                    for (var c = 0; c < root.numCols; c++) {
                        x += root.colW[c]
                        var px = Math.round(x) + 0.5
                        ctx.moveTo(px, 0)
                        ctx.lineTo(px, height)
                    }
                    ctx.stroke()

                    // Bottom border
                    ctx.beginPath()
                    var by = Math.round(height) - 0.5
                    ctx.moveTo(0, by)
                    ctx.lineTo(width, by)
                    ctx.stroke()
                }
            }

            // Native Text labels for column headers (crisp), positioned over Canvas
            Repeater {
                model: root.numCols
                delegate: Item {
                    id: colHdr
                    property int colIdx: index
                    property string _q: (root.columnQuantities && colIdx < root.columnQuantities.length)
                                        ? root.columnQuantities[colIdx] : ""
                    property bool hasUnit: _q !== "" && typeof gUnits !== "undefined"
                    x: root.colX(colIdx) - flick.contentX
                    y: 0
                    width: root.colW[colIdx]
                    height: root.effectiveHdrRowH
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        anchors.topMargin: 2
                        anchors.bottomMargin: 2
                        spacing: hasUnit ? 1 : 0

                        Text {
                            id: hdrLbl
                            width: parent.width
                            height: hasUnit ? 18 : parent.height
                            verticalAlignment: hasUnit ? Text.AlignBottom : Text.AlignVCenter
                            text: root._colHdrLabel(colIdx)
                            font: root.headerFont
                            color: root.textMuted
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Loader {
                            id: unitTok
                            active: hasUnit
                            visible: hasUnit
                            width: parent.width
                            height: hasUnit ? 16 : 0
                            sourceComponent: Component {
                                UnitToken {
                                    width: unitTok.width
                                    height: unitTok.height
                                    quantity: colHdr._q
                                    displayUnit: (root.columnUnits && colHdr.colIdx < root.columnUnits.length)
                                                 ? (root.columnUnits[colHdr.colIdx] || "")
                                                 : ""
                                    onUnitChosen: root.columnUnitChanged(colHdr.colIdx, unit)
                                }
                            }
                        }
                    }

                    MouseArea {
                        x: 0
                        y: 0
                        width: parent.width
                        height: hasUnit ? hdrLbl.height : parent.height
                        z: 10
                        acceptedButtons: Qt.LeftButton
                        onClicked: function(mouse) {
                            root._selectColumn(
                                colHdr.colIdx,
                                !!(mouse.modifiers & Qt.ShiftModifier),
                                !!(mouse.modifiers & Qt.ControlModifier))
                            focusCatcher.forceActiveFocus()
                        }
                    }
                }
            }

            // Column resize handles
            Repeater {
                model: root.numCols
                delegate: Item {
                    id: colRH
                    property int colIdx: index
                    property real _sx: 0; property real _sw: 0
                    x: root.colX(colIdx) + root.colW[colIdx] - 3 - flick.contentX
                    y: 0; width: 6; height: root.effectiveHdrRowH; z: 5
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeHorCursor
                        hoverEnabled: true
                        onPressed:  function(e) { colRH._sx = e.x + colRH.x; colRH._sw = root.colW[colRH.colIdx] }
                        onPositionChanged: function(e) {
                            if (!pressed) return
                            var arr = root.colW.slice()
                            var newW = Math.max(24, colRH._sw + (e.x + colRH.x - colRH._sx))
                            arr[colRH.colIdx] = newW
                            root.colW = arr
                            root._repaintAll()
                        }
                        onDoubleClicked: function(e) { root._autoFitCol(colRH.colIdx) }
                    }
                }
            }
        }

        // ── Row header strip ─────────────────────────────────────────────
        Item {
            id: rowHeaderStrip
            visible: root.showRowHeaders
            x: 0; y: root.effectiveHdrRowH; z: 3
            width: root.effectiveHdrColW
            height: sheetBody.height - root.effectiveHdrRowH - root.effectiveHBarH
            clip: true

            Canvas {
                id: rowHeaderCanvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Cooperative

                onPaint: {
                    var ctx = getContext("2d")
                    if (!ctx) return
                    ctx.clearRect(0, 0, width, height)

                    // Background
                    ctx.fillStyle = root.rowHdrBg
                    ctx.fillRect(0, 0, width, height)

                    // Selection-tinted rows
                    ctx.fillStyle = root.selFill
                    if (root.hasDiscreteRowSelection) {
                        for (var dri = 0; dri < root.selectedRows.length; dri++) {
                            var rr = root.selectedRows[dri]
                            var rsy = root.rowY(rr) - flick.contentY
                            ctx.fillRect(0, rsy, width, root.rowH[rr])
                        }
                    } else if (!root.hasDiscreteColSelection) {
                        var sy = root.rowY(root.selR1) - flick.contentY
                        var sh = 0
                        for (var sr = root.selR1; sr <= root.selR2; sr++)
                            sh += root.rowH[sr]
                        if (sh > 0)
                            ctx.fillRect(0, sy, width, sh)
                    }

                    // Horizontal separators between rows
                    ctx.strokeStyle = root.headerBorder
                    ctx.lineWidth = 1
                    var y = -flick.contentY
                    ctx.beginPath()
                    for (var r = 0; r < root.numRows; r++) {
                        y += root.rowH[r]
                        var py = Math.round(y) + 0.5
                        ctx.moveTo(0, py)
                        ctx.lineTo(width, py)
                    }
                    ctx.stroke()

                    // Right border
                    ctx.beginPath()
                    var bx = Math.round(width) - 0.5
                    ctx.moveTo(bx, 0)
                    ctx.lineTo(bx, height)
                    ctx.stroke()
                }
            }

            // Native Text labels for row headers
            Repeater {
                model: root.numRows
                delegate: Item {
                    id: rowHdr
                    property int rowIdx: index
                    x: 0
                    y: root.rowY(rowIdx) - flick.contentY
                    width: root.effectiveHdrColW
                    height: root.rowH[rowIdx]
                    clip: true

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignLeft
                        text: root._rowHdrLabel(rowIdx)
                        font: root.cellFont
                        color: root.textMain
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            root._selectRow(
                                rowHdr.rowIdx,
                                !!(mouse.modifiers & Qt.ShiftModifier),
                                !!(mouse.modifiers & Qt.ControlModifier))
                            focusCatcher.forceActiveFocus()
                        }
                    }
                }
            }

            // Row resize handles
            Repeater {
                model: root.numRows
                delegate: Item {
                    id: rowRH
                    property int rowIdx: index
                    property real _sy: 0; property real _sh: 0
                    x: 0
                    y: root.rowY(rowIdx) + root.rowH[rowIdx] - 3 - flick.contentY
                    width: root.effectiveHdrColW; height: 6; z: 5
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeVerCursor
                        hoverEnabled: true
                        onPressed:  function(e) { rowRH._sy = e.y + rowRH.y; rowRH._sh = root.rowH[rowRH.rowIdx] }
                        onPositionChanged: function(e) {
                            if (!pressed) return
                            var arr = root.rowH.slice()
                            var newH = Math.max(16, rowRH._sh + (e.y + rowRH.y - rowRH._sy))
                            arr[rowRH.rowIdx] = newH
                            root.rowH = arr
                            root._repaintAll()
                        }
                        onDoubleClicked: function(e) { root._autoFitRow(rowRH.rowIdx) }
                    }
                }
            }
        }

        // ── Grid area (scrollable) ───────────────────────────────────────
        Flickable {
            id: flick
            x: root.effectiveHdrColW; y: root.effectiveHdrRowH
            width:  sheetBody.width  - root.effectiveHdrColW - root.effectiveVBarW
            height: sheetBody.height - root.effectiveHdrRowH - root.effectiveHBarH
            clip: true
            contentWidth:  root.contentW
            contentHeight: root.contentH
            boundsBehavior: Flickable.StopAtBounds
            interactive: false   // scrollbars + wheel only; clicks go to inner MouseArea

            // Repaint frozen header canvases when grid scrolls — Canvas
            // doesn't auto-repaint on Flickable contentX/Y changes, so the
            // header separator lines need an explicit nudge.
            onContentXChanged: colHeaderCanvas.requestPaint()
            onContentYChanged: rowHeaderCanvas.requestPaint()

            // Inner item that holds Canvas + Text overlays + cell input
            Item {
                width:  Math.max(flick.width,  root.contentW)
                height: Math.max(flick.height, root.contentH)

                // ── Grid Canvas: backgrounds, alt rows, grid lines, sel ──
                Canvas {
                    id: gridCanvas
                    anchors.fill: parent
                    renderTarget: Canvas.Image
                    renderStrategy: Canvas.Cooperative

                    onPaint: {
                        var ctx = getContext("2d")
                        if (!ctx) return
                        ctx.clearRect(0, 0, width, height)

                        var totalW = root.totalW()
                        var totalH = root.totalH()

                        // 1. Base background
                        ctx.fillStyle = root.cellBg
                        ctx.fillRect(0, 0, totalW, totalH)

                        // 2. Alternating row tints
                        if (root.alternatingRows) {
                            ctx.fillStyle = root.cellBgAlt
                            var ay = 0
                            for (var ar = 0; ar < root.numRows; ar++) {
                                if (ar % 2 === 1)
                                    ctx.fillRect(0, ay, totalW, root.rowH[ar])
                                ay += root.rowH[ar]
                            }
                        }

                        // 3. Selection fill
                        ctx.fillStyle = root.selFill
                        if (root.hasDiscreteRowSelection) {
                            for (var dri = 0; dri < root.selectedRows.length; dri++) {
                                var rr = root.selectedRows[dri]
                                var rowSy = root.rowY(rr)
                                ctx.fillRect(0, rowSy, totalW, root.rowH[rr])
                            }
                        } else if (root.hasDiscreteColSelection) {
                            for (var dci = 0; dci < root.selectedCols.length; dci++) {
                                var cc = root.selectedCols[dci]
                                var colSx = root.colX(cc)
                                ctx.fillRect(colSx, 0, root.colW[cc], totalH)
                            }
                        } else {
                            var sx = root.colX(root.selC1)
                            var sy = root.rowY(root.selR1)
                            var sw = 0, sh = 0
                            for (var sc = root.selC1; sc <= root.selC2; sc++) sw += root.colW[sc]
                            for (var sr = root.selR1; sr <= root.selR2; sr++) sh += root.rowH[sr]
                            ctx.fillRect(sx, sy, sw, sh)
                        }

                        // 4. Active-cell fill (slightly stronger blue)
                        var cx = root.colX(root.curCol)
                        var cy = root.rowY(root.curRow)
                        var cw = root.colW[root.curCol] || 0
                        var ch = root.rowH[root.curRow] || 0
                        ctx.fillStyle = root.cursorFill
                        ctx.fillRect(cx, cy, cw, ch)

                        // 5. Edit background (warmer tint)
                        if (root.editing) {
                            ctx.fillStyle = root.editBg
                            ctx.fillRect(cx, cy, cw, ch)
                        }

                        // 6. Grid lines — vertical (with +0.5 for crispness)
                        ctx.strokeStyle = root.gridColor
                        ctx.lineWidth = 1
                        var x = 0
                        ctx.beginPath()
                        for (var c = 0; c < root.numCols; c++) {
                            x += root.colW[c]
                            var px = Math.round(x) + 0.5
                            ctx.moveTo(px, 0)
                            ctx.lineTo(px, totalH)
                        }
                        // Horizontal grid lines
                        var y = 0
                        for (var r = 0; r < root.numRows; r++) {
                            y += root.rowH[r]
                            var py = Math.round(y) + 0.5
                            ctx.moveTo(0, py)
                            ctx.lineTo(totalW, py)
                        }
                        ctx.stroke()

                        // 7. Active-cell BLUE LEFT RULE (like PGridValue)
                        ctx.fillStyle = root.cursorRule
                        ctx.fillRect(cx, cy, 2, ch)

                        // 8. Active-cell crisp border (1px dark)
                        ctx.strokeStyle = root.cursorRule
                        ctx.lineWidth = 1
                        var bx = Math.round(cx) + 0.5
                        var by = Math.round(cy) + 0.5
                        var bw = Math.round(cw) - 1
                        var bh = Math.round(ch) - 1
                        ctx.strokeRect(bx, by, bw, bh)
                    }
                }

                // ── Native Text overlays for visible cells (crisp) ──
                // We render ALL cells as Text items. For numCols * numRows
                // up to ~2000 this is fine; beyond that, virtualization
                // would kick in. PGrid-style use cases stay well under.
                Repeater {
                    id: cellRepeater
                    model: root.numRows * root.numCols
                    delegate: Item {
                        property int rowIdx: Math.floor(index / root.numCols)
                        property int colIdx: index % root.numCols
                        x: root.colX(colIdx)
                        y: root.rowY(rowIdx)
                        width: root.colW[colIdx]
                        height: root.rowH[rowIdx]
                        visible: !(root.editing && rowIdx === root.curRow && colIdx === root.curCol)

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            text: {
                                root._unitRev    // re-eval on unit set change
                                return root._getVal(rowIdx, colIdx)
                            }
                            font: root.cellFont
                            color: root._isEditableColumn(colIdx) ? root.valueBlue : root.textMain
                            elide: Text.ElideRight
                        }
                    }
                }

                // Inline cell editor — single TextInput re-positioned over current cell
                TextInput {
                    id: cellInput
                    x: root.colX(root.curCol)
                    y: root.rowY(root.curRow)
                    width:  root.colW[root.curCol]
                    height: root.rowH[root.curRow]
                    visible: root.editing
                    font: root.cellFont
                    color: root.valueBlue
                    clip: true
                    selectByMouse: true
                    validator: root.numericOnlyCells ? numericCellValidator : null
                    inputMethodHints: root.numericOnlyCells
                                      ? (Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText)
                                      : Qt.ImhNone
                    leftPadding: 6
                    rightPadding: 6
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignRight
                    text: root.editText
                    onTextEdited: { root.editText = text }
                    Keys.onReturnPressed:  function(e) { root._commitEdit(); e.accepted = true }
                    Keys.onTabPressed:     function(e) { root._commitEdit(); root._navigate(0, 1) }
                    Keys.onEscapePressed:  function(e) { root._cancelEdit() }
                    Keys.onUpPressed:      function(e) { root._commitEdit(); root._navigate(-1, 0) }
                    Keys.onDownPressed:    function(e) { root._commitEdit(); root._navigate(1, 0) }
                    Keys.onLeftPressed:    function(e) { if (cursorPosition === 0) { root._commitEdit(); root._navigate(0, -1) } }
                    Keys.onRightPressed:   function(e) { if (cursorPosition === length) { root._commitEdit(); root._navigate(0, 1) } }
                }

                // ── Mouse interaction on the grid ──
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    hoverEnabled: false

                    onWheel: function(wheel) {
                        var step = 60
                        var needsY = root.contentH > flick.height
                        var needsX = root.contentW > flick.width
                        if (needsY && wheel.angleDelta.y !== 0) {
                            var newY = flick.contentY - (wheel.angleDelta.y / 120) * step
                            flick.contentY = Math.max(0, Math.min(newY, root.contentH - flick.height))
                        }
                        if (needsX && wheel.angleDelta.x !== 0) {
                            var newX = flick.contentX - (wheel.angleDelta.x / 120) * step
                            flick.contentX = Math.max(0, Math.min(newX, root.contentW - flick.width))
                        }
                        if (!needsY && !needsX)
                            root.wheelPassthrough(wheel.angleDelta.y, wheel.angleDelta.x)
                        wheel.accepted = true
                    }

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
                        root._clearDiscreteRowSelection()
                        root._clearDiscreteColSelection()
                        var hit = _hitTest(e.x, e.y)
                        root.curRow = hit.r; root.curCol = hit.c
                        if (!(e.modifiers & Qt.ShiftModifier)) {
                            root.selAnchorRow = hit.r
                            root.selAnchorCol = hit.c
                        }
                        e.accepted = true
                    }

                    onPositionChanged: function(e) {
                        if (!pressed) return
                        var hit = _hitTest(e.x, e.y)
                        if (hit.r !== root.curRow || hit.c !== root.curCol) {
                            root.curRow = hit.r
                            root.curCol = hit.c
                        }
                    }

                    onDoubleClicked: function(e) {
                        var hit = _hitTest(e.x, e.y)
                        root._beginEdit(hit.r, hit.c)
                        e.accepted = true
                    }
                }
            }
        }

        // ── Scrollbars ──
        ScrollBar {
            id: vBar
            anchors { right: sheetBody.right; top: sheetBody.top; topMargin: root.effectiveHdrRowH; bottom: sheetBody.bottom; bottomMargin: root.effectiveHBarH }
            orientation: Qt.Vertical; policy: root.verticalScrollBarPolicy
            visible: root.verticalScrollBarPolicy !== ScrollBar.AlwaysOff
            size:     flick.height     / Math.max(1, root.contentH)
            position: flick.contentY   / Math.max(1, root.contentH)
            onPositionChanged: if (pressed) flick.contentY = position * root.contentH
        }
        ScrollBar {
            id: hBar
            anchors { left: sheetBody.left; leftMargin: root.effectiveHdrColW; right: sheetBody.right; rightMargin: root.effectiveVBarW; bottom: sheetBody.bottom }
            orientation: Qt.Horizontal; policy: root.horizontalScrollBarPolicy
            visible: root.horizontalScrollBarPolicy !== ScrollBar.AlwaysOff
            size:     flick.width      / Math.max(1, root.contentW)
            position: flick.contentX   / Math.max(1, root.contentW)
            onPositionChanged: if (pressed) flick.contentX = position * root.contentW
        }
    }

    // ── Keyboard focus when not editing ──
    Item {
        id: focusCatcher
        anchors.fill: parent
        focus: true

        // Intercept Tab/Backtab here so they do wrap-style movement within
        // the spreadsheet (like Excel), only exiting to the next/previous
        // tab stop when the user tries to go past the bottom-right / top-left
        // corner. Keys.priority: BeforeItem so this runs before the root's
        // Tab handler (which would otherwise exit the sheet immediately).
        Keys.priority: Keys.BeforeItem

        Keys.onTabPressed: function(e) {
            var r = root.curRow
            var c = root.curCol
            if (c < root.numCols - 1) {
                root._moveTo(r, c + 1)
            } else if (r < root.numRows - 1) {
                root._moveTo(r + 1, 0)
            } else {
                // At bottom-right corner: exit the spreadsheet forward.
                root._moveToNextTabStop(true)
            }
            e.accepted = true
        }
        Keys.onBacktabPressed: function(e) {
            var r = root.curRow
            var c = root.curCol
            if (c > 0) {
                root._moveTo(r, c - 1)
            } else if (r > 0) {
                root._moveTo(r - 1, root.numCols - 1)
            } else {
                // At top-left corner: exit the spreadsheet backward.
                root._moveToNextTabStop(false)
            }
            e.accepted = true
        }

        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_F2 && !root.readOnly) {
                root._beginEdit(root.curRow, root.curCol); e.accepted = true; return
            }
            // Ctrl+A — select all
            if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                root._selectAll(); e.accepted = true; return
            }
            // Ctrl+C
            if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
                root._copyToClipboard(root._selectedTextWithHeaders())
                e.accepted = true; return
            }
            // Ctrl+V
            if (!root.readOnly && e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier)) {
                root._paste(); e.accepted = true; return
            }
            // Delete / Backspace — clear selection
            if (!root.readOnly && (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace)) {
                if (root.hasDiscreteRowSelection) {
                    for (var dri = 0; dri < root.selectedRows.length; dri++)
                        for (var dcc = 0; dcc < root.numCols; dcc++)
                            if (root._isEditableColumn(dcc))
                                root._set(root.selectedRows[dri], dcc, "")
                } else if (root.hasDiscreteColSelection) {
                    for (var dci = 0; dci < root.selectedCols.length; dci++)
                        for (var drr = 0; drr < root.numRows; drr++)
                            if (root._isEditableColumn(root.selectedCols[dci]))
                                root._set(drr, root.selectedCols[dci], "")
                } else {
                    for (var dr = root.selR1; dr <= root.selR2; dr++)
                        for (var dc = root.selC1; dc <= root.selC2; dc++)
                            if (root._isEditableColumn(dc))
                                root._set(dr, dc, "")
                }
                root._repaintGrid(); e.accepted = true; return
            }
            // Arrow keys move between cells; Enter moves down like Excel.
            // Tab/Backtab are intentionally NOT column-right/left here —
            // they're treated as app-wide focus navigation (handled by the
            // root's Keys.onTabPressed). Omitting Tab from this branch lets
            // the event bubble back up to the root.
            var drow = 0, dcol = 0
            if      (e.key === Qt.Key_Up)    drow = -1
            else if (e.key === Qt.Key_Down)  drow =  1
            else if (e.key === Qt.Key_Left)  dcol = -1
            else if (e.key === Qt.Key_Right) dcol =  1
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) drow = 1
            if (drow || dcol) {
                var shift = !!(e.modifiers & Qt.ShiftModifier)
                root._navigate(drow, dcol, shift)
                e.accepted = true; return
            }
            // Printable key → start editing
            if (!root.readOnly && e.text.length > 0 && !root.editing) {
                if (!root._isEditableColumn(root.curCol)) { e.accepted = true; return }
                if (root.numericOnlyCells && !/^[-+0-9.eE]$/.test(e.text)) { e.accepted = true; return }
                root._beginEdit(root.curRow, root.curCol)
                root.editText = e.text
                e.accepted = true
            }
        }
    }
}
