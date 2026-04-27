import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../common" as Common

Item {
    id: root

    property var fluidManager: gFluidPackageManager
    property var componentManager: gComponentManager

    // Emitted when the user, via a Delete Error → confirm flow, asks to
    // navigate to a stream that's blocking deletion of a fluid package.
    // Owned by PfdMainView, which closes the Fluid Manager, selects the
    // stream on the PFD, pulses its highlight ring, and opens its
    // workspace window.
    signal navigateToStream(string unitId)

    property string selectedPackageId: ""
    property var selectedPackage: ({})
    property string selectedListId: ""
    property var resolvedCache: []
    property var compositionCache: []  // [{id,massFrac,moleFrac,mw}] parallel to resolvedCache
    property string selectedResolvedId: ""
    property var packageSummary: ({})
    property int componentListVersion: 0   // bumped on componentListsChanged to force combo re-eval

    // Per-quantity display unit overrides (empty string = use Unit Set default).
    // When the user clicks a PGridUnit picker on a specific row, the chosen
    // unit goes here and `unitFor()` returns it for that quantity.
    property var unitOverrides: ({
        "Temperature": "",
        "Pressure":    ""
    })
    function unitFor(q) { return unitOverrides[q] !== undefined ? unitOverrides[q] : "" }
    function setUnit(q, u) {
        var copy = Object.assign({}, unitOverrides)
        copy[q] = u
        unitOverrides = copy
    }

    implicitWidth: 1060
    implicitHeight: 660

    property int rowH: 22
    property int headH: 20

    function fmt(v) {
        if (v === undefined || v === null || v === "") return ""
        return String(v)
    }
    function fmtNum(v, digits) {
        if (v === undefined || v === null || v === "") return ""
        const n = Number(v)
        if (isNaN(n)) return String(v)
        return n.toFixed(digits !== undefined ? digits : 4)
    }
    function allComponentLists() {
        return componentManager ? componentManager.listComponentLists() : []
    }
    function componentListNameById(listId) {
        const lists = allComponentLists()
        for (let i = 0; i < lists.length; ++i) {
            if (fmt(lists[i].id) === fmt(listId))
                return fmt(lists[i].name || lists[i].id)
        }
        return fmt(listId)
    }
    function listIndexForId(listId) {
        const lists = allComponentLists()
        for (let i = 0; i < lists.length; ++i)
            if (fmt(lists[i].id) === fmt(listId))
                return i
        return -1
    }

    function refreshResolvedComponents() {
        if (!componentManager || selectedListId === "") {
            resolvedCache = []
            selectedResolvedId = ""
            detailComponent = ({})
            try { compSheet.clearAll() } catch (e) {}
            return
        }
        resolvedCache = componentManager.resolvedComponentsForList(selectedListId)
        compositionCache = (fluidManager && selectedPackageId !== "") ? fluidManager.packageComposition(selectedPackageId) : []
        if (resolvedCache.length > 0) {
            selectedResolvedId = resolvedCache[0].id
            loadComponentDetail(resolvedCache[0])
        } else {
            selectedResolvedId = ""
            detailComponent = ({})
        }
        rebuildCompositionSheet()
    }

    function refreshPackageSummary() {
        if (fluidManager && selectedPackageId !== "")
            packageSummary = fluidManager.packageEditorSummary(selectedPackageId)
        else {
            packageSummary = {
                valid: selectedListId !== "",
                componentListName: componentListNameById(selectedListId),
                componentCount: resolvedCache.length,
                thermoMethodId: eosCombo.currentText,
                eosName: eosCombo.currentText,
                supportFlags: ["TP", "PH", "PS", "PVF", "TS"],
                status: selectedListId !== "" ? "Unsaved package changes." : "Select a component list for this package."
            }
        }
    }

    function loadPackageDetail(pkg) {
        pkg = pkg || {}
        selectedPackage = pkg
        selectedPackageId = fmt(pkg.id)
        pkgNameField.text = fmt(pkg.name)
        pkgIdField.text = fmt(pkg.id)
        defaultCheck.checked = !!pkg.isDefault
        const methodList = fluidManager ? fluidManager.availableThermoMethods : []
        const methodCurrent = fmt(pkg.thermoMethodId || pkg.propertyMethod) || "PRSV"
        const methodIdx = methodList.indexOf(methodCurrent)
        eosCombo.currentIndex = methodIdx >= 0 ? methodIdx : 0
        notesField.text = fmt(pkg.notes)

        selectedListId = fmt(pkg.componentListId)
        refreshResolvedComponents()
        compositionCache = (fluidManager && selectedPackageId !== "") ? fluidManager.packageComposition(selectedPackageId) : []
        refreshPackageSummary()
    }

    function selectPackage(packageId) {
        selectedPackageId = fmt(packageId)
        selectedPackage = selectedPackageId !== "" && fluidManager
                          ? fluidManager.getFluidPackage(selectedPackageId) : ({})
        loadPackageDetail(selectedPackage)
    }

    function refreshPackages(preferredId) {
        if (!fluidManager) return
        const all = fluidManager.listFluidPackages()
        let targetId = preferredId || selectedPackageId
        let found = false
        for (let i = 0; i < all.length; ++i) {
            if (fmt(all[i].id) === fmt(targetId)) {
                found = true
                break
            }
        }
        if (!found) targetId = all.length > 0 ? fmt(all[0].id) : ""
        selectPackage(targetId)
    }

    function saveSelectedPackage() {
        if (!fluidManager) return
        const out = {
            id: selectedPackage && selectedPackage.id ? selectedPackage.id : "",
            name: pkgNameField.text,
            selectionMode: "componentList",
            componentListId: selectedListId,
            componentIds: [],
            propertyMethod: eosCombo.currentText,
            thermoMethodId: eosCombo.currentText,
            isDefault: defaultCheck.checked,
            source: selectedPackage && selectedPackage.source ? selectedPackage.source : "user",
            notes: notesField.text,
            tags: selectedPackage && selectedPackage.tags ? selectedPackage.tags : ["fluid-package"]
        }
        if (fluidManager.addOrUpdateFluidPackage(out)) {
            refreshPackages(out.id || fluidManager.defaultFluidPackageId)
            statusLabel.text = fluidManager.lastStatus || ""
        }
    }

    function newPackage() {
        selectedPackageId = ""
        selectedPackage = ({
            componentIds: [],
            selectionMode: "componentList",
            propertyMethod: "PRSV",
            thermoMethodId: "PRSV",
            tags: ["fluid-package"],
            source: "user",
            notes: ""
        })
        loadPackageDetail(selectedPackage)
        pkgIdField.text = ""
        pkgNameField.text = ""
        statusLabel.text = "Ready to create a new fluid package."
    }

    // ── Delete Error flow ──────────────────────────────────────────────────
    // Fluid-package delete: if blocked by streams, show dialog. Clicking a
    // stream name shows a Confirm dialog; on Yes, emit navigateToStream so
    // PfdMainView can close us, select the stream on the PFD, pulse its
    // highlight ring, and open its workspace window.
    function attemptDeletePackage() {
        if (!fluidManager || selectedPackageId === "") return
        const blockingStreams = fluidManager.streamsUsingPackage(selectedPackageId)
        if (blockingStreams.length === 0) {
            if (fluidManager.removeFluidPackage(selectedPackageId)) {
                selectedPackageId = ""
                refreshPackages("")
            } else {
                statusLabel.text = fluidManager.lastStatus || "Cannot delete fluid package."
            }
            return
        }
        // Capture parallel arrays so the dialog can map clicked label -> id
        const blockingStreamIds = fluidManager.streamUnitIdsUsingPackage(selectedPackageId)
        const pkgInfo = fluidManager.getFluidPackage(selectedPackageId)
        const pkgName = (pkgInfo && pkgInfo.name) ? pkgInfo.name : selectedPackageId
        deleteErrorDialog.streamUnitIds = blockingStreamIds
        deleteErrorDialog.message = "Cannot delete fluid package '" + pkgName
            + "':\nit is being used by the following stream(s).\n\nClick a stream name to navigate to it."
        deleteErrorDialog.items = blockingStreams
        deleteErrorDialog.open()
    }

    // The component currently displayed in the Component Properties grid.
    // Property bindings on PGridValue read from here.
    property var detailComponent: ({})

    function loadComponentDetail(c) {
        c = c || {}

        // Find this component in compositionCache (matched by id/name)
        var massFrac = NaN, moleFrac = NaN
        for (var ci = 0; ci < compositionCache.length; ++ci) {
            var cc = compositionCache[ci]
            if (cc.id === (c.id || c.name) || cc.name === (c.name || c.id)) {
                massFrac = cc.massFrac
                moleFrac = cc.moleFrac
                break
            }
        }

        detailComponent = {
            name:     fmt(c.name || c.id),
            id:       fmt(c.id),
            cas:      fmt(c.cas),
            family:   fmt(c.family),
            type:     fmt(c.componentType),
            formula:  fmt(c.formula),
            aliases:  (c.aliases || []).join(", "),
            tags:     (c.tags || []).join(", "),
            phases:   (c.phaseCapabilities || []).join(", "),
            mw:       Number(c.molarMass || c.MW),
            tbK:      Number(c.normalBoilingPointK || c.Tb),
            tcK:      Number(c.criticalTemperatureK || c.Tc),
            pcPa:     Number(c.criticalPressurePa || c.Pc),
            omega:    Number(c.acentricFactor || c.omega),
            vcM3pKmol: Number(c.criticalVolumeM3PerKmol),
            zc:       Number(c.criticalCompressibility),
            sg60F:    Number(c.specificGravity60F || c.SG),
            watsonK:  Number(c.watsonK),
            volShift: Number(c.volumeShiftDelta || c.delta),
            source:   fmt(c.source),
            massFrac: massFrac,
            moleFrac: moleFrac
        }
    }

    // Recompute mole fractions from current compositionCache mass fractions
    function _recomputeMoleFracs() {
        if (compositionCache.length === 0) return
        var nc = compositionCache.slice()
        var moleSum = 0
        for (var i = 0; i < nc.length; ++i) {
            var mw = nc[i].mw > 0 ? nc[i].mw : 1.0
            nc[i] = { id: nc[i].id, name: nc[i].name, mw: nc[i].mw,
                      massFrac: nc[i].massFrac,
                      moleFrac: nc[i].massFrac / mw }
            moleSum += nc[i].moleFrac
        }
        if (moleSum > 0) {
            for (var j = 0; j < nc.length; ++j) {
                nc[j] = { id: nc[j].id, name: nc[j].name, mw: nc[j].mw,
                          massFrac: nc[j].massFrac,
                          moleFrac: nc[j].moleFrac / moleSum }
            }
        }
        compositionCache = nc
    }

    // Populate the composition PSpreadsheet from compositionCache.
    // Row labels = component names. Col 0 = editable mass frac, col 1 = mole frac.
    function rebuildCompositionSheet() {
        try {
            const rows = root.compositionCache.length
            compSheet.clearAll()
            compSheet.numRows = Math.max(1, rows)
            compSheet.numCols = 2
            compSheet.colLabels = ["Mass frac", "Mole frac"]
            const rowLabels = []
            for (let i = 0; i < rows; ++i) {
                const e = root.compositionCache[i]
                rowLabels.push(e.name || e.id || "")
                compSheet.setCell(i, 0, fmtNum(e.massFrac, 6))
                compSheet.setCell(i, 1, fmtNum(e.moleFrac, 6))
            }
            compSheet.rowLabels = rowLabels
        } catch (e) {}
    }

    // Handle a cell edit from the composition PSpreadsheet. Only col 0 editable.
    function onCompSheetEdited(row, col, text) {
        if (col !== 0) return
        if (row < 0 || row >= root.compositionCache.length) return
        const v = parseFloat(text)
        if (!isFinite(v) || v < 0) {
            compSheet.setCell(row, 0, fmtNum(root.compositionCache[row].massFrac, 6))
            return
        }
        const nc = root.compositionCache.slice()
        nc[row] = { id: nc[row].id, name: nc[row].name, mw: nc[row].mw,
                    massFrac: v, moleFrac: nc[row].moleFrac }
        root.compositionCache = nc
        root._recomputeMoleFracs()
        rebuildCompositionSheet()
        root.loadComponentDetail({ id: root.selectedResolvedId, name: root.selectedResolvedId })
    }

    function normalizeMassFractions() {
        if (root.compositionCache.length === 0) return
        var s = 0
        for (var i = 0; i < root.compositionCache.length; ++i)
            s += root.compositionCache[i].massFrac
        if (s <= 0) return
        var newCache = []
        for (var j = 0; j < root.compositionCache.length; ++j) {
            var entry = root.compositionCache[j]
            var mf = entry.massFrac / s
            newCache.push({ id: entry.id, name: entry.name, mw: entry.mw,
                            massFrac: mf, moleFrac: entry.moleFrac })
        }
        root.compositionCache = newCache
        root._recomputeMoleFracs()
        rebuildCompositionSheet()
        root.loadComponentDetail({ id: root.selectedResolvedId, name: root.selectedResolvedId })
    }

    Component.onCompleted: Qt.callLater(function() { refreshPackages("") })

    Connections {
        target: fluidManager
        function onFluidPackagesChanged() { refreshPackages(selectedPackageId) }
        function onErrorOccurred(msg) { statusLabel.text = msg }
        ignoreUnknownSignals: true
    }
    Connections {
        target: componentManager
        function onComponentListsChanged() {
            root.componentListVersion++   // forces combo model expression to re-run
            refreshResolvedComponents()
            refreshPackageSummary()
        }
        ignoreUnknownSignals: true
    }

    // (Legacy CompactFrame/SectionHeader/CompactField replaced by
    //  Common.PGroupBox / Common.PTextField / Common.PButton / etc.)

    Rectangle { anchors.fill: parent; color: (typeof gAppTheme !== "undefined") ? gAppTheme.pvPageBg : "#d8dde2" }

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        color: "#d8dde2"; border.color: "#6d7883"; border.width: 1

        Rectangle {
            id: commandBar
            x: 0; y: 0; width: parent.width; height: 40
            color: "#c8d0d8"; border.color: "#97a2ad"; border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 6

                Common.PButton { text: "New Package"; onClicked: root.newPackage() }
                Common.PButton { text: "Save Package"; enabled: pkgNameField.text.trim() !== ""; onClicked: root.saveSelectedPackage() }
                Common.PButton {
                    text: "Delete"; enabled: root.selectedPackageId !== ""
                    onClicked: root.attemptDeletePackage()
                }
                Common.PButton {
                    text: "Set Default"; enabled: root.selectedPackageId !== ""
                    onClicked: {
                        if (fluidManager.setDefaultFluidPackage(root.selectedPackageId)) {
                            defaultCheck.checked = true
                            statusLabel.text = fluidManager.lastStatus || ""
                        }
                    }
                }
                Common.PButton {
                    text: "Reset Starters"
                    onClicked: {
                        fluidManager.createStarterPackages()
                        root.refreshPackages("")
                        statusLabel.text = fluidManager.lastStatus || ""
                    }
                }

                Text {
                    id: statusLabel
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: 10
                    color: "#526571"
                    elide: Text.ElideRight
                    text: fluidManager && fluidManager.lastStatus ? fluidManager.lastStatus : ""
                    verticalAlignment: Text.AlignVCenter
                }

                // Unit Set selector — standard pattern matching Stream/HEX views.
                Text {
                    text: "Unit Set:"
                    font.pixelSize: 11
                    font.family: "Segoe UI"
                    color: "#526571"
                    Layout.alignment: Qt.AlignVCenter
                }
                Common.PComboBox {
                    id: unitSetCombo
                    Layout.preferredWidth: 110
                    Layout.alignment: Qt.AlignVCenter
                    fontSize: 11
                    font.bold: true
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
        }

        Common.PGroupBox {
            id: leftPane
            x: 6; y: commandBar.height + 6
            width: 230
            height: parent.height - y - 6
            caption: "Fluid Packages"
            fillContent: true

            Column {
                anchors.fill: parent
                spacing: 4

                Text {
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                    color: "#526571"; font.italic: true
                    text: fluidManager ? (fluidManager.fluidPackageCount + " packages") : ""
                }

                ListView {
                    id: packageListView
                    width: parent.width
                    height: parent.height - y
                    clip: true; spacing: 1
                    model: fluidManager ? fluidManager.fluidPackageModel : null
                    ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }

                    delegate: Common.PListItem {
                        id: liPkg
                        width: packageListView.width - 2
                        height: 46
                        altIndex: index
                        selected: model.id === root.selectedPackageId

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: liPkg.hovered = true
                            onExited: liPkg.hovered = false
                            onClicked: root.selectPackage(model.id)
                        }

                        Column {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.topMargin: 5
                            anchors.rightMargin: 4
                            spacing: 2
                            Text {
                                text: root.fmt(model.name || model.id)
                                font.family: "Segoe UI"
                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                font.bold: true
                                color: liPkg.selected ? "white" : "#1f2a34"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: root.componentListNameById(model.componentListId)
                                      + "  \u2022  "
                                      + root.fmt(model.thermoMethodId || model.propertyMethod)
                                font.family: "Segoe UI"
                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                color: liPkg.selected ? "#cce4f8" : "#5b6b75"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }
                }
            }
        }

        Common.PGroupBox {
            id: midPane
            x: leftPane.x + leftPane.width + 6
            y: leftPane.y
            width: 320
            height: leftPane.height
            caption: root.selectedPackageId === "" ? "Package Editor" : (root.selectedPackage.name || root.selectedPackageId)
            fillContent: true

            // Form fields (positioned absolutely inside the PGroupBox content area)
            Text {
                id: nameLbl
                x: 0; y: 0
                text: "Name"
                font.family: "Segoe UI"
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                color: "#1f2a34"
            }
            Common.PTextField {
                id: pkgNameField
                x: 70; y: -2; width: parent.width - 70
                placeholderText: "Package name"
            }

            Text {
                id: idLbl
                x: 0; y: pkgNameField.y + pkgNameField.height + 6
                text: "ID"
                font.family: "Segoe UI"
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                color: "#1f2a34"
            }
            Common.PTextField {
                id: pkgIdField
                x: 70; y: pkgNameField.y + pkgNameField.height + 4
                width: parent.width - 70
                readOnly: true
            }

            Text {
                id: clLbl
                x: 0; y: pkgIdField.y + pkgIdField.height + 6
                text: "Comp. List"
                font.family: "Segoe UI"
                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                color: "#1f2a34"
            }
            Common.PComboBox {
                id: componentListCombo
                x: 70; y: pkgIdField.y + pkgIdField.height + 4
                width: parent.width - 70

                model: {
                    void root.componentListVersion
                    const lists = root.allComponentLists()
                    const items = [{ id: "", text: "\u2014 None \u2014" }]
                    for (let i = 0; i < lists.length; ++i)
                        items.push({ id: root.fmt(lists[i].id), text: root.fmt(lists[i].name || lists[i].id) })
                    return items
                }
                textRole: "text"

                Connections {
                    target: root
                    function onSelectedListIdChanged() {
                        const lists = root.allComponentLists()
                        if (root.selectedListId === "") {
                            componentListCombo.currentIndex = 0
                            return
                        }
                        for (let i = 0; i < lists.length; ++i) {
                            if (root.fmt(lists[i].id) === root.selectedListId) {
                                componentListCombo.currentIndex = i + 1
                                return
                            }
                        }
                        componentListCombo.currentIndex = 0
                    }
                }

                onActivated: function(idx) {
                    const m = componentListCombo.model[idx]
                    root.selectedListId = m ? root.fmt(m.id) : ""
                    root.refreshResolvedComponents()
                    root.refreshPackageSummary()
                }
            }

            Common.PCheckBox {
                id: defaultCheck
                x: 0; y: componentListCombo.y + componentListCombo.height + 6
                text: "Default package"
            }

            // ── Thermo Method ──────────────────────────────────────────────
            Common.PGroupBox {
                id: methodSection
                x: 0; y: defaultCheck.y + defaultCheck.height + 10
                width: parent.width
                height: 58
                caption: "Thermo Method"
                fillContent: true

                Text {
                    x: 0; y: 0; text: "Method"
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    color: "#1f2a34"
                }
                Common.PComboBox {
                    id: eosCombo
                    x: 58; y: -2; width: parent.width - 58
                    model: fluidManager ? fluidManager.availableThermoMethods : ["PRSV", "PR", "SRK", "Ideal"]
                    onCurrentTextChanged: root.refreshPackageSummary()
                }
            }

            // ── Package Notes ──────────────────────────────────────────────
            Common.PGroupBox {
                id: notesSection
                x: 0; y: methodSection.y + methodSection.height + 6
                width: parent.width
                height: 162
                caption: "Package Notes"
                fillContent: true

                TextArea {
                    id: notesField
                    anchors.fill: parent
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    placeholderText: "Optional notes about this package and where it should be used."
                    background: Rectangle {
                        color: (typeof gAppTheme !== "undefined") ? (gAppTheme.pvCellEditBg || "#fbfdff") : "#fbfdff"
                        border.color: (typeof gAppTheme !== "undefined") ? (gAppTheme.pvGroupBorder || "#97a2ad") : "#97a2ad"
                        border.width: 1
                    }
                }
            }

            // ── Resolved Package Summary ────────────────────────────────────
            Common.PGroupBox {
                id: summarySection
                x: 0; y: notesSection.y + notesSection.height + 6
                width: parent.width
                height: parent.height - y - 6
                caption: "Resolved Package Summary"
                fillContent: true

                Text {
                    x: 0; y: 0; width: parent.width
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    color: packageSummary.valid ? "#1f2a34" : "#a94442"
                    wrapMode: Text.WordWrap
                    text: root.fmt(packageSummary.status)
                }
                Text {
                    x: 0; y: 24; width: parent.width
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    color: "#1f2a34"
                    text: "EOS: " + root.fmt(packageSummary.eosName || eosCombo.currentText)
                }
                Text {
                    x: 0; y: 42; width: parent.width
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    color: "#1f2a34"
                    text: "Components: " + root.fmt(packageSummary.componentCount || resolvedCache.length)
                }
                Text {
                    x: 0; y: 60; width: parent.width
                    font.family: "Segoe UI"
                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                    color: "#1f2a34"
                    text: "Support: " + root.fmt((packageSummary.supportFlags || []).join(", "))
                    elide: Text.ElideRight
                }
            }
        }

        Common.PGroupBox {
            id: rightPane
            x: midPane.x + midPane.width + 6
            y: leftPane.y
            width: parent.width - x - 6
            height: leftPane.height
            caption: root.selectedListId !== "" ? ("Package Components  \u2014  " + root.componentListNameById(root.selectedListId)) : "Package Components"
            fillContent: true

            property int listColW: 200
            property int detailColX: listColW + 4
            property int detailColW: rightPane.width - detailColX - 20

            // ── Resolved Components list (nested PGroupBox) ─────────────
            Common.PGroupBox {
                id: membersPane
                x: 0; y: 0
                width: rightPane.listColW - 8
                height: parent.height
                caption: "Resolved Components"
                fillContent: true

                Column {
                    anchors.fill: parent
                    spacing: 4

                    Text {
                        id: resolvedCountLabel
                        font.family: "Segoe UI"
                        font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                        color: "#526571"; font.italic: true
                        text: resolvedCache.length + " components"
                    }

                    ListView {
                        id: membersList
                        width: parent.width
                        height: parent.height - y
                        clip: true; spacing: 1
                        model: resolvedCache
                        ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }

                        delegate: Common.PListItem {
                            id: liMember
                            width: membersList.width - 2
                            height: 36
                            altIndex: index
                            selected: modelData.id === root.selectedResolvedId

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: liMember.hovered = true
                                onExited: liMember.hovered = false
                                onClicked: {
                                    root.selectedResolvedId = modelData.id
                                    root.loadComponentDetail(modelData)
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.topMargin: 3
                                anchors.rightMargin: 4
                                spacing: 1
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
                                    text: root.fmt(modelData.id)
                                    font.family: "Segoe UI"
                                    font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSizeSmall : 10
                                    color: liMember.selected ? "#cce4f8" : "#7a8a95"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                    }
                }
            }

            // ── Detail column: Component Properties (top) + Composition (bottom) ──
            Item {
                id: detailCol
                x: rightPane.detailColX
                y: 0
                width: rightPane.detailColW
                height: parent.height

                // Component Properties PGroupBox — vertical stack of
                // PGridLabel/PGridValue/PGridUnit rows (HYSYS pattern).
                // Three quantities have unit pickers: Tb, Tc, Pc. The rest
                // are plain text or dimensionless numeric, spanning across
                // the Value + Unit columns.
                Common.PGroupBox {
                    id: detailPane
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: compEditor.top }
                    anchors.bottomMargin: 6
                    caption: "Component Properties"
                    fillContent: true

                    readonly property int labelW: 90

                    Flickable {
                        id: detailFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: detailGrid.implicitHeight
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 10 }
                        boundsBehavior: Flickable.StopAtBounds

                        GridLayout {
                            id: detailGrid
                            width: detailFlick.width
                            columns: 3
                            columnSpacing: 0
                            rowSpacing: 0

                            // ── Name ────────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Name" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.name)
                            }

                            // ── ID ──────────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "ID"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.id)
                            }

                            // ── Family ──────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Family" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.family)
                            }

                            // ── Type ────────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Type"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.type)
                            }

                            // ── Formula ─────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Formula" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.formula)
                            }

                            // ── CAS ─────────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "CAS"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.cas)
                            }

                            // ── Aliases ─────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Aliases" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.aliases)
                            }

                            // ── Tags ────────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Tags"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.tags)
                            }

                            // ── Phases ──────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Phases" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.phases)
                            }

                            // ── Molar mass (MW) ─────────────────────────
                            // Label combines both conventions: "Molar mass"
                            // (SI chemistry) and "MW" (petroleum/engineering).
                            // Same underlying property, one row with unit picker.
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Molar mass (MW)"; alt: true }
                            Common.PGridValue {
                                alt: true
                                quantity: "MolarMass"
                                siValue: isFinite(root.detailComponent.mw)
                                    ? root.detailComponent.mw * 0.001
                                    : NaN
                                displayUnit: root.unitFor("MolarMass")
                            }
                            Common.PGridUnit {
                                alt: true
                                quantity: "MolarMass"
                                siValue: isFinite(root.detailComponent.mw)
                                    ? root.detailComponent.mw * 0.001
                                    : NaN
                                displayUnit: root.unitFor("MolarMass")
                                onUnitOverride: function(u) { root.setUnit("MolarMass", u) }
                            }

                            // ── Tb (Temperature) ────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Tb" }
                            Common.PGridValue {
                                quantity: "Temperature"
                                siValue: root.detailComponent.tbK
                                displayUnit: root.unitFor("Temperature")
                            }
                            Common.PGridUnit {
                                quantity: "Temperature"
                                siValue: root.detailComponent.tbK
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // ── Tc (Temperature) ────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Tc"; alt: true }
                            Common.PGridValue {
                                alt: true
                                quantity: "Temperature"
                                siValue: root.detailComponent.tcK
                                displayUnit: root.unitFor("Temperature")
                            }
                            Common.PGridUnit {
                                alt: true
                                quantity: "Temperature"
                                siValue: root.detailComponent.tcK
                                displayUnit: root.unitFor("Temperature")
                                onUnitOverride: function(u) { root.setUnit("Temperature", u) }
                            }

                            // ── Pc (Pressure) ───────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Pc" }
                            Common.PGridValue {
                                quantity: "Pressure"
                                siValue: root.detailComponent.pcPa
                                displayUnit: root.unitFor("Pressure")
                            }
                            Common.PGridUnit {
                                quantity: "Pressure"
                                siValue: root.detailComponent.pcPa
                                displayUnit: root.unitFor("Pressure")
                                onUnitOverride: function(u) { root.setUnit("Pressure", u) }
                            }

                            // ── Vc (m³/kmol — kept dimensionless-style; no picker) ──
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Vc (m³/kmol)"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.vcM3pKmol) ? root.fmtNum(root.detailComponent.vcM3pKmol, 6) : ""
                            }

                            // ── Zc (critical compressibility, dimensionless) ────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Zc" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.zc) ? root.fmtNum(root.detailComponent.zc, 6) : ""
                            }

                            // ── Omega (dimensionless) ───────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Omega"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.omega) ? root.fmtNum(root.detailComponent.omega, 6) : ""
                            }

                            // ── SG @60F ─────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "SG @60F" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.sg60F) ? root.fmtNum(root.detailComponent.sg60F, 4) : ""
                            }

                            // ── Watson K ────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Watson K"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.watsonK) ? root.fmtNum(root.detailComponent.watsonK, 4) : ""
                            }

                            // ── Vol. shift ──────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Vol. shift" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.volShift) ? root.fmtNum(root.detailComponent.volShift, 6) : ""
                            }

                            // ── Source ──────────────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Source"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                alignText: "left"
                                textValue: root.fmt(root.detailComponent.source)
                            }

                            // ── Mass fraction ───────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Mass frac" }
                            Common.PGridValue {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.massFrac) ? root.fmtNum(root.detailComponent.massFrac, 6) : "\u2014"
                            }

                            // ── Mole fraction ───────────────────────────
                            Common.PGridLabel { Layout.preferredWidth: detailPane.labelW; text: "Mole frac"; alt: true }
                            Common.PGridValue {
                                alt: true
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                isText: true
                                textValue: isFinite(root.detailComponent.moleFrac) ? root.fmtNum(root.detailComponent.moleFrac, 6) : "\u2014"
                            }
                        }
                    }
                }

                // Package Composition PGroupBox
                Common.PGroupBox {
                    id: compEditor
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 260
                    caption: "Package Composition  (mass fractions)"
                    fillContent: true

                    Column {
                        anchors.fill: parent
                        spacing: 4

                        // Toolbar: sum indicator + Normalize button
                        Item {
                            id: compEditorToolbar
                            width: parent.width
                            height: 24

                            property real fracSum: {
                                var s = 0
                                for (var i = 0; i < root.compositionCache.length; ++i)
                                    s += root.compositionCache[i].massFrac
                                return s
                            }

                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: "Sum: " + compEditorToolbar.fracSum.toFixed(6)
                                font.family: "Segoe UI"
                                font.pixelSize: (typeof gAppTheme !== "undefined") ? gAppTheme.pvFontSize : 11
                                color: Math.abs(compEditorToolbar.fracSum - 1.0) < 1e-4 ? "#1a7a3c" : "#b23b3b"
                            }

                            Common.PButton {
                                text: "Normalize"
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 90
                                enabled: root.compositionCache.length > 0
                                onClicked: root.normalizeMassFractions()
                            }
                        }

                        // Composition spreadsheet — PSpreadsheet with row labels = names
                        Common.PSpreadsheet {
                            id: compSheet
                            width: parent.width
                            height: parent.height - compEditorToolbar.height - 4
                            numRows: 1; numCols: 2
                            colLabels: ["Mass frac", "Mole frac"]
                            readOnlyCols: [1]
                            numericOnlyCells: true
                            onCellEdited: function(row, col, text) {
                                root.onCompSheetEdited(row, col, text)
                            }
                            onWidthChanged: {
                                if (width > 0)
                                    Qt.callLater(function() { root.rebuildCompositionSheet() })
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

        // Parallel array to `items` (which holds display names): each entry
        // is the unitId for the corresponding stream label, so a clicked
        // label can be resolved back to a unit.
        property var streamUnitIds: []
        property string pendingStreamUnitId: ""
        property string pendingStreamLabel: ""

        onItemClicked: function(index, label) {
            if (index < 0 || index >= streamUnitIds.length) return
            const unitId = streamUnitIds[index]
            if (!unitId || unitId === "") return
            deleteErrorDialog.pendingStreamUnitId = unitId
            deleteErrorDialog.pendingStreamLabel = label
            confirmNavigateDialog.message = "Navigate to Stream '" + label + "'?"
            confirmNavigateDialog.open()
        }
    }

    // Inline confirm-navigation popup with Windows-classic 3D raised bevel.
    Popup {
        id: confirmNavigateDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape

        property string title: "Navigate"
        property string message: ""
        property int minWidth: 320

        // Auto-size to fit the message (which embeds a stream name that
        // could be arbitrarily long).
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
            const unitId = deleteErrorDialog.pendingStreamUnitId
            confirmNavigateDialog.close()
            deleteErrorDialog.close()
            if (unitId !== "") root.navigateToStream(unitId)
        }
        function doNo() {
            confirmNavigateDialog.close()
            // Delete Error stays open behind us.
        }

        contentItem: Item {
            id: confirmChrome
            implicitHeight: confirmCol.implicitHeight + 4

            Rectangle { anchors.fill: parent; color: gAppTheme.pvFrame }

            // Outer 3D bevel
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
