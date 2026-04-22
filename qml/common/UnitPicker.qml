import QtQuick 2.15
import QtQuick.Controls 2.15

// ─────────────────────────────────────────────────────────────────────────────
//  UnitPicker.qml  —  RESTYLED
//
//  Popup listing all units compatible with `quantity`, with a live preview
//  of `siValue` formatted in each unit.
//
//  Visual treatment:
//    Popup chrome : panel-grey frame + sunken page-area 1px bevel
//    Header       : chiseled-raised title strip with quantity name
//    Rows         : alt-row stripe, hover highlight, ✓ check on current unit
//    Footer       : "Set as default" + "Reset" links on a thin strip
// ─────────────────────────────────────────────────────────────────────────────

Popup {
    id: picker

    property string quantity:    ""
    property real   siValue:     NaN
    property string currentUnit: ""
    property int    decimals:    -1

    signal unitChosen(string unit)

    width: 220
    height: contentColumn.implicitHeight + 4
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    // ── Outer frame (raised) + inner sunken page chrome ─────────────────────
    background: Item {
        anchors.fill: parent

        // Outer raised frame
        Rectangle {
            anchors.fill: parent
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrame : "#d8dade"
            Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#5a5e66" }
            Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#5a5e66" }
        }
    }

    onAboutToShow: optionsRepeater.model = (typeof gUnits !== "undefined")
                                            ? gUnits.unitOptionsFor(quantity, siValue, decimals)
                                            : []

    contentItem: Column {
        id: contentColumn
        width: parent.width
        spacing: 0

        // Header — chiseled-raised strip with quantity name
        Rectangle {
            width: parent.width
            height: 22
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvTitleBg : "#c2c5cb"
            // Raised bevel (highlight top+left, shadow bottom+right)
            Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameHi : "#ffffff" }
            Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }
            Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Text {
                    text: picker.quantity
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    font.family: "Segoe UI"
                    font.bold: true
                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvTitleText : "#1f2226"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 4; height: 1 }
                Text {
                    text: "SI: " + (isFinite(picker.siValue) ? picker.siValue.toExponential(3) : "—")
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#526571"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Options list
        Repeater {
            id: optionsRepeater
            model: []
            delegate: Rectangle {
                width: parent.width
                height: 22
                color: optionMouse.containsMouse
                       ? "#e3edf5"
                       : (modelData.unit === picker.currentUnit
                          ? "#dde9f3"
                          : ((typeof gAppTheme !== "undefined") ? gAppTheme.pvCellCalcBg : "#ffffff"))

                Text {
                    id: checkMark
                    visible: modelData.unit === picker.currentUnit
                    text: "✓"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    font.bold: true
                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditText : "#1c4ea7"
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    text: modelData.unit
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    font.family: "Segoe UI"
                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvLabelText : "#1f2a34"
                    font.bold: modelData.unit === picker.currentUnit
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.right: previewText.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                }

                Text {
                    id: previewText
                    text: modelData.preview
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    font.family: "Segoe UI"
                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitText : "#526571"
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                }

                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.unitChosen(modelData.unit)
                }
            }
        }

        // Footer — chiseled-sunken strip with action links
        Rectangle {
            width: parent.width
            height: 22
            color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvPageBg : "#ebedf0"
            // Sunken bevel (shadow top+left, highlight bottom+right)
            Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFrameLo : "#6c7079" }

            Text {
                id: resetLink
                text: "Reset"
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                font.family: "Segoe UI"
                color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitText : "#2b5d8a"
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.unitChosen("")
                }
            }

            Text {
                text: "Set as default for " + picker.quantity
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                font.family: "Segoe UI"
                color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvUnitText : "#2b5d8a"
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: resetLink.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        console.log("Set default for", picker.quantity, "→", picker.currentUnit)
                    }
                }
            }
        }
    }
}
