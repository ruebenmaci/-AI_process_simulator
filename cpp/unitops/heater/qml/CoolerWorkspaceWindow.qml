import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    property var appState

    anchors.fill: parent

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth:  Math.max(width,  coolerView.implicitWidth)
        contentHeight: Math.max(height, coolerView.implicitHeight)

        HeaterCoolerView {
            id: coolerView
            appState: root.appState
            width:  Math.max(parent.width,  implicitWidth)
            height: Math.max(parent.height, implicitHeight)
        }
    }
}
