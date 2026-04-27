import QtQuick
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   SectionDivider — Accent bar + label + horizontal line
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 28
    Layout.fillWidth: true

    property string text: ""
    property color accent: Style.Theme.amber

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        Rectangle {
            width: 3; height: 12
            radius: 2
            color: root.accent
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root.text
            font: Qt.font({family: "Trebuchet MS", pixelSize: 14, bold: true})
            color: root.accent
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Style.Theme.border2
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
