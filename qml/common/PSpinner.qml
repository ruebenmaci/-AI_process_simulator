import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PSpinner.qml  —  HYSYS-style numeric spinner
//
//  A compact integer-first numeric input cell with stacked up/down chevrons on
//  the right edge. Visual treatment matches PGridValue (editable mode) and
//  PTextField:
//
//    • pale-blue editable fill (gAppTheme.pvCellEditBg)
//    • chiseled-SUNKEN 1px bevel (gAppTheme.pvCellSunkenLo / pvCellSunkenHi)
//    • blue editable text (gAppTheme.pvCellEditText)
//    • accent-blue 1px focus ring drawn on top of the bevel
//    • chevron column carries a raised PButton-style bevel so the buttons
//      visibly "press in" when clicked (matches HYSYS draw-spec spinners)
//
//  Behaviour:
//    • value is bound through a `value` property; emits valueChanged + edited(v)
//    • integer mode by default (decimals = 0). Set decimals > 0 for float.
//    • Up/Down arrow keys when focused step by stepSize. PageUp/PageDown step
//      by stepSize * 10. Home/End jump to from/to.
//    • mouse wheel over the cell steps the value (HYSYS behaviour).
//    • click-and-hold on a chevron auto-repeats after 350 ms at 60 ms cadence.
//    • Tab/Backtab integrate with the cell-navigation tabStop chain (same
//      pattern as PGridValue / PTextField / PComboBox).
//
//  AOT-safe: no for...of, no arrow functions, no `const`, no fractional
//  font.pixelSize, no shadowed FINAL properties.
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: spin

    // ── Public API ──────────────────────────────────────────────────────────
    property real    value:    0
    property real    from:     0
    property real    to:       9999
    property real    stepSize: 1
    property int     decimals: 0          // 0 = integer; >0 = float
    property bool    editable: true       // false → read-only, no chevrons
    property string  alignText: "right"   // "left" | "right" | "center"
    property int     chevronWidth: 18

    signal edited(real value)             // fires after a committed change

    // ── Tab-chain integration (matches PGridValue / PTextField) ─────────────
    property bool tabStop: editable
    activeFocusOnTab: editable

    function _moveToNextTabStop(forward) {
        var item = spin
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === spin) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    // ── Layout contract ─────────────────────────────────────────────────────
    // Content-sized by default. 78 px preferred (room for ~6 digits + chevrons),
    // 60 px minimum (chevron column 18 + ~30 px text + padding). Panels that
    // want a spinner to fill a row's value cell can override Layout.fillWidth
    // at the use site.
    Layout.preferredHeight: 22
    Layout.minimumHeight:   22
    Layout.preferredWidth:  78
    Layout.minimumWidth:    60
    Layout.fillWidth:       false

    implicitWidth:  78
    implicitHeight: 22

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _clamp(v) {
        if (v < from) return from
        if (v > to)   return to
        return v
    }

    function _format(v) {
        if (decimals <= 0) return String(Math.round(v))
        return Number(v).toFixed(decimals)
    }

    function _commitFromText(s) {
        var n = parseFloat(s)
        if (isNaN(n)) {
            valueInput.text = _format(spin.value)
            return
        }
        var clamped = _clamp(n)
        if (clamped !== spin.value) {
            spin.value = clamped
            spin.edited(clamped)
        } else {
            // Re-render in case user typed "5.0" when value is already 5
            valueInput.text = _format(clamped)
        }
    }

    function step(delta) {
        if (!editable) return
        var n = _clamp(spin.value + delta)
        if (n !== spin.value) {
            spin.value = n
            spin.edited(n)
        }
    }

    function stepUp()   { step(stepSize) }
    function stepDown() { step(-stepSize) }

    // ── Background fill ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: spin.editable
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditBg : "#fbfdff")
               : "#f0f0f0"
        z: 0
    }

    // ── Sunken bevel (top + left dark, right + bottom light) ────────────────
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

    // ── Focus ring (drawn on top of bevel) ──────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: (valueInput.activeFocus || spin.activeFocus)
                      ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7")
                      : "transparent"
        border.width: (valueInput.activeFocus || spin.activeFocus) ? 1 : 0
        z: 4
    }

    // ── Editable numeric input ──────────────────────────────────────────────
    TextField {
        id: valueInput
        visible: spin.editable
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: chevronColumn.left
        anchors.leftMargin: 4
        anchors.rightMargin: 2
        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
        font.family: "Segoe UI"
        horizontalAlignment: spin.alignText === "left"   ? Text.AlignLeft
                            : spin.alignText === "center" ? Text.AlignHCenter
                                                           : Text.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7"
        selectByMouse: true
        selectionColor: "#c8ddf3"
        selectedTextColor: color
        padding: 0; topPadding: 0; bottomPadding: 0
        background: Item {}
        activeFocusOnTab: true
        z: 3

        // Restrict input to digits (and optionally decimal point/sign)
        validator: spin.decimals > 0
                   ? doubleValidator
                   : intValidator
        IntValidator    { id: intValidator;    bottom: -2147483647; top: 2147483647 }
        DoubleValidator { id: doubleValidator
            bottom: -1e12
            top:    1e12
            decimals: spin.decimals
            notation: DoubleValidator.StandardNotation
            locale: "C"
        }

        Component.onCompleted: text = spin._format(spin.value)

        // Re-format when external value changes and we're not editing
        Connections {
            target: spin
            function onValueChanged() {
                if (!valueInput.activeFocus)
                    valueInput.text = spin._format(spin.value)
            }
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                text = spin._format(spin.value)
                selectAll()
            } else {
                spin._commitFromText(text)
                text = spin._format(spin.value)
            }
        }

        onEditingFinished: {
            spin._commitFromText(text)
            if (!activeFocus) text = spin._format(spin.value)
        }

        // Single-click → focus + select-all (matches PGridValue behaviour)
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

        Keys.priority: Keys.BeforeItem

        Keys.onTabPressed: function(event) {
            spin._commitFromText(text)
            spin._moveToNextTabStop(true)
            event.accepted = true
        }
        Keys.onBacktabPressed: function(event) {
            spin._commitFromText(text)
            spin._moveToNextTabStop(false)
            event.accepted = true
        }
        Keys.onReturnPressed: function(event) {
            spin._commitFromText(text)
            focus = false
            spin.forceActiveFocus()
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            spin._commitFromText(text)
            focus = false
            spin.forceActiveFocus()
            event.accepted = true
        }
        Keys.onEscapePressed: function(event) {
            text = spin._format(spin.value)
            focus = false
            event.accepted = true
        }
        Keys.onUpPressed: function(event) {
            spin._commitFromText(text)
            spin.stepUp()
            text = spin._format(spin.value)
            event.accepted = true
        }
        Keys.onDownPressed: function(event) {
            spin._commitFromText(text)
            spin.stepDown()
            text = spin._format(spin.value)
            event.accepted = true
        }
    }

    // ── Read-only display (when editable === false) ─────────────────────────
    Text {
        visible: !spin.editable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: spin.alignText === "left"   ? Text.AlignLeft
                            : spin.alignText === "center" ? Text.AlignHCenter
                                                           : Text.AlignRight
        text: spin._format(spin.value)
        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
        font.family: "Segoe UI"
        color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcText : "#1f2a34"
        elide: Text.ElideRight
        z: 3
    }

    // ── Mouse wheel: step value when hovering the cell ──────────────────────
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        enabled: spin.editable
        z: 5
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0)      spin.stepUp()
            else if (wheel.angleDelta.y < 0) spin.stepDown()
            wheel.accepted = true
        }
    }

    // ── Chevron column (up + down stacked, raised PButton bevel) ────────────
    Item {
        id: chevronColumn
        visible: spin.editable
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 1
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        width: spin.chevronWidth
        z: 5

        // Up chevron
        Rectangle {
            id: upBtn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.floor(parent.height / 2)
            color: upArea.pressed
                   ? "#c8d0d8"
                   : (upArea.containsMouse ? "#dbe0e5"
                                           : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonBg : "#d8dade"))
            // Raised bevel
            Rectangle { x: 0; y: 0; width: parent.width; height: 1
                color: upArea.pressed ? "#7f8a95" : "#f7f9fb" }
            Rectangle { x: 0; y: 0; width: 1; height: parent.height
                color: upArea.pressed ? "#7f8a95" : "#f7f9fb" }
            Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height
                color: upArea.pressed ? "#f7f9fb" : "#7f8a95" }
            Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1
                color: upArea.pressed ? "#f7f9fb" : "#7f8a95" }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: upArea.pressed ? 1 : 0
                text: "▲"
                font.pixelSize: 7
                font.family: "Segoe UI"
                color: spin.value >= spin.to
                       ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonDisabled : "#8a96a1")
                       : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#1f2a34")
            }

            MouseArea {
                id: upArea
                anchors.fill: parent
                hoverEnabled: true
                onPressed: {
                    spin.stepUp()
                    repeatTimerUp.restart()
                }
                onReleased: { repeatTimerUp.stop(); fastTimerUp.stop() }
                onCanceled: { repeatTimerUp.stop(); fastTimerUp.stop() }
            }
            Timer {
                id: repeatTimerUp
                interval: 350; repeat: false
                onTriggered: fastTimerUp.start()
            }
            Timer {
                id: fastTimerUp
                interval: 60; repeat: true
                onTriggered: spin.stepUp()
            }
        }

        // Down chevron
        Rectangle {
            id: dnBtn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height - upBtn.height
            color: dnArea.pressed
                   ? "#c8d0d8"
                   : (dnArea.containsMouse ? "#dbe0e5"
                                           : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonBg : "#d8dade"))
            // Raised bevel
            Rectangle { x: 0; y: 0; width: parent.width; height: 1
                color: dnArea.pressed ? "#7f8a95" : "#f7f9fb" }
            Rectangle { x: 0; y: 0; width: 1; height: parent.height
                color: dnArea.pressed ? "#7f8a95" : "#f7f9fb" }
            Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height
                color: dnArea.pressed ? "#f7f9fb" : "#7f8a95" }
            Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1
                color: dnArea.pressed ? "#f7f9fb" : "#7f8a95" }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: dnArea.pressed ? 1 : 0
                text: "▼"
                font.pixelSize: 7
                font.family: "Segoe UI"
                color: spin.value <= spin.from
                       ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonDisabled : "#8a96a1")
                       : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#1f2a34")
            }

            MouseArea {
                id: dnArea
                anchors.fill: parent
                hoverEnabled: true
                onPressed: {
                    spin.stepDown()
                    repeatTimerDn.restart()
                }
                onReleased: { repeatTimerDn.stop(); fastTimerDn.stop() }
                onCanceled: { repeatTimerDn.stop(); fastTimerDn.stop() }
            }
            Timer {
                id: repeatTimerDn
                interval: 350; repeat: false
                onTriggered: fastTimerDn.start()
            }
            Timer {
                id: fastTimerDn
                interval: 60; repeat: true
                onTriggered: spin.stepDown()
            }
        }
    }

    // ── Cell-level keys (when the spinner has focus but the field doesn't) ──
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (valueInput.activeFocus) return
        if (event.key === Qt.Key_Up)       { spin.stepUp();    event.accepted = true }
        else if (event.key === Qt.Key_Down){ spin.stepDown();  event.accepted = true }
        else if (event.key === Qt.Key_PageUp)   { spin.step(spin.stepSize * 10);  event.accepted = true }
        else if (event.key === Qt.Key_PageDown) { spin.step(-spin.stepSize * 10); event.accepted = true }
        else if (event.key === Qt.Key_Home)     { spin.value = spin.from; spin.edited(spin.value); event.accepted = true }
        else if (event.key === Qt.Key_End)      { spin.value = spin.to;   spin.edited(spin.value); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                 || event.key === Qt.Key_Space) {
            valueInput.forceActiveFocus()
            valueInput.selectAll()
            event.accepted = true
        }
    }
    Keys.onTabPressed: function(event) {
        if (valueInput.activeFocus) return
        spin._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        if (valueInput.activeFocus) return
        spin._moveToNextTabStop(false); event.accepted = true
    }
}
