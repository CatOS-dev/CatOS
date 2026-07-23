from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]


class ReleaseArchisoTests(unittest.TestCase):
    def test_legacy_parameter_script_is_removed(self) -> None:
        self.assertFalse((REPOSITORY / "build-release.sh").exists())

    def test_repository_contains_full_archiso_fork(self) -> None:
        mkarchiso = REPOSITORY / "archiso/archiso/mkarchiso"
        self.assertTrue(mkarchiso.is_file())
        self.assertTrue((REPOSITORY / "archiso/LICENSE").is_file())

    def test_fork_provides_secure_grub_bootmode(self) -> None:
        content = (REPOSITORY / "archiso/archiso/mkarchiso").read_text(encoding="utf-8")
        self.assertIn("_make_bootmode_uefi.grub.secureboot", content)
        self.assertIn("_validate_requirements_bootmode_uefi.grub.secureboot", content)
        self.assertNotIn("usbserial_usbdebug verify video", content)
        self.assertNotIn("_secureboot_build_ukis", content)
        self.assertNotIn("secure_boot_build_uki", content)
        self.assertNotIn("ukify", content)

    def test_profiles_use_secure_bootmode_and_declared_module_packages(self) -> None:
        normal = (REPOSITORY / "catos-iso/profiledef.sh").read_text(encoding="utf-8")
        nvidia = (REPOSITORY / "catos-iso-for-nvidia/profiledef.sh").read_text(encoding="utf-8")

        self.assertIn("uefi.grub.secureboot", normal)
        self.assertIn("secure_boot_module_packages=('broadcom-wl')", normal)
        self.assertNotIn("secure_boot_build_uki", normal)
        self.assertIn("uefi.grub.secureboot", nvidia)
        self.assertIn("secure_boot_module_packages=('broadcom-wl' 'nvidia-open')", nvidia)
        self.assertNotIn("secure_boot_build_uki", nvidia)

    def test_live_profiles_include_secure_boot_manager_for_offline_install(self) -> None:
        for relative in ("catos-iso/packages.x86_64", "catos-iso-for-nvidia/packages.x86_64"):
            packages = (REPOSITORY / relative).read_text(encoding="utf-8").splitlines()
            self.assertEqual(packages.count("catos-secureboot"), 1, relative)


    def test_makefile_is_the_zero_parameter_release_entrypoint(self) -> None:
        content = (REPOSITORY / "Makefile").read_text(encoding="utf-8")
        self.assertIn("iso:", content)
        self.assertIn("iso-nvidia:", content)
        self.assertIn("archiso/archiso/mkarchiso", content)
        self.assertIn("WORK_DIR := /tmp/archiso", content)
        self.assertIn("flock -n", content)
        self.assertIn("trap cleanup EXIT INT TERM", content)
        self.assertNotIn("$(WORK_DIR)/catos", content)
        self.assertNotIn("$(WORK_DIR)/catos-nvidia", content)
        self.assertNotIn("SNAPSHOT_SERVER", content)
        self.assertNotIn("ukify", content)
        self.assertIn("SECURE_BOOT_DIR := ../secureboot", content)
        self.assertNotIn("BUILDBOT_ROOT", content)
        self.assertNotIn("/var/lib/catos-release", content)

    def test_profiles_derive_secure_boot_materials_from_buildbot(self) -> None:
        for relative in ("catos-iso/profiledef.sh", "catos-iso-for-nvidia/profiledef.sh"):
            content = (REPOSITORY / relative).read_text(encoding="utf-8")
            self.assertIn('secure_boot_material_dir="${profile}/../../secureboot"', content)
            self.assertNotIn("/var/lib/catos-release", content)

    def test_vendor_extracts_complete_shim_rpm_before_copying_hardlinks(self) -> None:
        content = (REPOSITORY / "Makefile").read_text(encoding="utf-8")
        extract_line = next(line for line in content.splitlines() if "bsdtar -xf" in line)

        self.assertIn('bsdtar -xf "$(FEDORA_SHIM_RPM)" -C "$(CACHE_DIR)/fedora-shim";', content)
        self.assertNotIn("shimx64.efi", extract_line)
        self.assertNotIn("mmx64.efi", extract_line)
        self.assertNotIn('sudo install -Dm644 "$(CACHE_DIR)/fedora-shim', content)
        self.assertNotIn('sudo test -r "$(SECURE_BOOT_DIR)', content)
        self.assertNotIn('sudo openssl', content)

    def test_vendor_rejects_truncated_or_unsigned_secure_boot_binaries(self) -> None:
        content = (REPOSITORY / "Makefile").read_text(encoding="utf-8")

        self.assertIn(
            "FEDORA_SHIM_BINARY_SHA256 := 571ea56b855dcf73bec6acb63c5ded44c2a191138bca0d8cfa5aa93f60f46fff",
            content,
        )
        self.assertIn(
            "FEDORA_MOK_MANAGER_BINARY_SHA256 := f8af592759c8ab33b69c4b0e772da5a8e2aa6d09c7dbd5e24c62c89fa5fdbd05",
            content,
        )
        self.assertIn("verify_pe_signature()", content)
        self.assertIn("grep -Eq '^signature[[:space:]]+[0-9]+'", content)
        self.assertIn("secure_boot_material_valid()", content)
        self.assertNotIn('@sbverify --list "$(SECURE_BOOT_DIR)/fedora/shimx64.efi" >/dev/null', content)


if __name__ == "__main__":
    unittest.main()
