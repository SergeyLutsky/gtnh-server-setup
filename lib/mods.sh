#!/usr/bin/env bash

mod_catalogue_load() {
  local local_file="${GTNH_SETUP_ROOT:-}/catalog/mods.json" url="${GTNH_SETUP_RAW_BASE:-}/catalog/mods.json"
  if [[ -n "${GTNH_SETUP_ROOT:-}" && -r "$local_file" ]]; then cat -- "$local_file"; else curl --fail --silent --show-error --location "$url"; fi
}

mod_catalogue_validate() {
  jq -e '
    .schemaVersion==1 and (.mods|type=="array") and all(.mods[];
      (.id|type=="string") and (.releases|type=="array") and all(.releases[];
        (.artifactEntries // [] | all(.[]; type=="string" and length>0)) and
        (.runtimeRequirements // [] | all(.[];
          (.name|type=="string" and length>0) and
          (.jar|type=="string" and test("^[A-Za-z0-9._+()-]+\\.jar$")) and
          (.artifact // {} | if length==0 then true else
            (.url|type=="string" and startswith("https://github.com/")) and
            (.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
            (.sizeBytes|type=="number" and .>0) end) and
          (.entries // [] | all(.[]; type=="string" and length>0)))) and
        (.contentPacks // [] | all(.[];
          (.id|type=="string" and test("^[a-z0-9][a-z0-9-]*$")) and
          (.name|type=="string" and length>0) and
          (.version|type=="string" and length>0) and
          (.repository|type=="string" and startswith("https://github.com/")) and
          (.archive.name|type=="string" and test("^[A-Za-z0-9._+-]+\\.zip$")) and
          (.archive.url|type=="string" and startswith("https://github.com/")) and
          (.archive.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
          (.archive.sizeBytes|type=="number" and .>0) and
          (.archiveRoot|type=="string" and test("^[A-Za-z0-9._+ =/-]+$") and (contains("..")|not)) and
          (.target|type=="string" and test("^config/[A-Za-z0-9._+ =/-]+$") and (contains("..")|not)) and
          (.replacePaths|type=="array" and length>0 and all(.[];
            type=="string" and test("^[A-Za-z0-9._+ =/-]+$") and (contains("..")|not))) and
          (.requiredEntries|type=="array" and length>0 and all(.[];
            type=="string" and test("^[A-Za-z0-9._+ =/-]+$") and (contains("..")|not))))) and
        (.postStartChecks // [] | all(.[];
          (.name|type=="string" and length>0) and
          (.command|type=="string" and test("^[A-Za-z0-9._ -]+$")) and
          (.contains|type=="array" and length>0 and all(.[]; type=="string" and length>0)))) and
        (.postStartLogChecks // [] | all(.[];
          (.name|type=="string" and length>0) and
          (.command|type=="string" and test("^[A-Za-z0-9._ -]+$")) and
          (.logContains|type=="string" and length>0))) and
        (.updateResetPaths // [] | all(.[];
          type=="string" and test("^config/[A-Za-z0-9._/-]+$") and
          (contains("..")|not)))))
  ' >/dev/null <<<"$1"
}

mod_resolve() {
  local catalogue="$1" gtnh="$2" ids_csv="$3"
  [[ "$ids_csv" == "none" || -z "$ids_csv" ]] && { printf '[]\n'; return; }
  jq -cer --arg gtnh "$gtnh" --arg ids "$ids_csv" '
    ($ids|split(",")) as $want |
    [ .mods[] | . as $m | select(($want|index($m.id)) != null or ($ids=="all")) |
      first(.releases[]|select(.gtnh==$gtnh)) as $r |
      select($r != null) | {
        id:$m.id,name:$m.name,version:$r.version,clientRequired:$m.clientRequired,
        artifact:{name:$r.asset,url:$r.url,sha256:$r.sha256,sizeBytes:$r.sizeBytes},
        artifactEntries:($r.artifactEntries // []),
        runtimeRequirements:($r.runtimeRequirements // []),
        contentPacks:($r.contentPacks // []),
        postStartChecks:($r.postStartChecks // []),
        postStartLogChecks:($r.postStartLogChecks // []),
        updateResetPaths:($r.updateResetPaths // [])
      } ]
    | if ($ids!="all" and length != ($want|length)) then error("unknown or incompatible mod") else . end
  ' <<<"$catalogue"
}

mods_download() {
  local resolved="$1" target="$2" row
  mkdir -p -- "$target"
  while IFS= read -r row; do
    mod_artifact_download "$(jq -c '.artifact' <<<"$row")" "$target"
  done < <(jq -c '.[]' <<<"$resolved")
}

mod_artifact_download() {
  local artifact="$1" target="$2" name url sha partial actual
  mkdir -p -- "$target"
  name="$(jq -r '.name' <<<"$artifact")"; url="$(jq -r '.url' <<<"$artifact")"; sha="$(jq -r '.sha256' <<<"$artifact")"
  partial="$target/$name.part"
  curl --fail --show-error --location --retry 4 --retry-all-errors --output "$partial" "$url" || { rm -f -- "$partial"; return "$EX_UNAVAILABLE"; }
  actual="$(sha256_file "$partial")" || return $?
  [[ "$actual" == "$sha" ]] || { rm -f -- "$partial"; return "$EX_DATAERR"; }
  mv -- "$partial" "$target/$name"
}

mods_download_runtime_requirements() {
  local resolved="$1" target="$2" requirement artifact
  while IFS= read -r requirement; do
    artifact="$(jq -c --arg name "$(jq -r '.jar' <<<"$requirement")" '.artifact + {name:$name}' <<<"$requirement")"
    mod_artifact_download "$artifact" "$target" || return $?
  done < <(jq -c '.[] | .runtimeRequirements[]? | select(.artifact != null)' <<<"$resolved")
}

mods_download_content_packs() {
  local resolved="$1" target="$2" pack
  while IFS= read -r pack; do
    mod_artifact_download "$(jq -c '.archive' <<<"$pack")" "$target" || return $?
  done < <(jq -c '.[] | .contentPacks[]?' <<<"$resolved")
}

jar_has_entry() {
  local jar="$1" entry="$2"
  # Do not use grep -q here: with pipefail it can close a large JAR listing
  # early, making unzip's SIGPIPE look like a failed validation.
  unzip -Z1 "$jar" | grep -Fx -- "$entry" >/dev/null
}

mods_validate_artifacts() {
  local resolved="$1" target="$2" row entry jar
  while IFS= read -r row; do
    jar="$target/$(jq -r '.artifact.name' <<<"$row")"
    [[ -f "$jar" ]] || return "$EX_NOINPUT"
    while IFS= read -r entry; do
      jar_has_entry "$jar" "$entry" || {
        log_error "optional mod artifact is missing required content: $(basename -- "$jar"): $entry"
        return "$EX_DATAERR"
      }
    done < <(jq -r '.artifactEntries[]?' <<<"$row")
  done < <(jq -c '.[]' <<<"$resolved")
}

mods_validate_runtime_requirements() {
  local resolved="$1" target="$2" row requirement required_jar entry
  while IFS= read -r row; do
    while IFS= read -r requirement; do
      required_jar="$target/$(jq -r '.jar' <<<"$requirement")"
      if [[ ! -f "$required_jar" ]]; then
        log_error "missing runtime requirement for $(jq -r '.name' <<<"$row"): $(jq -r '.name' <<<"$requirement")"
        return "$EX_DATAERR"
      fi
      while IFS= read -r entry; do
        jar_has_entry "$required_jar" "$entry" || {
          log_error "runtime requirement lacks expected API content: $(basename -- "$required_jar"): $entry"
          return "$EX_DATAERR"
        }
      done < <(jq -r '.entries[]?' <<<"$requirement")
    done < <(jq -c '.runtimeRequirements[]?' <<<"$row")
  done < <(jq -c '.[]' <<<"$resolved")
}

zip_has_entry() {
  local archive="$1" entry="$2"
  unzip -Z1 "$archive" | grep -Fx -- "$entry" >/dev/null
}

mods_validate_content_packs() {
  local resolved="$1" target="$2" pack archive entry
  while IFS= read -r pack; do
    archive="$target/$(jq -r '.archive.name' <<<"$pack")"
    [[ -f "$archive" ]] || return "$EX_NOINPUT"
    archive_validate "$archive" || return $?
    while IFS= read -r entry; do
      zip_has_entry "$archive" "$entry" || {
        log_error "quest content archive is missing required content: $(basename -- "$archive"): $entry"
        return "$EX_DATAERR"
      }
    done < <(jq -r '.requiredEntries[]' <<<"$pack")
  done < <(jq -c '.[] | .contentPacks[]?' <<<"$resolved")
}

mods_apply_content_packs() {
  local resolved="$1" downloads="$2" stage="$3" pack archive root target extract source path destination
  local stage_real target_real destination_real
  stage_real="$(realpath -m -- "$stage")"
  while IFS= read -r pack; do
    archive="$downloads/$(jq -r '.archive.name' <<<"$pack")"
    root="$(jq -r '.archiveRoot' <<<"$pack")"
    target="$(jq -r '.target' <<<"$pack")"
    [[ "$root" != /* && "$root" != *..* && "$target" == config/* && "$target" != *..* ]] || return "$EX_DATAERR"
    target_real="$(realpath -m -- "$stage/$target")"
    [[ "$target_real" == "$stage_real/"* ]] || return "$EX_DATAERR"
    extract="$(mktemp -d "$downloads/.content-pack.XXXXXX")"
    unzip -q "$archive" -d "$extract" || { rm -rf -- "$extract"; return "$EX_DATAERR"; }
    if find "$extract" -type l -print -quit | grep -q .; then rm -rf -- "$extract"; return "$EX_DATAERR"; fi
    source="$extract/$root"
    [[ -d "$source" ]] || { rm -rf -- "$extract"; return "$EX_DATAERR"; }
    while IFS= read -r path; do
      [[ "$path" != /* && "$path" != *..* ]] || { rm -rf -- "$extract"; return "$EX_DATAERR"; }
      destination="$stage/$target/$path"
      destination_real="$(realpath -m -- "$destination")"
      [[ "$destination_real" == "$target_real/"* && -e "$source/$path" ]] || {
        rm -rf -- "$extract"
        return "$EX_DATAERR"
      }
      rm -rf -- "$destination_real"
      install -d -m 0755 -- "$(dirname -- "$destination_real")"
      cp -a -- "$source/$path" "$destination_real"
    done < <(jq -r '.replacePaths[]' <<<"$pack")
    rm -rf -- "$extract"
    log_info "installed quest content: $(jq -r '.name + " " + .version' <<<"$pack")"
  done < <(jq -c '.[] | .contentPacks[]?' <<<"$resolved")
}

mods_apply_update_migrations() {
  local old_state="$1" resolved="$2" stage="$3" row id old_version new_version path
  while IFS= read -r row; do
    id="$(jq -r '.id' <<<"$row")"
    new_version="$(jq -r '.version' <<<"$row")"
    old_version="$(jq -r --arg id "$id" 'first(.mods[]? | select(.id==$id) | .version) // ""' <<<"$old_state")"
    [[ -n "$old_version" && "$old_version" != "$new_version" ]] || continue
    while IFS= read -r path; do
      [[ "$path" == config/* && "$path" != *..* ]] || return "$EX_DATAERR"
      if [[ -e "$stage/$path" ]]; then
        rm -f -- "$stage/$path"
        log_info "reset $path while updating $id from $old_version to $new_version"
      fi
    done < <(jq -r '.updateResetPaths[]?' <<<"$row")
  done < <(jq -c '.[]' <<<"$resolved")
}

mods_validate_post_start() {
  local resolved="$1" service="$2" check output expected config_file helper log_file start_line deadline attempt rcon_ready check_ok
  [[ "${GTNH_TEST_MODE:-false}" == true ]] && return 0
  config_file="$(system_path "/etc/${service}.conf")"
  helper="$(system_path /usr/local/bin/gtnh)"
  while IFS= read -r check; do
    check_ok=false
    for ((attempt=1; attempt<=${GTNH_POST_START_COMMAND_ATTEMPTS:-6}; attempt++)); do
      if output="$(GTNH_CONFIG_FILE="$config_file" "$helper" command "$(jq -r '.command' <<<"$check")" 2>/dev/null)"; then
        check_ok=true
        while IFS= read -r expected; do
          if ! grep -F -- "$expected" <<<"$output" >/dev/null; then check_ok=false; break; fi
        done < <(jq -r '.contains[]' <<<"$check")
        [[ "$check_ok" == true ]] && break
      fi
      sleep "${GTNH_POST_START_COMMAND_RETRY_SECONDS:-5}"
    done
    if [[ "$check_ok" != true ]]; then
      log_error "post-start validation failed: $(jq -r '.name' <<<"$check") did not return all required evidence"
      return "$EX_TEMPFAIL"
    fi
  done < <(jq -c '.[] | .postStartChecks[]?' <<<"$resolved")

  # Some long BetterQuesting admin commands complete successfully but close
  # their RCON response. Prove those actions from a fresh log marker, then
  # require a new RCON connection so a stale marker cannot pass the check.
  # shellcheck disable=SC1090
  source "$config_file"
  log_file="$GTNH_INSTALL_PATH/logs/latest.log"
  while IFS= read -r check; do
    [[ -f "$log_file" ]] || return "$EX_NOINPUT"
    start_line="$(wc -l <"$log_file")"
    GTNH_CONFIG_FILE="$config_file" "$helper" command "$(jq -r '.command' <<<"$check")" >/dev/null 2>&1 || true
    deadline=$((SECONDS + ${GTNH_POST_START_LOG_TIMEOUT:-60}))
    while ((SECONDS < deadline)); do
      if tail -n "+$((start_line + 1))" "$log_file" | grep -F -- "$(jq -r '.logContains' <<<"$check")" >/dev/null; then break; fi
      sleep 1
    done
    if ! tail -n "+$((start_line + 1))" "$log_file" | grep -F -- "$(jq -r '.logContains' <<<"$check")" >/dev/null; then
      log_error "post-start validation failed: $(jq -r '.name' <<<"$check") did not produce a fresh server log marker"
      return "$EX_TEMPFAIL"
    fi
    rcon_ready=false
    for ((attempt=1; attempt<=${GTNH_POST_START_RCON_ATTEMPTS:-6}; attempt++)); do
      if GTNH_CONFIG_FILE="$config_file" "$helper" command list >/dev/null 2>&1; then rcon_ready=true; break; fi
      sleep "${GTNH_POST_START_RCON_RETRY_SECONDS:-5}"
    done
    if [[ "$rcon_ready" != true ]]; then
      log_error "post-start validation failed: $(jq -r '.name' <<<"$check") did not restore RCON responsiveness"
      return "$EX_TEMPFAIL"
    fi
  done < <(jq -c '.[] | .postStartLogChecks[]?' <<<"$resolved")
}
