#!/usr/bin/env bash

declare -Ag DISCOVERY=()

read_fixture_or_command() {
  local fixture_variable="$1"
  shift
  if [[ -n "${!fixture_variable:-}" ]]; then
    printf '%s\n' "${!fixture_variable}"
  else
    "$@"
  fi
}

cidr_network() {
  local cidr="$1" address prefix a b c d ip mask network
  address="${cidr%/*}"
  prefix="${cidr#*/}"
  [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && "$prefix" =~ ^[0-9]+$ ]] || return "$EX_DATAERR"
  ((prefix >= 0 && prefix <= 32)) || return "$EX_DATAERR"
  IFS=. read -r a b c d <<<"$address"
  ((a <= 255 && b <= 255 && c <= 255 && d <= 255)) || return "$EX_DATAERR"
  ip=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  if ((prefix == 0)); then mask=0; else mask=$(( (0xFFFFFFFF << (32-prefix)) & 0xFFFFFFFF )); fi
  network=$((ip & mask))
  printf '%d.%d.%d.%d/%d\n' $(((network >> 24) & 255)) $(((network >> 16) & 255)) $(((network >> 8) & 255)) $((network & 255)) "$prefix"
}

port_is_occupied_from_ss() {
  local port="$1" input="$2"
  awk -v port="$port" '
    NR == 1 && /Local Address/ { next }
    {
      endpoint=$4
      sub(/%[^:]+$/, "", endpoint)
      if (endpoint ~ (":" port "$") || endpoint ~ ("\\]" ":" port "$") || endpoint == ("*:" port)) found=1
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$input"
}

discovery_run() {
  local install_path="$1" port="$2" os_data mem_data df_data ip_data ss_data ufw_data
  local id="" version="" arch="" euid="" networks=() iface address network

  if [[ -n "${GTNH_TEST_OS_RELEASE:-}" ]]; then os_data="$GTNH_TEST_OS_RELEASE"; else os_data="$(cat /etc/os-release 2>/dev/null || true)"; fi
  id="$(awk -F= '$1=="ID"{gsub(/"/,"",$2); print $2}' <<<"$os_data")"
  version="$(awk -F= '$1=="VERSION_ID"{gsub(/"/,"",$2); print $2}' <<<"$os_data")"
  arch="${GTNH_TEST_UNAME:-$(uname -m 2>/dev/null || printf unknown)}"
  euid="${GTNH_TEST_EUID:-$EUID}"

  if [[ -n "${GTNH_TEST_MEMINFO:-}" ]]; then mem_data="$GTNH_TEST_MEMINFO"; else mem_data="$(cat /proc/meminfo 2>/dev/null || true)"; fi
  DISCOVERY[ram_mib]="$(awk '/^MemTotal:/{printf "%d", $2/1024}' <<<"$mem_data")"
  : "${DISCOVERY[ram_mib]:=0}"

  if [[ -n "${GTNH_TEST_DF_OUTPUT:-}" ]]; then df_data="$GTNH_TEST_DF_OUTPUT"; else df_data="$(df -Pk -- "$install_path" 2>/dev/null || df -Pk -- "$(dirname -- "$install_path")" 2>/dev/null || df -Pk /)"; fi
  DISCOVERY[disk_mib]="$(awk 'NR==2{printf "%d", $4/1024}' <<<"$df_data")"
  : "${DISCOVERY[disk_mib]:=0}"
  if ((DISCOVERY[disk_mib] < 20480)); then DISCOVERY[disk_warning]="true"; else DISCOVERY[disk_warning]="false"; fi

  if [[ -n "${GTNH_TEST_IP_ADDR:-}" ]]; then ip_data="$GTNH_TEST_IP_ADDR"; elif command -v ip >/dev/null 2>&1; then ip_data="$(ip -o -4 addr show scope global 2>/dev/null || true)"; else ip_data=""; fi
  while read -r iface address; do
    [[ -n "$address" ]] || continue
    network="$(cidr_network "$address")" || continue
    networks+=("$iface=$network")
  done < <(awk '{global=0; for(i=1;i<=NF;i++) if($i=="scope" && $(i+1)=="global") global=1; if(global) for(i=1;i<=NF;i++) if($i=="inet") printf "%s\t%s\n", $2, $(i+1)}' <<<"$ip_data")
  DISCOVERY[networks]="$(IFS=,; printf '%s' "${networks[*]:-}")"

  if [[ -n "${GTNH_TEST_UFW_STATUS:-}" ]]; then ufw_data="$GTNH_TEST_UFW_STATUS"; elif command -v ufw >/dev/null 2>&1; then ufw_data="$(ufw status 2>/dev/null || true)"; else ufw_data="unavailable"; fi
  if grep -qi '^Status:[[:space:]]*active' <<<"$ufw_data"; then DISCOVERY[ufw]="active"; elif grep -qi '^Status:[[:space:]]*inactive' <<<"$ufw_data"; then DISCOVERY[ufw]="inactive"; else DISCOVERY[ufw]="unavailable"; fi

  if [[ -n "${GTNH_TEST_SS_OUTPUT:-}" ]]; then ss_data="$GTNH_TEST_SS_OUTPUT"; elif command -v ss >/dev/null 2>&1; then ss_data="$(ss -H -ltn 2>/dev/null || true)"; else ss_data=""; fi
  if port_is_occupied_from_ss "$port" "$ss_data"; then DISCOVERY[port_status]="occupied"; else DISCOVERY[port_status]="available"; fi

  DISCOVERY[os_id]="$id"
  DISCOVERY[os_version]="$version"
  DISCOVERY[architecture]="$arch"
  DISCOVERY[euid]="$euid"
  if [[ -r "$install_path/.gtnh-installer/state.json" ]]; then DISCOVERY[managed_install]="yes"; else DISCOVERY[managed_install]="no"; fi
  DISCOVERY[java]="$(java_detect_installed || printf 'not installed')"
  DISCOVERY[packages]="$(discovery_packages)"
  log_info "Discovery os=$id version=$version arch=$arch euid=$euid ram_mib=${DISCOVERY[ram_mib]} disk_mib=${DISCOVERY[disk_mib]} ufw=${DISCOVERY[ufw]} port=${DISCOVERY[port_status]}"
}

discovery_packages() {
  local command missing=()
  for command in curl jq unzip tar sha256sum ip ss whiptail; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  if ((${#missing[@]})); then printf 'missing:%s' "$(IFS=,; echo "${missing[*]}")"; else printf 'ready'; fi
}

discovery_enforce_platform() {
  [[ "${DISCOVERY[euid]}" == "0" ]] || die "$EX_NOPERM" "run this installer as root"
  [[ "${DISCOVERY[os_id]}" == "ubuntu" ]] || die "$EX_UNAVAILABLE" "this installer supports Ubuntu only"
  case "${DISCOVERY[os_version]}" in
    22.04|24.04|26.04) ;;
    *) die "$EX_UNAVAILABLE" "unsupported Ubuntu release: ${DISCOVERY[os_version]:-unknown} (supported LTS releases: 22.04, 24.04, 26.04)" ;;
  esac
  case "${DISCOVERY[architecture]}" in
    x86_64|amd64) ;;
    *) die "$EX_UNAVAILABLE" "unsupported architecture: ${DISCOVERY[architecture]}" ;;
  esac
}
