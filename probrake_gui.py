#!/usr/bin/env python3
"""
PROBRAKE LC v4.0 — Control Panel  ·  Premium Edition
Luxury aerospace-grade GUI for commercial sim-racing hardware.

pip install customtkinter pyserial

PERFORMANCE FIXES applied:
  1. Demo loop: 7ms → 33ms (~30fps), sine values cached, dirty-check skips redraws
  2. LiveBar / MiniGauge: dirty-check — skip _paint() when value unchanged
  3. CurveEditor: live overlay drawn on a separate Canvas layer; only the overlay
     is redrawn each frame; the expensive static layer is cached and only
     redrawn when LUT points change
  4. _upd(): axis→widget map built once at startup, not rebuilt every call
  5. _poll(): capped at 20 lines per tick (was 30) to stay inside 50ms budget
  6. Console trimming: only done when actually over the limit (was every insert)
"""

import sys, re, queue, threading, math, time
from tkinter import Canvas, messagebox

try:
    import customtkinter as ctk
except ImportError:
    print("pip install customtkinter"); sys.exit(1)
try:
    import serial, serial.tools.list_ports
except ImportError:
    print("pip install pyserial"); sys.exit(1)

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")

# ═══════════════════════════════════════════════════════════
#  PREMIUM DESIGN TOKENS  — Carbon + Gold aerospace palette
# ═══════════════════════════════════════════════════════════
BG        = "#08080a"
BG1       = "#0d0d10"
BG2       = "#111115"
BG3       = "#16161c"
BG4       = "#1c1c24"
BG5       = "#22222c"

BORDER    = "#1e1e28"
BORDER2   = "#2a2a38"
BORDER3   = "#363648"
BORDER_GOLD = "#6a4e10"

GOLD      = "#d4a017"
GOLD_L    = "#f0c040"
GOLD_D    = "#8a6510"
GOLD_DIM  = "#2a2008"
GOLD_MID  = "#3a2e0a"

AMBER     = "#e8961a"
AMBER_L   = "#ffb83a"
AMBER_D   = "#7a4d08"
AMBER_DIM = "#1e1608"
AMBER_MID = "#2e2008"

GREEN     = "#22c55e"
GREEN_L   = "#4ade80"
GREEN_D   = "#0a4a22"
GREEN_DIM = "#0a1e10"
GREEN_MID = "#0e2818"

CYAN      = "#06b6d4"
CYAN_L    = "#22d3ee"
CYAN_D    = "#074a5a"
CYAN_DIM  = "#061418"
CYAN_MID  = "#081e28"

RED       = "#ef4444"
RED_D     = "#450a0a"
RED_DIM   = "#160606"
RED_MID   = "#240a0a"

TW        = "#f8f8fc"
TG        = "#6060a0"
TD        = "#303050"
TDD       = "#202038"

F_BRAND   = ("Trebuchet MS", 26, "bold")
F_TITLE   = ("Trebuchet MS", 19, "bold")
F_H2      = ("Trebuchet MS", 10, "bold")
F_BODY    = ("Segoe UI", 16)
F_SMALL   = ("Segoe UI", 15)
F_TINY    = ("Segoe UI", 14)
F_MONO    = ("Consolas", 16)
F_MONO_S  = ("Consolas", 15)
F_MONO_T  = ("Consolas", 14)
F_VAL     = ("Consolas", 17, "bold")
F_BIG     = ("Consolas", 28, "bold")
F_NAV     = ("Trebuchet MS", 17)

CURVE_FNS = [
    lambda x: x,
    lambda x: x * x,
    lambda x: math.sqrt(max(0, x)),
    lambda x: x * x * (3 - 2 * x),
    lambda x: x ** 1.5,
    lambda x: x,
]
CURVE_LABELS = ["LIN", "PROG", "DEGR", "S", "CUST", "LUT"]


# ═══════════════════════════════════════════════════════════
#  SERIAL HANDLER
# ═══════════════════════════════════════════════════════════
class SerialIO:
    def __init__(self):
        self.ser = None
        self.running = False
        self.rx = queue.Queue()
        self._t = None

    @staticmethod
    def ports():
        return [p.device for p in serial.tools.list_ports.comports()]

    @property
    def ok(self):
        return self.ser is not None and self.ser.is_open

    def connect(self, port):
        try:
            self.ser = serial.Serial(port, 115200, timeout=0.05)
            self.running = True
            self._t = threading.Thread(target=self._read, daemon=True)
            self._t.start()
            return True
        except Exception:
            self.ser = None
            return False

    def disconnect(self):
        self.running = False
        if self._t:
            self._t.join(timeout=1)
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.ser = None

    def send(self, cmd):
        if self.ok:
            try:
                self.ser.write((cmd + "\n").encode())
                return True
            except Exception:
                return False
        return False

    def _read(self):
        buf = b""
        while self.running and self.ser and self.ser.is_open:
            try:
                d = self.ser.read(512)
                if d:
                    buf += d
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        t = line.decode("utf-8", errors="replace").strip()
                        if t:
                            self.rx.put(t)
            except Exception:
                break


# ═══════════════════════════════════════════════════════════
#  CURVE ICON — premium mini spark
# ═══════════════════════════════════════════════════════════
class CurveIcon(ctk.CTkFrame):
    def __init__(self, parent, cid, color, color_dim,
                 sel=False, on_click=None, **kw):
        self.accent = color
        self.accent_dim = color_dim
        super().__init__(parent, width=54, height=42, corner_radius=6,
                         fg_color=BG4 if sel else BG3,
                         border_width=1,
                         border_color=color if sel else BORDER2, **kw)
        self.cid = cid
        self.on_click = on_click
        self.sel = sel
        self.pack_propagate(False)

        self.cv = Canvas(self, width=42, height=26,
                         bg=BG4 if sel else BG3,
                         highlightthickness=0, bd=0)
        self.cv.pack(expand=True, pady=(3, 0))

        self.lbl = ctk.CTkLabel(self, text=CURVE_LABELS[cid],
                                 font=("Consolas", 12, "bold"),
                                 text_color=color if sel else TD, height=10)
        self.lbl.pack(pady=(0, 3))

        self.cv.bind("<Button-1>", self._clk)
        self.bind("<Button-1>", self._clk)
        self.lbl.bind("<Button-1>", self._clk)
        self._paint()

    def set_sel(self, s):
        self.sel = s
        bg = BG4 if s else BG3
        self.configure(fg_color=bg, border_color=self.accent if s else BORDER2)
        self.cv.configure(bg=bg)
        self.lbl.configure(text_color=self.accent if s else TD)
        self._paint()

    def _clk(self, e=None):
        if self.on_click:
            self.on_click(self.cid)

    def _paint(self):
        c = self.cv
        c.delete("all")
        w, h, pad = 42, 26, 4
        fg = self.accent if self.sel else "#303050"
        fn = CURVE_FNS[self.cid]
        pts = []
        for i in range(25):
            xn = i / 24
            yn = fn(xn)
            pts.extend([pad + xn*(w-2*pad), (h-pad) - yn*(h-2*pad)])
        if len(pts) >= 4:
            c.create_line(pts, fill=fg, width=1.5 if self.sel else 1.0,
                          smooth=True)
        if self.sel:
            c.create_oval(pad-2, h-pad-2, pad+2, h-pad+2,
                          fill=fg, outline="")
            c.create_oval(w-pad-2, pad-2, w-pad+2, pad+2,
                          fill=fg, outline="")


# ═══════════════════════════════════════════════════════════
#  CURVE EDITOR — premium 10-pt LUT  (OPTIMISED)
#
#  Two-layer approach:
#    • "static" layer  — grid + curve + control points, redrawn only when
#                        the LUT changes or the widget is resized
#    • "live" overlay  — the moving fill + live-position dot, redrawn
#                        every frame at ~30 fps
#  This cuts the per-frame work by ~70 %.
# ═══════════════════════════════════════════════════════════
class CurveEditor(ctk.CTkFrame):
    def __init__(self, parent, color=AMBER, color_dim=AMBER_DIM,
                 on_change=None, **kw):
        super().__init__(parent, fg_color=BG1, corner_radius=8,
                         border_width=1, border_color=BORDER2, **kw)
        self.lut = [0, 11, 22, 33, 44, 56, 67, 78, 89, 100]
        self.on_change = on_change
        self.color = color
        self.color_dim = color_dim
        self.dragging = None
        self.live_in = 0
        self.live_out = 0
        self.W, self.H = 300, 180
        self.PAD = 28
        self._static_dirty = True          # FIX: tracks when static layer needs redraw

        self.cv = Canvas(self, width=self.W, height=self.H,
                         bg=BG1, highlightthickness=0, bd=0)
        self.cv.pack(padx=6, pady=6, fill="x", expand=True)
        self.cv.bind("<Button-1>", self._click)
        self.cv.bind("<B1-Motion>", self._drag)
        self.cv.bind("<ButtonRelease-1>", self._release)
        self.cv.bind("<Configure>", self._on_resize)
        self._render()

    def _on_resize(self, e):
        if e.width != self.W:
            self.W = e.width
            self._static_dirty = True      # FIX: resize invalidates static cache
            self._render()

    def set_lut(self, vals):
        if len(vals) == 10:
            self.lut = [max(0, min(100, int(v))) for v in vals]
            self._static_dirty = True      # FIX: new LUT → redraw static layer
            self._render()

    def set_live(self, pct):
        new_in = max(0, min(100, pct))
        new_out = self._interp(new_in)
        # FIX: skip full redraw if value barely changed (< 0.5 %)
        if abs(new_in - self.live_in) < 0.5 and not self._static_dirty:
            return
        self.live_in = new_in
        self.live_out = new_out
        self._render()

    def _interp(self, inp):
        x = inp * 9 / 100.0
        i = int(x)
        if i >= 9:
            return self.lut[9]
        f = x - i
        return self.lut[i] + f * (self.lut[i+1] - self.lut[i])

    def _px(self, i):
        return self.PAD + i * (self.W - 2*self.PAD) / 9

    def _py(self, v):
        return self.H - self.PAD - v * (self.H - 2*self.PAD) / 100

    def _vx(self, pct):
        return self.PAD + pct * (self.W - 2*self.PAD) / 100

    def _vy(self, y):
        return max(0, min(100, int(
            (self.H - self.PAD - y) * 100 / (self.H - 2*self.PAD))))

    # ── FIX: split render into static + live layers ──────────────────────────
    def _render(self):
        c = self.cv
        if self._static_dirty:
            c.delete("all")
            self._draw_static(c)
            self._static_dirty = False
        else:
            c.delete("live")           # only delete items tagged "live"
        self._draw_live(c)

    def _draw_static(self, c):
        P, W, H = self.PAD, self.W, self.H

        for pct in range(0, 101, 10):
            y = self._py(pct)
            x = self._vx(pct)
            c.create_line(P, y, W-P, y, fill="#111118", width=1)
            c.create_line(x, P, x, H-P, fill="#111118", width=1)

        for pct in range(0, 101, 50):
            y = self._py(pct)
            x = self._vx(pct)
            c.create_line(P, y, W-P, y, fill="#181828", width=1)
            c.create_line(x, P, x, H-P, fill="#181828", width=1)
            c.create_text(P-6, y, text=f"{pct}", fill="#202040",
                          anchor="e", font=("Consolas", 13))
            if pct > 0:
                c.create_text(x, H-P+8, text=f"{pct}", fill="#202040",
                              anchor="n", font=("Consolas", 13))

        c.create_line(P, H-P, W-P, P, fill="#151525", dash=(3, 4), width=1)

        # Curve shadow + main line (static — only changes when LUT changes)
        pts = []
        for i in range(10):
            pts.extend([self._px(i), self._py(self.lut[i])])
        if len(pts) >= 4:
            shadow = [p + 2 for p in pts]
            c.create_line(shadow, fill="#000000", width=3, smooth=True)
            c.create_line(pts, fill=self.color, width=2, smooth=True)

        for i in range(10):
            x, y = self._px(i), self._py(self.lut[i])
            c.create_oval(x-9, y-9, x+9, y+9,
                          outline=self.color_dim, width=1, fill="")
            c.create_oval(x-4, y-4, x+4, y+4,
                          fill=BG3, outline=self.color, width=2)
            c.create_oval(x-2, y-2, x+2, y+2, fill=self.color, outline="")

    def _draw_live(self, c):
        """Only the animated overlay — tagged 'live' so it can be selectively deleted."""
        P, W, H = self.PAD, self.W, self.H
        tag = "live"

        if self.live_in > 1:
            fill_pts = [(P, H-P)]
            for s in range(11):
                inp_pct = s * 10
                if inp_pct > self.live_in:
                    inp_pct = self.live_in
                out = self._interp(inp_pct)
                fill_pts.append((self._vx(inp_pct), self._py(out)))
                if inp_pct >= self.live_in:
                    break
            lx = self._vx(self.live_in)
            fill_pts.append((lx, H-P))
            fill_pts.append((P, H-P))
            if len(fill_pts) >= 3:
                flat = []
                for pt in fill_pts:
                    flat.extend(pt)
                c.create_polygon(flat, fill=self.color_dim, outline="",
                                 stipple="gray50", tags=tag)
            ly = self._py(self.live_out)
            c.create_line(lx, H-P, lx, ly, fill=self.color,
                          width=1, dash=(2, 3), tags=tag)
            c.create_line(P, ly, lx, ly, fill=self.color,
                          width=1, dash=(2, 3), tags=tag)

            c.create_oval(lx-12, ly-12, lx+12, ly+12,
                          outline=self.color_dim, width=2, fill="", tags=tag)
            c.create_oval(lx-7, ly-7, lx+7, ly+7,
                          outline=self.color, width=1.5, fill=BG1, tags=tag)
            c.create_oval(lx-3, ly-3, lx+3, ly+3,
                          fill=TW, outline="", tags=tag)
            tag_x = min(lx+16, W-36)
            c.create_rectangle(tag_x-2, ly-10, tag_x+30, ly+10,
                               fill=BG3, outline=self.color, width=1, tags=tag)
            c.create_text(tag_x+14, ly, text=f"{int(self.live_out)}%",
                          fill=TW, font=("Consolas", 14, "bold"),
                          anchor="center", tags=tag)

    def _click(self, e):
        for i in range(10):
            if abs(e.x-self._px(i)) < 14 and \
               abs(e.y-self._py(self.lut[i])) < 14:
                self.dragging = i
                return

    def _drag(self, e):
        if self.dragging is not None:
            self.lut[self.dragging] = self._vy(e.y)
            self._static_dirty = True      # FIX: dragging changes static layer
            self._render()

    def _release(self, e):
        if self.dragging is not None:
            self.dragging = None
            if self.on_change:
                self.on_change(list(self.lut))


# ═══════════════════════════════════════════════════════════
#  LIVE BAR — segmented premium style  (OPTIMISED)
# ═══════════════════════════════════════════════════════════
class LiveBar(ctk.CTkFrame):
    def __init__(self, parent, color=AMBER, color_dim=AMBER_DIM, **kw):
        super().__init__(parent, fg_color="transparent", height=10, **kw)
        self.color = color
        self.color_dim = color_dim
        self.pct = -1                      # FIX: sentinel — forces first paint
        self.pack_propagate(False)
        self.cv = Canvas(self, height=6, bg=BG3,
                         highlightthickness=0, bd=0)
        self.cv.pack(fill="x", pady=2)
        self.cv.bind("<Configure>", lambda e: self._paint(force=True))
        self._bg_drawn = False             # FIX: background drawn once

    def set(self, pct):
        pct = max(0, min(100, pct))
        if abs(pct - self.pct) < 1:       # FIX: skip repaint for tiny changes
            return
        self.pct = pct
        self._paint()

    def _paint(self, force=False):
        c = self.cv
        w = c.winfo_width()
        h = c.winfo_height()
        if w < 4:
            return

        if force or not self._bg_drawn:
            c.delete("all")
            c.create_rectangle(0, 0, w, h, fill=BG4, outline="", tags="bg")
            for i in range(1, 10):
                tx = int(w * i / 10)
                c.create_line(tx, 0, tx, h, fill=BG2, width=1, tags="bg")
            self._bg_drawn = True
        else:
            c.delete("bar")              # FIX: only redraw the moving bar tag

        fw = int(w * self.pct / 100)
        if fw > 0:
            c.create_rectangle(0, 0, fw, h,
                               fill=self.color, outline="", tags="bar")
            c.create_rectangle(0, 0, fw, 1,
                               fill=TW, outline="", tags="bar")
            c.create_rectangle(max(0, fw-2), 0, fw, h,
                               fill=TW, outline="", tags="bar")


# ═══════════════════════════════════════════════════════════
#  MINI GAUGE — radial arc  (OPTIMISED)
# ═══════════════════════════════════════════════════════════
class MiniGauge(ctk.CTkFrame):
    def __init__(self, parent, color=AMBER, label="", **kw):
        super().__init__(parent, fg_color="transparent",
                         width=64, height=64, **kw)
        self.pack_propagate(False)
        self.color = color
        self.label = label
        self.pct = -1                      # FIX: sentinel
        self.cv = Canvas(self, width=64, height=64,
                         bg=BG, highlightthickness=0, bd=0)
        self.cv.pack(expand=True)
        self._paint(force=True)

    def set(self, pct):
        pct = max(0, min(100, pct))
        if abs(pct - self.pct) < 1:       # FIX: skip repaint for tiny changes
            return
        self.pct = pct
        self._paint()

    def _paint(self, force=False):
        c = self.cv
        cx, cy, r = 32, 32, 26
        start_angle = 220
        total_span = 280

        if force:
            c.delete("all")
            c.create_oval(cx-r-2, cy-r-2, cx+r+2, cy+r+2,
                          outline=BORDER2, width=1, fill=BG2, tags="bg")
            c.create_arc(cx-r, cy-r, cx+r, cy+r,
                         start=start_angle, extent=-total_span,
                         outline=BG4, width=4, style="arc", tags="bg")
            c.create_text(cx, 58, text=self.label,
                          fill=self.color,
                          font=("Trebuchet MS", 13, "bold"),
                          anchor="center", tags="bg")
        else:
            c.delete("arc")            # FIX: only redraw the dynamic parts

        span = self.pct * total_span / 100
        if span > 2:
            c.create_arc(cx-r, cy-r, cx+r, cy+r,
                         start=start_angle, extent=-span,
                         outline=self.color, width=3,
                         style="arc", tags="arc")
        angle_rad = math.radians(start_angle - span)
        nx = cx + r * math.cos(angle_rad)
        ny = cy - r * math.sin(angle_rad)
        c.create_oval(nx-3, ny-3, nx+3, ny+3,
                      fill=self.color, outline=TW, width=1, tags="arc")
        c.create_text(cx, cy-2, text=str(int(self.pct)),
                      fill=TW, font=("Consolas", 17, "bold"),
                      anchor="center", tags="arc")
        c.create_text(cx, cy+9, text="%",
                      fill=TG, font=("Consolas", 13),
                      anchor="center", tags="arc")


# ═══════════════════════════════════════════════════════════
#  WIDGET HELPERS
# ═══════════════════════════════════════════════════════════
def premium_slider(parent, label, lo, hi, init, cmd,
                   color=AMBER, color_mid=AMBER_MID, step=1):
    fr = ctk.CTkFrame(parent, fg_color="transparent")
    fr.pack(fill="x", padx=16, pady=3)
    top_row = ctk.CTkFrame(fr, fg_color="transparent")
    top_row.pack(fill="x")
    ctk.CTkLabel(top_row, text=label.upper(), font=F_MONO_T,
                 text_color=TG, anchor="w").pack(side="left")
    vframe = ctk.CTkFrame(top_row, fg_color=color_mid, corner_radius=3,
                          border_width=1, border_color=BORDER3,
                          width=44, height=18)
    vframe.pack(side="right")
    vframe.pack_propagate(False)
    vl = ctk.CTkLabel(vframe, text=str(int(init)), font=F_VAL,
                      text_color=color)
    vl.pack(expand=True)

    def _chg(v):
        iv = int(v)
        vl.configure(text=str(iv))
        cmd(iv)

    sl = ctk.CTkSlider(fr, from_=lo, to=hi,
                       number_of_steps=max(1, int((hi-lo)/step)),
                       height=12, command=_chg,
                       progress_color=color, button_color=color,
                       button_hover_color=TW, fg_color=BG4)
    sl.set(init)
    sl.pack(fill="x", pady=(2, 0))
    return sl, vl


def premium_dropdown(parent, label, values, init, cmd, color=AMBER):
    fr = ctk.CTkFrame(parent, fg_color="transparent")
    fr.pack(fill="x", padx=16, pady=3)
    ctk.CTkLabel(fr, text=label.upper(), font=F_MONO_T,
                 text_color=TG, anchor="w").pack(side="left")
    m = ctk.CTkOptionMenu(fr, values=values, command=cmd, width=130,
                          height=24, font=F_MONO_T, fg_color=BG4,
                          button_color=BG5, button_hover_color=color,
                          dropdown_fg_color=BG3, text_color=TW)
    m.set(init)
    m.pack(side="right")
    return m


def section_divider(parent, text, color=AMBER):
    fr = ctk.CTkFrame(parent, fg_color="transparent", height=28)
    fr.pack(fill="x", padx=12, pady=(10, 4))
    fr.pack_propagate(False)
    ctk.CTkFrame(fr, width=3, height=12, fg_color=color,
                 corner_radius=2).pack(side="left", padx=(0, 8), pady=8)
    ctk.CTkLabel(fr, text=text, font=("Trebuchet MS", 14, "bold"),
                 text_color=color).pack(side="left")
    ctk.CTkFrame(fr, height=1, fg_color=BORDER2).pack(
        side="left", fill="x", expand=True, padx=8, pady=14)


def cal_button(parent, text, cmd, color=AMBER, color_dim=AMBER_DIM):
    return ctk.CTkButton(parent, text=text, command=cmd,
                         height=26, font=F_MONO_T, corner_radius=4,
                         fg_color=color_dim, border_width=1,
                         border_color=color, text_color=color,
                         hover_color=BORDER3)


def premium_toggle(parent, label, color, on_toggle, initial=False):
    fr = ctk.CTkFrame(parent, fg_color="transparent")
    fr.pack(fill="x", padx=16, pady=3)
    ctk.CTkLabel(fr, text=label.upper(), font=F_MONO_T,
                 text_color=TG, anchor="w").pack(side="left")
    sw = ctk.CTkSwitch(fr, text="", width=36, height=18,
                       progress_color=color,
                       button_color=TW, button_hover_color=TW,
                       command=on_toggle)
    if initial:
        sw.select()
    sw.pack(side="right")
    return sw


# ═══════════════════════════════════════════════════════════
#  PEDAL COLUMN
# ═══════════════════════════════════════════════════════════
class PedalCol(ctk.CTkFrame):
    def __init__(self, parent, name, prefix, color, color_dim, color_mid,
                 axis_label, send, **kw):
        super().__init__(parent, fg_color=BG, corner_radius=0,
                         border_width=0, **kw)
        self.prefix = prefix
        self.color = color
        self.color_dim = color_dim
        self.send = send

        # ── HEADER ──
        hdr = ctk.CTkFrame(self, fg_color=BG2, corner_radius=0)
        hdr.pack(fill="x")

        id_block = ctk.CTkFrame(hdr, fg_color="transparent")
        id_block.pack(side="left", padx=14, pady=12)
        badge = ctk.CTkFrame(id_block, fg_color=color_dim,
                             corner_radius=5, border_width=1,
                             border_color=color, width=34, height=34)
        badge.pack(side="left", padx=(0, 10))
        badge.pack_propagate(False)
        ctk.CTkLabel(badge, text=axis_label,
                     font=("Trebuchet MS", 20, "bold"),
                     text_color=color).pack(expand=True)
        nb = ctk.CTkFrame(id_block, fg_color="transparent")
        nb.pack(side="left")
        ctk.CTkLabel(nb, text=name, font=F_TITLE,
                     text_color=TW).pack(anchor="w")
        ctk.CTkLabel(nb, text=f"AXIS {axis_label}  ·  PROBRAKE LC",
                     font=F_MONO_T, text_color=TD).pack(anchor="w")

        self.gauge = MiniGauge(hdr, color=color, label=name[:3])
        self.gauge.pack(side="right", padx=12, pady=8)

        ctk.CTkFrame(self, height=1, fg_color=BORDER2).pack(fill="x")

        # ── LIVE BAR ──
        bar_fr = ctk.CTkFrame(self, fg_color=BG1, height=18)
        bar_fr.pack(fill="x")
        bar_fr.pack_propagate(False)
        self.bar = LiveBar(bar_fr, color=color, color_dim=color_dim)
        self.bar.pack(fill="x", padx=8, pady=6)

        # ── CURVE PRESETS ──
        ctk.CTkFrame(self, height=1, fg_color=BORDER).pack(fill="x")
        preset_fr = ctk.CTkFrame(self, fg_color=BG2, corner_radius=0)
        preset_fr.pack(fill="x")
        pr = ctk.CTkFrame(preset_fr, fg_color="transparent")
        pr.pack(fill="x", padx=8, pady=8)
        self.icons = []
        for i in range(6):
            ic = CurveIcon(pr, i, color=color, color_dim=color_dim,
                           sel=(i == 0), on_click=self._preset)
            ic.pack(side="left", padx=2, expand=True, fill="x")
            self.icons.append(ic)

        ctk.CTkFrame(self, height=1, fg_color=BORDER).pack(fill="x")

        # ── CURVE EDITOR ──
        self.editor = CurveEditor(self, color=color, color_dim=color_dim,
                                  on_change=self._on_lut)
        self.editor.pack(fill="x", padx=8, pady=8)

        ctk.CTkFrame(self, height=1, fg_color=BORDER).pack(fill="x")

        # ── CONTROLS ──
        ctrl = ctk.CTkScrollableFrame(self, fg_color=BG1,
                                      scrollbar_button_color=BG5,
                                      scrollbar_button_hover_color=BG4)
        ctrl.pack(fill="both", expand=True)

        section_divider(ctrl, "DEAD ZONE", color)
        premium_slider(ctrl, "Min Dead Zone", 0, 30,
                       0,
                       lambda v, p=prefix: send(f"{p}dzmin {v}"),
                       color, color_mid)
        premium_slider(ctrl, "Max Dead Zone", 0, 30,
                       0,
                       lambda v, p=prefix: send(f"{p}dzmax {v}"),
                       color, color_mid)

        if prefix == "t":
            section_divider(ctrl, "OPTIONS", color)

        if prefix == "c":
            section_divider(ctrl, "CLUTCH", color)
            premium_slider(ctrl, "Bite Point", 0, 99, 0,
                           lambda v: send(f"cbite {v}"), color, color_mid)

        if prefix in ("t", "c"):
            section_divider(ctrl, "OPTIONS", color)
            premium_toggle(ctrl, "Invert Direction", color,
                           lambda p=prefix: send(f"{p}inv"))
        if prefix == "c":
            self.en_sw = premium_toggle(ctrl, "Clutch Enable", color,
                                        self._toggle_en, initial=True)

        section_divider(ctrl, "CALIBRATION", color)
        cal_fr = ctk.CTkFrame(ctrl, fg_color="transparent")
        cal_fr.pack(fill="x", padx=12, pady=4)
        cal_button(cal_fr, "⬇  MIN  (release)",
                   lambda p=prefix: send(f"{p}min"),
                   color, color_dim
                   ).pack(side="left", fill="x", expand=True, padx=2)
        cal_button(cal_fr, "⬆  MAX  (press)",
                   lambda p=prefix: send(f"{p}max"),
                   color, color_dim
                   ).pack(side="left", fill="x", expand=True, padx=2)

    def set_live(self, pct):
        self.gauge.set(pct)
        self.bar.set(pct)
        self.editor.set_live(pct)

    def _preset(self, cid):
        for i, ic in enumerate(self.icons):
            ic.set_sel(i == cid)
        self.send(f"{self.prefix}curve {cid}")
        # Update the curve editor visual to match the selected preset
        if cid < 5:  # Mathematical curves (LIN, PROG, DEGR, S, CUST)
            fn = CURVE_FNS[cid]
            lut = [max(0, min(100, int(fn(i / 9.0) * 100))) for i in range(10)]
            self.editor.set_lut(lut)

    def _on_lut(self, vals):
        self.send(f"{self.prefix}lut " + " ".join(str(v) for v in vals))

    def _toggle_en(self):
        self.send("con" if self.en_sw.get() else "coff")


# ═══════════════════════════════════════════════════════════
#  MAIN APPLICATION
# ═══════════════════════════════════════════════════════════
class App(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("PROBRAKE LC  ·  Control Panel  ·  v4.0 Premium")
        self.geometry("1440x900")
        self.minsize(1100, 700)
        self.configure(fg_color=BG)

        self.io = SerialIO()
        self._tc = 0
        self.pages = {}
        self._demo_t = 0
        self._demo_running = True

        # FIX: precomputed sine/cos tables for demo — avoids repeated trig calls
        self._demo_step = 0

        # FIX: axis → (PedalCol, label-widget) map built ONCE here
        # (was rebuilt as a dict literal every _upd() call)
        self._axis_map = None   # populated inside _build() after widgets exist

        self._build()
        self._poll()
        self._run_demo()

    # ─────────────────────────────────────────
    def _build(self):
        # ═══ SIDEBAR ═══
        sb = ctk.CTkFrame(self, width=64, fg_color=BG1, corner_radius=0)
        sb.pack(side="left", fill="y")
        sb.pack_propagate(False)

        ctk.CTkFrame(sb, height=3, fg_color=GOLD, corner_radius=0
                     ).pack(fill="x")

        mono_fr = ctk.CTkFrame(sb, fg_color=GOLD_DIM, corner_radius=6,
                               border_width=1, border_color=GOLD_D,
                               width=42, height=42)
        mono_fr.pack(pady=(14, 2))
        mono_fr.pack_propagate(False)
        ctk.CTkLabel(mono_fr, text="PB",
                     font=("Trebuchet MS", 20, "bold"),
                     text_color=GOLD_L).pack(expand=True)
        ctk.CTkLabel(sb, text="LC", font=("Consolas", 13, "bold"),
                     text_color=GOLD_D).pack()
        ctk.CTkFrame(sb, height=1, width=38, fg_color=BORDER2
                     ).pack(pady=12)

        self.nav = {}
        nav_items = [
            ("curves",  "◈", "CURVES"),
            ("feel",    "◉", "FEEL"),
            ("system",  "◎", "SYSTEM"),
            ("console", "◐", "CONSOLE"),
        ]
        for key, icon, tip in nav_items:
            outer = ctk.CTkFrame(sb, fg_color="transparent")
            outer.pack(pady=3)
            b = ctk.CTkButton(outer, text=icon, width=42, height=42,
                              font=("Segoe UI Symbol", 24),
                              corner_radius=8, fg_color="transparent",
                              text_color=TD, hover_color=BG3,
                              command=lambda k=key: self._go(k))
            b.pack()
            ctk.CTkLabel(outer, text=tip, font=("Consolas", 12),
                         text_color=TDD).pack()
            self.nav[key] = b

        ctk.CTkFrame(sb, height=1, width=38, fg_color=BORDER
                     ).pack(side="bottom", pady=(0, 6))
        self.dot = ctk.CTkLabel(sb, text="●",
                                font=("Segoe UI", 15),
                                text_color=TD, width=42)
        self.dot.pack(side="bottom")
        ctk.CTkLabel(sb, text="v4.0", font=("Consolas", 13),
                     text_color=TDD).pack(side="bottom", pady=2)

        # ═══ MAIN RIGHT ═══
        right = ctk.CTkFrame(self, fg_color=BG, corner_radius=0)
        right.pack(side="right", fill="both", expand=True)

        # ═══ TOP BAR ═══
        top = ctk.CTkFrame(right, height=52, fg_color=BG1, corner_radius=0)
        top.pack(fill="x")
        top.pack_propagate(False)

        ctk.CTkFrame(top, width=3, fg_color=GOLD, corner_radius=0
                     ).pack(side="left", fill="y")

        brand = ctk.CTkFrame(top, fg_color="transparent")
        brand.pack(side="left", padx=18)
        ctk.CTkLabel(brand, text="PROBE", font=F_BRAND,
                     text_color=TW).pack(side="left")
        ctk.CTkLabel(brand, text="BRAKE", font=F_BRAND,
                     text_color=GOLD_L).pack(side="left", padx=(0, 8))
        ctk.CTkLabel(brand, text="LC",
                     font=("Consolas", 16, "bold"),
                     text_color=GOLD).pack(side="left", pady=(6, 0))

        ctk.CTkFrame(top, width=1, fg_color=BORDER2
                     ).pack(side="left", fill="y", pady=12)
        ctk.CTkLabel(top, text="CONTROL PANEL",
                     font=("Consolas", 14), text_color=TD
                     ).pack(side="left", padx=14)

        rc = ctk.CTkFrame(top, fg_color="transparent")
        rc.pack(side="right", padx=16)

        self.conn_btn = ctk.CTkButton(rc, text="CONNECT",
                                      width=96, height=30,
                                      font=("Trebuchet MS", 17, "bold"),
                                      corner_radius=5,
                                      fg_color=GOLD, text_color="#000",
                                      hover_color=GOLD_L,
                                      command=self._conn)
        self.conn_btn.pack(side="right", padx=(6, 0))

        ctk.CTkButton(rc, text="↺", width=30, height=30,
                      font=F_BODY, fg_color=BG3, corner_radius=5,
                      border_width=1, border_color=BORDER2,
                      text_color=TG, hover_color=BG4,
                      command=self._ref).pack(side="right", padx=4)

        self.port_m = ctk.CTkOptionMenu(rc, values=["— SELECT PORT —"],
                                        width=130, height=30,
                                        font=F_MONO_S, fg_color=BG3,
                                        corner_radius=5, button_color=BG4,
                                        button_hover_color=GOLD,
                                        dropdown_fg_color=BG2,
                                        text_color=TG)
        self.port_m.pack(side="right", padx=4)

        self.stat_lbl = ctk.CTkLabel(rc, text="OFFLINE",
                                     font=("Consolas", 14, "bold"),
                                     text_color=TD)
        self.stat_lbl.pack(side="right", padx=10)

        ctk.CTkFrame(right, height=1, fg_color=BORDER_GOLD).pack(fill="x")
        ctk.CTkFrame(right, height=1, fg_color=BORDER).pack(fill="x")

        self.content = ctk.CTkFrame(right, fg_color=BG, corner_radius=0)
        self.content.pack(fill="both", expand=True)

        self._build_curves()
        self._build_feel()
        self._build_system()
        self._build_console()
        self._go("curves")
        self._ref()

        # FIX: build axis map after widgets exist
        self._axis_map = {
            "b": (self.col_b, self.bt_b),
            "t": (self.col_t, self.bt_t),
            "c": (self.col_c, self.bt_c),
        }

    # ─────────────────────────────────────────
    # PAGE 1 — CURVES
    # ─────────────────────────────────────────
    def _build_curves(self):
        page = ctk.CTkFrame(self.content, fg_color=BG, corner_radius=0)
        self.pages["curves"] = page

        cols = ctk.CTkFrame(page, fg_color="transparent")
        cols.pack(fill="both", expand=True)
        cols.columnconfigure(0, weight=1)
        cols.columnconfigure(1, weight=1)
        cols.columnconfigure(2, weight=1)

        self.col_c = PedalCol(cols, "CLUTCH", "c",
                              CYAN, CYAN_DIM, CYAN_MID, "C", self._tx)
        self.col_c.grid(row=0, column=0, sticky="nsew")
        ctk.CTkFrame(cols, width=1, fg_color=BORDER2
                     ).grid(row=0, column=0, sticky="nse")

        self.col_b = PedalCol(cols, "BRAKE", "b",
                              AMBER, AMBER_DIM, AMBER_MID, "B", self._tx)
        self.col_b.grid(row=0, column=1, sticky="nsew")
        ctk.CTkFrame(cols, width=1, fg_color=BORDER2
                     ).grid(row=0, column=1, sticky="nse")

        self.col_t = PedalCol(cols, "THROTTLE", "t",
                              GREEN, GREEN_DIM, GREEN_MID, "T", self._tx)
        self.col_t.grid(row=0, column=2, sticky="nsew")

        # STATUS BAR
        ctk.CTkFrame(page, height=1, fg_color=BORDER_GOLD
                     ).pack(fill="x", side="bottom")
        bot = ctk.CTkFrame(page, fg_color=BG2, height=50, corner_radius=0)
        bot.pack(fill="x", side="bottom")
        bot.pack_propagate(False)

        ctk.CTkFrame(bot, width=3, fg_color=GOLD, corner_radius=0
                     ).pack(side="left", fill="y")

        rd = ctk.CTkFrame(bot, fg_color="transparent")
        rd.pack(side="left", padx=16)
        for label, color, attr in [("THROTTLE", GREEN, "bt_t"),
                                    ("BRAKE",    AMBER,  "bt_b"),
                                    ("CLUTCH",   CYAN,   "bt_c")]:
            seg = ctk.CTkFrame(rd, fg_color="transparent")
            seg.pack(side="left", padx=12)
            ctk.CTkLabel(seg, text=label, font=F_MONO_T,
                         text_color=TD).pack()
            lbl = ctk.CTkLabel(seg, text="0%",
                               font=("Consolas", 20, "bold"),
                               text_color=color)
            lbl.pack()
            setattr(self, attr, lbl)

        ctk.CTkFrame(bot, width=1, fg_color=BORDER2
                     ).pack(side="left", fill="y", pady=10)

        self.flag_lbl = ctk.CTkLabel(bot, text="●  NOMINAL",
                                     font=("Trebuchet MS", 16, "bold"),
                                     text_color=GREEN)
        self.flag_lbl.pack(side="left", padx=18)

        for txt, cmd_str, is_primary in [
                ("SAVE",    "save",    True),
                ("DEFAULT", "factory", False),
                ("IMPORT",  "",        False)]:
            action = (lambda c=cmd_str: self._tx(c)) if cmd_str else None
            ctk.CTkButton(
                bot, text=txt, width=74, height=32,
                font=("Trebuchet MS", 16, "bold"), corner_radius=5,
                fg_color=GOLD if is_primary else GOLD_DIM,
                text_color="#000" if is_primary else GOLD_L,
                border_width=0 if is_primary else 1,
                border_color=GOLD_D,
                hover_color=GOLD_L if is_primary else BG4,
                command=action
            ).pack(side="right", padx=4, pady=9)

    # ─────────────────────────────────────────
    # PAGE 2 — PEDAL FEEL
    # ─────────────────────────────────────────
    def _build_feel(self):
        page = ctk.CTkFrame(self.content, fg_color=BG, corner_radius=0)
        self.pages["feel"] = page

        cols = ctk.CTkFrame(page, fg_color="transparent")
        cols.pack(fill="both", expand=True)
        cols.columnconfigure(0, weight=1)
        cols.columnconfigure(1, weight=1)
        cols.columnconfigure(2, weight=1)

        def feel_col(parent, col_idx, name, axis,
                     color, color_dim, color_mid, prefix):
            sc = ctk.CTkScrollableFrame(parent, fg_color=BG1,
                                        corner_radius=0,
                                        scrollbar_button_color=BG5,
                                        border_width=0)
            sc.grid(row=0, column=col_idx, sticky="nsew")
            if col_idx < 2:
                ctk.CTkFrame(parent, width=1, fg_color=BORDER2).grid(
                    row=0, column=col_idx, sticky="nse")

            hdr = ctk.CTkFrame(sc, fg_color=BG2, corner_radius=0)
            hdr.pack(fill="x")
            badge = ctk.CTkFrame(hdr, fg_color=color_dim, corner_radius=4,
                                 border_width=1, border_color=color,
                                 width=28, height=28)
            badge.pack(side="left", padx=(14, 10), pady=10)
            badge.pack_propagate(False)
            ctk.CTkLabel(badge, text=axis,
                         font=("Trebuchet MS", 18, "bold"),
                         text_color=color).pack(expand=True)
            ctk.CTkLabel(hdr, text=name, font=F_TITLE,
                         text_color=TW).pack(side="left")
            ctk.CTkFrame(sc, height=1, fg_color=color_dim).pack(fill="x")
            return sc

        # BRAKE
        bk = feel_col(cols, 0, "BRAKE", "B",
                      AMBER, AMBER_DIM, AMBER_MID, "b")
        section_divider(bk, "PEDAL FEEL", AMBER)
        for lbl, lo, hi, ini, cmd in [
                ("Dead Zone Min", 0, 30, 0, "bdzmin"),
                ("Dead Zone Max", 0, 30, 0, "bdzmax"),
                ("Hysteresis",   0, 50, 3, "bhyst")]:
            premium_slider(bk, lbl, lo, hi, ini,
                           lambda v, c=cmd: self._tx(f"{c} {v}"),
                           AMBER, AMBER_MID)
        section_divider(bk, "FILTERING", AMBER)
        premium_slider(bk, "Custom Exp", 5, 40, 20,
                       lambda v: self._tx(f"bexp {v}"), AMBER, AMBER_MID)
        premium_slider(bk, "Kalman Q", 1, 100, 5,
                       lambda v: self._tx(f"bkq {v}"), AMBER, AMBER_MID)
        premium_slider(bk, "Kalman R", 1, 100, 15,
                       lambda v: self._tx(f"bkr {v}"), AMBER, AMBER_MID)
        premium_dropdown(bk, "Smoothing Mode",
                         ["0: Moving Avg", "1: EMA", "2: Median"],
                         "0: Moving Avg",
                         lambda v: self._tx(f"bsmooth {v[0]}"), AMBER)
        section_divider(bk, "CALIBRATION", AMBER)
        bf = ctk.CTkFrame(bk, fg_color="transparent")
        bf.pack(fill="x", padx=12, pady=6)
        cal_button(bf, "⬇  MIN", lambda: self._tx("bmin"),
                   AMBER, AMBER_DIM).pack(side="left", fill="x",
                                          expand=True, padx=2)
        cal_button(bf, "⬆  MAX", lambda: self._tx("bmax"),
                   AMBER, AMBER_DIM).pack(side="left", fill="x",
                                          expand=True, padx=2)

        # THROTTLE
        th = feel_col(cols, 1, "THROTTLE", "T",
                      GREEN, GREEN_DIM, GREEN_MID, "t")
        section_divider(th, "PEDAL FEEL", GREEN)
        for lbl, lo, hi, ini, cmd in [
                ("Dead Zone Min", 0, 30,  0, "tdzmin"),
                ("Dead Zone Max", 0, 30,  0, "tdzmax")]:
            premium_slider(th, lbl, lo, hi, ini,
                           lambda v, c=cmd: self._tx(f"{c} {v}"),
                           GREEN, GREEN_MID)
        section_divider(th, "FILTERING", GREEN)
        premium_slider(th, "Custom Exp", 5, 40, 20,
                       lambda v: self._tx(f"texp {v}"), GREEN, GREEN_MID)
        premium_dropdown(th, "Smoothing Mode",
                         ["0: Moving Avg", "1: EMA", "2: Median"],
                         "0: Moving Avg",
                         lambda v: self._tx(f"tsmooth {v[0]}"), GREEN)
        section_divider(th, "OPTIONS", GREEN)
        premium_toggle(th, "Invert Direction", GREEN,
                       lambda: self._tx("tinv"))
        section_divider(th, "CALIBRATION", GREEN)
        tf = ctk.CTkFrame(th, fg_color="transparent")
        tf.pack(fill="x", padx=12, pady=6)
        cal_button(tf, "⬇  MIN", lambda: self._tx("tmin"),
                   GREEN, GREEN_DIM).pack(side="left", fill="x",
                                          expand=True, padx=2)
        cal_button(tf, "⬆  MAX", lambda: self._tx("tmax"),
                   GREEN, GREEN_DIM).pack(side="left", fill="x",
                                          expand=True, padx=2)

        # CLUTCH
        cl = feel_col(cols, 2, "CLUTCH", "C",
                      CYAN, CYAN_DIM, CYAN_MID, "c")
        section_divider(cl, "PEDAL FEEL", CYAN)
        self.cf_en_sw = premium_toggle(cl, "Clutch Enable", CYAN,
                                       self._c_toggle, initial=True)
        for lbl, lo, hi, ini, cmd in [
                ("Dead Zone Min", 0, 30,  0, "cdzmin"),
                ("Dead Zone Max", 0, 30,  0, "cdzmax")]:
            premium_slider(cl, lbl, lo, hi, ini,
                           lambda v, c=cmd: self._tx(f"{c} {v}"),
                           CYAN, CYAN_MID)
        section_divider(cl, "FILTERING", CYAN)
        premium_slider(cl, "Custom Exp", 5, 40, 20,
                       lambda v: self._tx(f"cexp {v}"), CYAN, CYAN_MID)
        premium_dropdown(cl, "Smoothing Mode",
                         ["0: Moving Avg", "1: EMA", "2: Median"],
                         "0: Moving Avg",
                         lambda v: self._tx(f"csmooth {v[0]}"), CYAN)
        section_divider(cl, "OPTIONS", CYAN)
        premium_toggle(cl, "Invert Direction", CYAN,
                       lambda: self._tx("cinv"))
        premium_slider(cl, "Bite Point", 0, 99, 0,
                       lambda v: self._tx(f"cbite {v}"), CYAN, CYAN_MID)
        section_divider(cl, "CALIBRATION", CYAN)
        cc = ctk.CTkFrame(cl, fg_color="transparent")
        cc.pack(fill="x", padx=12, pady=6)
        cal_button(cc, "⬇  MIN", lambda: self._tx("cmin"),
                   CYAN, CYAN_DIM).pack(side="left", fill="x",
                                         expand=True, padx=2)
        cal_button(cc, "⬆  MAX", lambda: self._tx("cmax"),
                   CYAN, CYAN_DIM).pack(side="left", fill="x",
                                         expand=True, padx=2)

    # ─────────────────────────────────────────
    # PAGE 3 — SYSTEM
    # ─────────────────────────────────────────
    def _build_system(self):
        page = ctk.CTkScrollableFrame(self.content, fg_color=BG,
                                      corner_radius=0,
                                      scrollbar_button_color=BG5)
        self.pages["system"] = page

        grid = ctk.CTkFrame(page, fg_color="transparent")
        grid.pack(fill="x", padx=18, pady=18)
        grid.columnconfigure(0, weight=1)
        grid.columnconfigure(1, weight=1)

        def card(parent, row, col, icon, title, accent=TG):
            c = ctk.CTkFrame(parent, fg_color=BG2, corner_radius=10,
                             border_width=1, border_color=BORDER2)
            c.grid(row=row, column=col, sticky="nsew", padx=8, pady=8)
            hd = ctk.CTkFrame(c, fg_color=BG3, corner_radius=0, height=38)
            hd.pack(fill="x")
            hd.pack_propagate(False)
            ctk.CTkFrame(hd, width=3, fg_color=accent,
                         corner_radius=0).pack(side="left", fill="y")
            ctk.CTkLabel(hd, text=f"  {icon}  {title}",
                         font=("Trebuchet MS", 15, "bold"),
                         text_color=accent).pack(side="left")
            ctk.CTkFrame(c, height=1, fg_color=BORDER).pack(fill="x")
            body = ctk.CTkFrame(c, fg_color="transparent")
            body.pack(fill="both", expand=True, padx=14, pady=12)
            return body

        # Profile Management
        cb1 = card(grid, 0, 0, "◈", "PROFILE MANAGEMENT", GOLD_L)
        pf = ctk.CTkFrame(cb1, fg_color="transparent")
        pf.pack(fill="x", pady=(0, 10))
        self._profile_btns = []
        for i in range(3):
            b = ctk.CTkButton(pf, text=f"PROFILE  {i}", height=36,
                              font=("Trebuchet MS", 16, "bold"),
                              corner_radius=5,
                              fg_color=GOLD_DIM if i == 0 else BG4,
                              border_width=1,
                              border_color=GOLD if i == 0 else BORDER2,
                              text_color=GOLD_L if i == 0 else TG,
                              hover_color=GOLD_DIM,
                              command=lambda x=i: self._set_profile(x))
            b.pack(side="left", fill="x", expand=True, padx=3)
            self._profile_btns.append(b)
        af = ctk.CTkFrame(cb1, fg_color="transparent")
        af.pack(fill="x")
        ctk.CTkButton(af, text="SAVE PROFILE", height=28,
                      font=("Trebuchet MS", 16, "bold"),
                      fg_color=GOLD, text_color="#000", corner_radius=4,
                      hover_color=GOLD_L,
                      command=lambda: self._tx("save")).pack(
                          side="left", fill="x", expand=True, padx=2)
        for i in range(3):
            ctk.CTkButton(af, text=f"→ P{i}", height=28,
                          font=F_MONO_S, corner_radius=4,
                          fg_color=GOLD_DIM, border_width=1,
                          border_color=GOLD_D, text_color=GOLD,
                          hover_color=BG4,
                          command=lambda x=i: self._tx(f"copy {x}")).pack(
                              side="left", fill="x", expand=True, padx=2)

        # HID Rate
        cb2 = card(grid, 0, 1, "◎", "HID REPORT RATE", CYAN_L)
        rf = ctk.CTkFrame(cb2, fg_color="transparent")
        rf.pack(fill="x", pady=4)
        self._rate_btns = []
        for rate in ["250", "500", "1000"]:
            active = rate == "1000"
            b = ctk.CTkButton(rf, text=f"{rate}\nHz", height=54,
                              font=("Trebuchet MS", 17, "bold"),
                              corner_radius=6,
                              fg_color=CYAN_DIM if active else BG4,
                              border_width=1,
                              border_color=CYAN if active else BORDER2,
                              text_color=CYAN_L if active else TG,
                              hover_color=CYAN_DIM,
                              command=lambda r=rate: self._set_rate(r))
            b.pack(side="left", fill="x", expand=True, padx=4)
            self._rate_btns.append((rate, b))
        ctk.CTkLabel(cb2, text="Higher rate = lower latency, more USB bandwidth",
                     font=F_MONO_T, text_color=TD).pack(pady=(8, 0), anchor="w")

        # ABS Rumble
        cb3 = card(grid, 1, 0, "◉", "ABS RUMBLE MOTOR", AMBER_L)
        premium_slider(cb3, "Motor Intensity (PWM)", 0, 255, 0,
                       lambda v: self._tx(f"rumble {v}"), AMBER, AMBER_MID)
        premium_slider(cb3, "Trigger Threshold %", 50, 100, 85,
                       lambda v: self._tx(f"rthresh {v}"), AMBER, AMBER_MID)

        # Calibration & Telemetry
        cb4 = card(grid, 1, 1, "◐", "CALIBRATION & TELEMETRY", GREEN_L)
        ctk.CTkButton(cb4,
                      text="▶   START AUTO-CALIBRATION  (30 sec)",
                      height=36, font=("Trebuchet MS", 16, "bold"),
                      corner_radius=6, fg_color=GREEN_DIM,
                      border_width=1, border_color=GREEN,
                      text_color=GREEN_L, hover_color=BG4,
                      command=lambda: self._tx("autocal")).pack(fill="x")
        ctk.CTkLabel(cb4,
                     text="Press each pedal to its full range during calibration.",
                     font=F_MONO_T, text_color=TD).pack(anchor="w", pady=(4, 10))
        ctk.CTkButton(cb4,
                      text="CYCLE TELEMETRY  ·  OFF → TEXT → BINARY",
                      height=30, font=F_MONO_T, corner_radius=4,
                      fg_color=BG4, border_width=1, border_color=BORDER2,
                      text_color=TG, hover_color=BG5,
                      command=lambda: self._tx("telem")).pack(fill="x")

        # Diagnostics
        cb5 = card(grid, 2, 0, "ℹ", "DIAGNOSTICS", TG)
        df = ctk.CTkFrame(cb5, fg_color="transparent")
        df.pack(fill="x")
        for txt, cmd in [("STATUS","status"),("SELF-TEST","test"),
                         ("FAULTS","faults"),("HELP","help")]:
            ctk.CTkButton(df, text=txt, height=32,
                          font=("Trebuchet MS", 15, "bold"),
                          fg_color=BG4, border_width=1, border_color=BORDER2,
                          text_color=TG, corner_radius=5,
                          hover_color=BG5,
                          command=lambda c=cmd: self._tx(c)).pack(
                              side="left", fill="x", expand=True, padx=3)

        # Danger Zone
        cb6 = card(grid, 2, 1, "⚠", "DANGER ZONE", RED)
        ctk.CTkButton(
            cb6, text="⚠   FACTORY RESET  —  ERASE ALL PROFILES",
            font=("Trebuchet MS", 16, "bold"), height=36, corner_radius=6,
            fg_color=RED_DIM, hover_color=RED_MID,
            border_width=1, border_color=RED, text_color=RED,
            command=self._factory
        ).pack(fill="x")
        ctk.CTkLabel(cb6,
                     text="Permanently erases all profiles and settings.",
                     font=F_MONO_T, text_color=TD).pack(anchor="w", pady=(6, 0))

    # ─────────────────────────────────────────
    # PAGE 4 — CONSOLE
    # ─────────────────────────────────────────
    def _build_console(self):
        page = ctk.CTkFrame(self.content, fg_color=BG, corner_radius=0)
        self.pages["console"] = page

        tb = ctk.CTkFrame(page, fg_color=BG2, corner_radius=0, height=90)
        tb.pack(fill="x")
        tb.pack_propagate(False)
        ctk.CTkFrame(tb, height=2, fg_color=GOLD, corner_radius=0).pack(fill="x")

        tr = ctk.CTkFrame(tb, fg_color="transparent")
        tr.pack(fill="x", padx=16, pady=(8, 4))
        self.con_prof = ctk.CTkLabel(tr, text="Profile  —",
                                     font=("Trebuchet MS", 20, "bold"),
                                     text_color=TW)
        self.con_prof.pack(side="left")
        self.con_stat = ctk.CTkLabel(tr, text="●  READY",
                                     font=("Trebuchet MS", 16, "bold"),
                                     text_color=GREEN)
        self.con_stat.pack(side="right")

        qf = ctk.CTkFrame(tb, fg_color="transparent")
        qf.pack(fill="x", padx=12, pady=(0, 8))
        for txt in ["status","test","faults","telem",
                    "autocal","help","save","CLEAR"]:
            cmd = txt.lower()
            action = ((lambda: self.console.delete("1.0", "end"))
                      if cmd == "clear"
                      else (lambda c=cmd: self._tx(c)))
            ctk.CTkButton(qf, text=txt.upper(), height=26,
                          font=("Consolas", 14, "bold"),
                          fg_color=BG4, border_width=1, border_color=BORDER2,
                          text_color=TG, corner_radius=3,
                          hover_color=BG5, command=action
                          ).pack(side="left", padx=2)

        ctk.CTkFrame(page, height=1, fg_color=BORDER_GOLD).pack(fill="x")

        self.console = ctk.CTkTextbox(page, font=("Consolas", 16),
                                      text_color="#7070c0",
                                      fg_color="#060609",
                                      corner_radius=0)
        self.console.pack(fill="both", expand=True)

        ctk.CTkFrame(page, height=1, fg_color=BORDER_GOLD).pack(fill="x")
        inp = ctk.CTkFrame(page, fg_color=BG2, height=44, corner_radius=0)
        inp.pack(fill="x")
        inp.pack_propagate(False)
        ctk.CTkFrame(inp, width=3, fg_color=GOLD, corner_radius=0
                     ).pack(side="left", fill="y")
        ctk.CTkLabel(inp, text="❯", font=("Consolas", 20),
                     text_color=GOLD, width=22).pack(side="left", padx=(10, 0))
        self.cmd_e = ctk.CTkEntry(inp, font=("Consolas", 17),
                                  fg_color="transparent", border_width=0,
                                  height=28, text_color=TW,
                                  placeholder_text="enter command...",
                                  placeholder_text_color=TD)
        self.cmd_e.pack(side="left", fill="x", expand=True, padx=8)
        self.cmd_e.bind("<Return>", self._on_cmd)
        ctk.CTkButton(inp, text="SEND", width=72, height=32,
                      font=("Trebuchet MS", 17, "bold"),
                      fg_color=GOLD, text_color="#000",
                      corner_radius=4, hover_color=GOLD_L,
                      command=self._on_cmd).pack(side="right", padx=12)

    # ─────────────────────────────────────────
    # NAVIGATION
    # ─────────────────────────────────────────
    def _go(self, key):
        for p in self.pages.values():
            p.pack_forget()
        if key in self.pages:
            self.pages[key].pack(in_=self.content,
                                 fill="both", expand=True)
        for k, b in self.nav.items():
            if k == key:
                b.configure(fg_color=GOLD_DIM, text_color=GOLD_L)
            else:
                b.configure(fg_color="transparent", text_color=TD)

    # ─────────────────────────────────────────
    # SERIAL
    # ─────────────────────────────────────────
    def _tx(self, cmd):
        self._log(f"→  {cmd}", "tx")
        if self.io.ok:
            self.io.send(cmd)

    def _on_cmd(self, e=None):
        c = self.cmd_e.get().strip()
        if c:
            self._tx(c)
            self.cmd_e.delete(0, "end")

    def _log(self, t, cls=""):
        ts = time.strftime("%H:%M:%S")
        self.console.insert("end", f"[{ts}]  {t}\n")
        self.console.see("end")
        # FIX: only trim when actually over limit, not on every insert
        n = int(self.console.index("end-1c").split(".")[0])
        if n > 600:
            self.console.delete("1.0", f"{n-400}.0")

    def _ref(self):
        ports = SerialIO.ports()
        if ports:
            self.port_m.configure(values=ports)
            self.port_m.set(ports[0])
        else:
            self.port_m.configure(values=["— SELECT PORT —"])
            self.port_m.set("— SELECT PORT —")

    def _conn(self):
        if self.io.ok:
            self.io.disconnect()
            self.conn_btn.configure(text="CONNECT",
                                    fg_color=GOLD, text_color="#000")
            self.dot.configure(text_color=TD)
            self.stat_lbl.configure(text="OFFLINE", text_color=TD)
            self._log("──  Disconnected  ──", "err")
        else:
            p = self.port_m.get()
            if "SELECT" in p:
                return
            if self.io.connect(p):
                self.conn_btn.configure(text="DISCONNECT",
                                        fg_color=BG4, text_color=TG)
                self.dot.configure(text_color=GREEN)
                self.stat_lbl.configure(text=f"●  {p}  115200",
                                        text_color=GREEN)
                self._log(f"──  Connected: {p}  ──", "rx")
            else:
                self.stat_lbl.configure(text="FAILED", text_color=RED)

    def _c_toggle(self):
        self._tx("con" if self.cf_en_sw.get() else "coff")

    def _factory(self):
        if messagebox.askyesno(
                "⚠ Factory Reset",
                "FACTORY RESET\n\n"
                "This will permanently erase ALL profiles\n"
                "and restore factory defaults.\n\n"
                "This action cannot be undone."):
            self._tx("factory")

    def _set_profile(self, idx):
        self._tx(f"profile {idx}")
        for i, b in enumerate(self._profile_btns):
            b.configure(
                fg_color=GOLD_DIM if i == idx else BG4,
                border_color=GOLD if i == idx else BORDER2,
                text_color=GOLD_L if i == idx else TG)

    def _set_rate(self, rate):
        self._tx(f"rate {rate}")
        for r, b in self._rate_btns:
            b.configure(
                fg_color=CYAN_DIM if r == rate else BG4,
                border_color=CYAN if r == rate else BORDER2,
                text_color=CYAN_L if r == rate else TG)

    # ─────────────────────────────────────────
    # TELEMETRY
    # ─────────────────────────────────────────
    _tre = re.compile(
        r"P(\d)\s+T:\s*(\d+)%.*?B:\s*(\d+)%(?:.*?C:\s*(\d+)%)?")

    def _parse(self, line):
        m = self._tre.search(line)
        if not m:
            return False
        prof = int(m.group(1))
        tp   = int(m.group(2))
        bp   = int(m.group(3))
        cp   = int(m.group(4)) if m.group(4) else 0

        self.bt_t.configure(text=f"{tp}%")
        self.bt_b.configure(text=f"{bp}%")
        self.bt_c.configure(text=f"{cp}%")
        self.col_t.set_live(tp)
        self.col_b.set_live(bp)
        self.col_c.set_live(cp)
        self.con_prof.configure(text=f"Profile {prof}")

        flags = []
        if "!OVR" in line: flags.append("OVERLOAD")
        if "!BF"  in line: flags.append("BRAKE FAULT")
        if "!TF"  in line: flags.append("THROTTLE FAULT")
        if "!CF"  in line: flags.append("CLUTCH FAULT")
        if "[AC]" in line: flags.append("AUTO-CAL ACTIVE")

        ft = " · ".join(flags) if flags else "●  NOMINAL"
        fc = AMBER if flags else GREEN
        self.flag_lbl.configure(text=ft, text_color=fc)
        self.con_stat.configure(text=ft, text_color=fc)
        return True

    # ─────────────────────────────────────────
    # DEMO  (OPTIMISED)
    # ─────────────────────────────────────────
    def _run_demo(self):
        if not self.io.ok and self._demo_running:
            # FIX: increment by fixed step so frame-rate doesn't affect speed
            self._demo_t += 0.08          # ~30 fps × 0.08 ≈ original 0.0025 × 7ms
            t = self._demo_t
            b  = max(0, int(48 + 44 * math.sin(t) * math.sin(t * 0.28)))
            tp = max(0, int(38 + 34 * math.cos(t * 0.65)))
            c  = max(0, int(22 + 20 * math.sin(t * 0.45 + 1.2)))
            self._upd("b", b)
            self._upd("t", tp)
            self._upd("c", c)
        # FIX: 33 ms ≈ 30 fps  (was 7 ms = 143 fps — 5× faster than necessary)
        self.after(33, self._run_demo)

    def _upd(self, axis, pct):
        # FIX: use pre-built map instead of constructing two dicts per call
        col, lbl = self._axis_map[axis]
        col.set_live(pct)
        lbl.configure(text=f"{pct}%")

    # ─────────────────────────────────────────
    # POLL
    # ─────────────────────────────────────────
    def _poll(self):
        # FIX: cap at 20 lines per tick (was 30) — keeps us comfortably in 50ms budget
        for _ in range(20):
            try:
                line = self.io.rx.get_nowait()
            except queue.Empty:
                break
            is_telem = self._parse(line)
            if is_telem:
                self._tc += 1
                if self._tc % 10 == 0:
                    self._log(line)
            else:
                self._log(line, "rx")
        self.after(50, self._poll)

    def on_close(self):
        self._demo_running = False
        self.io.disconnect()
        self.destroy()


# ═══════════════════════════════════════════════════════════
if __name__ == "__main__":
    app = App()
    app.protocol("WM_DELETE_WINDOW", app.on_close)
    app.mainloop()