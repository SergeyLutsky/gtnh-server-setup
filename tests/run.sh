#!/usr/bin/env bash

# Fixture variables are read by functions from separately sourced modules.
# shellcheck disable=SC2034

set -Eeuo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=test_helper.bash
source "$TEST_DIR/test_helper.bash"

catalogue="$(<"$TEST_DIR/fixtures/releases.json")"
assert_success "release catalogue validates" release_validate_catalogue "$catalogue"
malformed_catalogue="$(jq '.["2.8.4"].server |= del(.java17_2XUrl)' <<<"$catalogue")"
assert_failure "missing server asset metadata fails closed" release_validate_catalogue "$malformed_catalogue"
curl() { return 22; }
assert_failure "release catalogue network failure is reported" release_fetch_catalogue
unset -f curl

stable="$(release_resolve "$catalogue" latest-stable)"
assert_eq "2.8.4" "$(jq -r '.version' <<<"$stable")" "latest stable excludes beta/nightly"
assert_eq "stable" "$(jq -r '.channel' <<<"$stable")" "stable channel is normalized"

rc="$(release_resolve "$catalogue" latest-rc)"
assert_eq "2.8.0-rc-2" "$(jq -r '.version' <<<"$rc")" "latest RC resolves by date"
assert_eq "rc" "$(jq -r '.channel' <<<"$rc")" "RC channel is normalized"

exact="$(release_resolve "$catalogue" 2.7.4)"
assert_eq "2.7.4" "$(jq -r '.version' <<<"$exact")" "specific stable resolves"
assert_failure "beta is rejected as a specific release" release_resolve "$catalogue" 2.9.0-beta-2
assert_failure "nightly is rejected as a specific release" release_resolve "$catalogue" 2.9.0-nightly-2026-07-29
assert_failure "missing release fails closed" release_resolve "$catalogue" 9.9.9

checksums="$(release_load_checksums)"
assert_success "checksum catalogue validates" release_validate_checksums "$checksums"
stable="$(release_attach_pinned_checksum "$stable" "$checksums")"
rc="$(release_attach_pinned_checksum "$rc" "$checksums")"
assert_eq "a58d771a07dd707535df01519085755398296c1e91383612d2d32ff36990c08c" "$(jq -r '.serverAsset.sha256' <<<"$stable")" "stable server pack has pinned SHA-256"
assert_eq "ee562a219ccd4268de590a169ae0a09c43647d9cfa8f61beaf62faa2f70c7971" "$(jq -r '.serverAsset.sha256' <<<"$rc")" "RC server pack has pinned SHA-256"
assert_failure "unpinned historical release fails closed" release_attach_pinned_checksum "$exact" "$checksums"

java_current="$(java_resolve_for_release "$stable")"
assert_eq "21" "$(jq -r '.recommendedMajor' <<<"$java_current")" "Java 21 selected for 17-25 pack"
assert_eq "25" "$(jq -r '.maximumMajor' <<<"$java_current")" "Java maximum comes from asset"
java_old="$(java_resolve_for_release "$exact")"
assert_eq "21" "$(jq -r '.recommendedMajor' <<<"$java_old")" "Java 21 selected for 17-21 pack"

bad_release="$(jq '.upstream.maxJavaVersion=21' <<<"$stable")"
assert_failure "Java metadata mismatch fails closed" java_resolve_for_release "$bad_release"

GTNH_STATE_TIMESTAMP='2026-08-15T12:00:00Z'
built_state="$(state_build_json /opt/gtnh /var/backups/gtnh "$stable" "$java_current" 21.0.8 install-test complete complete false)"
assert_eq "a58d771a07dd707535df01519085755398296c1e91383612d2d32ff36990c08c" "$(jq -r '.gtnh.artifact.sha256' <<<"$built_state")" "state persists resolved artifact checksum"
assert_eq "21" "$(jq -r '.gtnh.java.major' <<<"$built_state")" "state persists Java identity"
unset GTNH_STATE_TIMESTAMP

assert_eq "10.69.4.0/24" "$(cidr_network 10.69.4.111/24)" "IPv4 /24 subnet detection"
assert_eq "192.168.50.0/27" "$(cidr_network 192.168.50.9/27)" "IPv4 /27 subnet detection"
assert_eq "0.0.0.0/0" "$(cidr_network 10.1.2.3/0)" "IPv4 default subnet detection"
assert_failure "invalid IPv4 is rejected" cidr_network 300.1.2.3/24

ss_fixture="$(<"$TEST_DIR/fixtures/discovery-ss.txt")"
assert_success "occupied IPv6 wildcard port detected" port_is_occupied_from_ss 25565 "$ss_fixture"
assert_failure "unused port remains available" port_is_occupied_from_ss 25566 "$ss_fixture"

GTNH_TEST_OS_RELEASE=$'ID=ubuntu\nVERSION_ID="24.04"'
GTNH_TEST_MEMINFO='MemTotal:       33554432 kB'
GTNH_TEST_DF_OUTPUT=$'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 104857600 1024 83886080 1% /'
GTNH_TEST_IP_ADDR="$(<"$TEST_DIR/fixtures/discovery-ip.txt")"
GTNH_TEST_SS_OUTPUT="$ss_fixture"
GTNH_TEST_UFW_STATUS='Status: active'
GTNH_TEST_EUID=0
GTNH_TEST_UNAME=x86_64
discovery_run /opt/gtnh 25565
assert_eq "enp6s18=10.69.4.0/24,enp7s19=192.168.50.0/27" "${DISCOVERY[networks]}" "multiple global interfaces produce network CIDRs"
assert_eq "occupied" "${DISCOVERY[port_status]}" "discovery reports occupied selected port"
assert_eq "active" "${DISCOVERY[ufw]}" "active UFW is detected"
assert_eq "false" "${DISCOVERY[disk_warning]}" "sufficient disk avoids warning"
GTNH_TEST_DF_OUTPUT=$'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 104857600 1024 10485760 90% /'
discovery_run /opt/gtnh 25566
assert_eq "true" "${DISCOVERY[disk_warning]}" "low disk warns instead of failing discovery"
assert_failure "unsupported Ubuntu release is rejected" bash -c 'source "$1/lib/core.sh"; source "$1/lib/logging.sh"; source "$1/lib/discovery.sh"; DISCOVERY[euid]=0; DISCOVERY[os_id]=ubuntu; DISCOVERY[os_version]=20.04; DISCOVERY[architecture]=x86_64; discovery_enforce_platform 2>/dev/null' _ "$TEST_ROOT"
unset GTNH_TEST_OS_RELEASE GTNH_TEST_MEMINFO GTNH_TEST_DF_OUTPUT GTNH_TEST_IP_ADDR GTNH_TEST_SS_OUTPUT GTNH_TEST_UFW_STATUS GTNH_TEST_EUID GTNH_TEST_UNAME

UI_MODE=plain
assert_eq "install" "$(printf '1\n' | ui_action_menu)" "plain action menu selects install"
ASSUME_YES=false
assert_success "plain confirmation accepts yes" bash -c 'source "$1/lib/core.sh"; source "$1/lib/ui.sh"; UI_MODE=plain; printf "yes\n" | ui_confirm_plan "Plan"' _ "$TEST_ROOT"
whiptail() { printf 'update' >&2; }
UI_MODE=whiptail
assert_eq "update" "$(ui_action_menu)" "Whiptail action menu selects update"
unset -f whiptail

assert_eq "resumable" "$(operation_recovery_class in_progress download false)" "download interruption is resumable"
assert_eq "rollback-required" "$(operation_recovery_class in_progress switch true)" "switched install with backup needs rollback"
assert_eq "manual-recovery" "$(operation_recovery_class in_progress switch false)" "switched install without backup needs manual recovery"

secret_log="$(mktemp "${TMPDIR:-/tmp}/gtnh-log-test.XXXXXX")"
LOG_FILE="$secret_log"
secret_value='private-test-value-9f6a2d'
log_register_secret "$secret_value"
log_info "password=hunter2 token=ghp_abcdefghijklmnopqrstuvwxyz secret=$secret_value Authorization: Bearer abcdef"
if grep -Fq 'hunter2' "$secret_log" || grep -Fq 'ghp_abcdefghijklmnopqrstuvwxyz' "$secret_log" || grep -Fq "$secret_value" "$secret_log" || grep -Fq 'Bearer abcdef' "$secret_log"; then
  fail "logging removes secrets"
else
  pass "logging removes secrets"
fi
rm -f -- "$secret_log"

DRY_RUN=true
assert_failure "dry-run hard guard blocks mutation" require_mutation_allowed "test write"
DRY_RUN=false

download_destination="$(mktemp -d "${TMPDIR:-/tmp}/gtnh-download-destination.XXXXXX")"
download_partial="$download_destination/test-artifact.zip.part"
printf 'known test artifact\n' >"$download_partial"
assert_failure "incorrect artifact checksum fails closed" release_promote_verified_download "$download_partial" "$download_destination/test-artifact.zip" "0000000000000000000000000000000000000000000000000000000000000000"
if [[ -e "$download_destination/test-artifact.zip" || -e "$download_destination/test-artifact.zip.part" ]]; then
  fail "failed download removes partial artifacts"
else
  pass "failed download removes partial artifacts"
fi
rm -rf -- "$download_destination"

assert_eq "6144" "$(heap_recommended_mib 8192)" "heap reserves memory on an 8 GiB host"
assert_eq "12288" "$(heap_recommended_mib 32768)" "heap recommendation is capped at 12 GiB"
assert_failure "insufficient host RAM has no unsafe heap default" heap_recommended_mib 4096

mod_catalogue="$(mod_catalogue_load)"
assert_success "six-mod catalogue validates" mod_catalogue_validate "$mod_catalogue"
all_mods="$(mod_resolve "$mod_catalogue" 2.8.4 all)"
assert_eq "6" "$(jq length <<<"$all_mods")" "all six mods resolve for GTNH 2.8.4"
assert_eq "6" "$(jq '[.[].artifact.sha256]|unique|length' <<<"$all_mods")" "mod artifacts have unique pinned checksums"
assert_failure "unknown mod fails closed" mod_resolve "$mod_catalogue" 2.8.4 does-not-exist
UI_MODE=plain
assert_eq "gtnh-rates,ae2-things" "$(printf '1,3\n' | ui_mod_selector "$mod_catalogue" 2.8.4 '')" "plain mod checklist maps numbered choices"
assert_eq "gtnh-rates,ae2-things" "$(printf '\n' | ui_mod_selector "$mod_catalogue" 2.8.4 'gtnh-rates,ae2-things')" "update mod checklist keeps installed defaults"

config_dir="$(mktemp -d "${TMPDIR:-/tmp}/gtnh-config-test.XXXXXX")"
printf 'alpha=one\nmanaged=old\nomega=three\n' >"$config_dir/server.properties"
properties_set "$config_dir/server.properties" managed new
properties_set "$config_dir/server.properties" appended value
assert_eq "new" "$(awk -F= '$1=="managed"{print $2}' "$config_dir/server.properties")" "properties patch updates one key"
assert_eq "three" "$(awk -F= '$1=="omega"{print $2}' "$config_dir/server.properties")" "properties patch preserves unrelated keys"
printf 'managed=a\nmanaged=b\n' >"$config_dir/duplicate.properties"
assert_failure "duplicate property is rejected" properties_set "$config_dir/duplicate.properties" managed c
printf 'commands {\n  B:enabled=false\n}\nworld {\n  B:enabled=false\n}\n' >"$config_dir/sections.cfg"
cfg_set_in_section "$config_dir/sections.cfg" world 'B:enabled' true
assert_eq "false true" "$(awk -F= '/B:enabled/{printf "%s%s",sep,$2;sep=" "}' "$config_dir/sections.cfg")" "section patch changes only requested duplicate key"
printf '[player]\nserverutilities.homes.max=1\n[admin]\nserverutilities.homes.max=1\nserverutilities.homes.cross_dim: false\n' >"$config_dir/ranks.txt"
ranks_set_admin "$config_dir/ranks.txt" serverutilities.homes.max 100
ranks_set_admin "$config_dir/ranks.txt" serverutilities.homes.cross_dim true
assert_eq "100 true" "$(awk -F': ' '/^\[admin\]/{admin=1;next} admin&&/homes.max/{a=$2} admin&&/homes.cross_dim/{b=$2} END{print a,b}' "$config_dir/ranks.txt")" "admin rank patch canonicalizes equals and colon formats"
assert_eq "b50ad385-829d-3141-a216-7e7d7539ba7f" "$(offline_uuid Notch)" "offline UUID matches Minecraft algorithm"
rm -rf -- "$config_dir"

archive_dir="$(mktemp -d "${TMPDIR:-/tmp}/gtnh-archive-test.XXXXXX")"
mkdir -p "$archive_dir/safe"
printf x >"$archive_dir/safe/file"
(cd "$archive_dir" && zip -q safe.zip safe/file)
assert_success "safe zip path validates" archive_validate "$archive_dir/safe.zip"
printf 'not a zip\n' >"$archive_dir/invalid.zip"
assert_failure "invalid zip fails closed" archive_validate "$archive_dir/invalid.zip"
(cd "$archive_dir" && tar -czf safe.tar.gz safe/file)
assert_success "safe backup tar path validates" tar_archive_validate "$archive_dir/safe.tar.gz"
printf 'not a tar\n' >"$archive_dir/invalid.tar.gz"
assert_failure "invalid backup tar fails closed" tar_archive_validate "$archive_dir/invalid.tar.gz"
rm -rf -- "$archive_dir"

systemctl() { return 0; }
journalctl() { [[ "$*" == *'2026-08-15 12:34:56 UTC'* ]] && printf 'Done (1.0s)! For help, type "help"\n'; }
system_path() { printf '/bin/true\n'; }
assert_success "startup health is scoped to current restart time" service_wait_healthy test-service 1 '2026-08-15 12:34:56 UTC'
unset -f systemctl journalctl system_path

finish_tests
