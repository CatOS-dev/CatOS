# CatOS documentation VM

This directory contains a CLI harness for reproducible CatOS installer and desktop screenshots. It boots the release ISO under QEMU/KVM without a host display window and exposes the guest framebuffer through a localhost-only VNC server.

The documentation baseline is **1920x1080**. QEMU advertises that resolution through the virtio-gpu EDID, and every accepted capture is checked against QEMU's real guest framebuffer dimensions. A scaled `remote-viewer` window therefore cannot accidentally produce a non-1080p documentation screenshot.

## Requirements

- QEMU/KVM (`qemu-system-x86_64`, `qemu-img`, `/dev/kvm`)
- `edk2-ovmf`
- ImageMagick (`magick`)
- `bsdtar`
- `uv`
- optional `remote-viewer` for interactive debugging

`vncdotool` is run through `uvx`, so it does not need to be installed into the system Python environment.

## Start a fresh installation VM

From the main CatOS repository:

```bash
tools/docs-vm/catos-docs-vm start --reset-disk
tools/docs-vm/catos-docs-vm wait-resolution 180
```

The default ISO is `out/catos-2026.08.05-x86_64.iso`. Use another image with `--iso PATH`.

The virtual disk and OVMF variables live under `~/.cache/catos-docs-vm/default/`, outside the Git checkout.

## Capture an exact 1920x1080 framebuffer

```bash
tools/docs-vm/catos-docs-vm capture /tmp/catos-live.png
```

The command uses QMP `screendump`, converts the raw framebuffer to PNG, and fails instead of saving the image if the framebuffer is not exactly 1920x1080. VNC is used for keyboard and mouse automation only, so heavy installer I/O cannot stall documentation captures.

For documentation images, point the output directly at the website checkout, for example:

```bash
tools/docs-vm/catos-docs-vm capture \
  ../catos-website/static/img/docs/install-current/live-desktop.png
```

## Automate keyboard and mouse input

The `vncdo` subcommand forwards commands to `vncdotool`:

```bash
tools/docs-vm/catos-docs-vm vncdo move 960 540 click 1
tools/docs-vm/catos-docs-vm vncdo key ctrl-l type 'example' key enter
```

With a fixed 1920x1080 framebuffer, installer page controls can be addressed using stable coordinates. A capture can also be used as an `expect` reference before continuing a flow.

For debugging only, an interactive viewer can be opened with:

```bash
tools/docs-vm/catos-docs-vm viewer
```

The documentation screenshot itself should still be produced with `capture`, not with a host desktop screenshot utility.

## Regenerate the complete offline-installation screenshot set

The tested flow can be run end-to-end without opening a host GUI:

```bash
tools/docs-vm/capture-offline-installation
```

It creates a fresh 64 GiB virtual disk, waits for the Live desktop, closes the welcome windows, opens the offline installer, fills a documentation-only test account, selects erase-disk on the virtual disk, runs the installation, and captures the ten images currently referenced by the offline-installation guide.

By default the images replace:

```text
../catos-website/static/img/docs/install_catos_01.png
...
../catos-website/static/img/docs/install_catos_10.png
```

Every image is captured through QMP and individually verified as 1920x1080. The script only erases its disposable qcow2 virtual disk; it never presents a host block device to the guest.

## Boot the installed disk

After installation finishes, stop the VM and start it with the disk preferred:

```bash
tools/docs-vm/catos-docs-vm stop
tools/docs-vm/catos-docs-vm start --boot disk
```

The ISO remains attached for convenience, while `bootindex` and the firmware boot order prefer the virtual disk.

## Secure Boot test VM

Use a separate state directory so its NVRAM and virtual disk never mix with the normal documentation VM:

```bash
tools/docs-vm/catos-docs-vm start \
  --secure-boot \
  --reset-disk \
  --state-dir ~/.cache/catos-docs-vm/secureboot
```

On a fresh Secure Boot state directory, the harness uses `virt-fw-vars` through `uvx` to create a real Secure Boot-enabled OVMF variable store. It enrolls Microsoft's platform/KEK/db certificates so the Fedora-signed shim is trusted, extracts the **public** `catos-release.cer` from the selected CatOS ISO, and places that certificate in the shim MOK database. No CatOS private signing key is read or copied by the test harness.

This makes the Live ISO boot under actual Secure Boot rather than OVMF Setup Mode. It has been validated inside the CatOS Live environment with:

```bash
mokutil --sb-state
```

which reports `SecureBoot enabled`.

MokManager screenshots and installed-system enrollment testing should keep using this separate state directory so UEFI variable changes persist across required reboots. Firmware and MokManager screens may use their own pre-OS resolution; the **desktop and documentation screenshots remain strictly 1920x1080** once the graphical session starts.

## Stop and clean runtime files

```bash
tools/docs-vm/catos-docs-vm stop
tools/docs-vm/catos-docs-vm clean
```

`clean` removes only the transient socket/log/PID directory. It deliberately keeps the qcow2 disk and OVMF variables; use `--reset-disk` on the next `start` when a completely fresh installation target is required.
