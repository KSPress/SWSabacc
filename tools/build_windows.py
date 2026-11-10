#!/usr/bin/env python3
"""Build the offline Windows game and a portable ZIP with bundled card art."""
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = sys.argv[1] if len(sys.argv) > 1 else r"E:\godot-windows-64-stable\Godot_v4.7.2-stable_win64_console.exe"
out = ROOT / "build/windows"
out.mkdir(parents=True, exist_ok=True)
subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--log-file", str(out / "export.log"),
                "--export-release", "Windows Desktop", str(out / "SWU_Kyber.exe")], check=True)
for name in ("SWU_Kyber.exe", "SWU_Kyber.pck"):
    if not (out / name).is_file():
        sys.exit(f"Missing Windows build output: {name}")
with zipfile.ZipFile(ROOT / "build/SWU-Kyber-windows.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for name in ("SWU_Kyber.exe", "SWU_Kyber.pck"):
        archive.write(out / name, name)
print("Windows: build/SWU-Kyber-windows.zip (extract both files together)")
