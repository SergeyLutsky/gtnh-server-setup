#!/usr/bin/env bash

state_build_json() {
  local install_path="$1" backup_path="$2" release_json="$3" java_json="$4" java_version="$5"
  local operation_id="${6:-none}" operation_status="${7:-none}" operation_stage="${8:-complete}" backup_available="${9:-false}"
  local timestamp="${GTNH_STATE_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  validate_absolute_path "$install_path" || return "$EX_USAGE"
  validate_absolute_path "$backup_path" || return "$EX_USAGE"
  [[ "$backup_available" == "true" || "$backup_available" == "false" ]] || return "$EX_USAGE"

  jq -cn \
    --arg installPath "$install_path" \
    --arg backupPath "$backup_path" \
    --argjson release "$release_json" \
    --argjson java "$java_json" \
    --arg javaVersion "$java_version" \
    --arg operationId "$operation_id" \
    --arg operationStatus "$operation_status" \
    --arg operationStage "$operation_stage" \
    --argjson backupAvailable "$backup_available" \
    --arg timestamp "$timestamp" '
      {
        schemaVersion: 1,
        managedBy: "gtnh-server-setup",
        installation: {
          path: $installPath,
          backupPath: $backupPath,
          serviceName: "gtnh.service"
        },
        gtnh: {
          version: $release.version,
          channel: $release.channel,
          artifact: {
            name: $release.serverAsset.name,
            url: $release.serverAsset.url,
            sha256: $release.serverAsset.sha256,
            sizeBytes: $release.serverAsset.sizeBytes
          },
          java: {
            major: $java.recommendedMajor,
            package: $java.package,
            version: $javaVersion
          }
        },
        mods: [],
        operation: {
          id: $operationId,
          status: $operationStatus,
          stage: $operationStage,
          backupAvailable: $backupAvailable,
          startedAt: $timestamp
        },
        updatedAt: $timestamp
      }
    '
}

state_write_atomic() {
  local state_json="$1" destination="$2" directory temporary
  require_mutation_allowed "write installer state" || return $?
  validate_absolute_path "$destination" || return "$EX_USAGE"
  directory="$(dirname -- "$destination")"
  install -d -m 0700 -- "$directory"
  temporary="$(mktemp "$directory/.state.json.XXXXXX")"
  chmod 0600 "$temporary"
  printf '%s\n' "$state_json" >"$temporary"
  jq -e '.schemaVersion == 1 and .managedBy == "gtnh-server-setup"' "$temporary" >/dev/null || {
    rm -f -- "$temporary"
    return "$EX_DATAERR"
  }
  mv -- "$temporary" "$destination"
}
