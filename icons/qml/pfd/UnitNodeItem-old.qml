import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    property real canvasScale: 1.0
    property real iconBaseWidth: unitType === "stream" ? 50 : 100
    property real iconBaseHeight: unitType === "stream" ? 50 : 100
    property real labelAreaHeight: unitType === "stream" ? Math.max(22, Math.round(24 * Math.min(canvasScale, 1.35))) : Math.max(18, Math.round(18 * Math.min(canvasScale, 1.35)))
    property real labelPreferredWidth: unitType === "stream" ? Math.max(width, Math.round(50 * Math.max(6.0, tagLabel.font.pixelSize * 0.62))) : width
    width: Math.max(24, Math.round(iconBaseWidth * canvasScale))
    height: Math.max(24, Math.round(iconBaseHeight * canvasScale) + labelAreaHeight)

    property string unitId: ""
    property string name: ""
    property string unitType: ""
    property bool selected: false
    property bool pendingConnectionSelection: false
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: labelAreaHeight + 4

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: pendingConnectionSelection ? 3 : (selected ? 2 : 0)
            border.color: pendingConnectionSelection ? "#cc7a00" : "#2f6fa3"
            radius: 4
        }

        Loader {
            anchors.fill: parent
            anchors.margins: selected ? 2 : 0
            sourceComponent: root.unitType === "stream" ? streamIconComponent : columnIconComponent
        }

        Component {
            id: columnIconComponent
            Image {
                source: Qt.resolvedUrl("../../icons/svg/Equip_Palette/Distillation_Column.svg")
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        Component {
            id: streamIconComponent
            Image {
                source: Qt.resolvedUrl("../../icons/svg/Equip_Palette/Material_Stream.svg")
                fillMode: Image.PreserveAspectFit
                width: root.unitType === "stream" ? Math.round(40 * root.canvasScale) : Math.round(64 * root.canvasScale)
                height: root.unitType === "stream" ? Math.round(40 * root.canvasScale) : Math.round(64 * root.canvasScale)
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
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pixelSize: Math.max(9, Math.round(11 * Math.min(root.canvasScale, 1.35)))
        lineHeight: 1.0
        lineHeightMode: Text.ProportionalHeight
        color: "#31404a"
        text: (name && name !== "") ? name : unitId
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real pressOffsetX: 0
        property real pressOffsetY: 0
        property bool dragged: false

        onPressed: function(mouse) {
            pressOffsetX = mouse.x
            pressOffsetY = mouse.y
            dragged = false
            root.clicked(root.unitId)
            mouse.accepted = true
        }

        onPositionChanged: function(mouse) {
            if (!pressed)
                return

            const dx = mouse.x - pressOffsetX
            const dy = mouse.y - pressOffsetY

            if (!dragged && (Math.abs(dx) > 1 || Math.abs(dy) > 1))
                dragged = true

            root.applyConstrainedPosition(root.x + dx, root.y + dy)
            mouse.accepted = true
        }

        onReleased: function(mouse) {
            if (dragged)
                root.moved(root.unitId, root.x, root.y)
            mouse.accepted = true
        }

        onDoubleClicked: function(mouse) {
            root.doubleClicked(root.unitId)
            mouse.accepted = true
        }
    }
}
