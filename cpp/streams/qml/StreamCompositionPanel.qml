import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../qml/common"

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
    property var columnUnitOverrides: ["", "", "", "", "", "", "", ""]

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
            anchors.margins: 8
            spacing: 5

            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 28
                clip: true

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Label {
                        id: massSumLabel
                        text: root.streamObject ? ((root.compositionBasis === "Mole fraction" ? "Mole fraction sum: " : "Mass fraction sum: ") + fmt6(root.visibleFractionSum())) : ""
                        color: root.textDark
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Item { width: 4; height: 1 }

                    PButton {
                        id: normalizeButton
                        text: "Normalize Fractions"
                        fontPixelSize: 11
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
                        onClicked: {
                            if (!root.streamObject || !root.streamObject.compositionModel)
                                return
                            if (root.compositionBasis === "Mole fraction")
                                root.streamObject.compositionModel.normalizeMoleFractions()
                            else
                                root.streamObject.normalizeComposition()
                        }
                    }
                    PButton {
                        id: resetFractionsButton
                        text: "Reset Fractions"
                        fontPixelSize: 11
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
                        onClicked: root.restoreOriginalFractions()
                    }
                    PButton {
                        id: resetPropertiesButton
                        text: "Reset Properties"
                        fontPixelSize: 11
                        visible: !root.isProductStream
                        enabled: !!root.streamObject && root.canEditComposition
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
                    font.pixelSize: 11
                    font.bold: true
                }
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
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Label {
                    text: "View basis"
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                }

                PComboBox {
                    id: basisCombo
                    Layout.preferredWidth: 120
                    fontSize: 11
                    model: ["Mass fraction", "Mole fraction"]
                    currentIndex: root.compositionBasis === "Mole fraction" ? 1 : 0
                    onActivated: root.compositionBasis = currentText
                }

                PCheckBox {
                    id: nonzeroOnlyCheck
                    text: "Show nonzero only"
                    checked: root.showNonzeroOnly
                    fontPixelSize: 11
                    onToggled: root.showNonzeroOnly = checked
                }

                Item { Layout.fillWidth: false }

                Label {
                    text: "Filter"
                    color: root.textDark
                    font.pixelSize: 11
                    font.bold: true
                }

                PTextField {
                    id: filterField
                    Layout.preferredWidth: 118
                    Layout.minimumWidth: 96
                    fontSize: 11
                    placeholderText: "Component name"
                    text: root.componentFilterText
                    onTextChanged: root.componentFilterText = text
                }
            }

            // ── Composition table — PSpreadsheet ──────────────────────
            // Col 0: Component name (frozen/read-only)
            // Col 1: Mass/Mole Fraction (editable for feed streams)
            // Cols 2-8: Tb, MW, Tc, Pc, omega, SG, delta (editable for feed streams)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                clip: true

                PSpreadsheet {
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
                    columnQuantities: ["", "Temperature", "MolarMass", "Temperature", "Pressure", "", "", ""]
                    columnUnits: root.columnUnitOverrides

                    // Per-column unit metadata — one entry per data column.
                    //   q       : gFormats / gUnits quantity name ("" = no quantity)
                    //   modelSI : multiplier that converts model value → SI
                    //             (most are already SI so multiplier = 1)
                    //   label   : column label (no unit suffix; UnitToken below
                    //             the header label shows the active unit)
                    // Per-column decimals are NOT stored here anymore — gFormats
                    // controls per-quantity formatting via _displayValue().
                    // Col 0 (fraction) uses a dynamic quantity keyed off basis
                    // ("MassFraction" or "MoleFraction") — see _fracQuantity().
                    readonly property var _colMeta: [
                        { q: "",            modelSI: 1.0,   label: root.fractionHeaderText() },
                        { q: "Temperature", modelSI: 1.0,   label: "Tb"    },
                        { q: "MolarMass",   modelSI: 0.001, label: "MW"    },
                        { q: "Temperature", modelSI: 1.0,   label: "Tc"    },
                        { q: "Pressure",    modelSI: 1.0,   label: "Pc"    },
                        { q: "Acentric",    modelSI: 1.0,   label: "omega" },
                        { q: "SpecificGravity", modelSI: 1.0, label: "SG"  },
                        { q: "",            modelSI: 1.0,   label: "delta" }
                    ]

                    // Quantity name for col 0 (fraction column) — depends on
                    // the user's chosen view basis so gFormats picks the right
                    // spec (both MassFraction and MoleFraction are Fixed 4).
                    function _fracQuantity() {
                        return root.compositionBasis === "Mole fraction"
                               ? "MoleFraction" : "MassFraction"
                    }

                    // Re-format cell values when the active unit set changes.
                    Connections {
                        target: typeof gUnits !== "undefined" ? gUnits : null
                        ignoreUnknownSignals: true
                        function onUnitsChanged()         { Qt.callLater(compSheet.refresh) }
                        function onActiveUnitSetChanged() { Qt.callLater(compSheet.refresh) }
                    }

                    // Same for the active format set / per-quantity spec edits.
                    Connections {
                        target: typeof gFormats !== "undefined" ? gFormats : null
                        ignoreUnknownSignals: true
                        function onFormatsChanged()         { Qt.callLater(compSheet.refresh) }
                        function onActiveFormatSetChanged() { Qt.callLater(compSheet.refresh) }
                    }

                    function _unitFor(col) {
                        var meta = _colMeta[col]
                        if (!meta || meta.q === "") return ""
                        if (root.columnUnitOverrides && col < root.columnUnitOverrides.length && root.columnUnitOverrides[col])
                            return root.columnUnitOverrides[col]
                        if (typeof gUnits === "undefined") return ""
                        return gUnits.defaultUnit(meta.q)
                    }

                    // Bare column labels — no parenthesized unit suffix.
                    // The active unit is already shown in the clickable
                    // UnitToken that PSpreadsheet renders directly below
                    // each header label whenever the column has a quantity,
                    // so duplicating it here ("Tb (°F)" + "°F ▾") is just
                    // visual noise. Cell values still re-format on unit-set
                    // changes via the refresh() trigger in Connections above.
                    colLabels: {
                        var labels = []
                        for (var c = 0; c < _colMeta.length; c++) {
                            if (c === 0) { labels.push(root.fractionHeaderText()); continue }
                            labels.push(_colMeta[c].label)
                        }
                        return labels
                    }

                    defaultColW: 70
                    hdrColW: 62

                    // Per-column widths for the composition table.
                    // 72 px is the snug-but-comfortable width that fits the
                    // numeric values plus a unit token (e.g. "°F ▾") below
                    // each header. Mass Fraction is bumped to 88 because its
                    // header text alone ("Mass Fraction" / "Mole Fraction")
                    // doesn't fit in 72 px. Indices match _colMeta:
                    // [Frac, Tb, MW, Tc, Pc, omega, SG, delta]
                    property var compactColWidths: [88, 72, 72, 72, 72, 72, 72, 72]

                    property int _populated: 0

                    // Convert a model-side raw number to display string in the
                    // active unit, formatted per the gFormats spec for the
                    // column's quantity. Falls back gracefully if a registry
                    // is missing.
                    function _displayValue(col, modelValue) {
                        var m = _colMeta[col]
                        if (modelValue === undefined || modelValue === null || isNaN(modelValue))
                            return ""
                        var v = Number(modelValue)
                        if (!m) return String(v)

                        // Resolve quantity (col 0 is dynamic based on basis).
                        var q = (col === 0) ? _fracQuantity() : m.q

                        // No quantity → no unit conversion. Format with gFormats
                        // if available (delta etc. fall through to the default
                        // Fixed/3 spec); otherwise raw String().
                        if (q === "" || typeof gUnits === "undefined") {
                            if (typeof gFormats !== "undefined")
                                return gFormats.formatValue(q, v)
                            return String(v)
                        }

                        // Quantity-bearing column: SI-convert then format.
                        var siValue  = v * m.modelSI
                        var unit     = _unitFor(col)
                        var converted = gUnits.fromSI(q, siValue, unit)
                        if (typeof gFormats !== "undefined")
                            return gFormats.formatValue(q, converted)
                        return Number(converted).toFixed(3)
                    }

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

                        // Populate data cells — each value goes through
                        // _displayValue() which converts to the active unit.
                        for (var r = 0; r < visibleRows.length; r++) {
                            var srcRow = visibleRows[r]
                            var ix = model.index(srcRow, 0)
                            var basis = root.compositionBasis === "Mole fraction"
                                        ? model.data(ix, Qt.UserRole + 3)   // moleFraction
                                        : model.data(ix, Qt.UserRole + 2)   // fraction
                            setCell(r, 0, _displayValue(0, basis))
                            setCell(r, 1, _displayValue(1, model.data(ix, Qt.UserRole + 4)))   // Tb
                            setCell(r, 2, _displayValue(2, model.data(ix, Qt.UserRole + 5)))   // MW
                            setCell(r, 3, _displayValue(3, model.data(ix, Qt.UserRole + 6)))   // Tc
                            setCell(r, 4, _displayValue(4, model.data(ix, Qt.UserRole + 7)))   // Pc
                            setCell(r, 5, _displayValue(5, model.data(ix, Qt.UserRole + 8)))   // omega
                            setCell(r, 6, _displayValue(6, model.data(ix, Qt.UserRole + 9)))   // SG
                            setCell(r, 7, _displayValue(7, model.data(ix, Qt.UserRole + 10))) // delta
                        }

                        // Store visible row mapping for use in cellEdited
                        compSheet._visibleRows = visibleRows
                        _populated++
                    }

                    property var _visibleRows: []

                    // Convert a user-typed display value back to the model
                    // storage unit (inverse of _displayValue).
                    function _modelValue(col, displayText) {
                        var v = Number(displayText)
                        if (isNaN(v)) return v
                        var m = _colMeta[col]
                        if (!m || m.q === "" || typeof gUnits === "undefined")
                            return v
                        var unit = _unitFor(col)
                        var siValue = gUnits.toSI(m.q, v, unit)
                        // Inverse of "v_si = v_model * modelSI" → v_model = v_si / modelSI
                        return siValue / m.modelSI
                    }

                    // Push edits back to the C++ model (converted to model unit)
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
                        } else if (col === 1) model.setPropertyValue(srcRow, "Tb",    _modelValue(1, text))
                        else if (col === 2) model.setPropertyValue(srcRow, "MW",    _modelValue(2, text))
                        else if (col === 3) model.setPropertyValue(srcRow, "Tc",    _modelValue(3, text))
                        else if (col === 4) model.setPropertyValue(srcRow, "Pc",    _modelValue(4, text))
                        else if (col === 5) model.setPropertyValue(srcRow, "omega", Number(text))
                        else if (col === 6) model.setPropertyValue(srcRow, "SG",    Number(text))
                        else if (col === 7) model.setPropertyValue(srcRow, "delta", Number(text))
                    }

                    onColumnUnitChanged: function(col, unit) {
                        var next = root.columnUnitOverrides ? root.columnUnitOverrides.slice() : []
                        while (next.length < numCols) next.push("")
                        next[col] = unit
                        root.columnUnitOverrides = next
                        Qt.callLater(compSheet.refresh)
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
