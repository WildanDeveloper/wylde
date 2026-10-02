#!/usr/bin/env python3
"""Check that a Wylde guest came up as a desktop, not just as a booted kernel.

Drives the serial console: waits for the login prompt, logs in, and asks the
guest about its session. Every check corresponds to something that has actually
gone wrong at some point in this project:

  the GPU driver is missing from the kernel      -> no /sys/class/drm
  udev is not running                            -> no device properties
  init keeps restarting the session              -> more than one compositor
  the compositor starts and then wedges          -> the probe cannot connect
"""
from __future__ import annotations

import re
import sys
import time

LOGIN_DEADLINE = 900
STEP_DEADLINE = 120


class Console:
    def __init__(self, port: int) -> None:
        import socket

        self.sock = socket.create_connection(("127.0.0.1", port), timeout=20)
        self.sock.settimeout(1.0)
        self.chunks: list[str] = []

    def read(self, seconds: float) -> str:
        end = time.time() + seconds
        while time.time() < end:
            try:
                data = self.sock.recv(4096).decode("utf-8", "replace")
            except OSError:
                break
            if not data:
                break
            self.chunks.append(data)
        return "".join(self.chunks)

    def wait_for(self, needle: str, timeout: int) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if needle in self.read(1.0):
                return True
        return needle in "".join(self.chunks)

    def send(self, line: str) -> None:
        self.sock.sendall(line.encode() + b"\n")

    def transcript(self) -> str:
        return "".join(self.chunks)


def main() -> int:
    port = int(sys.argv[1])
    log_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/wylde-desktop-test.log"

    try:
        console = Console(port)
    except OSError as error:
        print(f"desktop-test: cannot reach the serial console: {error}")
        return 1

    failures: list[str] = []
    notes: list[str] = []

    if not console.wait_for("login:", LOGIN_DEADLINE):
        print("desktop-test: the guest never reached a login prompt")
        with open(log_path, "w") as handle:
            handle.write(console.transcript())
        return 1

    console.send("root")
    console.wait_for("Password:", 30)
    console.send("")
    console.wait_for("# ", STEP_DEADLINE)
    notes.append("reached the login prompt")

    def ask(command: str, seconds: int = 60) -> str:
        before = len(console.transcript())
        console.send(command)
        time.sleep(1)
        console.read(seconds)
        text = console.transcript()[before:]
        return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", text)

    def last_number(text: str) -> int | None:
        """The last bare number in a chunk of console output.

        The console echoes the command and prints a prompt afterwards, so the
        final line is never the answer. Taking it anyway is how a guest with a
        perfectly good session gets reported as broken.
        """
        for line in reversed([l.strip() for l in text.splitlines()]):
            if line.isdigit():
                return int(line)
        return None

    def count_of(process: str, seconds: int = 30) -> int:
        """Ask the guest how many processes match, and keep asking for a while.

        A session that is starting is not a session that has failed yet: the
        login prompt appears seconds before the compositor is answering
        clients. Sampling once would report a working desktop as broken.
        """
        end = time.time() + seconds
        answer = 0
        while time.time() < end:
            found = last_number(ask(f"pgrep -c {process}"))
            if found is not None:
                answer = found
                if answer > 0:
                    return answer
            time.sleep(2)
        return answer

    connectors: list[str] = []
    end = time.time() + 120
    while time.time() < end:
        listing = ask("ls /sys/class/drm")
        connectors = re.findall(r"(card\d+-[A-Za-z0-9]+)", listing)
        if connectors:
            break
        time.sleep(2)
    if connectors:
        notes.append(f"graphics: {len(connectors)} connector(s)")
    else:
        failures.append("the kernel exposes no DRM connector: no graphics device")

    if count_of("udevd") > 0:
        notes.append("udev: running")
    else:
        failures.append("udev is not running: no device properties, no input")

    count = count_of("labwc")
    if count == 0:
        failures.append("no compositor is running: the session did not start")
    elif count > 1:
        failures.append(f"{count} compositors are running: init is restarting the session")
    else:
        notes.append("compositor: one labwc")

    if count_of("seatd") > 0:
        notes.append("seat: seatd running")
    else:
        notes.append("seatd: not running (input will not work)")

    found = None
    end = time.time() + 120
    while time.time() < end:
        globals_line = ask(
            "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/0 "
            "wylde-session-probe 2>&1 | tail -1",
            seconds=40,
        )
        found = re.search(r"answered with (\d+) globals", globals_line)
        if found:
            break
        time.sleep(3)
    if found:
        notes.append(f"wayland: the compositor serves {found.group(1)} globals")
    else:
        failures.append("a Wayland client could not talk to the compositor")

    memory = last_number(
        ask("ps -o rss= -C labwc,seatd | awk '{s+=$1} END {print int(s/1024)}'")
    )
    if memory is not None:
        notes.append(f"session memory: {memory} MiB (software rendering)")

    transcript = console.transcript()
    with open(log_path, "w") as handle:
        handle.write(re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", transcript))

    print("desktop session")
    print("----------------")
    for note in notes:
        print(f"  ok       {note}")
    for failure in failures:
        print(f"  FAILED   {failure}")
    print()
    if failures:
        print("a desktop that does not come up is not a desktop")
        return 1
    print("the session came up and serves clients")
    return 0


if __name__ == "__main__":
    sys.exit(main())