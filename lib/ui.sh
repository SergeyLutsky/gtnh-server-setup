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

ui_mod_selector() {
  local catalogue="$1" gtnh="$2" installed_csv="${3:-}" row id name version default choice output="" index=0
  local -a rows=() args=()
  installed_csv="$(jq -r --arg installed "$installed_csv" '
    ($installed|split(",")) as $ids |
    [.mods[].id as $id | select(($ids|index($id)) != null) | $id] | join(",")
  ' <<<"$catalogue")"
  mapfile -t rows < <(jq -c '.mods[]' <<<"$catalogue")
  if [[ "$UI_MODE" == whiptail ]]; then
    for row in "${rows[@]}"; do
      id="$(jq -r .id <<<"$row")"; name="$(jq -r .name <<<"$row")"
      version="$(jq -r --arg g "$gtnh" 'first(.releases[]|select(.gtnh==$g)|.version)//"incompatible"' <<<"$row")"
      default=OFF; [[ ",$installed_csv," == *",$id,"* ]] && default=ON
      args+=("$id" "$name ($version)" "$default")
    done
    choice="$(whiptail --title 'Optional GTNH mods' --checklist 'Space selects. No mods are selected on a clean install.' 22 78 12 "${args[@]}" 3>&1 1>&2 2>&3)" || return "$EX_CANCELLED"
    choice="${choice//\"/}"; choice="${choice// /,}"
    printf '%s\n' "${choice:-none}"
    return
  fi
  printf '\nOptional mods (comma-separated numbers; blank keeps defaults)\n' >&2
  for row in "${rows[@]}"; do
    index=$((index+1)); id="$(jq -r .id <<<"$row")"; name="$(jq -r .name <<<"$row")"
    version="$(jq -r --arg g "$gtnh" 'first(.releases[]|select(.gtnh==$g)|.version)//"incompatible"' <<<"$row")"
    default=' '; [[ ",$installed_csv," == *",$id,"* ]] && default=x
    printf '  %d) [%s] %s (%s)\n' "$index" "$default" "$name" "$version" >&2
  done
  read -r -p 'Selection: ' choice || return "$EX_CANCELLED"
  if [[ -z "$choice" ]]; then printf '%s\n' "${installed_csv:-none}"; return; fi
  IFS=, read -ra selected <<<"$choice"
  for index in "${selected[@]}"; do
    [[ "$index" =~ ^[0-9]+$ ]] && ((index>=1 && index<=${#rows[@]})) || return "$EX_USAGE"
    id="$(jq -r .id <<<"${rows[index-1]}")"
    output="${output:+$output,}$id"
  done
  printf '%s\n' "${output:-none}"
}
