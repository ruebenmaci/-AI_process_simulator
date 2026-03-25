import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property var streamObject: null
    property var unitObject: null

    readonly property color chrome: "#d2d9e6"
    readonly property color panelInset: "#f4f6fa"
    readonly property color border: "#2a2a2a"
    readonly property color activeBlue: "#2e76db"
    readonly property color textDark: "#1f2430"
    readonly property color mutedText: "#5a6472"
    readonly property color rowAlt: "#eef2f8"
    readonly property color warnBg: "#fff4db"
    readonly property color warnBorder: "#d19a1c"
    readonly property color infoBg: "#eef4ff"
    readonly property color infoBorder: "#8aa9d6"

    readonly property bool isProductStream: !!root.streamObject && root.streamObject.productStream
    readonly property bool canEditStream: !!root.streamObject && !root.isProductStream
    readonly property bool canEditCrude: root.canEditStream && !!root.streamObject && root.streamObject.isCrudeFeed

    readonly property int colComponentW: 100
    readonly property int colFractionW: 80
    readonly property int colTbW: 81
    readonly property int colMwW: 81
    readonly property int colTcW: 81
    readonly property int colPcW: 81
    readonly property int colOmegaW: 81
    readonly property int colSgW: 81
    readonly property int colDeltaW: 81
    readonly property int tableSideMargins: 8
    readonly property int tableSpacing: 8
    readonly property int tableContentWidth: tableSideMargins * 2
                                           + colComponentW + colFractionW + colTbW + colMwW + colTcW + colPcW + colOmegaW + colSgW + colDeltaW
                                           + tableSpacing * 8



    property string compositionBasis: "Mass fraction"
    property bool showNonzeroOnly: false
    property string componentFilterText: ""

    function fmt6(v) { return Number(v || 0).toFixed(6) }
    function rowMatchesFilter(componentNameValue, fractionValue) {
        var matchesText = componentFilterText.trim().length === 0
                          || String(componentNameValue).toLowerCase().indexOf(componentFilterText.trim().toLowerCase()) !== -1
        var passesNonzero = !showNonzeroOnly || Number(fractionValue) > 0.0
        return matchesText && passesNonzero
    }
    function fractionHeaderText() {
        return compositionBasis === "Mole fraction" ? "Mole Fraction" : "Mass Fraction"
    }
    function fractionDisplayValue(fractionValue, moleFractionValue) {
        return compositionBasis === "Mole fraction" ? Number(moleFractionValue) : Number(fractionValue)
    }
    function fractionEditable() {
        return compositionBasis === "Mass fraction"
    }

    Rectangle {
        anchors.fill: parent
        color: root.panelInset
        border.color: root.border
        border.width: 1
        radius: 8

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    id: componentPropsLabel
                    text: "Component Properties"
                    color: root.textDark
                    font.bold: true
                    font.pixelSize: 12
                }

                Item {
                    Layout.minimumWidth: 30
                    Layout.fillWidth: true
                }

                Label {
                    id: massSumLabel
                    text: root.streamObject ? ("Mass fraction sum: " + fmt6(root.streamObject.massFractionSum)) : ""
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }

                Button {
                    id: normalizeButton
                    text: "Normalize Fractions"
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditCrude
                    Layout.preferredWidth: Math.max(implicitWidth + 20, 150)
                    Layout.minimumWidth: Math.max(implicitWidth + 20, 150)
                    Layout.alignment: Qt.AlignRight
                    onClicked: if (root.streamObject) root.streamObject.normalizeComposition()
                }

                Button {
                    id: resetCompositionButton
                    text: "Reset Composition"
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditCrude
                    onClicked: if (root.streamObject) root.streamObject.resetCompositionToFluidDefault()
                }

                Button {
                    id: resetPropertiesButton
                    text: "Reset Properties"
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditCrude
                    onClicked: if (root.streamObject) root.streamObject.resetComponentPropertiesToFluidDefault()
                }

                Button {
                    id: clearEditsButton
                    text: "Clear Custom Edits"
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditCrude && root.streamObject.hasCustomComposition
                    onClicked: if (root.streamObject) root.streamObject.clearCustomCompositionEdits()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 6
                color: root.isProductStream ? "#ececec" : root.infoBg
                border.color: root.isProductStream ? "#c8c8c8" : root.infoBorder
                border.width: 1
                implicitHeight: statusBannerLabel.implicitHeight + 12

                Label {
                    id: statusBannerLabel
                    anchors.fill: parent
                    anchors.margins: 6
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.streamObject ? root.streamObject.compositionEditStatusLabel : ""
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Label {
                Layout.fillWidth: true
                visible: !!root.streamObject
                text: root.streamObject ? root.streamObject.compositionSourceLabel : ""
                color: root.mutedText
                font.pixelSize: 11
                font.italic: true
            }
            Rectangle {
                Layout.fillWidth: true
                visible: !!root.streamObject && !root.isProductStream && root.streamObject.isCrudeFeed && !root.streamObject.massFractionsBalanced
                color: root.warnBg
                border.color: root.warnBorder
                border.width: 1
                radius: 6
                implicitHeight: warningLabel.implicitHeight + 12

                Label {
                    id: warningLabel
                    anchors.fill: parent
                    anchors.margins: 6
                    wrapMode: Text.WordWrap
                    text: "Warning: mass fractions do not currently sum to 1.0."
                    color: "#744f00"
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: "View basis"
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                }

                ComboBox {
                    id: basisCombo
                    Layout.preferredWidth: 150
                    model: ["Mass fraction", "Mole fraction"]
                    currentIndex: root.compositionBasis === "Mole fraction" ? 1 : 0
                    onActivated: root.compositionBasis = currentText
                }

                CheckBox {
                    id: nonzeroOnlyCheck
                    text: "Show nonzero only"
                    checked: root.showNonzeroOnly
                    onToggled: root.showNonzeroOnly = checked
                }

                Item { Layout.fillWidth: false }

                Label {
                    text: "Filter"
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                }

                TextField {
                    id: filterField
                    Layout.preferredWidth: 180
                    Layout.minimumWidth: 140
                    placeholderText: "Component name"
                    text: root.componentFilterText
                    onTextChanged: root.componentFilterText = text
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.compositionBasis === "Mole fraction"
                color: "#f2f4f7"
                border.color: "#c3cad6"
                border.width: 1
                radius: 6
                implicitHeight: moleInfoLabel.implicitHeight + 12

                Label {
                    id: moleInfoLabel
                    anchors.fill: parent
                    anchors.margins: 6
                    text: "Mole fraction view is read-only. Switch back to Mass fraction to edit composition values."
                    wrapMode: Text.WordWrap
                    color: root.mutedText
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: root.panelInset
                border.color: root.border
                border.width: 1

                Rectangle {
                    id: tableClipFrame
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 6
                    color: root.panelInset
                    clip: true
                    visible: !!root.streamObject

                    Flickable {
                        id: tableFlick
                        anchors.fill: parent
                        anchors.margins: 2
                        clip: true
                        contentWidth: Math.max(root.tableContentWidth, width)
                        contentHeight: height
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentWidth > width
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                        Column {
                            width: Math.max(root.tableContentWidth, tableFlick.width)
                            spacing: 1

                            Rectangle {
                                width: parent.width
                                height: 28
                                radius: 6
                                color: root.chrome
                                border.color: root.border
                                border.width: 1

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.tableSideMargins
                                    anchors.rightMargin: root.tableSideMargins
                                    spacing: root.tableSpacing

                                    Label { text: "Component"; color: root.textDark; font.bold: true; width: root.colComponentW; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: root.fractionHeaderText(); color: root.textDark; font.bold: true; width: root.colFractionW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Tb (K)"; color: root.textDark; font.bold: true; width: root.colTbW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "MW"; color: root.textDark; font.bold: true; width: root.colMwW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Tc (K)"; color: root.textDark; font.bold: true; width: root.colTcW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Pc"; color: root.textDark; font.bold: true; width: root.colPcW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "omega"; color: root.textDark; font.bold: true; width: root.colOmegaW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "SG"; color: root.textDark; font.bold: true; width: root.colSgW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "delta"; color: root.textDark; font.bold: true; width: root.colDeltaW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                }
                            }

                            ListView {
                                id: listView
                                width: tableFlick.contentWidth
                                height: tableFlick.height - 29
                                clip: true
                                model: root.streamObject ? root.streamObject.compositionModel : null
                                spacing: 1
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Rectangle {
                                    width: listView.width
                                    readonly property bool rowVisible: root.rowMatchesFilter(componentName, fraction)
                                    height: rowVisible ? 32 : 0
                                    visible: rowVisible
                                    color: index % 2 === 0 ? root.rowAlt : root.panelInset

                                    function fieldBg(field) {
                                        return field.activeFocus ? root.activeBlue : "#9eacbf"
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.tableSideMargins
                                        anchors.rightMargin: root.tableSideMargins
                                        spacing: root.tableSpacing

                                        Label {
                                            text: componentName
                                            color: root.textDark
                                            font.pixelSize: 11
                                            width: root.colComponentW
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            height: parent.height
                                        }

                                        TextField {
                                            id: fracField
                                            text: root.fractionDisplayValue(fraction, moleFraction).toFixed(6)
                                            enabled: true
                                            readOnly: !editable || !root.fractionEditable()
                                            width: root.colFractionW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(fracField); border.width: 1 }
                                            onEditingFinished: { if (editable && root.fractionEditable() && root.streamObject && root.streamObject.compositionModel) { root.streamObject.compositionModel.setFraction(index, Number(text)) } else { text = root.fractionDisplayValue(fraction, moleFraction).toFixed(6) } }
                                        }
                                        TextField {
                                            id: tbField
                                            text: Number(boilingPointK).toFixed(1)
                                            enabled: editable
                                            width: root.colTbW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(tbField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Tb", Number(text))
                                        }
                                        TextField {
                                            id: mwField
                                            text: Number(molecularWeight).toFixed(2)
                                            enabled: editable
                                            width: root.colMwW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(mwField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "MW", Number(text))
                                        }
                                        TextField {
                                            id: tcField
                                            text: Number(criticalTemperatureK).toFixed(1)
                                            enabled: editable
                                            width: root.colTcW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(tcField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Tc", Number(text))
                                        }
                                        TextField {
                                            id: pcField
                                            text: Number(criticalPressure).toFixed(2)
                                            enabled: editable
                                            width: root.colPcW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(pcField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Pc", Number(text))
                                        }
                                        TextField {
                                            id: omegaField
                                            text: Number(omega).toFixed(4)
                                            enabled: editable
                                            width: root.colOmegaW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(omegaField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "omega", Number(text))
                                        }
                                        TextField {
                                            id: sgField
                                            text: Number(specificGravity).toFixed(4)
                                            enabled: editable
                                            width: root.colSgW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(sgField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "SG", Number(text))
                                        }
                                        TextField {
                                            id: deltaField
                                            text: Number(delta).toFixed(4)
                                            enabled: editable
                                            width: root.colDeltaW
                                            height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 11
                                            padding: 4
                                            background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(deltaField); border.width: 1 }
                                            onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "delta", Number(text))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: !root.streamObject
                    text: "No stream selected."
                    color: root.mutedText
                    font.pixelSize: 12
                }
            }
        }
    }
}
