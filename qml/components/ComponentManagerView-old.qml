import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../common" as Common

Item {
    id: root
    property var manager: gComponentManager
    property int rowH: 22
    property int headH: 20
    property int currentTab: tabsHeader.currentIndex

    property var filteredComponents: []
    property string selectedComponentId: ""
    property var selectedComponent: ({})

    property var componentListsCache: []
    property string selectedListId: ""
    property var selectedList: ({})
    property var availableComponentsForList: []
    property var memberComponentsForList: []
    property string selectedAvailableComponentId: ""
    property string selectedMemberComponentId: ""

    implicitWidth: 980
    implicitHeight: 720
    focus: true

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

    function currentFamilyValue(combo) {
        if (!combo.currentText || combo.currentText === "All families") return ""
        return combo.currentText
    }

    function rowMeta() {
        return [
            { label: "ID", key: "id" },
            { label: "Name", key: "name" },
            { label: "Formula", key: "formula" },
            { label: "CAS", key: "cas" },
            { label: "Family", key: "family" },
            { label: "Component type", key: "componentType" },
            { label: "Aliases", key: "aliases" },
            { label: "Tags", key: "tags" },
            { label: "Phases", key: "phaseCapabilities" },
            { label: "Source", key: "source" },
            { label: "Molar mass (kg/kmol)", key: "molarMass" },
            { label: "Normal boiling point (K)", key: "normalBoilingPointK" },
            { label: "Critical temperature (K)", key: "criticalTemperatureK" },
            { label: "Critical pressure (Pa)", key: "criticalPressurePa" },
            { label: "Acentric factor", key: "acentricFactor" },
            { label: "Critical volume (m3/kmol)", key: "criticalVolumeM3PerKmol" },
            { label: "Critical compressibility", key: "criticalCompressibility" },
            { label: "Specific gravity @60F", key: "specificGravity60F" },
            { label: "Watson K", key: "watsonK" },
            { label: "Volume shift delta", key: "volumeShiftDelta" }
        ]
    }

    function rowValueFromComponent(key, c) {
        if (!c) return ""
        switch (key) {
        case "aliases": return c.aliases ? c.aliases.join(", ") : ""
        case "tags": return c.tags ? c.tags.join(", ") : ""
        case "phaseCapabilities": return c.phaseCapabilities ? c.phaseCapabilities.join(", ") : ""
        case "molarMass": return fmt(c.molarMass, 6)
        case "normalBoilingPointK": return fmt(c.normalBoilingPointK, 6)
        case "criticalTemperatureK": return fmt(c.criticalTemperatureK, 6)
        case "criticalPressurePa": return fmt(c.criticalPressurePa, 6)
        case "acentricFactor": return fmt(c.acentricFactor, 6)
        case "criticalVolumeM3PerKmol": return fmt(c.criticalVolumeM3PerKmol, 6)
        case "criticalCompressibility": return fmt(c.criticalCompressibility, 6)
        case "specificGravity60F": return fmt(c.specificGravity60F, 6)
        case "watsonK": return fmt(c.watsonK, 6)
        case "volumeShiftDelta": return fmt(c.volumeShiftDelta, 6)
        default: return c[key] || ""
        }
    }

    function worksheetValue(key) {
        const meta = rowMeta()
        for (let i = 0; i < meta.length; ++i)
            if (meta[i].key === key) return componentSheet.getCell(i, 0)
        return ""
    }

    function loadWorksheetFromComponent(c) {
        const meta = rowMeta()
        const labels = []
        for (let i = 0; i < meta.length; ++i) labels.push(meta[i].label)
        componentSheet.clearAll()
        componentSheet.rowLabels = labels
        componentSheet.colLabels = ["Value"]
        for (let i = 0; i < meta.length; ++i)
            componentSheet.setCell(i, 0, rowValueFromComponent(meta[i].key, c))
        notesArea.text = c && c.notes ? c.notes : ""
    }

    function refreshComponentResults(preferredId) {
        if (!manager) return
        filteredComponents = manager.findComponents(componentSearch.text, currentFamilyValue(componentFamilyCombo), componentIncludePseudo.checked)
        let target = preferredId || selectedComponentId
        let found = false
        for (let i = 0; i < filteredComponents.length; ++i) {
            if (filteredComponents[i].id === target) { found = true; break }
        }
        if (!found) target = filteredComponents.length > 0 ? filteredComponents[0].id : ""
        selectedComponentId = target
        selectedComponent = target ? manager.getComponent(target) : ({})
        loadWorksheetFromComponent(selectedComponent)
        Qt.callLater(function() { loadWorksheetFromComponent(selectedComponent) })
        statusLabel.text = manager.lastLoadStatus && manager.lastLoadStatus !== ""
                           ? manager.lastLoadStatus
                           : (filteredComponents.length + " components shown")
    }

    function saveSelectedComponent() {
        if (!manager) return
        const out = {
            id: worksheetValue("id"),
            name: worksheetValue("name"),
            formula: worksheetValue("formula"),
            cas: worksheetValue("cas"),
            family: worksheetValue("family"),
            componentType: worksheetValue("componentType"),
            aliases: worksheetValue("aliases").trim() === "" ? [] : worksheetValue("aliases").split(",").map(s => s.trim()).filter(s => s.length > 0),
            tags: worksheetValue("tags").trim() === "" ? [] : worksheetValue("tags").split(",").map(s => s.trim()).filter(s => s.length > 0),
            phaseCapabilities: worksheetValue("phaseCapabilities").trim() === "" ? [] : worksheetValue("phaseCapabilities").split(",").map(s => s.trim()).filter(s => s.length > 0),
            molarMass: parseNum(worksheetValue("molarMass")),
            normalBoilingPointK: parseNum(worksheetValue("normalBoilingPointK")),
            criticalTemperatureK: parseNum(worksheetValue("criticalTemperatureK")),
            criticalPressurePa: parseNum(worksheetValue("criticalPressurePa")),
            acentricFactor: parseNum(worksheetValue("acentricFactor")),
            criticalVolumeM3PerKmol: parseNum(worksheetValue("criticalVolumeM3PerKmol")),
            criticalCompressibility: parseNum(worksheetValue("criticalCompressibility")),
            specificGravity60F: parseNum(worksheetValue("specificGravity60F")),
            watsonK: parseNum(worksheetValue("watsonK")),
            volumeShiftDelta: parseNum(worksheetValue("volumeShiftDelta")),
            source: worksheetValue("source"),
            notes: notesArea.text
        }
        manager.addOrUpdateComponent(out)
        refreshComponentResults(out.id)
        statusLabel.text = "Saved component: " + (out.name || out.id)
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
        let found = false
        for (let i = 0; i < memberComponentsForList.length; ++i) {
            if (memberComponentsForList[i].id === selectedMemberComponentId) { found = true; break }
        }
        if (!found) selectedMemberComponentId = memberComponentsForList.length > 0 ? memberComponentsForList[0].id : ""
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

    function refreshAvailableComponentsForList() {
        if (!manager) {
            availableComponentsForList = []
            return
        }

        const family = currentFamilyValue(listFamilyCombo)
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
        let found = false
        for (let i = 0; i < availableComponentsForList.length; ++i) {
            if (availableComponentsForList[i].id === selectedAvailableComponentId) { found = true; break }
        }
        if (!found) selectedAvailableComponentId = availableComponentsForList.length > 0 ? availableComponentsForList[0].id : ""
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
        memberDetailSheet.clearAll()
        memberDetailSheet.rowLabels = labels
        memberDetailSheet.colLabels = ["Value"]
        for (let i = 0; i < values.length; ++i)
            memberDetailSheet.setCell(i, 0, values[i])
    }

    Component.onCompleted: {
        componentFamilyCombo.model = familyOptions()
        listFamilyCombo.model = familyOptions()
        Qt.callLater(function() {
            refreshComponentResults("")
            refreshComponentLists("")
            loadListMemberDetail()
            if (selectedComponentId !== "")
                loadWorksheetFromComponent(selectedComponent)
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
        function onErrorOccurred(message) { statusLabel.text = message }
        ignoreUnknownSignals: true
    }

    component CompactFrame : Rectangle {
        color: "#e8ebef"
        border.color: "#97a2ad"
        border.width: 1
    }
    component SectionHeader : Rectangle {
        property alias text: lbl.text
        height: headH
        color: "#c8d0d8"
        border.color: "#97a2ad"
        border.width: 1
        Text { id: lbl; anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 10; font.bold: true; color: "#1f2a34" }
    }
    component CompactButton : Rectangle {
        id: btnRoot
        property alias text: lbl.text
        property bool enabled_: true
        signal clicked
        width: 96
        height: 24
        opacity: enabled_ ? 1.0 : 0.45
        color: !enabled_ ? "#d0d5da" : (ma.pressed ? "#b0b8c2" : (ma.containsMouse ? "#e4e8ed" : "#d8dde3"))
        border.color: ma.pressed ? "#6a7880" : "#97a2ad"
        border.width: 1
        Text { id: lbl; anchors.centerIn: parent; anchors.verticalCenterOffset: ma.pressed ? 1 : 0; font.pixelSize: 10; color: "#1f2a34" }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: btnRoot.enabled_; onClicked: btnRoot.clicked() }
    }
    component CompactField : TextField {
        implicitHeight: rowH - 4
        font.pixelSize: 10
        padding: 2
        leftPadding: 4
        rightPadding: 4
        topPadding: 1
        bottomPadding: 1
        selectByMouse: true
        background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
    }
    component CompactCombo : ComboBox {
        implicitHeight: 22
        font.pixelSize: 10
        leftPadding: 6
        rightPadding: 20
        topPadding: 1
        bottomPadding: 1
        delegate: ItemDelegate {
            width: ListView.view ? ListView.view.width : parent.width
            height: 22
            contentItem: Text {
                text: modelData
                font.pixelSize: 10
                color: "#1f2a34"
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            highlighted: parent.highlightedIndex === index
        }
        contentItem: Text {
            text: parent.displayText
            font.pixelSize: 10
            color: "#1f2a34"
            verticalAlignment: Text.AlignVCenter
            leftPadding: 0
            elide: Text.ElideRight
        }
        background: Rectangle { color: "white"; border.color: "#97a2ad"; border.width: 1 }
    }

    Rectangle { anchors.fill: parent; color: "#d8dde2" }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        color: "#d8dde2"
        border.color: "#6d7883"
        border.width: 1

        Rectangle {
            id: commandBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 74
            color: "#c8d0d8"
            border.color: "#97a2ad"
            border.width: 1

            Common.ClassicTabs {
                id: tabsHeader
                x: 8; y: 6; width: 300
                tabs: [
                    { text: "Components", width: 118 },
                    { text: "Component Lists", width: 132 }
                ]
                currentIndex: 0
            }

            Row {
                x: 8; y: 38; spacing: 6
                visible: tabsHeader.currentIndex === 0
                CompactButton { text: "Import pseudo fluid"; width: 118; onClicked: if (manager && pseudoFluidCombo.currentText !== "") manager.importPseudoComponentFluid(pseudoFluidCombo.currentText, "pseudo-fraction", true) }
                CompactCombo { id: pseudoFluidCombo; width: 180; model: manager ? manager.availableFluidNames : [] }
                CompactButton { text: "Reset starter seed"; width: 112; onClicked: if (manager) manager.resetToStarterSeed() }
                CompactButton { text: "Refresh"; width: 64; onClicked: refreshComponentResults(selectedComponentId) }
                CompactButton { text: "New Component"; width: 92; onClicked: loadWorksheetFromComponent({ source: "user" }) }
                CompactButton { text: "Save"; width: 64; onClicked: saveSelectedComponent() }
                CompactButton { text: "Delete"; width: 64; enabled_: selectedComponentId !== ""; onClicked: if (manager && selectedComponentId !== "") manager.removeComponent(selectedComponentId) }
            }

            Row {
                x: 8; y: 38; spacing: 6
                visible: tabsHeader.currentIndex === 1
                CompactField { id: newListField; width: 180; placeholderText: "New component list name" }
                CompactButton { text: "Create List"; width: 80; enabled_: newListField.text.trim() !== ""; onClicked: { if (!manager) return; const preferred = newListField.text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-+|-+$)/g, ""); if (manager.createComponentList(newListField.text)) { newListField.text = ""; refreshComponentLists(preferred) } } }
                CompactButton { text: "Rename"; width: 64; enabled_: selectedListId !== "" && listNameField.text.trim() !== ""; onClicked: if (manager && manager.renameComponentList(selectedListId, listNameField.text)) refreshComponentLists("") }
                CompactButton { text: "Delete"; width: 64; enabled_: selectedListId !== ""; onClicked: if (manager && selectedListId !== "") manager.removeComponentList(selectedListId) }
                CompactButton { text: "Refresh"; width: 64; onClicked: refreshComponentLists(selectedListId) }
            }

            Text {
                id: statusLabel
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: tabsHeader.verticalCenter
                width: 420
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 10
                color: "#526571"
                elide: Text.ElideRight
                text: manager && manager.lastLoadStatus ? manager.lastLoadStatus : ""
            }
        }

        StackLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: commandBar.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 6
            currentIndex: tabsHeader.currentIndex

            Item {
                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    CompactFrame {
                        Layout.preferredWidth: 280
                        Layout.fillHeight: true
                        SectionHeader { id: compListHeader; width: parent.width; text: "Components" }
                        Text { x: 6; y: compListHeader.height + 4; font.pixelSize: 9; color: "#526571"; font.italic: true; text: filteredComponents.length + " shown" }
                        CompactField { id: componentSearch; x: 6; y: compListHeader.height + 22; width: parent.width - 12; placeholderText: "Search components"; onTextChanged: refreshComponentResults(selectedComponentId) }
                        CompactCombo { id: componentFamilyCombo; x: 6; y: componentSearch.y + 26; width: parent.width - 12; onCurrentIndexChanged: refreshComponentResults(selectedComponentId) }
                        CheckBox { id: componentIncludePseudo; x: 6; y: componentFamilyCombo.y + 26; text: "Include pseudo-components"; checked: true; font.pixelSize: 10; onToggled: refreshComponentResults(selectedComponentId) }
                        ListView {
                            id: componentListView
                            x: 0; y: componentIncludePseudo.y + 24
                            width: parent.width; height: parent.height - y
                            clip: true
                            model: filteredComponents
                            ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                            delegate: Rectangle {
                                width: componentListView.width - 2; height: 44
                                color: modelData.id === selectedComponentId ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                                border.color: "#dfe5ea"; border.width: 1
                                MouseArea { anchors.fill: parent; onClicked: { selectedComponentId = modelData.id; selectedComponent = manager.getComponent(modelData.id); loadWorksheetFromComponent(selectedComponent) } }
                                Column {
                                    anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                                    Text { text: modelData.name || modelData.id; font.pixelSize: 10; font.bold: true; color: modelData.id === selectedComponentId ? "white" : "#1f2a34" }
                                    Text { text: (modelData.family || "") + "  •  " + (modelData.source || "user"); font.pixelSize: 9; color: modelData.id === selectedComponentId ? "#cce4f8" : "#5b6b75" }
                                }
                            }
                        }
                    }

                    CompactFrame {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        SectionHeader { id: worksheetHeader; width: parent.width; text: selectedComponentId === "" ? "Component Worksheet" : (selectedComponent.name || selectedComponentId) }
                        SimpleSpreadsheet {
                            id: componentSheet
                            x: 6; y: worksheetHeader.height + 6
                            width: parent.width - 12
                            height: parent.height - y - 82
                            numCols: 1
                            numRows: rowMeta().length
                        }
                        CompactFrame {
                            x: 6; y: parent.height - 70; width: parent.width - 12; height: 64
                            SectionHeader { id: notesHeader; width: parent.width; text: "Notes" }
                            TextArea {
                                id: notesArea
                                x: 4; y: notesHeader.height + 4
                                width: parent.width - 8; height: parent.height - notesHeader.height - 8
                                wrapMode: TextArea.Wrap
                                font.pixelSize: 10
                                selectByMouse: true
                                background: Rectangle { color: "white"; border.color: "#dfe5ea"; border.width: 1 }
                            }
                        }
                    }
                }
            }

            Item {
                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    CompactFrame {
                        Layout.preferredWidth: 240
                        Layout.fillHeight: true
                        SectionHeader { id: listHeader; width: parent.width; text: "Saved Component Lists" }
                        Text { x: 6; y: listHeader.height + 4; font.pixelSize: 9; color: "#526571"; font.italic: true; text: componentListsCache.length + " lists" }
                        ListView {
                            id: savedListsView
                            x: 0; y: listHeader.height + 20
                            width: parent.width; height: 220
                            clip: true
                            model: manager ? manager.componentListModel : null
                            ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                            delegate: Rectangle {
                                width: savedListsView.width - 2; height: 44
                                color: model.id === selectedListId ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                                border.color: "#dfe5ea"; border.width: 1
                                MouseArea { anchors.fill: parent; onClicked: refreshComponentLists(model.id) }
                                Column {
                                    anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                                    Text { text: model.name || model.id; font.pixelSize: 10; font.bold: true; color: model.id === selectedListId ? "white" : "#1f2a34" }
                                    Text { text: (model.count || 0) + " components  •  " + (model.source || "user"); font.pixelSize: 9; color: model.id === selectedListId ? "#cce4f8" : "#5b6b75" }
                                }
                            }
                        }
                        CompactFrame {
                            x: 6; y: savedListsView.y + savedListsView.height + 6
                            width: parent.width - 12; height: 128
                            SectionHeader { id: detailHeader; width: parent.width; text: "List Details" }
                            Text { x: 6; y: detailHeader.height + 8; text: "Name"; font.pixelSize: 10; color: "#1f2a34" }
                            CompactField { id: listNameField; x: 48; y: detailHeader.height + 6; width: parent.width - 54 }
                            Text { x: 6; y: listNameField.y + 28; text: "ID"; font.pixelSize: 10; color: "#1f2a34" }
                            Text { x: 48; y: listNameField.y + 30; text: selectedListId; font.pixelSize: 10; color: "#526571" }
                            TextArea {
                                id: listNotesArea
                                x: 6; y: listNameField.y + 50; width: parent.width - 12; height: 44
                                readOnly: true
                                wrapMode: TextArea.Wrap
                                font.pixelSize: 10
                                background: Rectangle { color: "#f5f7f9"; border.color: "#dfe5ea"; border.width: 1 }
                            }
                        }
                    }

                    CompactFrame {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        SectionHeader { id: builderHeader; width: parent.width; text: selectedListId === "" ? "Component List Builder" : (selectedList.name || selectedListId) }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: builderHeader.bottom
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            spacing: 6

                            CompactFrame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                SectionHeader { id: availableHeader; width: parent.width; text: "Available Components" }
                                CompactField { id: listSearch; x: 6; y: availableHeader.height + 6; width: parent.width - 12; placeholderText: "Search available components"; onTextChanged: refreshAvailableComponentsForList() }
                                CompactCombo { id: listFamilyCombo; x: 6; y: listSearch.y + 26; width: parent.width - 12; onCurrentIndexChanged: refreshAvailableComponentsForList() }
                                ListView {
                                    id: availableListView
                                    x: 0; y: listFamilyCombo.y + 32
                                    width: parent.width; height: parent.height - y
                                    clip: true
                                    model: availableComponentsForList
                                    ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                    delegate: Rectangle {
                                        width: availableListView.width - 2; height: 38
                                        color: modelData.id === selectedAvailableComponentId ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                                        border.color: "#dfe5ea"; border.width: 1
                                        MouseArea { anchors.fill: parent; onClicked: selectedAvailableComponentId = modelData.id }
                                        Column {
                                            anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                                            Text { text: modelData.name || modelData.id; font.pixelSize: 10; font.bold: true; color: modelData.id === selectedAvailableComponentId ? "white" : "#1f2a34" }
                                            Text {
                                                text: {
                                                    const fam = modelData.family || ""
                                                    const src = modelData.source || ""
                                                    if (modelData.isPseudoComponent && src.indexOf("pseudo-fluid:") === 0)
                                                        return fam + "  •  " + src.substring("pseudo-fluid:".length)
                                                    return fam
                                                }
                                                font.pixelSize: 9
                                                color: modelData.id === selectedAvailableComponentId ? "#cce4f8" : "#5b6b75"
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                Layout.preferredWidth: 90
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 10
                                CompactButton { text: "Add →"; width: 80; enabled_: selectedListId !== "" && selectedAvailableComponentId !== ""; onClicked: if (manager.addComponentToList(selectedListId, selectedAvailableComponentId)) { refreshListMembership(); refreshComponentLists(selectedListId) } }
                                CompactButton { text: "← Remove"; width: 80; enabled_: selectedListId !== "" && selectedMemberComponentId !== ""; onClicked: if (manager.removeComponentFromList(selectedListId, selectedMemberComponentId)) { refreshListMembership(); refreshComponentLists(selectedListId) } }
                            }

                            CompactFrame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                SectionHeader { id: membersHeader; width: parent.width; text: "List Members" }
                                Text { x: 6; y: membersHeader.height + 6; font.pixelSize: 9; color: "#526571"; font.italic: true; text: memberComponentsForList.length + " components" }
                                ListView {
                                    id: memberListView
                                    x: 0; y: membersHeader.height + 22
                                    width: parent.width; height: parent.height - y
                                    clip: true
                                    model: memberComponentsForList
                                    ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }
                                    delegate: Rectangle {
                                        width: memberListView.width - 2; height: 38
                                        color: modelData.id === selectedMemberComponentId ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                                        border.color: "#dfe5ea"; border.width: 1
                                        MouseArea { anchors.fill: parent; onClicked: { selectedMemberComponentId = modelData.id; loadListMemberDetail() } }
                                        Column {
                                            anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                                            Text { text: modelData.name || modelData.id; font.pixelSize: 10; font.bold: true; color: modelData.id === selectedMemberComponentId ? "white" : "#1f2a34" }
                                            Text { text: modelData.id || ""; font.pixelSize: 9; color: modelData.id === selectedMemberComponentId ? "#cce4f8" : "#5b6b75" }
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
