# GTNH Server Setup

An interactive, GitHub-loaded installer and updater for a private GT New Horizons server on Ubuntu. It installs the official server pack, Java, systemd service, curated optional mods, gameplay configuration, local administration, verified backups, and automatic update rollback.

## Install

Run as `root` on a dedicated Ubuntu 22.04, 24.04, or 26.04 x86-64 server:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)"
```

The menus ask Install or Update, GTNH release, administrator username, and optional mods. A plain numbered UI is used when Whiptail is unavailable. No optional mods are selected by default on a clean install.

For a preview that writes nothing:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)" -- --dry-run --yes --admin YourMinecraftName
```

For a repeatable non-interactive install:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)" -- \
  --yes --action install --channel stable --admin YourMinecraftName --mods all
```

Always inspect scripts before running them as root. This project deliberately runs Minecraft as root, as requested; a vulnerable server or mod would therefore control the VM. Keep the VM dedicated and do not store unrelated credentials on it.

## Managed defaults

- Install: `/opt/gtnh`; backups: `/var/backups/gtnh`; service: `gtnh.service`.
- Latest stable GTNH by default; stable and RC selection are supported when their checksum is pinned.
- Java 21 when supported by the selected official pack; safe heap chosen from host RAM.
- Offline mode, no whitelist, Hard, 20 players, view distance 12, no PvP, flight allowed.
- Selected Minecraft port is LAN-scoped when UFW is already active. UFW is never enabled by this installer.
- RCON uses a generated 48-character password, a root-only file, and an explicit non-loopback firewall rejection. It is never opened in UFW.
- Worldgen caves/mineshafts/underground lakes and dirt/gravel pockets are disabled before the first world starts. Pollution, machine explosions, fire spread, and butterfly spawning are disabled.
- ServerUtilities homes, back, claims, chunk loading, ranks, half-hour live backups, and 50% sleep are configured.

Offline mode does not authenticate usernames. Another user who can reach the server can impersonate an operator name; only permit trusted LAN clients.

## Optional mods pinned for GTNH 2.8.4

- GTNH Rates 1.11.0-2.8.4
- Programmable Hatches 0.1.3p53
- AE2 Things 1.2.14
- Twist Space Technology 0.7.16
- 123Technology 2.1.8_5
- GT Not Leisure 0.2.6-hotfix1

Artifacts and exact SHA-256 hashes are kept in `catalog/mods.json`. GT Not Leisure includes its two default quest lines in the mod JAR. The installer verifies those resources and GTNH 2.8.4's compatible BetterQuesting, automatically installs the separately pinned BetterQuestingAPI 1.1.2, and requires both quest chapters to appear in the live API before declaring startup healthy. During a GT Not Leisure version update, it also performs the author's required reset of `GregTech.lang` and the current or legacy GT Not Leisure configuration after creating the pre-update backup.

All six mods were tested together on GTNH 2.8.4 and reached the ready state. Selected add-ons must also be installed on each client; the installer prints the exact client list.

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
```

See `PROJECT-SPEC.md` for the contract and `IMPLEMENTATION-PLAN.md` for the staged validation plan.

## Uninstall

Stop and disable the service before removing anything. Review every path first, especially if you overrode defaults:

```bash
systemctl disable --now gtnh.service
```

The installer does not provide an automatic destructive uninstall. Preserve `/var/backups/gtnh` before manually removing the service unit, runtime configuration, helper, and `/opt/gtnh`.
