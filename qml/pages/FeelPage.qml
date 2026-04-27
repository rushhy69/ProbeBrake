import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style
import "../components" as Comp

/* ═══════════════════════════════════════════════════════════
   FeelPage — Advanced per-pedal settings (3 columns)
   Column order: BRAKE | THROTTLE | CLUTCH (matches legacy)
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    signal sendCommand(string cmd)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── BRAKE COLUMN (left — matches legacy) ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: root.width / 3
                spacing: 3

                // Header
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 44; color: Style.Theme.bg2
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; spacing: 10
                        Rectangle {
                            width: 28; height: 28; radius: 4
                            color: Style.Theme.amberDim; border.width: 1; border.color: Style.Theme.amber
                            Text { anchors.centerIn: parent; text: "B"; font: Qt.font({family: "Trebuchet MS", pixelSize: 18, bold: true}); color: Style.Theme.amber }
                        }
                        Text { text: "BRAKE"; font: Style.Theme.titleFont; color: Style.Theme.tw }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.amberDim }

                Comp.SectionDivider { text: "PEDAL FEEL"; accent: Style.Theme.amber }
                Comp.PremiumSlider { label: "Dead Zone Min"; from: 0; to: 30; value: 0; settingsKey: "b_dzmin"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bdzmin " + v) } }
                Comp.PremiumSlider { label: "Dead Zone Max"; from: 0; to: 30; value: 0; settingsKey: "b_dzmax"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bdzmax " + v) } }
                Comp.PremiumSlider { label: "Hysteresis"; from: 0; to: 50; value: 3; settingsKey: "b_hyst"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bhyst " + v) } }




                Comp.SectionDivider { text: "FILTERING"; accent: Style.Theme.amber }
                Comp.PremiumSlider { label: "Custom Exp"; from: 5; to: 40; value: 20; settingsKey: "b_exp"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bexp " + v) } }
                Comp.PremiumSlider { label: "Kalman Q"; from: 1; to: 100; value: 5; settingsKey: "b_kq"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bkq " + v) } }
                Comp.PremiumSlider { label: "Kalman R"; from: 1; to: 100; value: 15; settingsKey: "b_kr"; accent: Style.Theme.amber; accentMid: Style.Theme.amberMid; onSliderMoved: function(v) { root.sendCommand("bkr " + v) } }
                Comp.PremiumDropdown { label: "Smoothing Mode"; model: ["0: Moving Avg", "1: EMA", "2: Median"]; settingsKey: "b_smooth"; accent: Style.Theme.amber; onActivated: function(t) { root.sendCommand("bsmooth " + t[0]) } }

                Comp.SectionDivider { text: "CALIBRATION"; accent: Style.Theme.amber }
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 4
                    Comp.CalButton { text: "⬇  MIN"; accent: Style.Theme.amber; accentDim: Style.Theme.amberDim; Layout.fillWidth: true; onClicked: root.sendCommand("bmin") }
                    Comp.CalButton { text: "⬆  MAX"; accent: Style.Theme.amber; accentDim: Style.Theme.amberDim; Layout.fillWidth: true; onClicked: root.sendCommand("bmax") }
                }
                Item { implicitHeight: 16 }
            }
        }

        Rectangle { width: 1; Layout.fillHeight: true; color: Style.Theme.border2 }

        // ── THROTTLE COLUMN (center — matches legacy) ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: root.width / 3
                spacing: 3

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 44; color: Style.Theme.bg2
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; spacing: 10
                        Rectangle {
                            width: 28; height: 28; radius: 4
                            color: Style.Theme.greenDim; border.width: 1; border.color: Style.Theme.green
                            Text { anchors.centerIn: parent; text: "T"; font: Qt.font({family: "Trebuchet MS", pixelSize: 18, bold: true}); color: Style.Theme.green }
                        }
                        Text { text: "THROTTLE"; font: Style.Theme.titleFont; color: Style.Theme.tw }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.greenDim }

                Comp.SectionDivider { text: "PEDAL FEEL"; accent: Style.Theme.green }
                Comp.PremiumSlider { label: "Dead Zone Min"; from: 0; to: 30; value: 0; settingsKey: "t_dzmin"; accent: Style.Theme.green; accentMid: Style.Theme.greenMid; onSliderMoved: function(v) { root.sendCommand("tdzmin " + v) } }
                Comp.PremiumSlider { label: "Dead Zone Max"; from: 0; to: 30; value: 0; settingsKey: "t_dzmax"; accent: Style.Theme.green; accentMid: Style.Theme.greenMid; onSliderMoved: function(v) { root.sendCommand("tdzmax " + v) } }


                Comp.SectionDivider { text: "FILTERING"; accent: Style.Theme.green }
                Comp.PremiumSlider { label: "Custom Exp"; from: 5; to: 40; value: 20; settingsKey: "t_exp"; accent: Style.Theme.green; accentMid: Style.Theme.greenMid; onSliderMoved: function(v) { root.sendCommand("texp " + v) } }
                Comp.PremiumDropdown { label: "Smoothing Mode"; model: ["0: Moving Avg", "1: EMA", "2: Median"]; settingsKey: "t_smooth"; accent: Style.Theme.green; onActivated: function(t) { root.sendCommand("tsmooth " + t[0]) } }

                Comp.SectionDivider { text: "OPTIONS"; accent: Style.Theme.green }
                Comp.PremiumToggle { label: "Invert Direction"; settingsKey: "t_inv"; accent: Style.Theme.green; onToggled: root.sendCommand("tinv") }

                Comp.SectionDivider { text: "CALIBRATION"; accent: Style.Theme.green }
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 4
                    Comp.CalButton { text: "⬇  MIN"; accent: Style.Theme.green; accentDim: Style.Theme.greenDim; Layout.fillWidth: true; onClicked: root.sendCommand("tmin") }
                    Comp.CalButton { text: "⬆  MAX"; accent: Style.Theme.green; accentDim: Style.Theme.greenDim; Layout.fillWidth: true; onClicked: root.sendCommand("tmax") }
                }
                Item { implicitHeight: 16 }
            }
        }

        Rectangle { width: 1; Layout.fillHeight: true; color: Style.Theme.border2 }

        // ── CLUTCH COLUMN (right — matches legacy) ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: root.width / 3
                spacing: 3

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 44; color: Style.Theme.bg2
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; spacing: 10
                        Rectangle {
                            width: 28; height: 28; radius: 4
                            color: Style.Theme.cyanDim; border.width: 1; border.color: Style.Theme.cyan
                            Text { anchors.centerIn: parent; text: "C"; font: Qt.font({family: "Trebuchet MS", pixelSize: 18, bold: true}); color: Style.Theme.cyan }
                        }
                        Text { text: "CLUTCH"; font: Style.Theme.titleFont; color: Style.Theme.tw }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.cyanDim }

                Comp.SectionDivider { text: "PEDAL FEEL"; accent: Style.Theme.cyan }
                Comp.PremiumToggle { label: "Clutch Enable"; settingsKey: "c_enable"; accent: Style.Theme.cyan; checked: false; onToggled: function(on) { root.sendCommand(on ? "con" : "coff") } }
                Comp.PremiumSlider { label: "Dead Zone Min"; from: 0; to: 30; value: 0; settingsKey: "c_dzmin"; accent: Style.Theme.cyan; accentMid: Style.Theme.cyanMid; onSliderMoved: function(v) { root.sendCommand("cdzmin " + v) } }
                Comp.PremiumSlider { label: "Dead Zone Max"; from: 0; to: 30; value: 0; settingsKey: "c_dzmax"; accent: Style.Theme.cyan; accentMid: Style.Theme.cyanMid; onSliderMoved: function(v) { root.sendCommand("cdzmax " + v) } }


                Comp.SectionDivider { text: "FILTERING"; accent: Style.Theme.cyan }
                Comp.PremiumSlider { label: "Custom Exp"; from: 5; to: 40; value: 20; settingsKey: "c_exp"; accent: Style.Theme.cyan; accentMid: Style.Theme.cyanMid; onSliderMoved: function(v) { root.sendCommand("cexp " + v) } }
                Comp.PremiumDropdown { label: "Smoothing Mode"; model: ["0: Moving Avg", "1: EMA", "2: Median"]; settingsKey: "c_smooth"; accent: Style.Theme.cyan; onActivated: function(t) { root.sendCommand("csmooth " + t[0]) } }

                Comp.SectionDivider { text: "OPTIONS"; accent: Style.Theme.cyan }
                Comp.PremiumToggle { label: "Invert Direction"; settingsKey: "c_inv"; accent: Style.Theme.cyan; onToggled: root.sendCommand("cinv") }
                Comp.PremiumSlider { label: "Bite Point"; from: 0; to: 99; value: 0; settingsKey: "c_bite"; accent: Style.Theme.cyan; accentMid: Style.Theme.cyanMid; onSliderMoved: function(v) { root.sendCommand("cbite " + v) } }

                Comp.SectionDivider { text: "CALIBRATION"; accent: Style.Theme.cyan }
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 4
                    Comp.CalButton { text: "⬇  MIN"; accent: Style.Theme.cyan; accentDim: Style.Theme.cyanDim; Layout.fillWidth: true; onClicked: root.sendCommand("cmin") }
                    Comp.CalButton { text: "⬆  MAX"; accent: Style.Theme.cyan; accentDim: Style.Theme.cyanDim; Layout.fillWidth: true; onClicked: root.sendCommand("cmax") }
                }
                Item { implicitHeight: 16 }
            }
        }
    }
}
