import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ComboBox {
    id: combo

    // Tab-chain integration with the cell-navigation system. PComboBox is a
    // valid Tab destination when enabled (just like PTextField). Tab/Backtab
    // are intercepted before Qt's default focus-chain advancement so we can
    // skip labels and read-only cells (which set tabStop: false).
    property bool tabStop: enabled

    function _moveToNextTabStop(forward) {
        var item = combo
        for (var safety = 0; safety < 200; ++safety) {
            item = item.nextItemInFocusChain(forward)
            if (!item || item === combo) return
            if (item.tabStop === undefined || item.tabStop === true) {
                item.forceActiveFocus()
                return
            }
        }
    }

    Keys.priority: Keys.BeforeItem

    Keys.onTabPressed: function(event) {
        combo._moveToNextTabStop(true); event.accepted = true
    }
    Keys.onBacktabPressed: function(event) {
        combo._moveToNextTabStop(false); event.accepted = true
    }

    // Debounce flag: true for a brief window after we open the popup in
    // response to a key press. Qt Controls 2 ComboBox has an internal
    // key handler that toggles the popup on Enter/Space release (baked in
    // at the C++ level, not reachable via Keys.priority). Without this flag,
    // pressing Enter would open then immediately close — our handler runs
    // on press, Qt's runs on release. We suppress our toggle-on-press path
    // if it would re-fire within the debounce window.
    property bool _justOpened: false
    Timer {
        id: _justOpenedTimer
        interval: 220   // long enough to cover press+release round-trip
        repeat: false
        onTriggered: combo._justOpened = false
    }

    // Also swallow the release event that Qt's internal handler would
    // otherwise act on. This is the critical piece — the key-release is
    // what triggers Qt's toggle, so consuming it here prevents the close.
    Keys.onReleased: function(event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) && combo._justOpened) {
            event.accepted = true
        }
    }

    // Keyboard behaviour:
    //   • Popup closed:
    //       - Enter/Return/Space opens the popup (same as mouse click).
    //       - Arrow keys advance focus along the tabstop chain.
    //   • Popup open:
    //       - Leave all keys to Qt's default handling. Qt Controls 2 handles
    //         Up/Down to highlight items, Enter/Space to select and close,
    //         and Escape to cancel.
    //
    // Left/Right/Up/Down are explicitly consumed when the popup is closed
    // so Qt's default directional focus navigation doesn't fire (which
    // could otherwise shift enclosing scroll containers horizontally).
    Keys.onPressed: function(event) {
        if (combo.popup.opened) return   // hands off — Qt handles everything
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            combo.popup.open()
            combo._justOpened = true
            _justOpenedTimer.restart()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            combo._moveToNextTabStop(true); event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            combo._moveToNextTabStop(false); event.accepted = true
        }
    }

    property int    fontSize:            (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
    property int    arrowWidth:          22
    property int    minimumContentWidth: 80
    property color  valueColor:
        combo.enabled
            ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7")
            : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcText : "#1f2a34")
    property color  accentColor:
        (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellFocusBorder : "#1c4ea7"
    property string widthMode:           "content"

    implicitHeight: 22
    font.pixelSize: fontSize
    font.family: "Segoe UI"
    padding: 0
    topPadding: 0
    bottomPadding: 0
    leftPadding: 4
    rightPadding: arrowWidth

    property int _longestPx: 0
    TextMetrics {
        id: _tm
        font.pixelSize: combo.fontSize
        font.family: "Segoe UI"
    }
    function _remeasure() {
        if (!model) { _longestPx = 0; return }
        var n = (typeof model.length === "number") ? model.length
              : (typeof model.count === "number")  ? model.count
              : 0
        var maxPx = 0
        for (var i = 0; i < n; i++) {
            var entry = (typeof model.get === "function") ? model.get(i) : model[i]
            var s = (typeof entry === "string") ? entry
                  : (entry && entry.text) ? entry.text
                  : (entry && entry.display) ? entry.display
                  : String(entry)
            _tm.text = s
            if (_tm.advanceWidth > maxPx) maxPx = _tm.advanceWidth
        }
        _longestPx = Math.ceil(maxPx) + 2
    }
    Component.onCompleted: _remeasure()
    onModelChanged: _remeasure()
    onFontSizeChanged: { _tm.font.pixelSize = fontSize; _remeasure() }

    readonly property int _contentWidth:
        Math.max(_longestPx, minimumContentWidth)

    implicitWidth:          _contentWidth + leftPadding + rightPadding
    Layout.minimumWidth:    _contentWidth + leftPadding + rightPadding
    Layout.preferredWidth:  _contentWidth + leftPadding + rightPadding
    Layout.fillWidth:       widthMode === "fill"
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight:   implicitHeight

    background: Item {
        implicitWidth:  combo.implicitWidth
        implicitHeight: combo.implicitHeight

        Rectangle {
            anchors.fill: parent
            color: combo.enabled
                   ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonBg : "#d8dade")
                   : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvPageBg : "#ebedf0")
        }

        Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }

        Rectangle {
            x: combo.arrowWidth
            y: 2
            width: 1
            height: parent.height - 4
            visible: false
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079"
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: combo.activeFocus ? combo.accentColor : "transparent"
            border.width: combo.activeFocus ? 1 : 0
        }
    }

    // The ComboBox itself already insets the content area via its own
    // leftPadding (4) and rightPadding (arrowWidth, default 22). The
    // contentItem Text fills that pre-insetted area, so it must NOT add its
    // own leftPadding / rightPadding — doing so would shrink the visible
    // text region by an extra 4 + 22 = 26 px, eliding text away entirely
    // in narrow cells. (The legacy CCombo control had this same single-
    // pass padding; PComboBox originally set padding on both layers and
    // silently elided "L" / "feedPct" to nothing in any column under
    // ~70 px wide.)
    contentItem: Text {
        text: combo.displayText
        font: combo.font
        color: combo.valueColor
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }

    indicator: Item {
        x: combo.width - combo.arrowWidth
        y: 0
        width: combo.arrowWidth
        height: combo.height

        Text {
            anchors.centerIn: parent
            text: "▾"
            font.pixelSize: combo.fontSize
            color: combo.enabled
                   ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#1f2a34")
                   : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvButtonDisabled : "#8a96a1")
        }
    }

    popup: Popup {
        y: combo.height
        width: combo.width
        implicitHeight: contentItem.implicitHeight
        padding: 0
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrame : "#d8dade"
            Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
            Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
        }

        contentItem: ListView {
            clip: true
            model: combo.popup.visible ? combo.delegateModel : null
            implicitHeight: contentHeight
            currentIndex: combo.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }

    delegate: ItemDelegate {
        width: combo.popup ? combo.popup.width : combo.width
        height: 22
        padding: 0
        leftPadding: 4
        rightPadding: 4
        font.pixelSize: combo.fontSize
        font.family: "Segoe UI"
        highlighted: combo.highlightedIndex === index

        // Same single-padding rule as the main contentItem above: the
        // ItemDelegate's leftPadding/rightPadding (4 px each) already inset
        // the content area, so the inner Text must not re-apply them.
        contentItem: Text {
            text: {
                if (typeof modelData === "string") return modelData
                if (modelData && modelData.text)    return modelData.text
                if (modelData && modelData.display) return modelData.display
                return String(modelData)
            }
            font.pixelSize: combo.fontSize
            font.family: "Segoe UI"
            font.bold: index === combo.currentIndex
            color: combo.enabled
                   ? ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7")
                   : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcText : "#1f2a34")
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: highlighted                  ? "#e3edf5"
                 : index === combo.currentIndex ? "#dde9f3"
                                                : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcBg : "white")
        }
    }
}
