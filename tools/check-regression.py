#!/usr/bin/env python3
"""Fail the build when a Wylde system got slower or fatter.

Principle 1 of the project: a release that regresses is rejected. The baseline
is a JSON document of previous measurements; the new one comes from
scripts/benchmark.sh. Both numbers must stay within the allowed growth.

    python3 tools/check-regression.py new.json baseline.json
"""
import json
import sys

# How much a number may grow before the build fails. Boot time in QEMU under TCG
# emulation is noisy, so it gets a wider window than memory.
#
# Boot time is only comparable when both runs used the same accelerator: a guest
# on KVM boots roughly an order of magnitude faster than the same guest under TCG,
# so comparing them would fail a perfectly healthy system (or pass a broken one).
LIMITS = {
    "boot_seconds": 0.20,   # +20 %
    "ram_idle_kib": 0.05,   # +5 %
}


def load(path):
    with open(path) as handle:
        return json.load(handle)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    try:
        new = load(sys.argv[1])
        baseline = load(sys.argv[2])
    except (OSError, json.JSONDecodeError) as error:
        print(f"check-regression: {error}")
        return 2

    print("lean budget")
    print("-----------")
    failures = []

    new_accel = new.get("accel", "unknown")
    base_accel = baseline.get("accel", "unknown")

    for key, allowed in LIMITS.items():
        value = new.get(key)
        previous = baseline.get(key)

        if key == "boot_seconds" and new_accel != base_accel:
            print(
                f"  {key:<16} not comparable: this run used {new_accel}, "
                f"baseline used {base_accel}"
            )
            print(
                f"  {'':<16} measured {value}s on {new_accel}; "
                "memory is still enforced"
            )
            continue

        if value is None or previous in (None, 0):
            print(f"  {key:<16} no baseline, skipping")
            continue

        growth = (value - previous) / previous
        verdict = "ok" if growth <= allowed else "REGRESSION"
        print(
            f"  {key:<16} {value:>12}  baseline {previous:>12}  "
            f"{growth * 100:+.1f}%  (limit +{allowed * 100:.0f}%)  {verdict}"
        )
        if growth > allowed:
            failures.append(key)

    for key in ("ram_total_kib",):
        if new.get(key) and baseline.get(key):
            print(f"  {key:<16} {new[key]:>12}  baseline {baseline[key]:>12}")

    print(f"  {'accel':<16} {new_accel:>12}  baseline {base_accel:>12}")

    if failures:
        print()
        print("regression in: " + ", ".join(failures))
        print("principle 1: a release that regresses is rejected. fix it or justify it.")
        return 1

    print()
    print("within budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
