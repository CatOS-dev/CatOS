#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import tempfile


BASE_PACKAGES = {
    "catos-calamares",
    "catos-calamares-config",
    "catos-secureboot",
}
EFI_FILES = (
    "EFI/BOOT/BOOTX64.EFI",
    "EFI/BOOT/grubx64.efi",
    "EFI/BOOT/mmx64.efi",
)


def run(*args: str | Path) -> str:
    return subprocess.check_output([str(arg) for arg in args], text=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--certificate", required=True, type=Path)
    parser.add_argument("--require-package", action="append", default=[])
    parser.add_argument("--build-epoch", type=int)
    args = parser.parse_args()

    images = sorted(args.output.glob("*.iso"))
    if len(images) != 1:
        raise RuntimeError(f"expected one ISO in {args.output}, found {len(images)}")
    image = images[0]

    members = set(run("bsdtar", "-tf", image).splitlines())
    required_members = {"arch/pkglist.x86_64.txt", "arch/version", *EFI_FILES}
    missing_members = required_members - members
    if missing_members:
        raise RuntimeError(f"ISO is missing files: {sorted(missing_members)}")

    manifest = run("bsdtar", "-xOf", image, "arch/pkglist.x86_64.txt")
    packages = {line.split(maxsplit=1)[0] for line in manifest.splitlines() if line.strip()}
    required_packages = BASE_PACKAGES | set(args.require_package)
    missing_packages = required_packages - packages
    if missing_packages:
        raise RuntimeError(f"ISO is missing packages: {sorted(missing_packages)}")

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        subprocess.run(
            ["bsdtar", "-xf", str(image), "-C", str(root), *EFI_FILES],
            check=True,
        )
        for relative in EFI_FILES:
            subprocess.run(
                ["sbverify", "--list", str(root / relative)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        subprocess.run(
            [
                "sbverify",
                "--cert",
                str(args.certificate),
                str(root / "EFI/BOOT/grubx64.efi"),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )

    if args.build_epoch is not None:
        built = datetime.fromtimestamp(args.build_epoch, timezone.utc)
        expected_version = built.strftime("%Y.%m.%d")
        expected_label = built.strftime("CATOS_%Y%m%d")
        version = run("bsdtar", "-xOf", image, "arch/version").strip()
        if version != expected_version:
            raise RuntimeError(f"ISO version is {version}, expected {expected_version}")
        pvd = run("xorriso", "-indev", image, "-pvd_info")
        match = re.search(r"(?m)^Volume Id\s*:\s*(\S+)\s*$", pvd)
        label = match.group(1) if match else ""
        if label != expected_label:
            raise RuntimeError(f"ISO label is {label}, expected {expected_label}")

    print(f"validated {image}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
