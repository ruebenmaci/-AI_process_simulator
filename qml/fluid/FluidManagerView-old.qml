import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0

Item {
    id: root
    property var fluidManager: gFluidPackageManager
    property var componentManager: gComponentManager

    property string selectedPackageId: ""
    property var selectedPackage: ({})
    property var filteredComponents: []
    property string selectedComponentId: ""
    property var resolvedComponentsCache: []
    property string selectedResolvedComponentId: ""

    function fmt(v) {
        if (v === undefined || v === null || v === "") return ""
        return String(v)
    }

    function parseBool(text) {
        const t = (text || "").trim().toLowerCase()
        return t === "true" || t === "yes" || t === "1" || t === "default"
    }

    function packageRowMeta() {
        return [
            { label: "ID", key: "id" },
            { label: "Name", key: "name" },
            { label: "Selection mode", key: "selectionMode" },
            { label: "Selected crude", key: "selectedCrudeName" },
            { label: "Default package", key: "isDefault" },
            { label: "Resolved count", key: "resolvedComponentCount" }
        ]
    }

    function packageWorksheetValue(key) {
        const meta = packageRowMeta()
        for (let i = 0; i < meta.length; ++i)
            if (meta[i].key === key)
                return packageSheet.getCell(i, 0)
        return ""
    }

    function setPackageWorksheetValue(key, value) {
        const meta = packageRowMeta()
        for (let i = 0; i < meta.length; ++i) {
            if (meta[i].key === key) {
                packageSheet.setCell(i, 0, fmt(value))
                return
            }
        }
    }

    function currentSelectionMode() {
        const mode = packageWorksheetValue("selectionMode").trim()
        return mode === "crudePseudoList" ? "crudePseudoList" : "pureComponents"
    }

    function isCrudeMode() {
        return currentSelectionMode() === "crudePseudoList"
    }

    function familyFilterValue() {
        if (!familyCombo.currentText || familyCombo.currentText === "All families")
            return ""
        return familyCombo.currentText
    }

    function reloadFamilies() {
        const list = ["All families"]
        if (componentManager && componentManager.componentFamilies) {
            for (let i = 0; i < componentManager.componentFamilies.length; ++i)
                list.push(componentManager.componentFamilies[i])
        }
        familyCombo.model = list
        if (list.indexOf(familyCombo.currentText) < 0)
            familyCombo.currentIndex = 0
    }

    function refreshAvailableComponents(preferredId) {
        if (!componentManager)
            return
        filteredComponents = componentManager.findComponents(componentSearchField.text, familyFilterValue(), includePseudoCheck.checked)
        let targetId = preferredId || selectedComponentId
        let found = false
        for (let i = 0; i < filteredComponents.length; ++i) {
            if (filteredComponents[i].id === targetId) {
                found = true
                break
            }
        }
        if (!found)
            targetId = filteredComponents.length > 0 ? filteredComponents[0].id : ""
        selectedComponentId = targetId
        availableCountLabel.text = filteredComponents.length + " shown"
    }

    function loadResolvedSpreadsheet(components) {
        resolvedComponentsCache = components || []
        resolvedSheet.clearAll()
        resolvedSheet.colLabels = ["ID", "Name", "Family", "Type"]
        resolvedSheet.rowLabels = []
        for (let i = 0; i < resolvedSheet.numRows; ++i)
            resolvedSheet.rowLabels.push(String(i + 1))

        for (let i = 0; i < resolvedComponentsCache.length && i < resolvedSheet.numRows; ++i) {
            const c = resolvedComponentsCache[i]
            resolvedSheet.setCell(i, 0, c.id || "")
            resolvedSheet.setCell(i, 1, c.name || c.id || "")
            resolvedSheet.setCell(i, 2, c.family || "")
            resolvedSheet.setCell(i, 3, c.componentType || "")
        }

        let targetId = selectedResolvedComponentId
        let found = false
        for (let i = 0; i < resolvedComponentsCache.length; ++i) {
            if (resolvedComponentsCache[i].id === targetId) {
                found = true
                break
            }
        }
        if (!found)
            targetId = resolvedComponentsCache.length > 0 ? resolvedComponentsCache[0].id : ""
        selectedResolvedComponentId = targetId
        resolvedCountLabel.text = resolvedComponentsCache.length + " resolved components"
    }

    function loadPackageWorksheet(pkg) {
        pkg = pkg || {}
        const meta = packageRowMeta()
        packageSheet.clearAll()
        packageSheet.rowLabels = meta.map(m => m.label)
        packageSheet.colLabels = ["Value"]
        for (let i = 0; i < meta.length; ++i) {
            let value = ""
            switch (meta[i].key) {
            case "isDefault": value = pkg.isDefault ? "true" : "false"; break
            case "resolvedComponentCount": value = fmt(pkg.resolvedComponentCount || 0); break
            default: value = fmt(pkg[meta[i].key])
            }
            packageSheet.setCell(i, 0, value)
        }

        const mode = pkg.selectionMode === "crudePseudoList" ? "crudePseudoList" : "pureComponents"
        modeCombo.currentIndex = mode === "crudePseudoList" ? 0 : 1
        const crudes = fluidManager ? fluidManager.availableCrudeNames : []
        const crudeIdx = crudes.indexOf(pkg.selectedCrudeName || "")
        crudeCombo.currentIndex = crudeIdx >= 0 ? crudeIdx : 0
        defaultPackageCheck.checked = !!pkg.isDefault
        packageNotesArea.text = pkg.notes || ""
    }

    function refreshPackages(preferredId) {
        if (!fluidManager)
            return
        const all = fluidManager.listFluidPackages()
        let targetId = preferredId || selectedPackageId
        let found = false
        for (let i = 0; i < all.length; ++i) {
            if (all[i].id === targetId) {
                found = true
                break
            }
        }
        if (!found)
            targetId = all.length > 0 ? all[0].id : ""
        selectedPackageId = targetId
        selectedPackage = targetId ? fluidManager.getFluidPackage(targetId) : ({})
        loadPackageWorksheet(selectedPackage)
        loadResolvedSpreadsheet(targetId ? fluidManager.resolvedComponents(targetId) : [])
    }

    function saveSelectedPackage() {
        if (!fluidManager)
            return
        const mode = currentSelectionMode()
        const out = {
            id: packageWorksheetValue("id"),
            name: packageWorksheetValue("name"),
            selectionMode: mode,
            selectedCrudeName: mode === "crudePseudoList" ? packageWorksheetValue("selectedCrudeName") : "",
            componentIds: mode === "pureComponents" && selectedPackage && selectedPackage.componentIds ? selectedPackage.componentIds : [],
            notes: packageNotesArea.text,
            isDefault: defaultPackageCheck.checked,
            source: selectedPackage && selectedPackage.source ? selectedPackage.source : "user",
            tags: selectedPackage && selectedPackage.tags ? selectedPackage.tags : ["fluid-package"]
        }
        fluidManager.addOrUpdateFluidPackage(out)
        refreshPackages(out.id)
        statusLabel.text = fluidManager.lastStatus || ""
    }

    Component.onCompleted: {
        reloadFamilies()
        refreshAvailableComponents("")
        refreshPackages("")
    }

    Connections {
        target: fluidManager
        function onFluidPackagesChanged() {
            refreshPackages(selectedPackageId)
            statusLabel.text = fluidManager.lastStatus || ""
        }
        function onErrorOccurred(message) {
            statusLabel.text = message
        }
        ignoreUnknownSignals: true
    }

    Connections {
        target: componentManager
        function onComponentsChanged() {
            reloadFamilies()
            refreshAvailableComponents(selectedComponentId)
            refreshPackages(selectedPackageId)
        }
        ignoreUnknownSignals: true
    }

    Rectangle {
        anchors.fill: parent
        color: "#e9eef2"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Frame {
            Layout.fillWidth: true
            background: Rectangle {
                radius: 8
                color: "#f7fafc"
                border.color: "#c7d3db"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Label {
                    text: "Fluid Package Manager"
                    font.bold: true
                    font.pixelSize: 16
                    color: "#1d2a33"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        text: "New Package"
                        onClicked: {
                            root.selectedPackageId = ""
                            root.selectedPackage = ({ componentIds: [], selectionMode: "pureComponents", tags: ["fluid-package"], source: "user" })
                            loadPackageWorksheet({
                                id: "",
                                name: "",
                                selectionMode: "pureComponents",
                                selectedCrudeName: "",
                                isDefault: false,
                                resolvedComponentCount: 0
                            })
                            loadResolvedSpreadsheet([])
                            statusLabel.text = "Ready to create a new fluid package."
                        }
                    }

                    Button {
                        text: "Save Package"
                        enabled: packageWorksheetValue("name").trim() !== "" || packageWorksheetValue("id").trim() !== ""
                        onClicked: root.saveSelectedPackage()
                    }

                    Button {
                        text: "Delete Package"
                        enabled: root.selectedPackageId !== ""
                        onClicked: {
                            if (fluidManager.removeFluidPackage(root.selectedPackageId)) {
                                root.selectedPackageId = ""
                                root.refreshPackages("")
                            }
                        }
                    }

                    Button {
                        text: "Set Default"
                        enabled: root.selectedPackageId !== ""
                        onClicked: {
                            if (fluidManager.setDefaultFluidPackage(root.selectedPackageId)) {
                                defaultPackageCheck.checked = true
                                setPackageWorksheetValue("isDefault", "true")
                                statusLabel.text = fluidManager.lastStatus
                            }
                        }
                    }

                    Button {
                        text: "Reset Starter Packages"
                        enabled: fluidManager
                        onClicked: {
                            fluidManager.createStarterPackages()
                            root.refreshPackages("")
                            statusLabel.text = fluidManager.lastStatus
                        }
                    }

                    Label {
                        id: statusLabel
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        color: "#51636f"
                        text: fluidManager && fluidManager.lastStatus ? fluidManager.lastStatus : ""
                    }
                }
            }
        }

        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            Frame {
                SplitView.preferredWidth: 340
                SplitView.minimumWidth: 280
                background: Rectangle {
                    radius: 8
                    color: "#f7fafc"
                    border.color: "#c7d3db"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Label {
                        text: "Fluid Packages"
                        font.bold: true
                        color: "#1d2a33"
                    }

                    ListView {
                        id: fluidPackageList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: fluidManager ? fluidManager.listFluidPackages() : []

                        delegate: Rectangle {
                            width: fluidPackageList.width
                            height: 72
                            radius: 8
                            color: (modelData.id === root.selectedPackageId) ? "#d9e7f2" : "#ffffff"
                            border.color: (modelData.id === root.selectedPackageId) ? "#7ea4c3" : "#c9d4dc"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedPackageId = modelData.id
                                    root.refreshPackages(modelData.id)
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 3

                                Row {
                                    spacing: 6
                                    Label { text: modelData.name || modelData.id; font.bold: true; color: "#1d2a33" }
                                    Rectangle {
                                        visible: !!modelData.isDefault
                                        width: defaultTag.implicitWidth + 10
                                        height: 18
                                        radius: 9
                                        color: "#d7efe1"
                                        border.color: "#8ec2a1"
                                        Text { id: defaultTag; anchors.centerIn: parent; text: "Default"; font.pixelSize: 10; color: "#25553a" }
                                    }
                                }
                                Label {
                                    text: [modelData.selectionMode === "crudePseudoList" ? "Crude" : "Pure", (modelData.resolvedComponentCount || 0) + " components"].join("  •  ")
                                    color: "#5b6b75"
                                }
                                Label {
                                    text: modelData.selectionMode === "crudePseudoList" ? (modelData.selectedCrudeName || "") : "Custom pure component list"
                                    color: "#718390"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                    }
                }
            }

            Frame {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 620
                background: Rectangle {
                    radius: 8
                    color: "#f7fafc"
                    border.color: "#c7d3db"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Label {
                        text: root.selectedPackageId === "" ? "Package Definition" : ("Package Definition - " + (root.selectedPackage.name || root.selectedPackageId))
                        font.bold: true
                        color: "#1d2a33"
                    }

                    SplitView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 260
                        orientation: Qt.Horizontal

                        Frame {
                            SplitView.preferredWidth: 420
                            SplitView.minimumWidth: 320
                            background: Rectangle { radius: 8; color: "#ffffff"; border.color: "#d0dae2" }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Label { text: "Package worksheet"; font.bold: true; color: "#1d2a33" }

                                SimpleSpreadsheet {
                                    id: packageSheet
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    numRows: 6
                                    numCols: 1
                                    defaultColW: Math.max(220, width - hdrColW - 4)
                                    colLabels: ["Value"]
                                }
                            }
                        }

                        Frame {
                            SplitView.fillWidth: true
                            SplitView.minimumWidth: 260
                            background: Rectangle { radius: 8; color: "#ffffff"; border.color: "#d0dae2" }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Label { text: "Selection controls"; font.bold: true; color: "#1d2a33" }

                                Label { text: "Selection mode" }
                                ComboBox {
                                    id: modeCombo
                                    Layout.fillWidth: true
                                    model: [
                                        { text: "Crude pseudo list", value: "crudePseudoList" },
                                        { text: "Pure components", value: "pureComponents" }
                                    ]
                                    textRole: "text"
                                    onActivated: {
                                        setPackageWorksheetValue("selectionMode", currentValue)
                                        if (currentValue === "crudePseudoList")
                                            setPackageWorksheetValue("selectedCrudeName", crudeCombo.currentText || "")
                                        else
                                            setPackageWorksheetValue("selectedCrudeName", "")
                                    }
                                    property string selectedModeValue: currentIndex >= 0 ? model[currentIndex].value : "pureComponents"
                                    onCurrentIndexChanged: selectedModeValue = currentIndex >= 0 ? model[currentIndex].value : "pureComponents"                                }

                                Label { text: "Crude list" }
                                ComboBox {
                                    id: crudeCombo
                                    Layout.fillWidth: true
                                    model: fluidManager ? fluidManager.availableCrudeNames : []
                                    enabled: root.isCrudeMode()
                                    onActivated: setPackageWorksheetValue("selectedCrudeName", currentText || "")
                                }

                                CheckBox {
                                    id: defaultPackageCheck
                                    text: "Default fluid package"
                                    onToggled: setPackageWorksheetValue("isDefault", checked ? "true" : "false")
                                }

                                Label { text: root.isCrudeMode() ? "Crude packages reference one of the 5 pseudo-component crude lists." : "Pure packages hold a custom list selected from the warehouse."; wrapMode: Text.WordWrap; color: "#5b6b75" }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    Label { text: "Notes"; font.bold: true; color: "#1d2a33" }
                    TextArea {
                        id: packageNotesArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        wrapMode: TextEdit.Wrap
                        placeholderText: "Notes about this package"
                    }

                    SplitView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        orientation: Qt.Horizontal

                        Frame {
                            visible: !root.isCrudeMode()
                            SplitView.preferredWidth: 360
                            SplitView.minimumWidth: 300
                            background: Rectangle {
                                radius: 8
                                color: "#ffffff"
                                border.color: "#d0dae2"
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Label { text: "Available Components"; font.bold: true; color: "#1d2a33" }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    TextField {
                                        id: componentSearchField
                                        Layout.fillWidth: true
                                        placeholderText: "Search actual components"
                                        onTextChanged: root.refreshAvailableComponents("")
                                    }

                                    ComboBox {
                                        id: familyCombo
                                        Layout.preferredWidth: 170
                                        model: ["All families"]
                                        onCurrentTextChanged: root.refreshAvailableComponents("")
                                    }
                                }

                                CheckBox {
                                    id: includePseudoCheck
                                    text: "Include pseudo-components in search"
                                    checked: false
                                    onToggled: root.refreshAvailableComponents("")
                                }

                                Label { id: availableCountLabel; color: "#6d7d88" }

                                ListView {
                                    id: availableComponentList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 6
                                    model: filteredComponents

                                    delegate: Rectangle {
                                        width: availableComponentList.width
                                        height: 56
                                        radius: 8
                                        color: (modelData.id === root.selectedComponentId) ? "#d9e7f2" : "#ffffff"
                                        border.color: (modelData.id === root.selectedComponentId) ? "#7ea4c3" : "#c9d4dc"

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.selectedComponentId = modelData.id
                                        }

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 2

                                            Label { text: modelData.name || modelData.id; font.bold: true; color: "#1d2a33" }
                                            Label {
                                                text: [modelData.id, modelData.family, modelData.componentType].filter(Boolean).join("  •  ")
                                                color: "#5b6b75"
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }
                                    }
                                }

                                Button {
                                    text: "Add Selected Component"
                                    enabled: root.selectedPackageId !== "" && root.selectedComponentId !== "" && !root.isCrudeMode()
                                    onClicked: {
                                        if (fluidManager.addComponentToPackage(root.selectedPackageId, root.selectedComponentId))
                                            root.refreshPackages(root.selectedPackageId)
                                    }
                                }
                            }
                        }

                        Frame {
                            SplitView.fillWidth: true
                            SplitView.minimumWidth: 360
                            background: Rectangle {
                                radius: 8
                                color: "#ffffff"
                                border.color: "#d0dae2"
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Label {
                                    text: root.isCrudeMode() ? "Resolved Crude Pseudo Components" : "Resolved Package Components"
                                    font.bold: true
                                    color: "#1d2a33"
                                }

                                Label {
                                    text: root.isCrudeMode()
                                          ? "Read-only preview of the pseudo-components coming from the selected crude list."
                                          : "Preview of the currently assigned package components."
                                    wrapMode: Text.WordWrap
                                    color: "#5b6b75"
                                }

                                Label { id: resolvedCountLabel; color: "#6d7d88" }

                                SimpleSpreadsheet {
                                    id: resolvedSheet
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    numRows: 80
                                    numCols: 4
                                    defaultColW: 150
                                    colLabels: ["ID", "Name", "Family", "Type"]
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Button {
                                        text: "Remove Selected Component"
                                        enabled: root.selectedPackageId !== "" && !root.isCrudeMode() && root.selectedResolvedComponentId !== ""
                                        onClicked: {
                                            if (fluidManager.removeComponentFromPackage(root.selectedPackageId, root.selectedResolvedComponentId))
                                                root.refreshPackages(root.selectedPackageId)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            if (!resolvedSheet || !root.resolvedComponentsCache)
                return
            const row = Math.max(0, resolvedSheet.curRow)
            if (row < root.resolvedComponentsCache.length)
                root.selectedResolvedComponentId = root.resolvedComponentsCache[row].id || ""
        }
    }
}
