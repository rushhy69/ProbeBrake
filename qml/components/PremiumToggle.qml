import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   PremiumToggle — Switch with label and hover effects
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 28
    Layout.fillWidth: true

    property string label: ""
    property bool checked: false
    property color accent: Style.Theme.amber
    property string settingsKey: ""

    signal toggled(bool on)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        Text {
            text: root.label.toUpperCase()
            font: Style.Theme.monoTFont
            color: Style.Theme.tg
            Layout.fillWidth: true
        }

        Switch {
            id: sw
            checked: root.checked
            implicitWidth: 40
            implicitHeight: 20

            indicator: Rectangle {
                width: 40; height: 20
                radius: 10
                color: sw.checked ? root.accent : (swHover.hovered ? Style.Theme.bg5 : Style.Theme.bg4)
                border.width: 1
                border.color: sw.checked ? root.accent : (swHover.hovered ? Style.Theme.border3 : Style.Theme.border2)

                Behavior on color { ColorAnimation { duration: Style.Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Style.Theme.animFast } }

                // Glow on hover when checked
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Style.Theme.tw
                    opacity: swHover.hovered && sw.checked ? 0.1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                Rectangle {
                    x: sw.checked ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    radius: 7
                    color: Style.Theme.tw

                    scale: swHover.hovered ? 1.1 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: Style.Theme.animFast; easing.type: Easing.OutCubic } }
                }

                HoverHandler {
                    id: swHover
                    cursorShape: Qt.PointingHandCursor
                }
            }

            onToggled: {
                root.toggled(sw.checked)
                if (root.settingsKey && serialBackend)
                    serialBackend.setSetting(root.settingsKey, JSON.stringify(sw.checked))
            }

            Component.onCompleted: {
                if (root.settingsKey && serialBackend) {
                    var saved = JSON.parse(serialBackend.getSetting(root.settingsKey, JSON.stringify(root.checked)))
                    checked = saved
                }
            }
        }
    }
}
