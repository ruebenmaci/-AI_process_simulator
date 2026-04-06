import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ChatGPT5.ADT 1.0

Item {
    id: root
    property var appState

    anchors.fill: parent

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, distillationColumn.implicitWidth)
        contentHeight: height

        DistillationColumn {
            id: distillationColumn
            appState: root.appState
            width: Math.max(parent.width, implicitWidth)
            height: parent.height
        }
    }
}
