import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.qmlmodels 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    property var appState: null
    property bool debugAppStateLogs: false
    property string currentWorksheetTab: "Design"

    function logAppStateStatus(source) {
        if (!debugAppStateLogs)
            return;

        const hasRoot = root.appState !== null && root.appState !== undefined;
        const globalVisible = (typeof appState !== "undefined") && appState !== null && appState !== undefined;
        const selectedCrude = hasRoot && root.appState.feedStream.selectedFluid !== undefined ? root.appState.feedStream.selectedFluid : "<n/a>";
        const trays = hasRoot && root.appState.trays !== undefined ? root.appState.trays : "<n/a>";
        const solving = hasRoot && root.appState.solving !== undefined ? root.appState.solving : "<n/a>";

        console.log("HysysColumnMockup [" + source + "] hasRootAppState=", hasRoot,
                    "globalSymbolVisible=", globalVisible,
                    "selectedCrude=", selectedCrude,
                    "trays=", trays,
                    "solving=", solving,
                    "root.appState=", root.appState);
    }

    onAppStateChanged: {
        logAppStateStatus("onAppStateChanged");
        if (hasAppState())
            root.syncFromAppState();
    }

    function hasAppState() {
        return root.appState !== null && root.appState !== undefined;
    }
    function keyOf(combo) {
        if (!combo || combo.currentIndex < 0 || !combo.model)
            return "none";
        const k = combo.model[combo.currentIndex].k;
        return (k === undefined || k === null) ? "none" : String(k);
    }
    function isNoneSpec(combo) {
        return keyOf(combo) === "none";
    }
    function isSpec(combo, k) {
        return keyOf(combo) === k;
    }

    function syncFromAppState() {
        if (!hasAppState())
            return;
        const cType = root.appState.condenserType || "total";
        if (condTypeCombo)
            condTypeCombo.currentIndex = (cType === "partial") ? 1 : 0;

        const rType = root.appState.reboilerType || "partial";
        if (rebTypeCombo)
            rebTypeCombo.currentIndex = (rType === "total") ? 1 : 0;

        if (condSpecCombo) {
            const raw = (root.appState.condenserSpec === undefined || root.appState.condenserSpec === null) ? "" : String(root.appState.condenserSpec);
            const v = raw.trim().toLowerCase();
            const map = {
                "": "none",
                "none": "none",
                "refluxratio": "reflux",
                "reflux": "reflux",
                "duty": "duty",
                "temperature": "temperature"
            };
            const kk = map[v] || "reflux";
            for (let i = 0; i < condSpecCombo.model.length; ++i) {
                if (condSpecCombo.model[i].k === kk) {
                    condSpecCombo.currentIndex = i;
                    break;
                }
            }
        }

        if (rebSpecCombo) {
            const raw = (root.appState.reboilerSpec === undefined || root.appState.reboilerSpec === null) ? "" : String(root.appState.reboilerSpec);
            const v = raw.trim().toLowerCase();
            const map = {
                "": "none",
                "none": "none",
                "boilupratio": "boilup",
                "boilup": "boilup",
                "duty": "duty",
                "temperature": "temperature"
            };
            const kk = map[v] || "boilup";
            for (let i = 0; i < rebSpecCombo.model.length; ++i) {
                if (rebSpecCombo.model[i].k === kk) {
                    rebSpecCombo.currentIndex = i;
                    break;
                }
            }
        }

        if (topTsetField && !topTsetField.activeFocus)
            topTsetField.text = String(root.appState.topTsetK);
        if (refluxRatioField && !refluxRatioField.activeFocus)
            refluxRatioField.text = String(root.appState.refluxRatio);
        if (qcField && !qcField.activeFocus)
            qcField.text = String(root.appState.qcKW);
        if (bottomTsetField && !bottomTsetField.activeFocus)
            bottomTsetField.text = String(root.appState.bottomTsetK);
        if (boilupRatioField && !boilupRatioField.activeFocus)
            boilupRatioField.text = String(root.appState.boilupRatio);
        if (qrField && !qrField.activeFocus)
            qrField.text = String(root.appState.qrKW);

        if (crudeCombo && crudeCombo.model && root.appState.feedStream.fluidNames) {
            const crudeIdx = root.appState.feedStream.fluidNames.indexOf(root.appState.feedStream.selectedFluid);
            if (crudeIdx >= 0 && crudeCombo.currentIndex !== crudeIdx)
                crudeCombo.currentIndex = crudeIdx;
        }

        if (feedRateField && !feedRateField.activeFocus)
            feedRateField.text = String(root.appState.feedStream.flowRateKgph);
        if (feedTempField && !feedTempField.activeFocus)
            feedTempField.text = String(root.appState.feedStream.temperatureK);
        if (trayCountSpin && !trayCountSpin.activeFocus)
            trayCountSpin.value = root.appState.trays;
        if (feedTraySpin && !feedTraySpin.activeFocus) {
            feedTraySpin.to = Math.max(1, root.appState.trays || 1);
            feedTraySpin.value = root.appState.feedTray;
        }
        if (topPressureField && !topPressureField.activeFocus)
            topPressureField.text = String(root.appState.topPressurePa);
        if (dpField && !dpField.activeFocus)
            dpField.text = String(root.appState.dpPerTrayPa);
    }

    Component.onCompleted: {
        logAppStateStatus("onCompleted-before-autowire");

        if (!hasAppState() && (typeof appState !== "undefined") && appState) {
            root.appState = appState;
            console.log("HysysColumnMockup: auto-wired global appState into root.appState");
        }

        logAppStateStatus("onCompleted-after-autowire");
        root.syncFromAppState();
    }

    readonly property color bg: "#dfe4ee"
    readonly property color chrome: "#d2d9e6"
    readonly property color panel: "#e9edf5"
    readonly property color panelInset: "#f4f6fa"
    readonly property color border: "#2a2a2a"
    readonly property color activeBlue: "#2e76db"
    readonly property color textDark: "#1f2430"
    readonly property color textBlue: "#1c4ea7"
    readonly property color solveGreen: "#4c9c78"
    readonly property color solveGreenDark: "#3f8e6d"

    // Right-side worksheet widths
    readonly property int rhsComboLabelWidth: 52
    readonly property int rhsFieldLabelWidth: 118
    readonly property int rhsFieldWidth: 72
    readonly property int rhsLabelWidth: 121
    readonly property int rhsWideCrudeWidth: 157
    readonly property int rhsWideComboWidth: 146
    readonly property int lhsLabelWidth: 118

    Connections {
        target: root.hasAppState() ? root.appState : null
        function onCondenserTypeChanged() {
            root.syncFromAppState();
        }
        function onReboilerTypeChanged() {
            root.syncFromAppState();
        }
        function onCondenserSpecChanged() {
            root.syncFromAppState();
        }
        function onReboilerSpecChanged() {
            root.syncFromAppState();
        }
        function onTopTsetKChanged() {
            if (topTsetField && !topTsetField.activeFocus)
                topTsetField.text = String(root.appState.topTsetK);
        }
        function onRefluxRatioChanged() {
            if (refluxRatioField && !refluxRatioField.activeFocus)
                refluxRatioField.text = String(root.appState.refluxRatio);
        }
        function onQcKWChanged() {
            if (qcField && !qcField.activeFocus)
                qcField.text = String(root.appState.qcKW);
        }
        function onBottomTsetKChanged() {
            if (bottomTsetField && !bottomTsetField.activeFocus)
                bottomTsetField.text = String(root.appState.bottomTsetK);
        }
        function onBoilupRatioChanged() {
            if (boilupRatioField && !boilupRatioField.activeFocus)
                boilupRatioField.text = String(root.appState.boilupRatio);
        }
        function onQrKWChanged() {
            if (qrField && !qrField.activeFocus)
                qrField.text = String(root.appState.qrKW);
        }
        function onSelectedCrudeChanged() {
            root.syncFromAppState();
        }
        function onFeedRateKgphChanged() {
            if (feedRateField && !feedRateField.activeFocus)
                feedRateField.text = String(root.appState.feedStream.flowRateKgph);
        }
        function onFeedTempKChanged() {
            if (feedTempField && !feedTempField.activeFocus)
                feedTempField.text = String(root.appState.feedStream.temperatureK);
        }
        function onTraysChanged() {
            if (trayCountSpin && !trayCountSpin.activeFocus)
                trayCountSpin.value = root.appState.trays;
            if (feedTraySpin)
                feedTraySpin.to = Math.max(1, root.appState.trays || 1);
        }
        function onFeedTrayChanged() {
            if (feedTraySpin && !feedTraySpin.activeFocus)
                feedTraySpin.value = root.appState.feedTray;
        }
        function onTopPressurePaChanged() {
            if (topPressureField && !topPressureField.activeFocus)
                topPressureField.text = String(root.appState.topPressurePa);
        }
        function onDpPerTrayPaChanged() {
            if (dpField && !dpField.activeFocus)
                dpField.text = String(root.appState.dpPerTrayPa);
        }
    }

    component MockupCombo: ComboBox {
        implicitHeight: 24
        enabled: !root.hasAppState() || !root.appState.solving
        textRole: "t"

        background: Rectangle {
            radius: 4
            color: "#eef2f8"
            border.color: root.border
        }

        contentItem: Text {
            text: parent.displayText
            font.pixelSize: 10
            color: root.textDark
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
            rightPadding: 28
            elide: Text.ElideRight
        }

        delegate: ItemDelegate {
            width: parent.width
            contentItem: Text {
                text: modelData.t !== undefined ? modelData.t : modelData
                color: "black"
                font.pixelSize: 10
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        indicator: Canvas {
            x: parent.width - width - 8
            y: (parent.height - height) / 2
            width: 10
            height: 6
            contextType: "2d"
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = root.textDark;
                ctx.beginPath();
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    component MockupField: TextField {
        implicitHeight: 24
        enabled: !root.hasAppState() || !root.appState.solving
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        color: root.textBlue
        font.pixelSize: 10
        leftPadding: 10
        rightPadding: 10
        selectByMouse: true

        background: Rectangle {
            radius: 4
            color: "#eef2f8"
            border.color: root.border
        }
    }

    component MockupSpin: SpinBox {
        implicitHeight: 24
        editable: true
        enabled: !root.hasAppState() || !root.appState.solving

        background: Rectangle {
            radius: 4
            color: "#eef2f8"
            border.color: root.border
        }

        contentItem: TextInput {
            text: parent.value
            font.pixelSize: 10
            color: root.textBlue
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            readOnly: !parent.editable
            inputMethodHints: Qt.ImhDigitsOnly
        }
    }

    Rectangle {
        anchors.fill: parent
        color: bg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 10
        anchors.topMargin: 0
        spacing: 0



        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Tab bar — rounded pill buttons matching stream view style
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Repeater {
                            model: ["Design", "Draws", "Tray Profile", "Run Results", "Run Log"]
                            delegate: Rectangle {
                                readonly property bool selected: modelData === root.currentWorksheetTab
                                width: {
                                    if (modelData === "Draws")   return 110
                                    if (modelData === "Tray Profile")  return 110
                                    if (modelData === "Run Results")   return 106
                                    if (modelData === "Run Log")       return 86
                                    return 80
                                }
                                height: 28
                                radius: 10
                                color: selected ? activeBlue : "#cfd4dc"
                                border.color: "#3f3f3f"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: parent.selected ? "white" : textDark
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentWorksheetTab = modelData
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: designWorkspacePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.currentWorksheetTab === "Design"
                    color: bg
                    border.color: border
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 8

                        // ── Column name field ──────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 500
                            spacing: 10

                            Text {
                                text: "Column name"
                                font.pixelSize: 11
                                color: textDark
                                font.bold: true
                                Layout.preferredWidth: 90
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 24
                                radius: 4
                                color: "#eef2f8"
                                border.color: "#9eacbf"
                                border.width: 1

                                TextInput {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 11
                                    color: textDark
                                    selectByMouse: true
                                    maximumLength: 100
                                    text: root.appState ? (root.appState.name || root.appState.id || "") : ""
                                    validator: RegularExpressionValidator { regularExpression: /^[A-Za-z0-9_\-.]{0,100}$/ }
                                    onTextChanged: {
                                        if (!root.appState) return
                                        let value = String(text || "").trim().replace(/\s+/g, "_")
                                        value = value.replace(/[^A-Za-z0-9_\-.]/g, "")
                                        if (value !== "") root.appState.name = value
                                    }
                                    onEditingFinished: {
                                        if (!root.appState) return
                                        let value = String(text || "").trim().replace(/\s+/g, "_")
                                        value = value.replace(/[^A-Za-z0-9_\-.]/g, "")
                                        if (value === "") value = root.appState.id
                                        text = value
                                        root.appState.name = value
                                    }
                                }
                            }
                        }


                        // ── EOS mode ─────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: "EOS mode"
                                font.pixelSize: 10
                                color: textDark
                                font.bold: true
                                Layout.preferredWidth: 60
                            }

                            MockupCombo {
                                id: designEosModeCombo
                                Layout.preferredWidth: 180
                                model: [
                                    { k: "auto",   t: "Auto (by tray/crude)" },
                                    { k: "manual", t: "Manual" }
                                ]
                                Component.onCompleted: {
                                    currentIndex = (root.hasAppState() && root.appState.eosMode === "manual") ? 1 : 0;
                                }
                                onActivated: { if (root.hasAppState()) root.appState.eosMode = model[index].k; }
                            }

                            Text {
                                text: "Manual EOS"
                                font.pixelSize: 10
                                color: textDark
                                font.bold: true
                            }

                            MockupCombo {
                                id: designManualEosCombo
                                Layout.preferredWidth: 100
                                enabled: (!root.hasAppState() || !root.appState.solving) && (!root.hasAppState() || root.appState.eosMode === "manual")
                                model: [
                                    { k: "PR",   t: "PR"   },
                                    { k: "PRSV", t: "PRSV" },
                                    { k: "SRK",  t: "SRK"  }
                                ]
                                Component.onCompleted: {
                                    const v = root.hasAppState() ? (root.appState.eosManual || "PRSV") : "PRSV";
                                    const vals = ["PR","PRSV","SRK"];
                                    const idx = vals.indexOf(v);
                                    currentIndex = idx >= 0 ? idx : 1;
                                }
                                onActivated: { if (root.hasAppState()) root.appState.eosManual = model[index].k; }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            Rectangle {
                                id: diagramPanel
                                Layout.preferredWidth: 590
                                Layout.fillHeight: true
                                radius: 8
                                color: panelInset
                                border.color: border

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    anchors.topMargin: 8

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 12

                                        ColumnLayout {
                                            id: leftSpecsColumn
                                            Layout.preferredWidth: 120
                                            Layout.alignment: Qt.AlignTop
                                            Layout.fillHeight: false
                                            spacing: 10

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: feedGrid.implicitHeight + 36
                                                radius: 6
                                                color: panelInset
                                                border.color: border

                                                Text {
                                                    x: 12
                                                    y: 8
                                                    text: "Feed"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: textDark
                                                }

                                                Item {
                                                    id: feedGrid
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 10
                                                    anchors.topMargin: 26
                                                    implicitHeight: childrenRect.height

                                                    GridLayout {
                                                        id: crudeGrid
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        columns: 2
                                                        columnSpacing: 8
                                                        rowSpacing: 0

                                                        Text {
                                                            text: "Crude"
                                                            color: textDark
                                                            font.pixelSize: 10
                                                            Layout.preferredWidth: 25
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        MockupCombo {
                                                            id: crudeCombo
                                                            Layout.preferredWidth: root.rhsWideCrudeWidth
                                                            Layout.maximumWidth: root.rhsWideCrudeWidth
                                                            model: root.hasAppState() ? root.appState.feedStream.fluidNames.map(function (name) {
                                                                return {
                                                                    k: name,
                                                                    t: name
                                                                };
                                                            }) : [
                                                                {
                                                                    k: "Brent",
                                                                    t: "Brent"
                                                                },
                                                                {
                                                                    k: "West Texas Intermediate",
                                                                    t: "West Texas Intermediate"
                                                                },
                                                                {
                                                                    k: "Arab Light",
                                                                    t: "Arab Light"
                                                                },
                                                                {
                                                                    k: "Western Canadian Select",
                                                                    t: "Western Canadian Select"
                                                                },
                                                                {
                                                                    k: "Venezuelan Heavy",
                                                                    t: "Venezuelan Heavy"
                                                                }
                                                            ]
                                                            Component.onCompleted: root.syncFromAppState()
                                                            onActivated: {
                                                                if (root.hasAppState() && index >= 0 && index < model.length)
                                                                    root.appState.feedStream.selectedFluid = model[index].k;
                                                            }
                                                        }
                                                    }

                                                    GridLayout {
                                                        id: feedRateTempGrid
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.margins: 0
                                                        anchors.topMargin: 32
                                                        columns: 2
                                                        columnSpacing: 8
                                                        rowSpacing: 8

                                                        Text {
                                                            text: "Feed rate  (kg/h)"
                                                            color: textDark
                                                            font.pixelSize: 10
                                                            Layout.preferredWidth: lhsLabelWidth
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        MockupField {
                                                            id: feedRateField
                                                            Layout.preferredWidth: rhsFieldWidth
                                                            Layout.maximumWidth: rhsFieldWidth
                                                            validator: DoubleValidator {
                                                                bottom: 0
                                                            }
                                                            onEditingFinished: if (root.hasAppState())
                                                                root.appState.feedStream.flowRateKgph = Number(text)
                                                            Component.onCompleted: root.syncFromAppState()
                                                        }

                                                        Text {
                                                            text: "Feed temp.  (K)"
                                                            color: textDark
                                                            font.pixelSize: 10
                                                            Layout.preferredWidth: lhsLabelWidth
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        MockupField {
                                                            id: feedTempField
                                                            Layout.preferredWidth: rhsFieldWidth
                                                            Layout.maximumWidth: rhsFieldWidth
                                                            validator: DoubleValidator {
                                                                bottom: 0
                                                            }
                                                            onEditingFinished: if (root.hasAppState())
                                                                root.appState.feedStream.temperatureK = Number(text)
                                                            Component.onCompleted: root.syncFromAppState()
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: traysGrid.implicitHeight + 42
                                                radius: 6
                                                color: panelInset
                                                border.color: border

                                                Text {
                                                    x: 12
                                                    y: 8
                                                    text: "Trays"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: textDark
                                                }

                                                GridLayout {
                                                    id: traysGrid
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 10
                                                    anchors.topMargin: 32
                                                    columns: 2
                                                    columnSpacing: 8
                                                    rowSpacing: 8

                                                    Text {
                                                        text: "Tray count"
                                                        color: textDark
                                                        font.pixelSize: 10
                                                        Layout.preferredWidth: lhsLabelWidth
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    MockupSpin {
                                                        id: trayCountSpin
                                                        Layout.preferredWidth: rhsFieldWidth
                                                        Layout.maximumWidth: rhsFieldWidth
                                                        from: root.hasAppState() && root.appState.minTrays !== undefined ? root.appState.minTrays : 1
                                                        to: root.hasAppState() && root.appState.maxTrays !== undefined ? root.appState.maxTrays : 200
                                                        value: root.hasAppState() && root.appState.trays !== undefined ? root.appState.trays : 32
                                                        onValueModified: if (root.hasAppState())
                                                            root.appState.trays = value
                                                        Component.onCompleted: root.syncFromAppState()
                                                    }

                                                    Text {
                                                        text: "Feed tray"
                                                        color: textDark
                                                        font.pixelSize: 10
                                                        Layout.preferredWidth: lhsLabelWidth
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    MockupSpin {
                                                        id: feedTraySpin
                                                        Layout.preferredWidth: rhsFieldWidth
                                                        Layout.maximumWidth: rhsFieldWidth
                                                        from: 1
                                                        to: root.hasAppState() ? Math.max(1, root.appState.trays || 1) : 32
                                                        value: root.hasAppState() && root.appState.feedTray !== undefined ? root.appState.feedTray : 1
                                                        onValueModified: if (root.hasAppState())
                                                            root.appState.feedTray = value
                                                        Component.onCompleted: root.syncFromAppState()
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: pressureGrid.implicitHeight + 42
                                                radius: 6
                                                color: panelInset
                                                border.color: border

                                                Text {
                                                    x: 12
                                                    y: 8
                                                    text: "Pressure"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: textDark
                                                }

                                                GridLayout {
                                                    id: pressureGrid
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 10
                                                    anchors.topMargin: 32
                                                    columns: 2
                                                    columnSpacing: 8
                                                    rowSpacing: 8

                                                    Text {
                                                        text: "Top pressure  (Pa)"
                                                        color: textDark
                                                        font.pixelSize: 10
                                                        Layout.preferredWidth: lhsLabelWidth
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    MockupField {
                                                        id: topPressureField
                                                        Layout.preferredWidth: rhsFieldWidth
                                                        Layout.maximumWidth: rhsFieldWidth
                                                        validator: DoubleValidator {
                                                            bottom: 0
                                                        }
                                                        onEditingFinished: if (root.hasAppState())
                                                            root.appState.topPressurePa = Number(text)
                                                        Component.onCompleted: root.syncFromAppState()
                                                    }

                                                    Text {
                                                        text: "ΔP / tray  (Pa)"
                                                        color: textDark
                                                        font.pixelSize: 10
                                                        Layout.preferredWidth: lhsLabelWidth
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    MockupField {
                                                        id: dpField
                                                        Layout.preferredWidth: rhsFieldWidth
                                                        Layout.maximumWidth: rhsFieldWidth
                                                        validator: DoubleValidator {
                                                            bottom: 0
                                                        }
                                                        onEditingFinished: if (root.hasAppState())
                                                            root.appState.dpPerTrayPa = Number(text)
                                                        Component.onCompleted: root.syncFromAppState()
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            id: columnGraphicArea
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.alignment: Qt.AlignTop
                                            Layout.minimumWidth: 182

                                            Image {
                                                id: columnSvgImage
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width - 12, 270)
                                                height: Math.min(parent.height - 12, 360)
                                                fillMode: Image.PreserveAspectFit
                                                source: Qt.resolvedUrl("Column.png")
                                                smooth: true
                                                mipmap: true
                                                asynchronous: false
                                                visible: status === Image.Ready
                                            }

                                            // Cond. Duty overlay near condenser icon
                                            Rectangle {
                                                visible: columnSvgImage.visible
                                                x: columnSvgImage.x + columnSvgImage.paintedWidth * 0.42 + 4
                                                y: columnSvgImage.y + columnSvgImage.paintedHeight * 0.08 + 6
                                                width: 72; height: 24
                                                radius: 4
                                                color: "#eef2f8"
                                                border.color: "#9eacbf"
                                                border.width: 1
                                                z: 10
                                                Label {
                                                    anchors.left: parent.left; anchors.leftMargin: 3
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Qc:"
                                                    font.pixelSize: 10
                                                    color: root.mutedText
                                                }
                                                TextInput {
                                                    id: qcOverlay
                                                    anchors.right: parent.right; anchors.rightMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 24
                                                    horizontalAlignment: Text.AlignRight
                                                    font.pixelSize: 10
                                                    color: root.textBlue
                                                    readOnly: root.hasAppState() && root.appState.solving
                                                    selectByMouse: true
                                                    text: root.hasAppState() ? String(root.appState.qcKW) : "-6000"
                                                    validator: DoubleValidator {}
                                                    onEditingFinished: if (root.hasAppState()) { root.appState.qcKW = Number(text); qcField.text = text }
                                                }
                                            }

                                            // Reb. Duty overlay near reboiler icon
                                            Rectangle {
                                                visible: columnSvgImage.visible
                                                x: columnSvgImage.x + columnSvgImage.paintedWidth * 0.48 + 20
                                                y: columnSvgImage.y + columnSvgImage.paintedHeight * 0.68 + 22
                                                width: 72; height: 24
                                                radius: 4
                                                color: "#eef2f8"
                                                border.color: "#9eacbf"
                                                border.width: 1
                                                z: 10
                                                Label {
                                                    anchors.left: parent.left; anchors.leftMargin: 3
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Qr:"
                                                    font.pixelSize: 10
                                                    color: root.mutedText
                                                }
                                                TextInput {
                                                    id: qrOverlay
                                                    anchors.right: parent.right; anchors.rightMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 24
                                                    horizontalAlignment: Text.AlignRight
                                                    font.pixelSize: 10
                                                    color: root.textBlue
                                                    readOnly: root.hasAppState() && root.appState.solving
                                                    selectByMouse: true
                                                    text: root.hasAppState() ? String(root.appState.qrKW) : "6000"
                                                    validator: DoubleValidator {}
                                                    onEditingFinished: if (root.hasAppState()) { root.appState.qrKW = Number(text); qrField.text = text }
                                                }
                                            }

                                            Item {
                                                id: fallbackColumnGraphic
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width - 12, 270)
                                                height: Math.min(parent.height - 12, 360)
                                                visible: columnSvgImage.status !== Image.Ready

                                                Rectangle {
                                                    x: width * 0.42
                                                    y: height * 0.25
                                                    width: width * 0.16
                                                    height: height * 0.48
                                                    radius: width * 0.08
                                                    color: "transparent"
                                                    border.color: root.border
                                                    border.width: 1.5
                                                }

                                                Repeater {
                                                    model: 9
                                                    Rectangle {
                                                        x: fallbackColumnGraphic.width * 0.43
                                                        y: fallbackColumnGraphic.height * (0.30 + index * 0.04)
                                                        width: fallbackColumnGraphic.width * 0.14
                                                        height: 1
                                                        color: root.border
                                                    }
                                                }

                                                Canvas {
                                                    anchors.fill: parent
                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.reset();
                                                        ctx.strokeStyle = root.border;
                                                        ctx.lineWidth = 1.5;

                                                        function line(x1, y1, x2, y2) {
                                                            ctx.beginPath();
                                                            ctx.moveTo(x1, y1);
                                                            ctx.lineTo(x2, y2);
                                                            ctx.stroke();
                                                        }
                                                        function arrow(x1, y1, x2, y2) {
                                                            line(x1, y1, x2, y2);
                                                            const ang = Math.atan2(y2 - y1, x2 - x1);
                                                            const ah = 8;
                                                            ctx.beginPath();
                                                            ctx.moveTo(x2, y2);
                                                            ctx.lineTo(x2 - ah * Math.cos(ang - Math.PI / 6), y2 - ah * Math.sin(ang - Math.PI / 6));
                                                            ctx.moveTo(x2, y2);
                                                            ctx.lineTo(x2 - ah * Math.cos(ang + Math.PI / 6), y2 - ah * Math.sin(ang + Math.PI / 6));
                                                            ctx.stroke();
                                                        }

                                                        const w = width, h = height;
                                                        const cx = w * 0.50;
                                                        const topY = h * 0.30;
                                                        const midY = h * 0.46;
                                                        const lowY = h * 0.66;
                                                        const botY = h * 0.82;
                                                        const colLeft = w * 0.42;
                                                        const colRight = w * 0.58;
                                                        const hxTop = w * 0.78;
                                                        const hyTop = h * 0.18;
                                                        const hxBot = w * 0.60;
                                                        const hyBot = h * 0.74;

                                                        line(cx, topY, cx, hyTop);
                                                        line(cx, hyTop, hxTop, hyTop);
                                                        arrow(colRight, topY, w * 0.90, topY);
                                                        arrow(colLeft, midY, w * 0.18, midY);
                                                        arrow(colRight, lowY, w * 0.68, lowY);
                                                        line(cx, h * 0.73, hxBot, h * 0.73);
                                                        line(hxBot, h * 0.73, hxBot, botY);
                                                        line(hxBot, botY, w * 0.92, botY);
                                                        arrow(hxBot, botY, w * 0.92, botY);
                                                        arrow(hxBot, h * 0.73, hxBot, h * 0.86);

                                                        ctx.beginPath();
                                                        ctx.arc(hxTop, hyTop, 18, 0, Math.PI * 2);
                                                        ctx.stroke();
                                                        line(hxTop - 12, hyTop + 12, hxTop + 12, hyTop - 12);
                                                        arrow(hxTop - 18, hyTop + 24, hxTop + 20, hyTop - 20);

                                                        ctx.beginPath();
                                                        ctx.arc(hxBot, hyBot, 18, 0, Math.PI * 2);
                                                        ctx.stroke();
                                                        line(hxBot - 12, hyBot + 12, hxBot + 12, hyBot - 12);
                                                        arrow(hxBot + 18, hyBot - 24, hxBot - 20, hyBot + 20);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 210
                                Layout.fillHeight: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: panelInset
                                    border.color: border

                                    Text {
                                        x: 18
                                        y: 14
                                        text: "Condenser"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: textDark
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: 18
                                        anchors.topMargin: 34
                                        spacing: 8

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 2
                                            rowSpacing: 8

                                            Text {
                                                text: "Type"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: root.rhsComboLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupCombo {
                                                id: condTypeCombo
                                                Layout.preferredWidth: root.rhsWideComboWidth
                                                Layout.maximumWidth: root.rhsWideComboWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(condSpecCombo)
                                                model: [
                                                    {
                                                        k: "total",
                                                        t: "Total condenser"
                                                    },
                                                    {
                                                        k: "partial",
                                                        t: "Partial condenser"
                                                    }
                                                ]
                                                Component.onCompleted: root.syncFromAppState()
                                                onActivated: if (root.hasAppState())
                                                    root.appState.condenserType = model[index].k
                                            }

                                            Text {
                                                text: "Cond. Spec."
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: root.rhsComboLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupCombo {
                                                id: condSpecCombo
                                                Layout.preferredWidth: root.rhsWideComboWidth
                                                Layout.maximumWidth: root.rhsWideComboWidth
                                                model: [
                                                    {
                                                        k: "none",
                                                        t: "None (remove Cond.)"
                                                    },
                                                    {
                                                        k: "temperature",
                                                        t: "Temperature (Tc)"
                                                    },
                                                    {
                                                        k: "duty",
                                                        t: "Duty (Qc)"
                                                    },
                                                    {
                                                        k: "reflux",
                                                        t: "Reflux ratio (L0/D)"
                                                    }
                                                ]
                                                Component.onCompleted: root.syncFromAppState()
                                                onActivated: if (root.hasAppState())
                                                    root.appState.condenserSpec = model[index].k
                                            }
                                        }

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 6
                                            rowSpacing: 8

                                            Text {
                                                text: "Tops temp.  (K)"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: rhsLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupField {
                                                id: topTsetField
                                                Layout.preferredWidth: root.rhsFieldWidth
                                                Layout.maximumWidth: root.rhsFieldWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(condSpecCombo) && root.isSpec(condSpecCombo, "temperature")
                                                validator: DoubleValidator {
                                                    bottom: 0
                                                }
                                                text: root.hasAppState() ? String(root.appState.topTsetK) : "349.5"
                                                onEditingFinished: if (root.hasAppState())
                                                    root.appState.topTsetK = Number(text)
                                            }

                                            Text {
                                                text: "Reflux Ratio  (—)"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: rhsLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupField {
                                                id: refluxRatioField
                                                Layout.preferredWidth: root.rhsFieldWidth
                                                Layout.maximumWidth: root.rhsFieldWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(condSpecCombo) && root.isSpec(condSpecCombo, "reflux")
                                                validator: DoubleValidator {
                                                    bottom: 0
                                                }
                                                text: root.hasAppState() ? String(root.appState.refluxRatio) : "0.700"
                                                onEditingFinished: if (root.hasAppState())
                                                    root.appState.refluxRatio = Number(text)
                                            }

                                            // qcField kept as invisible for sync compatibility
                                            MockupField {
                                                id: qcField
                                                visible: false
                                                text: root.hasAppState() ? String(root.appState.qcKW) : "-5685.5"
                                                onEditingFinished: if (root.hasAppState()) root.appState.qcKW = Number(text)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: panelInset
                                    border.color: border

                                    Text {
                                        x: 18
                                        y: 14
                                        text: "Reboiler"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: textDark
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: 18
                                        anchors.topMargin: 34
                                        spacing: 8

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 2
                                            rowSpacing: 8

                                            Text {
                                                text: "Type"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: root.rhsComboLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupCombo {
                                                id: rebTypeCombo
                                                Layout.preferredWidth: root.rhsWideComboWidth
                                                Layout.maximumWidth: root.rhsWideComboWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(rebSpecCombo)
                                                model: [
                                                    {
                                                        k: "partial",
                                                        t: "Partial reboiler"
                                                    },
                                                    {
                                                        k: "total",
                                                        t: "Total reboiler"
                                                    }
                                                ]
                                                Component.onCompleted: root.syncFromAppState()
                                                onActivated: if (root.hasAppState())
                                                    root.appState.reboilerType = model[index].k
                                            }

                                            Text {
                                                text: "Reb. Spec."
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: root.rhsComboLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupCombo {
                                                id: rebSpecCombo
                                                Layout.preferredWidth: root.rhsWideComboWidth
                                                Layout.maximumWidth: root.rhsWideComboWidth
                                                model: [
                                                    {
                                                        k: "none",
                                                        t: "None (remove Reb.)"
                                                    },
                                                    {
                                                        k: "duty",
                                                        t: "Duty (Qr)"
                                                    },
                                                    {
                                                        k: "temperature",
                                                        t: "Temperature (Treb)"
                                                    },
                                                    {
                                                        k: "boilup",
                                                        t: "Boilup ratio (Vb/B)"
                                                    }
                                                ]
                                                Component.onCompleted: root.syncFromAppState()
                                                onActivated: if (root.hasAppState())
                                                    root.appState.reboilerSpec = model[index].k
                                            }
                                        }

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 6
                                            rowSpacing: 8

                                            Text {
                                                text: "Bottoms temp.  (K)"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: rhsLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupField {
                                                id: bottomTsetField
                                                Layout.preferredWidth: root.rhsFieldWidth
                                                Layout.maximumWidth: root.rhsFieldWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(rebSpecCombo) && root.isSpec(rebSpecCombo, "temperature")
                                                validator: DoubleValidator {
                                                    bottom: 0
                                                }
                                                text: root.hasAppState() ? String(root.appState.bottomTsetK) : "349.5"
                                                onEditingFinished: if (root.hasAppState())
                                                    root.appState.bottomTsetK = Number(text)
                                            }

                                            Text {
                                                text: "Boilup Ratio  (—)"
                                                color: textDark
                                                font.pixelSize: 10
                                                Layout.preferredWidth: rhsLabelWidth
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            MockupField {
                                                id: boilupRatioField
                                                Layout.preferredWidth: root.rhsFieldWidth
                                                Layout.maximumWidth: root.rhsFieldWidth
                                                enabled: (!root.hasAppState() || !root.appState.solving) && !root.isNoneSpec(rebSpecCombo) && root.isSpec(rebSpecCombo, "boilup")
                                                validator: DoubleValidator {
                                                    bottom: 0
                                                }
                                                text: root.hasAppState() ? String(root.appState.boilupRatio) : "0.900"
                                                onEditingFinished: if (root.hasAppState())
                                                    root.appState.boilupRatio = Number(text)
                                            }

                                            // qrField kept as invisible for sync compatibility
                                            MockupField {
                                                id: qrField
                                                visible: false
                                                text: root.hasAppState() ? String(root.appState.qrKW) : "5685.5"
                                                onEditingFinished: if (root.hasAppState()) root.appState.qrKW = Number(text)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Murphree efficiency ───────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text { text: "η_V:"; font.pixelSize: 10; color: textDark; font.bold: true; Layout.preferredWidth: 28 }
                            ColumnLayout { spacing: 1
                                Text { text: "top"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    text: root.hasAppState() && root.appState.etaVTop !== undefined ? String(root.appState.etaVTop) : "0.75"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaVTop = Number(text); }
                                }
                            }
                            ColumnLayout { spacing: 1
                                Text { text: "mid"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    text: root.hasAppState() && root.appState.etaVMid !== undefined ? String(root.appState.etaVMid) : "0.65"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaVMid = Number(text); }
                                }
                            }
                            ColumnLayout { spacing: 1
                                Text { text: "bot"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    text: root.hasAppState() && root.appState.etaVBot !== undefined ? String(root.appState.etaVBot) : "0.55"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaVBot = Number(text); }
                                }
                            }
                            Item { Layout.preferredWidth: 16 }
                            CheckBox {
                                id: designEtaLCheck
                                implicitHeight: 20
                                checked: root.hasAppState() && root.appState.enableEtaL !== undefined ? root.appState.enableEtaL : false
                                onToggled: { if (root.hasAppState()) root.appState.enableEtaL = checked; }
                            }
                            Text { text: "η_L:"; font.pixelSize: 10; color: textDark; font.bold: true; Layout.preferredWidth: 24; opacity: designEtaLCheck.checked ? 1.0 : 0.35 }
                            ColumnLayout { spacing: 1; opacity: designEtaLCheck.checked ? 1.0 : 0.35
                                Text { text: "top"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    enabled: designEtaLCheck.checked
                                    text: root.hasAppState() && root.appState.etaLTop !== undefined ? String(root.appState.etaLTop) : "0.75"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaLTop = Number(text); }
                                }
                            }
                            ColumnLayout { spacing: 1; opacity: designEtaLCheck.checked ? 1.0 : 0.35
                                Text { text: "mid"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    enabled: designEtaLCheck.checked
                                    text: root.hasAppState() && root.appState.etaLMid !== undefined ? String(root.appState.etaLMid) : "0.65"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaLMid = Number(text); }
                                }
                            }
                            ColumnLayout { spacing: 1; opacity: designEtaLCheck.checked ? 1.0 : 0.35
                                Text { text: "bot"; font.pixelSize: 10; color: textDark }
                                MockupField {
                                    implicitWidth: 72
                                    enabled: designEtaLCheck.checked
                                    text: root.hasAppState() && root.appState.etaLBot !== undefined ? String(root.appState.etaLBot) : "0.55"
                                    validator: DoubleValidator { bottom: 0; top: 1 }
                                    onEditingFinished: { if (root.hasAppState()) root.appState.etaLBot = Number(text); }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                    }
                }


                Rectangle {
                    id: specsDrawsWorkspacePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    visible: root.currentWorksheetTab === "Draws"
                    color: bg
                    border.color: border

                    ListModel {
                        id: specsDrawsRowsModel
                    }

                    function resetSpecsDrawsRows() {
                        specsDrawsRowsModel.clear();
                        specsDrawsRowsModel.append({ name: "Light Naphtha", tray: 30, basis: "% Feed", value: "6.80" });
                        specsDrawsRowsModel.append({ name: "Heavy Naphtha", tray: 27, basis: "% Feed", value: "14.40" });
                        specsDrawsRowsModel.append({ name: "Kerosene", tray: 21, basis: "% Feed", value: "13.30" });
                        specsDrawsRowsModel.append({ name: "LGO", tray: 15, basis: "% Feed", value: "13.05" });
                        specsDrawsRowsModel.append({ name: "HGO", tray: 8, basis: "% Feed", value: "13.05" });
                    }

                    function specsDrawsFeedRateKgph() {
                        if (root.hasAppState() && root.appState.feedStream.flowRateKgph !== undefined)
                            return Number(root.appState.feedStream.flowRateKgph);
                        return 100000;
                    }

                    function specsDrawsTotalPercent() {
                        let total = 0;
                        for (let i = 0; i < specsDrawsRowsModel.count; ++i) {
                            const row = specsDrawsRowsModel.get(i);
                            const v = Number(row.value);
                            if (row.basis === "% Feed" && !isNaN(v))
                                total += v;
                        }
                        return total;
                    }

                    Component.onCompleted: {
                        if (specsDrawsRowsModel.count === 0)
                            resetSpecsDrawsRows();
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: Math.max(width, specsDrawsContent.implicitWidth)
                        contentHeight: specsDrawsContent.implicitHeight

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: specsDrawsContent
                            width: specsDrawsWorkspacePanel.width - 36
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 8
                                color: panelInset
                                border.color: border
                                implicitHeight: drawConfigColumn.implicitHeight + 32

                                ColumnLayout {
                                    id: drawConfigColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: "Draw configuration (product basis)"
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: textDark
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: {
                                                const pct = specsDrawsWorkspacePanel.specsDrawsTotalPercent();
                                                const kgph = pct / 100.0 * specsDrawsWorkspacePanel.specsDrawsFeedRateKgph();
                                                return "Total (% feed specs):  " + pct.toFixed(1) + "%  (" + kgph.toLocaleString(Qt.locale(), 'f', 0) + " kg/h)";
                                            }
                                            font.pixelSize: 10
                                            color: textDark
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Edit Name, Tray (1=bottom, 32=top), and draw rate as % of feed or kg/h. The simulator uses only mid-column draws as side draws; overhead/bottoms are handled by condenser/reboiler."
                                        font.pixelSize: 10
                                        color: textDark
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        color: "transparent"
                                        border.color: border
                                        radius: 8
                                        implicitHeight: drawRowsColumn.implicitHeight + 18

                                        ColumnLayout {
                                            id: drawRowsColumn
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 10
                                            spacing: 8

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 28
                                                color: chrome
                                                border.color: border
                                                radius: 4

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 12

                                                    Text { text: "Name"; color: textDark; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                    Text { text: "Tray"; color: textDark; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.preferredWidth: 66; horizontalAlignment: Text.AlignHCenter }
                                                    Text { text: "Basis"; color: textDark; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.preferredWidth: 86; horizontalAlignment: Text.AlignHCenter }
                                                    Text { text: "Value"; color: textDark; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.preferredWidth: 96; horizontalAlignment: Text.AlignHCenter }
                                                    Item { Layout.preferredWidth: 26 }
                                                }
                                            }

                                            Repeater {
                                                model: specsDrawsRowsModel

                                                delegate: RowLayout {
                                                    required property int index
                                                    required property string name
                                                    required property int tray
                                                    required property string basis
                                                    required property string value

                                                    Layout.fillWidth: true
                                                    spacing: 12

                                                    MockupField {
                                                        Layout.fillWidth: true
                                                        text: name
                                                        onEditingFinished: specsDrawsRowsModel.setProperty(parent.index, "name", text)
                                                    }

                                                    MockupSpin {
                                                        Layout.preferredWidth: 66
                                                        from: 1
                                                        to: root.hasAppState() && root.appState.trays !== undefined ? root.appState.trays : 32
                                                        value: tray
                                                        onValueModified: specsDrawsRowsModel.setProperty(parent.index, "tray", value)
                                                    }

                                                    MockupCombo {
                                                        Layout.preferredWidth: 86
                                                        model: [
                                                            { k: "% Feed", t: "% Feed" },
                                                            { k: "kg/h", t: "kg/h" }
                                                        ]
                                                        currentIndex: basis === "kg/h" ? 1 : 0
                                                        onActivated: specsDrawsRowsModel.setProperty(parent.index, "basis", model[index].k)
                                                    }

                                                    MockupField {
                                                        Layout.preferredWidth: 96
                                                        text: value
                                                        validator: DoubleValidator { bottom: 0 }
                                                        onEditingFinished: specsDrawsRowsModel.setProperty(parent.index, "value", text)
                                                    }

                                                    Button {
                                                        Layout.preferredWidth: 26
                                                        Layout.preferredHeight: 24
                                                        text: "×"
                                                        enabled: specsDrawsRowsModel.count > 1
                                                        onClicked: specsDrawsRowsModel.remove(parent.index)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Button {
                                            text: "+ Add draw"
                                            onClicked: {
                                                specsDrawsRowsModel.append({
                                                    name: "New draw",
                                                    tray: root.hasAppState() && root.appState.feedTray !== undefined ? root.appState.feedTray : 16,
                                                    basis: "% Feed",
                                                    value: "0.00"
                                                });
                                            }
                                        }

                                        Button {
                                            text: "Reset to defaults"
                                            onClicked: specsDrawsWorkspacePanel.resetSpecsDrawsRows()
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "Draws: " + specsDrawsRowsModel.count + " / 30"
                                            font.pixelSize: 10
                                            color: textDark
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: trayProfileWorkspacePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    visible: root.currentWorksheetTab === "Tray Profile"
                    color: bg
                    border.color: border

                    property int modelRevision: 0
                    property var visualRows: []
                    property bool showPressureColumn: false
                    property bool showEnthalpyColumn: false
                    property string rawResultsText: (root.hasAppState() && root.appState.runResults !== undefined && root.appState.runResults !== null)
                                                  ? String(root.appState.runResults) : ""

                    function effectiveTrayModel() {
                        return (root.hasAppState() && root.appState.trayModel) ? root.appState.trayModel : null;
                    }

                    function trayCount() {
                        const m = effectiveTrayModel();
                        if (!m)
                            return 0;
                        if (m.rowCountQml)
                            return m.rowCountQml();
                        if (m.count !== undefined)
                            return m.count;
                        return 0;
                    }

                    function trayAt(i) {
                        const m = effectiveTrayModel();
                        if (!m || !m.get)
                            return null;
                        return m.get(i);
                    }

                    function clamp01(v) {
                        const x = Number(v);
                        if (!isFinite(x))
                            return 0;
                        return Math.max(0, Math.min(1, x));
                    }

                    function numOr(v, fallback) {
                        const x = Number(v);
                        return isFinite(x) ? x : fallback;
                    }

                    function fmtFlow(v) {
                        const x = Number(v);
                        return isFinite(x) ? (x.toLocaleString(Qt.locale(), "f", 3) + " kg/h") : "—";
                    }

                    function fmtTemp(v) {
                        const x = Number(v);
                        return isFinite(x) ? ("T=" + x.toFixed(2) + " K") : "T=—";
                    }

                    function fmtPress(v) {
                        const x = Number(v);
                        if (!isFinite(x))
                            return "P=—";
                        if (Math.abs(x) >= 100000)
                            return "P=" + (x / 1000.0).toFixed(2) + " kPa";
                        return "P=" + x.toFixed(0) + " Pa";
                    }

                    function fmtEnth(v) {
                        const x = Number(v);
                        return isFinite(x) ? ("H=" + x.toFixed(3)) : "H=—";
                    }

                    function splitCsvLine(line) {
                        const out = [];
                        let cur = "";
                        let inQuotes = false;
                        for (let i = 0; i < line.length; ++i) {
                            const ch = line.charAt(i);
                            if (ch === '"') {
                                if (inQuotes && i + 1 < line.length && line.charAt(i + 1) === '"') {
                                    cur += '"';
                                    ++i;
                                } else {
                                    inQuotes = !inQuotes;
                                }
                            } else if (ch === ',' && !inQuotes) {
                                out.push(cur.trim());
                                cur = "";
                            } else {
                                cur += ch;
                            }
                        }
                        out.push(cur.trim());
                        return out;
                    }

                    function parseNumberCell(v) {
                        if (v === undefined || v === null)
                            return NaN;
                        const s = String(v).trim();
                        if (s.length === 0 || s.toLowerCase() === "nan")
                            return NaN;
                        return Number(s);
                    }

                    function findHeaderIndex(headers, names) {
                        for (let i = 0; i < headers.length; ++i) {
                            const h = String(headers[i]).trim().toLowerCase();
                            for (let j = 0; j < names.length; ++j) {
                                if (h === names[j])
                                    return i;
                            }
                        }
                        return -1;
                    }

                    function configuredDrawForTray(trayNo) {
                        let total = 0;
                        let names = [];
                        try {
                            if (typeof specsDrawsRowsModel === "undefined" || !specsDrawsRowsModel)
                                return { rate: 0, name: "" };
                            const feedKgph = (typeof specsDrawsWorkspacePanel !== "undefined" && specsDrawsWorkspacePanel && specsDrawsWorkspacePanel.specsDrawsFeedRateKgph)
                                           ? Number(specsDrawsWorkspacePanel.specsDrawsFeedRateKgph()) : 0;
                            for (let i = 0; i < specsDrawsRowsModel.count; ++i) {
                                const row = specsDrawsRowsModel.get(i);
                                if (!row || Number(row.tray) !== Number(trayNo))
                                    continue;
                                let rate = Number(row.value);
                                if (!isFinite(rate) || rate <= 0)
                                    continue;
                                if (String(row.basis) === "% Feed")
                                    rate = feedKgph * rate / 100.0;
                                if (!isFinite(rate) || rate <= 0)
                                    continue;
                                total += rate;
                                if (row.name)
                                    names.push(String(row.name));
                            }
                        } catch (e) {
                            return { rate: 0, name: "" };
                        }
                        return { rate: total, name: names.join(" + ") };
                    }

                    function buildRowsFromTrayModel() {
                        const out = [];
                        const n = trayCount();
                        for (let i = 0; i < n; ++i) {
                            const row = trayAt(i);
                            if (!row)
                                continue;

                            const trayNo = numOr(row.tray, i + 1);
                            const vaporFrac = clamp01(row.vfrac !== undefined ? row.vfrac : row.vaporFrac);
                            const vaporRate = numOr(row.V_kgph !== undefined ? row.V_kgph
                                                     : (row.vaporRate !== undefined ? row.vaporRate
                                                     : (row.vapor_kgph !== undefined ? row.vapor_kgph : row.vaporKgph)), 0);
                            const liquidRate = numOr(row.L_kgph !== undefined ? row.L_kgph
                                                      : (row.liquidRate !== undefined ? row.liquidRate
                                                      : (row.liquid_kgph !== undefined ? row.liquid_kgph : row.liquidKgph)), 0);
                            const configuredDraw = configuredDrawForTray(trayNo);
                            const drawRate = Math.max(0, numOr(
                                                        row.DrawActual_kgph !== undefined ? row.DrawActual_kgph
                                                      : (row.drawActualKgph !== undefined ? row.drawActualKgph
                                                      : (row.Draw_kgph !== undefined ? row.Draw_kgph
                                                      : (row.draw_rate_kgph !== undefined ? row.draw_rate_kgph
                                                      : (row.drawRate !== undefined ? row.drawRate
                                                      : (row.drawKgph !== undefined ? row.drawKgph
                                                      : (row.liquidDrawKgph !== undefined ? row.liquidDrawKgph
                                                      : (row.sideDrawKgph !== undefined ? row.sideDrawKgph
                                                      : configuredDraw.rate))))))), 0));
                            const pressurePa = numOr(row.PressurePa !== undefined ? row.PressurePa
                                                   : (row.pressurePa !== undefined ? row.pressurePa
                                                   : (row.pressure !== undefined ? row.pressure : row.P)), NaN);
                            const enthalpy = (row.Hcalc !== undefined) ? numOr(row.Hcalc, NaN)
                                              : ((row.enthalpy !== undefined) ? numOr(row.enthalpy, NaN)
                                              : ((row.H !== undefined) ? numOr(row.H, NaN)
                                              : ((row.Htarget !== undefined) ? numOr(row.Htarget, NaN) : NaN)));

                            out.push({
                                trayNumber: trayNo,
                                vaporFrac: vaporFrac,
                                vaporRate: vaporRate,
                                liquidRate: liquidRate,
                                temperatureK: numOr(row.tempK !== undefined ? row.tempK
                                                      : (row.temperatureK !== undefined ? row.temperatureK
                                                      : (row.TempK !== undefined ? row.TempK : row.temperature)), NaN),
                                pressurePa: pressurePa,
                                enthalpy: enthalpy,
                                drawRate: drawRate,
                                drawType: "liquid",
                                drawName: configuredDraw.name,
                                isFeedTray: root.hasAppState() && root.appState.feedTray !== undefined
                                           ? (trayNo === Number(root.appState.feedTray)) : false,
                                isCondenser: (i === n - 1),
                                isReboiler: (i === 0),
                                trayLabel: ""
                            });
                        }
                        return out;
                    }

                    function buildRowsFromRunResults() {
                        const text = rawResultsText || "";
                        const lines = text.split(/\r?\n/);

                        let headers = [];
                        let rows = [];
                        for (let i = 0; i < lines.length; ++i) {
                            const headerLine = lines[i].trim();
                            if (headerLine.length === 0 || headerLine.indexOf(",") < 0)
                                continue;
                            const candidateHeaders = splitCsvLine(headerLine);
                            const joined = candidateHeaders.join(" ").toLowerCase();
                            if (joined.indexOf("tray") >= 0 && (joined.indexOf("temp") >= 0 || joined.indexOf("vfrac") >= 0 || joined.indexOf("pressure") >= 0)) {
                                headers = candidateHeaders;
                                let j = i + 1;
                                while (j < lines.length) {
                                    const rowLine = lines[j].trim();
                                    if (rowLine.length === 0 || rowLine.indexOf(",") < 0)
                                        break;
                                    rows.push(splitCsvLine(rowLine));
                                    ++j;
                                }
                                break;
                            }
                        }

                        if (headers.length === 0 || rows.length === 0)
                            return [];

                        const idxTray = findHeaderIndex(headers, ["tray"]);
                        const idxTemp = findHeaderIndex(headers, ["tempk", "temperaturek", "temperature"]);
                        const idxPressure = findHeaderIndex(headers, ["pressurepa", "pressure", "p"]);
                        const idxVfrac = findHeaderIndex(headers, ["vfrac", "vaporfraction"]);
                        const idxL = findHeaderIndex(headers, ["l_kgph", "lkgph", "liquidrate", "liquid_kgph", "liquidkgph"]);
                        const idxV = findHeaderIndex(headers, ["v_kgph", "vkgph", "vaporrate", "vapor_kgph", "vaporkgph"]);
                        const idxDraw = findHeaderIndex(headers, ["drawactual_kgph", "drawactualkgph", "draw_kgph", "drawkgph", "drawrate", "draw_rate_kgph", "liquiddrawkgph", "sidedrawkgph"]);
                        const idxH = findHeaderIndex(headers, ["hcalc", "enthalpy", "h", "htarget"]);

                        const out = [];
                        for (let r = 0; r < rows.length; ++r) {
                            const cols = rows[r];
                            const trayNo = idxTray >= 0 ? numOr(parseNumberCell(cols[idxTray]), r + 1) : (r + 1);
                            const configuredDraw = configuredDrawForTray(trayNo);
                            out.push({
                                trayNumber: trayNo,
                                vaporFrac: idxVfrac >= 0 ? clamp01(parseNumberCell(cols[idxVfrac])) : 0,
                                vaporRate: idxV >= 0 ? numOr(parseNumberCell(cols[idxV]), 0) : 0,
                                liquidRate: idxL >= 0 ? numOr(parseNumberCell(cols[idxL]), 0) : 0,
                                temperatureK: idxTemp >= 0 ? numOr(parseNumberCell(cols[idxTemp]), NaN) : NaN,
                                pressurePa: idxPressure >= 0 ? numOr(parseNumberCell(cols[idxPressure]), NaN) : NaN,
                                enthalpy: idxH >= 0 ? numOr(parseNumberCell(cols[idxH]), NaN) : NaN,
                                drawRate: idxDraw >= 0 ? Math.max(0, numOr(parseNumberCell(cols[idxDraw]), configuredDraw.rate)) : configuredDraw.rate,
                                drawType: "liquid",
                                drawName: configuredDraw.name,
                                isFeedTray: root.hasAppState() && root.appState.feedTray !== undefined
                                           ? (trayNo === Number(root.appState.feedTray)) : false,
                                isCondenser: false,
                                isReboiler: false,
                                trayLabel: ""
                            });
                        }

                        for (let k = 0; k < out.length; ++k) {
                            out[k].isReboiler = (k === 0);
                            out[k].isCondenser = (k === out.length - 1);
                        }
                        return out;
                    }

                    function rebuildVisualRows() {
                        let rows = buildRowsFromTrayModel();
                        if (!rows || rows.length === 0)
                            rows = buildRowsFromRunResults();

                        rows.sort(function(a, b) { return Number(b.trayNumber) - Number(a.trayNumber); });

                        let anyPressure = false;
                        let anyEnthalpy = false;

                        for (let i = 0; i < rows.length; ++i) {
                            const row = rows[i];
                            if (row.isFeedTray && (!row.trayLabel || row.trayLabel.length === 0))
                                row.trayLabel = "Flash zone / feed";
                            else if (row.isCondenser)
                                row.trayLabel = "Condenser";
                            else if (row.isReboiler)
                                row.trayLabel = "Reboiler";

                            if (!isNaN(Number(row.pressurePa)))
                                anyPressure = true;
                            if (!isNaN(Number(row.enthalpy)))
                                anyEnthalpy = true;
                        }

                        showPressureColumn = anyPressure;
                        showEnthalpyColumn = anyEnthalpy;
                        visualRows = rows;
                    }

                    onRawResultsTextChanged: rebuildVisualRows()
                    Component.onCompleted: rebuildVisualRows()

                    Connections {
                        target: trayProfileWorkspacePanel.effectiveTrayModel()
                        ignoreUnknownSignals: true
                        function onModelReset()    { trayProfileWorkspacePanel.modelRevision++; trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onLayoutChanged() { trayProfileWorkspacePanel.modelRevision++; trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onDataChanged()   { trayProfileWorkspacePanel.modelRevision++; trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onRowsInserted()  { trayProfileWorkspacePanel.modelRevision++; trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onRowsRemoved()   { trayProfileWorkspacePanel.modelRevision++; trayProfileWorkspacePanel.rebuildVisualRows(); }
                    }

                    Connections {
                        target: root.hasAppState() ? root.appState : null
                        ignoreUnknownSignals: true
                        function onRunResultsChanged() { trayProfileWorkspacePanel.rawResultsText = (root.appState.runResults !== undefined && root.appState.runResults !== null) ? String(root.appState.runResults) : ""; trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onFeedTrayChanged() { trayProfileWorkspacePanel.rebuildVisualRows(); }
                        function onTraysChanged() { trayProfileWorkspacePanel.rebuildVisualRows(); }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: "#0b1220"
                            border.color: "#22304a"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16

                                    Text {
                                        text: "Tray Profile"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#d9e7ff"
                                    }

                                    Text {
                                        text: trayProfileWorkspacePanel.visualRows.length > 0
                                              ? (trayProfileWorkspacePanel.visualRows.length + " trays")
                                              : "No tray data"
                                        font.pixelSize: 11
                                        color: "#91a9cf"
                                    }

                                    Item { Layout.fillWidth: true }

                                    Row {
                                        spacing: 10

                                        Rectangle {
                                            width: 18
                                            height: 10
                                            radius: 3
                                            color: "#67b0ff"
                                        }

                                        Text {
                                            text: "Vapor bar (V*)"
                                            font.pixelSize: 10
                                            color: "#91a9cf"
                                        }

                                        Rectangle {
                                            width: 18
                                            height: 10
                                            radius: 3
                                            color: "#294f8f"
                                        }

                                        Text {
                                            text: "Liquid bar (1 − V*)"
                                            font.pixelSize: 10
                                            color: "#91a9cf"
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: "#1c2a45"
                                }

                                ListView {
                                    id: trayProfileListView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 4
                                    model: trayProfileWorkspacePanel.visualRows

                                    delegate: Rectangle {
                                        width: trayProfileListView.width - 2
                                        height: 46
                                        radius: 8
                                        color: modelData.isFeedTray ? "#10253f"
                                              : ((index % 2) === 0 ? "#0f182b" : "#0d1525")
                                        border.color: modelData.isFeedTray ? "#2f7dd1" : "#182844"
                                        border.width: modelData.isFeedTray ? 1 : 0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 10

                                            Item {
                                                Layout.preferredWidth: 86
                                                Layout.fillHeight: true

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2

                                                    Text {
                                                        text: "Tray " + modelData.trayNumber
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: "#d9e7ff"
                                                    }

                                                    Text {
                                                        visible: !!modelData.trayLabel
                                                        text: modelData.trayLabel
                                                        font.pixelSize: 10
                                                        color: modelData.isFeedTray ? "#7fc2ff" : "#91a9cf"
                                                    }
                                                }
                                            }

                                            Item {
                                                Layout.preferredWidth: 112
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width
                                                    height: 12
                                                    radius: 6
                                                    color: "#16233b"
                                                    border.color: "#2a3d60"
                                                    border.width: 1

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        width: parent.width * trayProfileWorkspacePanel.clamp01(modelData.vaporFrac)
                                                        radius: 6
                                                        color: "#67b0ff"
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.preferredWidth: 52
                                                text: "V*=" + trayProfileWorkspacePanel.clamp01(modelData.vaporFrac).toFixed(3)
                                                font.pixelSize: 11
                                                color: "#d9e7ff"
                                            }

                                            Text {
                                                Layout.preferredWidth: 98
                                                text: "V=" + trayProfileWorkspacePanel.fmtFlow(modelData.vaporRate)
                                                font.pixelSize: 11
                                                color: "#d9e7ff"
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.preferredWidth: 98
                                                text: "L=" + trayProfileWorkspacePanel.fmtFlow(modelData.liquidRate)
                                                font.pixelSize: 11
                                                color: "#d9e7ff"
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.preferredWidth: 86
                                                text: trayProfileWorkspacePanel.fmtTemp(modelData.temperatureK)
                                                font.pixelSize: 11
                                                color: "#d9e7ff"
                                            }

                                            Text {
                                                visible: trayProfileWorkspacePanel.showPressureColumn
                                                Layout.preferredWidth: trayProfileWorkspacePanel.showPressureColumn ? 82 : 0
                                                text: trayProfileWorkspacePanel.fmtPress(modelData.pressurePa)
                                                font.pixelSize: 10
                                                color: "#d9e7ff"
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: trayProfileWorkspacePanel.showEnthalpyColumn
                                                Layout.preferredWidth: trayProfileWorkspacePanel.showEnthalpyColumn ? 78 : 0
                                                text: trayProfileWorkspacePanel.fmtEnth(modelData.enthalpy)
                                                font.pixelSize: 10
                                                color: "#d9e7ff"
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: Number(modelData.drawRate) > 0
                                                Layout.preferredWidth: visible ? 180 : 0
                                                text: (modelData.drawName && String(modelData.drawName).length > 0 ? String(modelData.drawName) + " " : "")
                                                      + (modelData.drawType === "vapor" ? "VDraw=" : "LDraw=")
                                                      + trayProfileWorkspacePanel.fmtFlow(modelData.drawRate)
                                                font.pixelSize: 10
                                                color: "#7fc2ff"
                                                elide: Text.ElideRight
                                            }

                                            Item { Layout.fillWidth: true }

                                            Rectangle {
                                                visible: false
                                                radius: 10
                                                color: "#14314a"
                                                border.color: "#4ca3ff"
                                                border.width: 1
                                                height: 24
                                                width: drawBadgeText.implicitWidth + 18

                                                Text {
                                                    id: drawBadgeText
                                                    anchors.centerIn: parent
                                                    text: (modelData.drawType === "vapor" ? "VDraw " : "LDraw ") + trayProfileWorkspacePanel.fmtFlow(modelData.drawRate)
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    color: "#dcecff"
                                                }
                                            }
                                        }
                                    }

                                    footer: Rectangle {
                                        visible: trayProfileWorkspacePanel.visualRows.length === 0
                                        width: trayProfileListView.width - 2
                                        height: 80
                                        radius: 8
                                        color: "#0f182b"
                                        border.color: "#22304a"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "No tray profile data detected yet. Solve the column to populate this panel."
                                            font.pixelSize: 11
                                            color: "#91a9cf"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: runResultsWorkspacePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    visible: root.currentWorksheetTab === "Run Results"
                    color: bg
                    border.color: border

                    property int modelRevision: 0
                    property string rawResultsText: (root.hasAppState() && root.appState.runResults !== undefined && root.appState.runResults !== null)
                                                  ? String(root.appState.runResults) : ""
                    property bool showRawText: false
                    property string currentResultsTable: "Tray Profile"
                    readonly property int maxTableColumns: 20

                    property var trayHeaders: []
                    property var trayRows: []
                    property var trayTableModelRows: []
                    property var trayColumnWidths: []

                    property var streamHeaders: []
                    property var streamRows: []
                    property var streamTableModelRows: []
                    property var streamColumnWidths: []

                    function effectiveTrayModel() {
                        return (root.hasAppState() && root.appState.trayModel) ? root.appState.trayModel : null;
                    }

                    function trayCount() {
                        const m = effectiveTrayModel();
                        if (!m)
                            return 0;
                        if (m.rowCountQml)
                            return m.rowCountQml();
                        if (m.count !== undefined)
                            return m.count;
                        return 0;
                    }

                    function trayAt(i) {
                        const m = effectiveTrayModel();
                        if (!m || !m.get)
                            return null;
                        return m.get(i);
                    }

                    function topTrayTempK() {
                        const _rev = modelRevision;
                        const n = trayCount();
                        if (n <= 0)
                            return 0;
                        const row = trayAt(n - 1);
                        return (row && row.tempK !== undefined) ? Number(row.tempK) : 0;
                    }

                    function bottomTrayTempK() {
                        const _rev = modelRevision;
                        const n = trayCount();
                        if (n <= 0)
                            return 0;
                        const row = trayAt(0);
                        return (row && row.tempK !== undefined) ? Number(row.tempK) : 0;
                    }

                    function fmt1(v) { return Number(v || 0).toFixed(1); }
                    function fmt0(v) { return Number(v || 0).toFixed(0); }
                    function fmtBarFromPa(pa) { return (Number(pa || 0) / 100000.0).toFixed(3) + " bar"; }

                    function ratioToPctText(v) {
                        const x = Number(v);
                        if (!isFinite(x) || x < 0)
                            return "—";
                        return (100.0 * x / (1.0 + x)).toFixed(3) + " %";
                    }

                    function splitCsvLine(line) {
                        const out = [];
                        let cur = "";
                        let inQuotes = false;
                        for (let i = 0; i < line.length; ++i) {
                            const ch = line.charAt(i);
                            if (ch === '"') {
                                if (inQuotes && i + 1 < line.length && line.charAt(i + 1) === '"') {
                                    cur += '"';
                                    ++i;
                                } else {
                                    inQuotes = !inQuotes;
                                }
                            } else if (ch === ',' && !inQuotes) {
                                out.push(cur.trim());
                                cur = "";
                            } else {
                                cur += ch;
                            }
                        }
                        out.push(cur.trim());
                        return out;
                    }

                    function classifyBlock(headers) {
                        let joined = "";
                        for (let i = 0; i < headers.length; ++i)
                            joined += " " + String(headers[i]).toLowerCase();
                        if (joined.indexOf("tray") >= 0 && (joined.indexOf("temp") >= 0 || joined.indexOf("pressure") >= 0 || joined.indexOf("vfrac") >= 0))
                            return "tray";
                        if (joined.indexOf("stream") >= 0 || joined.indexOf("flow") >= 0 || joined.indexOf("kgph") >= 0 || joined.indexOf("draw") >= 0)
                            return "stream";
                        return "other";
                    }

                    function buildWidths(headers, rows) {
                        const widths = [];
                        for (let c = 0; c < headers.length; ++c) {
                            let longest = headers[c] ? String(headers[c]).length : 0;
                            for (let r = 0; r < rows.length; ++r) {
                                const cell = (rows[r][c] !== undefined && rows[r][c] !== null) ? String(rows[r][c]) : "";
                                if (cell.length > longest)
                                    longest = cell.length;
                            }
                            widths.push(Math.max(78, Math.min(280, longest * 8 + 24)));
                        }
                        return widths;
                    }

                    function buildTableRows(headers, rows) {
                        const out = [];
                        for (let r = 0; r < rows.length; ++r) {
                            const obj = {};
                            for (let c = 0; c < maxTableColumns; ++c)
                                obj["c" + c] = (c < headers.length && rows[r][c] !== undefined) ? rows[r][c] : "";
                            out.push(obj);
                        }
                        return out;
                    }

                    function assignBlock(kind, headers, rows) {
                        const widths = buildWidths(headers, rows);
                        const modelRows = buildTableRows(headers, rows);
                        if (kind === "tray") {
                            trayHeaders = headers;
                            trayRows = rows;
                            trayTableModelRows = modelRows;
                            trayColumnWidths = widths;
                        } else {
                            streamHeaders = headers;
                            streamRows = rows;
                            streamTableModelRows = modelRows;
                            streamColumnWidths = widths;
                        }
                    }

                    function parseRunResultsText() {
                        const text = rawResultsText || "";
                        const lines = text.split(/\r?\n/);
                        trayHeaders = [];
                        trayRows = [];
                        trayTableModelRows = [];
                        trayColumnWidths = [];
                        streamHeaders = [];
                        streamRows = [];
                        streamTableModelRows = [];
                        streamColumnWidths = [];

                        const blocks = [];
                        let i = 0;
                        while (i < lines.length) {
                            const headerLine = lines[i].trim();
                            if (headerLine.length === 0 || headerLine.indexOf(",") < 0) {
                                ++i;
                                continue;
                            }

                            const headers = splitCsvLine(headerLine);
                            if (headers.length < 2) {
                                ++i;
                                continue;
                            }

                            const rows = [];
                            let j = i + 1;
                            while (j < lines.length) {
                                const rowLine = lines[j].trim();
                                if (rowLine.length === 0 || rowLine.indexOf(",") < 0)
                                    break;
                                rows.push(splitCsvLine(rowLine));
                                ++j;
                            }

                            if (rows.length > 0)
                                blocks.push({ headers: headers, rows: rows, kind: classifyBlock(headers) });

                            i = Math.max(j, i + 1);
                        }

                        if (blocks.length === 0)
                            return;

                        let trayBlock = null;
                        let streamBlock = null;
                        for (let b = 0; b < blocks.length; ++b) {
                            if (!trayBlock && blocks[b].kind === "tray")
                                trayBlock = blocks[b];
                            else if (!streamBlock && blocks[b].kind === "stream")
                                streamBlock = blocks[b];
                        }

                        if (!trayBlock)
                            trayBlock = blocks[0];
                        if (!streamBlock) {
                            for (let b = 0; b < blocks.length; ++b) {
                                if (blocks[b] !== trayBlock) {
                                    streamBlock = blocks[b];
                                    break;
                                }
                            }
                        }

                        if (trayBlock)
                            assignBlock("tray", trayBlock.headers, trayBlock.rows);
                        if (streamBlock)
                            assignBlock("stream", streamBlock.headers, streamBlock.rows);
                    }

                    function trayColumnWidth(col) {
                        if (trayColumnWidths && col >= 0 && col < trayColumnWidths.length)
                            return trayColumnWidths[col];
                        return 120;
                    }

                    function streamColumnWidth(col) {
                        if (streamColumnWidths && col >= 0 && col < streamColumnWidths.length)
                            return streamColumnWidths[col];
                        return 120;
                    }

                    onRawResultsTextChanged: parseRunResultsText()
                    Component.onCompleted: parseRunResultsText()

                    Connections {
                        target: runResultsWorkspacePanel.effectiveTrayModel()
                        ignoreUnknownSignals: true
                        function onModelReset()    { runResultsWorkspacePanel.modelRevision++ }
                        function onLayoutChanged() { runResultsWorkspacePanel.modelRevision++ }
                        function onDataChanged()   { runResultsWorkspacePanel.modelRevision++ }
                        function onRowsInserted()  { runResultsWorkspacePanel.modelRevision++ }
                        function onRowsRemoved()   { runResultsWorkspacePanel.modelRevision++ }
                    }

                    TableModel {
                        id: trayResultsTableModel
                        TableModelColumn { display: "c0" }
                        TableModelColumn { display: "c1" }
                        TableModelColumn { display: "c2" }
                        TableModelColumn { display: "c3" }
                        TableModelColumn { display: "c4" }
                        TableModelColumn { display: "c5" }
                        TableModelColumn { display: "c6" }
                        TableModelColumn { display: "c7" }
                        TableModelColumn { display: "c8" }
                        TableModelColumn { display: "c9" }
                        TableModelColumn { display: "c10" }
                        TableModelColumn { display: "c11" }
                        TableModelColumn { display: "c12" }
                        TableModelColumn { display: "c13" }
                        TableModelColumn { display: "c14" }
                        TableModelColumn { display: "c15" }
                        TableModelColumn { display: "c16" }
                        TableModelColumn { display: "c17" }
                        TableModelColumn { display: "c18" }
                        TableModelColumn { display: "c19" }
                        rows: runResultsWorkspacePanel.trayTableModelRows
                    }

                    TableModel {
                        id: streamResultsTableModel
                        TableModelColumn { display: "c0" }
                        TableModelColumn { display: "c1" }
                        TableModelColumn { display: "c2" }
                        TableModelColumn { display: "c3" }
                        TableModelColumn { display: "c4" }
                        TableModelColumn { display: "c5" }
                        TableModelColumn { display: "c6" }
                        TableModelColumn { display: "c7" }
                        TableModelColumn { display: "c8" }
                        TableModelColumn { display: "c9" }
                        TableModelColumn { display: "c10" }
                        TableModelColumn { display: "c11" }
                        TableModelColumn { display: "c12" }
                        TableModelColumn { display: "c13" }
                        TableModelColumn { display: "c14" }
                        TableModelColumn { display: "c15" }
                        TableModelColumn { display: "c16" }
                        TableModelColumn { display: "c17" }
                        TableModelColumn { display: "c18" }
                        TableModelColumn { display: "c19" }
                        rows: runResultsWorkspacePanel.streamTableModelRows
                    }

                    Component {
                        id: runSummaryRow
                        Item {
                            id: summaryRowRoot
                            property string label: ""
                            property string value: ""
                            property bool pill: false
                            implicitHeight: 28

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Label {
                                    text: summaryRowRoot.label
                                    color: "#315fb8"
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 110
                                    Layout.maximumWidth: 110
                                    elide: Text.ElideRight
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    visible: summaryRowRoot.pill
                                    radius: 6
                                    border.color: "#d4a29b"
                                    border.width: 1
                                    color: "#ecd8d3"
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    Layout.preferredWidth: Math.max(72, pillText.implicitWidth + 18)
                                    Layout.preferredHeight: 24

                                    Text {
                                        id: pillText
                                        anchors.centerIn: parent
                                        text: summaryRowRoot.value
                                        color: "#182030"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Label {
                                    visible: !summaryRowRoot.pill
                                    text: summaryRowRoot.value
                                    color: textDark
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    elide: Text.ElideLeft
                                }
                            }
                        }
                    }

                    Component {
                        id: sectionHeaderDelegate
                        Rectangle {
                            property var headersModel: []
                            property var widthsModel: []
                            height: 30
                            color: "transparent"
                            clip: true

                            Flickable {
                                id: hdrFlick
                                anchors.fill: parent
                                contentWidth: hdrRow.width
                                contentHeight: parent.height
                                interactive: false
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Row {
                                    id: hdrRow
                                    spacing: 0

                                    Repeater {
                                        model: parent.parent.parent.headersModel.length
                                        delegate: Rectangle {
                                            width: (parent.parent.parent.widthsModel && index < parent.parent.parent.widthsModel.length)
                                                   ? parent.parent.parent.widthsModel[index] : 120
                                            height: 30
                                            color: "#d8dde7"
                                            border.color: border

                                            Text {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                text: parent.parent.parent.headersModel[index]
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                color: textDark
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: cellDelegate
                        Rectangle {
                            implicitWidth: 120
                            implicitHeight: 28
                            border.color: border
                            color: (row % 2 === 0) ? "#f4f5f8" : "#eceef3"

                            TextEdit {
                                anchors.fill: parent
                                anchors.margins: 6
                                readOnly: true
                                selectByMouse: true
                                persistentSelection: true
                                text: (display !== undefined && display !== null) ? String(display) : ""
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.NoWrap
                                color: textDark
                                font.pixelSize: 11
                                verticalAlignment: TextEdit.AlignVCenter
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 380
                            Layout.fillHeight: true
                            radius: 8
                            color: panelInset
                            border.color: border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                Text {
                                    text: "Run Summary"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: textDark
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: border }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Top Tray T";
                                        item.pill = true;
                                        item.value = Qt.binding(function() {
                                            return runResultsWorkspacePanel.fmt1(runResultsWorkspacePanel.topTrayTempK()) + " K";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Bottom Tray T";
                                        item.pill = true;
                                        item.value = Qt.binding(function() {
                                            return runResultsWorkspacePanel.fmt1(runResultsWorkspacePanel.bottomTrayTempK()) + " K";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Top P";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? runResultsWorkspacePanel.fmtBarFromPa(root.appState.topPressurePa) : "—";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Feed tray";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? String(root.appState.feedTray) : "—";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Status";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? (root.appState.solved ? "Solved" : "Not solved") : "—";
                                        });
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: border }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Qc";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? runResultsWorkspacePanel.fmt0(root.appState.qcCalcKW) + " kW" : "—";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Qr";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? runResultsWorkspacePanel.fmt0(root.appState.qrCalcKW) + " kW" : "—";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Reflux frac";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? runResultsWorkspacePanel.ratioToPctText(root.appState.refluxRatio) : "—";
                                        });
                                    }
                                }

                                Loader {
                                    Layout.fillWidth: true
                                    sourceComponent: runSummaryRow
                                    onLoaded: {
                                        item.label = "Boil-up frac";
                                        item.value = Qt.binding(function() {
                                            return root.hasAppState() ? runResultsWorkspacePanel.ratioToPctText(root.appState.boilupRatio) : "—";
                                        });
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: panelInset
                            border.color: border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: "Run Results"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: textDark
                                    }

                                    Item { Layout.fillWidth: true }

                                    Button {
                                        text: runResultsWorkspacePanel.showRawText ? "Hide copyable text" : "Show copyable text"
                                        onClicked: runResultsWorkspacePanel.showRawText = !runResultsWorkspacePanel.showRawText
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: border }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "Results Table"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: textDark
                                    }

                                    ComboBox {
                                        id: resultsTableSelector
                                        Layout.preferredWidth: 170
                                        model: ["Tray Profile", "Stream Summary"]
                                        currentIndex: runResultsWorkspacePanel.currentResultsTable === "Stream Summary" ? 1 : 0
                                        onActivated: function(index) {
                                            runResultsWorkspacePanel.currentResultsTable = (index === 1) ? "Stream Summary" : "Tray Profile";
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: runResultsWorkspacePanel.showRawText ? 0 : 30
                                    visible: !runResultsWorkspacePanel.showRawText
                                    color: "transparent"
                                    clip: true

                                    Flickable {
                                        id: unifiedHeaderFlick
                                        anchors.fill: parent
                                        contentWidth: unifiedHeaderRow.width
                                        contentHeight: parent.height
                                        interactive: false
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        contentX: unifiedResultsTable.contentX

                                        Row {
                                            id: unifiedHeaderRow
                                            spacing: 0

                                            Repeater {
                                                model: runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                                       ? runResultsWorkspacePanel.streamHeaders.length
                                                       : runResultsWorkspacePanel.trayHeaders.length
                                                delegate: Rectangle {
                                                    width: runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                                           ? runResultsWorkspacePanel.streamColumnWidth(index)
                                                           : runResultsWorkspacePanel.trayColumnWidth(index)
                                                    height: 30
                                                    color: "#d8dde7"
                                                    border.color: border

                                                    Text {
                                                        anchors.fill: parent
                                                        anchors.margins: 6
                                                        text: runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                                              ? runResultsWorkspacePanel.streamHeaders[index]
                                                              : runResultsWorkspacePanel.trayHeaders[index]
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: textDark
                                                        elide: Text.ElideRight
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                TableView {
                                    id: unifiedResultsTable
                                    Layout.fillWidth: true
                                    Layout.fillHeight: !runResultsWorkspacePanel.showRawText
                                    Layout.preferredHeight: runResultsWorkspacePanel.showRawText ? 0 : 350
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                           ? streamResultsTableModel
                                           : trayResultsTableModel
                                    columnSpacing: 0
                                    rowSpacing: 0
                                    visible: !runResultsWorkspacePanel.showRawText && (runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                             ? runResultsWorkspacePanel.streamHeaders.length > 0
                                             : runResultsWorkspacePanel.trayHeaders.length > 0)

                                    columnWidthProvider: function(column) {
                                        return runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                               ? runResultsWorkspacePanel.streamColumnWidth(column)
                                               : runResultsWorkspacePanel.trayColumnWidth(column);
                                    }
                                    rowHeightProvider: function(row) { return 28; }

                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                                    delegate: cellDelegate
                                }

                                Text {
                                    visible: !runResultsWorkspacePanel.showRawText && (runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                             ? runResultsWorkspacePanel.streamHeaders.length === 0
                                             : runResultsWorkspacePanel.trayHeaders.length === 0)
                                    text: runResultsWorkspacePanel.currentResultsTable === "Stream Summary"
                                          ? "No Stream Summary table detected yet."
                                          : "No Tray Profile table detected yet."
                                    color: textDark
                                    font.pixelSize: 11
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: runResultsWorkspacePanel.showRawText
                                    Layout.preferredHeight: runResultsWorkspacePanel.showRawText ? 350 : 0
                                    visible: runResultsWorkspacePanel.showRawText
                                    color: "#ffffff"
                                    border.color: border
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Button {
                                                text: "Select All"
                                                onClicked: {
                                                    rawResultsEdit.forceActiveFocus()
                                                    rawResultsEdit.selectAll()
                                                }
                                            }

                                            Button {
                                                text: "Copy All"
                                                onClicked: {
                                                    rawResultsEdit.forceActiveFocus()
                                                    rawResultsEdit.selectAll()
                                                    rawResultsEdit.copy()
                                                }
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: "Use Ctrl+C after selecting, or Copy All."
                                                color: textDark
                                                elide: Label.ElideRight
                                            }
                                        }

                                        ScrollView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true

                                            TextArea {
                                                id: rawResultsEdit
                                                text: runResultsWorkspacePanel.rawResultsText
                                                readOnly: true
                                                selectByMouse: true
                                                persistentSelection: true
                                                wrapMode: TextArea.NoWrap
                                                color: textDark
                                                font.family: "Courier New"
                                                font.pixelSize: 11
                                                leftPadding: 8
                                                rightPadding: 8
                                                topPadding: 8
                                                bottomPadding: 8
                                                background: Rectangle {
                                                    color: "#ffffff"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                Rectangle {
                    id: runLogWorkspacePanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    visible: root.currentWorksheetTab === "Run Log"
                    color: bg
                    border.color: border

                    property var runLogModel: (root.hasAppState() && root.appState && root.appState.runLogModel !== undefined)
                                              ? root.appState.runLogModel : null
                    property int currentRow: -1
                    property var _matches: []
                    property int _matchPos: -1
                    property bool _matchesDirty: true

                    function _norm(s) {
                        const ss = (s === undefined || s === null) ? "" : String(s);
                        return runLogCaseBox.checked ? ss : ss.toLowerCase();
                    }

                    function rebuildMatchesIfNeeded() {
                        if (!runLogWorkspacePanel._matchesDirty)
                            return;

                        runLogWorkspacePanel._matchesDirty = false;
                        runLogWorkspacePanel._matches = [];
                        runLogWorkspacePanel._matchPos = -1;

                        const needleRaw = runLogSearchField.text;
                        if (!needleRaw || needleRaw.length === 0)
                            return;

                        const hay = runLogWorkspacePanel._norm(runLogText.text);
                        const needle = runLogWorkspacePanel._norm(needleRaw);

                        let i = 0;
                        while (true) {
                            const p = hay.indexOf(needle, i);
                            if (p < 0)
                                break;
                            runLogWorkspacePanel._matches.push(p);
                            i = p + Math.max(1, needle.length);
                        }
                    }

                    function clearSelection() {
                        try {
                            runLogText.deselect();
                        } catch (e) {
                            runLogText.select(0, 0);
                        }
                    }

                    function gotoMatch(pos) {
                        rebuildMatchesIfNeeded();
                        if (runLogWorkspacePanel._matches.length === 0)
                            return;

                        if (pos < 0)
                            pos = runLogWorkspacePanel._matches.length - 1;
                        if (pos >= runLogWorkspacePanel._matches.length)
                            pos = 0;

                        runLogWorkspacePanel._matchPos = pos;

                        const startPos = runLogWorkspacePanel._matches[runLogWorkspacePanel._matchPos];
                        const endPos = startPos + runLogSearchField.text.length;

                        runLogText.forceActiveFocus();
                        runLogText.select(startPos, endPos);

                        const r = runLogText.positionToRectangle(startPos);
                        const targetY = Math.max(0, r.y - runLogFlick.height * 0.35);
                        const maxY = Math.max(0, runLogFlick.contentHeight - runLogFlick.height);
                        runLogFlick.contentY = Math.min(maxY, targetY);

                        const targetX = Math.max(0, r.x - runLogFlick.width * 0.25);
                        const maxX = Math.max(0, runLogFlick.contentWidth - runLogFlick.width);
                        runLogFlick.contentX = Math.min(maxX, targetX);
                    }

                    function jumpNext() { gotoMatch(runLogWorkspacePanel._matchPos + 1); }
                    function jumpPrev() { gotoMatch(runLogWorkspacePanel._matchPos - 1); }

                    function syncLogTextFromModel() {
                        runLogWorkspacePanel.currentRow = -1;
                        runLogText.text = runLogWorkspacePanel.runLogModel ? runLogWorkspacePanel.runLogModel.allText : "";
                        runLogFlick.contentY = 0;
                        runLogFlick.contentX = 0;
                        runLogWorkspacePanel._matchesDirty = true;
                    }

                    function solverLogLevelValue() {
                        if (!root.hasAppState() || root.appState.solverLogLevel === undefined || root.appState.solverLogLevel === null)
                            return 1;
                        return Math.max(0, Math.min(2, root.appState.solverLogLevel));
                    }

                    Connections {
                        target: runLogWorkspacePanel.runLogModel
                        function onLineAppended(line) {
                            runLogWorkspacePanel._matchesDirty = true;
                            var atBottom = (runLogFlick.contentY + runLogFlick.height) >= (runLogFlick.contentHeight - 4);
                            if (runLogText.length === 0) {
                                runLogText.text = line;
                            } else {
                                runLogText.insert(runLogText.length, "\n" + line);
                            }
                            if (atBottom)
                                runLogFlick.contentY = Math.max(0, runLogFlick.contentHeight - runLogFlick.height);
                        }
                        function onCleared() {
                            runLogWorkspacePanel._matchesDirty = true;
                            runLogWorkspacePanel._matches = [];
                            runLogWorkspacePanel._matchPos = -1;
                            runLogText.text = "";
                            runLogFlick.contentY = 0;
                            runLogFlick.contentX = 0;
                        }
                    }

                    Connections {
                        target: root.hasAppState() ? root.appState : null
                        function onSolverLogLevelChanged() {
                            const v = runLogWorkspacePanel.solverLogLevelValue();
                            if (runLogVerbosityCombo.currentIndex !== v)
                                runLogVerbosityCombo.currentIndex = v;
                        }
                    }

                    onRunLogModelChanged: syncLogTextFromModel()
                    Component.onCompleted: syncLogTextFromModel()

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: panelInset
                            border.color: border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 10

                                Text {
                                    text: "Run Log"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: textDark
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    TextField {
                                        id: runLogSearchField
                                        placeholderText: "Type to search... then press Enter"
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 220
                                        implicitHeight: 30
                                        onAccepted: runLogWorkspacePanel.jumpNext()
                                        onTextChanged: runLogWorkspacePanel._matchesDirty = true
                                    }

                                    CheckBox {
                                        id: runLogCaseBox
                                        text: "Case"
                                        Layout.alignment: Qt.AlignVCenter
                                        onCheckedChanged: runLogWorkspacePanel._matchesDirty = true
                                    }

                                    Text {
                                        text: runLogSearchField.text.length === 0 ? "" :
                                              (runLogWorkspacePanel._matches.length === 0 ? "0 matches"
                                               : ((runLogWorkspacePanel._matchPos + 1) + " / " + runLogWorkspacePanel._matches.length))
                                        color: textMid
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "Verbosity"
                                        color: textMid
                                        font.pixelSize: 11
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ComboBox {
                                        id: runLogVerbosityCombo
                                        implicitHeight: 30
                                        width: 140
                                        model: [
                                            { k: 0, label: "Off" },
                                            { k: 1, label: "Summary" },
                                            { k: 2, label: "Debug" }
                                        ]
                                        textRole: "label"
                                        currentIndex: runLogWorkspacePanel.solverLogLevelValue()
                                        onActivated: {
                                            if (root.hasAppState())
                                                root.appState.solverLogLevel = model[index].k;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Button {
                                        text: "Prev"
                                        Layout.preferredWidth: 60
                                        onClicked: runLogWorkspacePanel.jumpPrev()
                                    }
                                    Button {
                                        text: "Next"
                                        Layout.preferredWidth: 60
                                        onClicked: runLogWorkspacePanel.jumpNext()
                                    }

                                    Item { Layout.fillWidth: true }

                                    Button {
                                        text: "Clear search"
                                        onClicked: {
                                            runLogSearchField.text = "";
                                            runLogWorkspacePanel._matchesDirty = true;
                                            runLogWorkspacePanel._matches = [];
                                            runLogWorkspacePanel._matchPos = -1;
                                            runLogWorkspacePanel.clearSelection();
                                        }
                                    }

                                    Button {
                                        text: "Clear log"
                                        onClicked: {
                                            if (runLogWorkspacePanel.runLogModel && runLogWorkspacePanel.runLogModel.clear)
                                                runLogWorkspacePanel.runLogModel.clear();
                                            runLogWorkspacePanel.currentRow = -1;
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: border
                                }

                                Flickable {
                                    id: runLogFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    contentWidth: runLogText.contentWidth
                                    contentHeight: runLogText.contentHeight

                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                                    Rectangle {
                                        x: 0
                                        y: 0
                                        width: Math.max(runLogFlick.width, runLogFlick.contentWidth)
                                        height: Math.max(runLogFlick.height, runLogFlick.contentHeight)
                                        color: "#ffffff"
                                        border.color: border
                                        z: -1
                                    }

                                    TextEdit {
                                        id: runLogText
                                        width: Math.max(runLogFlick.width, contentWidth)
                                        text: ""
                                        readOnly: true
                                        selectByMouse: true
                                        persistentSelection: true
                                        color: textDark
                                        selectionColor: "#ffeb3b"
                                        selectedTextColor: "black"
                                        font.family: "Courier New"
                                        font.pixelSize: 11
                                        wrapMode: TextEdit.NoWrap
                                        textFormat: TextEdit.PlainText

                                        function _ensureCursorVisible() {
                                            var r = cursorRectangle;

                                            if (r.y < runLogFlick.contentY) {
                                                runLogFlick.contentY = Math.max(0, r.y);
                                            } else if (r.y + r.height > runLogFlick.contentY + runLogFlick.height) {
                                                var maxY = Math.max(0, runLogFlick.contentHeight - runLogFlick.height);
                                                runLogFlick.contentY = Math.min(maxY, r.y + r.height - runLogFlick.height);
                                            }

                                            if (r.x < runLogFlick.contentX) {
                                                runLogFlick.contentX = Math.max(0, r.x);
                                            } else if (r.x + r.width > runLogFlick.contentX + runLogFlick.width) {
                                                var maxX = Math.max(0, runLogFlick.contentWidth - runLogFlick.width);
                                                runLogFlick.contentX = Math.min(maxX, r.x + r.width - runLogFlick.width);
                                            }
                                        }

                                        onCursorRectangleChanged: _ensureCursorVisible()
                                        onSelectionStartChanged: _ensureCursorVisible()
                                        onSelectionEndChanged: _ensureCursorVisible()
                                        onSelectedTextChanged: _ensureCursorVisible()
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    id: solveRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    spacing: 10
                    z: 10

                    Button {
                        id: solveBtn
                        text: (root.hasAppState() && root.appState.solving) ? "Solving..." : "Solve column"
                        enabled: !root.hasAppState() ? true : !root.appState.solving
                        flat: true
                        implicitHeight: 26
                        implicitWidth: 100
                        padding: 10

                        background: Rectangle {
                            radius: 10
                            color: (root.hasAppState() && root.appState.solving) ? "#888888" : "#00aa00"
                            border.color: (root.hasAppState() && root.appState.solving) ? "#666666" : "#008800"
                            border.width: 2
                        }

                        contentItem: Text {
                            text: solveBtn.text
                            color: "black"
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            anchors.fill: parent
                        }

                        onClicked: {
                            if (!root.hasAppState())
                                return;
                            if (typeof root.appState.solve === "function")
                                root.appState.solve();
                            else if (typeof root.appState.solveColumn === "function")
                                root.appState.solveColumn();
                        }
                    }

                    Label {
                        id: solveTimer

                        function formatTime(ms) {
                            var totalSeconds = Math.floor(ms / 1000);
                            var minutes = Math.floor(totalSeconds / 60);
                            var seconds = totalSeconds % 60;
                            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                        }

                        text: root.hasAppState() ? formatTime(root.appState.solveElapsedMs) : ""
                        color: "#9fb2c7"
                        font.bold: true
                        Layout.preferredWidth: 60
                    }

                    Label {
                        text: "Inputs changed — click Solve column to update."
                        color: "#9fb2c7"
                        Layout.fillWidth: true
                        elide: Label.ElideRight
                        visible: root.hasAppState() && !root.appState.solving && root.appState.specsDirty
                    }
                }
            }
        }
    }
}
