import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ChatGPT5.ADT 1.0

ApplicationWindow {
    id: win
    width: 1500
    height: 980
    visible: true
    title: "AI Process Simulator"

    palette.window: "#dde4e8"
    palette.text: "#22303a"

    PfdMainView {
        anchors.fill: parent
        flowsheet: gFlowsheet
        appState: gAppState
    }
}
