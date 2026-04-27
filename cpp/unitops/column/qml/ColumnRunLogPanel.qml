import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common"

// ─────────────────────────────────────────────────────────────────────────────
//  ColumnRunLogPanel.qml — Run Log tab.
//
//  A single PGroupBox with:
//    • A find toolbar at top: PTextField for the query, PCheckBox for case
//      sensitivity, PButton (Prev/Next/Clear), and a match-count Text.
//    • A scrollable ListView showing appState.runLogModel entries in
//      monospaced rows. Matched rows are highlighted; the current match has
//      an even darker highlight and is auto-scrolled into view.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    property var appState: null

    // ── Search state ────────────────────────────────────────────────────────
    property string searchText: ""
    property var    searchMatches: []
    property int    currentMatchPos: -1
    property bool   caseSensitive: false

    function refreshSearch() {
        if (!appState || !appState.runLogModel || searchText === "") {
            searchMatches = []
            currentMatchPos = -1
            return
        }
        searchMatches = appState.runLogModel.findMatches(searchText, caseSensitive)
        if (!searchMatches || searchMatches.length === 0) {
            currentMatchPos = -1
            return
        }
        if (currentMatchPos < 0 || currentMatchPos >= searchMatches.length) {
            currentMatchPos = 0
        }
        positionAtCurrentMatch()
    }
    function positionAtCurrentMatch() {
        if (!searchMatches || currentMatchPos < 0 || currentMatchPos >= searchMatches.length)
            return
        runLogList.positionViewAtIndex(searchMatches[currentMatchPos], ListView.Center)
    }
    function nextMatch() {
        if (!searchMatches || searchMatches.length === 0) return
        currentMatchPos = (currentMatchPos + 1) % searchMatches.length
        positionAtCurrentMatch()
    }
    function previousMatch() {
        if (!searchMatches || searchMatches.length === 0) return
        currentMatchPos = (currentMatchPos - 1 + searchMatches.length) % searchMatches.length
        positionAtCurrentMatch()
    }
    function clearSearch() {
        searchText = ""
        searchMatches = []
        currentMatchPos = -1
    }
    function lineMatches(lineText) {
        if (searchText === "") return false
        var line = String(lineText || "")
        if (caseSensitive) return line.indexOf(searchText) >= 0
        return line.toLowerCase().indexOf(searchText.toLowerCase()) >= 0
    }

    Rectangle {
        anchors.fill: parent
        color: "#e8ebef"

        Item {
            anchors.fill: parent
            anchors.margins: 4

            PGroupBox {
                anchors.fill: parent
                caption: "Run Log"
                contentPadding: 8
                fillContent: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    // ── Find toolbar ───────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Find"
                            font.pixelSize: 10
                            font.family: "Segoe UI"
                            color: "#1f2a34"
                            verticalAlignment: Text.AlignVCenter
                        }

                        PTextField {
                            id: searchField
                            Layout.preferredWidth: 240
                            Layout.minimumWidth: 160
                            // override PTextField's default fillWidth so it
                            // doesn't absorb the whole row's slack
                            Layout.fillWidth: false
                            placeholderText: "RR_SIGN, PH_FLASH_IN, STRIPPER..."
                            text: root.searchText
                            onTextChanged: {
                                root.searchText = text
                                root.refreshSearch()
                            }
                        }

                        PCheckBox {
                            text: "Case"
                            checked: root.caseSensitive
                            onToggled: {
                                root.caseSensitive = checked
                                root.refreshSearch()
                            }
                        }

                        PButton {
                            text: "Prev"
                            enabled: root.searchMatches.length > 0
                            onClicked: root.previousMatch()
                        }

                        PButton {
                            text: "Next"
                            enabled: root.searchMatches.length > 0
                            onClicked: root.nextMatch()
                        }

                        PButton {
                            text: "Clear"
                            enabled: root.searchText !== ""
                            onClicked: {
                                searchField.text = ""
                                root.clearSearch()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.searchText === "" ? ""
                                : (root.searchMatches.length === 0
                                   ? "0 matches"
                                   : ((root.currentMatchPos + 1) + " of " + root.searchMatches.length))
                            font.pixelSize: 10
                            font.family: "Segoe UI"
                            color: "#526571"
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // ── Run log list ───────────────────────────────────────
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        ListView {
                            id: runLogList
                            model: root.appState ? root.appState.runLogModel : null
                            spacing: 0

                            delegate: Item {
                                width: runLogList.width
                                height: 22

                                property bool rowIsMatch: root.lineMatches(model.text || "")
                                property bool rowIsCurrent: root.searchMatches.length > 0
                                                            && root.currentMatchPos >= 0
                                                            && index === root.searchMatches[root.currentMatchPos]

                                Rectangle {
                                    anchors.fill: parent
                                    color: rowIsCurrent ? "#ffe79a"
                                         : (rowIsMatch ? "#fff4c7"
                                                       : (index % 2 === 0 ? "#f4f6f8" : "#ffffff"))
                                }
                                Text {
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: model.text || ""
                                    font.pixelSize: 10
                                    color: "#1f2a34"
                                    font.family: "Monospace"
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 1
                                    color: "#d0d8e8"
                                }
                            }

                            onCountChanged: {
                                if (root.searchText !== "")
                                    Qt.callLater(function(){ root.refreshSearch() })
                                else
                                    Qt.callLater(function(){ runLogList.positionViewAtEnd() })
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !root.appState
                                         || !root.appState.runLogModel
                                         || root.appState.runLogModel.count === 0
                                text: "No run log entries yet"
                                color: "#526571"
                                font.pixelSize: 10
                                font.italic: true
                            }
                        }
                    }
                }
            }
        }
    }
}
