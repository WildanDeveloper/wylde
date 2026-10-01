#!/usr/bin/env python3
"""Cross-check the source files the build unpacks against the pinned list.

A build script that says `tar -xf ncurses-6.5-20250809.tgz` will fail on a clean
machine even though every other check passes — the file simply is not part of
the pinned source set. That failure shows up hours into a CI run, so it is much
cheaper to catch it here.

    python3 tools/check-build-sources.py [sources/wget-list] [sources/extra.list] [build/*.sh]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ARCHIVE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.+-]*\.(?:tar\.(?:gz|xz|bz2|lz)|tgz|tbz2|tbz)")
STAGE = re.compile(r"^\s*(?:simple_stage|stage)\s+(\S+)\s+(\S+)", re.M)

# Files the build creates or fetches itself; they are not part of the pinned
# source set and must be listed here with a reason.
ALLOWED = {
    "linux-6.16.1.tar.xz": "the kernel, fetched by build/05-kernel.sh from its own pin",
    "KV.tar.xz": "built from $KERNEL_VER by 05-kernel.sh, not a literal file name",
}


def pinned_names(*lists: Path) -> set[str]:
    """Basenames of every pinned file, from the book list and our own extras."""
    names: set[str] = set()
    for source in lists:
        if not source.exists():
            continue
        for line in source.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            names.add(fields[0].rsplit("/", 1)[-1])
            # extras may pin the name they are stored under
            if source.name == "extra.list" and len(fields) > 2:
                names.add(fields[2])
    return names


def main() -> int:
    args = sys.argv[1:]
    wget_list = Path(args[0]) if args else Path("sources/wget-list")
    extra = Path(args[1]) if len(args) > 1 else Path("sources/extra.list")
    scripts = [Path(a) for a in args[2:]] or [
        path
        for path in sorted(Path("build").glob("*.sh"))
        # the bootstrap *is* the fetcher; it names files from the pins
        if path.name != "00-bootstrap-host.sh"
    ]

    pinned = pinned_names(wget_list, extra)
    if not pinned:
        print(f"check-build-sources: {wget_list} is empty")
        return 2

    problems: list[tuple[str, str, str]] = []
    checked = 0

    for script in scripts:
        text = script.read_text()
        referenced: set[str] = set(ARCHIVE.findall(text))
        # stage/simple_stage take the tarball as an argument, which may be a glob
        for _name, tarball in STAGE.findall(text):
            referenced.add(tarball)

        for reference in sorted(referenced):
            # only real file names: no paths, heredoc markers or variables
            if reference.startswith(("/", "<<")) or "$" in reference or "/" in reference:
                continue
            if "*" in reference:
                # a glob: at least one pinned file must match it
                import fnmatch

                if any(fnmatch.fnmatch(name, reference) for name in pinned):
                    continue
                problems.append((str(script), reference, "no pinned source matches this glob"))
                continue

            checked += 1
            if reference in pinned or reference in ALLOWED:
                continue
            problems.append((str(script), reference, "not in the pinned source list"))

    print(
        f"build sources: {checked} archive references checked against "
        f"{wget_list} and {extra}"
    )
    if problems:
        print()
        for script, reference, why in problems:
            print(f"  {script}: {reference}")
            print(f"      {why}")
        print()
        print("Fix the name in the build script, or pin the file in sources/.")
        print("A renamed or republished package needs the same treatment in")
        print("build/*.sh as in sources/wget-list; see sources/README.md.")
        return 1

    print("every archive the build unpacks is part of the pinned source set")
    return 0


if __name__ == "__main__":
    sys.exit(main())