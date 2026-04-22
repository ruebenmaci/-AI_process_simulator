import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

TextField {
    id: field

    property int fontSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
    property color editableTextColor:
        (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7"
    property color readOnlyTextColor: "#1f1f1f"
    property color editableFillColor:
        (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditBg : "#fbfdff"
    property color readOnlyFillColor: "#f0f0f0"
    property color focusColor:
        (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"

    implicitHeight: 22
    font.pixelSize: fontSize
    font.family: "Segoe UI"
    color: (enabled && !readOnly) ? editableTextColor : readOnlyTextColor
    selectionColor: "#c8ddf3"
    selectedTextColor: color
    selectByMouse: true
    padding: 0
    leftPadding: 6
    rightPadding: 6
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    activeFocusOnTab: enabled

    // Tab stop advertisement: PTextField is always a tab destination when
    // enabled. Read-only fields participate too (users can click/select/copy).
    property bool tabStop: enabled

    // Intercept Tab before Qt's built-in focus-chain advancement, so we
    // can skip cells whose tabStop is false (labels and read-only grid
    // values). Same pattern as PGridValue's editable TextField.
    function _moveToNextTabStop(forward) {
        var item = field
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === field) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        field._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        field._moveToNextTabStop(false); event.accepted = true
    }

    // Qt's TextField accepts Right/Left arrows to move the cursor within text.
    // But when there's no text or the cursor is already at the end/start, Qt
    // falls back to its default directional focus navigation, which can cause
    // enclosing scroll containers to shift horizontally (ugly side effect).
    // To guarantee that never happens, we always accept Right/Left here — if
    // Qt had a legitimate cursor move to do, it will have already done it (our
    // Keys.priority is BeforeItem but TextField's internal input filter runs
    // at an even earlier stage for cursor movement). If Qt couldn't move the
    // cursor (end/start of text), we consume the event so Qt's default focus
    // navigation never fires. Up/Down are also consumed to prevent the same
    // side effect.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            var atStart = field.cursorPosition === 0
            var atEnd   = field.cursorPosition === field.length
            var hasSel  = field.selectedText.length > 0
            // If Qt is going to move the cursor normally, let it handle —
            // don't accept yet.
            if (event.key === Qt.Key_Left && (!atStart || hasSel)) return
            if (event.key === Qt.Key_Right && (!atEnd || hasSel)) return
            // Otherwise eat the event so Qt's default directional focus nav
            // doesn't fire.
            event.accepted = true
        }
    }

    background: Item {
        implicitWidth: field.implicitWidth
        implicitHeight: field.implicitHeight

        Rectangle {
            anchors.fill: parent
            color: (field.enabled && !field.readOnly) ? field.editableFillColor : field.readOnlyFillColor
        }

        Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenLo : "#6c7079" }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenLo : "#6c7079" }
        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenHi : "#ffffff" }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellSunkenHi : "#ffffff" }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: field.activeFocus ? field.focusColor : "transparent"
            border.width: field.activeFocus ? 1 : 0
        }
    }

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight: implicitHeight
}
