import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var streamObject
    property var unitObject

    readonly property color panelInset: "#f3f5f9"
    readonly property color border: "#5a5a5a"
    readonly property color textDark: "#1f2430"
    readonly property color textBlue: "#1c4ea7"
    readonly property color mutedText: "#5a6472"

    readonly property bool isProductStream: !!root.streamObject && root.streamObject.productStream
    readonly property bool canEditStream: !!root.streamObject && !root.isProductStream
    readonly property bool canEditCrude: root.canEditStream && !!root.streamObject && root.streamObject.isCrudeFeed

    function fmt0(v) { return Number(v || 0).toFixed(0) }
    function fmt3(v) { return Number(v || 0).toFixed(3) }
    function fmt4(v) { return Number(v || 0).toFixed(4) }
    function fmt6(v) { return Number(v || 0).toFixed(6) }
    function parseOrFallback(text, fallback) {
        const v = Number(text)
        return isNaN(v) ? fallback : v
    }

    Component {
        id: crudeFeedToggleValue
        CheckBox {
            checked: root.streamObject ? root.streamObject.isCrudeFeed : false
            enabled: root.canEditStream
            onToggled: if (root.streamObject) root.streamObject.isCrudeFeed = checked
        }
    }

    Component {
        id: productRoleValue
        Label {
            text: root.streamObject ? root.streamObject.streamName : ""
            color: root.textBlue
            font.bold: true
            font.pixelSize: 11
        }
    }

    Component {
        id: basisCrudeValue
        Label {
            text: root.streamObject ? root.streamObject.selectedFluid : ""
            color: root.textDark
            font.bold: true
            font.pixelSize: 11
        }
    }

    Component {
        id: crudeComboValue
        ComboBox {
            id: crudeCombo
            Layout.preferredWidth: 260
            implicitHeight: 26
            model: root.streamObject ? root.streamObject.fluidNames : []
            enabled: root.canEditCrude
            background: Rectangle {
                radius: 10
                color: "white"
                border.color: "#7c8797"
                border.width: 1
            }
            contentItem: Text {
                text: crudeCombo.displayText
                color: root.canEditCrude ? root.textDark : root.mutedText
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                leftPadding: 10
                rightPadding: 28
            }
            delegate: ItemDelegate {
                width: crudeCombo.width
                contentItem: Text {
                    text: modelData
                    color: "black"
                    elide: Text.ElideRight
                }
            }
            Component.onCompleted: {
                if (root.streamObject && root.streamObject.fluidNames) {
                    const i = root.streamObject.fluidNames.indexOf(root.streamObject.selectedFluid)
                    if (i >= 0)
                        currentIndex = i
                }
            }
            onActivated: if (root.streamObject) root.streamObject.selectedFluid = model[index]
            Connections {
                target: root.streamObject
                function onSelectedFluidChanged() {
                    if (!root.streamObject || !root.streamObject.fluidNames)
                        return
                    const i = root.streamObject.fluidNames.indexOf(root.streamObject.selectedFluid)
                    if (i >= 0 && crudeCombo.currentIndex !== i)
                        crudeCombo.currentIndex = i
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.panelInset
        border.color: root.border
        border.width: 1

        ScrollView {
            anchors.fill: parent
            anchors.margins: 8
            clip: true

            ColumnLayout {
                width: Math.max(availableWidth, 860)
                spacing: 10

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 18
                    rowSpacing: 8
                    enabled: !!root.streamObject

                    Label { text: "Stream type"; color: root.mutedText; font.pixelSize: 11 }
                    Label {
                        text: root.streamObject ? root.streamObject.streamTypeLabel : ""
                        color: root.textDark
                        font.bold: true
                        font.pixelSize: 11
                    }

                    Label {
                        text: root.isProductStream ? "Stream role" : "Is Crude Feed Stream"
                        color: root.mutedText
                        font.pixelSize: 11
                    }
                    Loader {
                        active: true
                        sourceComponent: root.isProductStream ? productRoleValue : crudeFeedToggleValue
                    }

                    Label {
                        text: root.isProductStream ? "Basis crude" : "Crude"
                        color: root.mutedText
                        font.pixelSize: 11
                    }
                    Loader {
                        active: true
                        sourceComponent: root.isProductStream ? basisCrudeValue : crudeComboValue
                    }

                    Label { text: "Name"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        id: streamNameField
                        text: root.unitObject ? (root.unitObject.name || root.unitObject.id) : ""
                        enabled: !!root.streamObject
                        Layout.preferredWidth: 420
                        Layout.minimumWidth: 300
                        implicitWidth: 420
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        maximumLength: 100
                        validator: RegularExpressionValidator {
                            regularExpression: /^[A-Za-z0-9_\-.]{0,100}$/
                        }

                        function normalizedName(rawText) {
                            let value = String(rawText || "")
                            value = value.trim().replace(/\s+/g, "_")
                            value = value.replace(/[^A-Za-z0-9_\-.]/g, "")
                            if (value.length > 100)
                                value = value.substring(0, 100)
                            if (value === "" && root.unitObject)
                                value = root.unitObject.id
                            return value
                        }

                        function commitName() {
                            if (!root.unitObject)
                                return
                            const normalized = normalizedName(text)
                            if (text !== normalized)
                                text = normalized
                            root.unitObject.name = normalized
                        }

                        onTextEdited: {
                            const normalized = normalizedName(text)
                            if (normalized !== text) {
                                const oldPos = cursorPosition
                                text = normalized
                                cursorPosition = Math.min(oldPos, text.length)
                            }
                            if (acceptableInput)
                                root.unitObject.name = text !== "" ? text : root.unitObject.id
                        }

                        onEditingFinished: commitName()
                        onAccepted: commitName()
                    }

                    Label { text: "Flow basis"; color: root.mutedText; font.pixelSize: 11 }
                    ComboBox {
                        id: flowSpecCombo
                        enabled: root.canEditStream
                        Layout.preferredWidth: 140
                        model: ["Mass flow", "Molar flow", "Std. liquid vol. flow"]
                        currentIndex: root.streamObject ? root.streamObject.flowSpecMode : 0
                        onActivated: if (root.streamObject) root.streamObject.flowSpecMode = currentIndex
                    }

                    Label { text: "Thermo spec"; color: root.mutedText; font.pixelSize: 11 }
                    ComboBox {
                        id: thermoSpecCombo
                        enabled: root.canEditStream
                        Layout.preferredWidth: 140
                        model: ["TP", "PH", "PS", "PVF", "TS"]
                        currentIndex: root.streamObject ? root.streamObject.thermoSpecMode : 0
                        onActivated: if (root.streamObject) root.streamObject.thermoSpecMode = currentIndex
                    }

                    Label { text: "Specification status"; color: root.mutedText; font.pixelSize: 11 }
                    Label {
                        text: root.streamObject ? root.streamObject.specificationStatus : ""
                        color: (root.streamObject && root.streamObject.streamSolvable) ? root.textBlue : "#a05a00"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label { text: "Specification note"; color: root.mutedText; font.pixelSize: 11; visible: root.streamObject && !!root.streamObject.specificationError }
                    Label {
                        visible: root.streamObject && !!root.streamObject.specificationError
                        text: root.streamObject ? root.streamObject.specificationError : ""
                        color: "#b23b3b"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label { text: "Mass flow (kg/h)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? fmt0(root.streamObject.flowRateKgph) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.massFlowEditable
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.flowRateKgph = parseOrFallback(text, root.streamObject.flowRateKgph)
                    }

                    Label { text: "Molar flow (kmol/h)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? fmt3(root.streamObject.molarFlowKmolph) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.molarFlowEditable
                        placeholderText: root.streamObject && !root.streamObject.averageMwValid ? "needs composition/MW" : ""
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.molarFlowKmolph = parseOrFallback(text, root.streamObject.molarFlowKmolph)
                    }

                    Label { text: "Std. liquid vol. flow (m³/h)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? fmt3(root.streamObject.standardLiquidVolumeFlowM3ph) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.standardLiquidVolumeFlowEditable
                        placeholderText: root.streamObject && !root.streamObject.referenceDensityValid ? "needs composition/density" : ""
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.standardLiquidVolumeFlowM3ph = parseOrFallback(text, root.streamObject.standardLiquidVolumeFlowM3ph)
                    }

                    Label { text: "Temperature (K)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? fmt3(root.streamObject.temperatureK) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.temperatureEditable
                        placeholderText: root.streamObject && root.streamObject.thermoSpecMode === 3 ? "calculated from PVF" : (root.streamObject && root.streamObject.thermoSpecMode === 4 ? "specified in TS" : "")
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.temperatureK = parseOrFallback(text, root.streamObject.temperatureK)
                    }

                    Label { text: "Pressure (bar)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? (Number(root.streamObject.pressurePa || 0) / 100000.0).toFixed(3) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.pressureEditable
                        placeholderText: root.streamObject && root.streamObject.thermoSpecMode === 4 ? "calculated from TS" : ""
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.pressurePa = parseOrFallback(text, Number(root.streamObject.pressurePa || 0) / 100000.0) * 100000.0
                    }

                    Label { text: "Vapour fraction (-)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject ? fmt4(root.streamObject.specifiedVaporFraction) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.vaporFractionEditable
                        placeholderText: root.streamObject && !root.streamObject.compositionValid ? "needs composition" : ""
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        onEditingFinished: if (root.streamObject) root.streamObject.specifiedVaporFraction = parseOrFallback(text, root.streamObject.specifiedVaporFraction)
                    }

                    Label { text: "Enthalpy (kJ/kg)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject && isFinite(root.streamObject.enthalpyKJkg) ? fmt3(root.streamObject.enthalpyKJkg) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.enthalpyEditable
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        placeholderText: root.streamObject && !root.streamObject.enthalpyEditable ? "calculated" : ""
                        onEditingFinished: if (root.streamObject) root.streamObject.enthalpyKJkg = parseOrFallback(text, root.streamObject.enthalpyKJkg)
                    }

                    Label { text: "Entropy (kJ/kg·K)"; color: root.mutedText; font.pixelSize: 11 }
                    TextField {
                        text: root.streamObject && isFinite(root.streamObject.entropyKJkgK) ? fmt6(root.streamObject.entropyKJkgK) : ""
                        enabled: root.canEditStream && root.streamObject && root.streamObject.entropyEditable && root.streamObject.supportsPS
                        color: root.textDark
                        font.pixelSize: 11
                        selectByMouse: true
                        horizontalAlignment: Text.AlignRight
                        placeholderText: root.streamObject && !root.streamObject.supportsPS ? "PS not implemented" : ""
                        onEditingFinished: if (root.streamObject) root.streamObject.entropyKJkgK = parseOrFallback(text, root.streamObject.entropyKJkgK)
                    }

                    Label { text: "Phase"; color: root.mutedText; font.pixelSize: 11 }
                    Label {
                        text: root.streamObject ? root.streamObject.phaseStatus : ""
                        color: root.textDark
                        font.bold: true
                        font.pixelSize: 11
                    }
                }

                Item {
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: !root.streamObject

            Label {
                text: "No stream selected"
                color: root.textDark
                font.bold: true
            }
        }
    }
}
