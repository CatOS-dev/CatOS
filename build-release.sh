#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-release.sh <normal|nvidia> <YYYY-MM-DD> [mkarchiso options]

Build a CatOS release against immutable repository snapshots.

The official Arch Linux repositories are pinned automatically to the given
Arch Linux Archive date. Snapshot URLs for all custom repositories are
required and must point at repositories frozen for the same release:

  ARCHLINUXCN_SNAPSHOT_SERVER
  ARCH4EDU_SNAPSHOT_SERVER
  CATOS_SNAPSHOT_SERVER

Each value is a complete pacman Server URL. Quote values containing pacman
variables, for example:

  CATOS_SNAPSHOT_SERVER='https://example.invalid/catos/2026.07/$arch'

Example:

  sudo --preserve-env=ARCHLINUXCN_SNAPSHOT_SERVER,ARCH4EDU_SNAPSHOT_SERVER,CATOS_SNAPSHOT_SERVER \
    ./build-release.sh normal 2026-07-17 -v -w /tmp/catos-work -o ./out
EOF
}

if (( $# < 2 )); then
  usage >&2
  exit 2
fi

variant="$1"
snapshot_date="$2"
shift 2

case "$variant" in
  normal)
    profile_name="catos-iso"
    ;;
  nvidia)
    profile_name="catos-iso-for-nvidia"
    ;;
  *)
    printf 'Unknown variant: %s\n' "$variant" >&2
    usage >&2
    exit 2
    ;;
esac

if ! snapshot_epoch="$(date -u --date="${snapshot_date} 00:00:00" +%s 2>/dev/null)"; then
  printf 'Invalid snapshot date: %s\n' "$snapshot_date" >&2
  exit 2
fi

canonical_date="$(date -u --date="@${snapshot_epoch}" +%F)"
if [[ "$canonical_date" != "$snapshot_date" ]]; then
  printf 'Snapshot date must use canonical YYYY-MM-DD form: %s\n' "$canonical_date" >&2
  exit 2
fi

required_snapshot_variables=(
  ARCHLINUXCN_SNAPSHOT_SERVER
  ARCH4EDU_SNAPSHOT_SERVER
  CATOS_SNAPSHOT_SERVER
)
for variable in "${required_snapshot_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    printf 'Missing required repository snapshot URL: %s\n' "$variable" >&2
    exit 2
  fi
done

if (( EUID != 0 )); then
  printf 'mkarchiso must run as root. Re-run this script through sudo.\n' >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_profile="${script_dir}/${profile_name}"
if [[ ! -d "$source_profile" ]]; then
  printf 'Profile directory not found: %s\n' "$source_profile" >&2
  exit 1
fi

snapshot_path="${snapshot_date//-//}"
official_server="https://archive.archlinux.org/repos/${snapshot_path}/\$repo/os/\$arch"
staging_root="$(mktemp -d --tmpdir catos-release.XXXXXXXX)"
trap 'rm -rf -- "$staging_root"' EXIT
staged_profile="${staging_root}/${profile_name}"
cp -a -- "$source_profile" "$staged_profile"
snapshot_conf="${staged_profile}/pacman.snapshot.conf"

awk \
  -v official_server="$official_server" \
  -v archlinuxcn_server="$ARCHLINUXCN_SNAPSHOT_SERVER" \
  -v arch4edu_server="$ARCH4EDU_SNAPSHOT_SERVER" \
  -v catos_server="$CATOS_SNAPSHOT_SERVER" \
  '
  function replacement(section) {
    if (section == "core" || section == "extra" || section == "multilib") {
      return official_server
    }
    if (section == "archlinuxcn") {
      return archlinuxcn_server
    }
    if (section == "arch4edu") {
      return arch4edu_server
    }
    if (section == "catos") {
      return catos_server
    }
    return ""
  }

  /^\[[^]]+\]$/ {
    section = substr($0, 2, length($0) - 2)
    server = replacement(section)
    print
    if (server != "") {
      print "Server = " server
      rewritten[section] = 1
    }
    next
  }

  replacement(section) != "" && /^(Server|Include)[[:space:]]*=/ {
    next
  }

  { print }

  END {
    required["core"] = 1
    required["extra"] = 1
    required["multilib"] = 1
    required["archlinuxcn"] = 1
    required["arch4edu"] = 1
    required["catos"] = 1
    for (repository in required) {
      if (!rewritten[repository]) {
        printf "Required repository section missing: [%s]\n", repository > "/dev/stderr"
        failed = 1
      }
    }
    if (failed) {
      exit 3
    }
  }
  ' "$source_profile/pacman.conf" > "$snapshot_conf"

printf 'Building %s with repository snapshot %s\n' "$variant" "$snapshot_date"
printf 'Staged profile: %s\n' "$staged_profile"

export SOURCE_DATE_EPOCH="$snapshot_epoch"
export TZ=UTC
mkarchiso -C "$snapshot_conf" "$@" "$staged_profile"
