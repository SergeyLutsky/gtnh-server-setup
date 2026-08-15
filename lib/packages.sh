#!/usr/bin/env bash

readonly GTNH_REQUIRED_PACKAGES=(curl jq unzip zip tar rsync iproute2 whiptail ufw python3 openssl ca-certificates)

packages_install() {
  local java_package="$1"
  require_mutation_allowed "install system packages" || return $?
  if [[ "${GTNH_TEST_MODE:-false}" == "true" ]]; then
    printf 'apt-install %s %s\n' "${GTNH_REQUIRED_PACKAGES[*]}" "$java_package" >>"${GTNH_TEST_ACTION_LOG:?}"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  if [[ -n "$java_package" ]]; then
    apt-get install -y --no-install-recommends "${GTNH_REQUIRED_PACKAGES[@]}" "$java_package"
  else
    apt-get install -y --no-install-recommends "${GTNH_REQUIRED_PACKAGES[@]}"
  fi
}

heap_recommended_mib() {
  local ram_mib="$1" reserve=2048 heap
  ((ram_mib >= 8192)) || return "$EX_DATAERR"
  ((ram_mib >= 24576)) && reserve=4096
  heap=$((ram_mib - reserve))
  ((heap > 12288)) && heap=12288
  ((heap < 6144)) && heap=6144
  printf '%s\n' "$heap"
}
