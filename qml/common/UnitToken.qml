import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  UnitToken.qml  —  RESTYLED
//
//  A clickable unit token. Looks like a raised button (chiseled-raised
//  bevel, panel-grey fill) to distinguish it from the data cells next to it.
//  Opens UnitPicker when clicked.
//
//  Visual treatment:
//    Normal  : panel-grey fill + chiseled-RAISED bevel (looks like a button)
//    Hover   : slight highlight fill, same bevel
//    Pressed / picker-open : inverted bevel (sunken), slightly darker fill
//    Override: amber-tinged fill signals a unit override active
//
//  Dimensionless: shows "—" (no arrow, no clickable behavior, no bevel)
// ─────────────────────────────────────────────────────────────────────────────

FocusScope {
    id: token

    activeFocusOnTab: false

    property string quantity:    ""
    property real   siValue:     NaN
    property string displayUnit: ""
    property int    decimals:    -1

    property int _unitRev: 0
    Connections {
        target: typeof gUnits !== "undefined" ? gUnits : null
        ignoreUnknownSignals: true
        function onUnitsChanged()         { token._unitRev = token._unitRev + 1 }
        function onActiveUnitSetChanged() { token._unitRev = token._unitRev + 1 }
    }

    readonly property string effectiveUnit: {
        var _r = _unitRev
        if (displayUnit !== "") return displayUnit
        return (typeof gUnits !== "undefined") ? gUnits.defaultUnit(quantity) : ""
    }

    readonly property bool dimensionless: quantity === "Dimensionless" || quantity === ""
    readonly property bool overridden: {
        var _r = _unitRev
        if (dimensionless) return false
        if (displayUnit === "") return false
        if (typeof gUnits === "undefined") return false
        return displayUnit !== gUnits.defaultUnit(quantity)
    }
    readonly property bool pressed: mouse.pressed || picker.opened

    signal unitChosen(string unit)

    function openPicker() {
        if (dimensionless) return
        if (Qt.__openUnitPicker && Qt.__openUnitPicker !== picker)
            Qt.__openUnitPicker.close()
        Qt.__openUnitPicker = picker
        picker.open()
    }

    function closePicker() {
        if (Qt.__openUnitPicker === picker)
            Qt.__openUnitPicker = null
        picker.close()
    }

    function pickerOpened() { return picker.opened }

    // ── Background fill ─────────────────────────────────────────────────────
    Rectangle {
        id: bg
        anchors.fill: parent
        visible: !token.dimensionless
        color: token.overridden
               ? "#fff8e8"
               : (token.pressed
                  ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonPressed : "#c2c5cb")
                  : (mouse.containsMouse
                     ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonHover : "#e2e4e8")
                     : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitBg : "#d8dade")))
        z: 0
    }

    // ── Chiseled border (raised, or inverted-sunken when pressed) ───────────
    // Not shown for dimensionless ("—") tokens.
    Rectangle {   // top
        visible: !token.dimensionless
        x: 0; y: 0; width: parent.width; height: 1
        color: token.pressed
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079")
               : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff")
        z: 1
    }
    Rectangle {   // left
        visible: !token.dimensionless
        x: 0; y: 0; width: 1; height: parent.height
        color: token.pressed
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079")
               : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff")
        z: 1
    }
    Rectangle {   // right
        visible: !token.dimensionless
        x: parent.width - 1; y: 0; width: 1; height: parent.height
        color: token.pressed
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff")
               : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079")
        z: 1
    }
    Rectangle {   // bottom
        visible: !token.dimensionless
        x: 0; y: parent.height - 1; width: parent.width; height: 1
        color: token.pressed
               ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff")
               : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079")
        z: 1
    }

    // ── Focus ring ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: token.activeFocus
                      ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7")
                      : "transparent"
        border.width: token.activeFocus ? 1 : 0
        z: 2
    }

    // ── Unit label + arrow ──────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        clip: true
        z: 3

        Text {
            id: arrow
            visible: !token.dimensionless
            text: "▾"
            font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitText : "#2b5d8a"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: unitLabel
            text: token.dimensionless ? "—" : token.effectiveUnit
            font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
            font.family: "Segoe UI"
            color: token.dimensionless
                   ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#526571")
                   : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitText : "#2b5d8a")
            anchors.right: arrow.visible ? arrow.left : parent.right
            anchors.rightMargin: arrow.visible ? 3 : 0
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideLeft
        }

        Text {
            visible: token.overridden
            text: "●"
            font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
            color: "#a05a00"
            anchors.right: unitLabel.left
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !token.dimensionless
        cursorShape: token.dimensionless ? Qt.ArrowCursor : Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            token.forceActiveFocus()
            if (picker.opened) token.closePicker()
            else               token.openPicker()
        }
    }

    Keys.onPressed: function(event) {
        if (token.dimensionless) return
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (picker.opened) token.closePicker()
            else               token.openPicker()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && picker.opened) {
            token.closePicker()
            event.accepted = true
        }
    }

    UnitPicker {
        id: picker
        quantity:    token.quantity
        siValue:     token.siValue
        currentUnit: token.effectiveUnit
        decimals:    token.decimals
        x: token.width - width
        y: token.height
        onUnitChosen: function(u) {
            token.unitChosen(u)
            token.closePicker()
        }
        onClosed: {
            if (Qt.__openUnitPicker === picker)
                Qt.__openUnitPicker = null
        }
    }
}
