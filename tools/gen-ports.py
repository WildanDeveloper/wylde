#!/usr/bin/env python3
"""Generate ports/*/Pkgfile files from a compact spec.

Ports are plain Bash files. Writing forty of them by hand invites typos in
checksums and version strings; this script emits them from a single table and
computes sha256 straight from the source tarballs, so a port can never claim a
checksum that does not match the file it downloads.

Usage:
    python3 tools/gen-ports.py ports.spec           # write Pkgfiles
    python3 tools/gen-ports.py ports.spec --check   # verify sources exist
"""
import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PORTS = REPO / "ports"
SOURCES_CANDIDATES = [Path("/mnt/lfs/sources"), Path("/mnt/lfs/var/lib/wld/sources")]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_source(tarball: str) -> Path | None:
    for base in SOURCES_CANDIDATES:
        candidate = base / tarball
        if candidate.exists():
            return candidate
    return None


def download(url: str, name: str) -> Path:
    """Fetch a source tarball so its real checksum can be recorded."""
    target = SOURCES_CANDIDATES[-1] / name
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"  fetching {url}")
    subprocess.run(
        ["curl", "-fsSL", "--retry", "3", "-o", str(target), url],
        check=True,
    )
    return target


def load_spec(path: Path) -> list[dict]:
    """Spec format: `key=value` fields, several per line, shell line
    continuations with a trailing backslash, and indented continuation lines for
    multi-line values (the build body). Quoted values may contain spaces.
    """
    text = path.read_text()
    # join shell continuations first, keeping indented continuation lines intact
    logical: list[str] = []
    for raw in text.splitlines():
        stripped = raw.rstrip()
        if logical and logical[-1].endswith("\\") and not raw.startswith(" "):
            logical[-1] = logical[-1][:-1] + " " + stripped.lstrip()
        elif raw.startswith(" "):
            body = raw[4:] if raw.startswith("    ") else raw.lstrip()
            logical.append("\x00" + body.rstrip())
        else:
            logical.append(stripped)

    records: list[dict] = []
    current: dict | None = None
    for line in logical:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("\x00"):
            if current is None:
                sys.exit(f"continuation line without a record: {line!r}")
            stripped = line[1:]
            if "build" in current and current["build"]:
                current["build"] += "\n" + stripped
            else:
                key, _, value = stripped.partition("=")
                current[key] += "\n" + value
            continue
        # a line starting with build= belongs to the record above it
        if current is not None and line.startswith("build="):
            rest = split_fields(line)
            body = rest[0].partition("=")[2]
            if len(rest) > 1:
                body += " " + " ".join(rest[1:])
            current["build"] = body
            continue
        if current:
            records.append(current)
        current = {}
        fields = split_fields(line)
        for index, field in enumerate(fields):
            key, _, value = field.partition("=")
            if key == "build":
                # everything after build= on this line is body text; field
                # splitting may chop it at spaces, so rejoin the remainder
                current[key] = value
                if index + 1 < len(fields):
                    current[key] += " " + " ".join(fields[index + 1:])
                break
            current[key] = value
    if current:
        records.append(current)
    return records


def split_fields(line: str) -> list[str]:
    """Split a line into key=value fields, honouring double quotes."""
    fields: list[str] = []
    buffer: list[str] = []
    in_quotes = False
    for char in line:
        if char == '"':
            in_quotes = not in_quotes
            buffer.append(char)
        elif char == " " and not in_quotes:
            if buffer:
                fields.append("".join(buffer))
                buffer = []
        else:
            buffer.append(char)
    if buffer:
        fields.append("".join(buffer))
    return fields


def render(record: dict) -> str:
    name = record["name"]
    version = record["version"]
    source = record["source"]
    lines = [
        f"name={name}",
        f"version={version}",
        f'description={record.get("description", "")}',
        f"license={record.get("license", "")}" if "license" in record else None,
        f"source={source}",
        f"checksum({source})={record['sha256']}",
    ]
    if "depends" in record:
        lines.append(f"depends={record['depends']}")
    lines.append("")
    lines.append("build() {")
    body = record.get("build", "").rstrip()
    body_lines = [line.rstrip() for line in body.splitlines()]
    indents = [len(l) - len(l.lstrip()) for l in body_lines if l.strip()]
    common = min(indents) if indents else 0
    for line in body_lines:
        lines.append(("    " + line[common:]).rstrip() if line.strip() else "")
    lines.append("}")
    return "\n".join(line for line in lines if line is not None) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("spec", type=Path)
    parser.add_argument("--check", action="store_true", help="only verify sources")
    parser.add_argument("--fetch", action="store_true", help="download missing sources")
    args = parser.parse_args()

    records = load_spec(args.spec)
    missing = []
    for record in records:
        tarball = record["source"].rsplit("/", 1)[-1]
        if "$version" in tarball:
            tarball = tarball.replace("$version", record["version"])
        found = find_source(tarball)
        if found is None:
            url = record["source"].replace("$version", record["version"])
            if args.fetch:
                found = download(url, tarball)
            else:
                missing.append((record["name"], tarball))
                continue
        record["sha256"] = sha256(found)

    if missing:
        print("missing sources:")
        for name, tarball in missing:
            print(f"  {name}: {tarball}")
        if args.check:
            return 1

    for record in records:
        if "sha256" not in record:
            continue
        directory = PORTS / record.get("category", "core") / record["name"]
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / "Pkgfile"
        target.write_text(render(record))
        print(f"wrote {target.relative_to(REPO)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
