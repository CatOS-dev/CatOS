---
name: catos-qemu-iso-debug
description: Reproduce, inspect, and validate CatOS Linux ISO boot, installer, KDE Plasma first-login, CatOS Hello, and Secure Boot behavior in a disposable QEMU/KVM VM. Use for CatOS ISO release smoke tests, Plasma Welcome/First Run regressions, screenshot-based desktop inspection, or tasks delegated to Luna through devshell-aromatic.
---

# CatOS ISO QEMU debugging (Luna-ready)

## Workspace and safety

- Work in `/home/aromatic/Applications/OwnProject/buildbot` on `aromatic-pc`, with the ISO project at `CatOS/CatOS`. Call `devshell-aromatic` `environ_info` first; use its `bash_run` for short commands, `tmux_run` for long operations, and `todo_report` to report meaningful progress.
- Read `AGENTS.md` in the buildbot workspace before operating. Do not commit/push PKGBUILD changes, run release jobs, alter repositories, reset disks, or deploy without explicit permission. Never use `git clean`/`reset --hard` or edit `.bdd` / `catos-repo` / `catos-stage` by hand.
- Reuse the already maintained `CatOS/CatOS/tools/docs-vm/catos-docs-vm` wrapper. **Do not write a second QEMU launcher.** It implements KVM, UEFI OVMF, `--secure-boot`, qcow2, VNC on localhost, QMP screenshots, `status`, `stop`, and `clean`.
- Use a fresh, dedicated `--state-dir` for each experiment, a free localhost-only `--vnc-port`, and a disposable qcow2. Never test against a physical host drive. `clean` removes only helper runtime state, **not** the qcow2; preserve or remove the test disk only if explicitly allowed.
- Do not claim that a change is verified from an *old* ISO. A new source or staging-package fix must first be present in the booted image or explicitly installed in the guest. For CatOS KDE Welcome, the older `2026.08.05` ISO cannot validate fixes made after August.

## Start a controlled test

Run commands from the **buildbot workspace**:

```bash
cd /home/aromatic/Applications/OwnProject/buildbot
VM="$PWD/CatOS/CatOS/tools/docs-vm/catos-docs-vm"
ISO="$PWD/CatOS/CatOS/out/<actual-new-iso-name>.iso"
STATE="$(mktemp -d "${TMPDIR:-/tmp}/catos-qemu-iso.XXXXXX")"
PORT=5911  # choose an unused localhost TCP port
sha256sum "$ISO"
bsdtar -xOf "$ISO" arch/pkglist.x86_64.txt | grep -E '^(catos-kde-settings|catos-hello) '
"$VM" start --iso "$ISO" --state-dir "$STATE" --vnc-port "$PORT" --memory 6144 --cpus 4
"$VM" status --state-dir "$STATE" --vnc-port "$PORT"
"$VM" wait-resolution --state-dir "$STATE" 180
"$VM" capture --state-dir "$STATE" "$STATE/live-desktop.png"
```

- First inspect `"$VM" help`; check free disk space, `/dev/kvm`, OVMF firmware and whether the port is occupied before starting. The VM defaults to UEFI; add `--secure-boot` to `start` **only for a Secure Boot test**. It enrolls the CatOS certificate from the ISO in VM-local OVMF variables.
- The helper uses VNC `127.0.0.1:$PORT`, never expose it to the public network. For graphical interaction use `"$VM" viewer --state-dir "$STATE" --vnc-port "$PORT"` if a local viewer is available, or `"$VM" vncdo --state-dir "$STATE" --vnc-port "$PORT" -- <vncdotool args>` to automate mouse/keyboard via the wrapper.
- Capture actual QEMU framebuffer evidence using `capture`; do not pass off a resized host window as a real screenshot. The helper enforces 1920 x 1080. If resolution is not ready, use `wait-resolution` and report if it cannot be reached.
- For a first-login issue, install CatOS onto the VM's qcow2 using the GUI, then stop/restart with the **same** state directory and `--boot disk`. This is the required test for `/etc/xdg` and `/etc/skel` post-install policy. A live desktop screenshot alone is not proof of first-login behavior.

## Inspect, capture, and clean up

```bash
"$VM" capture --state-dir "$STATE" "$STATE/first-login.png"
"$VM" status --state-dir "$STATE" --vnc-port "$PORT"
# After finishing installation and shutting down the guest:
"$VM" stop --state-dir "$STATE"
"$VM" start --iso "$ISO" --state-dir "$STATE" --vnc-port "$PORT" --boot disk
# When diagnosis is done:
"$VM" stop --state-dir "$STATE"
"$VM" clean --state-dir "$STATE"
```

- Inspect `$STATE/runtime/serial.log` when useful. Serial logs often omit desktop events; verify KDE state from a terminal **inside the guest** and capture the result. Prefer `kreadconfig6 --file kded5rc --group Module-kded_plasma_welcome --key autoload`, `journalctl --user -b`, and `qdbus6` loaded modules if available. Avoid claiming you obtained guest logs when you only have host QEMU logs.
- Follow `references/acceptance.md` for the first-login, installer, Secure Boot, and NVIDIA ISO checks.
- If starting/controlling QEMU fails, report the specific limitation and keep any partially started VM under control. Do not silently substitute source tests for a full VM acceptance.

## Deliver evidence to the requesting agent

Report: exact ISO path and SHA256, standard/NVIDIA variant, UEFI vs Secure Boot mode, snapshot disk state, VM PID and localhost VNC port, install/first-login results, screenshot paths, relevant guest log excerpts, source/package version verified, cleanup state, and unresolved blockers. State which parts were *not* tested.

For delegation to **Luna**: provide the skill path `CatOS/CatOS/.agents/skills/catos-qemu-iso-debug/SKILL.md`, the ISO path, the explicit scenario (for example: “fresh KDE login must not auto-launch Plasma Welcome; CatOS Hello remains available”), and require Luna to use `devshell-aromatic` and `todo_report` while adhering to this skill. Never authorize release or host configuration edits implicitly.
