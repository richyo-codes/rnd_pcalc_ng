#!/usr/bin/env python3
"""Non-CI X11 smoke test for a built pcalc bundle.

Run under xvfb-run (no window manager), with python-xlib installed.
Checks real window dimensions and resize events, not screenshot goldens.
"""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time

from Xlib import X, display, protocol


def wait_for(check, process, label):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"App exited during {label}: {process.returncode}")
        result = check()
        if result:
            return result
        time.sleep(0.1)
    raise TimeoutError(label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--gtk", choices=["gtk3", "gtk4"], required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    linked = subprocess.check_output(["ldd", str(binary)], text=True)
    expected = "libgtk-4.so" if args.gtk == "gtk4" else "libgtk-3.so"
    forbidden = "libgtk-3.so" if args.gtk == "gtk4" else "libgtk-4.so"
    assert expected in linked and forbidden not in linked, linked
    assert "libwindow_manager_plugin" not in linked, linked
    connection = display.Display()
    screen = connection.screen()
    if screen.width_in_pixels < 1000 or screen.height_in_pixels < 900:
        connection.close()
        raise RuntimeError(
            "Use a virtual display at least 1000x900, e.g. "
            "xvfb-run -a -s '-screen 0 1280x1024x24'. "
            "GTK4 clamps initial size to the monitor."
        )
    environment = {**os.environ, "GDK_BACKEND": "x11", "GDK_SCALE": "1"}
    # Isolate settings from the user's desktop profile.
    with tempfile.TemporaryDirectory(prefix="pcalc-window-") as settings:
        environment["XDG_CONFIG_HOME"] = settings
        with tempfile.TemporaryFile(mode="w+") as log:
            process = subprocess.Popen(
                [str(binary)], cwd=binary.parent, env=environment,
                stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                def find_window():
                    for child in connection.screen().root.query_tree().children:
                        if child.get_wm_name() == "pcalc express":
                            if child.get_attributes().map_state == X.IsViewable:
                                return child
                    return None

                window = wait_for(find_window, process, "window mapping")
                geometry = window.get_geometry()
                print(f"{args.gtk}: mapped X11 surface "
                      f"{geometry.width}x{geometry.height}", flush=True)
                extents = window.get_full_property(
                    connection.intern_atom("_GTK_FRAME_EXTENTS"),
                    X.AnyPropertyType,
                )
                if extents is not None:
                    print(f"GTK frame extents: {list(extents.value)}", flush=True)

                def has_size(width, height):
                    connection.sync()
                    geometry = window.get_geometry()
                    return (geometry.width, geometry.height) == (width, height)

                wait_for(lambda: has_size(620, 800), process, "620x800 startup")
                print(f"{args.gtk}: startup is 620x800", flush=True)
                for width, height in [(900, 650), (360, 640), (620, 800)]:
                    window.configure(width=width, height=height)
                    connection.sync()
                    wait_for(lambda: has_size(width, height), process, "resize")
                    print(f"{args.gtk}: resized to {width}x{height}", flush=True)

                # Allow the first Dart frame/native initialization to complete.
                wait_for(
                    lambda: "Dart VM service is listening" in read_log(log),
                    process, "Flutter debug service",
                )
                time.sleep(2)
                window.send_event(protocol.event.ClientMessage(
                    window=window,
                    client_type=connection.intern_atom("WM_PROTOCOLS"),
                    data=(32, [
                        connection.intern_atom("WM_DELETE_WINDOW"),
                        X.CurrentTime, 0, 0, 0,
                    ]),
                ))
                connection.flush()
                assert process.wait(timeout=10) == 0, "Window close failed"
                output = read_log(log)
                assert "Unhandled Exception" not in output, output
                assert "MissingPluginException" not in output, output
                print(f"{args.gtk}: native close passed", flush=True)
            except Exception:
                print(read_log(log))
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                connection.close()


def read_log(log):
    # pread does not move the file offset shared with the child process.
    return os.pread(log.fileno(), os.fstat(log.fileno()).st_size, 0).decode(
        "utf-8", errors="replace"
    )


if __name__ == "__main__":
    main()
