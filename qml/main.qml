import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "style" as Style
import "pages" as Pages
import "components" as Comp

/* ═══════════════════════════════════════════════════════════
   PROBRAKE LC v4.1 — Control Panel  ·  Premium QML Edition
   Root application shell: Sidebar + Top bar + Page stack
   ═══════════════════════════════════════════════════════════ */
ApplicationWindow {
    id: appWindow
    visible: true
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 700
    title: "PROBRAKE LC  ·  Control Panel  ·  v4.1 Premium"
    color: Style.Theme.bg

    // ── Backend bridge (set from Python) ──────────────────
    property QtObject backend: null

    // ── Navigation state ─────────────────────────────────
    property string currentPage: "curves"
    property var navItems: [
        { key: "curves",  icon: "◈", label: "CURVES"  },
        { key: "feel",    icon: "◉", label: "FEEL"    },
        { key: "system",  icon: "◎", label: "SYSTEM"  },
        { key: "console", icon: "◐", label: "CONSOLE" }
    ]

    // ── Live telemetry state ─────────────────────────────
    property real brakeValue: backend ? backend.brakeValue : 0
    property real throttleValue: backend ? backend.throttleValue : 0
    property real clutchValue: backend ? backend.clutchValue : 0
    property string flagText: backend ? backend.flagText : "●  NOMINAL"
    property color flagColor: backend ? backend.flagColor : Style.Theme.green
    property string profileText: backend ? backend.profileText : "Profile  —"
    property string statusText: backend ? backend.statusText : "OFFLINE"
    property color statusColor: backend ? backend.statusColor : Style.Theme.td
    property bool connected: backend ? backend.connected : false
    property var portList: backend ? backend.portList : ["— SELECT PORT —"]
    property string selectedPort: portList.length > 0 ? portList[0] : "— SELECT PORT —"

    // ── Forward commands to backend ──────────────────────
    function sendCommand(cmd) {
        if (backend) backend.sendCommand(cmd);

        // Auto-persist GUI settings when saving to Arduino EEPROM
        if (cmd === "save" && serialBackend) serialBackend.saveAllSettings();

        // ── Trigger calibration overlay on min/max commands ──
        var calMatch = cmd.match(/^([btc])(min|max)$/);
        if (calMatch) {
            var prefix = calMatch[1];
            var action = calMatch[2].toUpperCase();
            var names  = {"b": "BRAKE", "t": "THROTTLE", "c": "CLUTCH"};
            var colors = {"b": Style.Theme.amber, "t": Style.Theme.green, "c": Style.Theme.cyan};
            calOverlay.start(names[prefix], action, colors[prefix]);
        }
    }

    // ── Console log forwarding ───────────────────────────
    Connections {
        target: backend
        function onLogMessage(text) {
            if (consolePage) consolePage.appendLog(text);
        }
    }

    // ═══════════════════════════════════════════════════════
    //  LAYOUT: Sidebar | Right (TopBar + Content)
    // ═══════════════════════════════════════════════════════
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ─── SIDEBAR ─────────────────────────────────────
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: 64
            color: Style.Theme.bg1

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Gold top accent
                Rectangle { Layout.fillWidth: true; height: 3; color: Style.Theme.gold }

                // PB monogram
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 14
                    width: 42; height: 42
                    radius: 6
                    color: Style.Theme.goldDim
                    border.width: 1
                    border.color: Style.Theme.goldD

                    Text {
                        anchors.centerIn: parent
                        text: "PB"
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 20, bold: true})
                        color: Style.Theme.goldL
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    text: "LC"
                    font: Qt.font({family: "Consolas", pixelSize: 13, bold: true})
                    color: Style.Theme.goldD
                }

                // Divider
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    Layout.bottomMargin: 4
                    width: 38; height: 1
                    color: Style.Theme.border2
                }

                // Nav buttons
                Repeater {
                    model: appWindow.navItems
                    delegate: Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 3
                        width: 52; height: 58

                        property bool isActive: appWindow.currentPage === modelData.key

                        Rectangle {
                            id: navBg
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 42; height: 42
                            radius: 8
                            color: parent.isActive
                                   ? Style.Theme.goldDim
                                   : navMouseArea.containsMouse ? Style.Theme.bg3 : "transparent"
                            border.width: parent.isActive ? 1 : (navMouseArea.containsMouse ? 1 : 0)
                            border.color: parent.isActive ? Style.Theme.goldD
                                        : navMouseArea.containsMouse ? Style.Theme.border2
                                        : "transparent"

                            Behavior on color { ColorAnimation { duration: Style.Theme.animFast } }
                            Behavior on border.color { ColorAnimation { duration: Style.Theme.animFast } }

                            // Hover glow underlay
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Style.Theme.gold
                                opacity: navMouseArea.containsMouse && !parent.parent.isActive ? 0.06 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            // Scale on hover
                            scale: navMouseArea.containsMouse ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font: Qt.font({family: "Segoe UI Symbol", pixelSize: 24})
                                color: parent.parent.isActive ? Style.Theme.goldL
                                     : navMouseArea.containsMouse ? Style.Theme.tg
                                     : Style.Theme.td

                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            MouseArea {
                                id: navMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: appWindow.currentPage = modelData.key
                            }
                        }

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            font: Qt.font({family: "Consolas", pixelSize: 12})
                            color: parent.isActive ? Style.Theme.goldD
                                 : navMouseArea.containsMouse ? Style.Theme.td
                                 : Style.Theme.tdd

                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }

                // Spacer
                Item { Layout.fillHeight: true }

                // Version
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "v4.1"
                    font: Qt.font({family: "Consolas", pixelSize: 13})
                    color: Style.Theme.tdd
                }

                // Connection dot
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    text: "●"
                    font: Qt.font({family: "Segoe UI", pixelSize: 15})
                    color: appWindow.connected ? Style.Theme.green : Style.Theme.td
                }

                // Bottom divider
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    width: 38; height: 1
                    color: Style.Theme.border
                }
            }
        }

        // ─── MAIN RIGHT AREA ────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ═══ TOP BAR ═══
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                color: Style.Theme.bg1

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Gold accent bar
                    Rectangle { width: 3; Layout.fillHeight: true; color: Style.Theme.gold }

                    // Brand
                    RowLayout {
                        Layout.leftMargin: 18
                        spacing: 0
                        Text { text: "PROBE"; font: Style.Theme.brandFont; color: Style.Theme.tw }
                        Text { text: "BRAKE"; font: Style.Theme.brandFont; color: Style.Theme.goldL; leftPadding: 0; rightPadding: 8 }
                        Text {
                            text: "LC"
                            font: Qt.font({family: "Consolas", pixelSize: 16, bold: true})
                            color: Style.Theme.gold
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 4
                        }
                    }

                    // Separator
                    Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 12; Layout.bottomMargin: 12; color: Style.Theme.border2 }

                    Text {
                        text: "CONTROL PANEL"
                        font: Qt.font({family: "Consolas", pixelSize: 14})
                        color: Style.Theme.td
                        Layout.leftMargin: 14
                    }

                    Item { Layout.fillWidth: true }

                    // Status label
                    Text {
                        text: appWindow.statusText
                        font: Qt.font({family: "Consolas", pixelSize: 14, bold: true})
                        color: appWindow.statusColor
                        Layout.rightMargin: 10
                    }

                    // Port dropdown
                    ComboBox {
                        id: portCombo
                        model: appWindow.portList
                        implicitWidth: 150
                        implicitHeight: 30
                        font: Qt.font({family: "Consolas", pixelSize: 15})

                        background: Rectangle {
                            radius: 5
                            color: portCombo.hovered ? Style.Theme.bg4 : Style.Theme.bg3
                            border.width: 1
                            border.color: portCombo.hovered ? Style.Theme.gold : Style.Theme.border2
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                        contentItem: Text {
                            leftPadding: 8
                            text: portCombo.displayText
                            font: portCombo.font
                            color: portCombo.hovered ? Style.Theme.tw : Style.Theme.tg
                            verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        popup: Popup {
                            y: portCombo.height; width: portCombo.width
                            implicitHeight: contentItem.implicitHeight; padding: 1
                            background: Rectangle { color: Style.Theme.bg2; radius: 4; border.width: 1; border.color: Style.Theme.border2 }
                            contentItem: ListView {
                                clip: true; implicitHeight: contentHeight
                                model: portCombo.popup.visible ? portCombo.delegateModel : null
                            }
                        }
                        delegate: ItemDelegate {
                            width: portCombo.width; height: 28
                            background: Rectangle {
                                color: highlighted ? Style.Theme.bg5 : (hovered ? Style.Theme.bg4 : "transparent")
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }
                            contentItem: Text {
                                text: modelData; font: portCombo.font
                                color: highlighted ? Style.Theme.gold : (hovered ? Style.Theme.tw : Style.Theme.tg)
                                verticalAlignment: Text.AlignVCenter; leftPadding: 8
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }
                            highlighted: portCombo.highlightedIndex === index
                        }
                        onActivated: appWindow.selectedPort = portCombo.textAt(index)
                    }

                    // Refresh button
                    Button {
                        id: refreshBtn
                        implicitWidth: 30; implicitHeight: 30
                        text: "↺"
                        font: Qt.font({family: "Segoe UI", pixelSize: 16})
                        Layout.leftMargin: 4
                        background: Rectangle {
                            radius: 5
                            color: refreshBtn.hovered ? Style.Theme.bg4 : Style.Theme.bg3
                            border.width: 1
                            border.color: refreshBtn.hovered ? Style.Theme.border3 : Style.Theme.border2
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }

                            scale: refreshBtn.pressed ? 0.92 : 1.0
                            Behavior on scale { NumberAnimation { duration: 80 } }
                        }
                        contentItem: Text {
                            text: refreshBtn.text; font: refreshBtn.font
                            color: refreshBtn.hovered ? Style.Theme.tw : Style.Theme.tg
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        onClicked: { if (backend) backend.refreshPorts() }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }

                    // Connect button
                    Button {
                        id: connectBtn
                        implicitWidth: 108; implicitHeight: 30
                        text: appWindow.connected ? "DISCONNECT" : "CONNECT"
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 17, bold: true})
                        Layout.leftMargin: 6
                        Layout.rightMargin: 16

                        background: Rectangle {
                            radius: 5
                            color: {
                                if (appWindow.connected) {
                                    return connectBtn.pressed ? Style.Theme.bg5
                                         : connectBtn.hovered ? Style.Theme.bg5
                                         : Style.Theme.bg4;
                                } else {
                                    return connectBtn.pressed ? Style.Theme.goldL
                                         : connectBtn.hovered ? Qt.lighter(Style.Theme.gold, 1.15)
                                         : Style.Theme.gold;
                                }
                            }
                            border.width: appWindow.connected && connectBtn.hovered ? 1 : 0
                            border.color: Style.Theme.border3
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                        contentItem: Text {
                            text: connectBtn.text; font: connectBtn.font
                            color: appWindow.connected
                                   ? (connectBtn.hovered ? Style.Theme.tw : Style.Theme.tg)
                                   : "#000"
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: {
                            if (backend) {
                                if (appWindow.connected) {
                                    backend.disconnect();
                                } else {
                                    backend.connectPort(appWindow.selectedPort);
                                }
                            }
                        }
                    }
                }
            }

            // Gold + dark accent lines
            Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.borderGold }
            Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border }

            // ═══ PAGE STACK ═══
            StackLayout {
                id: pageStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: {
                    switch (appWindow.currentPage) {
                        case "curves":  return 0;
                        case "feel":    return 1;
                        case "system":  return 2;
                        case "console": return 3;
                        default:        return 0;
                    }
                }

                // Page 0: Curves
                Pages.CurvesPage {
                    brakeValue: appWindow.brakeValue
                    throttleValue: appWindow.throttleValue
                    clutchValue: appWindow.clutchValue
                    flagText: appWindow.flagText
                    flagColor: appWindow.flagColor
                    onSendCommand: function(cmd) { appWindow.sendCommand(cmd) }
                }

                // Page 1: Feel
                Pages.FeelPage {
                    onSendCommand: function(cmd) { appWindow.sendCommand(cmd) }
                }

                // Page 2: System
                Pages.SystemPage {
                    onSendCommand: function(cmd) { appWindow.sendCommand(cmd) }
                }

                // Page 3: Console
                Pages.ConsolePage {
                    id: consolePage
                    profileText: appWindow.profileText
                    statusText: appWindow.flagText
                    statusColor: appWindow.flagColor
                    onSendCommand: function(cmd) { appWindow.sendCommand(cmd) }
                }
            }
        }
    }

    // ═══ CALIBRATION OVERLAY (covers entire window) ═══
    Comp.CalibrationOverlay {
        id: calOverlay
        anchors.fill: parent
        onCalibrationDone: appWindow.sendCommand("save")
    }
}
