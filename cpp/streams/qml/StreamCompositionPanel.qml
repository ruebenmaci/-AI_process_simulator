import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

Item {
    id: root

    property var streamObject: null
    property var unitObject: null

    // ── Palette (ComponentManagerView) ─────────────────────────────
    readonly property color chrome:     "#c8d0d8"
    readonly property color panelInset: "#e8ebef"
    readonly property color border:     "#97a2ad"
    readonly property color activeBlue: "#2e73b8"
    readonly property color textDark:   "#1f2a34"
    readonly property color mutedText:  "#526571"
    readonly property color rowAlt:     "#f4f6f8"
    readonly property color warnBg:     "#fff4db"
    readonly property color warnBorder: "#d19a1c"
    readonly property color infoBg:     "#eef4ff"
    readonly property color infoBorder: "#8aa9d6"

    readonly property bool isProductStream: !!root.streamObject && root.streamObject.productStream
    readonly property bool canEditStream: !!root.streamObject && !root.isProductStream
    readonly property bool canEditComposition: root.canEditStream && !!root.streamObject && root.streamObject.componentEditingEnabled

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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    id: componentPropsLabel
                    text: "Package Component Properties"
                    color: root.textDark
                    font.bold: true
                    font.pixelSize: 11
                }

                Item {
                    Layout.minimumWidth: 30
                    Layout.fillWidth: true
                }

                Label {
                    id: massSumLabel
                    text: root.streamObject ? ("Mass fraction sum: " + fmt6(root.streamObject.massFractionSum)) : ""
                    color: root.textDark
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }

                ClassicButton {
                    id: normalizeButton
                    text: "Normalize Fractions"; width: 130
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditComposition
                    Layout.preferredWidth: 130; Layout.alignment: Qt.AlignRight
                    onClicked: if (root.streamObject) root.streamObject.normalizeComposition()
                }
                ClassicButton {
                    id: resetCompositionButton
                    text: "Reset Composition"; width: 120
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditComposition
                    onClicked: if (root.streamObject) root.streamObject.resetCompositionToFluidDefault()
                }
                ClassicButton {
                    id: resetPropertiesButton
                    text: "Reset Properties"; width: 110
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditComposition
                    onClicked: if (root.streamObject) root.streamObject.resetComponentPropertiesToFluidDefault()
                }
                ClassicButton {
                    id: clearEditsButton
                    text: "Clear Custom Edits"; width: 120
                    visible: !root.isProductStream
                    enabled: !!root.streamObject && root.canEditComposition && root.streamObject.hasCustomComposition
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
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Label {
                Layout.fillWidth: true
                visible: !!root.streamObject
                text: root.streamObject ? ((root.streamObject.selectedFluidPackageName ? ("Fluid package: " + root.streamObject.selectedFluidPackageName + "   •   ") : "") + root.streamObject.compositionSourceLabel) : ""
                color: root.mutedText
                font.pixelSize: 10
                font.italic: true
            }
            Rectangle {
                Layout.fillWidth: true
                visible: !!root.streamObject && !root.isProductStream && root.streamObject.componentEditingEnabled && !root.streamObject.massFractionsBalanced
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
                    font.pixelSize: 10
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: "View basis"
                    color: root.textDark
                    font.pixelSize: 10
                    font.bold: true
                }

                ComboBox {
                    id: basisCombo
                    Layout.preferredWidth: 150
                    font.pixelSize: 10
                    model: ["Mass fraction", "Mole fraction"]
                    currentIndex: root.compositionBasis === "Mole fraction" ? 1 : 0
                    onActivated: root.compositionBasis = currentText
                }

                CheckBox {
                    id: nonzeroOnlyCheck
                    text: "Show nonzero only"
                    checked: root.showNonzeroOnly
                    font.pixelSize: 10
                    onToggled: root.showNonzeroOnly = checked
                }

                Item { Layout.fillWidth: false }

                Label {
                    text: "Filter"
                    color: root.textDark
                    font.pixelSize: 10
                    font.bold: true
                }

                TextField {
                    id: filterField
                    Layout.preferredWidth: 180
                    Layout.minimumWidth: 140
                    font.pixelSize: 10
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
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
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

                                    Label { text: "Component"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colComponentW; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: root.fractionHeaderText(); color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colFractionW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Tb (K)"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colTbW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "MW"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colMwW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Tc (K)"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colTcW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "Pc"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colPcW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "omega"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colOmegaW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "SG"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colSgW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                                    Label { text: "delta"; color: root.textDark; font.bold: true; font.pixelSize: 10; width: root.colDeltaW; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
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
    
                                // Selection tracking - use array instead of object for better reactivity
                                property var selectedRowIndices: []
                                property int lastClickedRow: -1
                                property int selectionVersion: 0  // Force visual updates
    
                                function isRowSelected(rowIndex) {
                                    return selectedRowIndices.indexOf(rowIndex) >= 0
                                }
    
                                function selectRow(rowIndex, append) {
                                    var newSelection = append ? selectedRowIndices.slice() : []
                                    if (newSelection.indexOf(rowIndex) < 0) {
                                        newSelection.push(rowIndex)
                                    }
                                    selectedRowIndices = newSelection
                                    lastClickedRow = rowIndex
                                    selectionVersion++
                                }
    
                                function selectRowRange(startRow, endRow) {
                                    var newSelection = []
                                    var start = Math.min(startRow, endRow)
                                    var end = Math.max(startRow, endRow)
                                    for (var i = start; i <= end; i++) {
                                        newSelection.push(i)
                                    }
                                    selectedRowIndices = newSelection
                                    selectionVersion++
                                }
    
                                function toggleRowSelection(rowIndex) {
                                    var newSelection = selectedRowIndices.slice()
                                    var idx = newSelection.indexOf(rowIndex)
                                    if (idx >= 0) {
                                        newSelection.splice(idx, 1)
                                    } else {
                                        newSelection.push(rowIndex)
                                    }
                                    selectedRowIndices = newSelection
                                    lastClickedRow = rowIndex
                                    selectionVersion++
                                }
    
                                function clearSelection() {
                                    selectedRowIndices = []
                                    lastClickedRow = -1
                                    selectionVersion++
                                }
    
                                function getSelectedRowIndices() {
                                    return selectedRowIndices.slice().sort(function(a, b) { return a - b })
                                }
    
                                function selectAllRows() {
                                    if (!model) return
                                    var newSelection = []
                                    for (var i = 0; i < model.rowCount(); i++) {
                                        newSelection.push(i)
                                    }
                                    selectedRowIndices = newSelection
                                    selectionVersion++
                                }

                                delegate: Rectangle {
                                id: rowDelegate
                                width: listView.width
                                readonly property bool rowVisible: root.rowMatchesFilter(componentName, fraction)
                                readonly property bool isSelected: listView.isRowSelected(index) || (listView.selectionVersion >= 0 && false)  // Force binding update
                                height: rowVisible ? 32 : 0
                                visible: rowVisible
                                color: isSelected ? "#cce5ff" : (index % 2 === 0 ? root.rowAlt : root.panelInset)
                                border.color: isSelected ? root.activeBlue : "transparent"
                                border.width: isSelected ? 2 : 0

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
                                        font.pixelSize: 10
                                        width: root.colComponentW
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        height: parent.height
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                                        if (listView.lastClickedRow >= 0) {
                                                            listView.selectRowRange(listView.lastClickedRow, index)
                                                        } else {
                                                            listView.selectRow(index, false)
                                                        }
                                                    } else if (mouse.modifiers & Qt.ControlModifier) {
                                                        listView.toggleRowSelection(index)
                                                    } else {
                                                        listView.selectRow(index, false)
                                                    }
                                                } else if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                }
                                            }
                                        }
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
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(fracField); border.width: 1 }
                                        onEditingFinished: { 
                                            if (editable && root.fractionEditable() && root.streamObject && root.streamObject.compositionModel) { 
                                                root.streamObject.compositionModel.setFraction(index, Number(text)) 
                                            } else { 
                                                text = root.fractionDisplayValue(fraction, moleFraction).toFixed(6) 
                                            } 
                                        }
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false  // Let TextField handle left clicks
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: tbField
                                        text: Number(boilingPointK).toFixed(1)
                                        enabled: editable
                                        width: root.colTbW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(tbField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Tb", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: mwField
                                        text: Number(molecularWeight).toFixed(2)
                                        enabled: editable
                                        width: root.colMwW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(mwField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "MW", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: tcField
                                        text: Number(criticalTemperatureK).toFixed(1)
                                        enabled: editable
                                        width: root.colTcW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(tcField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Tc", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: pcField
                                        text: Number(criticalPressure).toFixed(2)
                                        enabled: editable
                                        width: root.colPcW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(pcField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "Pc", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: omegaField
                                        text: Number(omega).toFixed(4)
                                        enabled: editable
                                        width: root.colOmegaW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(omegaField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "omega", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: sgField
                                        text: Number(specificGravity).toFixed(4)
                                        enabled: editable
                                        width: root.colSgW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(sgField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "SG", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
        
                                    TextField {
                                        id: deltaField
                                        text: Number(delta).toFixed(4)
                                        enabled: editable
                                        width: root.colDeltaW
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: 10
                                        padding: 4
                                        selectByMouse: true
                                        background: Rectangle { radius: 4; color: "white"; border.color: fieldBg(deltaField); border.width: 1 }
                                        onEditingFinished: if (root.streamObject && root.streamObject.compositionModel) root.streamObject.compositionModel.setPropertyValue(index, "delta", Number(text))
            
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            propagateComposedEvents: true
                
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (!listView.isRowSelected(index)) {
                                                        listView.selectRow(index, false)
                                                    }
                                                    contextMenu.popup()
                                                    mouse.accepted = true
                                                }
                                            }
                
                                            onPressed: function(mouse) {
                                                if (mouse.button === Qt.LeftButton) {
                                                    mouse.accepted = false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
    
                                // Keyboard handler for copy/paste
                                Keys.onPressed: function(event) {
                                    if (event.modifiers & Qt.ControlModifier) {
                                        if (event.key === Qt.Key_C) {
                                            copySelectedRows()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_V) {
                                            pasteIntoSelectedRows()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_A) {
                                            selectAllRows()
                                            event.accepted = true
                                        }
                                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                                        clearSelectedRows()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Escape) {
                                        clearSelection()
                                        event.accepted = true
                                    }
                                }
    
                                focus: true  // Enable keyboard handling
    
                                function copySelectedRows() {
                                    if (!root.streamObject || !root.streamObject.compositionModel) return
        
                                    var indices = getSelectedRowIndices()
                                    if (indices.length === 0) return
        
                                    var model = root.streamObject.compositionModel
                                    var allData = []
        
                                    // Add header
                                    var headers = ["Component", root.fractionHeaderText(), "Tb (K)", "MW", "Tc (K)", "Pc", "omega", "SG", "delta"]
                                    allData.push(headers.join('\t'))
        
                                    // Add selected rows
                                    for (var i = 0; i < indices.length; i++) {
                                        var row = indices[i]
                                        var idx = model.index(row, 0)
            
                                        var rowData = []
                                        rowData.push(model.data(idx, Qt.UserRole + 1))   // componentName
                                        rowData.push(model.data(idx, Qt.UserRole + 2))   // fraction
                                        rowData.push(model.data(idx, Qt.UserRole + 4))   // boilingPointK
                                        rowData.push(model.data(idx, Qt.UserRole + 5))   // molecularWeight
                                        rowData.push(model.data(idx, Qt.UserRole + 6))   // criticalTemperatureK
                                        rowData.push(model.data(idx, Qt.UserRole + 7))   // criticalPressure
                                        rowData.push(model.data(idx, Qt.UserRole + 8))   // omega
                                        rowData.push(model.data(idx, Qt.UserRole + 9))   // specificGravity
                                        rowData.push(model.data(idx, Qt.UserRole + 10))  // delta
            
                                        allData.push(rowData.join('\t'))
                                    }
        
                                    Qt.application.clipboard.setText(allData.join('\n'))
                                    console.log("Copied", indices.length, "rows to clipboard")
                                }
    
                                function pasteIntoSelectedRows() {
                                    if (!root.streamObject || !root.streamObject.compositionModel) return
                                    if (!root.canEditComposition) {
                                        console.log("Cannot paste - stream is not editable")
                                        return
                                    }
        
                                    var clipboardText = Qt.application.clipboard.text
                                    if (!clipboardText) return
        
                                    var indices = getSelectedRowIndices()
                                    if (indices.length === 0) return
        
                                    // Parse clipboard data
                                    var rows = clipboardText.split('\n')
                                    var model = root.streamObject.compositionModel
        
                                    // Skip header row if it exists
                                    var startRow = 0
                                    if (rows.length > 0 && rows[0].indexOf("Component") >= 0) {
                                        startRow = 1
                                    }
        
                                    var rowsUpdated = 0
        
                                    for (var i = startRow; i < rows.length && rowsUpdated < indices.length; i++) {
                                        var rowText = rows[i].trim()
                                        if (rowText.length === 0) continue
            
                                        var cells = rowText.split('\t')
                                        var targetRow = indices[rowsUpdated]
            
                                        // Skip column 0 (component name)
                                        if (cells.length >= 2 && cells[1]) {
                                            model.setFraction(targetRow, Number(cells[1]))
                                        }
                                        if (cells.length >= 3 && cells[2]) {
                                            model.setPropertyValue(targetRow, "Tb", Number(cells[2]))
                                        }
                                        if (cells.length >= 4 && cells[3]) {
                                            model.setPropertyValue(targetRow, "MW", Number(cells[3]))
                                        }
                                        if (cells.length >= 5 && cells[4]) {
                                            model.setPropertyValue(targetRow, "Tc", Number(cells[4]))
                                        }
                                        if (cells.length >= 6 && cells[5]) {
                                            model.setPropertyValue(targetRow, "Pc", Number(cells[5]))
                                        }
                                        if (cells.length >= 7 && cells[6]) {
                                            model.setPropertyValue(targetRow, "omega", Number(cells[6]))
                                        }
                                        if (cells.length >= 8 && cells[7]) {
                                            model.setPropertyValue(targetRow, "SG", Number(cells[7]))
                                        }
                                        if (cells.length >= 9 && cells[8]) {
                                            model.setPropertyValue(targetRow, "delta", Number(cells[8]))
                                        }
            
                                        rowsUpdated++
                                    }
        
                                    console.log("Pasted into", rowsUpdated, "rows")
                                }
    
                                function clearSelectedRows() {
                                    if (!root.streamObject || !root.streamObject.compositionModel) return
                                    if (!root.canEditComposition) return
        
                                    var indices = getSelectedRowIndices()
                                    var model = root.streamObject.compositionModel
        
                                    for (var i = 0; i < indices.length; i++) {
                                        var row = indices[i]
                                        model.setFraction(row, 0)
                                        model.setPropertyValue(row, "Tb", 0)
                                        model.setPropertyValue(row, "MW", 0)
                                        model.setPropertyValue(row, "Tc", 0)
                                        model.setPropertyValue(row, "Pc", 0)
                                        model.setPropertyValue(row, "omega", 0)
                                        model.setPropertyValue(row, "SG", 0)
                                        model.setPropertyValue(row, "delta", 0)
                                    }
                                }
                            }
                        
                        // Context menu
                        Menu {
                            id: contextMenu
                            
                            MenuItem {
                                text: "Copy Selected Rows"
                                enabled: listView.getSelectedRowIndices().length > 0
                                onTriggered: listView.copySelectedRows()
                            }
                            
                            MenuItem {
                                text: "Paste into Selected Rows"
                                enabled: listView.getSelectedRowIndices().length > 0 && root.canEditComposition
                                onTriggered: listView.pasteIntoSelectedRows()
                            }
                            
                            MenuSeparator {}
                            
                            MenuItem {
                                text: "Select All"
                                onTriggered: listView.selectAllRows()
                            }
                            
                            MenuItem {
                                text: "Clear Selection"
                                enabled: listView.getSelectedRowIndices().length > 0
                                onTriggered: listView.clearSelection()
                            }
                            
                            MenuSeparator {}
                            
                            MenuItem {
                                text: "Clear Selected Rows"
                                enabled: listView.getSelectedRowIndices().length > 0 && root.canEditComposition
                                onTriggered: listView.clearSelectedRows()
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
                    font.pixelSize: 10
                }
            }
        }
    }
}
