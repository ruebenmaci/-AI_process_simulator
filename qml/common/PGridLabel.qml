import QtQuick 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PGridLabel.qml  —  RESTYLED
//
//  Column-0 label cell. Just text, left-aligned, colored by theme.
//
//  Visual treatment: no background fill, no border — labels in the new
//  vocabulary are plain text that sits directly on the page/groupbox
//  background. Only the text itself is visible.
//
//  This matches the mockup: "Mass flow", "Temperature", etc. render as
//  simple text tokens, with all the visual weight carried by the chiseled
//  value cells to their right.
//
//  Backward-compat: Layout.preferredWidth defaults to 200 for existing
//  GridLayout callers. In plain Grid callers, set `width` directly.
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: cell

    activeFocusOnTab: true

    // Grid-cell navigation contract:
    //   arrow keys  → walk the natural focus chain one cell at a time
    //   Tab/Backtab → walk forward/back, skipping over cells whose tabStop is
    //                 false (labels and read-only values). Unknown items in
    //                 the chain (PTextField, PComboBox, native controls) are
    //                 treated as tab stops so we don't get stuck.
    property bool tabStop: false   // labels are never tab stops

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
            // Items outside our cell family don't carry a tabStop property
            // — treat them as stops so focus can leave the grid normally.
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

    // Tab handling uses dedicated handlers with BeforeItem priority so our
    // custom tabstop-aware walker runs before Qt's built-in focus-chain
    // advancement (which would land on any cell with activeFocusOnTab: true,
    // including labels).
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
    }

    property string text: ""
    property bool   alt:  false

    // Baseline widths. preferredWidth of 170 matches the old default so
    // existing layouts are unchanged. minimumWidth of 120 is a floor that
    // prevents the label column from collapsing below the size needed to
    // render realistic label strings ("Outlet vapor fraction" etc.) at
    // 11 px Segoe UI. Callers that set their own Layout.preferredWidth still
    // win at normal sizes; this minimum only kicks in when the container
    // is compressed.
    Layout.preferredWidth: 170
    Layout.minimumWidth:   120
    Layout.preferredHeight: 22
    Layout.minimumHeight:   22

    // Focus ring only — no background fill, no border lines
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: cell.activeFocus
                      ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7")
                      : "transparent"
        border.width: cell.activeFocus ? 1 : 0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: cell.forceActiveFocus()
    }

    Text {
        text: cell.text
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
        font.family: "Segoe UI"
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#1f2226"
        elide: Text.ElideRight
        width: parent.width - 4
    }
}
