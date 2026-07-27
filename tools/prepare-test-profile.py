#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


PACMAN_CONFIGS = (
    Path("pacman.conf"),
    Path("airootfs/etc/pacman.conf"),
)


def stage_server(line: str) -> str:
    if "/$arch" not in line:
        raise ValueError(f"CatOS server does not end in /$arch: {line}")
    return line.replace("/$arch", "/catos-stage/$arch", 1)


def add_stage_repository(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    if "[catos-stage]" in content:
        raise ValueError(f"stage repository already exists: {path}")

    match = re.search(r"(?ms)^\[catos\]\n(?P<body>.*?)(?=^\[|\Z)", content)
    if match is None:
        raise ValueError(f"CatOS repository is missing: {path}")

    body_lines = match.group("body").rstrip().splitlines()
    stage_lines = ["[catos-stage]"]
    for line in body_lines:
        if line.startswith("Server = "):
            stage_lines.append(stage_server(line))
        else:
            stage_lines.append(line)
    stage_block = "\n".join(stage_lines).rstrip() + "\n\n"

    content = content[: match.start()] + stage_block + content[match.start() :]
    if content.index("[catos-stage]") > content.index("[catos]"):
        raise ValueError(f"stage repository is not above CatOS: {path}")
    path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    if args.destination.exists():
        shutil.rmtree(args.destination)
    shutil.copytree(args.source, args.destination, symlinks=True)

    for relative in PACMAN_CONFIGS:
        add_stage_repository(args.destination / relative)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
