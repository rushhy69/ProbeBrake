import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   CalibrationOverlay — Countdown popup during pedal calibration
   Shows 2s prepare + 5s measurement = 7s total
   Matches Arduino: safeDelay(2000) + calibrate5s()
   ═══════════════════════════════════════════════════════════ */
Rectangle {
    id: overlay
    anchors.fill: parent
    visible: false
    color: "#CC060609"
    z: 100

    // ── Public API ──
    property string pedalName: "BRAKE"
    property string action: "MIN"     // "MIN" or "MAX"
    property color accent: Style.Theme.amber

    signal calibrationDone()   // emitted when complete — parent auto-saves

    // ── Internal state ──
    property int phase: 0             // 0=idle, 1=prepare, 2=measuring
    property int countdown: 0
    property real progress: 0         // 0.0 → 1.0
    property int totalPrepare: 2
    property int totalMeasure: 5

    function start(pedal, act, clr) {
        pedalName = pedal;
        action = act;
        accent = clr;
        phase = 1;
        countdown = totalPrepare;
        progress = 0;
        visible = true;
        phaseTimer.start();
        progressAnim.start();
    }

    function stop() {
        phaseTimer.stop();
        progressAnim.stop();
        phase = 0;
        visible = false;
    }

    // ── Phase countdown timer (1s tick) ──
    Timer {
        id: phaseTimer
        interval: 1000
        repeat: true
        onTriggered: {
            overlay.countdown--;
            if (overlay.phase === 1 && overlay.countdown <= 0) {
                // Transition to measuring phase
                overlay.phase = 2;
                overlay.countdown = overlay.totalMeasure;
                overlay.progress = 0;
                progressAnim.stop();
                progressAnim.start();
            } else if (overlay.phase === 2 && overlay.countdown <= 0) {
                // Done
                doneTimer.start();
                phaseTimer.stop();
                progressAnim.stop();
                overlay.progress = 1.0;
                overlay.phase = 3;  // "DONE" state
            }
        }
    }

    // ── Progress animation ──
    NumberAnimation {
        id: progressAnim
        target: overlay
        property: "progress"
        from: 0; to: 1.0
        duration: overlay.phase === 1 ? (overlay.totalPrepare * 1000) : (overlay.totalMeasure * 1000)
    }

    // ── Auto-close after done ──
    Timer {
        id: doneTimer
        interval: 1500
        repeat: false
        onTriggered: {
            overlay.calibrationDone();
            overlay.stop();
        }
    }

    // ── Click backdrop to close (safety) ──
    MouseArea {
        anchors.fill: parent
        onClicked: {} // absorb clicks
    }

    // ═══ CARD ═══
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 340
        height: 300
        radius: 16
        color: Style.Theme.bg2
        border.width: 1
        border.color: overlay.accent

        // Entry animation
        scale: overlay.visible ? 1.0 : 0.85
        opacity: overlay.visible ? 1.0 : 0
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Glow border
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: parent.radius + 2
            color: "transparent"
            border.width: 2
            border.color: overlay.accent
            opacity: 0.3
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 8

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 36; height: 36; radius: 6
                    color: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.15)
                    border.width: 1; border.color: overlay.accent

                    Text {
                        anchors.centerIn: parent
                        text: overlay.pedalName.charAt(0)
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 20, bold: true})
                        color: overlay.accent
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: overlay.pedalName + " CALIBRATION"
                        font: Qt.font({family: "Trebuchet MS", pixelSize: 17, bold: true})
                        color: Style.Theme.tw
                    }
                    Text {
                        text: overlay.action === "MIN" ? "⬇  SET MINIMUM (release)" : "⬆  SET MAXIMUM (full press)"
                        font: Style.Theme.monoTFont
                        color: Style.Theme.tg
                    }
                }
            }

            // ── Divider ──
            Rectangle { Layout.fillWidth: true; height: 1; color: Style.Theme.border2 }

            // ── Phase indicator ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 5
                color: overlay.phase === 3 ? Qt.rgba(Style.Theme.green.r, Style.Theme.green.g, Style.Theme.green.b, 0.12)
                     : Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.08)
                border.width: 1
                border.color: overlay.phase === 3 ? Style.Theme.green : Style.Theme.border2

                Text {
                    anchors.centerIn: parent
                    text: overlay.phase === 1 ? (overlay.action === "MIN" ? "RELEASE PEDAL NOW" : "PRESS PEDAL FULLY")
                        : overlay.phase === 2 ? "HOLD STEADY — MEASURING"
                        : overlay.phase === 3 ? "✓  COMPLETE — AUTO-SAVING"
                        : ""
                    font: Qt.font({family: "Trebuchet MS", pixelSize: 14, bold: true})
                    color: overlay.phase === 3 ? Style.Theme.green
                         : overlay.phase === 1 ? Style.Theme.amberL
                         : overlay.accent
                }
            }

            // ── Countdown display ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Big countdown number
                Text {
                    anchors.centerIn: parent
                    text: overlay.phase === 3 ? "✓" : overlay.countdown.toString()
                    font: Qt.font({family: "Consolas", pixelSize: 72, bold: true})
                    color: overlay.phase === 3 ? Style.Theme.green : overlay.accent
                    opacity: overlay.phase === 3 ? 1.0 : 0.9

                    // Pulse animation on each tick
                    scale: pulseAnim.running ? 1.0 : 1.0

                    SequentialAnimation on scale {
                        id: pulseSeq
                        running: overlay.phase > 0 && overlay.phase < 3
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.08; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                    }

                    NumberAnimation on scale {
                        id: pulseAnim
                        running: false
                    }
                }

                // "seconds" label
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: overlay.phase === 3 ? "" : "seconds remaining"
                    font: Style.Theme.monoTFont
                    color: Style.Theme.td
                }
            }

            // ── Progress bar ──
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Style.Theme.bg4

                Rectangle {
                    width: parent.width * overlay.progress
                    height: parent.height
                    radius: parent.radius
                    color: overlay.phase === 3 ? Style.Theme.green : overlay.accent

                    Behavior on width { NumberAnimation { duration: 80 } }
                    Behavior on color { ColorAnimation { duration: 200 } }

                    // Shine effect
                    Rectangle {
                        anchors.right: parent.right
                        width: Math.min(parent.width, 40)
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.25) }
                        }
                    }
                }
            }

            // ── Phase dots ──
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Repeater {
                    model: [{t:"PREPARE", p:1}, {t:"MEASURE", p:2}, {t:"DONE", p:3}]

                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: overlay.phase >= modelData.p
                                   ? (modelData.p === 3 ? Style.Theme.green : overlay.accent)
                                   : Style.Theme.bg4
                            border.width: 1
                            border.color: overlay.phase >= modelData.p
                                          ? "transparent"
                                          : Style.Theme.border2

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            text: modelData.t
                            font: Qt.font({family: "Consolas", pixelSize: 11, bold: true})
                            color: overlay.phase >= modelData.p
                                   ? (modelData.p === 3 ? Style.Theme.green : overlay.accent)
                                   : Style.Theme.td

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }
            }
        }
    }
}
