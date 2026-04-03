import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    // Participate nicely when this view is placed inside a ColumnLayout/RowLayout
    Layout.fillWidth: true

    // Inputs from the main UI
    property var appState: null

    // If appState gets wired after we initialize the local drawModel, push our current rows into AppState.
    onAppStateChanged: {
        // Prefer loading from AppState if it already has draw specs.
        if (appState && appState.drawSpecs && appState.drawSpecs.length > 0) loadFromAppState();
        else syncToAppState();
    }

    property double feedRateKgph: 0
    property int trays: 32
    onTraysChanged: clampRowsToTrayCount()

    // "pct" or "kgph" (UI matches React; internal storage is always pct)
    property string drawBasis: "pct"

    // UI-only model for draw specs
    // Each row:
    // { name, tray, basis, phase, value, pct }
    // basis: "feedPct" | "stageLiqPct" | "kgph"
    // phase: "L" (reserved for future vapor support)
    // value: basis-dependent value
    // pct: legacy mirror (% feed) for backward compatibility
    ListModel { id: drawModel }

    function fmt0(x) {
        if (x === undefined || x === null || !isFinite(x)) return "—";
        return Math.round(x).toLocaleString(Qt.locale(), 'f', 0);
    }

    function drawTotalPct() {
        var s = 0;
        for (var i = 0; i < drawModel.count; i++) {
            var p = Number(drawModel.get(i).pct);
            if (isFinite(p)) s += p;
        }
        return s;
    }

    function pctToKgph(pct) {
        var fr = Number(feedRateKgph);
        if (!isFinite(fr) || fr <= 0) return 0;
        return (Number(pct) / 100.0) * fr;
    }

    function kgphToPct(kgph) {
        var fr = Number(feedRateKgph);
        if (!isFinite(fr) || fr <= 0) return 0;
        return (100.0 * Number(kgph)) / fr;
    }

    function maxAllowedDraws() { return Math.max(0, trays - 2); }     // exclude bottom + top
    function minDrawTray() { return 2; }
    function maxDrawTray() { return Math.max(2, trays - 1); }
    function defaultDrawTray() { return Math.max(minDrawTray(), Math.min(maxDrawTray(), Math.round(trays / 2))); }
    function canAddDraw() { return maxAllowedDraws() > 0 && drawModel.count < maxAllowedDraws(); }

    function clampRowsToTrayCount() {
        if (_syncGuard) return;

        _syncGuard = true;

        // remove invalid side draws (must be strictly between bottom/top)
        for (var i = drawModel.count - 1; i >= 0; --i) {
            var t = Number(drawModel.get(i).tray);
            if (!isFinite(t) || t <= 1 || t >= trays) {
                drawModel.remove(i);
                continue;
            }
            // clamp to valid range in case of stale values
            var clamped = Math.max(minDrawTray(), Math.min(maxDrawTray(), Math.round(t)));
            if (clamped !== t) drawModel.setProperty(i, "tray", clamped);
        }

        // cap number of draws based on tray count
        while (drawModel.count > maxAllowedDraws()) {
            drawModel.remove(drawModel.count - 1);
        }

        _syncGuard = false;
        syncToAppState();
    }
    
    // Prevent feedback loops when syncing between UI model and AppState
    property bool _syncGuard: false

    function loadFromAppState() {
        if (!appState) return;
        if (_syncGuard) return;

        var v = appState.drawSpecs;
        if (!v || v.length === undefined) return;

        _syncGuard = true;
        drawModel.clear();
        for (var i = 0; i < v.length; i++) {
            var r = v[i];
            if (!r) continue;

            var basis = (r.basis !== undefined) ? String(r.basis) : "feedPct";
            var phase = (r.phase !== undefined) ? String(r.phase) : "L";

            var value = 0;
            if (r.value !== undefined) value = Number(r.value);
            else if (r.pct !== undefined) value = Number(r.pct);

            var pctLegacy = (basis === "feedPct")
                          ? value
                          : ((r.pct !== undefined) ? Number(r.pct) : 0);

            drawModel.append({
                name: r.name !== undefined ? r.name : ("Draw " + (i + 1)),
                tray: r.tray !== undefined ? r.tray : 1,
                basis: basis,
                phase: phase,
                value: isFinite(value) ? value : 0,
                pct: isFinite(pctLegacy) ? pctLegacy : 0
            });
        }
        _syncGuard = false;
        clampRowsToTrayCount();
    }

    function syncToAppState() {
        if (_syncGuard) return;
        if (!appState) return;

        var arr = [];
        for (var i = 0; i < drawModel.count; i++) {
            var r = drawModel.get(i);

            var basis = (r.basis !== undefined) ? String(r.basis) : "feedPct";
            var phase = (r.phase !== undefined) ? String(r.phase) : "L";
            var value = Number(r.value);
            if (!isFinite(value)) value = 0;

            var pctLegacy = (basis === "feedPct") ? value : Number(r.pct);
            if (!isFinite(pctLegacy)) pctLegacy = 0;

            arr.push({
                name: r.name,
                tray: r.tray,
                basis: basis,
                phase: phase,
                value: value,
                pct: pctLegacy
            });
        }

        appState.drawSpecs = arr;
    }

    Component.onCompleted: {
        // On startup:
        //  - If AppState already has drawSpecs, just load them.
        //  - Otherwise, push our defaults into AppState once.
        if (!appState) return;
        var ds = appState.drawSpecs;
        if (ds && ds.length !== undefined && ds.length > 0) {
            loadFromAppState();
        } else {
            syncToAppState();
        }
    }
// NOTE: ListModel does not emit QAbstractItemModel signals like dataChanged/rowsInserted.
    // We explicitly call syncToAppState() from every edit/add/remove handler instead.
    // IMPORTANT:
    // This view is embedded inside SpecsPanel (a ColumnLayout). Layouts size
    // children using implicitHeight. A Rectangle does NOT compute implicitHeight
    // from its children, so `card.implicitHeight` is 0 and the whole view
    // collapses to zero height (appears "not rendered").
    //
    // Drive implicitHeight from the inner ColumnLayout instead.
    implicitHeight: content.implicitHeight + 24

    Rectangle {
        id: card
        anchors.fill: parent
        color: "#121a24"
        radius: 10
        border.color: "#223041"
        border.width: 1
        clip: true

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Title + right-side controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        text: "Draw configuration (product basis)"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#e6eef8"
                        Layout.fillWidth: true
                    }


                    // If AppState clears drawSpecs (e.g., reset or crude defaults), re-push the current UI model (or defaults).
                    // If AppState provides a non-empty drawSpecs list, load it into the UI model.
                    Connections {
                        target: appState
                        function onDrawSpecsChanged() {
                            if (!appState) return;
                            var v = appState.drawSpecs;
                            var n = (v && v.length !== undefined) ? v.length : 0;

                            if (n > 0) {
                                loadFromAppState();
                            } else {
                                // AppState became empty; keep UI as the source of truth.
                                syncToAppState();
                            }
                        }
                    }

                    // IMPORTANT: wrap within available width
                    Label {
                        text: "Edit Name, Tray (1=bottom, " + trays + "=top), and draw rate as % of feed or kg/h. The simulator uses only mid-column draws as side draws; overhead/bottoms are handled by condenser/reboiler."
                        color: "#a9bfd6"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                    }
                }

                // Right-side controls: Total
                ColumnLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignTop
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        Layout.alignment: Qt.AlignRight

                        Label {
                            text: "Total (% feed specs):"
                            color: "#a9bfd6"
                            font.pixelSize: 12
                        }
                        Label {
                            text: drawTotalPct().toFixed(1) + "%"
                            color: "#e6eef8"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Label {
                            visible: isFinite(feedRateKgph) && feedRateKgph > 0
                            text: "(" + fmt0(pctToKgph(drawTotalPct())) + " kg/h)"
                            color: "#a9bfd6"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // Table wrapper (do NOT fill all height; keep it compact like Material Balance)
            Rectangle {
                id: tableBox
                Layout.fillWidth: true
                Layout.preferredHeight: headerRow.height + Math.max(44 * 3, Math.min(rows.contentHeight, 7 * 44))
                Layout.minimumHeight: headerRow.height + 44 * 3
                radius: 10
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Header row
                    Rectangle {
                        id: headerRow
                        Layout.fillWidth: true
                        height: 34
                        color: Qt.rgba(1, 1, 1, 0.04)

                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            columns: 5
                            columnSpacing: 8
                            rowSpacing: 0

                            Text {
                                text: "Name"
                                color: "#a9bfd6"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                            }

                            Text {
                                text: "Tray"
                                color: "#a9bfd6"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.preferredWidth: 90
                            }

                            Text {
                                text: "Basis"
                                color: "#a9bfd6"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.preferredWidth: 120
                            }

                            Text {
                                text: "Value"
                                color: "#a9bfd6"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.preferredWidth: 140
                            }

                            Item { Layout.preferredWidth: 28 }
                        }
                    }

                    // Rows
                    ListView {
                        id: rows
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(contentHeight, 44 * 3)
                        Layout.minimumHeight: 44 * 3
                        interactive: false
                        clip: false
                        model: drawModel
                        spacing: 0

                        delegate: Rectangle {
                            width: rows.width
                            height: 44
                            color: "transparent"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.08)
                            }

                            // Keep GridLayout (stable in delegates) but make Name stretch and right columns tight
                            GridLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                columns: 5
                                columnSpacing: 8

                                TextField {
                                    id: nameField
                                    text: model.name
                                    onEditingFinished: {
                                        drawModel.setProperty(index, "name", text)
                                        root.syncToAppState()
                                    }
                                    placeholderText: "Name"
                                    font.pixelSize: 12
                                    color: "#e6eef8"
                                    selectionColor: "#334155"
                                    selectedTextColor: "#e6eef8"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    background: Rectangle {
                                        radius: 8
                                        color: "#0f151e"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                }

                                SpinBox {
                                    id: traySpin
                                    from: root.minDrawTray()
                                    to: root.maxDrawTray()
                                    value: Number(model.tray)
                                    onValueModified: {
                                        drawModel.setProperty(index, "tray", value)
                                        root.syncToAppState()
                                    }
                                    editable: true
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 90
                                    background: Rectangle {
                                        radius: 8
                                        color: "#0f151e"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                    contentItem: TextInput {
                                        text: traySpin.textFromValue(traySpin.value, traySpin.locale)
                                        color: "#e6eef8"
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        validator: IntValidator { bottom: root.minDrawTray(); top: root.maxDrawTray() }
                                    }
                                }

                                ComboBox {
                                    id: basisBox
                                    model: [
                                        { text: "% Feed", key: "feedPct" },
                                        { text: "% Stage L", key: "stageLiqPct" },
                                        { text: "kg/h", key: "kgph" }
                                    ]
                                    textRole: "text"
                                    valueRole: "key"
                                    Layout.preferredWidth: 120

                                    // Capture delegate row index so signal params can't shadow it
                                    readonly property int rowIndex: index

                                    // Keep visual selection tied to this row's model value
                                    currentIndex: {
                                        var row = drawModel.get(basisBox.rowIndex);
                                        var b = (row && row.basis !== undefined) ? String(row.basis) : "feedPct";
                                        for (var j = 0; j < basisBox.model.length; ++j) {
                                            if (basisBox.model[j].key === b)
                                                return j;
                                        }
                                        return 0;
                                    }

                                    onActivated: function(comboIndex) {
                                        var selectedKey = basisBox.model[comboIndex].key;
                                        var row = drawModel.get(basisBox.rowIndex);
                                        if (!row) return;

                                        var oldBasis = (row.basis !== undefined) ? String(row.basis) : "feedPct";
                                        var oldValue = Number(row.value);
                                        if (!isFinite(oldValue) || oldValue < 0) oldValue = 0;

                                        var newValue = oldValue;

                                        // Auto-convert only for % Feed <-> kg/h switches
                                        if (oldBasis === "feedPct" && selectedKey === "kgph") {
                                            newValue = root.pctToKgph(oldValue);
                                        } else if (oldBasis === "kgph" && selectedKey === "feedPct") {
                                            newValue = root.kgphToPct(oldValue);
                                        }

                                        drawModel.setProperty(basisBox.rowIndex, "basis", selectedKey);
                                        drawModel.setProperty(basisBox.rowIndex, "value", Math.max(0, newValue));

                                        // Keep legacy pct mirror consistent for totals/material-balance
                                        if (selectedKey === "feedPct") {
                                            drawModel.setProperty(basisBox.rowIndex, "pct", Math.max(0, newValue));
                                        } else if (selectedKey === "kgph") {
                                            drawModel.setProperty(basisBox.rowIndex, "pct", Math.max(0, root.kgphToPct(newValue)));
                                        }

                                        if (row.phase === undefined)
                                            drawModel.setProperty(basisBox.rowIndex, "phase", "L");

                                        root.syncToAppState();
                                    }
                                }

                                TextField {
                                    id: massField
                                    text: {
                                        var v = Number(model.value);
                                        if (!isFinite(v)) v = 0;
                                        if (String(model.basis) === "kgph") return Math.round(v);
                                        return v.toFixed(2);
                                    }
                                    onEditingFinished: {
                                        var v = Number(text);
                                        if (!isFinite(v) || v < 0) v = 0;
                                        drawModel.setProperty(index, "value", v);

                                        // legacy mirror
                                        if (String(model.basis) === "feedPct") {
                                            drawModel.setProperty(index, "pct", v);
                                        }

                                        if (model.phase === undefined) drawModel.setProperty(index, "phase", "L");
                                        root.syncToAppState()
                                    }
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    font.pixelSize: 12
                                    color: "#e6eef8"
                                    selectionColor: "#334155"
                                    selectedTextColor: "#e6eef8"
                                    Layout.preferredWidth: 140
                                    background: Rectangle {
                                        radius: 8
                                        color: "#0f151e"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                }

                                Button {
                                    text: "✕"
                                    onClicked: {
                                        drawModel.remove(index);
                                        root.syncToAppState();
                                    }
                                    enabled: true
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 26
                                    padding: 0
                                    font.pixelSize: 12
                                    background: Rectangle {
                                        radius: 8
                                        color: enabled ? "#93c5fd" : "#334155"
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.15)
                                    }
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }
            }

            // Buttons row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "+ Add draw"
                    enabled: root.canAddDraw()
                    onClicked: {
                        if (!root.canAddDraw())
                           return;
                        drawModel.append({
                            name: "New draw",
                            tray: root.defaultDrawTray(),
                            basis: "feedPct",
                            phase: "L",
                            value: 0,
                            pct: 0
                        });
                        root.syncToAppState();
                    }
                    font.pixelSize: 12
                    font.bold: true
                    background: Rectangle {
                        radius: 10
                        color: "#93c5fd"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.15)
                    }
                }

                Button {
                    text: "Reset to defaults"
                    onClicked: {
                        if (appState) appState.resetDrawSpecsToDefaults();
                    }
                    font.pixelSize: 12
                    font.bold: true
                    background: Rectangle {
                        radius: 10
                        color: "#93c5fd"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.15)
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "Draws: " + drawModel.count + " / " + maxAllowedDraws()
                    color: "#a9bfd6"
                    font.pixelSize: 12
                }

                Label {
                    // small warning if not ~100%
                    visible: Math.abs(drawTotalPct() - 100) > 0.5
                    text: "(should be ~100%)"
                    color: "#a9bfd6"
                    font.pixelSize: 12
                }
            }
        }
    }
}