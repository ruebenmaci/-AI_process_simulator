import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnDrawsPanel.qml — Draws / Solver tab.
//
//  Two side-by-side PGroupBox sections:
//
//    ┌─ Draw Specifications ──────────────────────────┐ ┌─ Solve / Status ─┐
//    │  Header row (column titles)                    │ │  [Solve]  [Reset]│
//    │  ┌──────────┬───┬──┬──────┬──────┬────────┬─┐ │ │                  │
//    │  │ Naphtha  │30 │L │feedPct│ 6.80 │Stripper│×│ │ │  Status: …       │
//    │  │ Kerosene │21 │L │feedPct│13.30 │Stripper│×│ │ │  Elapsed: …      │
//    │  │ ...      │   │  │       │      │        │ │ │ │  ...             │
//    │  └──────────┴───┴──┴──────┴──────┴────────┴─┘ │ │                  │
//    │  [Stripper config sub-panel — collapsible]     │ │                  │
//    │  [+ Add Draw] [Reset]   Total: 47.6%  (123 kg) │ │                  │
//    └────────────────────────────────────────────────┘ └──────────────────┘
//
//  The draw spec row uses the canonical 7-control pattern built around the
//  new PSpinner:
//
//    PTextField | PSpinner | PComboBox | PComboBox | PGridValue | PButton | PButton(✕)
//      name       tray       phase       basis        value       stripper    delete
//
//  All edits commit through the standard pattern of cloning drawSpecs, mutating
//  the row, and assigning back via setDrawSpecs (matches the original behaviour).
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    // ── Selection / focus state for stripper sub-panel ──────────────────────
    property int selectedDrawIndex:   -1
    property int activeStripperIndex: -1

    // ── Column-width probes (hidden, for content-driven table widths) ───────
    // These probes measure their own .implicitWidth based on the widest item
    // each column would ever render. Header cells and row delegate cells
    // both bind their Layout.* widths to the derived column-width properties
    // below, so the table is guaranteed to fit its content with header and
    // rows staying perfectly aligned. If the model ever grows ("feedPct" →
    // "feedPctDry"), the column resizes itself; no manual width math needed.
    //
    // Probes are children of root (a plain Item, not a layout) and have
    // width/height pinned to 0 with visible:false, so they never affect
    // the visual flow. PComboBox._longestPx is recomputed on model change,
    // so the .implicitWidth binding stays live.
    PComboBox {
        id: phaseProbe
        visible: false
        width: 0; height: 0
        model: ["L", "V"]
        minimumContentWidth: 0
    }
    PComboBox {
        id: basisProbe
        visible: false
        width: 0; height: 0
        model: ["feedPct", "kg/h"]
        minimumContentWidth: 0
    }
    PButton {
        id: stripperProbe
        visible: false
        width: 0; height: 0
        text: "Stripper On"        // longer of the two button states
        fontPixelSize: 10
        contentHPadding: 4
    }

    // ── Derived column widths (single source of truth for header + rows) ────
    // Rule: "use the floor unless the measured natural width is larger." This
    // is exactly the auto-sizing behaviour you'd want from any control —
    // floor protects the header alignment, probe protects against clipping.
    readonly property int nameColMinWidth:  282    // Name field: flex w/ floor
    readonly property int trayColWidth:     56     // PSpinner; 3-digit + chevrons
    readonly property int phaseColWidth:    Math.max(37, phaseProbe.implicitWidth)
    readonly property int basisColWidth:    Math.max(70, basisProbe.implicitWidth)
    readonly property int valueColWidth:    90     // PGridValue numeric, ~6 chars
    readonly property int stripperColWidth: Math.max(76, stripperProbe.implicitWidth)
    readonly property int deleteColWidth:   26     // PButton in icon mode

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _cloneSpecs() {
        if (!appState || !appState.drawSpecs) return []
        var src = appState.drawSpecs
        var out = []
        for (var k = 0; k < src.length; ++k) out.push(Object.assign({}, src[k]))
        return out
    }
    function _commit(specs) { if (appState) appState.drawSpecs = specs }
    function _activateRow(rowIdx) {
        selectedDrawIndex = rowIdx
        if (appState && appState.drawSpecs && rowIdx >= 0 && rowIdx < appState.drawSpecs.length)
            activeStripperIndex = Boolean(appState.drawSpecs[rowIdx].stripperEnabled) ? rowIdx : -1
        else
            activeStripperIndex = -1
    }
    function _toggleStripper(rowIdx) {
        if (!appState) return
        var c = _cloneSpecs()
        if (rowIdx < 0 || rowIdx >= c.length) return
        var enableNext = !Boolean(c[rowIdx].stripperEnabled)
        c[rowIdx].stripperEnabled = enableNext
        if (!c[rowIdx].stripperLabel || c[rowIdx].stripperLabel === "")
            c[rowIdx].stripperLabel = (c[rowIdx].name || "Draw") + " Stripper"
        if (!c[rowIdx].stripperTrays) c[rowIdx].stripperTrays = 4
        if (!c[rowIdx].stripperReturnTray)
            c[rowIdx].stripperReturnTray = Math.max(2, Number(c[rowIdx].tray || 2) - 1)
        if (!c[rowIdx].stripperHeatMode || c[rowIdx].stripperHeatMode === "")
            c[rowIdx].stripperHeatMode = "Steam"
        if (c[rowIdx].stripperHeatValue === undefined) c[rowIdx].stripperHeatValue = 0
        selectedDrawIndex = rowIdx
        activeStripperIndex = enableNext ? rowIdx : -1
        _commit(c)
    }
    function _deleteRow(rowIdx) {
        if (!appState) return
        var c = _cloneSpecs()
        if (rowIdx < 0 || rowIdx >= c.length) return
        c.splice(rowIdx, 1)
        if (selectedDrawIndex >= c.length) selectedDrawIndex = c.length - 1
        if (activeStripperIndex === rowIdx) activeStripperIndex = -1
        else if (activeStripperIndex > rowIdx) activeStripperIndex = activeStripperIndex - 1
        _commit(c)
    }
    function _addRow() {
        if (!appState) return
        var c = _cloneSpecs()
        c.push({
            name: "New Draw",
            tray: appState.feedTray || 16,
            basis: "feedPct",
            phase: "L",
            value: 0,
            stripperEnabled: false,
            stripperId: "",
            stripperLabel: "",
            stripperTrays: 4,
            stripperReturnTray: Math.max(2, (appState.feedTray || 16) - 1),
            stripperHeatMode: "Steam",
            stripperHeatValue: 0,
            stripperMaxCoupledIterations: 25,
            stripperCouplingTolerance: 1e-3,
            stripperReturnDamping: 0.35
        })
        selectedDrawIndex = c.length - 1
        _commit(c)
    }
    function _feedKgph() {
        return (appState && appState.feedStream) ? Number(appState.feedStream.flowRateKgph) : 0
    }
    function _totalTargetPct() {
        if (!appState || !appState.drawSpecs) return 0
        var tot = 0; var specs = appState.drawSpecs
        for (var i = 0; i < specs.length; ++i) {
            var v = Number(specs[i].value)
            if (specs[i].basis === "feedPct" && isFinite(v)) tot += v
        }
        return tot
    }
    function _fmt2(x)  { var n = Number(x); return isFinite(n) ? n.toFixed(2) : "—" }
    function _fmt3(x)  { var n = Number(x); return isFinite(n) ? n.toFixed(3) : "—" }

    // ── Per-quantity display unit overrides ────────────────────────────────
    // Mirrors the pattern used in FluidManagerView / ComponentManagerView /
    // ColumnSetupPanel: when the user clicks a PGridUnit picker on any
    // cell in this panel (Stripper Run Results, primarily), the chosen unit
    // is stashed here keyed by quantity. Every PGridValue and PGridUnit on
    // this panel binds its `displayUnit` to `unitFor(quantity)` and every
    // PGridUnit emits `onUnitOverride` back into `setUnit(quantity, u)`.
    //
    // The result: picking, say, "°C" on Top T immediately re-renders Top T
    // and Bottom T in °C — the underlying SI value is unchanged, only the
    // display unit flips. Empty string ("") means "fall back to the active
    // Unit Set default".
    //
    // The draw-row Value cells use Dimensionless (basis is in a separate
    // ComboBox), so they are unaffected.
    property var unitOverrides: ({
        "Temperature": "",
        "Pressure":    "",
        "MassFlow":    ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        // Object.assign is required so QML's reactivity sees a property
        // change. Mutating unitOverrides[q] directly would not fire the
        // unitOverridesChanged signal and the bindings would not update.
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // ── Commit-by-key helper used by every row control ──────────────────────
    function _setSpec(rowIdx, key, value) {
        if (!appState) return
        var c = _cloneSpecs()
        if (rowIdx < 0 || rowIdx >= c.length) return
        c[rowIdx][key] = value
        _commit(c)
    }

    // ── Stripper matching: maps a draw spec to its attached run-result row.
    // Lifted verbatim from the legacy DistillationColumn.qml so behaviour
    // is preserved exactly — same 3-tier lookup (stripperId → sourceTray →
    // label) and same descending-tray sort order.
    function _attachedStrippersSorted() {
        if (!appState || !appState.attachedStrippers) return []
        var rows = []
        for (var i = 0; i < appState.attachedStrippers.length; ++i)
            rows.push(appState.attachedStrippers[i])
        rows.sort(function(a, b) {
            var trayA = Number(a && a.sourceTray !== undefined ? a.sourceTray : -1)
            var trayB = Number(b && b.sourceTray !== undefined ? b.sourceTray : -1)
            if (trayA !== trayB) return trayB - trayA
            var labelA = a && a.label ? String(a.label) : ""
            var labelB = b && b.label ? String(b.label) : ""
            return labelA.localeCompare(labelB)
        })
        return rows
    }
    function _attachedStripperForSpec(spec) {
        if (!spec || !appState || !appState.attachedStrippers) return null
        var matches = _attachedStrippersSorted()
        var tray = Number(spec.tray !== undefined ? spec.tray : -1)
        var stripperId = spec.stripperId ? String(spec.stripperId) : ""
        var label = spec.stripperLabel
                    ? String(spec.stripperLabel)
                    : ((spec.name ? String(spec.name) : "") + " Stripper")
        // 1: match by stripperId
        for (var i = 0; i < matches.length; ++i) {
            var row = matches[i]
            if (stripperId !== "" && row.stripperId && String(row.stripperId) === stripperId)
                return row
        }
        // 2: match by source tray
        for (var j = 0; j < matches.length; ++j) {
            var row2 = matches[j]
            if (Number(row2.sourceTray) === tray) return row2
        }
        // 3: match by label
        for (var k = 0; k < matches.length; ++k) {
            var row3 = matches[k]
            if (row3.label && String(row3.label) === label) return row3
        }
        return null
    }
    function _stripperStatusColor(row) {
        if (!row) return "#526571"
        var st = String(row.status || "").toUpperCase()
        if (row.hasErrors   || st === "ERROR" || st === "FAIL") return "#b23b3b"
        if (row.hasWarnings || st === "WARN")                   return "#d6b74a"
        if (st === "OK")                                        return "#1a7a3c"
        return "#1c4ea7"
    }
    function _fmt0(x)  { var n = Number(x); return isFinite(n) ? Math.round(n).toString() : "—" }

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Text {
            anchors.centerIn: parent
            visible: !root.appState
            text: "No column selected"; font.pixelSize: 11; color: "#526571"
        }

        // ── Single-column layout: Draw Specifications (full width) ──────────
        // Solve / Status was previously a 26%-width sidebar on the right; it
        // has moved to the bottom of the Setup tab so this panel's full
        // width is now devoted to draws + the stripper sub-panel.
        // bottomMargin: 8 leaves room for the PGroupBox bottom etched border
        // to render fully — without it, the lower 1-2 px of the box was
        // being clipped against the PPropertyView page area edge.
        Item {
            anchors {
                left: parent.left; right: parent.right
                top: parent.top;   bottom: parent.bottom
                leftMargin: 4; rightMargin: 4
                topMargin: 4; bottomMargin: 8
            }
            visible: !!root.appState

            // ════════════════════════════════════════════════════════════════
            //  Draw Specifications — fills the entire panel
            // ════════════════════════════════════════════════════════════════
            PGroupBox {
                id: drawBox
                anchors.fill: parent
                caption: "Draw Specifications"
                contentPadding: 6
                fillContent: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 4

                    // ── Column header row ──────────────────────────────────
                    // Column widths are content-driven, not hardcoded — both
                    // header and row delegate cells bind to the *ColWidth
                    // properties at panel root. Each property is computed as
                    // Math.max(floor, probe.implicitWidth) where the probe is
                    // a hidden instance of the same control type holding the
                    // widest model item. Floors protect alignment when the
                    // model is short; probes protect against clipping when
                    // the model grows.
                    //
                    // Header alignment is centered for ALL columns (incl.
                    // Name and Value) for visual uniformity across the
                    // header strip — even though the data cells themselves
                    // align left (PTextField) or right (PGridValue numbers).
                    //
                    // Each non-Name column has BOTH preferredWidth and
                    // maximumWidth bound to the same property so the cell
                    // is exactly that width — no implicit-width drift. The
                    // Name column uses fillWidth + minimumWidth so it
                    // absorbs all remaining slack.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        RowLayout {
                            anchors.fill: parent
                            spacing: 4
                            Text { Layout.fillWidth: true; Layout.minimumWidth: root.nameColMinWidth
                                   text: "Name"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.trayColWidth; Layout.maximumWidth: root.trayColWidth
                                   text: "Tray"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.phaseColWidth; Layout.maximumWidth: root.phaseColWidth
                                   text: "Phase"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.basisColWidth; Layout.maximumWidth: root.basisColWidth
                                   text: "Basis"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.valueColWidth; Layout.maximumWidth: root.valueColWidth
                                   text: "Value"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.stripperColWidth; Layout.maximumWidth: root.stripperColWidth
                                   text: "Stripper"; font.pixelSize: 10; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignHCenter }
                            Text { Layout.preferredWidth: root.deleteColWidth; Layout.maximumWidth: root.deleteColWidth
                                   text: ""; font.pixelSize: 10 }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
                    }

                    // ── Draw spec rows ─────────────────────────────────────
                    ListView {
                        id: drawList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.appState ? root.appState.drawSpecs : []
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Item {
                            id: rowItem
                            width: drawList.width
                            height: 24

                            property var spec: modelData
                            property int rowIdx: index
                            readonly property bool isSelected: root.selectedDrawIndex === rowIdx

                            // Selection highlight strip behind the controls
                            Rectangle {
                                anchors.fill: parent
                                color: rowItem.isSelected ? "#dbe8f6" : "transparent"
                                z: 0
                            }

                            // Click-to-select catcher (does not intercept inner controls)
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root._activateRow(rowItem.rowIdx)
                                z: 0
                            }

                            // The 7-control draw-spec row.
                            // Widths are bound to the *ColWidth properties at
                            // panel root, which are the single source of truth
                            // for header + row column alignment. preferredWidth
                            // and maximumWidth are bound to the same property
                            // so the cell renders at exactly that width.
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                spacing: 4
                                z: 1

                                // 1) Name — PTextField (fills remaining width)
                                PTextField {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: root.nameColMinWidth
                                    Layout.preferredHeight: 22
                                    horizontalAlignment: Text.AlignLeft
                                    text: rowItem.spec.name || ""
                                    onActiveFocusChanged: { if (activeFocus) root._activateRow(rowItem.rowIdx) }
                                    onEditingFinished: root._setSpec(rowItem.rowIdx, "name", text)
                                }

                                // 2) Tray — PSpinner. Editing or stepping the
                                // value also activates this row, matching the
                                // legacy CSpin's onValueModified behaviour.
                                PSpinner {
                                    Layout.preferredWidth: root.trayColWidth
                                    Layout.maximumWidth:   root.trayColWidth
                                    Layout.minimumWidth:   root.trayColWidth
                                    Layout.preferredHeight: 22
                                    from: 2
                                    to:   root.appState ? Math.max(2, root.appState.trays - 1) : 30
                                    value: Number(rowItem.spec.tray || 2)
                                    onActiveFocusChanged: { if (activeFocus) root._activateRow(rowItem.rowIdx) }
                                    onEdited: function(v) {
                                        root._activateRow(rowItem.rowIdx)
                                        root._setSpec(rowItem.rowIdx, "tray", v)
                                    }
                                }

                                // 3) Phase — PComboBox (L / V).
                                PComboBox {
                                    Layout.preferredWidth: root.phaseColWidth
                                    Layout.maximumWidth:   root.phaseColWidth
                                    Layout.minimumWidth:   root.phaseColWidth
                                    Layout.preferredHeight: 22
                                    minimumContentWidth: 0
                                    model: ["L", "V"]
                                    currentIndex: (rowItem.spec.phase === "V") ? 1 : 0
                                    onActivated: function(i) {
                                        root._activateRow(rowItem.rowIdx)
                                        root._setSpec(rowItem.rowIdx, "phase", model[i])
                                    }
                                }

                                // 4) Basis — PComboBox (feedPct / kg/h).
                                PComboBox {
                                    Layout.preferredWidth: root.basisColWidth
                                    Layout.maximumWidth:   root.basisColWidth
                                    Layout.minimumWidth:   root.basisColWidth
                                    Layout.preferredHeight: 22
                                    minimumContentWidth: 0
                                    model: ["feedPct", "kg/h"]
                                    currentIndex: (rowItem.spec.basis === "kg/h") ? 1 : 0
                                    onActivated: function(i) {
                                        root._activateRow(rowItem.rowIdx)
                                        root._setSpec(rowItem.rowIdx, "basis", model[i])
                                    }
                                }

                                // 5) Value — PGridValue (numeric, dimensionless — basis is in col 4)
                                PGridValue {
                                    Layout.preferredWidth: root.valueColWidth
                                    Layout.maximumWidth:   root.valueColWidth
                                    Layout.minimumWidth:   root.valueColWidth
                                    Layout.preferredHeight: 22
                                    quantity: "Dimensionless"
                                    decimals: 2
                                    siValue: Number(rowItem.spec.value !== undefined ? rowItem.spec.value : 0)
                                    editable: true
                                    onEdited: function(siVal) {
                                        root._activateRow(rowItem.rowIdx)
                                        root._setSpec(rowItem.rowIdx, "value", siVal)
                                    }
                                }

                                // 6) Stripper toggle — green "Stripper On" when active.
                                // Matches original DistillationColumn.qml exactly:
                                //   off  →  "Stripper" in muted grey
                                //   on   →  "Stripper On" in HYSYS green (#1a7a3c)
                                //          on a pale-green fill (#edf5ea) with a
                                //          green border (#7aa46d).
                                PButton {
                                    Layout.preferredWidth: root.stripperColWidth
                                    Layout.maximumWidth:   root.stripperColWidth
                                    Layout.minimumWidth:   root.stripperColWidth
                                    Layout.preferredHeight: 22
                                    text: Boolean(rowItem.spec.stripperEnabled) ? "Stripper On" : "Stripper"
                                    fontPixelSize: 10
                                    contentHPadding: 4
                                    baseColor: Boolean(rowItem.spec.stripperEnabled) ? "#edf5ea" : "#d3d8de"
                                    hoverColor: Boolean(rowItem.spec.stripperEnabled) ? "#d9eed3" : "#dbe0e5"
                                    pressedColor: Boolean(rowItem.spec.stripperEnabled) ? "#bedab8" : "#c8d0d8"
                                    textColor: Boolean(rowItem.spec.stripperEnabled) ? "#1a7a3c" : "#526571"
                                    onClicked: root._toggleStripper(rowItem.rowIdx)
                                }

                                // 7) Delete — PButton in icon mode
                                PButton {
                                    Layout.preferredWidth: root.deleteColWidth
                                    Layout.maximumWidth:   root.deleteColWidth
                                    Layout.minimumWidth:   root.deleteColWidth
                                    Layout.preferredHeight: 22
                                    minButtonWidth: 22
                                    contentHPadding: 4
                                    iconText: "✕"
                                    iconColor: "#c5422c"
                                    iconFontSize: 12
                                    onClicked: root._deleteRow(rowItem.rowIdx)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !root.appState || !root.appState.drawSpecs || root.appState.drawSpecs.length === 0
                            text: "No draws — click + Add Draw to create one"
                            color: "#526571"; font.pixelSize: 11; font.italic: true
                        }
                    }

                    // ── Stripper sub-panel (visible when activeStripperIndex >= 0) ──
                    PGroupBox {
                        id: stripperBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? implicitHeight : 0
                        visible: root.activeStripperIndex >= 0
                                 && root.appState
                                 && root.appState.drawSpecs
                                 && root.appState.drawSpecs.length > root.activeStripperIndex
                        caption: "Attached Side Stripper"
                        contentPadding: 8

                        // The selected draw spec (kept stable as activeStripperIndex changes)
                        property var selectedSpec: visible
                            ? root.appState.drawSpecs[root.activeStripperIndex]
                            : null

                        // The matching attached-stripper run result, or null if
                        // the column has not been solved (or no result matched).
                        // Drives visibility of the Stripper Run Results sub-panel.
                        property var selectedResult: selectedSpec
                            ? root._attachedStripperForSpec(selectedSpec)
                            : null

                        function _commitField(key, value) {
                            if (root.activeStripperIndex < 0) return
                            root._setSpec(root.activeStripperIndex, key, value)
                        }

                        ColumnLayout {
                            width: stripperBox.width - (stripperBox.contentPadding * 2) - 2
                            spacing: 8

                            // ── Config grid ─────────────────────────────────
                            // Spinner widths (56) and Value widths (90) match
                            // the draw spec row above for visual consistency.
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 4; columnSpacing: 4; rowSpacing: 0

                                // Label
                                PGridLabel { Layout.preferredWidth: 100; text: "Label" }
                                PTextField {
                                    Layout.columnSpan: 3
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    horizontalAlignment: Text.AlignLeft
                                    text: stripperBox.selectedSpec
                                          ? (stripperBox.selectedSpec.stripperLabel
                                             || ((stripperBox.selectedSpec.name || "Draw") + " Stripper"))
                                          : ""
                                    onEditingFinished: stripperBox._commitField("stripperLabel", text)
                                }

                                // Trays | Return Tray
                                PGridLabel { Layout.preferredWidth: 100; text: "Trays"; alt: true }
                                PSpinner {
                                    Layout.preferredWidth: 56
                                    Layout.maximumWidth: 56
                                    Layout.minimumWidth: 56
                                    from: 2; to: 20
                                    value: stripperBox.selectedSpec && stripperBox.selectedSpec.stripperTrays
                                           ? Number(stripperBox.selectedSpec.stripperTrays) : 4
                                    onEdited: function(v) { stripperBox._commitField("stripperTrays", v) }
                                }
                                PGridLabel { Layout.preferredWidth: 100; text: "Return Tray"; alt: true }
                                PSpinner {
                                    Layout.preferredWidth: 56
                                    Layout.maximumWidth: 56
                                    Layout.minimumWidth: 56
                                    from: 2
                                    to:   root.appState ? Math.max(2, root.appState.trays - 1) : 30
                                    value: {
                                        var sp = stripperBox.selectedSpec
                                        if (sp && sp.stripperReturnTray) return Number(sp.stripperReturnTray)
                                        return Math.max(2, Number(sp && sp.tray ? sp.tray : 2) - 1)
                                    }
                                    onEdited: function(v) { stripperBox._commitField("stripperReturnTray", v) }
                                }

                                // Heat Mode | Heat Value (unit label depends on mode)
                                PGridLabel { Layout.preferredWidth: 100; text: "Heat Mode" }
                                PComboBox {
                                    Layout.preferredWidth: 110
                                    Layout.preferredHeight: 22
                                    model: ["Steam", "ReboilerDuty"]
                                    currentIndex: (stripperBox.selectedSpec
                                                   && stripperBox.selectedSpec.stripperHeatMode === "ReboilerDuty") ? 1 : 0
                                    onActivated: function(i) { stripperBox._commitField("stripperHeatMode", model[i]) }
                                }
                                // Heat Value cell pair: numeric value (90 px,
                                // matching draw row Value width) + unit suffix
                                // that switches between "kW" (for ReboilerDuty
                                // mode) and "kg/h steam" (for Steam mode).
                                //
                                // Note: a true PGridUnit isn't used here
                                // because the stored stripperHeatValue is a
                                // raw mode-dependent number, not an SI
                                // quantity. PGridUnit assumes the value is in
                                // SI and the unit is a display preference;
                                // here the unit *is* the meaning. So we use a
                                // static Text label that mirrors PGridUnit's
                                // visual style (small, muted).
                                Item {
                                    Layout.preferredHeight: 22
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4
                                        PGridLabel {
                                            Layout.preferredWidth: 78
                                            text: "Heat Value"
                                        }
                                        PGridValue {
                                            Layout.preferredWidth: 90
                                            Layout.maximumWidth: 90
                                            Layout.minimumWidth: 90
                                            quantity: "Dimensionless"
                                            decimals: 2
                                            siValue: stripperBox.selectedSpec
                                                     && stripperBox.selectedSpec.stripperHeatValue !== undefined
                                                     ? Number(stripperBox.selectedSpec.stripperHeatValue) : 0
                                            editable: true
                                            onEdited: function(v) { stripperBox._commitField("stripperHeatValue", v) }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: (stripperBox.selectedSpec
                                                   && stripperBox.selectedSpec.stripperHeatMode === "ReboilerDuty")
                                                  ? "kW" : "kg/h steam"
                                            font.pixelSize: 10
                                            color: "#526571"
                                        }
                                    }
                                }

                                // Max Coupled Iter | Coupling Tol (text, scientific)
                                PGridLabel { Layout.preferredWidth: 100; text: "Max Coupled Iter"; alt: true }
                                PSpinner {
                                    Layout.preferredWidth: 56
                                    Layout.maximumWidth: 56
                                    Layout.minimumWidth: 56
                                    from: 1; to: 200
                                    value: stripperBox.selectedSpec
                                           && stripperBox.selectedSpec.stripperMaxCoupledIterations
                                           ? Number(stripperBox.selectedSpec.stripperMaxCoupledIterations) : 25
                                    onEdited: function(v) { stripperBox._commitField("stripperMaxCoupledIterations", v) }
                                }
                                PGridLabel { Layout.preferredWidth: 100; text: "Coupling Tol"; alt: true }
                                PTextField {
                                    Layout.preferredWidth: 90
                                    Layout.maximumWidth: 90
                                    Layout.minimumWidth: 90
                                    Layout.preferredHeight: 22
                                    horizontalAlignment: Text.AlignRight
                                    text: stripperBox.selectedSpec
                                          && stripperBox.selectedSpec.stripperCouplingTolerance !== undefined
                                          ? Number(stripperBox.selectedSpec.stripperCouplingTolerance).toExponential(3)
                                          : "1.000e-3"
                                    onEditingFinished: {
                                        var n = Number(text)
                                        if (isFinite(n)) stripperBox._commitField("stripperCouplingTolerance", n)
                                    }
                                }

                                // Return Damping (90 px to match draw row Value)
                                PGridLabel { Layout.preferredWidth: 100; text: "Return Damping" }
                                PGridValue {
                                    Layout.columnSpan: 3
                                    Layout.preferredWidth: 90
                                    Layout.maximumWidth: 90
                                    Layout.minimumWidth: 90
                                    quantity: "Dimensionless"
                                    decimals: 3
                                    siValue: stripperBox.selectedSpec
                                             && stripperBox.selectedSpec.stripperReturnDamping !== undefined
                                             ? Number(stripperBox.selectedSpec.stripperReturnDamping) : 0.35
                                    editable: true
                                    onEdited: function(v) { stripperBox._commitField("stripperReturnDamping", v) }
                                }
                            } // config grid

                            // ── Stripper Run Results (only visible after a solve) ──
                            // Mirrors the original DistillationColumn.qml's results
                            // sub-panel: 5 rows × 3 triplets of post-solve numbers
                            // from the matched attached-stripper. The whole block
                            // stays hidden until _attachedStripperForSpec returns
                            // a row.
                            //
                            // Layout: 9 columns of [label | value | unit] triplets.
                            // Unit-bearing values (kg/h flows, K temperatures, Pa
                            // pressures) use real PGridValue + PGridUnit pairs so
                            // they participate in the global Unit Set selector.
                            // Dimensionless values (status string, ratios, counts,
                            // Yes/No) keep isText: true with an empty Item filler
                            // in the unit column to maintain grid alignment.
                            PGroupBox {
                                id: stripperResultsBox
                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? implicitHeight : 0
                                visible: !!stripperBox.selectedResult
                                caption: "Stripper Run Results"
                                contentPadding: 8

                                GridLayout {
                                    width: stripperResultsBox.width - (stripperResultsBox.contentPadding * 2) - 2
                                    columns: 8
                                    columnSpacing: 4
                                    rowSpacing: 0

                                    // Layout strategy: triplet 1 holds only
                                    // dimensionless cells (Status, Tol,
                                    // Source/Return, Solve Conv, Residual)
                                    // so it has NO unit column at all —
                                    // saving 36 + 4 = 40 px of horizontal
                                    // space that was previously wasted on
                                    // empty placeholder Items. Triplets 2
                                    // and 3 keep their unit columns since
                                    // every numeric quantity in those
                                    // triplets carries a real unit.
                                    //
                                    // Per-triplet label widths are sized to
                                    // the widest text in that triplet's
                                    // column rather than a uniform 86 px,
                                    // which freed ~44 px of horizontal
                                    // budget vs. the previous version:
                                    //
                                    //   Triplet 1 widest: "Source/Return" → 84 px
                                    //   Triplet 2 widest: "Vapor Return"  → 78 px
                                    //   Triplet 3 widest: "Diagnostics"   → 70 px
                                    //
                                    // Total budget:
                                    //   84+90 + 78+90+36 + 70+90+36 = 574 px
                                    //   plus 7 × 4 px gaps           =  28 px
                                    //   total                         = 602 px
                                    // Comfortably fits the ~646 px content
                                    // area, with room to spare.
                                    //
                                    // Row contents (Vapor Return swapped
                                    // with Tol so all unit-bearing values
                                    // land in triplets 2/3):
                                    //   Row 1: Status         | Feed   (kg/h) | Bottoms  (kg/h)
                                    //   Row 2: Tol            | Top T  (K)    | Bottom T (K)
                                    //   Row 3: Source/Return  | Pressure (Pa) | Diagnostics
                                    //   Row 4: Solve Conv     | Coupled       | Iterations
                                    //   Row 5: Residual       | Vapor Return (kg/h) | Mode

                                    // ── Row 1: Status | Feed | Bottoms ──
                                    PGridLabel { Layout.preferredWidth: 84; Layout.minimumWidth: 84; text: "Status" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        alignText: "left"
                                        textValue: stripperBox.selectedResult
                                                   ? String(stripperBox.selectedResult.status || "—") : "—"
                                        valueColor: root._stripperStatusColor(stripperBox.selectedResult)
                                    }

                                    PGridLabel { Layout.preferredWidth: 78; Layout.minimumWidth: 78; text: "Feed" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.feedKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                    }
                                    PGridUnit {
                                        Layout.preferredWidth: 36
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.feedKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                        onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                                    }

                                    PGridLabel { Layout.preferredWidth: 70; Layout.minimumWidth: 70; text: "Bottoms" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.bottomsProductKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                    }
                                    PGridUnit {
                                        Layout.preferredWidth: 36
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.bottomsProductKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                        onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                                    }

                                    // ── Row 2: Tol | Top T | Bottom T ──
                                    PGridLabel { Layout.preferredWidth: 84; Layout.minimumWidth: 84; text: "Tol"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: stripperBox.selectedResult
                                                   ? Number(stripperBox.selectedResult.couplingTolerance).toExponential(3)
                                                   : "—"
                                    }

                                    PGridLabel { Layout.preferredWidth: 78; Layout.minimumWidth: 78; text: "Top T"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "Temperature"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.topTemperatureK) : NaN
                                        displayUnit: root.unitFor("Temperature")
                                    }
                                    PGridUnit {
                                        alt: true
                                        Layout.preferredWidth: 36
                                        quantity: "Temperature"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.topTemperatureK) : NaN
                                        displayUnit: root.unitFor("Temperature")
                                        onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                    }

                                    PGridLabel { Layout.preferredWidth: 70; Layout.minimumWidth: 70; text: "Bottom T"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "Temperature"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.bottomTemperatureK) : NaN
                                        displayUnit: root.unitFor("Temperature")
                                    }
                                    PGridUnit {
                                        alt: true
                                        Layout.preferredWidth: 36
                                        quantity: "Temperature"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.bottomTemperatureK) : NaN
                                        displayUnit: root.unitFor("Temperature")
                                        onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                    }

                                    // ── Row 3: Source/Return | Pressure | Diagnostics ──
                                    PGridLabel { Layout.preferredWidth: 84; Layout.minimumWidth: 84; text: "Source/Return" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: stripperBox.selectedResult
                                                   ? (String(stripperBox.selectedResult.sourceTray) + " / "
                                                      + String(stripperBox.selectedResult.returnTray)) : "—"
                                    }

                                    PGridLabel { Layout.preferredWidth: 78; Layout.minimumWidth: 78; text: "Pressure" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "Pressure"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.topPressurePa) : NaN
                                        displayUnit: root.unitFor("Pressure")
                                    }
                                    PGridUnit {
                                        Layout.preferredWidth: 36
                                        quantity: "Pressure"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.topPressurePa) : NaN
                                        displayUnit: root.unitFor("Pressure")
                                        onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                    }

                                    PGridLabel { Layout.preferredWidth: 70; Layout.minimumWidth: 70; text: "Diagnostics" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: stripperBox.selectedResult
                                                   ? String(stripperBox.selectedResult.diagnosticCount || 0) : "0"
                                    }
                                    Item { Layout.preferredWidth: 36; Layout.preferredHeight: 22 }

                                    // ── Row 4: Solve Conv | Coupled | Iterations ──
                                    PGridLabel { Layout.preferredWidth: 84; Layout.minimumWidth: 84; text: "Solve Conv"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: {
                                            var r = stripperBox.selectedResult
                                            if (!r) return "—"
                                            if (r.solveConverged === undefined) return "—"
                                            return r.solveConverged ? "Yes" : "No"
                                        }
                                    }

                                    PGridLabel { Layout.preferredWidth: 78; Layout.minimumWidth: 78; text: "Coupled"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: {
                                            var r = stripperBox.selectedResult
                                            if (!r) return "—"
                                            if (r.coupledConverged === undefined) return "—"
                                            return r.coupledConverged ? "Yes" : "No"
                                        }
                                    }
                                    Item { Layout.preferredWidth: 36; Layout.preferredHeight: 22 }

                                    PGridLabel { Layout.preferredWidth: 70; Layout.minimumWidth: 70; text: "Iterations"; alt: true }
                                    PGridValue {
                                        alt: true
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: stripperBox.selectedResult
                                                   ? (String(stripperBox.selectedResult.coupledIterationsCompleted || 0)
                                                      + "/" + String(stripperBox.selectedResult.maxCoupledIterations || 0))
                                                   : "—"
                                    }
                                    Item { Layout.preferredWidth: 36; Layout.preferredHeight: 22 }

                                    // ── Row 5: Residual | Vapor Return | Mode ──
                                    PGridLabel { Layout.preferredWidth: 84; Layout.minimumWidth: 84; text: "Residual" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        textValue: stripperBox.selectedResult
                                                   ? root._fmt3(stripperBox.selectedResult.coupledResidual) : "—"
                                    }

                                    PGridLabel { Layout.preferredWidth: 78; Layout.minimumWidth: 78; text: "Vapor Return" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.vaporReturnKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                    }
                                    PGridUnit {
                                        Layout.preferredWidth: 36
                                        quantity: "MassFlow"
                                        siValue: stripperBox.selectedResult
                                                 ? Number(stripperBox.selectedResult.vaporReturnKgph) / 3600.0 : NaN
                                        displayUnit: root.unitFor("MassFlow")
                                        onUnitOverride: function(u) { root.setUnit("MassFlow", u) }
                                    }

                                    PGridLabel { Layout.preferredWidth: 70; Layout.minimumWidth: 70; text: "Mode" }
                                    PGridValue {
                                        Layout.preferredWidth: 90
                                        Layout.maximumWidth: 90
                                        Layout.minimumWidth: 90
                                        isText: true
                                        alignText: "left"
                                        textValue: stripperBox.selectedResult
                                                   ? String(stripperBox.selectedResult.coupledMode || "—") : "—"
                                    }
                                    Item { Layout.preferredWidth: 36; Layout.preferredHeight: 22 }
                                } // results grid
                            } // stripperResultsBox
                        } // ColumnLayout for stripper config + results
                    } // stripperBox

                    // ── Footer: Add / Reset / Total ────────────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#97a2ad" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.topMargin: 4
                            spacing: 6

                            PButton {
                                text: "+ Add Draw"
                                fontPixelSize: 11
                                contentHPadding: 10
                                onClicked: root._addRow()
                            }
                            PButton {
                                text: "Reset"
                                fontPixelSize: 11
                                contentHPadding: 10
                                onClicked: {
                                    if (root.appState) {
                                        root.selectedDrawIndex = -1
                                        root.activeStripperIndex = -1
                                        root.appState.resetDrawSpecsToDefaults()
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    var t = root._totalTargetPct()
                                    return "Total: " + t.toFixed(1) + "%  ("
                                           + Math.round(t * root._feedKgph() / 100) + " kg/h)"
                                }
                                font.pixelSize: 10
                                color: "#526571"
                            }
                        }
                    }
                }
            } // drawBox
        } // outer Item
    }
}
