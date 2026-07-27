SHELL := /usr/bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(CURDIR)
ARCHISO := $(ROOT)/archiso/archiso/mkarchiso
OUT_DIR := $(ROOT)/out
WORK_DIR := /tmp/archiso
BUILD_LOCK := /tmp/catos-archiso.lock
TEST_OUT_DIR := $(OUT_DIR)/test
TEST_WORK_DIR := /tmp/catos-archiso-test
TEST_BUILD_LOCK := /tmp/catos-archiso-test.lock
TEST_PROFILE_DIR := $(ROOT)/.catos-iso-test
CACHE_DIR := $(ROOT)/.cache
BUILD_EPOCH := $(shell git -C "$(ROOT)" log -1 --format=%ct)
OWNER := $(shell id -u):$(shell id -g)
SECURE_BOOT_DIR := ../secureboot
FEDORA_SHIM_RPM := $(CACHE_DIR)/shim-x64-16.1-5.x86_64.rpm
FEDORA_SHIM_URL := https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/Packages/s/shim-x64-16.1-5.x86_64.rpm
FEDORA_SHIM_SHA256 := a1bbabaca8e4398b2483c678240f4be4803e91390b512a7b618da3bc88e49917
FEDORA_SHIM_BINARY_SHA256 := 571ea56b855dcf73bec6acb63c5ded44c2a191138bca0d8cfa5aa93f60f46fff
FEDORA_MOK_MANAGER_BINARY_SHA256 := f8af592759c8ab33b69c4b0e772da5a8e2aa6d09c7dbd5e24c62c89fa5fdbd05
SECURE_BOOT_FILES := \
	$(SECURE_BOOT_DIR)/fedora/shimx64.efi \
	$(SECURE_BOOT_DIR)/fedora/mmx64.efi \
	$(SECURE_BOOT_DIR)/catos-release.key \
	$(SECURE_BOOT_DIR)/catos-release.crt
HOST_COMMANDS := \
	arch-chroot awk bsdtar curl depmod find flock gzip grub-mkstandalone install mkfs.fat \
	mcopy mmd modinfo openssl pacstrap python3 sbverify sbsign sha256sum stat xorriso xz zstd

.PHONY: all iso iso-nvidia test vendor doctor check clean distclean

all: iso

iso: doctor
	@mkdir -p "$(OUT_DIR)"
	@flock -n "$(BUILD_LOCK)" sudo bash -eu -o pipefail -c '\
		cleanup() { rm -rf -- "$(WORK_DIR)"; }; \
		trap cleanup EXIT INT TERM; \
		cleanup; \
		env SOURCE_DATE_EPOCH="$(BUILD_EPOCH)" TZ=UTC \
			"$(ARCHISO)" -v -w "$(WORK_DIR)" -o "$(OUT_DIR)" "$(ROOT)/catos-iso"; \
		chown -R "$(OWNER)" "$(OUT_DIR)"'

iso-nvidia: doctor
	@mkdir -p "$(OUT_DIR)"
	@flock -n "$(BUILD_LOCK)" sudo bash -eu -o pipefail -c '\
		cleanup() { rm -rf -- "$(WORK_DIR)"; }; \
		trap cleanup EXIT INT TERM; \
		cleanup; \
		env SOURCE_DATE_EPOCH="$(BUILD_EPOCH)" TZ=UTC \
			"$(ARCHISO)" -v -w "$(WORK_DIR)" -o "$(OUT_DIR)" "$(ROOT)/catos-iso-for-nvidia"; \
		chown -R "$(OWNER)" "$(OUT_DIR)"'

vendor:
	@verify_pe_signature() { \
		local output; \
		output="$$(sbverify --list "$$1" 2>&1)" || return 1; \
		grep -Eq '^signature[[:space:]]+[0-9]+' <<<"$$output"; \
	}; \
	verify_file_hash() { \
		test -r "$$2" && printf '%s  %s\n' "$$1" "$$2" | sha256sum -c - >/dev/null 2>&1; \
	}; \
	secure_boot_material_valid() { \
		verify_file_hash "$(FEDORA_SHIM_BINARY_SHA256)" "$(SECURE_BOOT_DIR)/fedora/shimx64.efi" && \
		verify_pe_signature "$(SECURE_BOOT_DIR)/fedora/shimx64.efi" && \
		verify_file_hash "$(FEDORA_MOK_MANAGER_BINARY_SHA256)" "$(SECURE_BOOT_DIR)/fedora/mmx64.efi" && \
		verify_pe_signature "$(SECURE_BOOT_DIR)/fedora/mmx64.efi"; \
	}; \
	mkdir -p "$(CACHE_DIR)"; \
	if ! verify_file_hash "$(FEDORA_SHIM_SHA256)" "$(FEDORA_SHIM_RPM)"; then \
		curl -fL --retry 3 -o "$(FEDORA_SHIM_RPM).tmp" "$(FEDORA_SHIM_URL)"; \
		printf '%s  %s\n' "$(FEDORA_SHIM_SHA256)" "$(FEDORA_SHIM_RPM).tmp" | sha256sum -c -; \
		mv -f "$(FEDORA_SHIM_RPM).tmp" "$(FEDORA_SHIM_RPM)"; \
	fi; \
	if ! secure_boot_material_valid; then \
		rm -rf "$(CACHE_DIR)/fedora-shim"; \
		mkdir -p "$(CACHE_DIR)/fedora-shim"; \
		bsdtar -xf "$(FEDORA_SHIM_RPM)" -C "$(CACHE_DIR)/fedora-shim"; \
		shim_source="$(CACHE_DIR)/fedora-shim/usr/lib/efi/shim/16.1-5/EFI/BOOT/BOOTX64.EFI"; \
		mok_source="$(CACHE_DIR)/fedora-shim/usr/lib/efi/shim/16.1-5/EFI/fedora/mmx64.efi"; \
		verify_file_hash "$(FEDORA_SHIM_BINARY_SHA256)" "$$shim_source"; \
		verify_pe_signature "$$shim_source"; \
		verify_file_hash "$(FEDORA_MOK_MANAGER_BINARY_SHA256)" "$$mok_source"; \
		verify_pe_signature "$$mok_source"; \
		install -Dm644 "$$shim_source" \
			"$(SECURE_BOOT_DIR)/fedora/shimx64.efi"; \
		install -Dm644 "$$mok_source" \
			"$(SECURE_BOOT_DIR)/fedora/mmx64.efi"; \
	fi; \
	secure_boot_material_valid

doctor: vendor
	@for command in $(HOST_COMMANDS); do \
		command -v "$$command" >/dev/null || { echo "Missing build command: $$command" >&2; exit 1; }; \
	done
	@for file in $(SECURE_BOOT_FILES); do \
		test -r "$$file" || { echo "Missing Secure Boot build material: $$file" >&2; exit 1; }; \
	done
	@mode="$$(stat -c '%a' "$(SECURE_BOOT_DIR)/catos-release.key")"; \
		(( (8#$$mode & 077) == 0 )) || { echo "Release private key must be root-only: mode $$mode" >&2; exit 1; }
	@verify_pe_signature() { \
		local output; \
		output="$$(sbverify --list "$$1" 2>&1)" || return 1; \
		grep -Eq '^signature[[:space:]]+[0-9]+' <<<"$$output"; \
	}; \
	printf '%s  %s\n' "$(FEDORA_SHIM_BINARY_SHA256)" "$(SECURE_BOOT_DIR)/fedora/shimx64.efi" | sha256sum -c - >/dev/null; \
	printf '%s  %s\n' "$(FEDORA_MOK_MANAGER_BINARY_SHA256)" "$(SECURE_BOOT_DIR)/fedora/mmx64.efi" | sha256sum -c - >/dev/null; \
	verify_pe_signature "$(SECURE_BOOT_DIR)/fedora/shimx64.efi"; \
	verify_pe_signature "$(SECURE_BOOT_DIR)/fedora/mmx64.efi"
	@cert_public="$$(openssl x509 -in "$(SECURE_BOOT_DIR)/catos-release.crt" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)"; \
		key_public="$$(openssl pkey -in "$(SECURE_BOOT_DIR)/catos-release.key" -pubout -outform DER | sha256sum | cut -d' ' -f1)"; \
		test -n "$$cert_public" && test "$$cert_public" = "$$key_public" || { echo "Release certificate and private key do not match" >&2; exit 1; }
	@sign_file="$$(find /usr/lib/modules /usr/src -path '*/scripts/sign-file' -type f -perm -u+x -print -quit 2>/dev/null)"; \
		test -n "$$sign_file" || { echo "Missing executable kernel scripts/sign-file; install build-host kernel headers" >&2; exit 1; }

test: doctor
	@cleanup_profile() { rm -rf -- "$(TEST_PROFILE_DIR)"; }; \
	trap cleanup_profile EXIT INT TERM; \
	python3 "$(ROOT)/tools/prepare-test-profile.py" \
		"$(ROOT)/catos-iso" "$(TEST_PROFILE_DIR)"; \
	rm -rf -- "$(TEST_OUT_DIR)"; \
	mkdir -p "$(TEST_OUT_DIR)"; \
	flock -n "$(TEST_BUILD_LOCK)" sudo bash -eu -o pipefail -c '\
		cleanup() { rm -rf -- "$(TEST_WORK_DIR)"; }; \
		trap cleanup EXIT INT TERM; \
		cleanup; \
		env SOURCE_DATE_EPOCH="$(BUILD_EPOCH)" TZ=UTC \
			"$(ARCHISO)" -v -w "$(TEST_WORK_DIR)" -o "$(TEST_OUT_DIR)" "$(TEST_PROFILE_DIR)"; \
		chown -R "$(OWNER)" "$(TEST_OUT_DIR)"'; \
	python3 "$(ROOT)/tools/verify-test-iso.py" \
		--certificate "$(SECURE_BOOT_DIR)/catos-release.crt" \
		--require-package ckbcomp \
		"$(TEST_OUT_DIR)"

check:
	PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile tools/*.py
	bash -O extglob -n "$(ARCHISO)"
	bash -n catos-iso/profiledef.sh catos-iso-for-nvidia/profiledef.sh

clean:
	@flock -n "$(BUILD_LOCK)" sudo rm -rf -- "$(WORK_DIR)"
	@flock -n "$(TEST_BUILD_LOCK)" sudo rm -rf -- "$(TEST_WORK_DIR)"

distclean: clean
	rm -rf -- "$(CACHE_DIR)" "$(OUT_DIR)" "$(TEST_PROFILE_DIR)"
