import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PGridValue.qml  —  RESTYLED (dimensional HYSYS vocabulary)
//
//  Column-1 value cell.  Three render modes:
//    1) numeric, read-only      — displays gUnits.format(quantity, siValue, displayUnit)
//    2) numeric, editable       — TextField; commits via gUnits.parseInline()
//    3) text                    — plain `textValue` string (set isText: true)
//
//  Visual treatment:
//    Editable  : pale-blue fill + chiseled-SUNKEN 1px bevel
//    Calculated: slightly grey fill + SAME chiseled-SUNKEN 1px bevel
//    Focus     : accent-blue 1px border drawn on top of the bevel
//
//  All visual tokens come from gAppTheme.pv* so the look swaps automatically
//  when the theme changes.
//
//  Layout: kept Layout.fillWidth: true for backward compat with the existing
//  GridLayout callers (Identification & Thermo Specs sections). In plain Grid
//  callers, an explicit `width` property takes precedence.
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: cell

    activeFocusOnTab: !editable

    // Grid-cell navigation contract:
    //   arrow keys  → walk the natural focus chain one cell at a time
    //   Tab/Backtab → walk forward/back, skipping over cells whose tabStop is
    //                 false (labels and read-only values). Unknown items in
    //                 the chain (PTextField, PComboBox, native controls) are
    //                 treated as tab stops so we don't get stuck.
    property bool tabStop: editable

    function _moveSteps(steps) {
        var item = cell
        var forward = steps > 0
        var count = Math.abs(steps)
        for (var i = 0; i < count; ++i) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === cell)
                break
        }
        if (item && item !== cell)
            item.forceActiveFocus()
    }

    function _moveToNextTabStop(forward) {
        // Start from whatever currently has focus — could be the inner
        // TextField when editing, or the cell FocusScope otherwise.
        var start = valueInput.activeFocus ? valueInput : cell
        var item = start
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === start)
                return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    function _gridColumns() {
        // Cell's parent is usually the GridLayout. Ask it how many columns
        // it has so Up/Down arrows jump the right number of focus-chain
        // items. Fallback to 3 (the original hardcoded value).
        if (parent && parent.columns !== undefined && parent.columns > 0)
            return parent.columns
        return 3
    }

    // Geometry-based row navigation that preserves column when possible.
    // Tries in order:
    //   1. Find a sibling in the current GridLayout in the next row, picking
    //      the one whose x is closest to our x.
    //   2. If no sibling row exists (we're at top/bottom of this grid), walk
    //      the focus chain until we find an item in a DIFFERENT parent whose
    //      x best matches our x. This lands us in the same column of the
    //      next visible group/GridLayout.
    function _moveToNextRow(forward) {
        var startX = cell.x
        var startY = cell.y
        var g = cell.parent

        // Step 1: look for a sibling row in the same grid.
        if (g && g.children) {
            var candidates = []
            for (var i = 0; i < g.children.length; i++) {
                var c = g.children[i]
                if (c === cell || !c.visible) continue
                if (forward ? c.y > startY : c.y < startY)
                    candidates.push(c)
            }
            if (candidates.length > 0) {
                var targetY = candidates[0].y
                for (var k = 1; k < candidates.length; k++) {
                    var ky = candidates[k].y
                    if (forward ? (ky < targetY) : (ky > targetY))
                        targetY = ky
                }
                var best = null
                var bestDist = Infinity
                for (var j = 0; j < candidates.length; j++) {
                    if (candidates[j].y !== targetY) continue
                    var d = Math.abs(candidates[j].x - startX)
                    if (d < bestDist) { best = candidates[j]; bestDist = d }
                }
                if (best) { best.forceActiveFocus(); return }
            }
        }

        // Step 2: cross-grid. Walk the focus chain looking for items in a
        // different parent, collect the first row's worth, pick the closest
        // match in scene-x. Preserves column when crossing group boundaries.
        var myScene = cell.mapToItem(null, 0, 0)
        var myScenex = myScene.x
        var item = cell
        var rowCandidates = []
        var targetRowY = null
        for (var s = 0; s < 200; ++s) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === cell) break
            if (item.parent === g) continue
            var scene = item.mapToItem(null, 0, 0)
            if (targetRowY === null) {
                targetRowY = scene.y
                rowCandidates.push({ item: item, sceneX: scene.x })
            } else if (Math.abs(scene.y - targetRowY) < 2) {
                rowCandidates.push({ item: item, sceneX: scene.x })
            } else {
                break
            }
        }
        if (rowCandidates.length > 0) {
            var pick = rowCandidates[0]
            var pickDist = Math.abs(pick.sceneX - myScenex)
            for (var r = 1; r < rowCandidates.length; r++) {
                var rd = Math.abs(rowCandidates[r].sceneX - myScenex)
                if (rd < pickDist) { pick = rowCandidates[r]; pickDist = rd }
            }
            pick.item.forceActiveFocus()
        }
    }

    // When this cell gains focus (via Tab, arrow nav, click, whatever),
    // scroll the nearest enclosing Flickable so the cell is visible.
    function _ensureVisible() {
        var flick = null
        var p = cell.parent
        while (p) {
            if (p.contentY !== undefined && p.contentHeight !== undefined
                    && p.height !== undefined && p.contentItem !== undefined) {
                flick = p
                break
            }
            p = p.parent
        }
        if (!flick) return

        var pos = cell.mapToItem(flick.contentItem, 0, 0)
        var cellTop = pos.y
        var cellBot = pos.y + cell.height

        if (cellTop < flick.contentY) {
            flick.contentY = Math.max(0, cellTop)
        } else if (cellBot > flick.contentY + flick.height) {
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                      cellBot - flick.height)
        }
    }

    onActiveFocusChanged: {
        if (activeFocus) cell._ensureVisible()
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        if (valueInput.activeFocus) return   // TextField handles its own Tab
        cell._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        if (valueInput.activeFocus) return
        cell._moveToNextTabStop(false); event.accepted = true
    }

    Keys.onPressed: function(event) {
        if (valueInput.activeFocus)
            return
        if (event.key === Qt.Key_Right) { cell._moveSteps(1); event.accepted = true }
        else if (event.key === Qt.Key_Left) { cell._moveSteps(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { cell._moveToNextRow(true); event.accepted = true }
        else if (event.key === Qt.Key_Up) { cell._moveToNextRow(false); event.accepted = true }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && cell.editable) {
            valueInput.forceActiveFocus()
            valueInput.selectAll()
            event.accepted = true
        }
    }

    property string quantity:    "Dimensionless"
    property real   siValue:     NaN
    property string displayUnit: ""
    property int    decimals:    -1
    property bool   editable:    false
    property bool   isText:      false
    property string textValue:   ""
    property color  valueColor:  editable
        ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7")
        : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcText : "#1f2a34")
    property string alignText:   "right"
    property bool   alt:         false

    // Width contract: fillWidth lets the cell grow to occupy remaining grid
    // space (same as before). minimumWidth of 88 px is a floor that matches
    // the Mass Fraction column width on the Stream Composition spreadsheet,
    // adopted as the universal minimum for numeric value cells so the cell
    // can never render narrower than is comfortable for a formatted number.
    // Per-instance Layout.minimumWidth overrides still work normally if a
    // specific view needs a wider floor.
    Layout.fillWidth: true
    Layout.minimumWidth: 88
    Layout.preferredHeight: 22
    Layout.minimumHeight: 22

    // ── Background fill ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: cell.editable
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditBg : "#fbfdff")
               : "#f0f0f0"
        z: 0
    }

    // ── Chiseled border ──────────────────────────────────────────────────────
    // Editable and calculated cells now share the same sunken border.
    Rectangle {   // top
        x: 0; y: 0; width: parent.width; height: 1
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenLo : "#6c7079"
        z: 1
    }
    Rectangle {   // left
        x: 0; y: 0; width: 1; height: parent.height
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenLo : "#6c7079"
        z: 1
    }
    Rectangle {   // right
        x: parent.width - 1; y: 0; width: 1; height: parent.height
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenHi : "#ffffff"
        z: 1
    }
    Rectangle {   // bottom
        x: 0; y: parent.height - 1; width: parent.width; height: 1
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenHi : "#ffffff"
        z: 1
    }

    signal edited(real siValue)

    property int _unitRev: 0

    readonly property string effectiveUnit: {
        var _r = _unitRev
        if (displayUnit !== "") return displayUnit
        return (typeof gUnits !== "undefined") ? gUnits.defaultUnit(quantity) : ""
    }

    function _commit(typed) {
        if (isText) return
        if (typeof gUnits === "undefined") return
        var r = gUnits.parseInline(quantity, typed, effectiveUnit)
        if (r.ok) edited(r.valueSI)
        else      console.warn("PGridValue: parse failed:", r.error)
    }

    readonly property string _reactiveText: {
        var _rev = _unitRev
        if (isText) return textValue
        if (typeof gUnits === "undefined")
            return Number(siValue).toFixed(Math.max(0, decimals))
        return gUnits.format(quantity, siValue, effectiveUnit, decimals)
    }

    // ── Focus ring (drawn on top of the bevel) ──────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: (valueInput.activeFocus || cell.activeFocus)
                      ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7")
                      : "transparent"
        border.width: (valueInput.activeFocus || cell.activeFocus) ? 1 : 0
        z: 2
    }

    // Click-to-focus for read-only cells. Editable cells let the TextField
    // below handle clicks directly.
    MouseArea {
        anchors.fill: parent
        enabled: !cell.editable
        onClicked: cell.forceActiveFocus()
        z: 2
    }

    // ── Read-only display ────────────────────────────────────────────────────
    Text {
        id: valueDisplay
        visible: !cell.editable
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: cell.alignText === "right" ? Text.AlignRight
                            : cell.alignText === "center" ? Text.AlignHCenter
                            : Text.AlignLeft
        text: cell._reactiveText
        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
        font.family: "Segoe UI"
        color: cell.valueColor
        elide: Text.ElideRight
        z: 3
    }

    // ── Editable input ──────────────────────────────────────────────────────
    TextField {
        id: valueInput
        visible: cell.editable
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
        font.family: "Segoe UI"
        horizontalAlignment: cell.alignText === "left" ? Text.AlignLeft : Text.AlignRight
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7"
        selectByMouse: true
        selectionColor: "#c8ddf3"
        selectedTextColor: color
        padding: 0; topPadding: 0; bottomPadding: 0
        background: Item {}
        activeFocusOnTab: true
        z: 3

        Component.onCompleted: text = cell._reactiveText
        Binding on text {
            value: cell._reactiveText
            when: !valueInput.activeFocus
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                text = cell._reactiveText
                selectAll()
            } else {
                text = cell._reactiveText
            }
        }

        onEditingFinished: {
            cell._commit(text)
            if (!activeFocus)
                text = cell._reactiveText
        }

        // Select-all on first click instead of positioning the cursor where
        // the user clicked. Once focused, subsequent clicks fall through so
        // the user can reposition the cursor or drag-select as normal.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: function(mouse) {
                if (!valueInput.activeFocus) {
                    valueInput.forceActiveFocus()
                    valueInput.selectAll()
                    mouse.accepted = true
                } else {
                    mouse.accepted = false
                }
            }
            onDoubleClicked: function(mouse) { mouse.accepted = false }
        }

        // Tab/Backtab must run before Qt's internal focus-chain handling.
        Keys.priority: Keys.BeforeItem

        Keys.onTabPressed: function(event) {
            cell._commit(text)
            cell._moveToNextTabStop(true)
            event.accepted = true
        }
        Keys.onBacktabPressed: function(event) {
            cell._commit(text)
            cell._moveToNextTabStop(false)
            event.accepted = true
        }
        Keys.onReturnPressed: function(event) {
            cell._commit(text)
            focus = false
            cell.forceActiveFocus()
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            cell._commit(text)
            focus = false
            cell.forceActiveFocus()
            event.accepted = true
        }
        Keys.onEscapePressed: function(event) {
            text = cell._reactiveText
            focus = false
            event.accepted = true
        }
    }

    Connections {
        target: typeof gUnits !== "undefined" ? gUnits : null
        ignoreUnknownSignals: true
        function onUnitsChanged()         { cell._unitRev = cell._unitRev + 1 }
        function onActiveUnitSetChanged() { cell._unitRev = cell._unitRev + 1 }
    }
    Connections {
        target: typeof gFormats !== "undefined" ? gFormats : null
        ignoreUnknownSignals: true
        function onFormatsChanged()         { cell._unitRev = cell._unitRev + 1 }
        function onActiveFormatSetChanged() { cell._unitRev = cell._unitRev + 1 }
    }
}
