#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly GTNH_SETUP_VERSION="1.0.0"
readonly GTNH_SETUP_REPOSITORY="SergeyLutsky/gtnh-server-setup"
readonly GTNH_SETUP_REF="${GTNH_SETUP_REF:-main}"
readonly GTNH_SETUP_RAW_BASE="${GTNH_SETUP_RAW_BASE:-https://raw.githubusercontent.com/${GTNH_SETUP_REPOSITORY}/${GTNH_SETUP_REF}}"

declare -a GTNH_SETUP_MODULES=(
  core.sh
  logging.sh
  ui.sh
  discovery.sh
  releases.sh
  java.sh
  state.sh
  diagnostics.sh
  packages.sh
  config.sh
  mods.sh
  lifecycle.sh
  backup.sh
  doctor.sh
)

bootstrap_modules() {
  local source_path="${BASH_SOURCE[0]:-}"
  local source_dir=""
  local module=""
  local module_content=""

  if [[ -n "$source_path" && -f "$source_path" ]]; then
    source_dir="$(cd -- "$(dirname -- "$source_path")" && pwd -P)"
  fi

  if [[ -n "$source_dir" && -d "$source_dir/lib" ]]; then
    GTNH_SETUP_ROOT="$source_dir"
  else
    command -v curl >/dev/null 2>&1 || {
      printf 'Error: curl is required to load the installer modules.\n' >&2
      exit 69
    }
    GTNH_SETUP_ROOT=""
    for module in "${GTNH_SETUP_MODULES[@]}"; do
      module_content="$(curl --fail --silent --show-error --location \
        --connect-timeout 10 --max-time 60 --retry 3 \
        "${GTNH_SETUP_RAW_BASE}/lib/${module}")" || {
          printf 'Error: could not load installer module %s.\n' "$module" >&2
          exit 69
        }
      # Source from an in-memory pipe so even remote --dry-run creates no files.
      # shellcheck source=/dev/null
      source <(printf '%s\n' "$module_content")
    done
  fi

  export GTNH_SETUP_ROOT GTNH_SETUP_RAW_BASE GTNH_SETUP_VERSION
  if [[ -n "$GTNH_SETUP_ROOT" ]]; then
    for module in "${GTNH_SETUP_MODULES[@]}"; do
      # shellcheck source=/dev/null
      source "$GTNH_SETUP_ROOT/lib/$module"
    done
  fi
}

usage() {
  cat <<'EOF'
GTNH Server Setup

Usage:
  bash install.sh [options]

Options:
  --action install|update       Skip the action prompt
  --channel stable|rc           Select latest release in this channel
  --version VERSION             Select a specific stable or RC version
  --install-path PATH           Managed server path (default: /opt/gtnh)
  --backup-path PATH            Verified backup path (default: /var/backups/gtnh)
  --service-name NAME           systemd unit basename (default: gtnh)
  --port PORT                   Minecraft TCP port (default: 25565)
  --rcon-port PORT              Local administration port (default: 25575)
  --heap-mib MIB                Java heap in MiB (safe detected default)
  --view-distance CHUNKS        View distance (default: 12)
  --seed SEED                   Optional world seed
  --admin USERNAME              Offline-mode operator name
  --mods none|all|ID,ID         Optional catalogue mods (default: none)
  --release-metadata FILE       Use a release catalogue fixture
  --plain                       Force numbered text prompts
  --yes                         Accept non-mutating confirmations
  --dry-run                     Detect and plan without changing the server
  --help                        Show this help

With no options the installer presents menus. --yes is suitable for a
non-interactive one-line install when --admin is also supplied.
EOF
}

parse_args() {
  ACTION=""
  RELEASE_CHANNEL="stable"
  RELEASE_SELECTION_EXPLICIT="false"
  RELEASE_VERSION=""
  INSTALL_PATH="/opt/gtnh"
  BACKUP_PATH="/var/backups/gtnh"
  SERVICE_NAME="gtnh"
  MINECRAFT_PORT="25565"
  RCON_PORT="25575"
  HEAP_MIB=""
  VIEW_DISTANCE="12"
  WORLD_SEED=""
  ADMIN_USERNAME=""
  MOD_SELECTION="none"
  MOD_SELECTION_EXPLICIT="false"
  RELEASE_METADATA_FILE=""
  UI_FORCE_PLAIN="false"
  ASSUME_YES="false"
  DRY_RUN="false"

  while (($#)); do
    case "$1" in
      --action) ACTION="${2:-}"; shift 2 ;;
      --channel) RELEASE_CHANNEL="${2:-}"; RELEASE_SELECTION_EXPLICIT="true"; shift 2 ;;
      --version) RELEASE_VERSION="${2:-}"; RELEASE_SELECTION_EXPLICIT="true"; shift 2 ;;
      --install-path) INSTALL_PATH="${2:-}"; shift 2 ;;
      --backup-path) BACKUP_PATH="${2:-}"; shift 2 ;;
      --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
      --port) MINECRAFT_PORT="${2:-}"; shift 2 ;;
      --rcon-port) RCON_PORT="${2:-}"; shift 2 ;;
      --heap-mib) HEAP_MIB="${2:-}"; shift 2 ;;
      --view-distance) VIEW_DISTANCE="${2:-}"; shift 2 ;;
      --seed) WORLD_SEED="${2:-}"; shift 2 ;;
      --admin) ADMIN_USERNAME="${2:-}"; shift 2 ;;
      --mods) MOD_SELECTION="${2:-}"; MOD_SELECTION_EXPLICIT="true"; shift 2 ;;
      --release-metadata) RELEASE_METADATA_FILE="${2:-}"; shift 2 ;;
      --plain) UI_FORCE_PLAIN="true"; shift ;;
      --yes) ASSUME_YES="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) printf 'Error: unknown option: %s\n' "$1" >&2; usage >&2; exit "$EX_USAGE" ;;
    esac
  done

  export UI_FORCE_PLAIN

  [[ "$ACTION" == "" || "$ACTION" == "install" || "$ACTION" == "update" ]] || die "$EX_USAGE" "--action must be install or update"
  [[ "$RELEASE_CHANNEL" == "stable" || "$RELEASE_CHANNEL" == "rc" ]] || die "$EX_USAGE" "--channel must be stable or rc"
  validate_absolute_path "$INSTALL_PATH" || die "$EX_USAGE" "install path must be an absolute path without traversal"
  validate_absolute_path "$BACKUP_PATH" || die "$EX_USAGE" "backup path must be absolute"
  validate_port "$MINECRAFT_PORT" || die "$EX_USAGE" "port must be between 1 and 65535"
  validate_port "$RCON_PORT" || die "$EX_USAGE" "RCON port must be between 1 and 65535"
  [[ "$MINECRAFT_PORT" != "$RCON_PORT" ]] || die "$EX_USAGE" "Minecraft and RCON ports must differ"
  [[ "$SERVICE_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@-]*$ ]] || die "$EX_USAGE" "invalid service name"
  if ! [[ "$VIEW_DISTANCE" =~ ^[0-9]+$ ]] || ((VIEW_DISTANCE<2 || VIEW_DISTANCE>32)); then
    die "$EX_USAGE" "view distance must be 2-32"
  fi
  [[ -z "$HEAP_MIB" || "$HEAP_MIB" =~ ^[0-9]+$ ]] || die "$EX_USAGE" "heap must be MiB"
  [[ -z "$ADMIN_USERNAME" || "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_]{1,16}$ ]] || die "$EX_USAGE" "Minecraft username must be 1-16 letters, numbers, or underscores"
}

load_release_catalogue() {
  if [[ -n "$RELEASE_METADATA_FILE" ]]; then
    [[ -r "$RELEASE_METADATA_FILE" ]] || die "$EX_NOINPUT" "cannot read release metadata: $RELEASE_METADATA_FILE"
    RELEASE_CATALOGUE_JSON="$(<"$RELEASE_METADATA_FILE")"
  else
    RELEASE_CATALOGUE_JSON="$(release_fetch_catalogue)" || die "$EX_UNAVAILABLE" "could not fetch the official GTNH release catalogue"
  fi
  release_validate_catalogue "$RELEASE_CATALOGUE_JSON" || die "$EX_DATAERR" "official GTNH release metadata is malformed"
}

select_release() {
  local selector=""
  if [[ -n "$RELEASE_VERSION" ]]; then
    selector="$RELEASE_VERSION"
  elif [[ "$RELEASE_SELECTION_EXPLICIT" == "true" || "$ASSUME_YES" == "true" ]]; then
    selector="latest-${RELEASE_CHANNEL}"
  else
    selector="$(ui_release_selector)" || die "$EX_CANCELLED" "release selection cancelled"
  fi
  RESOLVED_RELEASE_JSON="$(release_resolve "$RELEASE_CATALOGUE_JSON" "$selector")" || \
    die "$EX_DATAERR" "no supported stable/RC server pack matched '$selector'"
  RELEASE_CHECKSUMS_JSON="$(release_load_checksums)" || die "$EX_UNAVAILABLE" "could not load project-pinned GTNH checksums"
  release_validate_checksums "$RELEASE_CHECKSUMS_JSON" || die "$EX_DATAERR" "project GTNH checksum catalogue is malformed"
  RESOLVED_RELEASE_JSON="$(release_attach_pinned_checksum "$RESOLVED_RELEASE_JSON" "$RELEASE_CHECKSUMS_JSON")" || \
    die "$EX_DATAERR" "GTNH $selector is not yet supported because its server-pack checksum is not pinned"
  RESOLVED_JAVA_JSON="$(java_resolve_for_release "$RESOLVED_RELEASE_JSON")" || \
    die "$EX_DATAERR" "could not select a supported Java runtime"
}

render_plan() {
  local version channel asset_url asset_name asset_sha java_major java_range port_state existing
  version="$(jq -r '.version' <<<"$RESOLVED_RELEASE_JSON")"
  channel="$(jq -r '.channel' <<<"$RESOLVED_RELEASE_JSON")"
  asset_url="$(jq -r '.serverAsset.url' <<<"$RESOLVED_RELEASE_JSON")"
  asset_name="$(jq -r '.serverAsset.name' <<<"$RESOLVED_RELEASE_JSON")"
  asset_sha="$(jq -r '.serverAsset.sha256' <<<"$RESOLVED_RELEASE_JSON")"
  java_major="$(jq -r '.recommendedMajor' <<<"$RESOLVED_JAVA_JSON")"
  java_range="$(jq -r '"\(.minimumMajor)-\(.maximumMajor)"' <<<"$RESOLVED_JAVA_JSON")"
  port_state="${DISCOVERY[port_status]}"
  existing="${DISCOVERY[managed_install]}"

  PLAN_TEXT="Action: ${ACTION^}
GTNH: ${version} (${channel})
Server pack: ${asset_name}
SHA-256: ${asset_sha}
Java: ${java_major} (pack supports ${java_range}); heap ${HEAP_MIB} MiB
Install path: ${INSTALL_PATH}
Backup path: ${BACKUP_PATH}
Service: ${SERVICE_NAME}.service
Minecraft port: ${MINECRAFT_PORT} (${port_state})
Local RCON port: ${RCON_PORT}
Administrator: ${ADMIN_USERNAME}
Optional mods: $(jq -r 'if length==0 then "none" else map(.id+" "+.version)|join(", ") end' <<<"$RESOLVED_MODS_JSON")
Existing managed install: ${existing}
RAM: ${DISCOVERY[ram_mib]} MiB
Free disk: ${DISCOVERY[disk_mib]} MiB
Local networks: ${DISCOVERY[networks]:-none detected}
Artifact URL: ${asset_url}

Dry run: ${DRY_RUN}."
  ui_message "GTNH change plan" "$PLAN_TEXT"
  log_info "Rendered plan for action=$ACTION version=$version channel=$channel path=$INSTALL_PATH port=$MINECRAFT_PORT"
}

resolve_mods() {
  MOD_CATALOGUE_JSON="$(mod_catalogue_load)" || die "$EX_UNAVAILABLE" "could not load optional-mod catalogue"
  mod_catalogue_validate "$MOD_CATALOGUE_JSON" || die "$EX_DATAERR" "optional-mod catalogue is malformed"
  if [[ "$MOD_SELECTION_EXPLICIT" != true && "$ASSUME_YES" != true ]]; then
    local installed=""
    if [[ "$ACTION" == update ]]; then installed="$(jq -r '[.mods[].id]|join(",")' "$INSTALL_PATH/.gtnh-installer/state.json")"; fi
    MOD_SELECTION="$(ui_mod_selector "$MOD_CATALOGUE_JSON" "$(jq -r .version <<<"$RESOLVED_RELEASE_JSON")" "$installed")" || die "$EX_CANCELLED" "mod selection cancelled"
  fi
  RESOLVED_MODS_JSON="$(mod_resolve "$MOD_CATALOGUE_JSON" "$(jq -r .version <<<"$RESOLVED_RELEASE_JSON")" "$MOD_SELECTION")" || die "$EX_DATAERR" "one or more selected mods are unknown or incompatible"
}

first_network() {
  local first="${DISCOVERY[networks]%%,*}"
  printf '%s\n' "${first#*=}"
}

execute_change() {
  local version sha java_package java_version work archive stage parent old backup="" rcon_password state_json old_state final_mods_json old_runtime_config_file=""
  final_mods_json="$RESOLVED_MODS_JSON"
  version="$(jq -r .version <<<"$RESOLVED_RELEASE_JSON")"; sha="$(jq -r .serverAsset.sha256 <<<"$RESOLVED_RELEASE_JSON")"
  java_package="$(jq -r .package <<<"$RESOLVED_JAVA_JSON")"
  packages_install "$java_package"
  require_commands curl jq unzip tar rsync sha256sum python3 openssl java realpath
  java_version="$(java_detect_installed)"
  work="$(mktemp -d "${TMPDIR:-/tmp}/gtnh-install.XXXXXX")"; register_cleanup_path "$work"
  archive="$(release_download_and_verify "$RESOLVED_RELEASE_JSON" "$work" "$sha")" || die "$EX_UNAVAILABLE" "server pack download or checksum verification failed"
  parent="$(dirname -- "$INSTALL_PATH")"; install -d -m 0755 -- "$parent" "$BACKUP_PATH"
  stage="$(mktemp -d "$parent/.gtnh-stage.XXXXXX")"
  archive_extract_server "$archive" "$stage" || { rm -rf -- "$stage"; die "$EX_DATAERR" "unsafe or invalid GTNH server archive"; }

  if [[ "$ACTION" == update ]]; then
    old_state="$(<"$INSTALL_PATH/.gtnh-installer/state.json")"
    if [[ "$(jq -r .gtnh.version <<<"$old_state")" == "$version" && "$(jq -c '[.mods[].id]|sort' <<<"$old_state")" == "$(jq -c '[.[].id]|sort' <<<"$RESOLVED_MODS_JSON")" ]]; then
      log_info "Requested release and mod set already installed; configuration will be reconciled"
    fi
    # On Update, an installed active catalogue mod that is not selected remains
    # installed. Explicitly retired catalogue mods are removed after backup.
    final_mods_json="$(jq -cn --argjson old "$(jq .mods <<<"$old_state")" --argjson selected "$RESOLVED_MODS_JSON" --argjson retired "$(jq '[.retiredMods[]?.id]' <<<"$MOD_CATALOGUE_JSON")" '
      ($selected|map(.id)) as $ids |
      ($old|map(. as $m | select(($ids|index($m.id)) == null and ($retired|index($m.id)) == null))) + $selected
    ')"
  fi

  mods_download "$RESOLVED_MODS_JSON" "$stage/mods" || { rm -rf -- "$stage"; die "$EX_DATAERR" "optional mod download or checksum verification failed"; }
  mods_download_runtime_requirements "$RESOLVED_MODS_JSON" "$stage/mods" || { rm -rf -- "$stage"; die "$EX_DATAERR" "optional mod dependency download or checksum verification failed"; }
  mods_download_content_packs "$RESOLVED_MODS_JSON" "$work/content-packs" || { rm -rf -- "$stage"; die "$EX_DATAERR" "quest content download or checksum verification failed"; }
  mods_validate_artifacts "$RESOLVED_MODS_JSON" "$stage/mods" || { rm -rf -- "$stage"; die "$EX_DATAERR" "optional mod content validation failed"; }
  mods_validate_runtime_requirements "$RESOLVED_MODS_JSON" "$stage/mods" || { rm -rf -- "$stage"; die "$EX_DATAERR" "optional mod runtime requirements are missing or incompatible"; }
  mods_validate_content_packs "$RESOLVED_MODS_JSON" "$work/content-packs" || { rm -rf -- "$stage"; die "$EX_DATAERR" "quest content validation failed"; }
  if [[ "$ACTION" == update ]]; then
    if [[ "${GTNH_TEST_MODE:-false}" != true ]]; then systemctl stop "$SERVICE_NAME" 2>/dev/null || true; fi
    backup="$(backup_create "$INSTALL_PATH" "$BACKUP_PATH")" || {
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
      rm -rf -- "$stage"
      die "$EX_IOERR" "pre-update backup failed"
    }
    backup_prune_auto "$BACKUP_PATH" 5
    carry_forward_mutable "$INSTALL_PATH" "$stage" || {
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
      rm -rf -- "$stage"
      die "$EX_IOERR" "could not carry the existing world and configuration into staging"
    }
    mods_remove_retired "$MOD_CATALOGUE_JSON" "$stage" || {
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
      rm -rf -- "$stage"
      die "$EX_DATAERR" "retired optional-mod removal failed"
    }
    while IFS= read -r old; do rm -f -- "$stage/mods/$(basename -- "$old")"; done < <(
      jq -r --argjson selected "$RESOLVED_MODS_JSON" '
        .mods[] as $old |
        first($selected[] | select(.id==$old.id)) as $new |
        select($new != null and $old.artifact.name != $new.artifact.name) |
        $old.artifact.name
      ' <<<"$old_state"
    )
    while IFS= read -r old; do rm -f -- "$stage/mods/$(basename -- "$old")"; done < <(
      jq -r --argjson selected "$RESOLVED_MODS_JSON" '
        .mods[] as $old |
        first($selected[] | select(.id==$old.id)) as $new |
        select($new != null) |
        $old.runtimeRequirements[]? |
        select(.artifact != null) |
        .jar as $oldJar |
        select(($new.runtimeRequirements | map(.jar) | index($oldJar)) == null) |
        $oldJar
      ' <<<"$old_state"
    )
    mods_apply_update_migrations "$old_state" "$RESOLVED_MODS_JSON" "$stage" || {
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
      rm -rf -- "$stage"
      die "$EX_DATAERR" "optional-mod update migration failed"
    }
  fi
  mods_apply_content_packs "$RESOLVED_MODS_JSON" "$work/content-packs" "$stage" || {
    [[ "$ACTION" != update || "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
    rm -rf -- "$stage"
    die "$EX_DATAERR" "quest content installation failed"
  }
  rcon_password="$(rcon_password_generate)"; log_register_secret "$rcon_password"
  config_apply "$stage" "$MINECRAFT_PORT" "$WORLD_SEED" "$VIEW_DISTANCE" "$ADMIN_USERNAME" "$RCON_PORT" "$rcon_password" || {
    [[ "$ACTION" != update || "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
    rm -rf -- "$stage"
    die "$EX_DATAERR" "upstream configuration layout is incompatible"
  }
  config_validate "$stage" || {
    [[ "$ACTION" != update || "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME" || true
    rm -rf -- "$stage"
    die "$EX_DATAERR" "managed configuration validation failed"
  }

  old="${INSTALL_PATH}.rollback.$(date +%s)"
  [[ -e "$INSTALL_PATH" ]] && mv -- "$INSTALL_PATH" "$old"
  mv -- "$stage" "$INSTALL_PATH"
  state_json="$(state_build_json "$INSTALL_PATH" "$BACKUP_PATH" "$RESOLVED_RELEASE_JSON" "$RESOLVED_JAVA_JSON" "$java_version" "${ACTION}-$(date +%s)" complete complete "$([[ -n "$backup" ]] && echo true || echo false)")"
  state_json="$(jq --argjson mods "$final_mods_json" --arg service "${SERVICE_NAME}.service" --argjson port "$MINECRAFT_PORT" --argjson rcon "$RCON_PORT" --argjson heap "$HEAP_MIB" '.mods=$mods | .installation.serviceName=$service | .installation.minecraftPort=$port | .installation.rconPort=$rcon | .installation.heapMiB=$heap' <<<"$state_json")"
  state_write_atomic "$state_json" "$INSTALL_PATH/.gtnh-installer/state.json"
  if [[ "$ACTION" == update && -f "$(system_path "/etc/${SERVICE_NAME}.conf")" ]]; then
    old_runtime_config_file="$work/previous-runtime.conf"
    install -m 0600 -- "$(system_path "/etc/${SERVICE_NAME}.conf")" "$old_runtime_config_file"
  fi
  runtime_config_write "$INSTALL_PATH" "$BACKUP_PATH" "$SERVICE_NAME" "$HEAP_MIB" "$RCON_PORT" "$rcon_password" "$([[ "$ACTION" == update ]] && printf '%s' '-Dfml.queryResult=confirm')"
  helper_install "$SERVICE_NAME"; service_install "$INSTALL_PATH" "$SERVICE_NAME" "$HEAP_MIB"
  [[ "${ASSUME_YES}" == true ]] && firewall_apply "$MINECRAFT_PORT" "$(first_network)"
  local start_ok=true health_since
  health_since="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  service_start "$SERVICE_NAME" || start_ok=false
  if [[ "$start_ok" != true ]] || ! service_wait_healthy "$SERVICE_NAME" 900 "$health_since" || ! mods_validate_post_start "$final_mods_json" "$SERVICE_NAME"; then
    log_error "new server failed startup health check"
    if [[ -n "$backup" ]]; then
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl stop "$SERVICE_NAME" || true
      mv -- "$INSTALL_PATH" "${INSTALL_PATH}.failed.$(date +%s)"; mv -- "$old" "$INSTALL_PATH"
      if [[ -n "$old_runtime_config_file" ]]; then
        install -m 0600 -- "$old_runtime_config_file" "$(system_path "/etc/${SERVICE_NAME}.conf")"
      fi
      [[ "${GTNH_TEST_MODE:-false}" == true ]] || systemctl start "$SERVICE_NAME"
    fi
    die "$EX_TEMPFAIL" "server did not reach the positive startup marker; update was rolled back"
  fi
  gamerules_apply "$SERVICE_NAME"
  # The update-only Forge confirmation is deliberately one-start-only. Future
  # missing-mod prompts must not be accepted without another verified backup.
  runtime_config_write "$INSTALL_PATH" "$BACKUP_PATH" "$SERVICE_NAME" "$HEAP_MIB" "$RCON_PORT" "$rcon_password"
  [[ -d "$old" ]] && rm -rf -- "$old"
  printf '\nGTNH %s is installed and healthy. Connect to this server on TCP %s.\n' "$version" "$MINECRAFT_PORT"
  printf 'Administration: gtnh status | gtnh logs | gtnh command "list" | gtnh backup\n'
  printf 'Minecraft EULA: https://www.minecraft.net/eula\n'
  jq -r '.[]|select(.clientRequired)|"Client mod required: \(.name) \(.version)"' <<<"$final_mods_json"
  jq -r '.[]|.runtimeRequirements[]?|select(.clientRequired==true)|"Client dependency required: \(.name)"' <<<"$final_mods_json"
  jq -r '.[]|.contentPacks[]?|"Server quest content installed: \(.name) \(.version)"' <<<"$final_mods_json"
}

main() {
  bootstrap_modules
  parse_args "$@"
  install_error_traps
  register_cleanup_handler

  export DRY_RUN
  require_commands curl
  logging_init
  ui_init

  ui_warning "Security warning" "This project will eventually run GTNH as root, as requested. A vulnerable server or mod would then control the whole VM. Keep this server isolated from unrelated secrets."

  if [[ -z "$ACTION" ]]; then
    ACTION="$(ui_action_menu)" || die "$EX_CANCELLED" "action selection cancelled"
  fi

  discovery_run "$INSTALL_PATH" "$MINECRAFT_PORT"
  discovery_enforce_platform
  if [[ "$ACTION" == "update" && "${DISCOVERY[managed_install]}" != "yes" ]]; then
    die "$EX_NOINPUT" "Update requires an installer-managed state file at $INSTALL_PATH/.gtnh-installer/state.json"
  fi
  if [[ "$ACTION" == "install" && "${DISCOVERY[managed_install]}" == "yes" ]]; then
    die "$EX_DATAERR" "A managed installation already exists at $INSTALL_PATH; choose Update"
  fi
  if [[ "$DRY_RUN" != true ]]; then
    packages_install ""
  fi
  require_commands jq
  load_release_catalogue
  select_release
  if [[ -z "$ADMIN_USERNAME" ]]; then
    if [[ "$ASSUME_YES" == true ]]; then die "$EX_USAGE" "--admin is required with --yes"; fi
    read -r -p 'Minecraft administrator username: ' ADMIN_USERNAME
    [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_]{1,16}$ ]] || die "$EX_USAGE" "invalid Minecraft username"
  fi
  [[ -n "$HEAP_MIB" ]] || HEAP_MIB="$(heap_recommended_mib "${DISCOVERY[ram_mib]}")" || die "$EX_DATAERR" "at least 8 GiB RAM is required"
  ((HEAP_MIB >= 4096 && HEAP_MIB < DISCOVERY[ram_mib])) || die "$EX_USAGE" "heap must be at least 4096 MiB and leave memory for Ubuntu"
  resolve_mods
  render_plan

  if [[ "${DISCOVERY[disk_warning]}" == "true" ]]; then
    ui_warning "Low disk space" "Less than 20 GiB is free. Installation is allowed, but GTNH and backups may exhaust this disk."
  fi

  if [[ "$DRY_RUN" == true ]]; then
    printf '\nDry run complete. No server changes were made.\n'
    printf 'Log: %s\n' "${LOG_FILE:-terminal only (dry run)}"
    return
  fi
  ui_warning "Offline-mode warning" "Usernames are not authenticated. Another permitted LAN user could impersonate the operator name."
  ui_confirm_plan "$PLAN_TEXT" || die "$EX_CANCELLED" "change cancelled"
  execute_change
}

main "$@"
