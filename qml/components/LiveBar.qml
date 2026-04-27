import QtQuick
import QtQuick.Layouts
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   LiveBar — Segmented horizontal progress bar with glow tip
   GPU-composited via QML Canvas (replaces tkinter LiveBar)
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 10

    property real value: 0            // 0..100
    property color accent: Style.Theme.amber
    property color accentDim: Style.Theme.amberDim

    // --- smooth animation on value changes ---
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

            // Background track
            ctx.fillStyle = Style.Theme.bg4;
            ctx.fillRect(0, 0, w, h);

            // Segment lines
            ctx.strokeStyle = Style.Theme.bg2;
            ctx.lineWidth = 1;
            for (var i = 1; i < 10; i++) {
                var sx = Math.floor(w * i / 10);
                ctx.beginPath();
                ctx.moveTo(sx, 0);
                ctx.lineTo(sx, h);
                ctx.stroke();
            }

            // Filled portion
            var fw = w * root._animValue / 100;
            if (fw > 0) {
                ctx.fillStyle = root.accent;
                ctx.fillRect(0, 0, fw, h);

                // Top highlight
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.35);
                ctx.fillRect(0, 0, fw, 1);

                // Right glow edge
                ctx.fillStyle = Style.Theme.tw;
                ctx.fillRect(Math.max(0, fw - 2), 0, 2, h);
            }
        }
    }

    on_AnimValueChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
}
