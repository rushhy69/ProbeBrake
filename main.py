#!/usr/bin/env python3
"""
PROBRAKE LC v4.1 — Control Panel · PySide6/QML Premium Edition
──────────────────────────────────────────────────────────────
GPU-accelerated replacement for the customtkinter GUI.

pip install PySide6 pyserial

Launches the QML UI and exposes a SerialBackend QObject that
bridges Python serial I/O ↔ QML properties/signals.
"""

import sys
import os
import re
import math
import time
import json
import queue
import threading

from PySide6.QtCore import (
    QObject, Property, Signal, Slot, QTimer, QUrl, Qt
)
from PySide6.QtGui import QGuiApplication, QColor, QIcon
from PySide6.QtQml import QQmlApplicationEngine

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial not installed.  Run:  pip install pyserial")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════
#  SERIAL I/O THREAD
# ═══════════════════════════════════════════════════════════
class SerialIO:
    """Threaded serial reader — identical to legacy implementation."""

    def __init__(self):
        self.ser = None
        self.running = False
        self.rx = queue.Queue()
        self._thread = None

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
            self._thread = threading.Thread(target=self._read, daemon=True)
            self._thread.start()
            return True
        except Exception:
            self.ser = None
            return False

    def disconnect(self):
        self.running = False
        if self._thread:
            self._thread.join(timeout=1)
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.ser = None

    def send(self, cmd: str):
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
                        text = line.decode("utf-8", errors="replace").strip()
                        if text:
                            self.rx.put(text)
            except Exception:
                break


# ═══════════════════════════════════════════════════════════
#  BACKEND BRIDGE  (QObject exposed to QML)
# ═══════════════════════════════════════════════════════════
class SerialBackend(QObject):
    """
    Bridges Python serial I/O ↔ QML.
    All properties use Qt property system so QML can bind to them.
    """

    # ── Notify signals for QML property bindings ──────────
    brakeValueChanged = Signal()
    throttleValueChanged = Signal()
    clutchValueChanged = Signal()
    flagTextChanged = Signal()
    flagColorChanged = Signal()
    profileTextChanged = Signal()
    statusTextChanged = Signal()
    statusColorChanged = Signal()
    connectedChanged = Signal()
    portListChanged = Signal()
    logMessage = Signal(str)   # fires for every line to show in console

    def __init__(self, parent=None):
        super().__init__(parent)
        self._io = SerialIO()

        # ── Live telemetry ────────────────────────────────
        self._brake = 0.0
        self._throttle = 0.0
        self._clutch = 0.0
        self._flag_text = "●  NOMINAL"
        self._flag_color = QColor("#22c55e")
        self._profile_text = "Profile  —"
        self._status_text = "OFFLINE"
        self._status_color = QColor("#303050")
        self._connected = False
        self._ports = ["— SELECT PORT —"]

        # ── Demo state ────────────────────────────────────
        self._demo_t = 0.0
        self._telem_count = 0

        # ── GUI settings persistence ─────────────────────
        self._gui_settings = {}
        self._load_settings_from_file()

        # Telemetry regex (same as legacy)
        self._telem_re = re.compile(
            r"P(\d)\s+T:\s*(\d+)%.*?B:\s*(\d+)%(?:.*?C:\s*(\d+)%)?"
        )

        # ── Timers ────────────────────────────────────────
        self._poll_timer = QTimer(self)
        self._poll_timer.setInterval(50)
        self._poll_timer.timeout.connect(self._poll)
        self._poll_timer.start()

        self._demo_timer = QTimer(self)
        self._demo_timer.setInterval(33)   # ~30 fps
        self._demo_timer.timeout.connect(self._run_demo)
        self._demo_timer.start()

        # Initial port scan
        self._refresh_ports()

    # ── QML-readable properties ───────────────────────────
    @Property(float, notify=brakeValueChanged)
    def brakeValue(self):
        return self._brake

    @Property(float, notify=throttleValueChanged)
    def throttleValue(self):
        return self._throttle

    @Property(float, notify=clutchValueChanged)
    def clutchValue(self):
        return self._clutch

    @Property(str, notify=flagTextChanged)
    def flagText(self):
        return self._flag_text

    @Property(QColor, notify=flagColorChanged)
    def flagColor(self):
        return self._flag_color

    @Property(str, notify=profileTextChanged)
    def profileText(self):
        return self._profile_text

    @Property(str, notify=statusTextChanged)
    def statusText(self):
        return self._status_text

    @Property(QColor, notify=statusColorChanged)
    def statusColor(self):
        return self._status_color

    @Property(bool, notify=connectedChanged)
    def connected(self):
        return self._connected

    @Property("QVariantList", notify=portListChanged)
    def portList(self):
        return self._ports

    # ── Invokable from QML ────────────────────────────────
    @Slot(str)
    def sendCommand(self, cmd: str):
        ts = time.strftime("%H:%M:%S")
        self.logMessage.emit(f"[{ts}]  →  {cmd}")
        if self._io.ok:
            self._io.send(cmd)

    @Slot(str)
    def connectPort(self, port: str):
        if "SELECT" in port:
            return
        if self._io.connect(port):
            self._connected = True
            self._status_text = f"●  {port}  115200"
            self._status_color = QColor("#22c55e")
            self.connectedChanged.emit()
            self.statusTextChanged.emit()
            self.statusColorChanged.emit()
            ts = time.strftime("%H:%M:%S")
            self.logMessage.emit(f"[{ts}]  ──  Connected: {port}  ──")
        else:
            self._status_text = "FAILED"
            self._status_color = QColor("#ef4444")
            self.statusTextChanged.emit()
            self.statusColorChanged.emit()

    @Slot()
    def disconnect(self):
        self._io.disconnect()
        self._connected = False
        self._status_text = "OFFLINE"
        self._status_color = QColor("#303050")
        self.connectedChanged.emit()
        self.statusTextChanged.emit()
        self.statusColorChanged.emit()
        ts = time.strftime("%H:%M:%S")
        self.logMessage.emit(f"[{ts}]  ──  Disconnected  ──")

    @Slot()
    def refreshPorts(self):
        self._refresh_ports()

    # ── Internal helpers ──────────────────────────────────
    def _refresh_ports(self):
        ports = SerialIO.ports()
        if ports:
            self._ports = ports
        else:
            self._ports = ["— SELECT PORT —"]
        self.portListChanged.emit()

    def _set_brake(self, v):
        if abs(v - self._brake) > 0.3:
            self._brake = v
            self.brakeValueChanged.emit()

    def _set_throttle(self, v):
        if abs(v - self._throttle) > 0.5:
            self._throttle = v
            self.throttleValueChanged.emit()

    def _set_clutch(self, v):
        if abs(v - self._clutch) > 0.5:
            self._clutch = v
            self.clutchValueChanged.emit()

    # ── Telemetry parser (same regex as legacy) ──────────
    def _parse(self, line: str) -> bool:
        m = self._telem_re.search(line)
        if not m:
            return False

        prof = int(m.group(1))
        tp = int(m.group(2))
        bp = int(m.group(3))
        cp = int(m.group(4)) if m.group(4) else 0

        self._set_throttle(tp)
        self._set_brake(bp)
        self._set_clutch(cp)

        new_prof = f"Profile {prof}"
        if self._profile_text != new_prof:
            self._profile_text = new_prof
            self.profileTextChanged.emit()

        # Check flags
        flags = []
        if "!OVR" in line:
            flags.append("OVERLOAD")
        if "!BF" in line:
            flags.append("BRAKE FAULT")
        if "!TF" in line:
            flags.append("THROTTLE FAULT")
        if "!CF" in line:
            flags.append("CLUTCH FAULT")
        if "[AC]" in line:
            flags.append("AUTO-CAL ACTIVE")

        ft = " · ".join(flags) if flags else "●  NOMINAL"
        fc = QColor("#e8961a") if flags else QColor("#22c55e")

        if ft != self._flag_text:
            self._flag_text = ft
            self._flag_color = fc
            self.flagTextChanged.emit()
            self.flagColorChanged.emit()

        return True

    # ── Poll serial RX queue ─────────────────────────────
    def _poll(self):
        for _ in range(20):
            try:
                line = self._io.rx.get_nowait()
            except queue.Empty:
                break

            is_telem = self._parse(line)
            if is_telem:
                self._telem_count += 1
                if self._telem_count % 10 == 0:
                    ts = time.strftime("%H:%M:%S")
                    self.logMessage.emit(f"[{ts}]  {line}")
            else:
                ts = time.strftime("%H:%M:%S")
                self.logMessage.emit(f"[{ts}]  {line}")

    # ── Demo mode (runs when not connected) ──────────────
    def _run_demo(self):
        if not self._io.ok:
            self._demo_t += 0.08
            t = self._demo_t
            b = max(0, int(48 + 44 * math.sin(t) * math.sin(t * 0.28)))
            tp = max(0, int(38 + 34 * math.cos(t * 0.65)))
            c = max(0, int(22 + 20 * math.sin(t * 0.45 + 1.2)))
            self._set_brake(b)
            self._set_throttle(tp)
            self._set_clutch(c)

    def cleanup(self):
        """Call on app shutdown."""
        self._poll_timer.stop()
        self._demo_timer.stop()
        self._io.disconnect()

    # ── GUI Settings Persistence ─────────────────────────
    def _settings_path(self):
        if getattr(sys, 'frozen', False):
            base = os.path.dirname(sys.executable)
        else:
            base = os.path.dirname(os.path.abspath(__file__))
        return os.path.join(base, 'probrake_settings.json')

    def _load_settings_from_file(self):
        path = self._settings_path()
        if os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    self._gui_settings = json.load(f)
            except Exception:
                self._gui_settings = {}

    @Slot(str, str, result=str)
    def getSetting(self, key, default_json):
        """Get stored GUI setting. Returns JSON string."""
        val = self._gui_settings.get(key)
        if val is not None:
            try:
                return json.dumps(val)
            except (TypeError, ValueError):
                return default_json
        return default_json

    @Slot(str, str)
    def setSetting(self, key, value_json):
        """Store GUI setting from JSON string."""
        try:
            self._gui_settings[key] = json.loads(value_json)
        except (json.JSONDecodeError, TypeError, ValueError):
            self._gui_settings[key] = value_json

    @Slot()
    def saveAllSettings(self):
        """Persist all GUI settings to JSON file."""
        path = self._settings_path()
        try:
            with open(path, 'w') as f:
                json.dump(self._gui_settings, f, indent=2, default=str)
        except Exception as e:
            print(f"Settings save error: {e}")


# ═══════════════════════════════════════════════════════════
#  APPLICATION ENTRY POINT
# ═══════════════════════════════════════════════════════════
def main():
    # Force Basic style so custom control backgrounds render properly
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"

    app = QGuiApplication(sys.argv)
    app.setApplicationName("PROBRAKE LC Control Panel")
    app.setOrganizationName("ProBrake")
    app.setApplicationVersion("4.1")

    # Create backend
    backend = SerialBackend()

    # Create QML engine
    engine = QQmlApplicationEngine()

    # Expose backend to QML as a context property
    engine.rootContext().setContextProperty("serialBackend", backend)

    # Resolve QML path (handle PyInstaller frozen bundle)
    if getattr(sys, 'frozen', False):
        base_dir = sys._MEIPASS
    else:
        base_dir = os.path.dirname(os.path.abspath(__file__))
    qml_dir = os.path.join(base_dir, "qml")
    main_qml = os.path.join(qml_dir, "main.qml")

    # Add import paths so QML can find modules (style, components, pages, panels)
    engine.addImportPath(qml_dir)

    engine.load(QUrl.fromLocalFile(main_qml))

    if not engine.rootObjects():
        print("ERROR: Failed to load QML. Check console for QML errors.")
        sys.exit(1)

    # Wire up backend to root window
    root = engine.rootObjects()[0]
    root.setProperty("backend", backend)

    # Cleanup on exit
    def on_exit():
        backend.cleanup()

    app.aboutToQuit.connect(on_exit)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
