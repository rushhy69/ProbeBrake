import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   PremiumSlider — Labeled slider with accent value badge
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 42
    Layout.fillWidth: true

    property string label: ""
    property real from: 0
    property real to: 100
    property real value: 50
    property real stepSize: 1
    property color accent: Style.Theme.amber
    property color accentMid: Style.Theme.amberMid
    property string settingsKey: ""

    signal sliderMoved(int val)

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.label.toUpperCase()
                font: Style.Theme.monoTFont
                color: Style.Theme.tg
                Layout.fillWidth: true
            }
            Rectangle {
                width: 44; height: 18
                radius: 3
                color: root.accentMid
                border.width: 1
                border.color: Style.Theme.border3
                Text {
                    anchors.centerIn: parent
                    text: Math.round(slider.value)
                    font: Style.Theme.valFont
                    color: root.accent
                }
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            from: root.from
            to: root.to
            value: root.value
            stepSize: root.stepSize
            implicitHeight: 16

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Style.Theme.bg4

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: root.accent

                    // Glow highlight on hover
                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Style.Theme.tw
                        opacity: hoverHandler.hovered ? 0.15 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 14; height: 14
                radius: 7
                color: slider.pressed ? Style.Theme.tw : root.accent
                border.width: 2
                border.color: slider.pressed ? Style.Theme.tw
                            : hoverHandler.hovered ? Qt.lighter(root.accent, 1.3)
                            : root.accent

                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on border.color { ColorAnimation { duration: 100 } }

                scale: slider.pressed ? 1.2 : (hoverHandler.hovered ? 1.12 : 1.0)
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                // Outer glow ring on hover
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    radius: 11
                    color: "transparent"
                    border.width: hoverHandler.hovered ? 2 : 0
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
                    scale: hoverHandler.hovered ? 1.0 : 0.6
                    opacity: hoverHandler.hovered ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                HoverHandler { id: hoverHandler }
            }

            onMoved: {
                root.sliderMoved(Math.round(value))
                if (root.settingsKey && serialBackend)
                    serialBackend.setSetting(root.settingsKey, JSON.stringify(Math.round(value)))
            }

            Component.onCompleted: {
                if (root.settingsKey && serialBackend) {
                    var saved = JSON.parse(serialBackend.getSetting(root.settingsKey, JSON.stringify(root.value)))
                    value = saved
                }
            }
        }
    }
}
