#!/usr/bin/env python3
"""Drive a Wylde guest over serial and measure it.

Writes JSON with:
  boot_seconds  guest /proc/uptime at the login prompt (kernel start -> login)
  ram_total_kib MemTotal
  ram_idle_kib  MemTotal - MemAvailable

Usage: measure.py <port> <output.json> [accel]
"""
import json
import re
import socket
import sys
import time

LOGIN_DEADLINE = 900
STEP_DEADLINE = 240


def main() -> int:
    port = int(sys.argv[1])
    out_path = sys.argv[2]
    accel = sys.argv[3] if len(sys.argv) > 3 else "unknown"

    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    sock.settimeout(1.0)
    text = []

    def read_until(needle: str, timeout: int) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if any(needle in chunk for chunk in text[-3:]):
                return True
            try:
                chunk = sock.recv(4096).decode("utf-8", "replace")
            except socket.timeout:
                continue
            except OSError:
                return False
            if not chunk:
                return False
            text.append(chunk)
        return any(needle in c for c in text[-3:])

    def send(line: str) -> None:
        sock.sendall(line.encode() + b"\n")

    if not read_until("login:", LOGIN_DEADLINE):
        sys.stderr.write("measure: no login prompt\n")
        with open("/tmp/opencode/measure-console.log", "w") as f:
            f.write("".join(text))
        return 1

    send("root")
    read_until("assword:", 60)
    send("")
    read_until("# ", STEP_DEADLINE)

    # one command, one marker, parse the line right before the marker
    send("echo __MEASURE_START__; cat /proc/uptime; cat /proc/meminfo | head -3; echo __MEASURE_END__")
    read_until("__MEASURE_END__", STEP_DEADLINE)
    send("exit")

    blob = "".join(text)
    with open("/tmp/opencode/measure-console.log", "w") as f:
        f.write(blob)

    section = blob.split("__MEASURE_START__")[-1]
    uptime = None
    match = re.search(r"(\d+\.\d+)\s+(\d+\.\d+)", section)
    if match:
        uptime = float(match.group(1))

    total = None
    available = None
    match = re.search(r"MemTotal:\s+(\d+)", section)
    if match:
        total = int(match.group(1))
    match = re.search(r"MemAvailable:\s+(\d+)", section)
    if match:
        available = int(match.group(1))

    result = {
        "accel": accel,
        "boot_seconds": round(uptime, 2) if uptime is not None else None,
        "ram_total_kib": total,
        "ram_idle_kib": (total - available) if total and available else None,
    }
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
