# CatOS ISO QEMU acceptance scenarios

## First login: KDE Welcome vs CatOS Hello

1. Confirm the **tested ISO** actually includes the changed `catos-kde-settings` package; the historical 2026.08.05 ISO cannot verify a new `kded5rc` fix.
2. Install CatOS to the test VM disk with KDE selected, shut down, and reboot the same qcow2 from disk.
3. On the *first installed KDE session*, check that KDE `plasma-welcome` does **not** open automatically. Keep the distinction from login manager, splash, Kickoff application launcher, and CatOS Hello.
4. In a guest Konsole check `kreadconfig6 --file kded5rc --group Module-kded_plasma_welcome --key autoload` returns `false`; verify `/etc/xdg/kded5rc` and that `/usr/bin/plasma-welcome` is still manually executable.
5. Check CatOS Hello remains installed and its autostart source `/etc/skel/.config/autostart/catos-hello.desktop` is present. Observe whether a newly created user sees the intended CatOS Hello page. A single static config check is not equivalent to confirming first-login GUI behavior.
6. Record the first-login desktop screenshot and relevant `journalctl --user -b` lines. If the welcome prompt still appears, distinguish KDE Welcome KDED from CatOS Hello and obtain process/desktop-file identity before changing code.

## Installer and ISO metadata

- Parse `arch/pkglist.x86_64.txt`; verify expected versions and presence of `catos-calamares`, `catos-calamares-config`, `catos-kde-settings`, `catos-hello`.
- Run the maintained `CatOS/CatOS/tools/verify-test-iso.py` when checking a newly built test ISO, passing its required `--certificate` and any required package flags. This checks ISO contents and EFI signatures but **does not** prove GUI behavior.
- Use the virtual disk only; do not touch local host partitions. Preserve installer screenshots for desktop selection, target partition screen, successful installation and first login.

## Secure Boot and NVIDIA

- Test both normal UEFI and `--secure-boot` when requested. The helper provisions a test-only OVMF NVRAM with Microsoft keys and the public CatOS MOK from the selected ISO; never change host Secure Boot keys.
- Select standard or NVIDIA ISO explicitly and include the ISO filename/version in the evidence. Do not conclude that a driver works just because its package is on the ISO; distinguish detection, module loading, and actual graphics session.

## Final report template

Summarize `tested ISO / sha256 / state-dir / scenario / firmware / result / screenshot files / guest logs / cleanup / remaining issues`. Identify whether an issue was reproduced on the live session, on the installed system, or only by static package inspection. Note failed steps truthfully; leave any VM running only when its PID, VNC port, and state dir are documented and the user has requested continued debugging.
