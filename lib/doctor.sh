#!/usr/bin/env bash

doctor_run() {
  local config="${1:-/etc/gtnh-server-setup.conf}" failures=0
  [[ -r "$config" ]] || { printf 'FAIL runtime config: %s\n' "$config"; return 1; }
  # shellcheck disable=SC1090
  source "$config"
  for command in java jq systemctl sha256sum; do command -v "$command" >/dev/null || { printf 'FAIL command: %s\n' "$command"; failures=$((failures+1)); }; done
  [[ -r "$GTNH_INSTALL_PATH/.gtnh-installer/state.json" ]] || { printf 'FAIL state file\n'; failures=$((failures+1)); }
  [[ -f "$GTNH_INSTALL_PATH/lwjgl3ify-forgePatches.jar" ]] || { printf 'FAIL launch jar\n'; failures=$((failures+1)); }
  config_validate "$GTNH_INSTALL_PATH" || { printf 'FAIL managed config\n'; failures=$((failures+1)); }
  systemctl is-active --quiet "$GTNH_SERVICE" || { printf 'FAIL service inactive\n'; failures=$((failures+1)); }
  ((failures==0)) && printf 'OK GTNH installation is healthy\n'
  ((failures==0))
}
