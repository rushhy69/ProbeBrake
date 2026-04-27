import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style
import "../components" as Comp

/* ═══════════════════════════════════════════════════════════
   SystemPage — Profiles, HID rate, ABS, Diagnostics, Danger
   All buttons have premium hover effects
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    signal sendCommand(string cmd)

    property int activeProfile: 0
    property string activeRate: "1000"

    // ── Load saved system settings on startup ──
    Component.onCompleted: {
        if (serialBackend) {
            var savedProfile = JSON.parse(serialBackend.getSetting("sys_profile", "0"))
            root.activeProfile = savedProfile
            var savedRate = JSON.parse(serialBackend.getSetting("sys_rate", JSON.stringify("1000")))
            root.activeRate = String(savedRate)
        }
    }

    // ── Reusable card component ──
    component SystemCard: Rectangle {
        property string title: ""
        property string icon: ""
        property color accent: Style.Theme.tg
        default property alias content: cardBody.data

        Layout.fillWidth: true
        radius: 10
        color: Style.Theme.bg2
        border.width: 1; border.color: Style.Theme.border2

        ColumnLayout {
            anchors.fill: parent; spacing: 0

            Rectangle {
                Layout.fillWidth: true; implicitHeight: 38; color: Style.Theme.bg3
                // Round only top corners
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }
                radius: 10

                RowLayout {
                    anchors.fill: parent; spacing: 0
                    Rectangle { width: 3; Layout.fillHeight: true; color: accent }
                    Text {
                        text: "  " + icon + "  " + title
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 15, bold: true})
                        color: accent; Layout.fillWidth: true
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border }

            ColumnLayout {
                id: cardBody
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.margins: 14; spacing: 6
            }
        }
    }

    // ── Reusable hover button ──
    component HoverButton: Button {
        id: hBtn
        property color bgNormal: Style.Theme.bg4
        property color bgHover: Style.Theme.bg5
        property color bgPress: Style.Theme.bg5
        property color textNormal: Style.Theme.tg
        property color textHover: Style.Theme.tw
        property color borderNormal: Style.Theme.border2
        property color borderHover: Style.Theme.border3
        property int bgRadius: 5

        background: Rectangle {
            radius: hBtn.bgRadius
            color: hBtn.pressed ? hBtn.bgPress
                 : hBtn.hovered ? hBtn.bgHover
                 : hBtn.bgNormal
            border.width: 1
            border.color: hBtn.hovered ? hBtn.borderHover : hBtn.borderNormal
            Behavior on color { ColorAnimation { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }
        }
        contentItem: Text {
            text: hBtn.text; font: hBtn.font
            color: hBtn.hovered ? hBtn.textHover : hBtn.textNormal
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 16

            Item { implicitHeight: 2 }

            // ═══ ROW 1: Profile + HID Rate ═══
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 16

                // ── PROFILE MANAGEMENT ──
                SystemCard {
                    Layout.preferredHeight: 170
                    title: "PROFILE MANAGEMENT"; icon: "◈"; accent: Style.Theme.goldL

                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Repeater {
                            model: 3
                            HoverButton {
                                Layout.fillWidth: true; implicitHeight: 36
                                text: "PROFILE  " + index
                                font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                                bgNormal: root.activeProfile === index ? Style.Theme.goldDim : Style.Theme.bg4
                                bgHover: Style.Theme.goldDim
                                borderNormal: root.activeProfile === index ? Style.Theme.gold : Style.Theme.border2
                                borderHover: Style.Theme.gold
                                textNormal: root.activeProfile === index ? Style.Theme.goldL : Style.Theme.tg
                                textHover: Style.Theme.goldL
                                bgRadius: 5
                                onClicked: {
                                    root.activeProfile = index;
                                    root.sendCommand("profile " + index);
                                    if (serialBackend) serialBackend.setSetting("sys_profile", JSON.stringify(index));
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 4
                        Button {
                            id: saveProfileBtn
                            Layout.fillWidth: true; implicitHeight: 28
                            text: "SAVE PROFILE"
                            font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                            background: Rectangle {
                                radius: 4
                                color: saveProfileBtn.pressed ? Style.Theme.goldL
                                     : saveProfileBtn.hovered ? Qt.lighter(Style.Theme.gold, 1.15)
                                     : Style.Theme.gold
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            contentItem: Text { text: parent.text; font: parent.font; color: "#000"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: root.sendCommand("save")
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                        Repeater {
                            model: 3
                            HoverButton {
                                Layout.fillWidth: true; implicitHeight: 28
                                text: "→ P" + index
                                font: Style.Theme.monoSFont
                                bgNormal: Style.Theme.goldDim
                                bgHover: Style.Theme.bg4
                                borderNormal: Style.Theme.goldD
                                borderHover: Style.Theme.gold
                                textNormal: Style.Theme.gold
                                textHover: Style.Theme.goldL
                                bgRadius: 4
                                onClicked: root.sendCommand("copy " + index)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── HID REPORT RATE ──
                SystemCard {
                    Layout.preferredHeight: 170
                    title: "HID REPORT RATE"; icon: "◎"; accent: Style.Theme.cyanL

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: ["250", "500", "1000"]
                            HoverButton {
                                Layout.fillWidth: true; implicitHeight: 54
                                text: modelData + "\nHz"
                                font: Qt.font({family: "Trebuchet MS", pixelSize: 17, bold: true})
                                bgNormal: root.activeRate === modelData ? Style.Theme.cyanDim : Style.Theme.bg4
                                bgHover: Style.Theme.cyanDim
                                borderNormal: root.activeRate === modelData ? Style.Theme.cyan : Style.Theme.border2
                                borderHover: Style.Theme.cyan
                                textNormal: root.activeRate === modelData ? Style.Theme.cyanL : Style.Theme.tg
                                textHover: Style.Theme.cyanL
                                bgRadius: 6
                                onClicked: {
                                    root.activeRate = modelData;
                                    root.sendCommand("rate " + modelData);
                                    if (serialBackend) serialBackend.setSetting("sys_rate", JSON.stringify(modelData));
                                }
                            }
                        }
                    }

                    Text { text: "Higher rate = lower latency, more USB bandwidth"; font: Style.Theme.monoTFont; color: Style.Theme.td }
                    Item { Layout.fillHeight: true }
                }
            }

            // ═══ ROW 2: ABS Rumble + Calibration ═══
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 16

                // ── ABS RUMBLE ──
                SystemCard {
                    Layout.preferredHeight: 150
                    title: "ABS RUMBLE MOTOR"; icon: "◉"; accent: Style.Theme.amberL

                    Comp.PremiumSlider { label: "Motor Intensity (PWM)"; from: 0; to: 255; value: 0; settingsKey: "sys_rumble"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("rumble " + v) } }
                    Comp.PremiumSlider { label: "Trigger Threshold %"; from: 50; to: 100; value: 85; settingsKey: "sys_rthresh"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("rthresh " + v) } }
                    Item { Layout.fillHeight: true }
                }

                // ── CALIBRATION & TELEMETRY ──
                SystemCard {
                    Layout.preferredHeight: 150
                    title: "CALIBRATION & TELEMETRY"; icon: "◐"; accent: Style.Theme.greenL

                    Button {
                        id: autocalBtn
                        Layout.fillWidth: true; implicitHeight: 36
                        text: "▶   START AUTO-CALIBRATION  (30 sec)"
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                        background: Rectangle {
                            radius: 6
                            color: autocalBtn.pressed ? Style.Theme.bg4
                                 : autocalBtn.hovered ? Qt.lighter(Style.Theme.greenDim, 1.4)
                                 : Style.Theme.greenDim
                            border.width: 1
                            border.color: autocalBtn.hovered ? Style.Theme.greenL : Style.Theme.green
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: autocalBtn.hovered ? Style.Theme.tw : Style.Theme.greenL
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        onClicked: root.sendCommand("autocal")
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                    Text { text: "Press each pedal to its full range during calibration."; font: Style.Theme.monoTFont; color: Style.Theme.td }
                    HoverButton {
                        Layout.fillWidth: true; implicitHeight: 30
                        text: "CYCLE TELEMETRY  ·  OFF → TEXT → BINARY"
                        font: Style.Theme.monoTFont
                        bgRadius: 4
                        onClicked: root.sendCommand("telem")
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ═══ ROW 3: Diagnostics + Danger Zone ═══
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 16

                // ── DIAGNOSTICS ──
                SystemCard {
                    Layout.preferredHeight: 120
                    title: "DIAGNOSTICS"; icon: "ℹ"; accent: Style.Theme.tg

                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Repeater {
                            model: [{t:"STATUS",c:"status"},{t:"SELF-TEST",c:"test"},{t:"FAULTS",c:"faults"},{t:"HELP",c:"help"}]
                            HoverButton {
                                Layout.fillWidth: true; implicitHeight: 36
                                text: modelData.t
                                font: Qt.font({family: "Trebuchet MS", pixelSize: 15, bold: true})
                                bgRadius: 5
                                onClicked: root.sendCommand(modelData.c)
                            }
                        }
                    }
                }

                // ── DANGER ZONE ──
                SystemCard {
                    Layout.preferredHeight: 120
                    title: "DANGER ZONE"; icon: "⚠"; accent: Style.Theme.red

                    Button {
                        id: factoryBtn
                        Layout.fillWidth: true; implicitHeight: 36
                        text: "⚠   FACTORY RESET  —  ERASE ALL PROFILES"
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 16, bold: true})
                        background: Rectangle {
                            radius: 6
                            color: factoryBtn.pressed ? Style.Theme.redMid
                                 : factoryBtn.hovered ? Qt.lighter(Style.Theme.redDim, 1.5)
                                 : Style.Theme.redDim
                            border.width: 1
                            border.color: factoryBtn.hovered ? Qt.lighter(Style.Theme.red, 1.2) : Style.Theme.red
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                        contentItem: Text {
                            text: parent.text; font: parent.font
                            color: factoryBtn.hovered ? Qt.lighter(Style.Theme.red, 1.3) : Style.Theme.red
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                        onClicked: root.sendCommand("factory")
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                    Text { text: "Permanently erases all profiles and settings."; font: Style.Theme.monoTFont; color: Style.Theme.td }
                    Item { Layout.fillHeight: true }
                }
            }

            // Bottom padding
            Item { implicitHeight: 18 }
        }
    }
}
