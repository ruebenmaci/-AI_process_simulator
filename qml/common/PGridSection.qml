import QtQuick 2.15
import QtQuick.Layouts 1.15

// A full-width section header bar inside a PGrid.
// Span the entire grid by setting Layout.columnSpan in the parent GridLayout.
Rectangle {
    id: section
    property string title:  ""
    property string aux:    ""
    height: 20
    color: "#c8d0d8"
    border.color: "#97a2ad"
    border.width: 1

    Text {
        anchors.left: parent.left; anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: section.title
        font.pixelSize: 11
        font.bold: true
        color: "#1f2a34"
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: section.aux
        font.pixelSize: 11
        color: "#526571"
    }
}
