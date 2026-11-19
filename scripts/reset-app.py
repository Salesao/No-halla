#!/usr/bin/env python3
"""Reset the current user's No-halla installation and reopen onboarding."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time


BUNDLE_ID = "dev.nohalla.NoHalla"
MARKER = b"NOHALLA_LOGIN_ITEM_RESET_OK"
ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/Build/Products/Release/No-halla.app"
HOME = Path.home()
DATA = HOME / "Library/Application Support/NoHalla"
EXTRA = [
    HOME / "Library/Caches" / BUNDLE_ID,
    HOME / "Library/Saved Application State" / (BUNDLE_ID + ".savedState"),
]


def running_processes():
    result = subprocess.run(["/bin/ps", "-axo", "uid=,pid=,comm="], check=True,
                            capture_output=True, text=True)
    found = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) != 3 or int(fields[0]) != os.getuid():
            continue
        command = fields[2]
        if command.endswith("/No-halla.app/Contents/MacOS/No-halla"):
            found.append((int(fields[1]), "app"))
        elif command.endswith("/No-halla.app/Contents/MacOS/NoHallaWatchdog"):
            found.append((int(fields[1]), "watchdog"))
    return found


def check_app():
    executable = APP / "Contents/MacOS/No-halla"
    try:
        with (APP / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if info.get("CFBundleIdentifier") != BUNDLE_ID or not os.access(executable, os.X_OK):
            raise ValueError("unexpected bundle identifier or missing executable")
        if MARKER not in executable.read_bytes():
            raise ValueError("the app was built before reset support was added")
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise RuntimeError(f"Cannot use {APP}: {error}. Run ./scripts/build.sh first.") from error
    return executable


def stop_app():
    for pid, kind in running_processes():
        if kind == "app":
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 30
    while running_processes():
        if time.monotonic() >= deadline:
            raise RuntimeError("No-halla or its watchdog did not exit. No data was deleted; close the app and retry.")
        time.sleep(0.25)


def check_recovery_state():
    path = DATA / "state.json"
    if not path.exists() and not path.is_symlink():
        return
    try:
        with path.open(encoding="utf-8") as file:
            state = json.load(file)
        if not isinstance(state, dict) or state.get("schemaVersion") != 1 or not isinstance(state.get("frozen"), list):
            raise ValueError("unsupported or invalid recovery state")
        if state["frozen"]:
            raise ValueError("the recovery state still contains frozen processes")
    except (OSError, ValueError) as error:
        raise RuntimeError(f"Cannot safely remove {path}: {error}. Recover the processes and retry; the data was kept.") from error


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def reset(executable):
    print("Stopping No-halla and waiting for the watchdog...")
    stop_app()
    if DATA.is_symlink():
        raise RuntimeError(f"Refusing to reset a symlinked data directory: {DATA}")
    DATA.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(DATA / "nohalla.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o644)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("No-halla is still using its data. No data was deleted; retry after it exits.") from error
        if running_processes():
            raise RuntimeError("No-halla or its watchdog restarted. No data was deleted; retry.")
        check_recovery_state()
        print("Disabling launch at login...")
        result = subprocess.run([str(executable), "--reset-login-item"], capture_output=True, text=True, timeout=20)
        if result.returncode != 0 or MARKER.decode() not in result.stdout:
            raise RuntimeError("Could not disable launch at login; data was kept. " + result.stderr.strip())
        print("Removing No-halla settings and user data...")
        defaults = subprocess.run(["/usr/bin/defaults", "read", BUNDLE_ID], capture_output=True)
        if defaults.returncode == 0:
            subprocess.run(["/usr/bin/defaults", "delete", BUNDLE_ID], check=True)
        for child in DATA.iterdir():
            if child.name != "nohalla.lock":
                remove_path(child)
        for path in EXTRA:
            remove_path(path)
    finally:
        os.close(lock_fd)
    print("Opening No-halla...")
    subprocess.run(["/usr/bin/open", str(APP)], check=True)
    print("Reset complete. Onboarding should appear in the app.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="show the planned reset without changing anything")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this script requires macOS")
    try:
        executable = check_app()
        if args.dry_run:
            print(f"App: {APP}\nRunning No-halla processes: {len(running_processes())}")
            print(f"Would stop the app, disable launch at login, and clear {DATA} (keeping the lock file).")
            print("Would clear app preferences, caches and saved window state, then reopen the app.")
            print("The system domain guard and macOS notification permission are retained.")
        else:
            reset(executable)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Reset failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
