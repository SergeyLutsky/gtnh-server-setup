# GTNH Server Setup

An interactive, GitHub-loaded installer and updater for a private GT New Horizons server on Ubuntu. It installs the official server pack, Java, systemd service, curated optional mods, gameplay configuration, local administration, verified backups, and automatic update rollback.

## Install

Run as `root` on a dedicated Ubuntu 22.04, 24.04, or 26.04 x86-64 server:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)"
```

The menus ask Install or Update, GTNH release, administrator username (default `LutchS`), and optional mods. A plain numbered UI is used when Whiptail is unavailable. No optional mods are selected by default on a clean install.

For a preview that writes nothing:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)" -- --dry-run --yes
```

For a repeatable non-interactive install:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)" -- \
  --yes --action install --channel stable --admin LutchS --mods all
```

Always inspect scripts before running them as root. This project deliberately runs Minecraft as root, as requested; a vulnerable server or mod would therefore control the VM. Keep the VM dedicated and do not store unrelated credentials on it.

## Managed defaults

- Install: `/opt/gtnh`; backups: `/var/backups/gtnh`; service: `gtnh.service`.
- Latest stable GTNH by default; stable and RC selection are supported when their checksum is pinned.
- Java 21 when supported by the selected official pack; safe heap chosen from host RAM.
- Offline mode, no whitelist, Hard, 20 players, view distance 12, no PvP, flight allowed.
- `LutchS` is the default level-4 operator and ServerUtilities administrator; the running server grant is reapplied after every managed install or update.
- Selected Minecraft port is LAN-scoped when UFW is already active. UFW is never enabled by this installer.
- RCON uses a generated 48-character password, a root-only file, and an explicit non-loopback firewall rejection. It is never opened in UFW.
- Worldgen caves/mineshafts/underground lakes and dirt/gravel pockets are disabled before the first world starts. Pollution, machine explosions, fire spread, and butterfly spawning are disabled.
- ServerUtilities homes, back, claims, chunk loading, ranks, half-hour live backups, and 50% sleep are configured.

Offline mode does not authenticate usernames. Another user who can reach the server can impersonate an operator name; only permit trusted LAN clients.

## Optional mods pinned for GTNH 2.8.4

- Programmable Hatches 0.1.3p53
- AE2 Things 1.2.14
- Twist Space Technology 0.7.16
- 123Technology 2.1.8_5
- GT Not Leisure 0.2.6-hotfix1
- Ore Excavation 1.1.134
- Iron Furnaces 1.2.4

Artifacts and exact SHA-256 hashes are kept in `catalog/mods.json`. Selecting Twist Space Technology automatically installs the pinned GTNH 2.8.4 Twist Stuff quest snapshot into BetterQuesting's `DefaultQuests`, verifies BetterQuesting's automatic startup load without resetting player progress, and fails or rolls back if the load is not confirmed. The installer deliberately does not follow Twist Stuff's `main` branch because it now contains GTNH 2.9 quest changes.

GT Not Leisure includes its two default quest lines in the mod JAR. The installer verifies those resources and GTNH 2.8.4's compatible BetterQuesting, automatically installs the separately pinned BetterQuestingAPI 1.1.2, and requires both quest chapters to appear in the live API before declaring startup healthy. After creating the pre-update backup, version updates also perform each author's required generated-file resets: `GregTech.lang` plus the current or legacy GT Not Leisure configuration for GT Not Leisure, and `GregTech.lang` plus `TwistSpaceTechnology.cfg` for Twist Space Technology. Same-version reconciliation preserves these files.

The original five offered mods were tested together on GTNH 2.8.4 and reached the ready state. Ore Excavation 1.1.134 and Iron Furnaces 1.2.4 are pinned from their Minecraft 1.7.10 CurseForge releases for both server and client installation. GTNH Rates is retired: it is never offered for new installations, and the next managed update removes its previously installed JAR after creating the verified backup. Selected add-ons must also be installed on each client; the installer prints the exact client list.

## Configure an existing Prism Launcher client

On Windows, install the official **GTNH 2.8.4 Java 17-25** instance in Prism Launcher first. Then open PowerShell in this repository and run:

```powershell
.\setup-client.ps1 -ServerAddress "192.168.1.50:25565" -PlayerName "LutchS"
```

The script auto-detects a standard Prism Launcher instance, verifies that it is GTNH 2.8.4, pins the instance to the Prism Minecraft profile named `LutchS`, and configures it to match the server. Add or refresh that Microsoft/Minecraft account in Prism first, then close Prism before running the script. Both native Prism instances using `.minecraft` and CurseForge-managed Prism instances using `minecraft` are supported. It installs all seven pinned server add-ons, BetterQuestingAPI 1.1.2, Extreme Sound Muffler: Legacy 1.1.1, and the pinned Outlined Ores Modern resource pack. The resource pack is enabled without removing existing packs.

Twist Stuff's pinned GTNH 2.8.4 quest snapshot is installed into BetterQuesting `DefaultQuests` using the same quest-line directories and order file as the server. GT Not Leisure's two quest chapters are embedded in its JAR and load through the bundled BetterQuesting plus the installed BetterQuestingAPI dependency; no duplicate external GTNL quest files are copied. When the Twist Space Technology or GT Not Leisure JAR changes, the script backs up and resets the author-required generated config and `GregTech.lang` files before the next launch.

Every downloaded JAR, quest archive, and resource pack is checked against its pinned size and SHA-256 in `catalog/mods.json` or `catalog/client-addons.json`. Re-running the command is safe; replaced or removed files and edited configuration are copied to `.gtnh-client-backups` inside the instance.

If Prism is portable or more than one matching instance exists, identify it explicitly:

```powershell
.\setup-client.ps1 `
  -InstancePath "D:\PrismLauncher\instances\GT New Horizons 2.8.4" `
  -ServerAddress "play.example.net:25565" `
  -PlayerName "LutchS" `
  -MemoryMB 8192
```

Use `-PlayerName` to select a different existing Prism Minecraft profile. Use `-Mods none` for a server with no optional server add-ons, or pass a quoted comma-separated subset such as `-Mods "programmable-hatches,ae2-things"`. Omit `-ServerAddress` to leave the multiplayer list unchanged. Use `-SkipMemoryConfiguration` to preserve the instance's current Prism memory settings, `-SkipClientExtras` to omit Extreme Sound Muffler and Outlined Ores, or `-SkipQuestContent` to omit the external Twist Stuff quest snapshot.

## Administration

```bash
gtnh status
gtnh start
gtnh stop
gtnh restart
gtnh logs
gtnh command "list"
gtnh backup my-before-change
gtnh restore /var/backups/gtnh/my-before-change.tar.gz
gtnh doctor
```

`gtnh restore` refuses a backup whose sidecar SHA-256 does not match. Automatic pre-update backups retain the five newest automatic snapshots; manually named backups are not pruned.

Updates are forward-only. The updater downloads and validates everything in a staging directory before downtime, stops the service, makes a verified backup, carries the world, player/quest/map data, configuration, catalogue mods, and unmanaged mods forward, then starts the staged server. Forge's missing-item confirmation is enabled only for that first post-update start and cleared after the server is healthy. A failed ready-state check automatically switches back to the old installation.

## Useful options

Run `install.sh --help` for the complete list. Important overrides include `--version`, `--install-path`, `--backup-path`, `--service-name`, `--port`, `--rcon-port`, `--heap-mib`, `--view-distance`, `--seed`, `--admin`, and `--mods none|all|ID,ID`.

World pre-generation is intentionally not automatic. After confirming the server works, use your preferred compatible pre-generation command through `gtnh command`.

## Tests

```bash
bash -n install.sh lib/*.sh bin/gtnh bin/gtnh-rcon-firewall
shellcheck install.sh lib/*.sh bin/gtnh bin/gtnh-rcon-firewall
python3 -m py_compile bin/gtnh-rcon.py
bash tests/run.sh
bash tests/dry-run.sh
pwsh -NoProfile -File tests/client-account.ps1
```

See `PROJECT-SPEC.md` for the contract and `IMPLEMENTATION-PLAN.md` for the staged validation plan.

## Uninstall

Stop and disable the service before removing anything. Review every path first, especially if you overrode defaults:

```bash
systemctl disable --now gtnh.service
```

The installer does not provide an automatic destructive uninstall. Preserve `/var/backups/gtnh` before manually removing the service unit, runtime configuration, helper, and `/opt/gtnh`.
