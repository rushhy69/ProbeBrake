import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   ConsolePage — Serial terminal with quick-action buttons
   All buttons have premium hover effects
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    signal sendCommand(string cmd)

    property string profileText: "Profile  —"
    property string statusText: "●  READY"
    property color statusColor: Style.Theme.green

    function appendLog(text) {
        var ts = new Date().toLocaleTimeString("HH:mm:ss");
        logModel.append({line: "[" + ts + "]  " + text});
        // Trim if too long
        if (logModel.count > 500) logModel.remove(0, logModel.count - 400);
        logView.positionViewAtEnd();
    }

    function clearLog() {
        logModel.clear();
    }

    ListModel { id: logModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── TOP TOOLBAR ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 90
            color: Style.Theme.bg2

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Gold accent top
                Rectangle { Layout.fillWidth: true; height: 2; color: Style.Theme.gold }

                // Profile + status row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8

                    Text {
                        text: root.profileText
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 20, bold: true})
                        color: Style.Theme.tw
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.statusText
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                        color: root.statusColor
                    }
                }

                // Quick-action buttons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    spacing: 4

                    Repeater {
                        model: ["STATUS", "TEST", "FAULTS", "TELEM", "AUTOCAL", "HELP", "SAVE", "CLEAR"]

                        Button {
                            id: qBtn
                            text: modelData
                            implicitHeight: 26
                            font: Qt.font({family: "Consolas", pixelSize: 14, bold: true})

                            background: Rectangle {
                                radius: 3
                                color: qBtn.pressed ? Style.Theme.bg5
                                     : qBtn.hovered ? Style.Theme.bg5
                                     : Style.Theme.bg4
                                border.width: 1
                                border.color: qBtn.hovered ? Style.Theme.border3 : Style.Theme.border2

                                Behavior on color { ColorAnimation { duration: 80 } }
                                Behavior on border.color { ColorAnimation { duration: 80 } }

                                // Subtle accent glow on hover
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Style.Theme.gold
                                    opacity: qBtn.hovered ? 0.06 : 0
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                }
                            }
                            contentItem: Text {
                                text: qBtn.text; font: qBtn.font
                                color: qBtn.hovered ? Style.Theme.tw : Style.Theme.tg
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }

                            onClicked: {
                                if (modelData === "CLEAR") {
                                    root.clearLog();
                                } else {
                                    root.sendCommand(modelData.toLowerCase());
                                }
                            }
                        }
                    }
                }
            }
        }

        // Gold accent line
        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.borderGold }

        // ── LOG VIEW ──
        ListView {
            id: logView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: logModel

            Rectangle {
                anchors.fill: parent
                color: "#060609"
                z: -1
            }

            delegate: Text {
                width: logView.width
                text: line
                font: Qt.font({family: "Consolas", pixelSize: 16})
                color: "#7070c0"
                leftPadding: 8
                topPadding: 1
                bottomPadding: 1
                wrapMode: Text.Wrap
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }

        // Gold accent line
        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.borderGold }

        // ── COMMAND INPUT BAR ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            color: Style.Theme.bg2

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Gold accent bar
                Rectangle { width: 3; Layout.fillHeight: true; color: Style.Theme.gold }

                // Prompt
                Text {
                    text: "❯"
                    font: Qt.font({family: "Consolas", pixelSize: 20})
                    color: Style.Theme.gold
                    Layout.leftMargin: 10
                }

                // Input field
                TextField {
                    id: cmdInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    placeholderText: "enter command..."
                    placeholderTextColor: Style.Theme.td
                    color: Style.Theme.tw
                    font: Qt.font({family: "Consolas", pixelSize: 17})

                    background: Rectangle { color: "transparent" }

                    onAccepted: {
                        if (text.trim().length > 0) {
                            root.sendCommand(text.trim());
                            text = "";
                        }
                    }
                }

                // Send button
                Button {
                    id: sendBtn
                    text: "SEND"
                    implicitWidth: 72; implicitHeight: 32
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 17, bold: true})
                    Layout.rightMargin: 12

                    background: Rectangle {
                        radius: 4
                        color: sendBtn.pressed ? Style.Theme.goldL
                             : sendBtn.hovered ? Qt.lighter(Style.Theme.gold, 1.15)
                             : Style.Theme.gold
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    contentItem: Text {
                        text: sendBtn.text; font: sendBtn.font
                        color: "#000"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    onClicked: {
                        if (cmdInput.text.trim().length > 0) {
                            root.sendCommand(cmdInput.text.trim());
                            cmdInput.text = "";
                        }
                    }
                }
            }
        }
    }
}
