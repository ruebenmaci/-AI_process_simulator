import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ─────────────────────────────────────────────────────────────────────────────
//  PConfirmDialog.qml
//
//  Modal Yes/No confirmation popup, styled to match PMessageDialog. Used for
//  "Navigate to X?" prompts after the user clicks an offending dependency in
//  the Delete Error dialog.
//
//  Visual styling matches the P-control vocabulary: chiseled 1px highlight/
//  shadow border, raised title bar.
//
//  Usage:
//    PConfirmDialog {
//        id: confirmDialog
//        title: "Navigate"
//        message: "Navigate to fluid package 'PRSV-1'?"
//        onYesClicked: { ... do navigation ... }
//        onNoClicked: { ... return to Delete Error dialog ... }
//    }
//    confirmDialog.open()
// ─────────────────────────────────────────────────────────────────────────────

Popup {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────
    property string title: "Confirm"
    property string message: ""
    property string yesText: "Yes"
    property string noText: "No"

    signal yesClicked()
    signal noClicked()

    // ── Modal positioning ───────────────────────────────────────────────────
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    width: 400
    implicitHeight: chrome.implicitHeight
    height: implicitHeight

    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 3) : 0

    padding: 0
    background: Rectangle { color: "transparent" }

    // ── Chiseled outer chrome ───────────────────────────────────────────────
    contentItem: Item {
        id: chrome
        implicitHeight: outerColumn.implicitHeight + 2

        Rectangle {
            anchors.fill: parent
            color: gAppTheme.pvFrame
            border.width: 1
            border.color: gAppTheme.pvFrameLo
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            color: "transparent"
            border.width: 1
            border.color: gAppTheme.pvFrameHi
        }

        ColumnLayout {
            id: outerColumn
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0

            // ── Title bar ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: gAppTheme.pvTitleBg
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    color: gAppTheme.pvTitleText
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            // ── Message body ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: messageText.implicitHeight + 24
                color: gAppTheme.pvFrame

                Text {
                    id: messageText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.message
                    color: gAppTheme.pvLabelText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                }
            }

            // ── Button row ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: gAppTheme.pvFrame

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    PButton {
                        width: 76
                        text: root.yesText
                        onClicked: {
                            root.yesClicked()
                            root.close()
                        }
                    }
                    PButton {
                        width: 76
                        text: root.noText
                        onClicked: {
                            root.noClicked()
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
