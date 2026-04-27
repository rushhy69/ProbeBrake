import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style
import "../components" as Comp

/* ═══════════════════════════════════════════════════════════
   PedalColumn — Full pedal configuration column
   Header → LiveBar → Curve Presets → CurveEditor → Controls
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root

    property string name: "BRAKE"
    property string prefix: "b"
    property string axisLabel: "B"
    property color accent: Style.Theme.amber
    property color accentDim: Style.Theme.amberDim
    property color accentMid: Style.Theme.amberMid
    property real liveValue: 0
    property int selectedCurve: 0

    signal sendCommand(string cmd)

    // ── Load saved curve & LUT on startup ──
    Component.onCompleted: {
        if (serialBackend) {
            var savedCurve = JSON.parse(serialBackend.getSetting(root.prefix + "_curve", "0"))
            root.selectedCurve = savedCurve

            var savedLutStr = serialBackend.getSetting(root.prefix + "_lut", "null")
            var savedLut = JSON.parse(savedLutStr)
            if (savedLut && savedLut.length === 10)
                curveEditor.lut = savedLut
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── HEADER ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 60
            color: Style.Theme.bg2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 10

                // Badge
                Rectangle {
                    width: 34; height: 34
                    radius: 5
                    color: root.accentDim
                    border.width: 1
                    border.color: root.accent

                    Text {
                        anchors.centerIn: parent
                        text: root.axisLabel
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 20, bold: true})
                        color: root.accent
                    }
                }

                // Name + subtitle
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Text {
                        text: root.name
                        font: Style.Theme.titleFont
                        color: Style.Theme.tw
                    }
                    Text {
                        text: "AXIS " + root.axisLabel + "  ·  PROBRAKE LC"
                        font: Style.Theme.monoTFont
                        color: Style.Theme.td
                    }
                }

                // Gauge
                Comp.MiniGauge {
                    width: 64; height: 64
                    accent: root.accent
                    label: root.name.substring(0, 3)
                    value: root.liveValue
                }
            }
        }

        // ── SEPARATOR ──
        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border2 }

        // ── LIVE BAR ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 18
            color: Style.Theme.bg1

            Comp.LiveBar {
                anchors.fill: parent
                anchors.margins: 6
                accent: root.accent
                accentDim: root.accentDim
                value: root.liveValue
            }
        }

        // ── CURVE PRESETS ──
        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: Style.Theme.bg2

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: 6
                    Comp.CurveIcon {
                        Layout.fillWidth: true
                        curveId: index
                        accent: root.accent
                        accentDim: root.accentDim
                        selected: root.selectedCurve === index
                        onClicked: function(cid) {
                            root.selectedCurve = cid;
                            root.sendCommand(root.prefix + "curve " + cid);
                            if (serialBackend) serialBackend.setSetting(root.prefix + "_curve", JSON.stringify(cid));
                            if (cid < 5) {
                                // Generate LUT from curve function
                                var newLut = [];
                                for (var i = 0; i < 10; i++) {
                                    var xn = i / 9.0;
                                    var yn;
                                    switch (cid) {
                                        case 0: yn = xn; break;
                                        case 1: yn = xn * xn; break;
                                        case 2: yn = Math.sqrt(Math.max(0, xn)); break;
                                        case 3: yn = xn * xn * (3 - 2 * xn); break;
                                        case 4: yn = Math.pow(xn, 2.0); break;
                                        default: yn = xn; break;
                                    }
                                    newLut.push(Math.max(0, Math.min(100, Math.round(yn * 100))));
                                }
                                curveEditor.lut = newLut;
                                if (serialBackend) serialBackend.setSetting(root.prefix + "_lut", JSON.stringify(newLut));
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border }

        // ── CURVE EDITOR ──
        Comp.CurveEditor {
            id: curveEditor
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            accent: root.accent
            accentDim: root.accentDim
            liveInput: root.liveValue

            onLutEdited: function(newLut) {
                root.sendCommand(root.prefix + "lut " + newLut.join(" "));
                if (serialBackend) serialBackend.setSetting(root.prefix + "_lut", JSON.stringify(newLut));
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border }

        // ── CONTROLS (scrollable) ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: root.width
                spacing: 3

                Comp.SectionDivider { text: "DEAD ZONE"; accent: root.accent }
                Comp.PremiumSlider {
                    label: "Min Dead Zone"; from: 0; to: 30
                    value: 0; settingsKey: root.prefix + "_dzmin"
                    accent: root.accent; accentMid: root.accentMid
                    onSliderMoved: function(v) { root.sendCommand(root.prefix + "dzmin " + v) }
                }
                Comp.PremiumSlider {
                    label: "Max Dead Zone"; from: 0; to: 30
                    value: 0; settingsKey: root.prefix + "_dzmax"
                    accent: root.accent; accentMid: root.accentMid
                    onSliderMoved: function(v) { root.sendCommand(root.prefix + "dzmax " + v) }
                }





                // Clutch-specific
                Loader {
                    active: root.prefix === "c"
                    Layout.fillWidth: true
                    sourceComponent: ColumnLayout {
                        spacing: 3
                        Comp.SectionDivider { text: "CLUTCH"; accent: root.accent }
                        Comp.PremiumSlider {
                            label: "Bite Point"; from: 0; to: 99; value: 0
                            settingsKey: "c_bite"
                            accent: root.accent; accentMid: root.accentMid
                            onSliderMoved: function(v) { root.sendCommand("cbite " + v) }
                        }
                    }
                }

                // Invert for throttle / clutch
                Loader {
                    active: root.prefix === "t" || root.prefix === "c"
                    Layout.fillWidth: true
                    sourceComponent: ColumnLayout {
                        spacing: 3
                        Comp.SectionDivider { text: "OPTIONS"; accent: root.accent }
                        Comp.PremiumToggle {
                            label: "Invert Direction"; accent: root.accent
                            settingsKey: root.prefix + "_inv"
                            onToggled: root.sendCommand(root.prefix + "inv")
                        }
                    }
                }

                // Clutch enable
                Loader {
                    active: root.prefix === "c"
                    Layout.fillWidth: true
                    sourceComponent: Comp.PremiumToggle {
                        label: "Clutch Enable"; accent: root.accent; checked: false
                        settingsKey: "c_enable"
                        onToggled: function(on) { root.sendCommand(on ? "con" : "coff") }
                    }
                }

                // Calibration
                Comp.SectionDivider { text: "CALIBRATION"; accent: root.accent }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 4

                    Comp.CalButton {
                        text: "⬇  MIN  (release)"
                        accent: root.accent; accentDim: root.accentDim
                        Layout.fillWidth: true
                        onClicked: root.sendCommand(root.prefix + "min")
                    }
                    Comp.CalButton {
                        text: "⬆  MAX  (press)"
                        accent: root.accent; accentDim: root.accentDim
                        Layout.fillWidth: true
                        onClicked: root.sendCommand(root.prefix + "max")
                    }
                }

                // Bottom padding
                Item { Layout.fillWidth: true; implicitHeight: 16 }
            }
        }
    }
}
