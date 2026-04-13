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

    property string compositionBasis: "Mass fraction"
    property bool showNonzeroOnly: false
    property string componentFilterText: ""

    property var _snapshotStreamObject: null
    property var _originalMassFractions: []
    property var _originalComponentProperties: []

    function captureOriginalState() {
        if (!root.streamObject || !root.streamObject.compositionModel)
            return
        var model = root.streamObject.compositionModel
        var n = model.rowCountQml()
        var fractions = []
        var props = []
        for (var i = 0; i < n; ++i) {
            var idx = model.index(i, 0)
            fractions.push(Number(model.data(idx, Qt.UserRole + 2)))
            props.push({
                Tb: Number(model.data(idx, Qt.UserRole + 4)),
                MW: Number(model.data(idx, Qt.UserRole + 5)),
                Tc: Number(model.data(idx, Qt.UserRole + 6)),
                Pc: Number(model.data(idx, Qt.UserRole + 7)),
                omega: Number(model.data(idx, Qt.UserRole + 8)),
                SG: Number(model.data(idx, Qt.UserRole + 9)),
                delta: Number(model.data(idx, Qt.UserRole + 10))
            })
        }
        root._snapshotStreamObject = root.streamObject
        root._originalMassFractions = fractions
        root._originalComponentProperties = props
    }

    function ensureOriginalStateCaptured() {
        if (!root.streamObject || !root.streamObject.compositionModel)
            return false
        if (root._snapshotStreamObject !== root.streamObject
                || !root._originalMassFractions
                || root._originalMassFractions.length === 0) {
            root.captureOriginalState()
        }
        return root._snapshotStreamObject === root.streamObject
    }

    function restoreOriginalFractions() {
        if (!root.ensureOriginalStateCaptured())
            return
        var model = root.streamObject.compositionModel
        var count = Math.min(model.rowCountQml(), root._originalMassFractions.length)
        for (var i = 0; i < count; ++i)
            model.setFraction(i, Number(root._originalMassFractions[i]))
    }

    function restoreOriginalProperties() {
        if (!root.ensureOriginalStateCaptured())
            return
        var model = root.streamObject.compositionModel
        var count = Math.min(model.rowCountQml(), root._originalComponentProperties.length)
        for (var i = 0; i < count; ++i) {
            var prop = root._originalComponentProperties[i]
            if (!prop)
                continue
            model.setPropertyValue(i, "Tb", Number(prop.Tb))
            model.setPropertyValue(i, "MW", Number(prop.MW))
            model.setPropertyValue(i, "Tc", Number(prop.Tc))
            model.setPropertyValue(i, "Pc", Number(prop.Pc))
            model.setPropertyValue(i, "omega", Number(prop.omega))
            model.setPropertyValue(i, "SG", Number(prop.SG))
            model.setPropertyValue(i, "delta", Number(prop.delta))
        }
    }

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
    function visibleFractionSum() {
        if (!root.streamObject || !root.streamObject.compositionModel) return 0
        var model = root.streamObject.compositionModel
        var n = model.rowCountQml()
        var total = 0
        for (var i = 0; i < n; ++i) {
            var idx = model.index(i, 0)
            var fractionValue = model.data(idx, Qt.UserRole + 2)
            var moleFractionValue = model.data(idx, Qt.UserRole + 3)
            var componentName = model.data(idx, Qt.UserRole + 1)
            var shownValue = root.fractionDisplayValue(fractionValue, moleFractionValue)
            if (root.rowMatchesFilter(componentName, shownValue))
                total += Number(shownValue)
        }
        return total
    }

    Rectangle {
        anchors.fill: parent
        clip: true
        color: root.panelInset
        border.color: root.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 28
                clip: true

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Label {
                        id: massSumLabel
                        text: root.streamObject ? ((root.compositionBasis === "Mole fraction" ? "Mole fraction sum: " : "Mass fraction sum: ") + fmt6(root.visibleFractionSum())) : ""
                        color: root.textDark
                        font.pixelSize: 10
                        font.bold: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Item { width: 12; height: 1 }

                    ClassicButton {
                        id: normalizeButton
                        text: "Normalize Fractions"
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
                        width: 122
                        onClicked: {
                            if (!root.streamObject || !root.streamObject.compositionModel)
                                return
                            if (root.compositionBasis === "Mole fraction")
                                root.streamObject.compositionModel.normalizeMoleFractions()
                            else
                                root.streamObject.normalizeComposition()
                        }
                    }
                    ClassicButton {
                        id: resetFractionsButton
                        text: "Reset Fractions"
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
                        width: 114
                        onClicked: root.restoreOriginalFractions()
                    }
                    ClassicButton {
                        id: resetPropertiesButton
                        text: "Reset Properties"
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
                        width: 106
                        onClicked: root.restoreOriginalProperties()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
                Layout.minimumWidth: 0
                visible: !!root.streamObject
                text: root.streamObject ? ((root.streamObject.selectedFluidPackageName ? ("Fluid package: " + root.streamObject.selectedFluidPackageName + "   •   ") : "") + root.streamObject.compositionSourceLabel) : ""
                color: root.mutedText
                font.pixelSize: 10
                font.italic: true
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
                Layout.minimumWidth: 0
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

            // ── Composition table — SimpleSpreadsheet ──────────────────────
            // Col 0: Component name (frozen/read-only)
            // Col 1: Mass/Mole Fraction (editable for feed streams)
            // Cols 2-8: Tb, MW, Tc, Pc, omega, SG, delta (editable for feed streams)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                clip: true

                SimpleSpreadsheet {
                    id: compSheet
                    anchors.fill: parent
                    readOnly: false
                    stretchToWidth: false
                    verticalScrollBarPolicy: ScrollBar.AsNeeded
                    horizontalScrollBarPolicy: ScrollBar.AsNeeded
                    cornerLabel: "Component"
                    readOnlyCols: root.canEditComposition ? [] : [0,1,2,3,4,5,6,7]
                    numCols: 8
                    numRows: 0   // will be set on refresh

                    colLabels: [root.fractionHeaderText(), "Tb (K)", "MW", "Tc (K)", "Pc", "omega", "SG", "delta"]
                    defaultColW: 80

                    property var compactColWidths: [100, 72, 72, 72, 104, 72, 60, 60]

                    property int _populated: 0

                    function refresh() {
                        if (!root.streamObject || !root.streamObject.compositionModel) {
                            numRows = 0
                            clearAll()
                            return
                        }
                        var model = root.streamObject.compositionModel
                        var n = model.rowCountQml()

                        // Apply filter
                        var visibleRows = []
                        for (var i = 0; i < n; i++) {
                            var idx = model.index(i, 0)
                            var cname = model.data(idx, Qt.UserRole + 1)
                            var frac  = model.data(idx, Qt.UserRole + 2)
                            if (root.rowMatchesFilter(cname, frac))
                                visibleRows.push(i)
                        }

                        numRows = visibleRows.length
                        colW = compactColWidths.slice()
                        // Row labels = component names (shown in the frozen Property column)
                        var labels = []
                        for (var j = 0; j < visibleRows.length; j++) {
                            var midx = model.index(visibleRows[j], 0)
                            labels.push(model.data(midx, Qt.UserRole + 1))
                        }
                        rowLabels = labels

                        // Populate data cells
                        for (var r = 0; r < visibleRows.length; r++) {
                            var srcRow = visibleRows[r]
                            var ix = model.index(srcRow, 0)
                            var basis = root.compositionBasis === "Mole fraction"
                                        ? model.data(ix, Qt.UserRole + 3)   // moleFraction
                                        : model.data(ix, Qt.UserRole + 2)   // fraction
                            setCell(r, 0, Number(basis).toFixed(6))
                            setCell(r, 1, Number(model.data(ix, Qt.UserRole + 4)).toFixed(1))   // Tb
                            setCell(r, 2, Number(model.data(ix, Qt.UserRole + 5)).toFixed(2))   // MW
                            setCell(r, 3, Number(model.data(ix, Qt.UserRole + 6)).toFixed(1))   // Tc
                            setCell(r, 4, Number(model.data(ix, Qt.UserRole + 7)).toFixed(2))   // Pc
                            setCell(r, 5, Number(model.data(ix, Qt.UserRole + 8)).toFixed(4))   // omega
                            setCell(r, 6, Number(model.data(ix, Qt.UserRole + 9)).toFixed(4))   // SG
                            setCell(r, 7, Number(model.data(ix, Qt.UserRole + 10)).toFixed(4))  // delta
                        }

                        // Store visible row mapping for use in cellEdited
                        compSheet._visibleRows = visibleRows
                        _populated++
                    }

                    property var _visibleRows: []

                    // Push edits back to the C++ model
                    onCellEdited: function(row, col, text) {
                        if (!root.canEditComposition) return
                        if (!root.streamObject || !root.streamObject.compositionModel) return
                        var srcRow = _visibleRows[row]
                        if (srcRow === undefined) return
                        var model = root.streamObject.compositionModel
                        if (col === 0) {
                            if (root.compositionBasis === "Mole fraction")
                                model.setMoleFraction(srcRow, Number(text))
                            else
                                model.setFraction(srcRow, Number(text))
                        } else if (col === 1) model.setPropertyValue(srcRow, "Tb",    Number(text))
                        else if (col === 2) model.setPropertyValue(srcRow, "MW",    Number(text))
                        else if (col === 3) model.setPropertyValue(srcRow, "Tc",    Number(text))
                        else if (col === 4) model.setPropertyValue(srcRow, "Pc",    Number(text))
                        else if (col === 5) model.setPropertyValue(srcRow, "omega", Number(text))
                        else if (col === 6) model.setPropertyValue(srcRow, "SG",    Number(text))
                        else if (col === 7) model.setPropertyValue(srcRow, "delta", Number(text))
                    }

                    // Outer panel scroll passthrough (Properties panel uses Flickable)
                    onWheelPassthrough: function(dy, dx) { /* no outer flickable here */ }

                    Component.onCompleted: {
                        Qt.callLater(root.captureOriginalState)
                        Qt.callLater(refresh)
                    }

                    Connections {
                        target: root
                        function onStreamObjectChanged() {
                            root.captureOriginalState()
                            Qt.callLater(compSheet.refresh)
                        }
                        function onCompositionBasisChanged() { Qt.callLater(compSheet.refresh) }
                        function onShowNonzeroOnlyChanged() { Qt.callLater(compSheet.refresh) }
                        function onComponentFilterTextChanged() { Qt.callLater(compSheet.refresh) }
                    }
                    Connections {
                        target: root.streamObject
                        function onCompositionChanged()       { Qt.callLater(compSheet.refresh) }
                        function onDerivedConditionsChanged() { Qt.callLater(compSheet.refresh) }
                        ignoreUnknownSignals: true
                    }
                }
            }
        }
    }
}
