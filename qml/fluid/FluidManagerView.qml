import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../common" as Common

Item {
    id: root

    property var fluidManager:     gFluidPackageManager
    property var componentManager: gComponentManager

    // ── Selection state ────────────────────────────────────────────────
    property string selectedPackageId:  ""
    property var    selectedPackage:    ({})
    property string selectedListId:     ""   // selected Component List id
    property var    resolvedCache:      []   // components in selected list
    property string selectedResolvedId: ""

    implicitWidth:  900
    implicitHeight: 660

    property int rowH:  22
    property int headH: 20

    // ── Helpers ────────────────────────────────────────────────────────
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

    // ── Package list ───────────────────────────────────────────────────
    function refreshPackages(preferredId) {
        if (!fluidManager) return
        const all = fluidManager.listFluidPackages()
        let targetId = preferredId || selectedPackageId
        let found = false
        for (let i = 0; i < all.length; ++i)
            if (all[i].id === targetId) { found = true; break }
        if (!found) targetId = all.length > 0 ? all[0].id : ""
        selectedPackageId = targetId
        selectedPackage   = targetId ? fluidManager.getFluidPackage(targetId) : ({})
        loadPackageDetail(selectedPackage)
    }

    // ── Package detail ─────────────────────────────────────────────────
    function loadPackageDetail(pkg) {
        pkg = pkg || {}
        selectedPackage = pkg
        selectedPackageId = fmt(pkg.id)
        pkgNameField.text    = fmt(pkg.name)
        pkgIdField.text      = fmt(pkg.id)
        defaultCheck.checked = !!pkg.isDefault
        const eosList    = fluidManager ? fluidManager.propertyMethods : []
        const eosCurrent = fmt(pkg.propertyMethod) || "Peng-Robinson"
        const eosIdx     = eosList.indexOf(eosCurrent)
        eosCombo.currentIndex = eosIdx >= 0 ? eosIdx : 0

        const linkedListId = fmt(pkg.componentListId)
        if (linkedListId !== "")
            selectList(linkedListId)
        else {
            selectedListId = ""
            resolvedCache = []
            selectedResolvedId = ""
            resolvedCountLabel.text = "0 components"
            detailSheet.clearAll()
        }
    }

    function saveSelectedPackage() {
        if (!fluidManager) return
        const out = {
            id:             selectedPackage && selectedPackage.id ? selectedPackage.id : "",
            name:           pkgNameField.text,
            selectionMode:  "componentList",
            componentListId: selectedListId,
            componentIds:   [],
            propertyMethod: eosCombo.currentText,
            isDefault:      defaultCheck.checked,
            source:         selectedPackage && selectedPackage.source
                            ? selectedPackage.source : "user",
            notes:          "",
            tags:           selectedPackage && selectedPackage.tags
                            ? selectedPackage.tags : ["fluid-package"]
        }
        fluidManager.addOrUpdateFluidPackage(out)
        refreshPackages(out.id)
        statusLabel.text = fluidManager.lastStatus || ""
    }

    // ── Component List selection ───────────────────────────────────────
    function selectList(listId) {
        selectedListId = listId

        if (fluidManager && listId !== "") {
            const allPkgs = fluidManager.listFluidPackages()
            for (let i = 0; i < allPkgs.length; ++i) {
                if (fmt(allPkgs[i].componentListId) === listId && fmt(allPkgs[i].id) !== selectedPackageId) {
                    selectedPackageId = fmt(allPkgs[i].id)
                    selectedPackage = fluidManager.getFluidPackage(selectedPackageId)
                    loadPackageDetail(selectedPackage)
                    return
                }
            }
        }

        if (!componentManager || listId === "") {
            resolvedCache = []
            selectedResolvedId = ""
            resolvedCountLabel.text = "0 components"
            detailSheet.clearAll()
            return
        }
        resolvedCache = componentManager.resolvedComponentsForList(listId)
        resolvedCountLabel.text = resolvedCache.length + " components"
        if (resolvedCache.length > 0) {
            selectedResolvedId = resolvedCache[0].id
            loadComponentDetail(resolvedCache[0])
        } else {
            selectedResolvedId = ""
            detailSheet.clearAll()
        }
    }

    // ── Property detail sheet ──────────────────────────────────────────
    function loadComponentDetail(c) {
        c = c || {}
        const labels = ["Name","ID","Family","Type","Formula",
                        "MW","Tb (K)","Tc (K)","Pc (Pa)","Omega",
                        "SG @60F","Vol. shift","Source"]
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
            fmt(c.source)
        ]
        detailSheet.clearAll()
        detailSheet.rowLabels = labels
        detailSheet.colLabels = ["Value"]
        for (let i = 0; i < values.length; ++i)
            detailSheet.setCell(i, 0, values[i])
    }

    // ── Lifecycle ──────────────────────────────────────────────────────
    Component.onCompleted: {
        refreshPackages("")
    }

    Connections {
        target: fluidManager
        function onFluidPackagesChanged() { refreshPackages(selectedPackageId) }
        function onErrorOccurred(msg)     { statusLabel.text = msg }
        ignoreUnknownSignals: true
    }
    Connections {
        target: componentManager
        function onComponentListsChanged() {
            refreshPackages(selectedPackageId)
        }
        ignoreUnknownSignals: true
    }

    // ──────────────────────────────────────────────────────────────────
    //  Shared primitives
    // ──────────────────────────────────────────────────────────────────
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

    // ──────────────────────────────────────────────────────────────────
    //  Root background
    // ──────────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#d8dde2" }

    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        color: "#d8dde2"; border.color: "#6d7883"; border.width: 1

        // ── Command bar ───────────────────────────────────────────────
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

                Common.ClassicButton {
                    text: "New Package"
                    fontPixelSize: 10
                    onClicked: {
                        root.selectedPackageId = ""
                        root.selectedPackage   = ({ componentIds: [], selectionMode: "componentList",
                                                    propertyMethod: "Peng-Robinson",
                                                    tags: ["fluid-package"], source: "user" })
                        loadPackageDetail(root.selectedPackage)
                        statusLabel.text = "Ready to create a new fluid package."
                    }
                }
                Common.ClassicButton {
                    text: "Save Package"
                    fontPixelSize: 10
                    enabled: pkgNameField.text.trim() !== ""
                    onClicked: root.saveSelectedPackage()
                }
                Common.ClassicButton {
                    text: "Delete"
                    fontPixelSize: 10
                    enabled: root.selectedPackageId !== ""
                    onClicked: {
                        if (fluidManager.removeFluidPackage(root.selectedPackageId)) {
                            root.selectedPackageId = ""
                            root.refreshPackages("")
                        }
                    }
                }
                Common.ClassicButton {
                    text: "Set Default"
                    fontPixelSize: 10
                    enabled: root.selectedPackageId !== ""
                    onClicked: {
                        if (fluidManager.setDefaultFluidPackage(root.selectedPackageId)) {
                            defaultCheck.checked = true
                            statusLabel.text = fluidManager.lastStatus || ""
                        }
                    }
                }
                Common.ClassicButton {
                    text: "Reset Starters"
                    fontPixelSize: 10
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

        // ── Left pane: Component Lists ────────────────────────────────
        CompactFrame {
            id: leftPane
            x: 6; y: commandBar.height + 6
            width: 210
            height: parent.height - y - 6

            SectionHeader { id: leftHeader; width: parent.width; text: "Component Lists" }

            Text {
                x: 6; y: leftHeader.height + 4
                font.pixelSize: 9; color: "#526571"; font.italic: true
                text: componentManager ? (componentManager.componentListCount + " lists") : ""
            }

            ListView {
                id: listView
                x: 0; y: leftHeader.height + 20
                width: parent.width; height: parent.height - y
                clip: true; spacing: 0
                model: componentManager ? componentManager.componentListModel : null
                ScrollBar.vertical: ScrollBar { width: 12; policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: listView.width - 2; height: 44
                    color: (model.id === root.selectedListId)
                           ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
                    border.color: "#dfe5ea"; border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectList(model.id)
                    }
                    Column {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.topMargin: 4; spacing: 2
                        Text {
                            text: root.fmt(model.name || model.title || (modelData && modelData.name) || model.id)
                            font.pixelSize: 10; font.bold: true
                            color: (model.id === root.selectedListId) ? "white" : "#1f2a34"
                            elide: Text.ElideRight
                            width: parent.width - 10
                        }
                        Text {
                            text: root.fmt(model.count || 0) + " components  •  " + root.fmt(model.source || "user")
                            font.pixelSize: 9
                            color: (model.id === root.selectedListId) ? "#cce4f8" : "#5b6b75"
                        }
                    }
                }
            }
        }

        // ── Mid pane: Fluid Package identity + EOS ────────────────────
        CompactFrame {
            id: midPane
            x: leftPane.x + leftPane.width + 6
            y: leftPane.y
            width: 268
            height: leftPane.height

            SectionHeader {
                id: midHeader; width: parent.width
                text: root.selectedPackageId === ""
                      ? "Fluid Package"
                      : (root.selectedPackage.name || root.selectedPackageId)
            }

            // Name
            Text { x:6; y: midHeader.height + 7; text:"Name"; font.pixelSize:10; color:"#1f2a34" }
            CompactField {
                id: pkgNameField
                x:46; y: midHeader.height + 5; width: midPane.width - 52
                placeholderText: "Package name"
            }

            // ID (read-only)
            Text { x:6; y: pkgNameField.y + rowH + 3; text:"ID"; font.pixelSize:10; color:"#1f2a34" }
            CompactField {
                id: pkgIdField
                x:46; y: pkgNameField.y + rowH + 3; width: midPane.width - 52
                placeholderText: "(auto-generated)"; readOnly: true
                background: Rectangle { color:"#f0f2f4"; border.color:"#dfe5ea"; border.width:1 }
            }

            // Default checkbox
            CheckBox {
                id: defaultCheck
                x:4; y: pkgIdField.y + rowH + 4
                text: "Default package"; font.pixelSize: 10
            }

            // Linked Component List (read-only display)
            CompactFrame {
                id: linkedListSection
                x:6; y: defaultCheck.y + 28; width: midPane.width - 12
                height: linkedHeader.height + rowH + 8

                SectionHeader { id: linkedHeader; width: parent.width; text: "Component List" }
                Text {
                    x:8; y: linkedHeader.height + 6
                    width: parent.width - 16
                    text: root.selectedListId !== ""
                          ? (componentManager
                             ? (componentManager.getComponentList(root.selectedListId).name || root.selectedListId)
                             : root.selectedListId)
                          : "No list selected — pick one from the left"
                    font.pixelSize: 10
                    color: root.selectedListId !== "" ? "#1c4ea7" : "#7a8a95"
                    font.italic: root.selectedListId === ""
                    wrapMode: Text.WordWrap
                }
            }

            // Property Package (EOS)
            CompactFrame {
                id: eosSection
                x:6; y: linkedListSection.y + linkedListSection.height + 6
                width: midPane.width - 12

                SectionHeader { id: eosHeader; width: parent.width; text: "Property Package" }

                Text {
                    x:8; y: eosHeader.height + 6; width: parent.width - 16
                    text: "Equation of State / Property Method"
                    font.pixelSize: 10; color: "#1f2a34"
                }
                ComboBox {
                    id: eosCombo
                    x:8; y: eosHeader.height + 24; width: parent.width - 16; height: 22
                    font.pixelSize: 10
                    model: fluidManager ? fluidManager.propertyMethods
                                        : ["Peng-Robinson","PRSV","SRK","Ideal","Raoult's Law"]
                }
                Rectangle {
                    x:8; y: eosHeader.height + 52; width: parent.width - 16
                    height: eosHint.implicitHeight + 10
                    color: "#eef3f7"; border.color: "#c8d4dc"; border.width:1; radius:2
                    Text {
                        id: eosHint
                        x:6; y:5; width: parent.width - 12
                        font.pixelSize: 9; color: "#3d5260"; wrapMode: Text.WordWrap
                        text: {
                            switch (eosCombo.currentText) {
                            case "Peng-Robinson": return "PR — Hydrocarbons, gas processing, refining. Best general-purpose choice."
                            case "PRSV":          return "PRSV — PR with Stryjek-Vera correction. Better accuracy for polar/non-ideal systems."
                            case "SRK":           return "SRK — Soave-Redlich-Kwong. Similar to PR; widely used for gas-phase systems."
                            case "Ideal":         return "Ideal gas law. Only suitable for ideal, low-pressure vapour mixtures."
                            case "Raoult's Law":  return "Modified Raoult's Law. Simple VLE for near-ideal liquid mixtures."
                            default:              return ""
                            }
                        }
                    }
                }
                height: eosHeader.height + 110
            }

            // Enthalpy / Transport placeholder
            CompactFrame {
                x:6; y: eosSection.y + eosSection.height + 6
                width: midPane.width - 12
                height: midPane.height - y - 6

                SectionHeader { width: parent.width; text: "Enthalpy / Transport Correlations" }
                Text {
                    x:8; y: headH + 8; width: parent.width - 16
                    font.pixelSize: 9; color: "#7a8a95"; wrapMode: Text.WordWrap
                    text: "Viscosity, thermal conductivity, surface tension, and enthalpy correlation overrides will be configured here in a future release."
                }
            }
        }

        // ── Right pane: list members + property detail ─────────────────
        CompactFrame {
            id: rightPane
            x: midPane.x + midPane.width + 6
            y: leftPane.y
            width: parent.width - x - 6
            height: leftPane.height

            SectionHeader {
                id: rightHeader; width: parent.width
                text: root.selectedListId !== ""
                      ? ("Components  —  " + (componentManager
                         ? (componentManager.getComponentList(root.selectedListId).name || root.selectedListId)
                         : root.selectedListId))
                      : "Components"
            }

            property int listColW:   Math.floor(rightPane.width * 0.48)
            property int detailColX: listColW + 2
            property int detailColW: rightPane.width - detailColX - 4

            // ── Members list ──────────────────────────────────────────
            CompactFrame {
                id: membersPane
                x: 4; y: rightHeader.height + 4
                width: rightPane.listColW - 4
                height: rightPane.height - rightHeader.height - 10

                SectionHeader { id: membersHeader; width: parent.width; text: "List Members" }

                Text {
                    id: resolvedCountLabel
                    x:4; y: membersHeader.height + 4
                    font.pixelSize: 9; color: "#526571"; text: "0 components"
                }

                ListView {
                    id: membersList
                    x:0; y: membersHeader.height + 18
                    width: membersPane.width; height: membersPane.height - y - 4
                    clip: true; spacing: 0
                    model: resolvedCache
                    ScrollBar.vertical: ScrollBar { width:12; policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        width: membersList.width - 2; height: 30
                        color: (modelData.id === root.selectedResolvedId)
                               ? "#2e73b8" : (index % 2 ? "#f4f6f8" : "#ffffff")
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
                            Row {
                                spacing: 4
                                Text {
                                    text: modelData.name || modelData.id
                                    font.pixelSize: 10; font.bold: true
                                    color: (modelData.id === root.selectedResolvedId) ? "white" : "#1f2a34"
                                }
                                Text {
                                    text: modelData.formula ? ("(" + modelData.formula + ")") : ""
                                    font.pixelSize: 10
                                    color: (modelData.id === root.selectedResolvedId) ? "#d4ecff" : "#5b6b75"
                                }
                            }
                            Text {
                                text: fmt(modelData.id)
                                font.pixelSize: 9
                                color: (modelData.id === root.selectedResolvedId) ? "#cce4f8" : "#7a8a95"
                            }
                        }
                    }
                }
            }

            // ── Property detail sheet ─────────────────────────────────
            CompactFrame {
                id: detailPane
                x: rightPane.detailColX
                y: rightHeader.height + 4
                width: rightPane.detailColW
                height: rightPane.height - rightHeader.height - 8

                SectionHeader { id: detailHeader; width: parent.width; text: "Component Properties" }

                SimpleSpreadsheet {
                    id: detailSheet
                    x:0; y: detailHeader.height
                    width: detailPane.width
                    height: detailPane.height - detailHeader.height
                    numRows: 13; numCols: 1
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
        }
    }
}
