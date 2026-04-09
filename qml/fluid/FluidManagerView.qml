import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../common" as Common

Item {
    id: root

    property var fluidManager: gFluidPackageManager
    property var componentManager: gComponentManager

    property string selectedPackageId: ""
    property var selectedPackage: ({})
    property string selectedListId: ""
    property var resolvedCache: []
    property var compositionCache: []  // [{id,massFrac,moleFrac,mw}] parallel to resolvedCache
    property string selectedResolvedId: ""
    property var packageSummary: ({})
    property int componentListVersion: 0   // bumped on componentListsChanged to force combo re-eval

    implicitWidth: 980
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
            resolvedCountLabel.text = "0 components"
            detailSheet.clearAll()
            return
        }
        resolvedCache = componentManager.resolvedComponentsForList(selectedListId)
        compositionCache = (fluidManager && selectedPackageId !== "") ? fluidManager.packageComposition(selectedPackageId) : []
        resolvedCountLabel.text = resolvedCache.length + " components"
        if (resolvedCache.length > 0) {
            selectedResolvedId = resolvedCache[0].id
            loadComponentDetail(resolvedCache[0])
        } else {
            selectedResolvedId = ""
            detailSheet.clearAll()
        }
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

    function loadComponentDetail(c) {
        c = c || {}

        // Find this component in compositionCache (matched by id/name)
        let massFrac = NaN, moleFrac = NaN
        for (let ci = 0; ci < compositionCache.length; ++ci) {
            const cc = compositionCache[ci]
            if (cc.id === (c.id || c.name) || cc.name === (c.name || c.id)) {
                massFrac = cc.massFrac
                moleFrac = cc.moleFrac
                break
            }
        }

        const labels = ["Name","ID","Family","Type","Formula",
                        "MW","Tb (K)","Tc (K)","Pc (Pa)","Omega",
                        "SG @60F","Vol. shift","Source",
                        "Mass fraction","Mole fraction"]
        const values = [
            fmt(c.name || c.id), fmt(c.id), fmt(c.family),
            fmt(c.componentType), fmt(c.formula),
            fmtNum(c.molarMass || c.MW, 4),
            fmtNum(c.normalBoilingPointK || c.Tb, 4),
            fmtNum(c.criticalTemperatureK || c.Tc, 4),
            fmtNum(c.criticalPressurePa || c.Pc, 2),
            fmtNum(c.acentricFactor || c.omega, 6),
            fmtNum(c.specificGravity60F || c.SG, 4),
            fmtNum(c.volumeShiftDelta || c.delta, 6),
            fmt(c.source),
            isFinite(massFrac) ? fmtNum(massFrac, 6) : "—",
            isFinite(moleFrac) ? fmtNum(moleFrac, 6) : "—"
        ]
        detailSheet.clearAll()
        detailSheet.rowLabels = labels
        detailSheet.colLabels = ["Value"]
        for (let i = 0; i < values.length; ++i)
            detailSheet.setCell(i, 0, values[i])
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

    Component.onCompleted: refreshPackages("")

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

    component CompactFrame : Rectangle {
        color: "#e8ebef"; border.color: "#97a2ad"; border.width: 1
    }
    component SectionHeader : Rectangle {
        property alias text: lbl.text
        height: headH; color: "#c8d0d8"; border.color: "#97a2ad"; border.width: 1
        Text {
            id: lbl
            anchors.left: parent.left; anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 10; font.bold: true; color: "#1f2a34"
        }
    }
    component CompactField : TextField {
        implicitHeight: rowH - 4
        font.pixelSize: 10; padding: 2; leftPadding: 4; rightPadding: 4; topPadding: 1; bottomPadding: 1
        selectByMouse: true
        background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
    }

    Rectangle { anchors.fill: parent; color: "#d8dde2" }

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

                Common.ClassicButton { text: "New Package"; fontPixelSize: 10; onClicked: root.newPackage() }
                Common.ClassicButton { text: "Save Package"; fontPixelSize: 10; enabled: pkgNameField.text.trim() !== ""; onClicked: root.saveSelectedPackage() }
                Common.ClassicButton {
                    text: "Delete"; fontPixelSize: 10; enabled: root.selectedPackageId !== ""
                    onClicked: {
                        if (fluidManager.removeFluidPackage(root.selectedPackageId)) {
                            root.selectedPackageId = ""
                            root.refreshPackages("")
                        }
                    }
                }
                Common.ClassicButton {
                    text: "Set Default"; fontPixelSize: 10; enabled: root.selectedPackageId !== ""
                    onClicked: {
                        if (fluidManager.setDefaultFluidPackage(root.selectedPackageId)) {
                            defaultCheck.checked = true
                            statusLabel.text = fluidManager.lastStatus || ""
                        }
                    }
                }
                Common.ClassicButton {
                    text: "Reset Starters"; fontPixelSize: 10
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
            }
        }

        CompactFrame {
            id: leftPane
            x: 6; y: commandBar.height + 6
            width: 230
            height: parent.height - y - 6

            SectionHeader { id: leftHeader; width: parent.width; text: "Fluid Packages" }

            Text {
                x: 6; y: leftHeader.height + 4
                font.pixelSize: 9; color: "#526571"; font.italic: true
                text: fluidManager ? (fluidManager.fluidPackageCount + " packages") : ""
            }

            ListView {
                id: packageListView
                x: 0; y: leftHeader.height + 20
                width: parent.width; height: parent.height - y
                clip: true; spacing: 0
                model: fluidManager ? fluidManager.fluidPackageModel : null
                ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: packageListView.width - 2; height: 46
                    color: (model.id === root.selectedPackageId) ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                    border.color: "#dfe5ea"; border.width: 1

                    MouseArea { anchors.fill: parent; onClicked: root.selectPackage(model.id) }
                    Column {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                        Text {
                            text: root.fmt(model.name || model.id)
                            font.pixelSize: 10; font.bold: true
                            color: (model.id === root.selectedPackageId) ? "white" : "#1f2a34"
                            elide: Text.ElideRight
                            width: parent.width - 10
                        }
                        Text {
                            text: root.componentListNameById(model.componentListId) + "  •  " + root.fmt(model.thermoMethodId || model.propertyMethod)
                            font.pixelSize: 9
                            color: (model.id === root.selectedPackageId) ? "#cce4f8" : "#5b6b75"
                            elide: Text.ElideRight
                            width: parent.width - 10
                        }
                    }
                }
            }
        }

        CompactFrame {
            id: midPane
            x: leftPane.x + leftPane.width + 6
            y: leftPane.y
            width: 320
            height: leftPane.height

            SectionHeader {
                id: midHeader; width: parent.width
                text: root.selectedPackageId === "" ? "Package Editor" : (root.selectedPackage.name || root.selectedPackageId)
            }

            Text { x: 6; y: midHeader.height + 7; text: "Name"; font.pixelSize: 10; color: "#1f2a34" }
            CompactField {
                id: pkgNameField
                x: 70; y: midHeader.height + 5; width: midPane.width - 76
                placeholderText: "Package name"
            }

            Text { x: 6; y: pkgNameField.y + rowH + 5; text: "ID"; font.pixelSize: 10; color: "#1f2a34" }
            CompactField {
                id: pkgIdField
                x: 70; y: pkgNameField.y + rowH + 3; width: midPane.width - 76
                readOnly: true
                background: Rectangle { color: "#f0f2f4"; border.color: "#dfe5ea"; border.width: 1 }
            }

            Text { x: 6; y: pkgIdField.y + rowH + 7; text: "Comp. List"; font.pixelSize: 10; color: "#1f2a34" }
            ComboBox {
                id: componentListCombo
                x: 70; y: pkgIdField.y + rowH + 4; width: midPane.width - 76; height: 22
                font.pixelSize: 10

                // Build model from all available component lists.
                // componentListVersion is referenced to force re-evaluation
                // whenever the Component Manager adds or removes lists.
                model: {
                    void root.componentListVersion  // reactive dependency
                    const lists = root.allComponentLists()
                    const items = [{ id: "", name: "— None —" }]
                    for (let i = 0; i < lists.length; ++i)
                        items.push({ id: root.fmt(lists[i].id), name: root.fmt(lists[i].name || lists[i].id) })
                    return items
                }

                textRole: "name"

                // Keep combo in sync when selectedListId changes externally (e.g. loadPackageDetail)
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
                                componentListCombo.currentIndex = i + 1  // +1 for "None" entry
                                return
                            }
                        }
                        componentListCombo.currentIndex = 0
                    }
                }

                onActivated: {
                    const m = model[currentIndex]
                    root.selectedListId = m ? root.fmt(m.id) : ""
                    root.refreshResolvedComponents()
                    root.refreshPackageSummary()
                }
            }

            CheckBox { id: defaultCheck; x: 4; y: componentListCombo.y + 26; text: "Default package"; font.pixelSize: 10 }

            CompactFrame {
                id: methodSection
                x: 6; y: defaultCheck.y + 28; width: midPane.width - 12; height: 52
                SectionHeader { id: methodHeader; width: parent.width; text: "Thermo Method" }
                Text { x: 8; y: methodHeader.height + 7; text: "Method"; font.pixelSize: 10; color: "#1f2a34" }
                ComboBox {
                    id: eosCombo
                    x: 58; y: methodHeader.height + 4; width: parent.width - 66; height: 22
                    font.pixelSize: 10
                    model: fluidManager ? fluidManager.availableThermoMethods : ["PRSV", "PR", "SRK", "Ideal"]
                    onCurrentTextChanged: root.refreshPackageSummary()
                }
            }

            CompactFrame {
                id: notesSection
                x: 6; y: methodSection.y + methodSection.height + 6; width: midPane.width - 12; height: 162
                SectionHeader { id: notesHeader; width: parent.width; text: "Package Notes" }
                TextArea {
                    id: notesField
                    x: 6; y: notesHeader.height + 4; width: parent.width - 12; height: parent.height - notesHeader.height - 8
                    font.pixelSize: 10; wrapMode: TextArea.Wrap
                    background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
                    padding: 4
                    placeholderText: "Optional notes about this package and where it should be used."
                }
            }

            CompactFrame {
                id: summarySection
                x: 6; y: notesSection.y + notesSection.height + 6; width: midPane.width - 12; height: midPane.height - y - 6
                SectionHeader { id: summaryHeader; width: parent.width; text: "Resolved Package Summary" }
                Text {
                    x: 8; y: summaryHeader.height + 6; width: parent.width - 16
                    font.pixelSize: 10; color: packageSummary.valid ? "#1f2a34" : "#a94442"
                    wrapMode: Text.WordWrap
                    text: root.fmt(packageSummary.status)
                }
                Text {
                    x: 8; y: summaryHeader.height + 30; width: parent.width - 16
                    font.pixelSize: 10; color: "#1f2a34"
                    text: "EOS: " + root.fmt(packageSummary.eosName || eosCombo.currentText)
                }
                Text {
                    x: 8; y: summaryHeader.height + 48; width: parent.width - 16
                    font.pixelSize: 10; color: "#1f2a34"
                    text: "Components: " + root.fmt(packageSummary.componentCount || resolvedCache.length)
                }
                Text {
                    x: 8; y: summaryHeader.height + 66; width: parent.width - 16
                    font.pixelSize: 10; color: "#1f2a34"
                    text: "Support: " + root.fmt((packageSummary.supportFlags || []).join(", "))
                    elide: Text.ElideRight
                }
            }
        }

        CompactFrame {
            id: rightPane
            x: midPane.x + midPane.width + 6
            y: leftPane.y
            width: parent.width - x - 6
            height: leftPane.height

            SectionHeader {
                id: rightHeader; width: parent.width
                text: root.selectedListId !== "" ? ("Package Components  —  " + root.componentListNameById(root.selectedListId)) : "Package Components"
            }

            property int listColW: Math.floor(rightPane.width * 0.45)
            property int detailColX: listColW + 2
            property int detailColW: rightPane.width - detailColX - 4

            CompactFrame {
                id: membersPane
                x: 4; y: rightHeader.height + 4
                width: rightPane.listColW - 4
                height: rightPane.height - rightHeader.height - 10

                SectionHeader { id: membersHeader; width: parent.width; text: "Resolved Components" }
                Text { id: resolvedCountLabel; x: 4; y: membersHeader.height + 4; font.pixelSize: 9; color: "#526571"; text: "0 components" }

                ListView {
                    id: membersList
                    x: 0; y: membersHeader.height + 18
                    width: membersPane.width; height: membersPane.height - y - 4
                    clip: true; spacing: 0
                    model: resolvedCache
                    ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        width: membersList.width - 2; height: 30
                        color: (modelData.id === root.selectedResolvedId) ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                        border.color: "#dfe5ea"; border.width: 1
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedResolvedId = modelData.id
                                root.loadComponentDetail(modelData)
                            }
                        }
                        Column {
                            anchors.fill: parent; anchors.leftMargin: 5; anchors.topMargin: 3; spacing: 0
                            Text {
                                text: modelData.name || modelData.id
                                font.pixelSize: 10; font.bold: true
                                color: (modelData.id === root.selectedResolvedId) ? "white" : "#1f2a34"
                            }
                            Text {
                                text: root.fmt(modelData.id)
                                font.pixelSize: 9
                                color: (modelData.id === root.selectedResolvedId) ? "#cce4f8" : "#7a8a95"
                            }
                        }
                    }
                }
            }

            // ── Detail column: properties (top) + composition editor (bottom) ──
            Item {
                id: detailCol
                x: rightPane.detailColX
                y: rightHeader.height + 4
                width: rightPane.detailColW
                height: rightPane.height - rightHeader.height - 8

                // ── Component Properties spreadsheet ──────────────────────
                CompactFrame {
                    id: detailPane
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: compEditor.top }
                    anchors.bottomMargin: 4

                    SectionHeader { id: detailHeader; width: parent.width; text: "Component Properties" }
                    SimpleSpreadsheet {
                        id: detailSheet
                        x: 0; y: detailHeader.height
                        width: detailPane.width
                        height: detailPane.height - detailHeader.height
                        numRows: 15; numCols: 1
                        colLabels: ["Value"]
                        readOnly: true
                        cellFont: Qt.font({ family: "Segoe UI", pixelSize: 11 })
                        onWidthChanged: {
                            if (width > 0) Qt.callLater(function() {
                                if (root.resolvedCache.length > 0)
                                    root.loadComponentDetail(root.resolvedCache[0])
                            })
                        }
                    }
                }

                // ── Composition editor ────────────────────────────────────
                CompactFrame {
                    id: compEditor
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 220

                    SectionHeader {
                        id: compEditorHdr; width: parent.width
                        text: "Package Composition  (mass fractions)"
                    }

                    // Toolbar: sum indicator + Normalize button
                    Item {
                        id: compEditorToolbar
                        anchors { left: parent.left; right: parent.right; top: compEditorHdr.bottom }
                        height: 24

                        // Compute sum of all edited mass fractions
                        property real fracSum: {
                            var s = 0
                            for (var i = 0; i < root.compositionCache.length; ++i)
                                s += root.compositionCache[i].massFrac
                            return s
                        }

                        Text {
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            text: "Sum: " + compEditorToolbar.fracSum.toFixed(6)
                            font.pixelSize: 10
                            color: Math.abs(compEditorToolbar.fracSum - 1.0) < 1e-4 ? "#1a7a3c" : "#b23b3b"
                        }

                        Rectangle {
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 80; height: 18; radius: 3
                            color: normalizeHover.containsMouse ? "#1a5a90" : "#2e73b8"
                            Text {
                                anchors.centerIn: parent
                                text: "Normalize"; font.pixelSize: 10; font.bold: true; color: "white"
                            }
                            MouseArea {
                                id: normalizeHover; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.compositionCache.length === 0) return
                                    var s = 0
                                    for (var i = 0; i < root.compositionCache.length; ++i)
                                        s += root.compositionCache[i].massFrac
                                    if (s <= 0) return
                                    // Normalize all mass fractions and recompute mole fractions
                                    var newCache = []
                                    for (var j = 0; j < root.compositionCache.length; ++j) {
                                        var entry = root.compositionCache[j]
                                        var mf = entry.massFrac / s
                                        newCache.push({ id: entry.id, name: entry.name, mw: entry.mw,
                                                        massFrac: mf, moleFrac: entry.moleFrac })
                                    }
                                    root.compositionCache = newCache
                                    root._recomputeMoleFracs()
                                    root.loadComponentDetail({ id: root.selectedResolvedId,
                                                               name: root.selectedResolvedId })
                                }
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
                    }

                    // Column headers
                    Item {
                        id: compEditorColHdr
                        anchors { left: parent.left; right: parent.right; top: compEditorToolbar.bottom }
                        height: 18
                        Row {
                            anchors { fill: parent; leftMargin: 6 }
                            Text { width: compEditor.width * 0.40; text: "Component"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"; verticalAlignment: Text.AlignVCenter; height: parent.height }
                            Text { width: compEditor.width * 0.28; text: "Mass frac"; font.pixelSize: 9; font.bold: true; color: "#1f2a34"; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                            Text { width: compEditor.width * 0.28; text: "Mole frac"; font.pixelSize: 9; font.bold: true; color: "#526571"; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: parent.height }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#97a2ad" }
                    }

                    // Composition rows
                    ListView {
                        id: compEditorList
                        anchors { left: parent.left; right: parent.right; top: compEditorColHdr.bottom; bottom: parent.bottom }
                        anchors.bottomMargin: 4
                        clip: true
                        model: root.compositionCache
                        ScrollBar.vertical: ScrollBar { width: 10; policy: ScrollBar.AsNeeded }

                        Text {
                            anchors.centerIn: parent
                            visible: root.compositionCache.length === 0
                            text: "No composition data\n(apply FluidPackageManager C++ files and rebuild)"
                            color: "#97a2ad"; font.pixelSize: 10; font.italic: true
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            width: parent.width - 20
                        }

                        delegate: Item {
                            width: compEditorList.width
                            height: 22
                            property int rowIdx: index

                            Rectangle { anchors.fill: parent; color: index % 2 ? "#f4f6f8" : "#ffffff" }

                            Row {
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }

                                // Component name
                                Text {
                                    width: compEditor.width * 0.40
                                    text: modelData.name || modelData.id
                                    font.pixelSize: 10; color: "#1f2a34"
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                // Editable mass fraction
                                TextField {
                                    id: massFracField
                                    width: compEditor.width * 0.28 - 4
                                    height: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.massFrac.toFixed(6)
                                    horizontalAlignment: Text.AlignRight
                                    font.pixelSize: 10
                                    selectByMouse: true
                                    padding: 2; leftPadding: 4; rightPadding: 4
                                    background: Rectangle {
                                        color: massFracField.activeFocus ? "#fffbe6" : "transparent"
                                        border.color: massFracField.activeFocus ? "#97a2ad" : "transparent"
                                        border.width: 1
                                    }
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^[0-9]*\.?[0-9]*$/
                                    }
                                    onEditingFinished: {
                                        var v = parseFloat(text)
                                        if (!isFinite(v) || v < 0) { text = modelData.massFrac.toFixed(6); return }
                                        // Update compositionCache
                                        var nc = root.compositionCache.slice()
                                        nc[rowIdx] = { id: nc[rowIdx].id, name: nc[rowIdx].name,
                                                       mw: nc[rowIdx].mw, massFrac: v,
                                                       moleFrac: nc[rowIdx].moleFrac }
                                        root.compositionCache = nc
                                        root._recomputeMoleFracs()
                                        root.loadComponentDetail({ id: root.selectedResolvedId,
                                                                   name: root.selectedResolvedId })
                                    }
                                }

                                // Read-only mole fraction
                                Text {
                                    width: compEditor.width * 0.28
                                    text: modelData.moleFrac.toFixed(6)
                                    font.pixelSize: 10; color: "#526571"
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#e8ebef" }
                        }
                    }
                }
            }
        }
    }
}
