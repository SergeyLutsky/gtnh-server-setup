#!/usr/bin/env bash

diagnostics_create_bundle() {
  local output_dir="$1" source_log="${2:-}" discovery_file="${3:-}"
  local work bundle
  require_mutation_allowed "create diagnostic bundle" || return $?
  validate_absolute_path "$output_dir" || return "$EX_USAGE"
  install -d -m 0700 -- "$output_dir"
  work="$(mktemp -d "${TMPDIR:-/tmp}/gtnh-diagnostics.XXXXXX")"
  register_cleanup_path "$work"

  if [[ -n "$source_log" && -r "$source_log" ]]; then
    while IFS= read -r line; do redact_text "$line"; printf '\n'; done <"$source_log" >"$work/installer.log"
  fi
  if [[ -n "$discovery_file" && -r "$discovery_file" ]]; then
    while IFS= read -r line; do redact_text "$line"; printf '\n'; done <"$discovery_file" >"$work/discovery.txt"
  fi
  bundle="$output_dir/gtnh-diagnostics-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
  tar -czf "$bundle" -C "$work" .
  chmod 0600 "$bundle"
  printf '%s\n' "$bundle"
}
