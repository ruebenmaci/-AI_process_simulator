import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    property real canvasScale: 1.0

    property int iconNodeBoxSize: 50
    property int droppedIconSize: 42
    property real labelAreaHeight: Math.max(18, Math.round(18 * Math.min(canvasScale, 1.35)))
    property real labelPreferredWidth: Math.max(iconNodeBoxSize, Math.min(260, Math.ceil(tagLabel.contentWidth) + 12))

    width: Math.max(iconNodeBoxSize, labelPreferredWidth)
    height: iconNodeBoxSize + labelAreaHeight + 4

    property string unitId: ""
    property string name: ""
    property string unitType: ""
    property bool selected: false
    property bool highlighted: false
    property var flowsheet: null
    property Item dragBounds: null
    property real dragPaddingLeft: 0
    property real dragPaddingTop: 0
    property real dragPaddingRight: 0
    property real dragPaddingBottom: 0
    property rect exclusionRect: Qt.rect(-1, -1, 0, 0)
    property rect exclusionRect2: Qt.rect(-1, -1, 0, 0)

    signal clicked(string unitId)
    signal doubleClicked(string unitId)
    signal moved(string unitId, real x, real y)
    signal rightClicked(string unitId, real mouseX, real mouseY)

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function intersectsRect(nx, ny, r) {
        return r.width > 0 && r.height > 0
            && nx < r.x + r.width
            && nx + root.width > r.x
            && ny < r.y + r.height
            && ny + root.height > r.y
    }

    function intersectsAnyExclusion(nx, ny) {
        return intersectsRect(nx, ny, exclusionRect) || intersectsRect(nx, ny, exclusionRect2)
    }

    function bestCandidateForRect(nx, ny, r, minX, minY, maxX, maxY) {
        const leftX = clamp(r.x - root.width, minX, maxX)
        const rightX = clamp(r.x + r.width, minX, maxX)
        const aboveY = clamp(r.y - root.height, minY, maxY)
        const belowY = clamp(r.y + r.height, minY, maxY)

        const candidates = [
            Qt.point(leftX, ny),
            Qt.point(rightX, ny),
            Qt.point(nx, aboveY),
            Qt.point(nx, belowY)
        ]

        let best = Qt.point(nx, ny)
        let bestDist = 1e18
        for (let i = 0; i < candidates.length; ++i) {
            const c = candidates[i]
            if (intersectsAnyExclusion(c.x, c.y))
                continue
            const dist = Math.abs(c.x - nx) + Math.abs(c.y - ny)
            if (dist < bestDist) {
                best = c
                bestDist = dist
            }
        }
        return best
    }

    function constrainedPoint(nx, ny) {
        const minX = dragPaddingLeft
        const minY = dragPaddingTop
        const maxX = dragBounds ? Math.max(minX, dragBounds.width - root.width - dragPaddingRight) : nx
        const maxY = dragBounds ? Math.max(minY, dragBounds.height - root.height - dragPaddingBottom) : ny

        nx = clamp(nx, minX, maxX)
        ny = clamp(ny, minY, maxY)

        if (intersectsAnyExclusion(nx, ny)) {
            let best = Qt.point(nx, ny)
            let bestDist = 1e18
            const rects = [exclusionRect, exclusionRect2]
            for (let rIdx = 0; rIdx < rects.length; ++rIdx) {
                const r = rects[rIdx]
                if (!intersectsRect(nx, ny, r))
                    continue
                const candidate = bestCandidateForRect(nx, ny, r, minX, minY, maxX, maxY)
                if (!intersectsAnyExclusion(candidate.x, candidate.y)) {
                    const dist = Math.abs(candidate.x - nx) + Math.abs(candidate.y - ny)
                    if (dist < bestDist) {
                        best = candidate
                        bestDist = dist
                    }
                }
            }
            nx = best.x
            ny = best.y
        }

        return Qt.point(nx, ny)
    }

    function applyConstrainedPosition(nx, ny) {
        const p = constrainedPoint(nx, ny)
        root.x = p.x
        root.y = p.y
    }

    Item {
        id: visualContainer
        width: root.iconNodeBoxSize
        height: root.iconNodeBoxSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: selected ? 2 : 0
            border.color: gAppTheme.nodeSelectionBorder
            radius: 4
        }

        // Transient highlight ring — pulses when this unit was navigated to
        // from a Delete Error dialog (or any cross-view navigation that calls
        // gFlowsheet.highlightStream). Auto-clears via FlowsheetState's 3s
        // timer, or immediately on Escape / click-elsewhere on the canvas.
        Rectangle {
            id: highlightRing
            anchors.fill: parent
            anchors.margins: -3
            color: "transparent"
            border.width: 3
            border.color: "#ff9500"   // orange — distinct from selection blue
            radius: 6
            visible: root.highlighted
            opacity: 0

            SequentialAnimation on opacity {
                running: root.highlighted
                loops: Animation.Infinite
                NumberAnimation { from: 0.0; to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.0; to: 0.3; duration: 400; easing.type: Easing.InOutQuad }
            }
        }

        Loader {
            anchors.centerIn: parent
            width: root.droppedIconSize
            height: root.droppedIconSize
            sourceComponent: genericIconComponent

            // Pass the resolved icon path down into the component
            property string resolvedIconPath: {
                if (root.unitType === "stream")
                    return Qt.resolvedUrl(gAppTheme.iconPath("stream_material"))
                if (root.unitType === "column")
                    return Qt.resolvedUrl(gAppTheme.iconPath("dist_column"))
                if (root.unitType === "heater")
                    return Qt.resolvedUrl(gAppTheme.iconPath("heater"))
                if (root.unitType === "cooler")
                    return Qt.resolvedUrl(gAppTheme.iconPath("cooler"))
                if (root.unitType === "heat_exchanger")
                    return Qt.resolvedUrl(gAppTheme.iconPath("heat_exchanger"))
                // Generic fallback: try the unitType as an icon name directly
                return Qt.resolvedUrl(gAppTheme.iconPath(root.unitType))
            }
        }

        Component {
            id: genericIconComponent
            Image {
                width: root.droppedIconSize
                height: root.droppedIconSize
                // The Loader sets resolvedIconPath on itself; we reach it via parent
                source: parent ? parent.resolvedIconPath : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }
    }

    Text {
        id: tagLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.labelPreferredWidth
        height: root.labelAreaHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        wrapMode: Text.NoWrap
        elide: Text.ElideNone
        font.pixelSize: Math.max(9, Math.round(11 * Math.min(root.canvasScale, 1.35)))
        color: gAppTheme.nodeLabelColor
        text: (name && name !== "") ? name : unitId
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false
        cursorShape: (pressed && pressedButtons === Qt.LeftButton) ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real pressOffsetX: 0
        property real pressOffsetY: 0
        property bool dragged: false

        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.rightClicked(root.unitId, root.x + mouse.x, root.y + mouse.y)
                mouse.accepted = true
                return
            }

            pressOffsetX = mouse.x
            pressOffsetY = mouse.y
            dragged = false
            root.clicked(root.unitId)
            mouse.accepted = true
        }

        onReleased: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                mouse.accepted = true
                return
            }

            if (dragged)
                root.moved(root.unitId, root.x, root.y)

            mouse.accepted = true
        }

        onPositionChanged: function(mouse) {
            if (!pressed || pressedButtons !== Qt.LeftButton)
                return
            const dx = mouse.x - pressOffsetX
            const dy = mouse.y - pressOffsetY
            if (!dragged && (Math.abs(dx) > 1 || Math.abs(dy) > 1))
                dragged = true
            root.applyConstrainedPosition(root.x + dx, root.y + dy)
            mouse.accepted = true
        }

        onDoubleClicked: function(mouse) {
            root.doubleClicked(root.unitId)
            mouse.accepted = true
        }
    }
}
