#!/usr/bin/env bash

properties_set() {
  local file="$1" key="$2" value="$3" matches tmp
  [[ -f "$file" && "$key" =~ ^[A-Za-z0-9_.-]+$ && "$value" != *$'\n'* ]] || return "$EX_DATAERR"
  matches="$(awk -F= -v key="$key" '$1==key{n++} END{print n+0}' "$file")"
  ((matches <= 1)) || return "$EX_DATAERR"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v key="$key" -v value="$value" 'BEGIN{done=0} $0 ~ "^" key "=" {print key "=" value; done=1; next} {print} END{if(!done) print key "=" value}' "$file" >"$tmp"
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  mv -- "$tmp" "$file"
}

cfg_set_unique() {
  local file="$1" key="$2" value="$3" matches tmp
  [[ -f "$file" && "$key" != *$'\n'* && "$value" != *$'\n'* ]] || return "$EX_DATAERR"
  # Match the full left side including Forge type prefix and optional quotes.
  matches="$(awk -v key="$key" '{x=$0; sub(/^[[:space:]]*/,"",x); if(index(x,key"=")==1)n++} END{print n+0}' "$file")"
  ((matches == 1)) || return "$EX_DATAERR"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v key="$key" -v value="$value" '{x=$0; match(x,/^[[:space:]]*/); indent=substr(x,1,RLENGTH); sub(/^[[:space:]]*/,"",x); if(index(x,key"=")==1){print indent key "=" value; next} print}' "$file" >"$tmp"
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  mv -- "$tmp" "$file"
}

cfg_set_in_section() {
  local file="$1" section="$2" key="$3" value="$4" tmp
  [[ -f "$file" ]] || return "$EX_NOINPUT"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v section="$section" -v key="$key" -v value="$value" '
    /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*\{/ {s=$1}
    {x=$0; match(x,/^[[:space:]]*/); indent=substr(x,1,RLENGTH); sub(/^[[:space:]]*/,"",x)}
    s==section && index(x,key"=")==1 {if(found++) exit 42; print indent key "=" value; next}
    {print}
    END{if(!found) exit 43}
  ' "$file" >"$tmp" || { rm -f -- "$tmp"; return "$EX_DATAERR"; }
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  mv -- "$tmp" "$file"
}

ranks_set_admin() {
  local file="$1" key="$2" value="$3" tmp
  [[ -f "$file" ]] || return "$EX_NOINPUT"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    /^\[.*\]$/ {section=$0}
    {x=$0; match(x,/^[[:space:]]*/); indent=substr(x,1,RLENGTH); sub(/^[[:space:]]*/,"",x)}
    section=="[admin]" && index(x,key)==1 {
      rest=substr(x,length(key)+1)
      if(rest ~ /^[[:space:]]*[:=]/) {if(found++) exit 42; print indent key ": " value; next}
    }
    {print}
    END{if(!found) exit 43}
  ' "$file" >"$tmp" || { rm -f -- "$tmp"; return "$EX_DATAERR"; }
  mv -- "$tmp" "$file"
}

offline_uuid() {
  python3 - "$1" <<'PY'
import hashlib, sys
b=bytearray(hashlib.md5(("OfflinePlayer:"+sys.argv[1]).encode()).digest())
b[6]=(b[6]&0x0f)|0x30; b[8]=(b[8]&0x3f)|0x80
h=b.hex(); print(f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}")
PY
}

config_apply() {
  local root="$1" port="$2" seed="$3" view="$4" admin="$5" rcon_port="$6" rcon_password="$7" uuid
  properties_set "$root/server.properties" online-mode false
  properties_set "$root/server.properties" white-list false
  properties_set "$root/server.properties" max-players 20
  properties_set "$root/server.properties" difficulty 3
  properties_set "$root/server.properties" view-distance "$view"
  properties_set "$root/server.properties" pvp false
  properties_set "$root/server.properties" allow-flight true
  properties_set "$root/server.properties" spawn-protection 0
  properties_set "$root/server.properties" server-port "$port"
  properties_set "$root/server.properties" level-seed "$seed"
  properties_set "$root/server.properties" enable-rcon true
  properties_set "$root/server.properties" rcon.port "$rcon_port"
  properties_set "$root/server.properties" rcon.password "$rcon_password"
  printf 'eula=true\n' >"$root/eula.txt"

  cfg_set_unique "$root/config/GregTech/WorldGeneration.cfg" 'B:generateUndergroundDirtGen' false
  cfg_set_unique "$root/config/GregTech/WorldGeneration.cfg" 'B:generateUndergroundGravelGen' false
  cfg_set_unique "$root/config/RWG.cfg" 'B:"Generate Caves"' false
  cfg_set_unique "$root/config/RWG.cfg" 'B:"Generate Mineshafts"' false
  cfg_set_unique "$root/config/RWG.cfg" 'B:"Generate Underground Lakes"' false
  cfg_set_unique "$root/config/RWG.cfg" 'B:"Generate Underground Lava Lakes"' false
  cfg_set_unique "$root/config/GregTech/Pollution.cfg" 'B:"Activate Pollution"' false
  cfg_set_unique "$root/config/GregTech/GregTech.cfg" 'B:machineExplosions' false
  cfg_set_unique "$root/config/forestry/common.cfg" 'B:disable.butterfly' true

  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" commands 'B:home' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" commands 'B:back' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" ranks 'B:enabled' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'B:chunk_claiming' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'B:chunk_loading' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'S:enable_pvp' FALSE
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'S:enable_explosions' FALSE
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'B:enable_player_sleeping_percentage' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" world 'I:player_sleeping_percentage' 50
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'B:enable_backups' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'S:backup_timer' 0.5
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'I:backups_to_keep' 12
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'B:need_online_players' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'B:only_backup_claimed_chunks' false
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'B:use_separate_thread' true
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" backups 'B:delete_custom_name_backups' false
  cfg_set_in_section "$root/serverutilities/serverutilities.cfg" auto_shutdown 'B:enabled' false

  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.claims.max_chunks 1000
  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.chunkloader.max_chunks 500
  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.homes.max 100
  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.homes.warmup 0s
  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.homes.cooldown 0s
  ranks_set_admin "$root/serverutilities/server/ranks.txt" serverutilities.homes.cross_dim true

  uuid="$(offline_uuid "$admin")"
  jq -n --arg uuid "$uuid" --arg name "$admin" '[{uuid:$uuid,name:$name,level:4,bypassesPlayerLimit:false}]' >"$root/ops.json"
  chmod 0600 "$root/ops.json"
}

config_validate() {
  local root="$1"
  grep -qx 'online-mode=false' "$root/server.properties" &&
  grep -qx 'pvp=false' "$root/server.properties" &&
  grep -qx 'eula=true' "$root/eula.txt" &&
  jq -e 'length == 1 and .[0].level == 4' "$root/ops.json" >/dev/null
}
