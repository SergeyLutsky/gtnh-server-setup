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
        (.postStartChecks // [] | all(.[];
          (.name|type=="string" and length>0) and
          (.command|type=="string" and test("^[A-Za-z0-9._ -]+$")) and
          (.contains|type=="array" and length>0 and all(.[]; type=="string" and length>0)))) and
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
        postStartChecks:($r.postStartChecks // []),
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
  local resolved="$1" service="$2" check output expected
  [[ "${GTNH_TEST_MODE:-false}" == true ]] && return 0
  while IFS= read -r check; do
    output="$(GTNH_CONFIG_FILE="$(system_path "/etc/${service}.conf")" \
      "$(system_path /usr/local/bin/gtnh)" command "$(jq -r '.command' <<<"$check")")" || return "$EX_TEMPFAIL"
    while IFS= read -r expected; do
      grep -F -- "$expected" <<<"$output" >/dev/null || {
        log_error "post-start validation failed: $(jq -r '.name' <<<"$check") is missing $expected"
        return "$EX_TEMPFAIL"
      }
    done < <(jq -r '.contains[]' <<<"$check")
  done < <(jq -c '.[] | .postStartChecks[]?' <<<"$resolved")
}
