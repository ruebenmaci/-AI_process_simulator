// SpreadsheetWorkspaceWindow.qml
// Hosts SimpleSpreadsheet inside a FloatingPanel.
//
// colLabels / rowLabels are passed straight through to SimpleSpreadsheet.
// Leave them empty ([]) to get the default A/B/C… and 1/2/3… headers.
//
// Example — Component property sheet:
//   SpreadsheetWorkspaceWindow {
//       colLabels: ["Property", "Value", "Units", "Notes"]
//       rowLabels: ["ID", "Name", "Formula", "MW", "BP (°C)", "TC (°C)", "PC (bar)"]
//   }

import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    property var colLabels: []
    property var rowLabels: []

    SimpleSpreadsheet {
        anchors.fill: parent
        colLabels: root.colLabels
        rowLabels: root.rowLabels
    }
}
