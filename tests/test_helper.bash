#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export GTNH_SETUP_ROOT="$TEST_ROOT"
export DRY_RUN=false

# shellcheck source=/dev/null
source "$TEST_ROOT/lib/core.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/ui.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/discovery.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/releases.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/java.sh"
# shellcheck source=/dev/null
source "$TEST_ROOT/lib/state.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok - %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$name"; else fail "$name (expected '$expected', got '$actual')"; fi
}

assert_success() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@"; then fail "$name (unexpected success)"; else pass "$name"; fi
}

finish_tests() {
  printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  ((FAIL_COUNT == 0))
}
