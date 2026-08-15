#!/usr/bin/env bash

backup_create() {
  local install_path="$1" backup_path="$2" name="${3:-auto-$(date -u +%Y%m%dT%H%M%SZ)}" archive manifest
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || return "$EX_USAGE"
  install -d -m 0700 -- "$backup_path"
  archive="$backup_path/${name}.tar.gz"; manifest="$archive.sha256"
  tar -C "$(dirname -- "$install_path")" -czf "$archive.part" "$(basename -- "$install_path")"
  mv -- "$archive.part" "$archive"
  (cd -- "$backup_path" && sha256sum "$(basename -- "$archive")" >"$(basename -- "$manifest")")
  chmod 0600 "$archive" "$manifest"
  printf '%s\n' "$archive"
}

backup_verify() {
  local archive="$1"
  [[ -f "$archive" && -f "$archive.sha256" ]] || return "$EX_NOINPUT"
  (cd -- "$(dirname -- "$archive")" && sha256sum -c "$(basename -- "$archive.sha256")" >/dev/null) || return "$EX_DATAERR"
  tar_archive_validate "$archive"
}

backup_prune_auto() {
  local backup_path="$1" keep="${2:-5}" file
  mapfile -t files < <(find "$backup_path" -maxdepth 1 -type f -name 'auto-*.tar.gz' -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
  for file in "${files[@]:$keep}"; do rm -f -- "$file" "$file.sha256"; done
}

backup_restore() {
  local archive="$1" install_path="$2" parent tmp
  backup_verify "$archive" || return $?
  parent="$(dirname -- "$install_path")"; tmp="$(mktemp -d "$parent/.gtnh-restore.XXXXXX")"
  tar -xzf "$archive" -C "$tmp"
  [[ -d "$tmp/$(basename -- "$install_path")" ]] || { rm -rf -- "$tmp"; return "$EX_DATAERR"; }
  mv -- "$install_path" "${install_path}.failed.$(date +%s)"
  mv -- "$tmp/$(basename -- "$install_path")" "$install_path"
  rmdir -- "$tmp"
}

carry_forward_mutable() {
  local old="$1" stage="$2" item jar base
  for item in World world DIM-1 DIM1 serverutilities config server.properties ops.json whitelist.json banned-ips.json banned-players.json usercache.json; do
    [[ -e "$old/$item" ]] && rsync -a --delete -- "$old/$item" "$stage/"
  done
  # Preserve only add-on/unmanaged jars absent from the new official pack.
  if [[ -d "$old/mods" ]]; then
    while IFS= read -r -d '' jar; do
      base="$(basename -- "$jar")"
      [[ -e "$stage/mods/$base" ]] || install -m 0644 -- "$jar" "$stage/mods/$base"
    done < <(find "$old/mods" -maxdepth 1 -type f -name '*.jar' -print0)
  fi
}
