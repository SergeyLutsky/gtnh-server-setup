#!/usr/bin/env bash

mod_catalogue_load() {
  local local_file="${GTNH_SETUP_ROOT:-}/catalog/mods.json" url="${GTNH_SETUP_RAW_BASE:-}/catalog/mods.json"
  if [[ -n "${GTNH_SETUP_ROOT:-}" && -r "$local_file" ]]; then cat -- "$local_file"; else curl --fail --silent --show-error --location "$url"; fi
}

mod_catalogue_validate() {
  jq -e '.schemaVersion==1 and (.mods|type=="array") and all(.mods[]; (.id|type=="string") and (.releases|type=="array"))' >/dev/null <<<"$1"
}

mod_resolve() {
  local catalogue="$1" gtnh="$2" ids_csv="$3"
  [[ "$ids_csv" == "none" || -z "$ids_csv" ]] && { printf '[]\n'; return; }
  jq -cer --arg gtnh "$gtnh" --arg ids "$ids_csv" '
    ($ids|split(",")) as $want |
    [ .mods[] | . as $m | select(($want|index($m.id)) != null or ($ids=="all")) |
      first(.releases[]|select(.gtnh==$gtnh)) as $r |
      select($r != null) | {id:$m.id,name:$m.name,version:$r.version,clientRequired:$m.clientRequired,artifact:{name:$r.asset,url:$r.url,sha256:$r.sha256,sizeBytes:$r.sizeBytes}} ]
    | if ($ids!="all" and length != ($want|length)) then error("unknown or incompatible mod") else . end
  ' <<<"$catalogue"
}

mods_download() {
  local resolved="$1" target="$2" row partial actual
  mkdir -p -- "$target"
  while IFS= read -r row; do
    local name url sha
    name="$(jq -r '.artifact.name' <<<"$row")"; url="$(jq -r '.artifact.url' <<<"$row")"; sha="$(jq -r '.artifact.sha256' <<<"$row")"
    partial="$target/$name.part"
    curl --fail --show-error --location --retry 4 --retry-all-errors --output "$partial" "$url" || { rm -f -- "$partial"; return "$EX_UNAVAILABLE"; }
    actual="$(sha256_file "$partial")" || return $?
    [[ "$actual" == "$sha" ]] || { rm -f -- "$partial"; return "$EX_DATAERR"; }
    mv -- "$partial" "$target/$name"
  done < <(jq -c '.[]' <<<"$resolved")
}
