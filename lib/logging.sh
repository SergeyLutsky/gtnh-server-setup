#!/usr/bin/env bash

LOG_FILE=""
declare -ag LOG_SECRETS=()

log_register_secret() {
  [[ -n "${1:-}" ]] && LOG_SECRETS+=("$1")
}

redact_text() {
  local text="$1" secret
  text="$(sed -E \
    -e 's/([Pp]assword|[Tt]oken|[Ss]ecret|rcon[._-]password)([[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1\2[REDACTED]/g' \
    -e 's/(Authorization:[[:space:]]*(Bearer|token)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(ghp_|github_pat_)[A-Za-z0-9_]+/[REDACTED_GITHUB_TOKEN]/g' <<<"$text")"
  for secret in "${LOG_SECRETS[@]:-}"; do
    [[ -n "$secret" ]] || continue
    text="${text//"$secret"/[REDACTED]}"
  done
  printf '%s' "$text"
}

logging_init() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    LOG_FILE=""
    return 0
  fi
  local log_dir="${GTNH_LOG_DIR:-/var/log/gtnh-installer}"
  require_mutation_allowed "create installer log directory" || return $?
  install -d -m 0700 -- "$log_dir"
  LOG_FILE="$log_dir/installer-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
  : >"$LOG_FILE"
  chmod 0600 "$LOG_FILE"
}

log_write() {
  local level="$1"
  shift
  local line
  line="$(redact_text "$*")"
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) [$level] $line"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" >>"$LOG_FILE"
  fi
}

log_debug() { log_write DEBUG "$*"; }
log_info() { log_write INFO "$*"; }
log_warn() { log_write WARN "$*"; }
log_error() { log_write ERROR "$*"; }
