#!/usr/bin/env bash

java_range_from_asset() {
  local name="$1"
  if [[ "$name" =~ _Java_([0-9]+)-([0-9]+)\.zip$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$name" =~ _Java_([0-9]+)\.zip$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}"
  else
    return "$EX_DATAERR"
  fi
}

java_recommended_major() {
  local minimum="$1" maximum="$2" candidate
  # Prefer a current LTS available from supported Ubuntu repositories.
  for candidate in 21 17; do
    if ((candidate >= minimum && candidate <= maximum)); then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return "$EX_DATAERR"
}

java_resolve_for_release() {
  local release_json="$1" name minimum maximum upstream_max recommended
  name="$(jq -r '.serverAsset.name' <<<"$release_json")"
  read -r minimum maximum < <(java_range_from_asset "$name") || return "$EX_DATAERR"
  upstream_max="$(jq -r '.upstream.maxJavaVersion' <<<"$release_json")"
  [[ "$upstream_max" =~ ^[0-9]+$ ]] || return "$EX_DATAERR"
  ((maximum == upstream_max)) || return "$EX_DATAERR"
  recommended="$(java_recommended_major "$minimum" "$maximum")" || return "$EX_DATAERR"
  jq -cn \
    --argjson minimum "$minimum" \
    --argjson maximum "$maximum" \
    --argjson recommended "$recommended" \
    '{minimumMajor:$minimum, maximumMajor:$maximum, recommendedMajor:$recommended, package:("openjdk-" + ($recommended|tostring) + "-jre-headless"), selectionPolicy:"prefer-supported-ubuntu-lts"}'
}

java_detect_installed() {
  command -v java >/dev/null 2>&1 || return 1
  java -version 2>&1 | awk -F'"' 'NR==1{print $2; exit}'
}
