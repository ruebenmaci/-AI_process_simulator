import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ChatGPT5.ADT 1.0
import "../../../../qml/common" as Common

Rectangle {
    id: root
    width:  1340
    height: 920

    property var appState: null

    // ── Palette — matches ComponentManagerView exactly ─────────
    readonly property color bgOuter:    "#d8dde2"
    readonly property color cmdBar:     "#c8d0d8"
    readonly property color frameInner: "#e8ebef"
    readonly property color hdrBg:      "#c8d0d8"
    readonly property color borderOut:  "#6d7883"
    readonly property color borderIn:   "#97a2ad"
    readonly property color textMain:   "#1f2a34"
    readonly property color textMuted:  "#526571"
    readonly property color valueBlue:  "#1c4ea7"
    readonly property color activeBlue: "#2e73b8"
    readonly property color inputBg:    "#ffffff"
    readonly property color rowEven:    "#f4f6f8"
    readonly property color rowOdd:     "#ffffff"
    readonly property color warnAmber:  "#d6b74a"
    readonly property color errorRed:   "#b23b3b"
    readonly property color white:      "#ffffff"

    readonly property int   headH:  20
    readonly property int   rowH:   22
    readonly property int   fsLbl:  10
    readonly property int   fsVal:  10
    readonly property int   fsSm:   9

    color: bgOuter

    // ── Helpers ────────────────────────────────────────────────
    function fmt2(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(2)  : "—" }
    function fmt3(x)  { const n = Number(x); return isFinite(n) ? n.toFixed(3)  : "—" }
    function fmtMs(ms) {
        const s = Math.floor((ms || 0) / 1000)
        return String(Math.floor(s / 60)).padStart(2,"0") + ":" + String(s % 60).padStart(2,"0")
    }
    function solveStatus() {
        if (!appState) return "—"
        if (appState.solving)    return "Solving…"
        if (appState.solved)     return "Converged"
        if (appState.specsDirty) return "Specs changed – re-run"
        return "Not solved"
    }
    function solveStatusColor() {
        if (!appState)           return textMuted
        if (appState.solving)    return warnAmber
        if (appState.solved)     return "#1a7a3c"
        if (appState.specsDirty) return warnAmber
        return errorRed
    }

    // ── Tab state ──────────────────────────────────────────────
    property string activeTab:       "Worksheet/Solver"
    property string worksheetSubTab: "Setup"
    property string profilesSubTab:  "Tray Table"

    // ──────────────────────────────────────────────────────────
    //  Shared primitives
    // ──────────────────────────────────────────────────────────
    component SectionHeader : Rectangle {
        property alias text: lbl.text
        height: headH; color: hdrBg; border.color: borderIn; border.width: 1
        Text { id: lbl; anchors.left: parent.left; anchors.leftMargin: 6
               anchors.verticalCenter: parent.verticalCenter
               font.pixelSize: fsLbl; font.bold: true; color: textMain }
    }

    component CompactFrame : Rectangle {
        color: frameInner; border.color: borderIn; border.width: 1
    }

    // A standard label|control row — label on left, control fills remaining width
    component FormRow : Item {
        id: frow
        property string label: ""
        property string unit:  ""
        property alias  control: controlSlot.data
        height: rowH
        // Alternating background
        Rectangle { anchors.fill: parent; color: parent.ListView ? (parent.ListView.index % 2 === 0 ? rowEven : rowOdd) : "transparent" }
        Text { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 160
               text: frow.label; font.pixelSize: fsLbl; color: textMuted }
        Item { id: controlSlot
               anchors { left: parent.left; leftMargin: 168; right: unitTxt.visible ? unitTxt.left : parent.right; rightMargin: 4
                         verticalCenter: parent.verticalCenter }
               height: rowH - 4 }
        Text { id: unitTxt; visible: frow.unit !== ""; text: frow.unit
               anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
               font.pixelSize: fsSm; color: textMuted; width: 32; horizontalAlignment: Text.AlignRight }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: borderIn }
    }

    // Compact read-only value row
    component ValueRow : Item {
        property string label: ""
        property string value: ""
        property string unit:  ""
        property color  vColor: valueBlue
        height: rowH
        Text { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 160
               text: parent.label; font.pixelSize: fsLbl; color: textMuted }
        Text { anchors { right: unitItem.visible ? unitItem.left : parent.right
                         rightMargin: unitItem.visible ? 4 : 8; verticalCenter: parent.verticalCenter }
               text: parent.value; font.pixelSize: fsVal; color: parent.vColor }
        Item { id: unitItem; visible: parent.unit !== ""; width: 38
               anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
               Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                      text: parent.parent.unit; font.pixelSize: fsSm; color: textMuted } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: borderIn }
    }

    // Styled TextField
    component CField : TextField {
        implicitHeight: rowH - 4
        font.pixelSize: fsVal; selectByMouse: true
        padding: 2; leftPadding: 4; rightPadding: 4; topPadding: 1; bottomPadding: 1
        horizontalAlignment: Text.AlignRight; color: valueBlue
        background: Rectangle { color: inputBg; border.color: borderIn; border.width: 1 }
    }

    // Styled ComboBox
    component CCombo : ComboBox {
        implicitHeight: rowH - 4
        font.pixelSize: fsVal
        background: Rectangle { color: inputBg; border.color: borderIn; border.width: 1 }
        contentItem: Text { leftPadding: 4; rightPadding: 18; text: parent.displayText
                            color: valueBlue; font.pixelSize: fsVal; verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight }
    }

    // Styled SpinBox
    component CSpin : SpinBox {
        implicitHeight: rowH - 4; implicitWidth: 90
        font.pixelSize: fsVal
        background: Rectangle { color: inputBg; border.color: borderIn; border.width: 1 }
    }

    // Tab button (top-level)
    component TabBtn : Rectangle {
        id: tbr; property string label: ""; property bool active: false; signal clicked
        height: active ? 26 : 24
        radius: 0
        color: active ? activeBlue : (tma.containsMouse ? "#e4e8ed" : "#d8dde3")
        border.color: active ? "#1a5a90" : borderIn; border.width: 1
        transform: Translate { y: tbr.active ? -2 : 0 }
        z: active ? 2 : 1
        Rectangle { anchors.left:tbr.left; anchors.top:tbr.top; width:tbr.width-1; height:1; color:"#f8fafc"; visible:!active }
        Rectangle { anchors.left:tbr.left; anchors.top:tbr.top; width:1; height:tbr.height-1; color:"#f8fafc"; visible:!active }
        Rectangle { anchors.left: tbr.left; anchors.right: tbr.right; anchors.bottom: tbr.bottom; height: active ? 2 : 1; color: active ? cmdBar : borderIn }
        Text { anchors.centerIn: parent; text: tbr.label; font.pixelSize: fsLbl; font.bold: true
               color: active ? white : textMain }
        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; onClicked: tbr.clicked() }
    }

    component SubTabBtn : Rectangle {
        id: stbr; property string label: ""; property bool active: false; signal clicked
        height: active ? 26 : 24
        radius: 0
        color: active ? activeBlue : (stma.containsMouse ? "#e4e8ed" : "#d8dde3")
        border.color: active ? "#1a5a90" : borderIn; border.width: 1
        transform: Translate { y: stbr.active ? -2 : 0 }
        z: active ? 2 : 1
        Rectangle { anchors.left: stbr.left; anchors.right: stbr.right; anchors.bottom: stbr.bottom; height: active ? 2 : 1; color: active ? cmdBar : borderIn }
        Text { anchors.centerIn: parent; text: stbr.label; font.pixelSize: fsLbl; font.bold: true
               color: active ? white : textMain }
        MouseArea { id: stma; anchors.fill: parent; hoverEnabled: true; onClicked: stbr.clicked() }
    }

    component HDivider : Rectangle { height: 1; color: borderIn }

    // ──────────────────────────────────────────────────────────
    //  Root layout
    // ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        color: bgOuter; border.color: borderOut; border.width: 1

        // Top tab bar
        Rectangle {
            id: topTabBar
            x: 0; y: 0; width: parent.width; height: 40
            color: cmdBar; border.color: borderIn; border.width: 1

            Common.ClassicTabs {
                id: mainTabs
                x: 8; y: 6
                tabs: [
                    { text: "Worksheet/Solver", width: 130 },
                    { text: "Performance",      width: 92 },
                    { text: "Profiles",         width: 76 },
                    { text: "Products",         width: 76 },
                    { text: "Run Log",          width: 74 },
                    { text: "Diagnostics",      width: 90 }
                ]
                currentIndex: ["Worksheet/Solver","Performance","Profiles","Products","Run Log","Diagnostics"].indexOf(root.activeTab)
                onTabClicked: function(index) {
                    const names = ["Worksheet/Solver","Performance","Profiles","Products","Run Log","Diagnostics"]
                    root.activeTab = names[index]
                }
            }
        }

        // Content area
        Item {
            id: content
            x: 6; y: topTabBar.height + 6
            width: parent.width - 12
            height: parent.height - topTabBar.height - 12

            // ==================================================
            //  WORKSHEET / SOLVER TAB
            // ==================================================
            Item {
                anchors.fill: parent
                visible: root.activeTab === "Worksheet/Solver"

                // Sub-tab bar
                Rectangle {
                    id: wsSubBar
                    x: 0; y: 0; width: parent.width; height: 32
                    color: cmdBar; border.color: borderIn; border.width: 1
                    Common.ClassicTabs {
                        id: wsTabs
                        x: 6; y: 3
                        tabs: [
                            { text: "Setup", width: 80 },
                            { text: "Draws/Solver", width: 102 }
                        ]
                        currentIndex: root.worksheetSubTab === "Draws/Solver" ? 1 : 0
                        onTabClicked: function(index) { root.worksheetSubTab = index === 1 ? "Draws/Solver" : "Setup" }
                    }
                }

                // ── SETUP sub-tab ──────────────────────────────
                Item {
                    visible: root.worksheetSubTab === "Setup"
                    anchors { left: parent.left; right: parent.right; top: wsSubBar.bottom; topMargin: 4; bottom: parent.bottom }

                    property real halfW: (width - 6) / 2
                    property int  inputW: 110
                    property int  unitW:  36

                    // LEFT COLUMN
                    // General Setup
                    CompactFrame {
                        id: generalCard
                        x: 0; y: 0; width: parent.halfW
                        height: generalSectionHdr.height + generalCol.implicitHeight + 1

                        SectionHeader { id: generalSectionHdr; width: parent.width; text: "General Setup" }

                        Column {
                            id: generalCol
                            anchors { left: parent.left; right: parent.right; top: generalSectionHdr.bottom }

                            // Column Name
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Column Name"; font.pixelSize:fsLbl; color:textMuted }
                                CField {
                                    anchors { left:parent.left; leftMargin:168; right:parent.right; rightMargin:6; verticalCenter:parent.verticalCenter }
                                    text: appState ? (appState.name || appState.id || "") : ""
                                    onEditingFinished: { if (appState) appState.name = text }
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Feed Stream
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Feed Stream"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter}
                                       text: appState?(appState.connectedFeedStreamName||"—"):"—"
                                       font.pixelSize:fsVal; color:valueBlue }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Feed fluid — read-only, shows the fluid package assigned to the feed stream
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Feed fluid"; font.pixelSize:fsLbl; color:textMuted }
                                Text {
                                    anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter}
                                    text: {
                                        if (!appState || !appState.feedStream) return "—"
                                        var pkgName = appState.feedStream.selectedFluidPackageName
                                        if (pkgName && pkgName !== "") return pkgName
                                        var fluid = appState.feedStream.selectedFluid
                                        if (fluid && fluid !== "") return fluid
                                        return "—"
                                    }
                                    font.pixelSize:fsVal; color:valueBlue; elide:Text.ElideRight
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Total Trays
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Total Trays"; font.pixelSize:fsLbl; color:textMuted }
                                CSpin {
                                    anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter}
                                    from:appState?appState.minTrays:1; to:appState?appState.maxTrays:200
                                    value:appState?appState.trays:32
                                    onValueModified: { if (appState) appState.trays=value }
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Feed Tray
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Feed Tray"; font.pixelSize:fsLbl; color:textMuted }
                                CSpin {
                                    anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter}
                                    from:1; to:appState?Math.max(1,appState.trays):32
                                    value:appState?appState.feedTray:4
                                    onValueModified: { if (appState) appState.feedTray=value }
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Feed Rate
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Feed Rate"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"kg/h"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState&&appState.feedStream?String(Math.round(appState.feedStream.flowRateKgph)):""
                                    onEditingFinished:{if(appState&&appState.feedStream)appState.feedStream.flowRateKgph=Number(text)}
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Feed Temperature
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Feed Temperature"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"K"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState&&appState.feedStream?fmt3(appState.feedStream.temperatureK):""
                                    onEditingFinished:{if(appState&&appState.feedStream)appState.feedStream.temperatureK=Number(text)}
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Top Pressure
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Top Pressure"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"Pa"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState?String(Math.round(appState.topPressurePa)):""
                                    onEditingFinished:{if(appState)appState.topPressurePa=Number(text)}
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // Pressure Drop/Tray
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"Pressure Drop/Tray"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"Pa"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState?String(Math.round(appState.dpPerTrayPa)):""
                                    onEditingFinished:{if(appState)appState.dpPerTrayPa=Number(text)}
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // T Overhead
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"T Overhead (spec)"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"K"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState?fmt3(appState.topTsetK):""
                                    onEditingFinished:{if(appState)appState.topTsetK=Number(text)}
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }
                            // T Bottoms
                            Item { width: parent.width; height: rowH
                                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:160; text:"T Bottoms (spec)"; font.pixelSize:fsLbl; color:textMuted }
                                Text { anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"K"; font.pixelSize:fsSm; color:textMuted; width:32; horizontalAlignment:Text.AlignRight }
                                CField {
                                    anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:parent.width-210
                                    text:appState?fmt3(appState.bottomTsetK):""
                                    onEditingFinished:{if(appState)appState.bottomTsetK=Number(text)}
                                }
                            }
                        }
                    }

                    // Murphree Efficiencies
                    CompactFrame {
                        id: effCard2
                        x: 0; y: generalCard.height + 4; width: parent.halfW
                        height: effHdr.height + effEnableRow.height + effColHdr.height + etaTopRow2.height + etaMidRow2.height + etaBotRow2.height + 1

                        SectionHeader { id: effHdr; width: parent.width; text: "Murphree Efficiencies" }

                        // Enable toggle
                        Item { id: effEnableRow; anchors{left:parent.left;right:parent.right;top:effHdr.bottom} height:rowH
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Enable Liquid η";font.pixelSize:fsLbl;color:textMuted}
                            CheckBox{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter}
                                     checked:appState?appState.enableEtaL:false
                                     onToggled:{if(appState)appState.enableEtaL=checked}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        // Column headers
                        Item { id: effColHdr; anchors{left:parent.left;right:parent.right;top:effEnableRow.bottom} height:rowH
                            property real secW: 160; property real etaW: (width-secW-12)/2
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:secW;text:"Section";font.pixelSize:fsSm;font.bold:true;color:textMain}
                            Text{x:6+secW;anchors.verticalCenter:parent.verticalCenter;width:effColHdr.etaW;text:"Vapour η";font.pixelSize:fsSm;font.bold:true;color:textMain;horizontalAlignment:Text.AlignRight}
                            Text{x:6+secW+effColHdr.etaW;anchors.verticalCenter:parent.verticalCenter;width:effColHdr.etaW;text:"Liquid η";font.pixelSize:fsSm;font.bold:true;color:textMain;horizontalAlignment:Text.AlignRight}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        // Top
                        Item { id: etaTopRow2; anchors{left:parent.left;right:parent.right;top:effColHdr.bottom} height:rowH
                            property real secW:160; property real etaW:(width-secW-12)/2
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;text:"Top";font.pixelSize:fsLbl;color:textMuted}
                            CField{x:6+secW;anchors.verticalCenter:parent.verticalCenter;width:etaTopRow2.etaW-6
                                   text:appState?fmt3(appState.etaVTop):"";onEditingFinished:{if(appState)appState.etaVTop=Number(text)}}
                            CField{x:6+secW+etaTopRow2.etaW;anchors.verticalCenter:parent.verticalCenter;width:etaTopRow2.etaW-6
                                   enabled:appState?appState.enableEtaL:false
                                   text:appState?fmt3(appState.etaLTop):"";onEditingFinished:{if(appState)appState.etaLTop=Number(text)}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        // Middle
                        Item { id: etaMidRow2; anchors{left:parent.left;right:parent.right;top:etaTopRow2.bottom} height:rowH
                            property real secW:160; property real etaW:(width-secW-12)/2
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;text:"Middle";font.pixelSize:fsLbl;color:textMuted}
                            CField{x:6+secW;anchors.verticalCenter:parent.verticalCenter;width:etaMidRow2.etaW-6
                                   text:appState?fmt3(appState.etaVMid):"";onEditingFinished:{if(appState)appState.etaVMid=Number(text)}}
                            CField{x:6+secW+etaMidRow2.etaW;anchors.verticalCenter:parent.verticalCenter;width:etaMidRow2.etaW-6
                                   enabled:appState?appState.enableEtaL:false
                                   text:appState?fmt3(appState.etaLMid):"";onEditingFinished:{if(appState)appState.etaLMid=Number(text)}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        // Bottom
                        Item { id: etaBotRow2; anchors{left:parent.left;right:parent.right;top:etaMidRow2.bottom} height:rowH
                            property real secW:160; property real etaW:(width-secW-12)/2
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;text:"Bottom";font.pixelSize:fsLbl;color:textMuted}
                            CField{x:6+secW;anchors.verticalCenter:parent.verticalCenter;width:etaBotRow2.etaW-6
                                   text:appState?fmt3(appState.etaVBot):"";onEditingFinished:{if(appState)appState.etaVBot=Number(text)}}
                            CField{x:6+secW+etaBotRow2.etaW;anchors.verticalCenter:parent.verticalCenter;width:etaBotRow2.etaW-6
                                   enabled:appState?appState.enableEtaL:false
                                   text:appState?fmt3(appState.etaLBot):"";onEditingFinished:{if(appState)appState.etaLBot=Number(text)}}
                        }
                    }

                    // RIGHT COLUMN — Condenser
                    CompactFrame {
                        id: condCard2
                        x: parent.halfW + 6; y: 0; width: parent.halfW
                        height: condHdr.height + condCol2.implicitHeight + 1

                        SectionHeader { id: condHdr; width: parent.width; text: "Condenser" }
                        Column {
                            id: condCol2
                            anchors { left:parent.left; right:parent.right; top:condHdr.bottom }
                            // Condenser Type
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Condenser Type";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["total","partial"];currentIndex:appState?(appState.condenserType==="partial"?1:0):0
                                    onActivated:{if(appState)appState.condenserType=model[index]}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Spec Type
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Spec Type";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["reflux","duty","temperature"]
                                    currentIndex:{if(!appState)return 0;var s=(appState.condenserSpec||"").toLowerCase();if(s==="refluxratio"||s==="reflux")return 0;if(s==="duty")return 1;if(s==="temperature")return 2;return 0}
                                    onActivated:{if(appState)appState.condenserSpec=model[index]}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Reflux Ratio
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Reflux Ratio";font.pixelSize:fsLbl;color:textMuted}
                                CField{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?fmt3(appState.refluxRatio):"";onEditingFinished:{if(appState)appState.refluxRatio=Number(text)}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Fixed Duty
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Fixed Duty";font.pixelSize:fsLbl;color:textMuted}
                                Text{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"kW";font.pixelSize:fsSm;color:textMuted;width:32;horizontalAlignment:Text.AlignRight}
                                CField{anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?String(Math.round(appState.qcKW)):"";onEditingFinished:{if(appState)appState.qcKW=Number(text)}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // T Setpoint
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"T Setpoint";font.pixelSize:fsLbl;color:textMuted}
                                Text{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"K";font.pixelSize:fsSm;color:textMuted;width:32;horizontalAlignment:Text.AlignRight}
                                CField{anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?fmt3(appState.topTsetK):"";onEditingFinished:{if(appState)appState.topTsetK=Number(text)}}
                            }
                        }
                    }

                    // Reboiler
                    CompactFrame {
                        id: rebCard2
                        x: parent.halfW + 6; y: condCard2.height + 4; width: parent.halfW
                        height: rebHdr.height + rebCol2.implicitHeight + 1

                        SectionHeader { id: rebHdr; width: parent.width; text: "Reboiler" }
                        Column {
                            id: rebCol2
                            anchors { left:parent.left; right:parent.right; top:rebHdr.bottom }
                            // Reboiler Type
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Reboiler Type";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["partial","total"];currentIndex:appState?(appState.reboilerType==="total"?1:0):0
                                    onActivated:{if(appState)appState.reboilerType=model[index]}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Spec Type
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Spec Type";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["boilup","duty","temperature"]
                                    currentIndex:{if(!appState)return 0;var s=(appState.reboilerSpec||"").toLowerCase();if(s==="boilup"||s==="boilupratio")return 0;if(s==="duty")return 1;if(s==="temperature")return 2;return 0}
                                    onActivated:{if(appState)appState.reboilerSpec=model[index]}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Boilup Ratio
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Boilup Ratio";font.pixelSize:fsLbl;color:textMuted}
                                CField{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?fmt3(appState.boilupRatio):"";onEditingFinished:{if(appState)appState.boilupRatio=Number(text)}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // Fixed Duty
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Fixed Duty";font.pixelSize:fsLbl;color:textMuted}
                                Text{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"kW";font.pixelSize:fsSm;color:textMuted;width:32;horizontalAlignment:Text.AlignRight}
                                CField{anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?String(Math.round(appState.qrKW)):"";onEditingFinished:{if(appState)appState.qrKW=Number(text)}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            // T Setpoint
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"T Setpoint";font.pixelSize:fsLbl;color:textMuted}
                                Text{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} text:"K";font.pixelSize:fsSm;color:textMuted;width:32;horizontalAlignment:Text.AlignRight}
                                CField{anchors{right:parent.right;rightMargin:42;verticalCenter:parent.verticalCenter} width:110
                                    text:appState?fmt3(appState.bottomTsetK):"";onEditingFinished:{if(appState)appState.bottomTsetK=Number(text)}}
                            }
                        }
                    }

                    // Thermodynamics
                    CompactFrame {
                        x: parent.halfW + 6; y: condCard2.height + rebCard2.height + 8; width: parent.halfW
                        height: thermoHdr.height + thermoCol2.implicitHeight + 1

                        SectionHeader { id: thermoHdr; width: parent.width; text: "Thermodynamics" }
                        Column {
                            id: thermoCol2
                            anchors { left:parent.left; right:parent.right; top:thermoHdr.bottom }
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"EOS Mode";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["Auto","Manual"];currentIndex:appState?(appState.eosMode==="manual"?1:0):0
                                    onActivated:{if(appState)appState.eosMode=(index===1?"manual":"auto")}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:"Manual EOS";font.pixelSize:fsLbl;color:textMuted}
                                CCombo{anchors{right:parent.right;rightMargin:6;verticalCenter:parent.verticalCenter} width:110
                                    model:["PR","PRSV","SRK"]
                                    currentIndex:{if(!appState)return 1;var m=["PR","PRSV","SRK"].indexOf(appState.eosManual);return m>=0?m:1}
                                    enabled:appState?appState.eosMode==="manual":false
                                    onActivated:{if(appState)appState.eosManual=model[index]}}
                            }
                        }
                    }
                } // Setup sub-tab

                // ── DRAWS/SOLVER sub-tab ───────────────────────
                Item {
                    visible: root.worksheetSubTab === "Draws/Solver"
                    anchors { left:parent.left; right:parent.right; top:wsSubBar.bottom; topMargin:4; bottom:parent.bottom }

                    property real drawW:  (width - 6) * 2 / 3
                    property real solveW: (width - 6) / 3

                    // Draw Specifications
                    CompactFrame {
                        id: drawCard2
                        x: 0; y: 0; width: parent.drawW; height: parent.height

                        SectionHeader { id: drawHdr2; width: parent.width; text: "Draw Specifications" }

                        function feedKgph() { return (appState&&appState.feedStream)?Number(appState.feedStream.flowRateKgph):0 }
                        function totalTargetPct() {
                            if (!appState||!appState.drawSpecs) return 0
                            var tot=0; var specs=appState.drawSpecs
                            for (var i=0;i<specs.length;i++){var v=Number(specs[i].value);if(specs[i].basis==="feedPct"&&isFinite(v))tot+=v}
                            return tot
                        }
                        function commitSpecs(s){if(appState)appState.drawSpecs=s}

                        // Column headers
                        Item {
                            id: drawColHdr
                            anchors{left:parent.left;right:parent.right;top:drawHdr2.bottom}  height:rowH
                            Row {
                                anchors{left:parent.left;right:parent.right;leftMargin:6;rightMargin:6}  height:parent.height; spacing:4
                                Text{width:parent.width-288;text:"Name"; font.pixelSize:fsSm;font.bold:true;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter}
                                Text{width:60;text:"Tray";  font.pixelSize:fsSm;font.bold:true;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter}
                                Text{width:52;text:"Phase"; font.pixelSize:fsSm;font.bold:true;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter}
                                Text{width:78;text:"Basis"; font.pixelSize:fsSm;font.bold:true;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter}
                                Text{width:68;text:"Value"; font.pixelSize:fsSm;font.bold:true;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                Text{width:24;text:"";      height:parent.height}
                            }
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }

                        ScrollView {
                            anchors{left:parent.left;right:parent.right;top:drawColHdr.bottom;bottom:drawFooter2.top} clip:true
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            Column {
                                width: parent.width; spacing:0
                                Repeater {
                                    model: appState?appState.drawSpecs:[]
                                    delegate: Item {
                                        width: parent?parent.width:0; height:rowH
                                        property var spec: modelData; property int rowIdx: index
                                        Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                                        Row {
                                            anchors{left:parent.left;right:parent.right;leftMargin:6;rightMargin:6}  height:parent.height; spacing:4
                                            CField{width:parent.width-288;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignLeft
                                                text:spec.name||""
                                                onEditingFinished:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c[rowIdx].name=text;drawCard2.commitSpecs(c)}}
                                            CSpin{width:60;anchors.verticalCenter:parent.verticalCenter;from:2;to:appState?Math.max(2,appState.trays-1):30;value:spec.tray||1
                                                onValueModified:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c[rowIdx].tray=value;drawCard2.commitSpecs(c)}}
                                            CCombo{width:52;anchors.verticalCenter:parent.verticalCenter;model:["L","V"];currentIndex:(spec.phase==="V")?1:0
                                                onActivated:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c[rowIdx].phase=model[index];drawCard2.commitSpecs(c)}}
                                            CCombo{width:78;anchors.verticalCenter:parent.verticalCenter;model:["feedPct","kg/h"];currentIndex:(spec.basis==="kg/h")?1:0
                                                onActivated:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c[rowIdx].basis=model[index];drawCard2.commitSpecs(c)}}
                                            CField{width:68;anchors.verticalCenter:parent.verticalCenter
                                                text:spec.value!==undefined?fmt2(Number(spec.value)):"0.00"
                                                onEditingFinished:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c[rowIdx].value=Number(text);drawCard2.commitSpecs(c)}}
                                            Rectangle{width:24;height:parent.height-4;anchors.verticalCenter:parent.verticalCenter;color:"transparent"
                                                Text{anchors.centerIn:parent;text:"×";font.pixelSize:11;color:errorRed;font.bold:true}
                                                MouseArea{anchors.fill:parent;onClicked:{var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c.splice(rowIdx,1);drawCard2.commitSpecs(c)}}}
                                        }
                                        HDivider{anchors.bottom:parent.bottom;width:parent.width}
                                    }
                                }
                            }
                        }

                        Item {
                            id: drawFooter2
                            anchors{left:parent.left;right:parent.right;bottom:parent.bottom}  height:36
                            HDivider{anchors.top:parent.top;width:parent.width}
                            Row {
                                anchors{left:parent.left;right:parent.right;leftMargin:6;rightMargin:6;verticalCenter:parent.verticalCenter}  spacing:6
                                ClassicButton{text:"+ Add Draw";width:86;baseColor:activeBlue
                                    onClicked:{if(!appState)return;var s=appState.drawSpecs;var c=[];for(var k=0;k<s.length;k++)c.push(Object.assign({},s[k]));c.push({name:"New Draw",tray:appState.feedTray||16,basis:"feedPct",phase:"L",value:0});drawCard2.commitSpecs(c)}}
                                ClassicButton{text:"Reset";width:58
                                    onClicked:{if(appState)appState.resetDrawSpecsToDefaults()}}
                                Text{anchors.verticalCenter:parent.verticalCenter
                                    text:{var t=drawCard2.totalTargetPct();return "Total: "+t.toFixed(1)+"%  ("+Math.round(t*drawCard2.feedKgph()/100)+" kg/h)"}
                                    font.pixelSize:fsSm;color:textMuted}
                            }
                        }
                    }

                    // Solve / Status
                    CompactFrame {
                        x: parent.drawW + 6; y: 0; width: parent.solveW; height: parent.height

                        SectionHeader { id: solveHdr; width: parent.width; text: "Solve / Status" }

                        // Solve buttons
                        Row {
                            anchors{left:parent.left;right:parent.right;top:solveHdr.bottom;topMargin:6;leftMargin:6}  spacing:6; height:28
                            ClassicButton{text:"Solve Column";width:110;baseColor:activeBlue
                                enabled:appState?!appState.solving:false
                                onClicked:{if(appState&&!appState.solving)appState.solve()}}
                            ClassicButton{text:"Clear / Reset";width:96
                                onClicked:{if(appState)appState.reset()}}
                        }

                        // Status rows
                        Column {
                            anchors{left:parent.left;right:parent.right;top:solveHdr.bottom;topMargin:42} spacing:0

                            Item{width:parent.width;height:rowH
                                Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:130;text:"Solve Status";font.pixelSize:fsLbl;color:textMuted}
                                Text{anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter}
                                    text:solveStatus();color:solveStatusColor();font.pixelSize:fsVal;font.bold:true}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }

                            Repeater {
                                model:[
                                    {label:"Elapsed Time",  value:appState?fmtMs(appState.solveElapsedMs):"—"},
                                    {label:"Condenser Qc",  value:appState?(String(Math.round(appState.qcCalcKW))+" kW"):"—"},
                                    {label:"Reboiler Qr",   value:appState?(String(Math.round(appState.qrCalcKW))+" kW"):"—"},
                                    {label:"Reflux Frac.",  value:appState?(fmt3(appState.refluxFraction*100)+"%"):"—"},
                                    {label:"Boilup Frac.",  value:appState?(fmt3(appState.boilupFraction*100)+"%"):"—"},
                                    {label:"T Overhead",    value:appState?(fmt3(appState.tColdK)+" K"):"—"},
                                    {label:"T Bottoms",     value:appState?(fmt3(appState.tHotK)+" K"):"—"}
                                ]
                                delegate: Column {
                                    width:parent.width
                                    Item{width:parent.width;height:rowH
                                        Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                                        Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:130;text:modelData.label;font.pixelSize:fsLbl;color:textMuted}
                                        Text{anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter} text:modelData.value;font.pixelSize:fsVal;color:valueBlue}
                                        HDivider{anchors.bottom:parent.bottom;width:parent.width;visible:index<6}
                                    }
                                }
                            }
                        }
                    }
                } // Draws/Solver sub-tab
            } // Worksheet tab

            // ==================================================
            //  PERFORMANCE TAB
            // ==================================================
            Item {
                anchors.fill: parent
                visible: root.activeTab === "Performance"
                property real halfW: (width - 6) / 2

                CompactFrame {
                    id: perfSolveCard2
                    x:0; y:0; width:parent.halfW
                    height: perfSolveHdr.height + 3*rowH + 1
                    SectionHeader{id:perfSolveHdr;width:parent.width;text:"Solve Summary"}
                    Column{anchors{left:parent.left;right:parent.right;top:perfSolveHdr.bottom}
                        Repeater{model:[
                            {label:"Solve Status",value:solveStatus()},
                            {label:"Elapsed Time",value:appState?fmtMs(appState.solveElapsedMs):"—"},
                            {label:"Specs Dirty",value:appState?(appState.specsDirty?"Yes":"No"):"—"}
                        ]
                        delegate:Item{width:parent.width;height:rowH
                            Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:modelData.label;font.pixelSize:fsLbl;color:textMuted}
                            Text{anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter} text:modelData.value;font.pixelSize:fsVal;color:valueBlue}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width;visible:index<2}
                        }}
                    }
                }
                CompactFrame {
                    x:0; y:perfSolveCard2.height+4; width:parent.halfW
                    height:energyHdr.height+3*rowH+1
                    SectionHeader{id:energyHdr;width:parent.width;text:"Energy Summary"}
                    Column{anchors{left:parent.left;right:parent.right;top:energyHdr.bottom}
                        Repeater{model:[
                            {label:"Condenser Duty",value:appState?(Math.round(appState.qcCalcKW)+" kW"):"—"},
                            {label:"Reboiler Duty", value:appState?(Math.round(appState.qrCalcKW)+" kW"):"—"},
                            {label:"Net Duty",      value:appState?(Math.round(appState.qrCalcKW-Math.abs(appState.qcCalcKW))+" kW"):"—"}
                        ]
                        delegate:Item{width:parent.width;height:rowH
                            Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:160;text:modelData.label;font.pixelSize:fsLbl;color:textMuted}
                            Text{anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter} text:modelData.value;font.pixelSize:fsVal;color:valueBlue}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width;visible:index<2}
                        }}
                    }
                }
                CompactFrame {
                    x:parent.halfW+6; y:0; width:parent.halfW
                    height:topBotHdr.height+4*rowH+1
                    SectionHeader{id:topBotHdr;width:parent.width;text:"Top / Bottom Conditions"}
                    Column{anchors{left:parent.left;right:parent.right;top:topBotHdr.bottom}
                        Repeater{model:[
                            {label:"Overhead Temperature",value:appState?(fmt3(appState.tColdK)+" K"):"—"},
                            {label:"Bottoms Temperature", value:appState?(fmt3(appState.tHotK)+" K"):"—"},
                            {label:"Reflux Fraction",     value:appState?(fmt3(appState.refluxFraction*100)+"%"):"—"},
                            {label:"Boilup Fraction",     value:appState?(fmt3(appState.boilupFraction*100)+"%"):"—"}
                        ]
                        delegate:Item{width:parent.width;height:rowH
                            Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                            Text{x:6;anchors.verticalCenter:parent.verticalCenter;width:170;text:modelData.label;font.pixelSize:fsLbl;color:textMuted}
                            Text{anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter} text:modelData.value;font.pixelSize:fsVal;color:valueBlue}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width;visible:index<3}
                        }}
                    }
                }
                CompactFrame {
                    x:parent.halfW+6; y:topBotHdr.parent.height>0?topBotHdr.parent.height+4:140; width:parent.halfW
                    height:parent.height-y
                    SectionHeader{id:warnHdr;width:parent.width;text:"Solver Warnings"}
                    ListView{
                        anchors{left:parent.left;right:parent.right;top:warnHdr.bottom;bottom:parent.bottom;margins:0;leftMargin:8;rightMargin:8}
                        clip:true; model:appState?appState.diagnosticsModel:null
                        delegate:Item{width:parent?parent.width:0;height:rowH
                            Row{anchors{left:parent.left;right:parent.right;verticalCenter:parent.verticalCenter} spacing:6
                                Rectangle{width:8;height:8;radius:2;color:warnAmber;anchors.verticalCenter:parent.verticalCenter}
                                Text{text:model.message||"";color:textMain;font.pixelSize:fsLbl;wrapMode:Text.Wrap;width:parent.width-20}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}}
                        Text{anchors.centerIn:parent;visible:!appState||!appState.diagnosticsModel||appState.diagnosticsModel.rowCount()===0
                             text:"No warnings";color:textMuted;font.pixelSize:fsLbl;font.italic:true}
                    }
                }
            }

            // ==================================================
            //  PROFILES TAB
            // ==================================================
            Item {
                anchors.fill: parent
                visible: root.activeTab === "Profiles"

                Rectangle {
                    id: profSubBar
                    x:0; y:0; width:parent.width; height:32
                    color:cmdBar; border.color:borderIn; border.width:1
                    Common.ClassicTabs {
                        id: profileModeTabs
                        x: 6; y: 3
                        tabs: [
                            { text: "Tray Table",      width: 86 },
                            { text: "Visual Profiles", width: 106 },
                            { text: "Compositions",    width: 106 }
                        ]
                        currentIndex: root.profilesSubTab === "Visual Profiles" ? 1 : (root.profilesSubTab === "Compositions" ? 2 : 0)
                        onTabClicked: function(index) {
                            if (index === 1) root.profilesSubTab = "Visual Profiles"
                            else if (index === 2) root.profilesSubTab = "Compositions"
                            else root.profilesSubTab = "Tray Table"
                        }
                    }
                }

                // Tray Table
                Item {
                    visible: root.profilesSubTab === "Tray Table"
                    anchors{left:parent.left;right:parent.right;top:profSubBar.bottom;topMargin:4;bottom:parent.bottom}

                    CompactFrame {
                        anchors.fill: parent

                        SectionHeader{id:trayTableHdr;width:parent.width;text:"Tray Profiles"}

                        // Legend
                        Row {
                            anchors{right:parent.right;rightMargin:10;top:parent.top;topMargin:4} spacing:8
                            Rectangle{width:16;height:8;radius:2;color:"#67b0ff";anchors.verticalCenter:parent.verticalCenter}
                            Text{text:"Vapor (V*)";font.pixelSize:fsSm;color:textMuted;anchors.verticalCenter:parent.verticalCenter}
                            Rectangle{width:16;height:8;radius:2;color:"#294f8f";anchors.verticalCenter:parent.verticalCenter}
                            Text{text:"Liquid (1−V*)";font.pixelSize:fsSm;color:textMuted;anchors.verticalCenter:parent.verticalCenter}
                        }

                        // Header row
                        Item {
                            id: trayTblHdr
                            anchors{left:parent.left;right:parent.right;top:trayTableHdr.bottom} height:rowH
                            property var hdrs:  ["Tray","Temp (K)","Pressure (Pa)","Vap.Frac","Liq. Flow","Vap. Flow","Draw","V* / L*"]
                            property var colWs: [50,    100,       110,            80,        100,        100,        120,   150]
                            Row{anchors{left:parent.left;right:parent.right;leftMargin:8}
                                Repeater{model:trayTblHdr.hdrs.length
                                    delegate:Text{width:trayTblHdr.colWs[index];text:trayTblHdr.hdrs[index]
                                        font.pixelSize:fsSm;font.bold:true;color:textMain
                                        horizontalAlignment:index>0?Text.AlignRight:Text.AlignLeft
                                        height:rowH;verticalAlignment:Text.AlignVCenter}}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }

                        ListView {
                            anchors{left:parent.left;right:parent.right;top:trayTblHdr.bottom;bottom:parent.bottom}
                            clip:true; verticalLayoutDirection:ListView.BottomToTop
                            model:appState?appState.trayModel:null
                            delegate:Item{
                                width:parent?parent.width:0; height:rowH
                                property var colWs:[50,100,110,80,100,100,120]
                                property real vf:Math.max(0,Math.min(1,model.vaporFrac||0))
                                Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                                Row{anchors{left:parent.left;right:trayBarItem.left;rightMargin:8;leftMargin:8} height:parent.height
                                    Text{width:colWs[0];text:model.trayNumber||"—";font.pixelSize:fsVal;color:textMain;height:parent.height;verticalAlignment:Text.AlignVCenter}
                                    Text{width:colWs[1];text:fmt3(model.tempK);font.pixelSize:fsVal;color:valueBlue;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                    Text{width:colWs[2];text:{if(!appState)return"—";var tN=model.trayNumber;return String(Math.round(appState.topPressurePa+appState.dpPerTrayPa*(appState.trays-tN)))}
                                        font.pixelSize:fsVal;color:valueBlue;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                    Text{width:colWs[3];text:fmt3(model.vaporFrac);font.pixelSize:fsVal;color:valueBlue;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                    Text{width:colWs[4];text:Math.round(model.liquidFlow)+"";font.pixelSize:fsVal;color:valueBlue;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                    Text{width:colWs[5];text:Math.round(model.vaporFlow)+"";font.pixelSize:fsVal;color:valueBlue;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                    Text{width:colWs[6];text:model.drawLabel||"";font.pixelSize:fsSm;color:warnAmber;height:parent.height;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight;elide:Text.ElideRight}
                                }
                                Item{id:trayBarItem;anchors{right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter} width:140;height:parent.height
                                    Rectangle{anchors.verticalCenter:parent.verticalCenter;anchors.left:parent.left;anchors.right:parent.right;height:8;radius:4;color:"#294f8f"
                                        Rectangle{anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;width:parent.width*vf;radius:4;color:"#67b0ff"}}}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width}
                            }
                            Text{anchors.centerIn:parent;visible:!appState||!appState.trayModel||appState.trayModel.rowCount()===0
                                 text:"Run solver to populate tray table";color:textMuted;font.pixelSize:fsLbl;font.italic:true}
                        }
                    }
                }

                // Visual Profiles
                Item {
                    id: visualProfilesItem
                    visible: root.profilesSubTab === "Visual Profiles"
                    anchors{left:parent.left;right:parent.right;top:profSubBar.bottom;topMargin:4;bottom:parent.bottom}

                    property var profileDefs:[
                        {key:"tempK",     label:"Temperature",    unit:"K",    color:"#2e73b8"},
                        {key:"pressure",  label:"Pressure",       unit:"Pa",   color:"#7c3aed"},
                        {key:"vaporFrac", label:"Vapour Fraction",unit:"—",    color:"#0891b2"},
                        {key:"liquidFlow",label:"Liquid Flow",    unit:"kg/h", color:"#059669"},
                        {key:"vaporFlow", label:"Vapour Flow",    unit:"kg/h", color:"#d97706"}
                    ]
                    property int profileIndex: 0
                    property var activeDef: profileDefs[profileIndex]

                    Common.ClassicTabs {
                        id: profSelRow
                        x: 0; y: 0
                        tabs: visualProfilesItem.profileDefs.map(function(def) {
                            return { text: def.label, width: def.label === "Vapour Fraction" ? 126 : 106 }
                        })
                        currentIndex: visualProfilesItem.profileIndex
                        onTabClicked: function(index) {
                            visualProfilesItem.profileIndex = index
                            profileCanvas2.requestPaint()
                        }
                    }

                    CompactFrame {
                        anchors{left:parent.left;right:parent.right;top:profSelRow.bottom;topMargin:4;bottom:parent.bottom}

                        readonly property int lm:46; readonly property int rm:16; readonly property int tm:14; readonly property int bm:56

                        Canvas {
                            id: profileCanvas2
                            anchors.fill: parent
                            property var trayModel: appState?appState.trayModel:null
                            property var def: visualProfilesItem.activeDef
                            Connections{target:profileCanvas2.trayModel;function onDataChanged(){profileCanvas2.requestPaint()} ignoreUnknownSignals:true}
                            onDefChanged: requestPaint()
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var par=parent
                                var lm=par.lm,rm=par.rm,tm=par.tm,bm=par.bm
                                var cw=width-lm-rm,ch=height-tm-bm
                                ctx.fillStyle="#ffffff"; ctx.fillRect(lm,tm,cw,ch)
                                ctx.strokeStyle="#2a2a2a"; ctx.lineWidth=1; ctx.strokeRect(lm,tm,cw,ch)
                                var model=profileCanvas2.trayModel; var pdef=profileCanvas2.def
                                if(!model||model.rowCount()===0||!pdef){ctx.fillStyle="#9ba8bf";ctx.font="13px sans-serif";ctx.textAlign="center";ctx.fillText("No data – run solver",lm+cw/2,tm+ch/2);return}
                                var pts=[]; var nTrays=appState?appState.trays:0; var p0=appState?appState.topPressurePa:0; var dp=appState?appState.dpPerTrayPa:0
                                for(var r=0;r<model.rowCount();r++){var row=model.get(r);var xVal=pdef.key==="pressure"?(p0+dp*(nTrays-row.trayNumber)):row[pdef.key];pts.push({tray:row.trayNumber,x:Number(xVal||0)})}
                                pts.sort(function(a,b){return a.tray-b.tray})
                                if(pts.length===0)return
                                var minTray=pts[0].tray,maxTray=pts[pts.length-1].tray,minX=pts[0].x,maxX=pts[0].x
                                for(var k=1;k<pts.length;k++){if(pts[k].x<minX)minX=pts[k].x;if(pts[k].x>maxX)maxX=pts[k].x}
                                var xPad=(maxX-minX)*0.06||Math.abs(maxX)*0.05||1,xLo=minX-xPad,xHi=maxX+xPad,rngX=xHi-xLo||1,rngTray=(maxTray-minTray)||1
                                var nGX=6,nGY=Math.min(pts.length,10)
                                ctx.strokeStyle="#dde4f0";ctx.lineWidth=1;ctx.setLineDash([3,3])
                                for(var gi=0;gi<=nGX;gi++){var gx=lm+gi*(cw/nGX);ctx.beginPath();ctx.moveTo(gx,tm);ctx.lineTo(gx,tm+ch);ctx.stroke()}
                                for(var gj=0;gj<=nGY;gj++){var gy=tm+ch-gj*(ch/nGY);ctx.beginPath();ctx.moveTo(lm,gy);ctx.lineTo(lm+cw,gy);ctx.stroke()}
                                ctx.setLineDash([])
                                ctx.fillStyle="#5a6472";ctx.font="10px sans-serif";ctx.textAlign="right"
                                var step=Math.max(1,Math.round(pts.length/nGY))
                                for(var yi=0;yi<pts.length;yi+=step){var yp=tm+ch-(pts[yi].tray-minTray)/rngTray*ch;ctx.fillText(pts[yi].tray,lm-4,yp+4)}
                                ctx.save();ctx.fillStyle="#1f2430";ctx.font="bold 11px sans-serif";ctx.textAlign="center";ctx.translate(13,tm+ch/2);ctx.rotate(-Math.PI/2);ctx.fillText("Tray Number (1 = Bottoms)",0,0);ctx.restore()
                                ctx.fillStyle="#5a6472";ctx.font="10px sans-serif";ctx.textAlign="center"
                                for(var xi=0;xi<=nGX;xi++){var xv=xLo+xi*rngX/nGX;var xp=lm+xi*(cw/nGX);var xStr=Math.abs(xv)>=10000?xv.toExponential(2):Math.abs(xv)>=100?xv.toFixed(0):Math.abs(xv)>=1?xv.toFixed(2):xv.toFixed(4);ctx.fillText(xStr,xp,tm+ch+14)}
                                ctx.fillStyle="#1f2430";ctx.font="bold 11px sans-serif";ctx.textAlign="center";ctx.fillText(pdef.label+" ("+pdef.unit+")",lm+cw/2,tm+ch+44)
                                ctx.strokeStyle=pdef.color;ctx.lineWidth=2;ctx.beginPath()
                                for(var p=0;p<pts.length;p++){var px=lm+(pts[p].x-xLo)/rngX*cw;var py=tm+ch-(pts[p].tray-minTray)/rngTray*ch;if(p===0)ctx.moveTo(px,py);else ctx.lineTo(px,py)}
                                ctx.stroke()
                                ctx.fillStyle=pdef.color
                                for(var d=0;d<pts.length;d++){var dpx=lm+(pts[d].x-xLo)/rngX*cw;var dpy=tm+ch-(pts[d].tray-minTray)/rngTray*ch;ctx.beginPath();ctx.arc(dpx,dpy,3.5,0,2*Math.PI);ctx.fill()}
                            }
                        }
                    }
                }

                // ── Compositions Sub-tab ──────────────────────────────────
                Item {
                    id: compositionsItem
                    visible: root.profilesSubTab === "Compositions"
                    anchors{left:parent.left;right:parent.right;top:profSubBar.bottom;topMargin:4;bottom:parent.bottom}

                    property var  compNames:    appState ? appState.componentNames : []
                    property int  compCount:    compNames.length
                    property int  selectedComp: 0
                    property bool showVapor:    false

                    // ── Top: Composition Table ────────────────────────────
                    CompactFrame {
                        id: compTableFrame
                        anchors{left:parent.left;right:parent.right;top:parent.top;bottom:compChartFrame.top;bottomMargin:4}

                        SectionHeader { id: compTblHdr; width:parent.width; text:"Tray Compositions  (mole fractions)" }

                        // Component selector row — same ComboBox drives both table and chart
                        Item {
                            id: compTblControls
                            anchors{left:parent.left;right:parent.right;top:compTblHdr.bottom}
                            height: 26
                            Text {
                                id: tblCompLbl
                                anchors{left:parent.left;leftMargin:8;verticalCenter:parent.verticalCenter}
                                text:"Component:"; font.pixelSize:fsLbl; color:textMuted
                            }
                            ComboBox {
                                id: tblCompSelector
                                anchors{left:tblCompLbl.right;leftMargin:6;verticalCenter:parent.verticalCenter}
                                width:160; implicitHeight:rowH-2
                                font.pixelSize:fsVal
                                model: compositionsItem.compNames
                                currentIndex: compositionsItem.selectedComp
                                onActivated: {
                                    compositionsItem.selectedComp = currentIndex
                                    // keep chart selector in sync
                                    if (compSelector.currentIndex !== currentIndex)
                                        compSelector.currentIndex = currentIndex
                                    compChartCanvas.requestPaint()
                                }
                                onModelChanged: { currentIndex = 0 }
                                background: Rectangle { color:inputBg; border.color:borderIn; border.width:1 }
                                contentItem: Text {
                                    leftPadding:4; text:parent.displayText
                                    font.pixelSize:fsVal; color:valueBlue
                                    verticalAlignment:Text.AlignVCenter; elide:Text.ElideRight
                                }
                            }
                            Text {
                                anchors{left:tblCompSelector.right;leftMargin:16;verticalCenter:parent.verticalCenter}
                                text: {
                                    var n = compositionsItem.compNames
                                    return n.length > 0 ? (n.length + " components in system") : ""
                                }
                                font.pixelSize:fsSm; color:textMuted; font.italic:true
                            }
                            HDivider { anchors.bottom:parent.bottom; width:parent.width }
                        }

                        // Fixed 3-column header: Tray | x (liquid) | y (vapor)
                        Item {
                            id: compHdrRow
                            anchors{left:parent.left;right:parent.right;top:compTblControls.bottom}
                            height: rowH
                            property real col0: 60   // Tray
                            property real col1: 160  // x liquid
                            property real col2: 160  // y vapor
                            Row {
                                anchors{left:parent.left;right:parent.right;leftMargin:8}
                                Text { width:compHdrRow.col0; text:"Tray"; font.bold:true; font.pixelSize:fsSm; color:textMain; height:rowH; verticalAlignment:Text.AlignVCenter }
                                Text { width:compHdrRow.col1; text:"x  (liquid mol frac)"; font.bold:true; font.pixelSize:fsSm; color:"#1e6fb5"; height:rowH; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                                Text { width:compHdrRow.col2; text:"y  (vapor mol frac)"; font.bold:true; font.pixelSize:fsSm; color:"#b45309"; height:rowH; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight }
                            }
                            HDivider { anchors.bottom:parent.bottom; width:parent.width }
                        }

                        ListView {
                            anchors{left:parent.left;right:parent.right;top:compHdrRow.bottom;bottom:parent.bottom}
                            clip:true
                            verticalLayoutDirection: ListView.BottomToTop
                            model: appState ? appState.trayModel : null

                            delegate: Item {
                                width: parent ? parent.width : 0
                                height: rowH
                                property var xArr: model.xLiq || []
                                property var yArr: model.yVap || []
                                property int ci:   compositionsItem.selectedComp

                                Rectangle { anchors.fill:parent; color:index%2===0?rowEven:rowOdd }
                                Row {
                                    anchors{left:parent.left;right:parent.right;leftMargin:8}
                                    height: parent.height
                                    Text {
                                        width:compHdrRow.col0; text:model.trayNumber||"—"
                                        font.pixelSize:fsVal; color:textMain
                                        height:parent.height; verticalAlignment:Text.AlignVCenter
                                    }
                                    Text {
                                        width:compHdrRow.col1
                                        text: { var v=xArr[ci]; return (v!==undefined&&v!==null)?Number(v).toFixed(6):"—" }
                                        font.pixelSize:fsVal; color:"#1e6fb5"
                                        height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                                    }
                                    Text {
                                        width:compHdrRow.col2
                                        text: { var v=yArr[ci]; return (v!==undefined&&v!==null)?Number(v).toFixed(6):"—" }
                                        font.pixelSize:fsVal; color:"#b45309"
                                        height:parent.height; verticalAlignment:Text.AlignVCenter; horizontalAlignment:Text.AlignRight
                                    }
                                }
                                HDivider { anchors.bottom:parent.bottom; width:parent.width }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !appState || !appState.trayModel || appState.trayModel.rowCount() === 0
                                text: "Run solver to populate composition table"
                                color:textMuted; font.pixelSize:fsLbl; font.italic:true
                            }
                        }
                    }

                    // ── Bottom: Composition Chart ─────────────────────────
                    CompactFrame {
                        id: compChartFrame
                        anchors{left:parent.left;right:parent.right;bottom:parent.bottom}
                        height: Math.round(parent.height * 0.50)

                        SectionHeader { id: compChartHdr; width:parent.width; text:"Composition Profile" }

                        // Controls row: Component dropdown + Liquid/Vapor toggle
                        Item {
                            id: compChartControls
                            anchors{left:parent.left;right:parent.right;top:compChartHdr.bottom}
                            height: 28

                            Text {
                                id: compDropLbl
                                anchors{left:parent.left;leftMargin:8;verticalCenter:parent.verticalCenter}
                                text: "Component:"; font.pixelSize:fsLbl; color:textMuted
                            }

                            ComboBox {
                                id: compSelector
                                anchors{left:compDropLbl.right;leftMargin:6;verticalCenter:parent.verticalCenter}
                                width: 160; implicitHeight: rowH - 2
                                font.pixelSize: fsVal
                                model: compositionsItem.compNames
                                currentIndex: compositionsItem.selectedComp
                                onActivated: {
                                    compositionsItem.selectedComp = currentIndex
                                    compChartCanvas.requestPaint()
                                }
                                background: Rectangle { color: inputBg; border.color: borderIn; border.width: 1 }
                                contentItem: Text {
                                    leftPadding: 4; text: parent.displayText
                                    font.pixelSize: fsVal; color: valueBlue
                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                }
                                // Reset to index 0 when component list changes after a new solve
                                onModelChanged: {
                                    currentIndex = 0
                                    compositionsItem.selectedComp = 0
                                    compChartCanvas.requestPaint()
                                }
                            }

                            // Liquid / Vapor toggle
                            Row {
                                anchors{left:compSelector.right;leftMargin:16;verticalCenter:parent.verticalCenter}
                                spacing: 4

                                Repeater {
                                    model: ["Liquid (x)", "Vapor (y)"]
                                    delegate: Rectangle {
                                        width: 76; height: 20; radius: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: (compositionsItem.showVapor === (index===1))
                                               ? (index===1 ? "#b45309" : "#1e6fb5")
                                               : "#d4dce8"
                                        Text {
                                            anchors.centerIn: parent; text: modelData
                                            font.pixelSize: fsSm; font.bold: true
                                            color: (compositionsItem.showVapor === (index===1)) ? "white" : "#334"
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                compositionsItem.showVapor = (index === 1)
                                                compChartCanvas.requestPaint()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Canvas {
                            id: compChartCanvas
                            anchors{left:parent.left;right:parent.right;top:compChartControls.bottom;topMargin:2;bottom:parent.bottom}
                            property var trayModel: appState ? appState.trayModel : null

                            Connections { target: compChartCanvas.trayModel; function onDataChanged(){ compChartCanvas.requestPaint() } ignoreUnknownSignals:true }
                            Connections { target: appState; function onComponentNamesChanged(){ compSelector.currentIndex=0; compositionsItem.selectedComp=0; compChartCanvas.requestPaint() } ignoreUnknownSignals:true }
                            onVisibleChanged: if(visible) requestPaint()

                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var lm=52, rm=20, tm=14, bm=46
                                var cw=width-lm-rm, ch=height-tm-bm
                                if(cw<10||ch<10) return
                                ctx.fillStyle="#ffffff"; ctx.fillRect(lm,tm,cw,ch)
                                ctx.strokeStyle="#2a2a2a"; ctx.lineWidth=1; ctx.strokeRect(lm,tm,cw,ch)

                                var model=compChartCanvas.trayModel
                                var compIdx=compositionsItem.selectedComp
                                var vapor=compositionsItem.showVapor
                                var compNames=compositionsItem.compNames
                                var compName=compIdx<compNames.length?compNames[compIdx]:"?"

                                if(!model||model.rowCount()===0||compNames.length===0){
                                    ctx.fillStyle="#9ba8bf";ctx.font="13px sans-serif";ctx.textAlign="center"
                                    ctx.fillText("No data – run solver",lm+cw/2,tm+ch/2);return
                                }

                                var pts=[]
                                for(var r=0;r<model.rowCount();r++){
                                    var row=model.get(r)
                                    var arr=vapor?row.yVap:row.xLiq
                                    if(!arr||compIdx>=arr.length) continue
                                    var v=Number(arr[compIdx])
                                    if(!isFinite(v)) continue
                                    pts.push({tray:row.trayNumber,v:v})
                                }
                                pts.sort(function(a,b){return a.tray-b.tray})
                                if(pts.length===0){
                                    ctx.fillStyle="#9ba8bf";ctx.font="13px sans-serif";ctx.textAlign="center"
                                    ctx.fillText("No composition data",lm+cw/2,tm+ch/2);return
                                }

                                var minTray=pts[0].tray, maxTray=pts[pts.length-1].tray
                                var rngTray=Math.max(1,maxTray-minTray)

                                // Grid
                                ctx.strokeStyle="#dde4f0";ctx.lineWidth=0.7;ctx.setLineDash([3,3])
                                for(var gi=0;gi<=5;gi++){var gx=lm+gi*(cw/5);ctx.beginPath();ctx.moveTo(gx,tm);ctx.lineTo(gx,tm+ch);ctx.stroke()}
                                for(var gj=0;gj<=5;gj++){var gy=tm+gj*(ch/5);ctx.beginPath();ctx.moveTo(lm,gy);ctx.lineTo(lm+cw,gy);ctx.stroke()}
                                ctx.setLineDash([])

                                // X-axis labels (mole fraction 0..1)
                                ctx.fillStyle="#5a6472";ctx.font="9px sans-serif";ctx.textAlign="center"
                                for(var xi=0;xi<=5;xi++){ctx.fillText((xi/5).toFixed(2),lm+xi*(cw/5),tm+ch+12)}

                                // Y-axis labels (tray number)
                                ctx.textAlign="right"
                                var step=Math.max(1,Math.round(pts.length/8))
                                for(var yi=0;yi<pts.length;yi+=step){
                                    var yp=tm+ch-(pts[yi].tray-minTray)/rngTray*ch
                                    ctx.fillText(pts[yi].tray,lm-4,yp+4)
                                }

                                // Axis labels
                                ctx.save();ctx.fillStyle="#1f2430";ctx.font="bold 10px sans-serif"
                                ctx.textAlign="center";ctx.translate(14,tm+ch/2);ctx.rotate(-Math.PI/2)
                                ctx.fillText("Tray  (1 = Bottoms)",0,0);ctx.restore()

                                ctx.fillStyle="#1f2430";ctx.font="bold 10px sans-serif";ctx.textAlign="center"
                                ctx.fillText(compName+"  —  "+(vapor?"Vapor mole fraction  y":"Liquid mole fraction  x"),lm+cw/2,tm+ch+34)

                                // Plot line
                                var lineColor=vapor?"#b45309":"#1e6fb5"
                                ctx.strokeStyle=lineColor;ctx.lineWidth=2;ctx.beginPath()
                                for(var p=0;p<pts.length;p++){
                                    var px=lm+pts[p].v*cw
                                    var py=tm+ch-(pts[p].tray-minTray)/rngTray*ch
                                    if(p===0)ctx.moveTo(px,py);else ctx.lineTo(px,py)
                                }
                                ctx.stroke()

                                // Dots
                                ctx.fillStyle=lineColor
                                for(var d=0;d<pts.length;d++){
                                    var dpx=lm+pts[d].v*cw
                                    var dpy=tm+ch-(pts[d].tray-minTray)/rngTray*ch
                                    ctx.beginPath();ctx.arc(dpx,dpy,3.5,0,2*Math.PI);ctx.fill()
                                }

                                // Feed tray dashed marker
                                if(appState&&appState.feedTray){
                                    var ft=appState.feedTray
                                    if(ft>=minTray&&ft<=maxTray){
                                        var fy=tm+ch-(ft-minTray)/rngTray*ch
                                        ctx.strokeStyle="#d4720a";ctx.lineWidth=1.5;ctx.setLineDash([4,3])
                                        ctx.beginPath();ctx.moveTo(lm,fy);ctx.lineTo(lm+cw,fy);ctx.stroke()
                                        ctx.setLineDash([])
                                        ctx.fillStyle="#d4720a";ctx.font="9px sans-serif";ctx.textAlign="left"
                                        ctx.fillText("Feed tray "+ft,lm+3,fy-3)
                                    }
                                }
                            }
                        }
                    }
                }

            }

            //  PRODUCTS TAB
            // ==================================================
            Item {
                id: productsTab
                anchors.fill: parent
                visible: root.activeTab === "Products"
                onVisibleChanged: if (visible && prodFrame) prodFrame.rebuildProdMbSorted()

                CompactFrame {
                    id: prodFrame
                    anchors.fill: parent

                    SectionHeader { id: prodHdr; width: parent.width; text: "Material Balance" }

                    Item {
                        id: prodMbHdr2
                        anchors{left:parent.left;right:parent.right;top:prodHdr.bottom}  height:rowH
                        Row{anchors{left:parent.left;right:parent.right;leftMargin:8}
                            Text{width:parent.width*0.55;text:"Product";    font.bold:true;font.pixelSize:fsLbl;color:textMain;height:rowH;verticalAlignment:Text.AlignVCenter}
                            Text{width:parent.width*0.25;text:"Flow (kg/h)";font.bold:true;font.pixelSize:fsLbl;color:textMain;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                            Text{width:parent.width*0.16;text:"Feed %";     font.bold:true;font.pixelSize:fsLbl;color:textMain;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                        }
                        HDivider{anchors.bottom:parent.bottom;width:parent.width}
                    }

                    property var prodMbSorted: []
                    function rebuildProdMbSorted() {
                        var mbm=appState?appState.materialBalanceModel:null
                        if(!mbm||!appState||!appState.solved){prodMbSorted=[];return}
                        var n=mbm.rowCount(),rows=[]
                        for(var i=0;i<n;i++){
                            var idx=mbm.index(i,0),nm=mbm.data(idx,257)||"",kg=mbm.data(idx,258)||0,fr=mbm.data(idx,259)||0
                            var nmL=nm.toLowerCase(),sortKey=0
                            if(nmL.indexOf("distillate")>=0||nmL.indexOf("overhead")>=0)sortKey=99999
                            else if(nmL.indexOf("bottoms")>=0||nmL.indexOf("residue")>=0)sortKey=-1
                            else{var parts=nm.match(/Tray\s*(\d+)/i);sortKey=parts?parseInt(parts[1]):0}
                            rows.push({name:nm,kgph:kg,frac:fr,sortKey:sortKey})
                        }
                        rows.sort(function(a,b){return b.sortKey-a.sortKey})
                        prodMbSorted=rows
                    }
                    Component.onCompleted: rebuildProdMbSorted()

                    Connections{
                        target: appState ? appState.materialBalanceModel : null
                        function onTotalsChanged(){ prodFrame.rebuildProdMbSorted() }
                        function onModelReset(){ prodFrame.rebuildProdMbSorted() }
                        function onRowsInserted(){ prodFrame.rebuildProdMbSorted() }
                        function onRowsRemoved(){ prodFrame.rebuildProdMbSorted() }
                        function onDataChanged(){ prodFrame.rebuildProdMbSorted() }
                        ignoreUnknownSignals: true
                    }
                    Connections{
                        target: appState
                        function onSolvedChanged(){ prodFrame.rebuildProdMbSorted() }
                        ignoreUnknownSignals: true
                    }
                    Connections{
                        target: root
                        function onActiveTabChanged(){ if(root.activeTab === "Products") prodFrame.rebuildProdMbSorted() }
                        ignoreUnknownSignals: true
                    }

                    ListView {
                        anchors{left:parent.left;right:parent.right;top:prodMbHdr2.bottom;bottom:prodTotals.top}
                        clip:true; model:prodFrame.prodMbSorted
                        delegate:Item{width:parent?parent.width:0;height:rowH
                            Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                            Row{anchors{left:parent.left;right:parent.right;leftMargin:8}
                                Text{width:parent.width*0.55;text:modelData.name||"—";font.pixelSize:fsVal;color:textMain;height:rowH;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight}
                                Text{width:parent.width*0.25;text:Math.round(modelData.kgph||0)+"";font.pixelSize:fsVal;color:valueBlue;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                Text{width:parent.width*0.16;text:fmt2((modelData.frac||0)*100)+"%";font.pixelSize:fsVal;color:valueBlue;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                            }
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        Text{anchors.centerIn:parent;visible:!appState||!appState.solved;text:"Run solver to see material balance";color:textMuted;font.pixelSize:fsLbl;font.italic:true}
                    }

                    Item {
                        id: prodTotals
                        anchors{left:parent.left;right:parent.right;bottom:parent.bottom} height:rowH*2+1
                        visible:appState&&appState.solved
                        HDivider{anchors.top:parent.top;width:parent.width}
                        Item{anchors{left:parent.left;right:parent.right;top:parent.top} height:rowH
                            Rectangle{anchors.fill:parent;color:hdrBg}
                            Row{anchors{left:parent.left;right:parent.right;leftMargin:8}
                                Text{width:parent.width*0.55;text:"Total Products";font.bold:true;font.pixelSize:fsLbl;color:textMain;height:rowH;verticalAlignment:Text.AlignVCenter}
                                Text{width:parent.width*0.25;text:appState&&appState.materialBalanceModel?Math.round(appState.materialBalanceModel.totalProductsKgph)+"":"—";font.bold:true;font.pixelSize:fsLbl;color:valueBlue;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                Text{width:parent.width*0.16;text:appState&&appState.materialBalanceModel?fmt2(appState.materialBalanceModel.totalFrac*100)+"%":"—";font.bold:true;font.pixelSize:fsLbl;color:valueBlue;height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                            }
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        Item{anchors{left:parent.left;right:parent.right;bottom:parent.bottom} height:rowH
                            Row{anchors{left:parent.left;right:parent.right;leftMargin:8}
                                Text{width:parent.width*0.55;text:"Balance Error";font.pixelSize:fsLbl;color:textMuted;height:rowH;verticalAlignment:Text.AlignVCenter}
                                Text{width:parent.width*0.25
                                    property double errKgph:appState&&appState.materialBalanceModel?appState.materialBalanceModel.balanceErrKgph:0
                                    text:fmt2(Math.abs(errKgph))+" kg/h";font.pixelSize:fsLbl
                                    color:Math.abs(errKgph)>100?errorRed:(Math.abs(errKgph)>10?warnAmber:"#1a7a3c")
                                    height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                                Text{width:parent.width*0.16
                                    property double feedK:appState&&appState.materialBalanceModel?appState.materialBalanceModel.feedKgph:1
                                    property double errK:appState&&appState.materialBalanceModel?appState.materialBalanceModel.balanceErrKgph:0
                                    property double errPct:(feedK>0)?Math.abs(errK)/feedK*100:0
                                    text:fmt2(errPct)+"%";font.pixelSize:fsLbl
                                    color:errPct>1.0?errorRed:(errPct>0.1?warnAmber:"#1a7a3c")
                                    height:rowH;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignRight}
                            }
                        }
                    }
                }
            }

            // ==================================================
            //  RUN LOG TAB
            // ==================================================
            Item {
                anchors.fill: parent
                visible: root.activeTab === "Run Log"

                CompactFrame {
                    anchors.fill: parent
                    SectionHeader{id:runLogHdr;width:parent.width;text:"Run Log"}
                    ScrollView {
                        anchors{left:parent.left;right:parent.right;top:runLogHdr.bottom;bottom:parent.bottom;leftMargin:6;rightMargin:6}
                        clip:true; ScrollBar.vertical.policy:ScrollBar.AsNeeded
                        ListView {
                            id:runLogList2; model:appState?appState.runLogModel:null; spacing:0
                            delegate:Item{width:runLogList2.width;height:rowH
                                Text{x:4;anchors.verticalCenter:parent.verticalCenter;text:model.text||"";font.pixelSize:fsVal;color:textMain;font.family:"Monospace"}
                                HDivider{anchors.bottom:parent.bottom;width:parent.width;color:"#d0d8e8"}
                            }
                            onCountChanged: Qt.callLater(function(){runLogList2.positionViewAtEnd()})
                            Text{anchors.centerIn:parent;visible:!appState||!appState.runLogModel||appState.runLogModel.rowCount()===0
                                 text:"No run log entries yet";color:textMuted;font.pixelSize:fsLbl;font.italic:true}
                        }
                    }
                }
            }

            // ==================================================
            //  DIAGNOSTICS TAB
            // ==================================================
            Item {
                anchors.fill: parent
                visible: root.activeTab === "Diagnostics"

                CompactFrame {
                    anchors.fill: parent
                    SectionHeader{id:diagHdr;width:parent.width;text:"Diagnostics"}
                    ListView {
                        anchors{left:parent.left;right:parent.right;top:diagHdr.bottom;bottom:parent.bottom;leftMargin:8;rightMargin:8}
                        clip:true; model:appState?appState.diagnosticsModel:null; spacing:4
                        delegate:Item{width:parent?parent.width:0;height:rowH
                            Rectangle{anchors.fill:parent;color:index%2===0?rowEven:rowOdd}
                            Row{anchors{left:parent.left;right:parent.right;leftMargin:4;verticalCenter:parent.verticalCenter} spacing:6
                                Rectangle{width:8;height:8;radius:2;color:model.level==="error"?errorRed:(model.level==="warn"?warnAmber:activeBlue);anchors.verticalCenter:parent.verticalCenter}
                                Text{text:model.message||"";font.pixelSize:fsLbl;color:textMain;wrapMode:Text.Wrap;width:parent.width-24}}
                            HDivider{anchors.bottom:parent.bottom;width:parent.width}
                        }
                        Text{anchors.centerIn:parent;visible:!appState||!appState.diagnosticsModel||appState.diagnosticsModel.rowCount()===0
                             text:"No diagnostics";color:textMuted;font.pixelSize:fsLbl;font.italic:true}
                    }
                }
            }

        } // content
    }
}
