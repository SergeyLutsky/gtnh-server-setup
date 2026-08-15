#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly GTNH_SETUP_VERSION="0.1.0-dev"
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
GTNH Server Setup (phases 1-3)

Usage:
  bash install.sh --dry-run [options]

Options:
  --action install|update       Skip the action prompt
  --channel stable|rc           Select latest release in this channel
  --version VERSION             Select a specific stable or RC version
  --install-path PATH           Managed server path (default: /opt/gtnh)
  --port PORT                   Minecraft TCP port (default: 25565)
  --release-metadata FILE       Use a release catalogue fixture
  --plain                       Force numbered text prompts
  --yes                         Accept non-mutating confirmations
  --dry-run                     Detect and plan without changing the server
  --help                        Show this help

Phases 1-3 implement discovery and release/Java planning. Native installation
and update execution begin in phase 4 and are intentionally unavailable here.
EOF
}

parse_args() {
  ACTION=""
  RELEASE_CHANNEL="stable"
  RELEASE_SELECTION_EXPLICIT="false"
  RELEASE_VERSION=""
  INSTALL_PATH="/opt/gtnh"
  MINECRAFT_PORT="25565"
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
      --port) MINECRAFT_PORT="${2:-}"; shift 2 ;;
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
  validate_port "$MINECRAFT_PORT" || die "$EX_USAGE" "port must be between 1 and 65535"
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
Java: ${java_major} (pack supports ${java_range})
Install path: ${INSTALL_PATH}
Minecraft port: ${MINECRAFT_PORT} (${port_state})
Existing managed install: ${existing}
RAM: ${DISCOVERY[ram_mib]} MiB
Free disk: ${DISCOVERY[disk_mib]} MiB
Local networks: ${DISCOVERY[networks]:-none detected}
Artifact URL: ${asset_url}

No files, packages, services, or firewall rules will be changed in dry-run mode."
  ui_message "GTNH change plan" "$PLAN_TEXT"
  log_info "Rendered plan for action=$ACTION version=$version channel=$channel path=$INSTALL_PATH port=$MINECRAFT_PORT"
}

main() {
  bootstrap_modules
  parse_args "$@"
  install_error_traps
  register_cleanup_handler

  if [[ "$DRY_RUN" != "true" ]]; then
    die "$EX_UNIMPLEMENTED" "phases 1-3 support planning only; rerun with --dry-run"
  fi
  export DRY_RUN

  require_commands curl jq
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
  load_release_catalogue
  select_release
  render_plan

  if [[ "${DISCOVERY[disk_warning]}" == "true" ]]; then
    ui_warning "Low disk space" "Less than 20 GiB is free. Installation is allowed, but GTNH and backups may exhaust this disk."
  fi

  printf '\nDry run complete. No server changes were made.\n'
  printf 'Log: %s\n' "${LOG_FILE:-terminal only (dry run)}"
}

main "$@"
