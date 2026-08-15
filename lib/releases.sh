#!/usr/bin/env bash

readonly GTNH_RELEASE_CATALOGUE_URL="${GTNH_RELEASE_CATALOGUE_URL:-https://raw.githubusercontent.com/GTNewHorizons/GTNewHorizons.github.io/master/public/versions.json}"
readonly GTNH_CHECKSUM_CATALOGUE_URL="${GTNH_CHECKSUM_CATALOGUE_URL:-${GTNH_SETUP_RAW_BASE:-}/catalog/gtnh-release-checksums.json}"

release_fetch_catalogue() {
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 45 --retry 3 --retry-all-errors \
    "$GTNH_RELEASE_CATALOGUE_URL"
}

release_validate_catalogue() {
  local json="$1"
  jq -e '
    type == "object" and length > 0 and
    all(to_entries[];
      (.key | type == "string") and
      (.value | type == "object") and
      (.value.title | type == "string") and
      (.value.releaseDate | test("^[0-9]{4}/[0-9]{2}/[0-9]{2}$")) and
      (.value.maxJavaVersion | type == "number") and
      (.value.server.java17_2XUrl | type == "string" and startswith("https://downloads.gtnewhorizons.com/ServerPacks/"))
    )
  ' >/dev/null <<<"$json"
}

release_load_checksums() {
  local local_file="${GTNH_SETUP_ROOT:-}/catalog/gtnh-release-checksums.json"
  if [[ -n "${GTNH_SETUP_ROOT:-}" && -r "$local_file" ]]; then
    cat -- "$local_file"
  elif [[ "$GTNH_CHECKSUM_CATALOGUE_URL" == https://* ]]; then
    curl --fail --silent --show-error --location \
      --connect-timeout 10 --max-time 30 --retry 3 --retry-all-errors \
      "$GTNH_CHECKSUM_CATALOGUE_URL"
  else
    return "$EX_NOINPUT"
  fi
}

release_validate_checksums() {
  jq -e '
    .schemaVersion == 1 and (.artifacts | type == "array") and
    all(.artifacts[];
      (.version | type == "string") and
      (.name | type == "string") and
      (.sha256 | test("^[a-f0-9]{64}$")) and
      (.sizeBytes | type == "number" and . > 0)
    )
  ' >/dev/null <<<"$1"
}

release_attach_pinned_checksum() {
  local release_json="$1" checksums_json="$2"
  jq -cer --argjson release "$release_json" '
    $release as $r
    | first(.artifacts[] | select(.version == $r.version and .name == $r.serverAsset.name)) as $pin
    | select($pin != null)
    | $r
    | .serverAsset.sha256 = $pin.sha256
    | .serverAsset.sizeBytes = $pin.sizeBytes
    | .serverAsset.checksumSource = "project-pinned-sha256"
    | .serverAsset.checksumVerifiedAt = $pin.verifiedAt
  ' <<<"$checksums_json"
}

release_resolve() {
  # The single-quoted filter fragments below intentionally contain jq variables.
  # shellcheck disable=SC2016
  local json="$1" selector="$2" filter
  case "$selector" in
    latest-stable)
      filter='(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.value.title | ascii_downcase | startswith("stable"))'
      ;;
    latest-rc)
      filter='(.key | test("(^|[-.])rc-?[0-9]+$"; "i"))'
      ;;
    *)
      jq -e --arg version "$selector" 'has($version)' >/dev/null <<<"$json" || return "$EX_DATAERR"
      if [[ "$selector" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # shellcheck disable=SC2016
        filter='(.key == $specific) and (.value.title | ascii_downcase | startswith("stable"))'
      elif [[ "$selector" =~ (^|[-.])[Rr][Cc]-?[0-9]+$ ]]; then
        # shellcheck disable=SC2016
        filter='(.key == $specific)'
      else
        return "$EX_DATAERR"
      fi
      ;;
  esac

  jq -cer --arg specific "$selector" --argjson is_specific "$([[ "$selector" == latest-* ]] && echo false || echo true)" '
    [to_entries[] | select('"$filter"')]
    | sort_by(.value.releaseDate, .key) | reverse | first
    | select(. != null)
    | . as $release
    | ($release.value.server.java17_2XUrl | split("/") | last) as $assetName
    | {
        version: $release.key,
        channel: (if ($release.key | test("(^|[-.])rc-?[0-9]+$"; "i")) then "rc" else "stable" end),
        title: $release.value.title,
        releaseDate: $release.value.releaseDate,
        serverAsset: {
          name: $assetName,
          url: $release.value.server.java17_2XUrl,
          checksumSource: "unresolved"
        },
        upstream: {
          catalogue: "GTNewHorizons/GTNewHorizons.github.io public/versions.json",
          maxJavaVersion: $release.value.maxJavaVersion
        }
      }
  ' <<<"$json"
}

release_download_and_verify() {
  local release_json="$1" destination="$2" expected_sha256="$3"
  local url name partial
  require_mutation_allowed "download GTNH server pack" || return $?
  [[ "$expected_sha256" =~ ^[a-fA-F0-9]{64}$ ]] || return "$EX_DATAERR"
  url="$(jq -r '.serverAsset.url' <<<"$release_json")"
  name="$(jq -r '.serverAsset.name' <<<"$release_json")"
  mkdir -p -- "$destination"
  partial="$destination/$name.part"
  rm -f -- "$partial"
  if ! curl --fail --show-error --location \
    --connect-timeout 15 --max-time 7200 --retry 4 --retry-all-errors \
    --continue-at - --output "$partial" "$url"; then
    rm -f -- "$partial"
    return "$EX_UNAVAILABLE"
  fi
  release_promote_verified_download "$partial" "$destination/$name" "$expected_sha256" || return $?
  printf '%s\n' "$destination/$name"
}

release_promote_verified_download() {
  local partial="$1" final="$2" expected_sha256="$3" actual
  [[ "$expected_sha256" =~ ^[a-fA-F0-9]{64}$ ]] || { rm -f -- "$partial"; return "$EX_DATAERR"; }
  actual="$(sha256_file "$partial")" || { rm -f -- "$partial"; return "$EX_UNAVAILABLE"; }
  if [[ "${actual,,}" != "${expected_sha256,,}" ]]; then
    rm -f -- "$partial"
    log_error "Checksum mismatch for $(basename -- "$final") expected=$expected_sha256 actual=$actual"
    return "$EX_DATAERR"
  fi
  mv -- "$partial" "$final"
}
