import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style
import "../panels" as Panels

/* ═══════════════════════════════════════════════════════════
   CurvesPage — 3-column pedal tuning + bottom status bar
   Column order: THROTTLE | BRAKE | CLUTCH
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root

    property real brakeValue: 0
    property real throttleValue: 0
    property real clutchValue: 0
    property string flagText: "●  NOMINAL"
    property color flagColor: Style.Theme.green

    signal sendCommand(string cmd)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── 3-column pedal area ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // THROTTLE (left)
            Panels.PedalColumn {
                Layout.fillWidth: true
                Layout.fillHeight: true
                name: "THROTTLE"; prefix: "t"; axisLabel: "T"
                accent: Style.Theme.green
                accentDim: Style.Theme.greenDim
                accentMid: Style.Theme.greenMid
                liveValue: root.throttleValue
                onSendCommand: function(cmd) { root.sendCommand(cmd) }
            }

            // Separator
            Rectangle { width: 1; Layout.fillHeight: true; color: Style.Theme.border2 }

            // BRAKE (center)
            Panels.PedalColumn {
                Layout.fillWidth: true
                Layout.fillHeight: true
                name: "BRAKE"; prefix: "b"; axisLabel: "B"
                accent: Style.Theme.amber
                accentDim: Style.Theme.amberDim
                accentMid: Style.Theme.amberMid
                liveValue: root.brakeValue
                onSendCommand: function(cmd) { root.sendCommand(cmd) }
            }

            // Separator
            Rectangle { width: 1; Layout.fillHeight: true; color: Style.Theme.border2 }

            // CLUTCH (right)
            Panels.PedalColumn {
                Layout.fillWidth: true
                Layout.fillHeight: true
                name: "CLUTCH"; prefix: "c"; axisLabel: "C"
                accent: Style.Theme.cyan
                accentDim: Style.Theme.cyanDim
                accentMid: Style.Theme.cyanMid
                liveValue: root.clutchValue
                onSendCommand: function(cmd) { root.sendCommand(cmd) }
            }
        }

        // ── GOLD ACCENT LINE ──
        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.borderGold }

        // ── STATUS BAR ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 50
            color: Style.Theme.bg2

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Gold accent bar
                Rectangle { width: 3; Layout.fillHeight: true; color: Style.Theme.gold }

                // Telemetry readouts (order matches legacy: THROTTLE, BRAKE, CLUTCH)
                RowLayout {
                    Layout.leftMargin: 16
                    spacing: 24

                    Repeater {
                        model: [
                            {label: "THROTTLE", color: Style.Theme.green, val: root.throttleValue},
                            {label: "BRAKE",    color: Style.Theme.amber, val: root.brakeValue},
                            {label: "CLUTCH",   color: Style.Theme.cyan,  val: root.clutchValue}
                        ]

                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: modelData.label
                                font: Style.Theme.monoTFont
                                color: Style.Theme.td
                            }
                            Text {
                                text: Math.round(modelData.val) + "%"
                                font: Qt.font({family: "Consolas", pixelSize: 20, bold: true})
                                color: modelData.color
                            }
                        }
                    }
                }

                // Separator
                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 10; Layout.bottomMargin: 10; color: Style.Theme.border2 }

                // Flag
                Text {
                    Layout.leftMargin: 18
                    text: root.flagText
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                    color: root.flagColor
                }

                Item { Layout.fillWidth: true }

                // Action buttons (order matches legacy: IMPORT, DEFAULT, SAVE — right to left)
                Button {
                    id: importBtn
                    text: "IMPORT"
                    implicitWidth: 74; implicitHeight: 32
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                    background: Rectangle {
                        radius: 5; color: importBtn.hovered ? Style.Theme.bg4 : Style.Theme.goldDim
                        border.width: 1; border.color: Style.Theme.goldD
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    contentItem: Text {
                        text: parent.text; font: parent.font
                        color: Style.Theme.goldL
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Button {
                    id: defaultBtn
                    text: "DEFAULT"
                    implicitWidth: 74; implicitHeight: 32
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                    background: Rectangle {
                        radius: 5; color: defaultBtn.hovered ? Style.Theme.bg4 : Style.Theme.goldDim
                        border.width: 1; border.color: Style.Theme.goldD
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    contentItem: Text {
                        text: parent.text; font: parent.font
                        color: Style.Theme.goldL
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.sendCommand("factory")
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Button {
                    id: saveBtn
                    text: "SAVE"
                    implicitWidth: 74; implicitHeight: 32
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                    background: Rectangle {
                        radius: 5; color: saveBtn.pressed ? Style.Theme.goldL : (saveBtn.hovered ? Qt.lighter(Style.Theme.gold, 1.15) : Style.Theme.gold)
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    contentItem: Text {
                        text: parent.text; font: parent.font; color: "#000"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.sendCommand("save")
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                Item { width: 8 }
            }
        }
    }
}
