#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

snapshot() {
  find "$ROOT" -path "$ROOT/.git" -prune -o -type f -print0 \
    | sort -z \
    | xargs -0 sha256sum
}

before="$(snapshot)"

export GTNH_TEST_OS_RELEASE=$'ID=ubuntu\nVERSION_ID="24.04"'
export GTNH_TEST_MEMINFO='MemTotal:       33554432 kB'
export GTNH_TEST_DF_OUTPUT=$'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 104857600 1024 83886080 1% /'
export GTNH_TEST_IP_ADDR
GTNH_TEST_IP_ADDR="$(<"$ROOT/tests/fixtures/discovery-ip.txt")"
export GTNH_TEST_SS_OUTPUT='LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*'
export GTNH_TEST_UFW_STATUS='Status: active'
export GTNH_TEST_EUID=0
export GTNH_TEST_UNAME=x86_64

bash "$ROOT/install.sh" --dry-run --plain --yes --action install --channel stable \
  --release-metadata "$ROOT/tests/fixtures/releases.json" --admin TestAdmin >/dev/null

after="$(snapshot)"
if [[ "$before" != "$after" ]]; then
  printf 'Dry-run changed repository files.\n' >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
  exit 1
fi

printf 'ok - dry-run leaves filesystem snapshot unchanged\n'
