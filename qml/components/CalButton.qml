import QtQuick
import QtQuick.Controls
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   CalButton — Bordered calibration action button with hover
   ═══════════════════════════════════════════════════════════ */
Button {
    id: root
    implicitHeight: 26

    property color accent: Style.Theme.amber
    property color accentDim: Style.Theme.amberDim

    font: Style.Theme.monoTFont

    contentItem: Text {
        text: root.text
        font: root.font
        color: root.hovered ? Style.Theme.tw : root.accent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    background: Rectangle {
        radius: 4
        color: root.pressed ? Style.Theme.border3
             : root.hovered ? Qt.lighter(root.accentDim, 1.4)
             : root.accentDim
        border.width: 1
        border.color: root.hovered ? Qt.lighter(root.accent, 1.2) : root.accent

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }

        scale: root.pressed ? 0.97 : (root.hovered ? 1.02 : 1.0)
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
