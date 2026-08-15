# GTNH Server Setup — Implementation Plan

## Delivery strategy

Implement the project in small, testable layers. Each phase must be usable by the next phase and must include automated verification. Remote VM mutation starts only after local static and fixture-based checks pass.

## Phase 1 — Repository foundation and contracts

### Build

- Define repository layout for the bootstrap, libraries, catalogue, configuration rules, tests, and documentation.
- Add strict Bash conventions and a shared error/cleanup framework.
- Define the installer state schema and mod catalogue schema.
- Add a JSON schema or equivalent validator for declarative files.
- Add a safe logging/redaction layer.
- Define command exit codes and resumable operation markers.

### Verify

- Shell syntax/lint checks pass.
- Catalogue and state fixtures validate.
- Secrets placed in test inputs are absent from captured logs.
- Interrupted-operation fixtures can be classified as resumable or rollback-required.

## Phase 2 — Terminal UI, discovery, and dry run

### Build

- Implement Whiptail UI with plain-terminal fallback.
- Implement root, Ubuntu, architecture, package, RAM, disk, network, UFW, port, and existing-install detection.
- Implement the Install/Update main menu.
- Implement final plan rendering and confirmation.
- Implement `--dry-run` with a hard no-mutation guard.
- Add timestamped log directories and redacted diagnostic bundle generation.

### Verify

- Scripted prompt tests cover Whiptail and fallback modes.
- Dry-run filesystem/service/firewall snapshots are identical before and after execution.
- Low disk produces a warning and explicit confirmation instead of blocking.
- Port and local-subnet detection fixtures cover IPv4 edge cases and multiple interfaces.

## Phase 3 — GTNH release and Java resolution

### Research/build

- Confirm authoritative stable and release-candidate sources.
- Implement release-channel filtering that excludes nightlies.
- Resolve exact server-pack assets for selected releases.
- Resolve the compatible Java runtime from server-pack metadata/naming and official guidance.
- Download into staging with retries, timeouts, and partial-download cleanup.
- Verify available upstream checksums; where upstream does not publish them, record project-pinned SHA-256 values in version metadata.
- Persist artifact identity and checksum in installer state.

### Verify

- Stable, RC, exact-version, excluded-nightly, missing-asset, and network-failure fixtures pass.
- Incorrect checksums fail closed before extraction.
- Java resolution is correct for every supported GTNH test fixture.

## Phase 4 — Native installation and service lifecycle

### Build

- Install required Ubuntu packages idempotently.
- Stage and extract the selected server pack.
- Configure memory using the detected recommendation and administrator choice.
- Install a systemd service running as root with boot enablement and crash-only restart behavior.
- Implement graceful stop, shutdown timeout, forced-stop reporting, and startup health checks.
- Implement local-only RCON with generated root-readable credentials.
- Implement the initial `gtnh` commands: `status`, `start`, `stop`, `restart`, `logs`, and `command`.

### Verify

- Repeated installation does not duplicate packages, units, or settings.
- Manual stop remains stopped.
- Forced process failure restarts after the configured delay.
- Startup health distinguishes healthy, timed-out, and crashed states.
- RCON works locally and is not exposed by an installer-created firewall rule.

## Phase 5 — Version-aware configuration engine

### Build

- Implement safe key-level patchers for Java properties, Forge-style `.cfg` files, gamerules, and ServerUtilities ranks.
- Preserve comments and unrelated keys where practical; otherwise use parse-render validation with explicit backups.
- Apply all settings in `PROJECT-SPEC.md` section 9.
- Apply configuration before initial world creation.
- Detect drift and show it in the final plan.
- Add version adapters for known config syntax/path changes.
- Validate that required keys exist after patching.

### Verify

- Golden-file tests cover every managed key.
- Existing unrelated edits survive.
- Missing, duplicated, moved, and malformed keys fail with actionable diagnostics.
- A second application produces no diff.
- World-generation settings are applied before the first healthy server start.

## Phase 6 — Optional mod catalogue

### Research

For each of the six initial repositories:

- map GTNH versions to supported mod releases;
- identify exact downloadable JAR assets and filename invariants;
- calculate/pin SHA-256 values;
- inspect JAR metadata and source documentation for client/server side requirements;
- identify dependencies, conflicts, config keys, and migrations;
- document required `GregTech.lang` or full-config resets;
- identify equivalent explosion settings to disable;
- define supported combined sets.

### Build

- Implement the individual mod checklist and installed/update/compatibility states.
- Disable incompatible entries with reasons.
- Resolve dependencies and conflicts before download.
- Install verified JARs and repository-managed settings.
- Preserve and report unmanaged JARs.
- Preselect compatible updates for installed catalogue mods.
- Keep unchecked installed mods; implement removal as a separate confirmed operation.
- Generate the required client-mod summary.

### Verify

- Unit fixtures cover compatible, incompatible, missing dependency, conflict, pre-release, update, removal, and unmanaged cases.
- Every approved artifact passes checksum verification.
- Known incompatible selections cannot proceed.
- Each supported combination starts in a clean staged server fixture before being marked supported.

## Phase 7 — Backups, update transaction, and rollback

### Build

- Implement manual and automatic update snapshots with manifests and checksums.
- Implement archive testing and required-content validation.
- Implement five-snapshot automatic retention without removing manual snapshots.
- Implement staged forward-only GTNH updates.
- Carry forward worlds, mutable player/quest/map data, unrelated config keys, and unmanaged mods.
- Apply mod/config migrations after staging.
- Atomically switch the live installation where the filesystem permits; otherwise use a journaled, resumable switch.
- On health failure, collect diagnostics, restore the full pre-update snapshot, restart the old version, and verify it.
- Implement `gtnh backup`, `restore`, and `update`.

### Verify

- Successful forward update preserves deterministic world/config/mod fixtures.
- Downgrade selection is refused.
- Corrupt/incomplete snapshots cannot restore.
- Simulated power/interruption points resume or roll back without mixed-version state.
- Deliberately broken startup triggers automatic rollback and healthy restart of the old version.
- Retention deletes only eligible automatic snapshots.

## Phase 8 — Diagnostics and doctor command

### Build

- Implement `gtnh doctor` checks for Java, service unit, process, port, RCON, filesystem ownership, free space, installed state, checksums, configs, mod compatibility, backups, and recent crash indicators.
- Generate redacted diagnostic bundles from installer failures and doctor runs.
- Add concise remediation text for common failures.

### Verify

- Fault-injection fixtures produce the expected diagnosis.
- Credential/world-data scanning proves bundles are redacted.
- Doctor is read-only unless an explicit future repair mode is added.

## Phase 9 — Local integration test matrix

### Build/verify

- Add disposable test roots and mocked system/package/firewall adapters for safe integration tests.
- Test clean install planning, no-op rerun, forward update, mod add/update/remove, unmanaged mod preservation, config migration, backup, restore, and rollback.
- Test both Whiptail and plain prompt flows.
- Test stable and RC release selection with pinned fixtures.
- Run shell lint, schema validation, unit tests, integration tests, redaction scans, and idempotency checks in CI.

### Exit gate

No remote VM testing begins until all local tests pass and the exact remote targets are printed for review.

## Phase 10 — Isolated Ubuntu VM end-to-end validation

### Safety boundary

- Reconfirm the VM identity and Ubuntu details read-only.
- Use a temporary, explicitly resolved test directory rather than `/opt/gtnh`.
- Use a nonstandard Minecraft port rather than `25565`.
- Use a separate test backup/log path.
- Record exact created paths, packages, unit names, and firewall rules for cleanup.
- Never touch the future production `/opt/gtnh` location.

### Scenarios

1. One-line GitHub launch and dry run.
2. Clean stable install with no optional mods.
3. Re-run/idempotency check.
4. Selected offered-mod compatible installation and retired-mod removal.
5. Forward stable or RC update.
6. Optional-mod update and unmanaged-mod preservation.
7. Forced bad JAR/config startup failure and automatic rollback.
8. Manual backup, verified restore, and corrupted-backup refusal.
9. Reboot and systemd boot-start verification.
10. Crash restart versus deliberate-stop behavior.
11. LAN-only Minecraft access and non-exposed RCON verification.
12. Diagnostic bundle redaction review.

### Cleanup

- Stop and disable only the test unit.
- Remove only recorded isolated test paths and installer-created test firewall rules.
- Report remaining packages and why they were retained.
- Verify `/opt/gtnh` remains absent or unchanged.

## Phase 11 — Documentation and release readiness

### Build

- Replace the placeholder README with prerequisites, the one-line command, trust warning, screenshots/examples of menus, supported Ubuntu/GTNH versions, service/helper commands, backup/restore guidance, client-mod output, troubleshooting, and uninstall/test-cleanup instructions.
- Document how to add or update a catalogue mod safely.
- Document state/config schemas and migration rules for maintainers.
- Add release checklist and compatibility matrix.

### Final acceptance

- Run the complete local and remote test matrices.
- Review all shell execution paths for quoting, path traversal, archive extraction, symlink, permission, and secret-handling risks.
- Confirm all acceptance criteria in `PROJECT-SPEC.md` section 14 with recorded evidence.
- Tag the first supported release only after the isolated VM test passes.

## Recommended implementation order

Start with Phases 1–3, then stop for a review of the resolved GTNH download/Java contracts. Continue with Phases 4–6, review the real server and mod compatibility results, then implement transactional updates and complete the validation phases.
