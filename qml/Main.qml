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

    menuBar: MenuBar {
        font.pixelSize: 12

        delegate: MenuBarItem {
            id: menuBarItem
            implicitWidth: contentItem.implicitWidth + 16
            implicitHeight: 22
            padding: 0
            leftPadding: 8
            rightPadding: 8
            topPadding: 0
            bottomPadding: 0

            contentItem: Text {
                text: menuBarItem.text
                font.pixelSize: 12
                color: menuBarItem.highlighted ? "white" : "#22303a"
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: menuBarItem.highlighted ? "#1976d2" : "transparent"
            }
        }

        Menu {
            title: "File"
            font.pixelSize: 12

            MenuItem { text: "New"; font.pixelSize: 12; onTriggered: pfdView.newFlowsheet() }
            MenuItem { text: "Open"; font.pixelSize: 12; onTriggered: pfdView.openFlowsheet() }
            MenuItem { text: "Save"; font.pixelSize: 12; onTriggered: pfdView.saveFlowsheet() }
            MenuItem { text: "Save As"; font.pixelSize: 12; onTriggered: pfdView.saveFlowsheetAs() }
        }

        Menu {
            title: "Worksheet"
            font.pixelSize: 12

            MenuItem { id: compMenuItem; text: "Components"; font.pixelSize: 12; onTriggered: pfdView.toggleComponentManager()

                contentItem: Row {
                    spacing: 6
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    Image {
                        source: Qt.resolvedUrl("../icons/svg/2D_Light_Icons/component_list.svg")
                        width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        id: compMenuText
                        text: "Components"
                        font.pixelSize: 12
                        color: compMenuItem.highlighted ? "white" : "#22303a"
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            MenuItem {
                id: fluidPkgMenuItem
                text: "Fluid Packages"
                font.pixelSize: 12
                onTriggered: pfdView.toggleFluidManager()

                contentItem: Row {
                    spacing: 6
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    Image {
                        source: Qt.resolvedUrl("../icons/svg/2D_Light_Icons/fluid_package.svg")
                        width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        text: fluidPkgMenuItem.text
                        font.pixelSize: 12
                        color: fluidPkgMenuItem.highlighted ? "white" : "#22303a"
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            MenuItem { text: "Equipment Palette"; font.pixelSize: 12; onTriggered: pfdView.toggleEquipmentPalette() }
        }

        Menu {
            title: "Settings"
            font.pixelSize: 12

            MenuItem { text: "Display"; font.pixelSize: 12; onTriggered: pfdView.openDisplaySettings() }
            MenuItem { text: "Units && Number Formats"; font.pixelSize: 12; onTriggered: pfdView.openUnitsFormatSettings() }

            Menu {
                title: "App Themes"
                font.pixelSize: 12

                MenuItem {
                    text: "Default"
                    font.pixelSize: 12
                    checkable: true
                    checked: gAppTheme.currentTheme === "Default"
                    onTriggered: pfdView.setTheme("Default")
                }
                MenuItem {
                    text: "Hysys"
                    font.pixelSize: 12
                    checkable: true
                    checked: gAppTheme.currentTheme === "HYSYS"
                    onTriggered: pfdView.setTheme("HYSYS")
                }
                MenuItem {
                    text: "AspenPlus"
                    font.pixelSize: 12
                    checkable: true
                    checked: gAppTheme.currentTheme === "AspenPlus"
                    onTriggered: pfdView.setTheme("AspenPlus")
                }
            }
        }

        Menu {
            title: "Help"
            font.pixelSize: 12
            MenuItem { text: "Solver Convergence Settings"; font.pixelSize: 12; onTriggered: pfdView.showSolverConvergenceHelp() }
            MenuItem { text: "Stripper Status Help"; font.pixelSize: 12; onTriggered: pfdView.showStripperStatusHelp() }
            MenuItem { text: "About"; font.pixelSize: 12; onTriggered: pfdView.showAbout() }
        }
    }

    PfdMainView {
        id: pfdView
        anchors.fill: parent
        flowsheet: gFlowsheet
        appState: gAppState
    }
}
