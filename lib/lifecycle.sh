#!/usr/bin/env bash

system_path() { printf '%s%s\n' "${GTNH_SYSTEM_ROOT:-}" "$1"; }

rcon_password_generate() { openssl rand -hex 24; }

archive_validate() {
  local archive="$1" entry listing
  listing="$(unzip -Z1 "$archive" 2>/dev/null)" || return "$EX_DATAERR"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* && "$entry" != *\\* && "$entry" != ../* && "$entry" != */../* && "$entry" != *'/..' ]] || return "$EX_DATAERR"
  done <<<"$listing"
}

tar_archive_validate() {
  local archive="$1" entry listing
  listing="$(tar -tzf "$archive" 2>/dev/null)" || return "$EX_DATAERR"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* && "$entry" != *\\* && "$entry" != ../* && "$entry" != */../* && "$entry" != *'/..' ]] || return "$EX_DATAERR"
  done <<<"$listing"
}

archive_extract_server() {
  local archive="$1" target="$2"
  archive_validate "$archive" || return $?
  mkdir -p -- "$target"
  unzip -q "$archive" -d "$target"
  [[ -f "$target/lwjgl3ify-forgePatches.jar" && -f "$target/java9args.txt" && -f "$target/server.properties" ]] || return "$EX_DATAERR"
  if find "$target" -type l -print -quit | grep -q .; then return "$EX_DATAERR"; fi
}

runtime_config_write() {
  local install_path="$1" backup_path="$2" service="$3" heap="$4" rcon_port="$5" rcon_password="$6" fml_query_argument="${7:-}" env_file
  env_file="$(system_path "/etc/${service}.conf")"
  install -d -m 0755 -- "$(dirname -- "$env_file")"
  umask 077
  {
    printf 'GTNH_INSTALL_PATH=%q\n' "$install_path"
    printf 'GTNH_BACKUP_PATH=%q\n' "$backup_path"
    printf 'GTNH_SERVICE=%q\n' "$service"
    printf 'GTNH_HEAP_MIB=%q\n' "$heap"
    printf 'GTNH_RCON_PORT=%q\n' "$rcon_port"
    printf 'GTNH_RCON_PASSWORD=%q\n' "$rcon_password"
    printf 'FML_QUERY_ARGUMENT=%q\n' "$fml_query_argument"
  } >"$env_file"
  chmod 0600 "$env_file"
}

helper_install() {
  local service="$1" destination source
  destination="$(system_path "/usr/local/bin/gtnh")"
  install -d -m 0755 -- "$(dirname -- "$destination")"
  if [[ -n "${GTNH_SETUP_ROOT:-}" ]]; then
    install -m 0755 -- "$GTNH_SETUP_ROOT/bin/gtnh" "$destination"
    install -m 0755 -- "$GTNH_SETUP_ROOT/bin/gtnh-rcon.py" "$(system_path /usr/local/lib/gtnh-rcon.py)"
    install -m 0755 -- "$GTNH_SETUP_ROOT/bin/gtnh-rcon-firewall" "$(system_path /usr/local/lib/gtnh-rcon-firewall)"
  else
    source="$(curl --fail --silent --show-error --location "${GTNH_SETUP_RAW_BASE}/bin/gtnh")"; printf '%s\n' "$source" >"$destination"; chmod 0755 "$destination"
    source="$(curl --fail --silent --show-error --location "${GTNH_SETUP_RAW_BASE}/bin/gtnh-rcon.py")"; printf '%s\n' "$source" >"$(system_path /usr/local/lib/gtnh-rcon.py)"; chmod 0755 "$(system_path /usr/local/lib/gtnh-rcon.py)"
    source="$(curl --fail --silent --show-error --location "${GTNH_SETUP_RAW_BASE}/bin/gtnh-rcon-firewall")"; printf '%s\n' "$source" >"$(system_path /usr/local/lib/gtnh-rcon-firewall)"; chmod 0755 "$(system_path /usr/local/lib/gtnh-rcon-firewall)"
  fi
  ln -sfn -- "${service}.conf" "$(system_path /etc/gtnh-server-setup.conf)"
}

service_install() {
  local install_path="$1" service="$2" heap="$3" unit
  unit="$(system_path "/etc/systemd/system/${service}.service")"
  install -d -m 0755 -- "$(dirname -- "$unit")"
  cat >"$unit" <<EOF
[Unit]
Description=GT New Horizons Minecraft Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$install_path
EnvironmentFile=$(system_path "/etc/${service}.conf")
ExecStartPre=$(system_path /usr/local/lib/gtnh-rcon-firewall) add
ExecStart=/usr/bin/java -Xms${heap}M -Xmx${heap}M -Dfml.readTimeout=180 \$FML_QUERY_ARGUMENT @java9args.txt -jar lwjgl3ify-forgePatches.jar nogui
# A process may crash between the stop request and RCON connection. Prefixing
# with '-' makes graceful RCON best-effort; systemd still terminates leftovers.
ExecStop=-$(system_path /usr/local/bin/gtnh) command stop
ExecStopPost=$(system_path /usr/local/lib/gtnh-rcon-firewall) remove
Restart=on-failure
RestartSec=12
TimeoutStopSec=90
SuccessExitStatus=0 143
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$unit"
  if [[ "${GTNH_TEST_MODE:-false}" == "true" ]]; then printf 'systemctl enable %s\n' "$service" >>"${GTNH_TEST_ACTION_LOG:?}"; else systemctl daemon-reload; systemctl enable "$service"; fi
}

firewall_apply() {
  local port="$1" network="$2"
  [[ "${DISCOVERY[ufw]:-inactive}" == active && -n "$network" ]] || return 0
  if [[ "${GTNH_TEST_MODE:-false}" == true ]]; then printf 'ufw allow from %s to any port %s proto tcp\n' "$network" "$port" >>"${GTNH_TEST_ACTION_LOG:?}"; else ufw allow from "$network" to any port "$port" proto tcp comment 'GTNH LAN'; fi
}

service_start() {
  local service="$1"
  if [[ "${GTNH_TEST_MODE:-false}" == true ]]; then printf 'systemctl start %s\n' "$service" >>"${GTNH_TEST_ACTION_LOG:?}"; return; fi
  systemctl restart "$service"
}

service_wait_healthy() {
  local service="$1" timeout="${2:-600}" since="${3:-$(date -u '+%Y-%m-%d %H:%M:%S UTC')}" elapsed=0
  [[ "${GTNH_TEST_MODE:-false}" == true ]] && return 0
  while ((elapsed < timeout)); do
    systemctl is-active --quiet "$service" || { sleep 2; elapsed=$((elapsed+2)); continue; }
    # Do not use grep -q here: with pipefail it closes the journal pipe early,
    # making journalctl's SIGPIPE turn a successful match into a failed pipeline.
    if journalctl -u "$service" --since "$since" --no-pager 2>/dev/null | grep -F 'For help, type "help"' >/dev/null; then
      GTNH_CONFIG_FILE="$(system_path "/etc/${service}.conf")" \
        "$(system_path /usr/local/bin/gtnh)" command list >/dev/null 2>&1 && return 0
    fi
    sleep 5; elapsed=$((elapsed+5))
  done
  return "$EX_TEMPFAIL"
}

gamerules_apply() {
  local service="$1"
  [[ "${GTNH_TEST_MODE:-false}" == true ]] && return 0
  local helper command attempt applied
  helper="$(system_path /usr/local/bin/gtnh)"
  for command in 'gamerule doFireTick false' 'gamerule mobGriefing true'; do
    applied=false
    for ((attempt=1; attempt<=6; attempt++)); do
      if "$helper" command "$command" >/dev/null; then applied=true; break; fi
      sleep 5
    done
    [[ "$applied" == true ]] || return "$EX_TEMPFAIL"
  done
  if ! "$helper" command 'gamerule playersSleepingPercentage 50' >/dev/null; then
    log_warn 'playersSleepingPercentage gamerule is unavailable; ServerUtilities setting remains active'
  fi
}
