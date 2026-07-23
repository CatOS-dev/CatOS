# CatOS ISO Secure Boot materials

The repository contains no private signing material. Official ISO builds use a fixed build-machine layout:

From the `CatOS/CatOS` repository, the fixed relative location is `../secureboot`:

```text
../secureboot/
├── catos-release.crt
├── catos-release.key
└── fedora/
    ├── mmx64.efi
    └── shimx64.efi
```

`catos-release.key` must be readable by the dedicated build account and inaccessible to group and other users (`0600`). The build itself runs `mkarchiso` through `sudo`, but `make doctor` validates the key as the invoking build account before privilege escalation. `shimx64.efi` and `mmx64.efi` must come from the same Fedora-signed shim build.

The CatOS archiso fork performs all signing after the live root has been assembled:

1. package-owned Broadcom and NVIDIA external modules are signed;
2. initramfs is regenerated so it contains the signed module copies;
3. the ordinary live kernel copied to the ISO is signed;
4. GRUB is built with shim lock enabled, a CatOS SBAT component and an embedded configuration;
5. GRUB and the live kernel are signed with the CatOS release certificate;
6. Fedora shim, matching MokManager, the CatOS certificate and signed GRUB are written into the EFI image;
7. every required signature is verified before the ISO is emitted.

The live medium keeps the normal archiso layout: GRUB loads a separate signed `vmlinuz-*` and external `initramfs-*.img`. The fork does not generate or add a UKI.

A release build has no required arguments:

```text
make iso
make iso-nvidia
```

`make doctor` validates tools, key permissions, certificate/key matching, and vendor EFI signatures without creating an ISO.
