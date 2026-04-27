import QtQuick
import "../style" as Style

/* ═══════════════════════════════════════════════════════════
   CurveEditor — 10-point draggable LUT with live overlay
   Two-layer rendering: static grid + live overlay
   ═══════════════════════════════════════════════════════════ */
Item {
    id: root
    implicitHeight: 190

    property color accent: Style.Theme.amber
    property color accentDim: Style.Theme.amberDim
    property var lut: [0, 11, 22, 33, 44, 56, 67, 78, 89, 100]
    property real liveInput: 0
    property real liveOutput: 0

    signal lutEdited(var newLut)

    readonly property real _pad: 28

    // Interpolation
    function _interp(inp) {
        var x = inp * 9 / 100.0;
        var i = Math.floor(x);
        if (i >= 9) return lut[9];
        var f = x - i;
        return lut[i] + f * (lut[i + 1] - lut[i]);
    }

    function _px(i)   { return _pad + i * (width - 2 * _pad) / 9 }
    function _py(v)   { return height - _pad - v * (height - 2 * _pad) / 100 }
    function _vx(pct) { return _pad + pct * (width - 2 * _pad) / 100 }
    function _vy(y)   { return Math.max(0, Math.min(100, Math.round((height - _pad - y) * 100 / (height - 2 * _pad)))) }

    onLiveInputChanged: {
        liveOutput = _interp(Math.max(0, Math.min(100, liveInput)));
        liveCanvas.requestPaint();
    }

    // Background (static grid + curve) — redrawn only when LUT changes
    Rectangle {
        anchors.fill: parent
        color: Style.Theme.bg1
        radius: 8
        border.width: 1
        border.color: Style.Theme.border2
    }

    Canvas {
        id: staticCanvas
        anchors.fill: parent
        anchors.margins: 0

        onPaint: {
            var ctx = getContext("2d");
            var w = width, h = height, P = root._pad;
            ctx.clearRect(0, 0, w, h);

            // Grid lines (light)
            ctx.strokeStyle = "#111118";
            ctx.lineWidth = 1;
            for (var pct = 0; pct <= 100; pct += 10) {
                var gy = root._py(pct);
                var gx = root._vx(pct);
                ctx.beginPath(); ctx.moveTo(P, gy); ctx.lineTo(w - P, gy); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(gx, P); ctx.lineTo(gx, h - P); ctx.stroke();
            }

            // Major grid lines
            ctx.strokeStyle = "#181828";
            for (var pct2 = 0; pct2 <= 100; pct2 += 50) {
                var my = root._py(pct2);
                var mx = root._vx(pct2);
                ctx.beginPath(); ctx.moveTo(P, my); ctx.lineTo(w - P, my); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(mx, P); ctx.lineTo(mx, h - P); ctx.stroke();

                // Axis labels
                ctx.fillStyle = "#202040";
                ctx.font = "13px Consolas";
                ctx.textAlign = "right";
                ctx.textBaseline = "middle";
                ctx.fillText(pct2, P - 6, my);
                if (pct2 > 0) {
                    ctx.textAlign = "center";
                    ctx.textBaseline = "top";
                    ctx.fillText(pct2, mx, h - P + 8);
                }
            }

            // Diagonal reference
            ctx.setLineDash([3, 4]);
            ctx.strokeStyle = "#151525";
            ctx.beginPath();
            ctx.moveTo(P, h - P);
            ctx.lineTo(w - P, P);
            ctx.stroke();
            ctx.setLineDash([]);

            // Curve shadow
            ctx.beginPath();
            for (var i = 0; i < 10; i++) {
                var sx = root._px(i) + 2, sy = root._py(root.lut[i]) + 2;
                if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
            }
            ctx.strokeStyle = "#000000";
            ctx.lineWidth = 3;
            ctx.stroke();

            // Curve main
            ctx.beginPath();
            for (var j = 0; j < 10; j++) {
                var cx = root._px(j), cy = root._py(root.lut[j]);
                if (j === 0) ctx.moveTo(cx, cy); else ctx.lineTo(cx, cy);
            }
            ctx.strokeStyle = root.accent;
            ctx.lineWidth = 2;
            ctx.stroke();

            // Control points
            for (var k = 0; k < 10; k++) {
                var px = root._px(k), py = root._py(root.lut[k]);

                // Outer ring
                ctx.beginPath();
                ctx.arc(px, py, 9, 0, 2 * Math.PI);
                ctx.strokeStyle = root.accentDim;
                ctx.lineWidth = 1;
                ctx.stroke();

                // Mid ring
                ctx.beginPath();
                ctx.arc(px, py, 4, 0, 2 * Math.PI);
                ctx.strokeStyle = root.accent;
                ctx.lineWidth = 2;
                ctx.fillStyle = Style.Theme.bg3;
                ctx.fill();
                ctx.stroke();

                // Center dot
                ctx.beginPath();
                ctx.arc(px, py, 2, 0, 2 * Math.PI);
                ctx.fillStyle = root.accent;
                ctx.fill();
            }
        }
    }

    // Live overlay — redrawn every frame, tag-separate
    Canvas {
        id: liveCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            var w = width, h = height, P = root._pad;
            ctx.clearRect(0, 0, w, h);

            var inp = root.liveInput;
            var out = root.liveOutput;
            if (inp < 1) return;

            // Fill polygon
            ctx.globalAlpha = 0.3;
            ctx.beginPath();
            ctx.moveTo(P, h - P);
            for (var s = 0; s <= 10; s++) {
                var ip = Math.min(s * 10, inp);
                var op = root._interp(ip);
                ctx.lineTo(root._vx(ip), root._py(op));
                if (ip >= inp) break;
            }
            var lx = root._vx(inp);
            ctx.lineTo(lx, h - P);
            ctx.closePath();
            ctx.fillStyle = root.accentDim;
            ctx.fill();
            ctx.globalAlpha = 1.0;

            // Crosshair lines
            var ly = root._py(out);
            ctx.setLineDash([2, 3]);
            ctx.strokeStyle = root.accent;
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(lx, h - P); ctx.lineTo(lx, ly); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(P, ly); ctx.lineTo(lx, ly); ctx.stroke();
            ctx.setLineDash([]);

            // Outer glow ring
            ctx.beginPath();
            ctx.arc(lx, ly, 12, 0, 2 * Math.PI);
            ctx.strokeStyle = root.accentDim;
            ctx.lineWidth = 2;
            ctx.stroke();

            // Inner ring
            ctx.beginPath();
            ctx.arc(lx, ly, 7, 0, 2 * Math.PI);
            ctx.strokeStyle = root.accent;
            ctx.lineWidth = 1.5;
            ctx.fillStyle = Style.Theme.bg1;
            ctx.fill();
            ctx.stroke();

            // Center dot
            ctx.beginPath();
            ctx.arc(lx, ly, 3, 0, 2 * Math.PI);
            ctx.fillStyle = Style.Theme.tw;
            ctx.fill();

            // Value tag
            var tagX = Math.min(lx + 16, w - 36);
            ctx.fillStyle = Style.Theme.bg3;
            ctx.strokeStyle = root.accent;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.rect(tagX - 2, ly - 10, 34, 20);
            ctx.fill();
            ctx.stroke();

            ctx.fillStyle = Style.Theme.tw;
            ctx.font = "bold 14px Consolas";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(Math.round(out) + "%", tagX + 15, ly);
        }
    }

    // Drag interaction on control points
    MouseArea {
        anchors.fill: parent
        property int dragging: -1

        onPressed: function(mouse) {
            for (var i = 0; i < 10; i++) {
                if (Math.abs(mouse.x - root._px(i)) < 14 &&
                    Math.abs(mouse.y - root._py(root.lut[i])) < 14) {
                    dragging = i;
                    return;
                }
            }
            dragging = -1;
        }

        onPositionChanged: function(mouse) {
            if (dragging >= 0) {
                var newLut = root.lut.slice();
                newLut[dragging] = root._vy(mouse.y);
                root.lut = newLut;
                staticCanvas.requestPaint();
                liveCanvas.requestPaint();
            }
        }

        onReleased: {
            if (dragging >= 0) {
                dragging = -1;
                root.lutEdited(root.lut.slice());
            }
        }
    }

    onLutChanged: staticCanvas.requestPaint()
    Component.onCompleted: { staticCanvas.requestPaint(); liveCanvas.requestPaint() }
    onWidthChanged:  { staticCanvas.requestPaint(); liveCanvas.requestPaint() }
    onHeightChanged: { staticCanvas.requestPaint(); liveCanvas.requestPaint() }
}
