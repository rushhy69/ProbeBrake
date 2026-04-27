import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   PremiumDropdown — Styled ComboBox with hover effects
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 32
    Layout.fillWidth: true

    property string label: ""
    property var model: []
    property int currentIndex: 0
    property color accent: Style.Theme.amber
    property string settingsKey: ""

    signal activated(string text)

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

        ComboBox {
            id: combo
            model: root.model
            currentIndex: root.currentIndex
            implicitWidth: 150
            implicitHeight: 24
            font: Style.Theme.monoTFont

            background: Rectangle {
                color: combo.hovered ? Style.Theme.bg5 : Style.Theme.bg4
                radius: 4
                border.width: 1
                border.color: combo.hovered ? root.accent : Style.Theme.border2
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on border.color { ColorAnimation { duration: 100 } }
            }

            contentItem: Text {
                leftPadding: 8
                text: combo.displayText
                font: Style.Theme.monoTFont
                color: combo.hovered ? Style.Theme.tw : Style.Theme.tw
                verticalAlignment: Text.AlignVCenter
            }

            popup: Popup {
                y: combo.height
                width: combo.width
                implicitHeight: contentItem.implicitHeight
                padding: 1

                background: Rectangle {
                    color: Style.Theme.bg3
                    radius: 4
                    border.width: 1
                    border.color: Style.Theme.border2
                }

                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: combo.popup.visible ? combo.delegateModel : null
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }

            delegate: ItemDelegate {
                width: combo.width
                height: 28

                background: Rectangle {
                    color: highlighted ? Style.Theme.bg5 : (hovered ? Style.Theme.bg4 : "transparent")
                    Behavior on color { ColorAnimation { duration: 80 } }
                }

                contentItem: Text {
                    text: modelData
                    font: Style.Theme.monoTFont
                    color: highlighted ? root.accent : (hovered ? Style.Theme.tw : Style.Theme.tg)
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8
                }

                highlighted: combo.highlightedIndex === index
            }

            onActivated: function(index) {
                root.activated(combo.textAt(index));
                if (root.settingsKey && serialBackend)
                    serialBackend.setSetting(root.settingsKey, JSON.stringify(index))
            }

            Component.onCompleted: {
                if (root.settingsKey && serialBackend) {
                    var saved = JSON.parse(serialBackend.getSetting(root.settingsKey, JSON.stringify(root.currentIndex)))
                    currentIndex = saved
                }
            }
        }
    }
}
