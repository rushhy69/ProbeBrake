"""
PROBRAKE LC v4.0 — EXE Builder
───────────────────────────────
Run:  python build_exe.py

Requires:  pip install pyinstaller
Output:    dist/ProBrakeLCv4.exe
"""

import PyInstaller.__main__
import os

here = os.path.dirname(os.path.abspath(__file__))
qml_src = os.path.join(here, "qml")

PyInstaller.__main__.run([
    "main.py",
    "--name=ProBrakeLCv4",
    "--onefile",
    "--windowed",                       # no console window
    "--noconfirm",                      # overwrite previous build
    f"--add-data={qml_src};qml",        # bundle entire qml/ tree
    "--hidden-import=PySide6.QtCore",
    "--hidden-import=PySide6.QtGui",
    "--hidden-import=PySide6.QtQml",
    "--hidden-import=PySide6.QtQuick",
    "--hidden-import=PySide6.QtQuickControls2",
    "--hidden-import=PySide6.QtNetwork",
    "--hidden-import=serial",
    "--hidden-import=serial.tools",
    "--hidden-import=serial.tools.list_ports",
    "--collect-all=PySide6",
])
