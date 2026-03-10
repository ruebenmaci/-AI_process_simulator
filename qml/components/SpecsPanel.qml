import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var appState: null
    signal solveClicked()

    function hasAppState() { return appState !== null && appState !== undefined }

    // --- Spec helpers (used to enable/disable related inputs cleanly) ---
    function keyOf(combo) {
        if (!combo || combo.currentIndex < 0 || !combo.model) return "none";
        const k = combo.model[combo.currentIndex].k;
        return (k === undefined || k === null) ? "none" : String(k);
    }
    function isNoneSpec(combo) { return keyOf(combo) === "none"; }
    function isSpec(combo, k) { return keyOf(combo) === k; }

    Component.onCompleted: {
        // If this component wasn't explicitly passed an appState,
        // try to pick up the global context property named "appState".
        if (!hasAppState() && (typeof appState !== "undefined") && appState) {
            root.appState = appState
            console.log("SpecsPanel: auto-wired global appState into root.appState")
        } else {
            console.log("SpecsPanel: root.appState =", root.appState)
        }
        updateSpecColW()  // stabilize ComboBox/column widths
    }

    // Visual constants (match React look)
    readonly property color cardBg: "#111823"
    readonly property color cardBorder: "#223041"
    readonly property color labelCol: "#9fb2c7"
    readonly property color textCol: "#e6eef8"
    readonly property color inputBg: "#0e1520"
    readonly property color inputBorder: "#2a3a4c"

    // Layout tuning (compact + consistent columns)
    // - Reduce vertical height by using tighter control height and smaller row spacing.
    // - Force all spec "cells" to use the same width so columns line up.
    // - Prevent ComboBoxes from resizing based on the current selection.
    property int specColumns: 5
    property int specColW: 200
    readonly property int specRowSpacing: 6
    readonly property int specColSpacing: 14
    readonly property int specFieldH: 32
    readonly property int specLabelFS: 13

    function updateSpecColW() {
        // Make columns fit within the available card width so the right-most column
        // (Reflux ratio / Reboil ratio) never gets clipped.
        const cols = root.specColumns;
        const hMargins = 8 * 2; // card content anchors.margins (left + right)
        const totalSpacing = root.specColSpacing * (cols - 1);
        const available = Math.max(0, card.width - hMargins - totalSpacing);

        // Keep a reasonable minimum so ComboBoxes/TextFields remain usable.
        root.specColW = Math.max(170, Math.floor(available / cols));
    }

    implicitHeight: card.implicitHeight

    // --- Sync helpers ------------------------------------------------------
    // TextField/SpinBox bindings often break after user edits (which is normal
    // in Qt Quick Controls). When the selected crude changes, AppState applies
    // new defaults, but the UI won't update if bindings were broken.
    //
    // We solve this by explicitly syncing controls from AppState whenever
    // selectedCrude (or reset) changes.
    function syncFromAppState() {
        if (!hasAppState()) return;

        // Only overwrite user-edited fields if the control isn't focused.
        if (!feedRateField.activeFocus) feedRateField.text = String(appState.feedRateKgph);
        if (!feedTempField.activeFocus) feedTempField.text = String(appState.feedTempK);

        if (!feedTraySpin.activeFocus) feedTraySpin.value = appState.feedTray;
        if (!trayCountSpin.activeFocus) trayCountSpin.value = appState.trays;

        if (!topPressureField.activeFocus) topPressureField.text = String(appState.topPressurePa);
        if (!dpField.activeFocus) dpField.text = String(appState.dpPerTrayPa);

        if (!refluxRatioField.activeFocus) refluxRatioField.text = String(appState.refluxRatio);
        if (!boilupRatioField.activeFocus) boilupRatioField.text = String(appState.boilupRatio);
        if (!qcField.activeFocus) qcField.text = String(appState.qcKW);
        if (!qrField.activeFocus) qrField.text = String(appState.qrKW);
        if (!topTsetField.activeFocus) topTsetField.text = String(appState.topTsetK);
        if (!bottomTsetField.activeFocus) bottomTsetField.text = String(appState.bottomTsetK);

        // ComboBoxes: set index if present.
        const crudeIdx = appState.crudeNames.indexOf(appState.selectedCrude);
        if (crudeIdx >= 0 && crudeCombo.currentIndex !== crudeIdx)
            crudeCombo.currentIndex = crudeIdx;

        eosModeCombo.currentIndex = (appState.eosMode === "manual") ? 1 : 0;
        const eosManualIdx = ["PR","PRSV","SRK"].indexOf(appState.eosManual || "PRSV");
        if (eosManualIdx >= 0) eosManualCombo.currentIndex = eosManualIdx;

        // Specs combo boxes are keyed objects (reflux/duty/temperature etc.).
        // Keep them in sync by mapping AppState's string to the combo's model keys.
        const cRaw = (appState.condenserSpec === undefined || appState.condenserSpec === null)
            ? ""
            : String(appState.condenserSpec);
        const rRaw = (appState.reboilerSpec === undefined || appState.reboilerSpec === null)
            ? ""
            : String(appState.reboilerSpec);

        const cKey = cRaw.trim().toLowerCase();
        const rKey = rRaw.trim().toLowerCase();

        const cMap = {
            "": "none",
            "none": "none",
            "refluxratio": "reflux",
            "reflux": "reflux",
            "duty": "duty",
            "temperature": "temperature"
        };
        const rMap = {
            "": "none",
            "none": "none",
            "boilupratio": "boilup",
            "boilup": "boilup",
            "duty": "duty",
            "temperature": "temperature"
        };

        const ck = cMap[cKey] || "none";
        const rk = rMap[rKey] || "none";

        for (let i = 0; i < condSpecCombo.model.length; ++i) {
            if (condSpecCombo.model[i].k === ck) { condSpecCombo.currentIndex = i; break; }
        }
        for (let i = 0; i < rebSpecCombo.model.length; ++i) {
            if (rebSpecCombo.model[i].k === rk) { rebSpecCombo.currentIndex = i; break; }
        }
        // Murphree
        if (!etaVTopField.activeFocus) etaVTopField.text = String(appState.etaVTop);
        if (!etaVMidField.activeFocus) etaVMidField.text = String(appState.etaVMid);
        if (!etaVBotField.activeFocus) etaVBotField.text = String(appState.etaVBot);
        etaLCheck.checked = appState.enableEtaL;
        if (!etaLTopField.activeFocus) etaLTopField.text = String(appState.etaLTop);
        if (!etaLMidField.activeFocus) etaLMidField.text = String(appState.etaLMid);
        if (!etaLBotField.activeFocus) etaLBotField.text = String(appState.etaLBot);
    }

    Connections {
        target: hasAppState() ? appState : null
        function onSelectedCrudeChanged() { root.syncFromAppState(); }
        function onFeedRateKgphChanged() { if (!feedRateField.activeFocus) feedRateField.text = String(appState.feedRateKgph); }
        function onFeedTempKChanged() { if (!feedTempField.activeFocus) feedTempField.text = String(appState.feedTempK); }
        function onFeedTrayChanged() { if (!feedTraySpin.activeFocus) feedTraySpin.value = appState.feedTray; }
        function onTraysChanged() { root.syncFromAppState(); }
        function onTopPressurePaChanged() { if (!topPressureField.activeFocus) topPressureField.text = String(appState.topPressurePa); }
        function onDpPerTrayPaChanged() { if (!dpField.activeFocus) dpField.text = String(appState.dpPerTrayPa); }
        function onCondenserSpecChanged() { root.syncFromAppState(); }
        function onReboilerSpecChanged() { root.syncFromAppState(); }
        function onRefluxRatioChanged() { if (!refluxRatioField.activeFocus) refluxRatioField.text = String(appState.refluxRatio); }
        function onBoilupRatioChanged() { if (!boilupRatioField.activeFocus) boilupRatioField.text = String(appState.boilupRatio); }
        function onQcKWChanged() { if (!qcField.activeFocus) qcField.text = String(appState.qcKW); }
        function onQrKWChanged() { if (!qrField.activeFocus) qrField.text = String(appState.qrKW); }
        function onTopTsetKChanged() { if (!topTsetField.activeFocus) topTsetField.text = String(appState.topTsetK); }
        function onBottomTsetKChanged() { if (!bottomTsetField.activeFocus) bottomTsetField.text = String(appState.bottomTsetK); }
        function onEtaVTopChanged() { if (!etaVTopField.activeFocus) etaVTopField.text = String(appState.etaVTop); }
        function onEtaVMidChanged() { if (!etaVMidField.activeFocus) etaVMidField.text = String(appState.etaVMid); }
        function onEtaVBotChanged() { if (!etaVBotField.activeFocus) etaVBotField.text = String(appState.etaVBot); }
        function onEnableEtaLChanged() { etaLCheck.checked = appState.enableEtaL; }
        function onEtaLTopChanged() { if (!etaLTopField.activeFocus) etaLTopField.text = String(appState.etaLTop); }
        function onEtaLMidChanged() { if (!etaLMidField.activeFocus) etaLMidField.text = String(appState.etaLMid); }
        function onEtaLBotChanged() { if (!etaLBotField.activeFocus) etaLBotField.text = String(appState.etaLBot); }
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right

        // Keep spec columns responsive to window resizing
        Component.onCompleted: root.updateSpecColW()
        onWidthChanged: root.updateSpecColW()

        radius: 10
        border.width: 1
        border.color: cardBorder
        color: cardBg
        implicitHeight: content.implicitHeight + 16
        clip: true

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            // ---- Top grid: Crude / EOS mode / Manual EOS ----
            // Use 5 columns everywhere so later rows align perfectly.
            Flickable {
                id: specsHFlick
                Layout.fillWidth: true
                Layout.preferredHeight: specsContent.implicitHeight
                Layout.minimumHeight: specsContent.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                // Safety floor: some Qt Layouts report small implicitWidth even when child controls
                // have large minimums; keep a reasonable minimum so right-most columns can scroll.
                contentWidth: Math.max(width, specsContent.implicitWidth, 1200)
                contentHeight: specsContent.implicitHeight

                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: specsContent
                    width: specsHFlick.contentWidth
                    spacing: root.specRowSpacing

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        columnSpacing: root.specColSpacing
                        rowSpacing: root.specRowSpacing

                        // Crude
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Crude"; color: labelCol; font.pixelSize: root.specLabelFS }
                            ComboBox {
                                id: crudeCombo
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                model: hasAppState() ? appState.crudeNames : ["Brent","West Texas Intermediate","Arab Light","Western Canadian Select","Venezuelan Heavy"]
                                enabled: root.hasAppState() ? !root.appState.solving : true
                                // dark pill look
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                contentItem: Text {
                                    text: crudeCombo.displayText
                                    color: textCol
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 10
                                    rightPadding: 28
                                }
                                delegate: ItemDelegate {
                                    width: crudeCombo.width
                                    contentItem: Text { text: modelData; color: "black"; elide: Text.ElideRight }
                                }
                                Component.onCompleted: {
                                    console.log("ComboBox completed. root.appState =", root.appState);
                                    console.log("ComboBox sees global appState symbol:",
                                    (typeof appState !== "undefined") ? appState : "undefined");
                                    if (hasAppState()) {
                                        const i = appState.crudeNames.indexOf(appState.selectedCrude);
                                        if (i >= 0) currentIndex = i;
                                    }
                                    root.syncFromAppState();
                                }
                                onActivated: { console.log("Crude changed to:", currentText);
                                    if (hasAppState()) {
                                        appState.selectedCrude = model[index];
                                    }
                                    else {
                                        console.log("hasAppState() returned false.");
                                    }
                                }
                            }
                        }

                        // EOS mode
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "EOS mode"; color: labelCol; font.pixelSize: root.specLabelFS }
                            ComboBox {
                                id: eosModeCombo
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                model: ["Auto (by tray/crude)", "Manual"]
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                contentItem: Text {
                                    text: eosModeCombo.displayText
                                    color: textCol
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 10
                                    rightPadding: 28
                                }
                                Component.onCompleted: {
                                    if (!hasAppState()) return;
                                    currentIndex = (appState.eosMode === "manual") ? 1 : 0;
                                }
                                onActivated: {
                                    if (!hasAppState()) return;
                                    appState.eosMode = (currentIndex === 1) ? "manual" : "auto";
                                }
                            }
                        }

                        // Manual EOS
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Manual EOS"; color: labelCol; font.pixelSize: root.specLabelFS }
                            ComboBox {
                                id: eosManualCombo
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                model: ["PR", "PRSV", "SRK"]
                                enabled: hasAppState() ? (appState.eosMode === "manual") : true
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                contentItem: Text {
                                    text: eosManualCombo.displayText
                                    color: enabled ? textCol : "#6e8094"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 10
                                    rightPadding: 28
                                }
                                Component.onCompleted: {
                                    if (!hasAppState()) return;
                                    const v = appState.eosManual || "PRSV";
                                    const idx = ["PR","PRSV","SRK"].indexOf(v);
                                    currentIndex = idx >= 0 ? idx : 1;
                                }
                                onActivated: if (hasAppState()) appState.eosManual = model[index]
                            }
                        }

                        
                        // Spacer columns to keep a consistent 5-column grid
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }

                        // Spacer column to keep 5-column grid alignment
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }                    }

                    // ---- Feed row ----
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        columnSpacing: root.specColSpacing
                        rowSpacing: root.specRowSpacing

                        // Feed rate
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Feed rate (kg/h)"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: feedRateField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.feedRateKgph = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Trays (moved into old Feed tray slot)
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Trays"; color: labelCol; font.pixelSize: root.specLabelFS }
                            SpinBox {
                                id: trayCountSpin
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                from: hasAppState() ? appState.minTrays : 1
                                to: hasAppState() ? appState.maxTrays : 200
                                editable: true
                                value: hasAppState() ? appState.trays : 32
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                contentItem: TextInput {
                                    text: trayCountSpin.value
                                    color: textCol
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    readOnly: !trayCountSpin.editable
                                    inputMethodHints: Qt.ImhDigitsOnly
                                }
                                onValueModified: if (hasAppState()) appState.trays = value
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Feed tray (moved into old Recommended tray slot)
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Feed tray"; color: labelCol; font.pixelSize: root.specLabelFS }
                            SpinBox {
                                id: feedTraySpin
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                from: 1; to: hasAppState() ? appState.trays : 32
                                editable: true
                                value: 1
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                contentItem: TextInput {
                                    text: feedTraySpin.value
                                    color: textCol
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    readOnly: !feedTraySpin.editable
                                    inputMethodHints: Qt.ImhDigitsOnly
                                }
                                onValueModified: if (hasAppState()) appState.feedTray = value
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Feed T
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "Feed T (K)"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: feedTempField
                                implicitHeight: root.specFieldH
                                Layout.fillWidth: true
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0 }
                                color: textCol
                                background: Rectangle {
                                    radius: 10
                                    color: "#24161a"
                                    border.color: "#5b3a45"
                                    border.width: 1
                                }
                                onEditingFinished: if (hasAppState()) appState.feedTempK = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Spacer column to complete 5-column grid
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                    }

                // ---- Condenser spec row (5 columns) ----
                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: root.specColSpacing
                    rowSpacing: root.specRowSpacing

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Condenser spec"; color: labelCol; font.pixelSize: root.specLabelFS }
                        ComboBox {
                            id: condSpecCombo
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            model: [
                                { k:"none", t:"None (remove condenser)" },
                                { k:"temperature", t:"Temperature (Tc)" },
                                { k:"duty", t:"Duty (Qc)" },
                                { k:"reflux", t:"Reflux ratio (L0/D)" }
                            ]
                            textRole: "t"
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            contentItem: Text { text: condSpecCombo.displayText; color: textCol; verticalAlignment: Text.AlignVCenter; leftPadding: 10; rightPadding: 28; elide: Text.ElideRight }
                            Component.onCompleted: {
                                if (!hasAppState()) return;
                                const raw = (appState.condenserSpec === undefined || appState.condenserSpec === null)
                                    ? ""
                                    : String(appState.condenserSpec);
                                const v = raw.trim().toLowerCase();
                                const map = {
                                    "":"none",
                                    "none":"none",
                                    "refluxratio":"reflux",
                                    "reflux":"reflux",
                                    "duty":"duty",
                                    "temperature":"temperature"
                                };
                                const kk = map[v] || "reflux";
                                for (let i=0;i<model.length;i++) if (model[i].k===kk) { currentIndex=i; break; }
                            }
                            onActivated: if (hasAppState()) appState.condenserSpec = model[index].k
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Condenser type"; color: labelCol; font.pixelSize: root.specLabelFS }
                        ComboBox {
                            id: condTypeCombo
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(condSpecCombo)
                            model: [
                                { k:"total", t:"Total condenser" },
                                { k:"partial", t:"Partial condenser" }
                            ]
                            textRole: "t"
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            contentItem: Text { text: condTypeCombo.displayText; color: textCol; verticalAlignment: Text.AlignVCenter; leftPadding: 10; rightPadding: 28; elide: Text.ElideRight }
                            Component.onCompleted: {
                                if (!hasAppState()) return;
                                const v = appState.condenserType || "total";
                                currentIndex = (v === "partial") ? 1 : 0;
                            }
                            onActivated: if (hasAppState()) appState.condenserType = model[index].k
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Top condenser T (K)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: topTsetField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(condSpecCombo) && condSpecCombo.model[condSpecCombo.currentIndex].k === "temperature"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: "#24161a"; border.color: "#5b3a45"; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.topTsetK = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Condenser duty Qc (kW)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: qcField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(condSpecCombo) && condSpecCombo.model[condSpecCombo.currentIndex].k === "duty"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.qcKW = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Reflux ratio (L0/D)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: refluxRatioField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(condSpecCombo) && condSpecCombo.model[condSpecCombo.currentIndex].k === "reflux"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.refluxRatio = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }
                }

                // ---- Reboiler spec row (5 columns) ----
                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: root.specColSpacing
                    rowSpacing: root.specRowSpacing

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Reboiler spec"; color: labelCol; font.pixelSize: root.specLabelFS }
                        ComboBox {
                            id: rebSpecCombo
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            model: [
                                { k:"none", t:"None (remove reboiler)" },
                                { k:"duty", t:"Duty (Qr)" },
                                { k:"temperature", t:"Temperature (Treb)" },
                                { k:"boilup", t:"Boilup ratio (Vb/B)" }
                            ]
                            textRole: "t"
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            contentItem: Text { text: rebSpecCombo.displayText; color: textCol; verticalAlignment: Text.AlignVCenter; leftPadding: 10; rightPadding: 28; elide: Text.ElideRight }
                            Component.onCompleted: {
                                if (!hasAppState()) return;
                                const raw = (appState.reboilerSpec === undefined || appState.reboilerSpec === null)
                                    ? ""
                                    : String(appState.reboilerSpec);
                                const v = raw.trim().toLowerCase();
                                const map = {
                                    "":"none",
                                    "none":"none",
                                    "boilupratio":"boilup",
                                    "boilup":"boilup",
                                    "duty":"duty",
                                    "temperature":"temperature"
                                };
                                const kk = map[v] || "boilup";
                                for (let i=0;i<model.length;i++) if (model[i].k===kk) { currentIndex=i; break; }
                            }
                            onActivated: if (hasAppState()) appState.reboilerSpec = model[index].k
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Reboiler type"; color: labelCol; font.pixelSize: root.specLabelFS }
                        ComboBox {
                            id: rebTypeCombo
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(rebSpecCombo)
                            model: [
                                { k:"partial", t:"Partial reboiler" },
                                { k:"total", t:"Total reboiler" }
                            ]
                            textRole: "t"
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            contentItem: Text { text: rebTypeCombo.displayText; color: textCol; verticalAlignment: Text.AlignVCenter; leftPadding: 10; rightPadding: 28; elide: Text.ElideRight }
                            Component.onCompleted: {
                                if (!hasAppState()) return;
                                const v = appState.reboilerType || "partial";
                                currentIndex = (v === "total") ? 1 : 0;
                            }
                            onActivated: if (hasAppState()) appState.reboilerType = model[index].k
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Bottom T set (K)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: bottomTsetField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(rebSpecCombo) && rebSpecCombo.model[rebSpecCombo.currentIndex].k === "temperature"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: "#24161a"; border.color: "#5b3a45"; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.bottomTsetK = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Reboiler duty Qr (kW)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: qrField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(rebSpecCombo) && rebSpecCombo.model[rebSpecCombo.currentIndex].k === "duty"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.qrKW = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Reboil ratio (Vb/B)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: boilupRatioField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            enabled: !root.isNoneSpec(rebSpecCombo) && rebSpecCombo.model[rebSpecCombo.currentIndex].k === "boilup"
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.boilupRatio = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }
                }

                // ---- Pressure row (5 columns; keep alignment with other spec rows) ----
                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: root.specColSpacing
                    rowSpacing: root.specRowSpacing

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "Top pressure (Pa)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: topPressureField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.topPressurePa = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: root.specColW
                        Layout.fillWidth: false
                        spacing: 4
                        Label { text: "ΔP per tray (Pa/tray)"; color: labelCol; font.pixelSize: root.specLabelFS }
                        TextField {
                            id: dpField
                            Layout.fillWidth: true
                            implicitHeight: root.specFieldH
                            text: "0"
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0 }
                            color: textCol
                            background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                            onEditingFinished: if (hasAppState()) appState.dpPerTrayPa = Number(text)
                            Component.onCompleted: root.syncFromAppState()
                        }

                    Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                    Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                    Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                }
            }

                    // ---- Murphree controls ----
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        columnSpacing: root.specColSpacing
                        rowSpacing: root.specRowSpacing

                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_V top"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaVTopField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaVTop = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_V mid"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaVMidField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaVMid = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }
                        ColumnLayout {
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_V bot"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaVBotField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaVBot = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Spacer columns to complete 5-column grid
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }

                        RowLayout {
                            Layout.columnSpan: 5
                            Layout.fillWidth: true
                            spacing: 8

                            CheckBox {
                                id: etaLCheck
                                checked: false
                                onToggled: if (hasAppState()) appState.enableEtaL = checked
                                Component.onCompleted: root.syncFromAppState()
                            }
                            Label { text: "Enable liquid Murphree (η_L)"; color: textCol; font.pixelSize: 12 }
                        }

                        // η_L fields
                        ColumnLayout {
                            visible: hasAppState() ? appState.enableEtaL : false
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_L top"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaLTopField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaLTop = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }
                        ColumnLayout {
                            visible: hasAppState() ? appState.enableEtaL : false
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_L mid"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaLMidField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaLMid = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }
                        ColumnLayout {
                            visible: hasAppState() ? appState.enableEtaL : false
                            Layout.preferredWidth: root.specColW
                            Layout.fillWidth: false
                            spacing: 4
                            Label { text: "η_L bot"; color: labelCol; font.pixelSize: root.specLabelFS }
                            TextField {
                                id: etaLBotField
                                Layout.fillWidth: true
                                implicitHeight: root.specFieldH
                                text: "0"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 1 }
                                color: textCol
                                background: Rectangle { radius: 10; color: inputBg; border.color: inputBorder; border.width: 1 }
                                onEditingFinished: if (hasAppState()) appState.etaLBot = Number(text)
                                Component.onCompleted: root.syncFromAppState()
                            }
                        }

                        // Spacer columns to complete 5-column grid (η_L rows)
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                        Item { Layout.preferredWidth: root.specColW; Layout.preferredHeight: 1; visible: false }
                    }
                } // specsContent
            } // specsHFlick

            // ---- Draw configuration (embed) ----
            // Keep parity with React: draw config lives inside the Controls card.
            Flickable {
                id: drawCfgFlick
                Layout.fillWidth: true
                Layout.preferredHeight: drawCfg.implicitHeight
                Layout.minimumHeight: drawCfg.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
            
                // Ensure Tray/Mass% columns + delete buttons never get clipped.
                contentWidth: Math.max(width, drawCfg.implicitWidth, 1100)
                contentHeight: drawCfg.implicitHeight
            
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            
                DrawConfigView {
                    id: drawCfg
                    width: drawCfgFlick.contentWidth
                    appState: root.hasAppState() ? root.appState : null
                    Layout.preferredHeight: implicitHeight
                    feedRateKgph: root.hasAppState() ? root.appState.feedRateKgph : 0
                    trays: root.hasAppState() ? root.appState.trays : 32
                }
            }

            // Solve row (React has "Solve column" + status text)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    id: solveBtn
                    text: (root.hasAppState() && root.appState.solving) ? "Solving..." : "Solve column"
                    enabled: !root.hasAppState() ? true : !root.appState.solving
                    flat: true
                    implicitHeight: 26
                    implicitWidth: 90
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
                        if (typeof drawCfg !== "undefined" && drawCfg)
                            drawCfg.syncToAppState();
                        root.solveClicked();
                    }
                }

                // ⏱ Solve timer
                Label {
                    id: solveTimer

                    function formatTime(ms) {
                        var totalSeconds = Math.floor(ms / 1000)
                        var minutes = Math.floor(totalSeconds / 60)
                        var seconds = totalSeconds % 60
                        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
                    }

                    text: root.hasAppState() ? formatTime(root.appState.solveElapsedMs) : ""
                    color: "#9fb2c7"
                    font.bold: true
                    width: 60
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
