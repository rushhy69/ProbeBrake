import QtQuick
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   CurveIcon — Mini curve preset thumbnail with hover + selection
   ═══════════════════════════════════════════════════════════ */
Rectangle {
    id: root
    width: 54; height: 42
    radius: 6
    color: selected ? Style.Theme.bg4
         : iconMouse.containsMouse ? Style.Theme.bg4
         : Style.Theme.bg3
    border.width: 1
    border.color: selected ? accent
                : iconMouse.containsMouse ? Qt.darker(accent, 1.6)
                : Style.Theme.border2

    property int curveId: 0
    property color accent: Style.Theme.amber
    property color accentDim: Style.Theme.amberDim
    property bool selected: false
    property var curveLabels: ["LIN", "PROG", "DEGR", "S", "CUST", "LUT"]

    signal clicked(int cid)

    Behavior on color { ColorAnimation { duration: Style.Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Style.Theme.animFast } }

    // Subtle hover glow
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: iconMouse.containsMouse && !root.selected ? 1 : 0
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
        opacity: iconMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Canvas {
        id: canvas
        width: 42; height: 26
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 3

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var w = 42, h = 26, pad = 4;
            var fg = root.selected ? root.accent
                   : iconMouse.containsMouse ? Qt.lighter(root.accent, 0.6)
                   : "#303050";

            ctx.beginPath();
            for (var i = 0; i < 25; i++) {
                var xn = i / 24;
                var yn;
                switch (root.curveId) {
                    case 0: yn = xn; break;
                    case 1: yn = xn * xn; break;
                    case 2: yn = Math.sqrt(Math.max(0, xn)); break;
                    case 3: yn = xn * xn * (3 - 2 * xn); break;
                    case 4: yn = Math.pow(xn, 1.5); break;
                    default: yn = xn; break;
                }
                var px = pad + xn * (w - 2 * pad);
                var py = (h - pad) - yn * (h - 2 * pad);
                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
            }
            ctx.strokeStyle = fg;
            ctx.lineWidth = root.selected ? 1.5 : 1.0;
            ctx.stroke();

            if (root.selected) {
                ctx.beginPath();
                ctx.arc(pad, h - pad, 2, 0, 2 * Math.PI);
                ctx.fillStyle = fg;
                ctx.fill();
                ctx.beginPath();
                ctx.arc(w - pad, pad, 2, 0, 2 * Math.PI);
                ctx.fillStyle = fg;
                ctx.fill();
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        text: curveLabels[curveId] || ""
        font: Qt.font({family: "Consolas", pixelSize: 12, bold: true})
        color: root.selected ? root.accent
             : iconMouse.containsMouse ? Qt.lighter(root.accent, 0.6)
             : Style.Theme.td

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Hover scale
    scale: iconMouse.containsMouse ? 1.06 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    MouseArea {
        id: iconMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked(root.curveId)
        onContainsMouseChanged: canvas.requestPaint()
    }

    onSelectedChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
