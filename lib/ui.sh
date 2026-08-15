#!/usr/bin/env bash

UI_MODE="plain"

ui_init() {
  if [[ "${UI_FORCE_PLAIN:-false}" != "true" ]] && command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    UI_MODE="whiptail"
  else
    UI_MODE="plain"
  fi
  log_info "UI mode: $UI_MODE"
}

ui_message() {
  local title="$1" message="$2"
  if [[ "$UI_MODE" == "whiptail" ]]; then
    whiptail --title "$title" --msgbox "$message" 22 78
  else
    printf '\n== %s ==\n%s\n' "$title" "$message"
  fi
}

ui_warning() {
  ui_message "$1" "$2"
}

ui_action_menu() {
  local choice
  if [[ "$UI_MODE" == "whiptail" ]]; then
    choice="$(whiptail --title "GTNH Server Setup" --menu "Choose an action" 15 64 2 \
      install "Install a new managed GTNH server" \
      update "Update an existing managed GTNH server" 3>&1 1>&2 2>&3)" || return "$EX_CANCELLED"
    printf '%s\n' "$choice"
    return
  fi
  printf '\nGTNH Server Setup\n  1) Install GTNH\n  2) Update GTNH\n' >&2
  while true; do
    read -r -p 'Choose [1-2]: ' choice || return "$EX_CANCELLED"
    case "$choice" in
      1|install) printf 'install\n'; return ;;
      2|update) printf 'update\n'; return ;;
      *) printf 'Please choose 1 or 2.\n' >&2 ;;
    esac
  done
}

ui_release_selector() {
  local choice version
  if [[ "$UI_MODE" == "whiptail" ]]; then
    choice="$(whiptail --title "GTNH release" --menu "Choose a supported release" 17 72 3 \
      latest-stable "Latest stable (recommended)" \
      latest-rc "Latest release candidate" \
      specific "Specific stable or release candidate" 3>&1 1>&2 2>&3)" || return "$EX_CANCELLED"
    if [[ "$choice" == "specific" ]]; then
      version="$(whiptail --title "GTNH version" --inputbox "Enter an exact stable or RC version" 10 64 3>&1 1>&2 2>&3)" || return "$EX_CANCELLED"
      printf '%s\n' "$version"
    else
      printf '%s\n' "$choice"
    fi
    return
  fi
  printf '\nRelease\n  1) Latest stable (recommended)\n  2) Latest release candidate\n  3) Specific stable/RC version\n' >&2
  while true; do
    read -r -p 'Choose [1-3]: ' choice || return "$EX_CANCELLED"
    case "$choice" in
      1) printf 'latest-stable\n'; return ;;
      2) printf 'latest-rc\n'; return ;;
      3) read -r -p 'Exact version: ' version; printf '%s\n' "$version"; return ;;
      *) printf 'Please choose 1, 2, or 3.\n' >&2 ;;
    esac
  done
}

ui_confirm_plan() {
  local message="$1" answer
  [[ "${ASSUME_YES:-false}" == "true" ]] && return 0
  if [[ "$UI_MODE" == "whiptail" ]]; then
    whiptail --title "Confirm changes" --yesno "$message" 22 78
    return $?
  fi
  read -r -p "$message Continue? [y/N]: " answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}
