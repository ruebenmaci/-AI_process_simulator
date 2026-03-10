import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var model

    onModelChanged: {
        root.currentRow = -1;
        logText.text = root.model ? root.model.allText : "";
        flick.contentY = 0;
        flick.contentX = 0;
    }

    // Current row used for search navigation (ListView removed to enable multi-line selection)
    property int currentRow: -1

    property color fg: "#e6eef8"
    property color fgMuted: "#a9bfd6"
    property color border: "#223041"
    property color panel: "#121a24"
    property color inputBg: "#0f1620"

    // Search navigation over the TextEdit contents (fast, no per-append scanning).
    property var _matches: []        // array of start indices in logText.text
    property int _matchPos: -1       // current index into _matches
    property bool _matchesDirty: true

    function _norm(s) {
        return caseBox.checked ? s : s.toLowerCase();
    }

    function rebuildMatchesIfNeeded() {
        if (!_matchesDirty) return;

        _matchesDirty = false;
        _matches = [];
        _matchPos = -1;

        const needleRaw = searchField.text;
        if (!needleRaw || needleRaw.length === 0) return;

        const hay = _norm(logText.text);
        const needle = _norm(needleRaw);

        let i = 0;
        while (true) {
            const p = hay.indexOf(needle, i);
            if (p < 0) break;
            _matches.push(p);
            i = p + Math.max(1, needle.length);
        }
    }

    function clearSelection() {
        try {
            logText.deselect();
        } catch (e) {
            // older Qt: fall back
            logText.select(0, 0);
        }
    }

    function gotoMatch(pos) {
        rebuildMatchesIfNeeded();
        if (_matches.length === 0) return;

        // clamp/wrap
        if (pos < 0) pos = _matches.length - 1;
        if (pos >= _matches.length) pos = 0;

        _matchPos = pos;

        const start = _matches[_matchPos];
        const end = start + searchField.text.length;

        // highlight
        logText.forceActiveFocus();
        logText.select(start, end);

        // scroll into view
        const r = logText.positionToRectangle(start);
        const targetY = Math.max(0, r.y - flick.height * 0.35);
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.min(maxY, targetY);

        // keep x reasonable too
        const targetX = Math.max(0, r.x - flick.width * 0.25);
        const maxX = Math.max(0, flick.contentWidth - flick.width);
        flick.contentX = Math.min(maxX, targetX);
    }

    // React-like behavior: type a search, press Enter (or use Prev/Next) to jump between matches.
    function jumpNext() { gotoMatch(_matchPos + 1); }
    function jumpPrev() { gotoMatch(_matchPos - 1); }

    Rectangle {
        id: card
        anchors.fill: parent
        color: root.panel
        radius: 10
        border.color: root.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Label {
                text: "Run log"
                color: root.fg
                font.bold: true
                font.pixelSize: 14
            }

            // Search / navigation row (matches React master)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: searchField
                    placeholderText: "Type to search... then press Enter"
                    selectByMouse: true
                    Layout.fillWidth: true
                    Layout.minimumWidth: 220
                    implicitHeight: 30
                    onAccepted: doSearch()
                }

                CheckBox {
                    id: caseBox
                    text: "Case"
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    id: matchLabel
                    text: matchInfo
                    color: "#B0B8C4"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // Put verbosity controls on their own row so the search field has room.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Label {
                    text: "Verbosity"
                    color: "#B0B8C4"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignVCenter
                }

                ComboBox {
                    id: verbosityCombo
                    implicitHeight: 30
                    width: 140
                    model: [
                        { k: 0, label: "Off" },
                        { k: 1, label: "Summary" },
                        { k: 2, label: "Debug" }
                    ]
                    textRole: "label"
                    currentIndex: {
                        const v = Math.max(0, Math.min(2, appState.solverLogLevel));
                        return v;
                    }
                    onActivated: {
                        appState.solverLogLevel = model[index].k;
                    }
                }
            }

            Connections {
                target: appState
                function onSolverLogLevelChanged() {
                    const v = Math.max(0, Math.min(2, appState.solverLogLevel));
                    if (verbosityCombo.currentIndex !== v) verbosityCombo.currentIndex = v;
                }
            }


            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button { text: "Prev"; onClicked: root.jumpPrev(); Layout.preferredWidth: 60 }
                Button { text: "Next"; onClicked: root.jumpNext(); Layout.preferredWidth: 60 }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Clear search"
                    onClicked: {
                        searchField.text = "";
                        root._matchesDirty = true;
                        root._matches = [];
                        root._matchPos = -1;
                        root.clearSelection();
                    }
                }
                Button {
                    text: "Clear log"
                    onClicked: { if (model) model.clear(); root.currentRow = -1; }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.border; opacity: 0.9 }

            // Multi-line selection + horizontal/vertical scrolling.
            // Uses a single TextEdit bound to model.allText.
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Let TextEdit handle mouse-drag selection; Flickable is still needed
                // to provide scrollbars and programmatic scrolling.
                boundsBehavior: Flickable.StopAtBounds

                contentWidth: logText.contentWidth
                contentHeight: logText.contentHeight

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                FontMetrics {
                    id: fm
                    font: logText.font
                }

                Rectangle {
                    // White background only for the log text area (like a browser textarea),
                    // while keeping the rest of the Run Log card dark.
                    x: 0
                    y: 0
                    width: Math.max(flick.width, flick.contentWidth)
                    height: Math.max(flick.height, flick.contentHeight)
                    color: "white"
                    z: -1
                }

                TextEdit {
                    id: logText
                    width: Math.max(flick.width, contentWidth)
                    text: ""
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    color: "black"
                    selectionColor: "#ffeb3b"
                    selectedTextColor: "black"
                    font.family: "Courier New"
                    font.pixelSize: 11
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText

                    // --- Auto-scroll while selecting ---
                    // When the user drags a selection past the viewport edge, keep the
                    // caret (selection end) visible by scrolling the Flickable.
                    function _ensureCursorVisible() {
                        var r = cursorRectangle;

                        // Vertical
                        if (r.y < flick.contentY) {
                            flick.contentY = Math.max(0, r.y);
                        } else if (r.y + r.height > flick.contentY + flick.height) {
                            var maxY = Math.max(0, flick.contentHeight - flick.height);
                            flick.contentY = Math.min(maxY, r.y + r.height - flick.height);
                        }

                        // Horizontal
                        if (r.x < flick.contentX) {
                            flick.contentX = Math.max(0, r.x);
                        } else if (r.x + r.width > flick.contentX + flick.width) {
                            var maxX = Math.max(0, flick.contentWidth - flick.width);
                            flick.contentX = Math.min(maxX, r.x + r.width - flick.width);
                        }
                    }

                    onCursorRectangleChanged: _ensureCursorVisible()

                    // Qt 6 TextEdit doesn't provide an `onSelectionChanged` handler.
                    // Track selection changes via the selection endpoints and selectedText.
                    onSelectionStartChanged: _ensureCursorVisible()
                    onSelectionEndChanged: _ensureCursorVisible()
                    onSelectedTextChanged: _ensureCursorVisible()
                }
            }

            // Incremental updates (avoid rebuilding the full document each append).
            Connections {
                target: root.model
                function onLineAppended(line) {
                    root._matchesDirty = true;
                    // Preserve "follow tail" behavior if the user is already near the bottom.
                    var atBottom = (flick.contentY + flick.height) >= (flick.contentHeight - 4);
                    if (logText.length === 0) {
                        logText.text = line;
                    } else {
                        // Append with newline. Using insert avoids resetting selection/cursor.
                        logText.insert(logText.length, "\n" + line);
                    }

                    if (atBottom) {
                        flick.contentY = Math.max(0, flick.contentHeight - flick.height);
                    }
                }
                function onCleared() {
                    root._matchesDirty = true;
                    root._matches = [];
                    root._matchPos = -1;
                    logText.text = "";
                    flick.contentY = 0;
                    flick.contentX = 0;
                }
            }
        }
    }
}
