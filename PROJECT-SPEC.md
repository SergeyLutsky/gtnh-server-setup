# GTNH Server Setup — Project Specification

## 1. Purpose

Build a GitHub-hosted, interactive Bash installer for a single GT New Horizons (GTNH) server on Ubuntu. An administrator runs the latest script directly from this repository, chooses **Install** or **Update**, chooses a supported GTNH release and optional community mods, and receives a configured, supervised, recoverable server.

The intended entry point is:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)"
```

The script must clearly document that this command trusts the current contents of the repository's `main` branch.

## 2. Goals

- Install a working GTNH dedicated server on Ubuntu with minimal manual file editing.
- Update an existing managed installation without losing the world, player state, local configuration, or optional mods.
- Present GTNH and optional-mod choices through a friendly terminal UI.
- Apply a curated private-server gameplay configuration.
- Make every update recoverable through verified backups and automatic rollback.
- Provide straightforward day-to-day administration commands.
- Keep version, mod, dependency, migration, and configuration knowledge in repository-managed data instead of scattering it through the installer.

## 3. Non-goals for Version 1

- Docker or other container deployment.
- Multiple GTNH instances on one Ubuntu server.
- Nightly GTNH releases.
- GTNH downgrades outside an explicit backup restore.
- Unattended installation or update.
- A web UI.
- Automatic upload of logs, diagnostics, telemetry, or world data.
- Managing player-side mod installation. The installer only reports which selected mods clients must install.

## 4. Target Deployment

| Concern | Decision |
|---|---|
| Deployment | Native Ubuntu installation |
| Process owner | `root`, with a prominent security warning |
| Instances | One server per machine |
| Service manager | `systemd` |
| Start policy | Start automatically at boot |
| Crash policy | Restart after unexpected failure with a delay |
| Deliberate stop | Remain stopped |
| Default install path | `/opt/gtnh`, editable during installation |
| Default backup path | `/var/backups/gtnh`, editable during installation |
| Installer logs | `/var/log/gtnh-installer/` |

Running Minecraft as root is an explicit project decision, not a recommended general practice. The installer must warn that a vulnerable server or mod would then have full control of the VM. Repository credentials, GitHub tokens, and unrelated secrets must never be placed in the GTNH directory, logs, or diagnostics.

## 5. User Experience

### 5.1 Interface

- Use Whiptail menus when available.
- Fall back to plain numbered terminal prompts if Whiptail cannot be used.
- Show a final change summary before any mutating Install or Update operation.
- Support `--dry-run`. Dry run performs detection, release/mod resolution, compatibility checks, configuration planning, port checks, and disk estimation without stopping services or writing files.
- Version 1 is otherwise interactive only.

### 5.2 Main menu

The script asks for one primary action:

1. Install GTNH
2. Update GTNH

It may also expose clearly secondary maintenance actions such as diagnostics or restore, but Install and Update remain the primary entry flow.

### 5.3 Logs and failures

- Write detailed, timestamped, sanitized logs.
- Keep terminal output concise and show the persistent log path.
- On failure, create a local redacted diagnostic bundle containing:
  - installer log;
  - detected Ubuntu, Java, GTNH, and mod versions;
  - service status;
  - configuration validation results;
  - recent GTNH startup logs.
- Exclude credentials, RCON secrets, unrelated environment variables, and world data.
- Never upload diagnostics automatically.

## 6. Install Workflow

The Install flow must:

1. Confirm it is running as root and on a supported Ubuntu environment.
2. Detect architecture, OS version, RAM, free disk space, network interfaces, active UFW state, occupied ports, and any existing managed installation.
3. Warn rather than block on low disk space. A new installation uses 20 GB free as the warning threshold.
4. Offer GTNH release choices:
   - latest stable (recommended/default);
   - latest release candidate;
   - a specific stable or release-candidate version.
5. Exclude nightly builds.
6. Resolve the matching official server pack and automatically select/install its supported Java runtime.
7. Prompt for Java heap size using a safe value calculated from detected RAM while reserving memory for Ubuntu.
8. Prompt for the install path, defaulting to `/opt/gtnh`.
9. Prompt for the Minecraft TCP port, defaulting to `25565`, and verify availability.
10. If UFW is active, offer to allow the Minecraft port only from the detected local subnet. Do not enable or broadly reconfigure UFW.
11. Ask for the administrator's Minecraft username and grant Minecraft operator plus ServerUtilities admin status.
12. Show the optional-mod checklist. No optional mods are selected by default.
13. Download all artifacts to staging, verify them, and construct the installation before switching it live.
14. Apply the managed server, GTNH, ServerUtilities, and mod configuration.
15. Write `eula=true` automatically and include a Minecraft EULA link in the final summary.
16. Install and enable the systemd service and administration helper.
17. Start the server and wait for a positive startup health signal.
18. Show connection information, selected versions, required client mods, service state, and log paths.

## 7. GTNH Release and Java Policy

- Resolve releases from authoritative GTNH sources at runtime.
- Stable and release-candidate GTNH releases are supported; nightly builds are not.
- A new installation can select the latest stable, latest RC, or a specific stable/RC version.
- Java selection is automatic and based on the chosen official server pack.
- Updates can only move forward. A lower GTNH version is available only by restoring a compatible snapshot.
- Store installed GTNH version, channel, server-pack asset identity, Java identity, and checksums in installer state.
- Prefer the Java arguments shipped with the selected GTNH server pack; alter only managed memory/service integration unless testing proves a version-specific change is necessary.

## 8. Resource and Network Defaults

| Setting | Required behavior |
|---|---|
| Heap | Prompt with a safe detected default |
| Minecraft port | Prompt, default `25565`, validate availability |
| Firewall | If UFW is active, ask before adding a local-subnet-only TCP rule |
| Internet exposure | Do not create a globally open UFW rule |
| Max players | `20` |
| View distance | Prompt, default `12` |
| Difficulty | Prompt, default Hard |
| World seed | Optional prompt; blank means random |
| World pre-generation | Do not run automatically; show an optional post-install command |
| Empty server | Continue ticking so chunk-loaded automation keeps running |

## 9. Managed Gameplay Configuration

Configuration is version-aware and key-level. The installer changes only declared keys, preserving unrelated local values unless an upstream mod migration explicitly requires a reset.

### 9.1 Minecraft core settings

| Key | Value/behavior |
|---|---|
| `eula` | `true` in `eula.txt` |
| `online-mode` | `false` |
| `white-list` | `false` by default |
| `max-players` | `20` |
| `difficulty` | Hard |
| `view-distance` | `12` by default, editable |
| `pvp` | `false` |
| `allow-flight` | `true` |
| `spawn-protection` | `0` |
| `server-port` | Selected port |
| `level-seed` | Optional selected seed |

The installer must warn that offline mode does not authenticate usernames and that another permitted LAN user could impersonate an operator name.

### 9.2 World generation

Apply before generating a new world:

```ini
# config/GregTech/WorldGeneration.cfg
B:generateUndergroundDirtGen=false
B:generateUndergroundGravelGen=false

# config/RWG.cfg
B:"Generate Caves"=false
B:"Generate Mineshafts"=false
B:"Generate Underground Lakes"=false
B:"Generate Underground Lava Lakes"=false
```

Leave GregTech ore veins, villages, surface structures, and cobblestone boulders enabled.

### 9.3 GregTech

```ini
# config/GregTech/Pollution.cfg
B:"Activate Pollution"=false

# config/GregTech/GregTech.cfg
B:machineExplosions=false
```

When an optional add-on has its own equivalent explosion setting, disable that setting too.

### 9.4 Forestry

```ini
# config/forestry/common.cfg
B:disable.butterfly=true
```

### 9.5 ServerUtilities

Required behavior:

```ini
B:home=true
B:back=true
B:chunk_claiming=true
B:chunk_loading=true
S:enable_pvp=FALSE
```

The installer must enable/configure the ServerUtilities permission/rank machinery required for these values:

```text
serverutilities.claims.max_chunks: 1000
serverutilities.chunkloader.max_chunks: 500
serverutilities.homes.max: 100
serverutilities.homes.warmup: 0s
serverutilities.homes.cooldown: 0s
serverutilities.homes.cross_dim: true
```

Live-world backup policy:

```ini
B:enable_backups=true
S:backup_timer=0.5
I:backups_to_keep=12
B:need_online_players=true
B:only_backup_claimed_chunks=false
B:use_separate_thread=true
```

Other gameplay behavior:

- 50% of online players must sleep to skip night.
- Disable fire spread (`doFireTick=false`).
- Keep mob griefing enabled.
- Keep automatic scheduled shutdown/restart disabled.
- Keep ServerUtilities/GTNH world processing active when no players are online.

## 10. Optional Mod Catalogue

### 10.1 Initial catalogue

1. `https://github.com/Sladki/GTNHRates`
2. `https://github.com/reobf/Programmable-Hatches-Mod`
3. `https://github.com/asdflj/AE2Things`
4. `https://github.com/Nxer/Twist-Space-Technology-Mod`
5. `https://github.com/CallmeSHaobe/123Technology`
6. `https://github.com/ABKQPO/GT-Not-Leisure`

### 10.2 Catalogue data

Each entry must be declarative and contain at least:

- stable identifier and display name;
- official project/source URL;
- supported GTNH release range or explicit GTNH-to-mod mapping;
- approved release/tag and exact asset selection rule;
- SHA-256 checksum;
- server/client side requirements;
- required and optional dependencies;
- known conflicts and combination constraints;
- installation filename and any filename invariants;
- managed configuration keys;
- install/update migrations;
- required configuration or language-file resets;
- tested combination identifier/status.

### 10.3 Selection and update behavior

- Use an individual checklist rather than presets.
- Show installed/not-installed state, current version, approved available version, client requirement, and compatibility status.
- Select no optional mods by default on a clean installation.
- Incompatible mods remain visible but disabled with an explanation.
- Do not provide a force-install escape hatch for known-incompatible versions.
- Allow curated pre-release mod builds only after they are pinned and tested by this project.
- Validate the full selected combination, not merely each JAR in isolation.
- Enforce required dependencies and known conflicts.
- On Update, preselect all compatible approved updates for installed catalogue mods; allow the administrator to uncheck them.
- Not selecting an installed mod during Update leaves it installed.
- Removal is a separate explicit, confirmed operation.
- Preserve manually added/unmanaged JARs and warn that their compatibility is not verified.
- Print a client mod list after installation/update.

### 10.4 Mod configuration migrations

- Apply repository-managed keys while preserving unrelated local settings.
- If upstream documentation requires a complete config or language-file reset, back up the old file, perform the reset, and reapply managed settings.
- Support documented migrations such as `GregTech.lang` regeneration and mod-specific config replacement.
- Never copy an entire old GTNH configuration directory over a newer server pack.

## 11. Update, Backup, and Rollback

### 11.1 Pre-update behavior

- Detect and report installed GTNH, Java, catalogue mods, unmanaged mods, and installer schema versions.
- Resolve only forward GTNH updates.
- Build the target version in staging.
- Estimate required disk space for the staged pack, backup, and 5 GB remaining headroom.
- Low space is a warning requiring explicit confirmation, not a hard block.
- Show the exact planned GTNH, Java, mod, config, migration, service, and firewall changes.

### 11.2 Snapshot contents

Create a recoverable pre-update snapshot containing:

- worlds and dimension data;
- player and quest data;
- relevant map/prospecting data;
- server and mod configs;
- whitelist/operator/permission data;
- catalogue and unmanaged mods;
- installer state and service configuration.

Exclude disposable logs, caches, downloaded staging files, and unrelated secrets.

### 11.3 Snapshot retention and integrity

- Default path: `/var/backups/gtnh`.
- Keep the latest five automatic update snapshots.
- Never delete manually named backups automatically.
- Generate checksums and a contents manifest.
- Test archive integrity and verify required content before accepting a snapshot.
- Refuse restoration from a damaged or structurally incomplete snapshot.

### 11.4 Update health and rollback

- Stop the service cleanly and confirm shutdown before switching versions.
- Start the updated server and wait for a positive GTNH startup health signal within a version-aware timeout.
- On failure, retain diagnostics, stop the failed version, restore the complete pre-update snapshot, restart the previous version, and verify its health.
- Report both the original update failure and rollback result.

## 12. Administration Helper

Install a `gtnh` helper command supporting:

```text
gtnh status
gtnh start
gtnh stop
gtnh restart
gtnh logs
gtnh command "<minecraft command>"
gtnh backup [name]
gtnh restore <snapshot>
gtnh update
gtnh doctor
```

`gtnh command` uses local-only RCON:

- generate a strong RCON password;
- store it in a root-only file;
- do not print it or include it in logs/diagnostics;
- do not add a UFW rule for the RCON port;
- validate that the helper can send a command during installation tests.

## 13. Configuration and State Ownership

- Store a machine-readable installer state file with a schema version.
- Record installed artifact identities and checksums, not just filenames.
- Treat repository-declared keys as managed.
- Preserve all unrelated local config keys.
- Preserve unmanaged mods.
- Detect and clearly report drift from managed values before modifying it.
- Apply changes idempotently: rerunning Install/Update against the same target must not duplicate settings, rules, service entries, or files.
- Make every migration version-aware and safe to resume after interruption.

## 14. Validation and Acceptance Criteria

The project is acceptable when all of the following are demonstrated:

1. The one-line GitHub command starts the interactive installer on a supported clean Ubuntu VM.
2. A stable GTNH server installs, reaches a positive startup health signal, starts at boot, and is reachable only from the selected LAN subnet.
3. The selected gameplay configuration is present at exact keys and survives a no-op rerun.
4. Each catalogue mod is mapped to verified GTNH versions, exact release assets, checksums, dependencies, client requirements, migrations, and configuration.
5. Supported selected mod combinations start successfully together.
6. An incompatible mod is shown but cannot be selected.
7. A normal forward GTNH/mod update preserves world and local unmanaged settings.
8. A deliberately broken update triggers automatic rollback and returns the old server to a healthy state.
9. Backup integrity checks detect a deliberately corrupted archive and block restore.
10. `--dry-run` makes no filesystem, firewall, package, or service changes.
11. All `gtnh` helper commands work, including local RCON.
12. Logs and diagnostic bundles contain no configured secrets or world data.
13. The isolated Ubuntu test installation can be removed without touching the future `/opt/gtnh` production location.

## 15. Implementation-time Research Items

These do not require new product decisions, but must be resolved and documented before release:

- Supported Ubuntu versions and CPU architectures.
- Authoritative GTNH stable/RC discovery endpoints and server-pack asset selection.
- Version-to-Java compatibility extraction.
- Safe heap recommendation formula.
- Exact positive startup marker and timeout for each supported GTNH line.
- Exact ServerUtilities rank/permission enablement needed for configured limits.
- Exact release asset, filename, checksum, side requirement, dependency graph, config surface, and compatibility mapping for all offered mods, plus exact-artifact migrations for retired mods.
- Compatibility of the offered mod combinations for each supported GTNH release.
- Version-specific config syntax changes and migration rules.
- Package dependencies required for Whiptail, archive handling, JSON parsing, RCON, and checksums.

## 16. Canonical References

- Community-scripts direct GitHub execution pattern: <https://community-scripts-proxmoxve.mintlify.app/installation-methods>
- GTNH server setup guidance: <https://wiki.gtnewhorizons.com/wiki/Server_Setup_%28Container%29>
- Official GTNH modpack repository: <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack>
- Official GTNH releases: <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/releases>
- Official ServerUtilities repository: <https://github.com/GTNewHorizons/ServerUtilities>
- Current GTNH managed config baselines:
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/config/GregTech/WorldGeneration.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/config/GregTech/Pollution.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/config/GregTech/GregTech.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/config/RWG.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/config/forestry/common.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/serverutilities/serverutilities.cfg>
  - <https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/master/serverutilities/server/ranks.txt>
