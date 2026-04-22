import QtQuick 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PGridUnit.qml  —  RESTYLED
//
//  Column-2 unit token cell. Thin wrapper around UnitToken — UnitToken now
//  carries all the visual treatment (chiseled-raised bevel, grey fill, hover
//  states). PGridUnit exists so the grid layout has a cell type matching
//  PGridLabel/PGridValue's naming and to handle keyboard focus navigation
//  and the per-cell focus ring.
//
//  Properties pass through to the underlying UnitToken.
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: cell

    activeFocusOnTab: true

    // Grid-cell navigation contract (see PGridLabel for full description).
    // Unit cells are always tab stops — the user can open the picker with
    // Space or Enter.
    property bool tabStop: true

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
        var item = cell
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === cell)
                return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    function _gridColumns() {
        if (parent && parent.columns !== undefined && parent.columns > 0)
            return parent.columns
        return 3
    }

    function _moveToNextRow(forward) {
        var startX = cell.x
        var startY = cell.y
        var g = cell.parent

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

        // Cross-grid: find next row in the focus chain at best-matching x.
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
        cell._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        cell._moveToNextTabStop(false); event.accepted = true
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Right) { cell._moveSteps(1); event.accepted = true }
        else if (event.key === Qt.Key_Left) { cell._moveSteps(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { cell._moveToNextRow(true); event.accepted = true }
        else if (event.key === Qt.Key_Up) { cell._moveToNextRow(false); event.accepted = true }
        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (unitTok.pickerOpened()) unitTok.closePicker()
            else unitTok.openPicker()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && unitTok.pickerOpened()) {
            unitTok.closePicker()
            event.accepted = true
        }
    }

    property string quantity:    "Dimensionless"
    property real   siValue:     NaN
    property string displayUnit: ""
    property int    decimals:    -1
    property bool   alt:         false

    signal unitOverride(string unit)

    Layout.preferredWidth: 72
    Layout.minimumWidth: 72
    Layout.preferredHeight: 22
    Layout.minimumHeight: 22

    UnitToken {
        id: unitTok
        anchors.fill: parent
        quantity:    cell.quantity
        siValue:     cell.siValue
        displayUnit: cell.displayUnit
        decimals:    cell.decimals
        onUnitChosen: function(u) { cell.unitOverride(u) }
    }

    // Focus ring — drawn on top of the UnitToken so it's visible when the
    // cell is tab-focused. Matches the treatment on PGridValue/PGridLabel.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: cell.activeFocus
                      ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7")
                      : "transparent"
        border.width: cell.activeFocus ? 1 : 0
        z: 5
    }
}
