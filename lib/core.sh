#!/usr/bin/env bash

# Public exit-code constants are consumed across separately sourced modules.
# shellcheck disable=SC2034

readonly EX_OK=0
readonly EX_USAGE=64
readonly EX_DATAERR=65
readonly EX_NOINPUT=66
readonly EX_UNAVAILABLE=69
readonly EX_SOFTWARE=70
readonly EX_CANTCREAT=73
readonly EX_IOERR=74
readonly EX_TEMPFAIL=75
readonly EX_NOPERM=77
readonly EX_CANCELLED=80
readonly EX_UNIMPLEMENTED=90

declare -ag CLEANUP_PATHS=()

die() {
  local code="$1"
  shift
  log_error "$*"
  printf 'Error: %s\n' "$*" >&2
  exit "$code"
}

install_error_traps() {
  trap 'on_unhandled_error $? $LINENO "$BASH_COMMAND"' ERR
  trap 'exit "$EX_CANCELLED"' INT TERM
}

on_unhandled_error() {
  local code="$1" line="$2" command="$3"
  log_error "Unhandled error code=$code line=$line command=$command"
}

register_cleanup_handler() {
  trap cleanup_registered_paths EXIT
}

register_cleanup_path() {
  local path="$1"
  [[ -n "$path" && "$path" == "${TMPDIR:-/tmp}/"* ]] || return "$EX_USAGE"
  CLEANUP_PATHS+=("$path")
}

cleanup_registered_paths() {
  local path
  for path in "${CLEANUP_PATHS[@]:-}"; do
    [[ -n "$path" && "$path" == "${TMPDIR:-/tmp}/"* ]] || continue
    rm -rf -- "$path"
  done
}

require_commands() {
  local missing=() command
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  ((${#missing[@]} == 0)) || die "$EX_UNAVAILABLE" "missing required command(s): ${missing[*]}"
}

require_mutation_allowed() {
  local description="$1"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_error "Dry-run mutation blocked: $description"
    return "$EX_NOPERM"
  fi
}

validate_absolute_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != *'/../'* && "$path" != *'/..' && "$path" != *$'\n'* ]]
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

operation_recovery_class() {
  local status="$1" stage="$2" backup_available="${3:-false}"
  case "$status" in
    complete|none) printf 'clean\n' ;;
    in_progress)
      case "$stage" in
        planned|download|verify|stage) printf 'resumable\n' ;;
        switch|configure|health-check)
          [[ "$backup_available" == "true" ]] && printf 'rollback-required\n' || printf 'manual-recovery\n'
          ;;
        *) printf 'manual-recovery\n' ;;
      esac
      ;;
    rollback_required) printf 'rollback-required\n' ;;
    *) printf 'manual-recovery\n' ;;
  esac
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$file" | awk '{print $1}'
  else
    return "$EX_UNAVAILABLE"
  fi
}
