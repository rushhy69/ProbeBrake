import QtQuick
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   MiniGauge — Radial arc gauge with glowing needle dot
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitWidth: 64
    implicitHeight: 64

    property real value: 0            // 0..100
    property color accent: Style.Theme.amber
    property string label: ""

    property real _animValue: 0
    Behavior on _animValue { NumberAnimation { duration: Style.Theme.animFast; easing.type: Easing.OutCubic } }
    onValueChanged: _animValue = Math.max(0, Math.min(100, value))

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            var w = width, h = height;
            ctx.clearRect(0, 0, w, h);

            var cx = w / 2, cy = h / 2;
            var r = Math.min(cx, cy) - 6;
            var startAngle = (220) * Math.PI / 180;
            var totalSpan = 280 * Math.PI / 180;

            // Outer ring background
            ctx.beginPath();
            ctx.arc(cx, cy, r + 2, 0, 2 * Math.PI);
            ctx.fillStyle = Style.Theme.bg2;
            ctx.fill();
            ctx.strokeStyle = Style.Theme.border2;
            ctx.lineWidth = 1;
            ctx.stroke();

            // Track arc (background)
            ctx.beginPath();
            ctx.arc(cx, cy, r, -startAngle, -(startAngle - totalSpan), true);
            ctx.strokeStyle = Style.Theme.bg4;
            ctx.lineWidth = 4;
            ctx.lineCap = "round";
            ctx.stroke();

            // Active arc
            var span = root._animValue * totalSpan / 100;
            if (span > 0.02) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, -startAngle, -(startAngle - span), true);
                ctx.strokeStyle = root.accent;
                ctx.lineWidth = 3;
                ctx.lineCap = "round";
                ctx.stroke();
            }

            // Needle dot
            var needleAngle = startAngle - span;
            var nx = cx + r * Math.cos(-needleAngle);
            var ny = cy + r * Math.sin(-needleAngle);
            ctx.beginPath();
            ctx.arc(nx, ny, 3, 0, 2 * Math.PI);
            ctx.fillStyle = root.accent;
            ctx.fill();
            ctx.strokeStyle = Style.Theme.tw;
            ctx.lineWidth = 1;
            ctx.stroke();

            // Center value text
            ctx.fillStyle = Style.Theme.tw;
            ctx.font = "bold 17px Consolas";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(Math.round(root._animValue), cx, cy - 2);

            // % sign
            ctx.fillStyle = Style.Theme.tg;
            ctx.font = "13px Consolas";
            ctx.fillText("%", cx, cy + 12);

            // Label below
            ctx.fillStyle = root.accent;
            ctx.font = "bold 13px 'Trebuchet MS'";
            ctx.fillText(root.label, cx, h - 2);
        }
    }

    on_AnimValueChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
