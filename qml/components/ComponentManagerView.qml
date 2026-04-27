import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../common" as Common

// ─────────────────────────────────────────────────────────────────────────────
//  ComponentManagerView.qml  (Level B refactor — HYSYS-style PPropertyView)
//
//  Layout:
//    PPropertyView (raised outer frame + tab strip + sunken page area)
//      ├── Components tab   — Actions PGroupBox + Left list panel + Worksheet panel
//      └── Component Lists tab — Actions PGroupBox + Saved Lists + List Builder
//
//  P-control vocabulary:
//    • PButton / PCheckBox / PTextField / PComboBox      — chiseled controls
//    • PGroupBox (child-sized)                           — form sections (default)
//    • PGroupBox { fillContent: true }                   — container for ListView/PSpreadsheet
//    • PSpreadsheet                                      — property worksheet grid
//    • PListItem                                         — beveled ListView delegate
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var manager: gComponentManager

    // Emitted when the user, via a Delete Error → confirm flow, asks to
    // navigate to a fluid package that's blocking deletion of a component
    // list. Owned by PfdMainView, which closes the Component Manager and
    // opens the Fluid Manager with `packageId` selected.
    signal navigateToFluidPackage(string packageId)

    // ── Tab state (plain int — owned by root, not read from tabsHeader) ──────
    property int currentTab: 0

    // ── Components tab state ────────────────────────────────────────────────
    property var filteredComponents: []
    property string selectedComponentId: ""
    property var selectedComponent: ({})

    // ── Component Lists tab state ───────────────────────────────────────────
    property var componentListsCache: []
    property string selectedListId: ""
    property var selectedList: ({})
    property var availableComponentsForList: []
    property var memberComponentsForList: []
    property string selectedAvailableComponentId: ""
    property string selectedMemberComponentId: ""
    property var selectedAvailableComponentIds: []
    property var selectedMemberComponentIds: []
    property int availableSelectionAnchorIndex: -1
    property int memberSelectionAnchorIndex: -1

    // ── Status message (surfaced in PPropertyView's right accessory) ────────
    property string statusMessage: ""

    // ── Per-quantity unit overrides (empty = use active Unit Set default) ───
    property var unitOverrides: ({
        "Temperature": "",
        "Pressure":    "",
        "MolarMass":   ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    // ── Draft component — the editable form state bound to PGridValue rows ─
    // Numeric fields are kept in SI units so PGridValue bindings work directly:
    //   molarMassKgPerMol  : SI for MolarMass (kg/mol). Storage uses kg/kmol,
    //                        so multiply by 1000 when saving.
    //   tbK, tcK           : Temperature in K (already SI)
    //   pcPa               : Pressure in Pa (already SI)
    //   critVolM3PerKmol   : Kept as stored (dimensionless for unit system)
    property var draftComponent: ({})

    function _siMolarMassFromKgKmol(kgkmol) {
        return isFinite(kgkmol) ? kgkmol * 0.001 : NaN
    }
    function _kgKmolFromSiMolarMass(siKgPerMol) {
        return isFinite(siKgPerMol) ? siKgPerMol * 1000.0 : NaN
    }

    // Populate draftComponent from a component object
    function loadDraftFromComponent(c) {
        c = c || {}
        draftComponent = {
            id:                     String(c.id || ""),
            name:                   String(c.name || ""),
            formula:                String(c.formula || ""),
            cas:                    String(c.cas || ""),
            family:                 String(c.family || ""),
            componentType:          String(c.componentType || ""),
            aliases:                c.aliases ? c.aliases.join(", ") : "",
            tags:                   c.tags ? c.tags.join(", ") : "",
            phaseCapabilities:      c.phaseCapabilities ? c.phaseCapabilities.join(", ") : "",
            source:                 String(c.source || ""),
            // Numeric fields — stored SI-ready for PGridValue
            molarMassSi:            _siMolarMassFromKgKmol(Number(c.molarMass)),
            tbK:                    Number(c.normalBoilingPointK),
            tcK:                    Number(c.criticalTemperatureK),
            pcPa:                   Number(c.criticalPressurePa),
            acentricFactor:         Number(c.acentricFactor),
            critVolM3PerKmol:       Number(c.criticalVolumeM3PerKmol),
            critCompressibility:    Number(c.criticalCompressibility),
            sg60F:                  Number(c.specificGravity60F),
            watsonK:                Number(c.watsonK),
            volumeShiftDelta:       Number(c.volumeShiftDelta)
        }
    }

    // Update a single field in draftComponent (keeps reactivity)
    function _setDraft(key, value) {
        var copy = Object.assign({}, draftComponent)
        copy[key] = value
        draftComponent = copy
    }

    implicitWidth: 980
    implicitHeight: 720
    focus: true

    // ───────────────────────────────────────────────────────────────────────
    //  Helper / data functions (unchanged from original)
    // ───────────────────────────────────────────────────────────────────────

    function fmt(v, digits) {
        if (v === undefined || v === null || v === "") return ""
        const n = Number(v)
        if (isNaN(n)) return String(v)
        return n.toFixed(digits === undefined ? 6 : digits)
    }

    function parseNum(text) {
        const t = (text || "").trim()
        if (t === "") return null
        const v = Number(t)
        return isNaN(v) ? null : v
    }

    function familyOptions() {
        const out = ["All families"]
        if (manager && manager.componentFamilies) {
            for (let i = 0; i < manager.componentFamilies.length; ++i)
                out.push(manager.componentFamilies[i])
        }
        return out
    }

    function familyValueFromText(text) {
        if (!text || text === "All families") return ""
        return text
    }

    function currentFamilyValue(combo) {
        return familyValueFromText(combo ? combo.currentText : "")
    }

    // (rowMeta, rowValueFromComponent, worksheetValue, loadWorksheetFromComponent
    //  are obsolete — replaced by draftComponent + loadDraftFromComponent above)

    function refreshComponentResults(preferredId, familyOverride) {
        if (!manager) return
        filteredComponents = manager.findComponents(componentSearch.text, familyOverride !== undefined ? familyValueFromText(familyOverride) : currentFamilyValue(componentFamilyCombo), componentIncludePseudo.checked)
        let target = preferredId || selectedComponentId
        let found = false
        for (let i = 0; i < filteredComponents.length; ++i) {
            if (filteredComponents[i].id === target) { found = true; break }
        }
        if (!found) target = filteredComponents.length > 0 ? filteredComponents[0].id : ""
        selectedComponentId = target
        selectedComponent = target ? manager.getComponent(target) : ({})
        loadDraftFromComponent(selectedComponent)
        try { notesArea.text = selectedComponent && selectedComponent.notes ? selectedComponent.notes : "" } catch (e) {}
        root.statusMessage = manager.lastLoadStatus && manager.lastLoadStatus !== ""
                             ? manager.lastLoadStatus
                             : (filteredComponents.length + " components shown")
    }

    function saveSelectedComponent() {
        if (!manager) return
        const d = draftComponent
        function splitCsv(t) {
            return (t && t.trim() !== "") ? t.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 }) : []
        }
        const out = {
            id: d.id,
            name: d.name,
            formula: d.formula,
            cas: d.cas,
            family: d.family,
            componentType: d.componentType,
            aliases: splitCsv(d.aliases),
            tags: splitCsv(d.tags),
            phaseCapabilities: splitCsv(d.phaseCapabilities),
            molarMass: isFinite(d.molarMassSi) ? _kgKmolFromSiMolarMass(d.molarMassSi) : null,
            normalBoilingPointK: isFinite(d.tbK) ? d.tbK : null,
            criticalTemperatureK: isFinite(d.tcK) ? d.tcK : null,
            criticalPressurePa: isFinite(d.pcPa) ? d.pcPa : null,
            acentricFactor: isFinite(d.acentricFactor) ? d.acentricFactor : null,
            criticalVolumeM3PerKmol: isFinite(d.critVolM3PerKmol) ? d.critVolM3PerKmol : null,
            criticalCompressibility: isFinite(d.critCompressibility) ? d.critCompressibility : null,
            specificGravity60F: isFinite(d.sg60F) ? d.sg60F : null,
            watsonK: isFinite(d.watsonK) ? d.watsonK : null,
            volumeShiftDelta: isFinite(d.volumeShiftDelta) ? d.volumeShiftDelta : null,
            source: d.source,
            notes: notesArea.text
        }
        manager.addOrUpdateComponent(out)
        refreshComponentResults(out.id)
        root.statusMessage = "Saved component: " + (out.name || out.id)
    }

    function refreshComponentLists(preferredId) {
        componentListsCache = manager ? manager.listComponentLists() : []
        let target = preferredId || selectedListId
        let found = false
        for (let i = 0; i < componentListsCache.length; ++i) {
            if (componentListsCache[i].id === target) { found = true; break }
        }
        if (!found) target = componentListsCache.length > 0 ? componentListsCache[0].id : ""
        selectedListId = target
        selectedList = target && manager ? manager.getComponentList(target) : ({})
        listNameField.text = selectedList && selectedList.name ? selectedList.name : ""
        listNotesArea.text = selectedList && selectedList.notes ? selectedList.notes : ""
        refreshListMembership()
        refreshAvailableComponentsForList()
    }

    function refreshListMembership() {
        memberComponentsForList = (manager && selectedListId !== "") ? manager.resolvedComponentsForList(selectedListId) : []
        const existingSelection = []
        for (let i = 0; i < memberComponentsForList.length; ++i) {
            if (selectionContains(selectedMemberComponentIds, memberComponentsForList[i].id))
                existingSelection.push(memberComponentsForList[i].id)
        }
        selectedMemberComponentIds = existingSelection
        if (selectedMemberComponentIds.length > 0)
            selectedMemberComponentId = selectedMemberComponentIds[selectedMemberComponentIds.length - 1]
        else
            selectedMemberComponentId = memberComponentsForList.length > 0 ? memberComponentsForList[0].id : ""
        if (selectedMemberComponentId !== "" && !selectionContains(selectedMemberComponentIds, selectedMemberComponentId))
            selectedMemberComponentIds = [selectedMemberComponentId]
        if (selectedMemberComponentId === "")
            memberSelectionAnchorIndex = -1
    }

    function selectedListPseudoSources() {
        const out = []
        const seen = {}
        for (let i = 0; i < memberComponentsForList.length; ++i) {
            const c = memberComponentsForList[i]
            const src = c && c.source ? String(c.source) : ""
            if (src.indexOf("pseudo-fluid:") !== 0) continue
            if (!seen[src]) {
                seen[src] = true
                out.push(src)
            }
        }
        return out
    }

    function refreshAvailableComponentsForList(familyOverride) {
        if (!manager) {
            availableComponentsForList = []
            return
        }

        const family = familyOverride !== undefined ? familyValueFromText(familyOverride) : currentFamilyValue(listFamilyCombo)
        const familyNorm = family ? String(family).trim().toLowerCase() : ""
        const pseudoSources = selectedListPseudoSources()
        const includeSelectedCrudePseudo = pseudoSources.length > 0
        const allMatches = manager.findComponents(listSearch.text, "", true)
        const filtered = []

        for (let i = 0; i < allMatches.length; ++i) {
            const c = allMatches[i]
            const isPseudo = !!(c && c.isPseudoComponent)
            const source = c && c.source ? String(c.source) : ""
            const componentFamily = c && c.family ? String(c.family).trim().toLowerCase() : ""

            if (isPseudo) {
                if (!includeSelectedCrudePseudo) continue
                if (pseudoSources.indexOf(source) < 0) continue
                filtered.push(c)
                continue
            }

            if (familyNorm === "pseudo-fraction") continue
            if (familyNorm !== "" && componentFamily !== familyNorm) continue
            filtered.push(c)
        }

        availableComponentsForList = filtered
        const existingSelection = []
        for (let i = 0; i < availableComponentsForList.length; ++i) {
            if (selectionContains(selectedAvailableComponentIds, availableComponentsForList[i].id))
                existingSelection.push(availableComponentsForList[i].id)
        }
        selectedAvailableComponentIds = existingSelection
        if (selectedAvailableComponentIds.length > 0)
            selectedAvailableComponentId = selectedAvailableComponentIds[selectedAvailableComponentIds.length - 1]
        else
            selectedAvailableComponentId = availableComponentsForList.length > 0 ? availableComponentsForList[0].id : ""
        if (selectedAvailableComponentId !== "" && !selectionContains(selectedAvailableComponentIds, selectedAvailableComponentId))
            selectedAvailableComponentIds = [selectedAvailableComponentId]
        if (selectedAvailableComponentId === "")
            availableSelectionAnchorIndex = -1
    }

    function selectionContains(ids, idValue) {
        return ids.indexOf(idValue) >= 0
    }

    // ── Delete Error flow ──────────────────────────────────────────────────
    // Component delete: if blocked by lists, show dialog. Clicking a list
    // name jumps to the Component Lists tab and highlights the offending
    // component within the list's members panel.
    function attemptDeleteComponent() {
        if (!manager || selectedComponentId === "") return
        const blockingLists = manager.componentListsUsingComponent(selectedComponentId)
        if (blockingLists.length === 0) {
            manager.removeComponent(selectedComponentId)
            return
        }
        const compInfo = manager.getComponent(selectedComponentId)
        const compName = (compInfo && compInfo.name) ? compInfo.name : selectedComponentId
        deleteErrorDialog.context = "component"
        deleteErrorDialog.componentIdToHighlight = selectedComponentId
        deleteErrorDialog.message = "Cannot delete component '" + compName
            + "':\nit is being used by the following component list(s).\n\nClick a list name to navigate to it."
        deleteErrorDialog.items = blockingLists
        deleteErrorDialog.open()
    }

    // Component-list delete: if blocked by fluid packages, show dialog.
    // Clicking a package name shows a Confirm dialog; on Yes, emit
    // navigateToFluidPackage so PfdMainView can close us and open Fluid
    // Manager with the right package selected.
    function attemptDeleteComponentList() {
        if (!manager || selectedListId === "") return
        const blockingPackages = manager.fluidPackagesUsingComponentList(selectedListId)
        if (blockingPackages.length === 0) {
            manager.removeComponentList(selectedListId)
            return
        }
        const listInfo = manager.getComponentList(selectedListId)
        const listName = (listInfo && listInfo.name) ? listInfo.name : selectedListId
        deleteErrorDialog.context = "list"
        deleteErrorDialog.componentIdToHighlight = ""
        deleteErrorDialog.message = "Cannot delete component list '" + listName
            + "':\nit is being used by the following fluid package(s).\n\nClick a package name to navigate to it."
        deleteErrorDialog.items = blockingPackages
        deleteErrorDialog.open()
    }

    // Resolves a fluid-package display name back to its id (since the dialog
    // shows names but FluidManagerView needs an id to select). Returns "" on
    // miss.
    function fluidPackageIdForName(name) {
        if (!gFluidPackageManager) return ""
        const pkgs = gFluidPackageManager.listFluidPackages()
        for (let i = 0; i < pkgs.length; ++i) {
            const p = pkgs[i]
            if (p && (p.name === name || p.id === name)) return p.id
        }
        return ""
    }

    // Resolves a component-list display name back to its id.
    function componentListIdForName(name) {
        if (!manager) return ""
        const lists = manager.listComponentLists()
        for (let i = 0; i < lists.length; ++i) {
            const l = lists[i]
            if (l && (l.name === name || l.id === name)) return l.id
        }
        return ""
    }

    function selectionIndexesToIds(items, startIndex, endIndex) {
        const out = []
        if (!items || items.length === 0) return out
        const lo = Math.max(0, Math.min(startIndex, endIndex))
        const hi = Math.min(items.length - 1, Math.max(startIndex, endIndex))
        for (let i = lo; i <= hi; ++i) {
            if (items[i] && items[i].id !== undefined)
                out.push(items[i].id)
        }
        return out
    }

    function handleAvailableSelection(clickedIndex, mouse) {
        const clicked = availableComponentsForList[clickedIndex]
        if (!clicked) return
        const clickedId = clicked.id
        const ctrl = !!(mouse.modifiers & Qt.ControlModifier)
        const shift = !!(mouse.modifiers & Qt.ShiftModifier)

        if (shift) {
            const anchor = availableSelectionAnchorIndex >= 0 ? availableSelectionAnchorIndex : clickedIndex
            selectedAvailableComponentIds = selectionIndexesToIds(availableComponentsForList, anchor, clickedIndex)
            availableSelectionAnchorIndex = anchor
        } else if (ctrl) {
            const next = selectedAvailableComponentIds.slice()
            const idx = next.indexOf(clickedId)
            if (idx >= 0)
                next.splice(idx, 1)
            else
                next.push(clickedId)
            selectedAvailableComponentIds = next
            availableSelectionAnchorIndex = clickedIndex
        } else {
            selectedAvailableComponentIds = [clickedId]
            availableSelectionAnchorIndex = clickedIndex
        }

        selectedAvailableComponentId = selectionContains(selectedAvailableComponentIds, clickedId)
                ? clickedId
                : (selectedAvailableComponentIds.length > 0 ? selectedAvailableComponentIds[selectedAvailableComponentIds.length - 1] : "")
    }

    function handleMemberSelection(clickedIndex, mouse) {
        const clicked = memberComponentsForList[clickedIndex]
        if (!clicked) return
        const clickedId = clicked.id
        const ctrl = !!(mouse.modifiers & Qt.ControlModifier)
        const shift = !!(mouse.modifiers & Qt.ShiftModifier)

        if (shift) {
            const anchor = memberSelectionAnchorIndex >= 0 ? memberSelectionAnchorIndex : clickedIndex
            selectedMemberComponentIds = selectionIndexesToIds(memberComponentsForList, anchor, clickedIndex)
            memberSelectionAnchorIndex = anchor
        } else if (ctrl) {
            const next = selectedMemberComponentIds.slice()
            const idx = next.indexOf(clickedId)
            if (idx >= 0)
                next.splice(idx, 1)
            else
                next.push(clickedId)
            selectedMemberComponentIds = next
            memberSelectionAnchorIndex = clickedIndex
        } else {
            selectedMemberComponentIds = [clickedId]
            memberSelectionAnchorIndex = clickedIndex
        }

        selectedMemberComponentId = selectionContains(selectedMemberComponentIds, clickedId)
                ? clickedId
                : (selectedMemberComponentIds.length > 0 ? selectedMemberComponentIds[selectedMemberComponentIds.length - 1] : "")
        loadListMemberDetail()
    }

    function selectedMemberDetail() {
        for (let i = 0; i < memberComponentsForList.length; ++i)
            if (memberComponentsForList[i].id === selectedMemberComponentId)
                return memberComponentsForList[i]
        return ({})
    }

    function loadListMemberDetail() {
        const c = selectedMemberDetail()
        const labels = ["Name", "ID", "Family", "Type", "Source", "MW", "Tb (K)", "Tc (K)", "Pc (Pa)", "Omega", "SG @60F"]
        const values = [
            c.name || c.id || "",
            c.id || "",
            c.family || "",
            c.componentType || "",
            c.source || "",
            fmt(c.molarMass || c.MW, 4),
            fmt(c.normalBoilingPointK || c.Tb, 4),
            fmt(c.criticalTemperatureK || c.Tc, 4),
            fmt(c.criticalPressurePa || c.Pc, 2),
            fmt(c.acentricFactor || c.omega, 6),
            fmt(c.specificGravity60F || c.SG, 4)
        ]
        // memberDetailSheet is not present in this view — it's a leftover from
        // an older layout that had a separate member detail panel. Guard the
        // access so we don't throw ReferenceError.
        try {
            memberDetailSheet.clearAll()
            memberDetailSheet.rowLabels = labels
            memberDetailSheet.colLabels = ["Value"]
            for (let i = 0; i < values.length; ++i)
                memberDetailSheet.setCell(i, 0, values[i])
        } catch (e) {
            // no memberDetailSheet in current layout — ignore
        }
    }

    Component.onCompleted: {
        componentFamilyCombo.model = familyOptions()
        listFamilyCombo.model = familyOptions()
        Qt.callLater(function() {
            refreshComponentResults("")
            refreshComponentLists("")
            loadListMemberDetail()
            if (selectedComponentId !== "")
                loadDraftFromComponent(selectedComponent)
        })
    }

    Connections {
        target: manager
        function onComponentsChanged() {
            componentFamilyCombo.model = familyOptions()
            listFamilyCombo.model = familyOptions()
            refreshComponentResults(selectedComponentId)
            refreshListMembership()
            refreshAvailableComponentsForList()
            loadListMemberDetail()
        }
        function onComponentListsChanged() {
            refreshComponentLists(selectedListId)
            loadListMemberDetail()
        }
        function onErrorOccurred(message) { root.statusMessage = message }
        ignoreUnknownSignals: true
    }

    // ───────────────────────────────────────────────────────────────────────
    //  (no inline components — using Common.PGroupBox + Common.PListItem)
    // ───────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────────────────────────────────────
    //  Root layout — PPropertyView shell
    // ───────────────────────────────────────────────────────────────────────

    Rectangle { anchors.fill: parent; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvPageBg : "#d8dde2" }

    Common.PPropertyView {
        id: propertyView
        anchors.fill: parent
        anchors.margins: 4

        tabs: [
            { text: "Components" },
            { text: "Component Lists" }
        ]
        currentIndex: root.currentTab
        onTabClicked: function(index) { root.currentTab = index }

        // Status message + Unit Set selector on the right side of the tab strip
        rightAccessory: Row {
            spacing: 10
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

            Text {
                text: root.statusMessage
                font.family: "Segoe UI"
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                color: "#526571"
                elide: Text.ElideRight
                width: 320
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Unit Set:"
                font.pixelSize: 11
                font.family: "Segoe UI"
                color: "#526571"
                anchors.verticalCenter: parent.verticalCenter
            }

            Common.PComboBox {
                id: unitSetCombo
                width: 110
                fontSize: 11
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                model: (typeof gUnits !== "undefined") ? gUnits.availableUnitSets : ["SI", "Field", "British"]
                currentIndex: {
                    var s = (typeof gUnits !== "undefined") ? gUnits.activeUnitSet : "SI"
                    var idx = model.indexOf(s)
                    return idx >= 0 ? idx : 0
                }
                onActivated: function(index) {
                    if (typeof gUnits !== "undefined")
                        gUnits.activeUnitSet = model[index]
                }
                Connections {
                    target: (typeof gUnits !== "undefined") ? gUnits : null
                    ignoreUnknownSignals: true
                    function onActiveUnitSetChanged() {
                        var i = unitSetCombo.model.indexOf(gUnits.activeUnitSet)
                        if (i >= 0 && unitSetCombo.currentIndex !== i)
                            unitSetCombo.currentIndex = i
                    }
                }
            }
        }

        // ───────────────────────────────────────────────────────────────────
        //  Components tab content
        // ───────────────────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: root.currentTab === 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                // ─── Actions toolbar (PGroupBox with captioned header) ────
                Common.PGroupBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "Component actions"

                    RowLayout {
                        spacing: 6
                        Common.PButton {
                            text: "Import pseudo fluid"
                            Layout.preferredWidth: 140
                            onClicked: if (manager && pseudoFluidCombo.currentText !== "") manager.importPseudoComponentFluid(pseudoFluidCombo.currentText, "pseudo-fraction", true)
                        }
                        Common.PComboBox {
                            id: pseudoFluidCombo
                            Layout.preferredWidth: 200
                            model: manager ? manager.availableFluidNames : []
                        }
                        Common.PButton { text: "Reset starter seed"; Layout.preferredWidth: 140; onClicked: if (manager) manager.resetToStarterSeed() }
                        Common.PButton { text: "Refresh";        Layout.preferredWidth: 76;  onClicked: refreshComponentResults(selectedComponentId) }
                        Common.PButton { text: "New Component";  Layout.preferredWidth: 112; onClicked: { loadDraftFromComponent({ source: "user" }); notesArea.text = "" } }
                        Common.PButton { text: "Save";           Layout.preferredWidth: 76;  onClicked: saveSelectedComponent() }
                        Common.PButton {
                            text: "Delete"
                            Layout.preferredWidth: 76
                            enabled: selectedComponentId !== ""
                            onClicked: root.attemptDeleteComponent()
                        }
                        Item { Layout.fillWidth: true }   // spacer
                    }
                }

                // ─── Body: Components list + Worksheet ────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    // ── Left: Components list ────────────────────────────
                    Common.PGroupBox {
                        fillContent: true
                        Layout.preferredWidth: 320
                        Layout.minimumWidth: 320
                        Layout.maximumWidth: 320
                        Layout.fillHeight: true
                        caption: "Components"

                        Item {
                            anchors.fill: parent

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: filteredComponents.length + " shown"
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                    color: "#526571"
                                    font.italic: true
                                }

                                Common.PTextField {
                                    id: componentSearch
                                    Layout.fillWidth: true
                                    placeholderText: "Search components"
                                    onTextChanged: refreshComponentResults(selectedComponentId)
                                }

                                Common.PComboBox {
                                    id: componentFamilyCombo
                                    Layout.fillWidth: true
                                    onActivated: function(index) { refreshComponentResults(selectedComponentId, textAt(index)) }
                                }

                                Common.PCheckBox {
                                    id: componentIncludePseudo
                                    text: "Include pseudo-components"
                                    checked: true
                                    onToggled: refreshComponentResults(selectedComponentId)
                                }

                                // ── Components ListView ─────────────────
                                ListView {
                                    id: componentListView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: filteredComponents
                                    spacing: 1
                                    ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                    delegate: Common.PListItem {
                                        id: liComp
                                        width: componentListView.width - 2
                                        height: 44
                                        altIndex: index
                                        selected: modelData.id === selectedComponentId

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: liComp.hovered = true
                                            onExited: liComp.hovered = false
                                            onClicked: {
                                                selectedComponentId = modelData.id
                                                selectedComponent = manager.getComponent(modelData.id)
                                                loadDraftFromComponent(selectedComponent)
                                                try { notesArea.text = selectedComponent && selectedComponent.notes ? selectedComponent.notes : "" } catch (e) {}
                                            }
                                        }

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.topMargin: 4
                                            anchors.rightMargin: 4
                                            spacing: 2
                                            Text {
                                                text: modelData.name || modelData.id
                                                font.family: "Segoe UI"
                                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                                font.bold: true
                                                color: liComp.selected ? "white" : "#1f2a34"
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                            Text {
                                                text: (modelData.family || "") + "  \u2022  " + (modelData.source || "user")
                                                font.family: "Segoe UI"
                                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                                color: liComp.selected ? "#cce4f8" : "#5b6b75"
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Right: Worksheet panel (field grid + Notes) ──────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        Common.PGroupBox {
                            id: worksheetBox
                            fillContent: true
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            caption: selectedComponentId === "" ? "Component Worksheet" : (selectedComponent.name || selectedComponentId)

                            readonly property int labelW: 170

                            Flickable {
                                id: worksheetFlick
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: worksheetGrid.implicitHeight
                                clip: true
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 10 }
                                boundsBehavior: Flickable.StopAtBounds

                                GridLayout {
                                    id: worksheetGrid
                                    width: worksheetFlick.width
                                    columns: 3
                                    columnSpacing: 0
                                    rowSpacing: 0

                                    // ── ID ──────────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "ID" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.id || ""
                                            onEditingFinished: root._setDraft("id", text)
                                        }
                                    }

                                    // ── Name ────────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Name"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.name || ""
                                            onEditingFinished: root._setDraft("name", text)
                                        }
                                    }

                                    // ── Formula ─────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Formula" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.formula || ""
                                            onEditingFinished: root._setDraft("formula", text)
                                        }
                                    }

                                    // ── CAS ─────────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "CAS"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.cas || ""
                                            onEditingFinished: root._setDraft("cas", text)
                                        }
                                    }

                                    // ── Family ──────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Family" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.family || ""
                                            onEditingFinished: root._setDraft("family", text)
                                        }
                                    }

                                    // ── Component type ──────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Component type"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.componentType || ""
                                            onEditingFinished: root._setDraft("componentType", text)
                                        }
                                    }

                                    // ── Aliases (comma-separated) ──────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Aliases" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.aliases || ""
                                            onEditingFinished: root._setDraft("aliases", text)
                                        }
                                    }

                                    // ── Tags ────────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Tags"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.tags || ""
                                            onEditingFinished: root._setDraft("tags", text)
                                        }
                                    }

                                    // ── Phases ──────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Phases" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.phaseCapabilities || ""
                                            onEditingFinished: root._setDraft("phaseCapabilities", text)
                                        }
                                    }

                                    // ── Source ──────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Source"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: root.draftComponent.source || ""
                                            onEditingFinished: root._setDraft("source", text)
                                        }
                                    }

                                    // ── Molar mass (MW) ──────────────────
                                    // Label combines both conventions: "Molar mass"
                                    // (SI chemistry) and "MW" (petroleum/engineering).
                                    // Same underlying property, one row.
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Molar mass (MW)" }
                                    Common.PGridValue {
                                        quantity: "MolarMass"
                                        siValue: root.draftComponent.molarMassSi
                                        displayUnit: root.unitFor("MolarMass")
                                        editable: true
                                        onEdited: function(siVal) { root._setDraft("molarMassSi", siVal) }
                                    }
                                    Common.PGridUnit {
                                        quantity: "MolarMass"
                                        siValue: root.draftComponent.molarMassSi
                                        displayUnit: root.unitFor("MolarMass")
                                        onUnitOverride: function(u) { root.setUnit("MolarMass", u) }
                                    }

                                    // ── Normal boiling point (Temperature) ──
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Normal boiling point"; alt: true }
                                    Common.PGridValue {
                                        alt: true
                                        quantity: "Temperature"
                                        siValue: root.draftComponent.tbK
                                        displayUnit: root.unitFor("Temperature")
                                        editable: true
                                        onEdited: function(siVal) { root._setDraft("tbK", siVal) }
                                    }
                                    Common.PGridUnit {
                                        alt: true
                                        quantity: "Temperature"
                                        siValue: root.draftComponent.tbK
                                        displayUnit: root.unitFor("Temperature")
                                        onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                    }

                                    // ── Critical temperature (Temperature) ──
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Critical temperature" }
                                    Common.PGridValue {
                                        quantity: "Temperature"
                                        siValue: root.draftComponent.tcK
                                        displayUnit: root.unitFor("Temperature")
                                        editable: true
                                        onEdited: function(siVal) { root._setDraft("tcK", siVal) }
                                    }
                                    Common.PGridUnit {
                                        quantity: "Temperature"
                                        siValue: root.draftComponent.tcK
                                        displayUnit: root.unitFor("Temperature")
                                        onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                                    }

                                    // ── Critical pressure (Pressure) ────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Critical pressure"; alt: true }
                                    Common.PGridValue {
                                        alt: true
                                        quantity: "Pressure"
                                        siValue: root.draftComponent.pcPa
                                        displayUnit: root.unitFor("Pressure")
                                        editable: true
                                        onEdited: function(siVal) { root._setDraft("pcPa", siVal) }
                                    }
                                    Common.PGridUnit {
                                        alt: true
                                        quantity: "Pressure"
                                        siValue: root.draftComponent.pcPa
                                        displayUnit: root.unitFor("Pressure")
                                        onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                                    }

                                    // ── Acentric factor (dimensionless) ─
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Acentric factor" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.acentricFactor) ? root.draftComponent.acentricFactor.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("acentricFactor", root.parseNum(text))
                                        }
                                    }

                                    // ── Critical volume (m3/kmol) ────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Critical volume (m3/kmol)"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.critVolM3PerKmol) ? root.draftComponent.critVolM3PerKmol.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("critVolM3PerKmol", root.parseNum(text))
                                        }
                                    }

                                    // ── Critical compressibility ─────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Critical compressibility" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.critCompressibility) ? root.draftComponent.critCompressibility.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("critCompressibility", root.parseNum(text))
                                        }
                                    }

                                    // ── Specific gravity @60F ────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Specific gravity @60F"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.sg60F) ? root.draftComponent.sg60F.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("sg60F", root.parseNum(text))
                                        }
                                    }

                                    // ── Watson K ────────────────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Watson K" }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.watsonK) ? root.draftComponent.watsonK.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("watsonK", root.parseNum(text))
                                        }
                                    }

                                    // ── Volume shift delta ───────────────
                                    Common.PGridLabel { Layout.preferredWidth: worksheetBox.labelW; text: "Volume shift delta"; alt: true }
                                    RowLayout {
                                        Layout.columnSpan: 2; Layout.fillWidth: true
                                        Common.PTextField {
                                            Layout.fillWidth: true
                                            text: isFinite(root.draftComponent.volumeShiftDelta) ? root.draftComponent.volumeShiftDelta.toFixed(6) : ""
                                            onEditingFinished: root._setDraft("volumeShiftDelta", root.parseNum(text))
                                        }
                                    }
                                }
                            }
                        }

                        Common.PGroupBox {

                            fillContent: true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            caption: "Notes"

                            TextArea {
                                id: notesArea
                                anchors.fill: parent
                                wrapMode: TextArea.Wrap
                                font.family: "Segoe UI"
                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                selectByMouse: true
                                background: Rectangle {
                                    color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvCellEditBg || "#fbfdff" : "#fbfdff"
                                    border.color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvGroupBorder || "#97a2ad" : "#97a2ad"
                                    border.width: 1
                                }
                            }
                        }
                    }
                }
            }
        }

        // ───────────────────────────────────────────────────────────────────
        //  Component Lists tab content
        // ───────────────────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: root.currentTab === 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                // ─── Actions toolbar ─────────────────────────────────────
                Common.PGroupBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    caption: "List actions"

                    RowLayout {
                        spacing: 6
                        Common.PTextField {
                            id: newListField
                            Layout.preferredWidth: 220
                            placeholderText: "New component list name"
                        }
                        Common.PButton {
                            text: "Create List"
                            Layout.preferredWidth: 96
                            enabled: newListField.text.trim() !== ""
                            onClicked: {
                                if (!manager) return
                                const preferred = newListField.text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-+|-+$)/g, "")
                                if (manager.createComponentList(newListField.text)) {
                                    newListField.text = ""
                                    refreshComponentLists(preferred)
                                }
                            }
                        }
                        Common.PButton {
                            text: "Rename"
                            Layout.preferredWidth: 80
                            enabled: selectedListId !== "" && listNameField.text.trim() !== ""
                            onClicked: if (manager && manager.renameComponentList(selectedListId, listNameField.text)) refreshComponentLists("")
                        }
                        Common.PButton {
                            text: "Delete"
                            Layout.preferredWidth: 76
                            enabled: selectedListId !== ""
                            onClicked: root.attemptDeleteComponentList()
                        }
                        Common.PButton { text: "Refresh"; Layout.preferredWidth: 76; onClicked: refreshComponentLists(selectedListId) }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ─── Body: Saved Lists + List Builder ────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    // ── Left column: Saved Lists + List Details ─────────
                    ColumnLayout {
                        Layout.preferredWidth: 280
                        Layout.minimumWidth: 280
                        Layout.maximumWidth: 280
                        Layout.fillHeight: true
                        spacing: 6

                        Common.PGroupBox {

                            fillContent: true
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            caption: "Saved Component Lists"

                            Item {
                                anchors.fill: parent

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    Text {
                                        text: componentListsCache.length + " lists"
                                        font.family: "Segoe UI"
                                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                        color: "#526571"
                                        font.italic: true
                                    }

                                    ListView {
                                        id: savedListsView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: manager ? manager.componentListModel : null
                                        spacing: 1
                                        ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                        delegate: Common.PListItem {
                                            id: liSaved
                                            width: savedListsView.width - 2
                                            height: 44
                                            altIndex: index
                                            selected: model.id === selectedListId

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: liSaved.hovered = true
                                                onExited: liSaved.hovered = false
                                                onClicked: refreshComponentLists(model.id)
                                            }

                                            Column {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.topMargin: 4
                                                anchors.rightMargin: 4
                                                spacing: 2
                                                Text {
                                                    text: model.name || model.id
                                                    font.family: "Segoe UI"
                                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                                    font.bold: true
                                                    color: liSaved.selected ? "white" : "#1f2a34"
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                                Text {
                                                    text: (model.count || 0) + " components  \u2022  " + (model.source || "user")
                                                    font.family: "Segoe UI"
                                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                                    color: liSaved.selected ? "#cce4f8" : "#5b6b75"
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── List Details (PGroupBox for small controls) ─
                        Common.PGroupBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            caption: "List Details"

                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4

                                Text {
                                    text: "Name"
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                    color: "#1f2a34"
                                }
                                Common.PTextField {
                                    id: listNameField
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                }

                                Text {
                                    text: "ID"
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                    color: "#1f2a34"
                                }
                                Text {
                                    text: selectedListId
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                    color: "#526571"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: "Notes"
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                    color: "#1f2a34"
                                    Layout.alignment: Qt.AlignTop
                                }
                                TextArea {
                                    id: listNotesArea
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    readOnly: true
                                    wrapMode: TextArea.Wrap
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                    background: Rectangle {
                                        color: "#f5f7f9"
                                        border.color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvGroupBorder || "#dfe5ea" : "#dfe5ea"
                                        border.width: 1
                                    }
                                }
                            }
                        }
                    }

                    // ── Right: List Builder (Available + Add/Remove + Members) ─
                    Common.PGroupBox {
                        fillContent: true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        caption: selectedListId === "" ? "Component List Builder" : (selectedList.name || selectedListId)

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            // ── Available Components ────────────────────
                            Common.PGroupBox {
                                fillContent: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                caption: "Available Components"

                                Item {
                                    anchors.fill: parent

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Common.PTextField {
                                            id: listSearch
                                            Layout.fillWidth: true
                                            placeholderText: "Search available components"
                                            onTextChanged: refreshAvailableComponentsForList()
                                        }

                                        Common.PComboBox {
                                            id: listFamilyCombo
                                            Layout.fillWidth: true
                                            onActivated: function(index) { refreshAvailableComponentsForList(textAt(index)) }
                                        }

                                        ListView {
                                            id: availableListView
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            model: availableComponentsForList
                                            spacing: 1
                                            ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                            delegate: Common.PListItem {
                                                id: liAvail
                                                width: availableListView.width - 2
                                                height: 40
                                                altIndex: index
                                                selected: selectionContains(selectedAvailableComponentIds, modelData.id)

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onEntered: liAvail.hovered = true
                                                    onExited: liAvail.hovered = false
                                                    onClicked: function(mouse) { handleAvailableSelection(index, mouse) }
                                                }

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.topMargin: 4
                                                    anchors.rightMargin: 4
                                                    spacing: 2
                                                    Text {
                                                        text: modelData.name || modelData.id
                                                        font.family: "Segoe UI"
                                                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                                        font.bold: true
                                                        color: liAvail.selected ? "white" : "#1f2a34"
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                    Text {
                                                        text: {
                                                            const fam = modelData.family || ""
                                                            const src = modelData.source || ""
                                                            if (modelData.isPseudoComponent && src.indexOf("pseudo-fluid:") === 0)
                                                                return fam + "  \u2022  " + src.substring("pseudo-fluid:".length)
                                                            return fam
                                                        }
                                                        font.family: "Segoe UI"
                                                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                                        color: liAvail.selected ? "#cce4f8" : "#5b6b75"
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Add / Remove buttons column ─────────────
                            ColumnLayout {
                                Layout.preferredWidth: 96
                                Layout.minimumWidth: 96
                                Layout.maximumWidth: 96
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 10
                                Item { Layout.fillHeight: true }
                                Common.PButton {
                                    text: "Add \u2192"
                                    Layout.preferredWidth: 90
                                    enabled: selectedListId !== "" && selectedAvailableComponentIds.length > 0
                                    onClicked: {
                                        if (!manager || selectedListId === "" || selectedAvailableComponentIds.length === 0) return
                                        let changed = false
                                        for (let i = 0; i < selectedAvailableComponentIds.length; ++i)
                                            if (manager.addComponentToList(selectedListId, selectedAvailableComponentIds[i])) changed = true
                                        if (changed) {
                                            refreshListMembership()
                                            refreshComponentLists(selectedListId)
                                        }
                                    }
                                }
                                Common.PButton {
                                    text: "\u2190 Remove"
                                    Layout.preferredWidth: 90
                                    enabled: selectedListId !== "" && selectedMemberComponentIds.length > 0
                                    onClicked: {
                                        if (!manager || selectedListId === "" || selectedMemberComponentIds.length === 0) return
                                        let changed = false
                                        for (let i = 0; i < selectedMemberComponentIds.length; ++i)
                                            if (manager.removeComponentFromList(selectedListId, selectedMemberComponentIds[i])) changed = true
                                        if (changed) {
                                            refreshListMembership()
                                            refreshComponentLists(selectedListId)
                                            loadListMemberDetail()
                                        }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }

                            // ── Members list ────────────────────────────
                            Common.PGroupBox {
                                fillContent: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                caption: "List Members"

                                Item {
                                    anchors.fill: parent

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Text {
                                            text: memberComponentsForList.length + " components"
                                            font.family: "Segoe UI"
                                            font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                            color: "#526571"
                                            font.italic: true
                                        }

                                        ListView {
                                            id: memberListView
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            model: memberComponentsForList
                                            spacing: 1
                                            ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                            delegate: Common.PListItem {
                                                id: liMember
                                                width: memberListView.width - 2
                                                height: 40
                                                altIndex: index
                                                selected: selectionContains(selectedMemberComponentIds, modelData.id)

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onEntered: liMember.hovered = true
                                                    onExited: liMember.hovered = false
                                                    onClicked: function(mouse) { handleMemberSelection(index, mouse) }
                                                }

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.topMargin: 4
                                                    anchors.rightMargin: 4
                                                    spacing: 2
                                                    Text {
                                                        text: modelData.name || modelData.id
                                                        font.family: "Segoe UI"
                                                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                                        font.bold: true
                                                        color: liMember.selected ? "white" : "#1f2a34"
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                    Text {
                                                        text: modelData.id || ""
                                                        font.family: "Segoe UI"
                                                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                                        color: liMember.selected ? "#cce4f8" : "#5b6b75"
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Delete Error & Confirm Navigation dialogs ──────────────────────────
    PMessageDialog {
        id: deleteErrorDialog
        parent: Overlay.overlay

        // "component" → click jumps to Lists tab + selects offending list
        //               + highlights the offending component within it
        // "list"      → click confirms then emits navigateToFluidPackage
        property string context: ""
        property string componentIdToHighlight: ""
        property string pendingPackageId: ""
        property string pendingPackageLabel: ""

        onItemClicked: function(index, label) {
            if (context === "component") {
                // In-view navigation: switch to Lists tab, select the list,
                // and highlight the offending component within the members.
                const listId = root.componentListIdForName(label)
                if (listId === "") return
                deleteErrorDialog.close()
                root.currentTab = 1
                root.refreshComponentLists(listId)
                // Highlight the component we tried to delete inside the
                // member panel, after refreshListMembership has populated it.
                Qt.callLater(function() {
                    if (componentIdToHighlight !== "") {
                        root.selectedMemberComponentId = componentIdToHighlight
                        root.selectedMemberComponentIds = [componentIdToHighlight]
                    }
                })
            } else if (context === "list") {
                // Cross-view navigation: confirm first, then signal up to
                // PfdMainView. Look up the package id from its display name.
                const pkgId = root.fluidPackageIdForName(label)
                if (pkgId === "") return
                deleteErrorDialog.pendingPackageId = pkgId
                deleteErrorDialog.pendingPackageLabel = label
                confirmNavigateDialog.message = "Navigate to Fluid Package '" + label + "'?"
                confirmNavigateDialog.open()
            }
        }
    }

    // Inline confirm-navigation popup with Windows-classic 3D raised bevel.
    // Behaviorally identical to a Yes/No dialog.
    Popup {
        id: confirmNavigateDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape

        property string title: "Navigate"
        property string message: ""
        property int minWidth: 320

        // Auto-size to fit the message (which embeds an object name that
        // could be arbitrarily long). Chrome overhead ~40px horizontally
        // (margins + padding).
        readonly property int maxAllowedWidth: parent ? Math.floor(parent.width * 0.85) : 1200
        width: Math.min(
            Math.max(minWidth, confirmMsgMetrics.contentWidth + 40),
            maxAllowedWidth)

        Text {
            id: confirmMsgMetrics
            visible: false
            text: confirmNavigateDialog.message
            font.pixelSize: 12
            textFormat: Text.PlainText
        }

        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 3) : 0
        padding: 0
        background: Rectangle { color: "transparent" }

        function doYes() {
            const pkgId = deleteErrorDialog.pendingPackageId
            confirmNavigateDialog.close()
            deleteErrorDialog.close()
            if (pkgId !== "") root.navigateToFluidPackage(pkgId)
        }
        function doNo() {
            confirmNavigateDialog.close()
            // Delete Error stays open behind us so the user can pick another
            // package or click OK.
        }

        contentItem: Item {
            id: confirmChrome
            implicitHeight: confirmCol.implicitHeight + 4

            // Base fill
            Rectangle { anchors.fill: parent; color: gAppTheme.pvFrame }

            // Raised 3D outer bevel (bright top+left, dark bottom+right)
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: gAppTheme.pvFrameHi }
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameHi }
            Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; width: 1; color: gAppTheme.pvFrameLo }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: gAppTheme.pvFrameLo }

            // Inner chisel
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.topMargin: 1; anchors.leftMargin: 1; anchors.rightMargin: 1; height: 1; color: Qt.lighter(gAppTheme.pvFrame, 1.05) }
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.topMargin: 1; anchors.leftMargin: 1; anchors.bottomMargin: 1; width: 1; color: Qt.lighter(gAppTheme.pvFrame, 1.05) }
            Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.topMargin: 1; anchors.rightMargin: 1; anchors.bottomMargin: 1; width: 1; color: Qt.darker(gAppTheme.pvFrame, 1.08) }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.leftMargin: 1; anchors.rightMargin: 1; anchors.bottomMargin: 1; height: 1; color: Qt.darker(gAppTheme.pvFrame, 1.08) }

            ColumnLayout {
                id: confirmCol
                anchors.fill: parent
                anchors.margins: 2
                spacing: 0

                // Title bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    color: gAppTheme.pvTitleBg

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: gAppTheme.pvFrameLo
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: confirmNavigateDialog.title
                        color: gAppTheme.pvTitleText
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                // Message
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: confirmMsg.implicitHeight + 28
                    color: gAppTheme.pvFrame
                    Text {
                        id: confirmMsg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        text: confirmNavigateDialog.message
                        color: gAppTheme.pvLabelText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Buttons
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: gAppTheme.pvFrame
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Common.PButton {
                            width: 64
                            text: "Yes"
                            onClicked: confirmNavigateDialog.doYes()
                        }
                        Common.PButton {
                            width: 64
                            text: "No"
                            onClicked: confirmNavigateDialog.doNo()
                        }
                    }
                }
            }
        }
    }
}
