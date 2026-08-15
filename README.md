# GTNH Server Setup

An interactive Ubuntu installer and updater for a single GT New Horizons server. The project is being built in verified phases; phases 1–3 currently provide safe discovery, planning, and official GTNH release/Java resolution. They do **not** install or update a live server yet.

## Current usage

On a local checkout:

```bash
sudo apt-get install -y curl jq
sudo bash install.sh --dry-run
```

The intended GitHub launch form is already supported and loads the project modules from the same branch:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/install.sh)" -- --dry-run
```

Do not use the non-dry-run command yet. Native installation, systemd, firewall, and server lifecycle work starts in phase 4.

Useful non-interactive planning example:

```bash
sudo bash install.sh --dry-run --plain --yes \
  --action install --channel stable --install-path /opt/gtnh --port 25565
```

## What phases 1–3 include

- strict Bash error handling, cleanup, exit-code, and resumable-operation contracts;
- sanitized timestamped logging for mutating runs and terminal-only logging during dry runs;
- Whiptail menus with a numbered terminal fallback;
- Ubuntu LTS 22.04/24.04/26.04, root, x86-64, RAM, disk, interface/subnet, UFW, port, package, Java, and managed-install discovery;
- a hard guard that rejects mutation functions during `--dry-run`;
- stable and release-candidate filtering from GTNH's official machine-readable release catalogue;
- exact modern-Java server-pack resolution and automatic Java 21 selection when supported;
- project-pinned SHA-256 verification before any downloaded archive can be promoted;
- versioned JSON schemas for installer state, release checksums, and the future optional-mod catalogue.

Beta, pre-release, daily, and nightly packs are excluded. At this phase gate, the project-pinned server packs are GTNH `2.8.4` stable and `2.8.0-rc-2`. An exact historical version is rejected until its archive is reviewed and pinned.

The Java policy prefers Java 21 because it is an LTS release available on supported Ubuntu installations and falls inside both current official server-pack ranges. The resolver verifies that choice against the range encoded in the official archive name and the upstream `maxJavaVersion` field.

## Repository layout

```text
install.sh                    Direct/local entry point
lib/                          Safety, UI, discovery, release, Java, state, diagnostics
catalog/                      Pinned release checksums and optional-mod catalogue
schemas/                      Versioned JSON contracts
tests/                        Deterministic shell tests and fixtures
scripts/                      Developer validation helpers
PROJECT-SPEC.md               Agreed product behavior
IMPLEMENTATION-PLAN.md        Phased delivery plan
```

## Developer verification

Run on Ubuntu or another environment with Bash 5, curl, jq, and sha256sum:

```bash
bash -n install.sh lib/*.sh tests/*.sh tests/*.bash
bash tests/run.sh
bash tests/dry-run.sh
```

The fixture suite covers stable/RC/exact resolution, rejected beta/nightly/missing versions, Java ranges, pinned checksums, state identity, IPv4 subnet and port detection, both UI modes, logging redaction, operation recovery classification, checksum failure, and the dry-run no-change invariant.

## Security boundary

Running the Minecraft process as `root` is an explicit project requirement, but it gives a vulnerable server or mod control of the whole VM. Keep the VM dedicated to GTNH and do not place repository credentials, tokens, or unrelated secrets in the installation directory. Installer logs redact common secret forms and never upload diagnostics automatically.

Authoritative release metadata comes from the GTNH website repository's [`public/versions.json`](https://github.com/GTNewHorizons/GTNewHorizons.github.io/blob/master/public/versions.json). Server archives come only from the official GTNH download host.
