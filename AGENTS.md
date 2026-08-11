# Project context for Pi and coding agents

This file is the durable project context. Pi loads root-level `AGENTS.md` automatically at startup when invoked in this repository or a child directory, unless context loading is explicitly disabled with `--no-context-files`/`-nc`. After editing this file in an existing Pi session, run `/reload` or restart Pi.

## Project purpose

This repository is `codingtino/nix`, a reusable flake-based configuration for NixOS and macOS owned by `tino`. It deliberately keeps reusable policy in Git and machine identity/state in local wrapper flakes.

Primary goals:

- one modular configuration for NixOS and nix-darwin;
- shared Home Manager packages and application settings;
- safe interactive or flag-driven bootstrap through `install.sh`;
- stable NixOS/nix-darwin/Home Manager release inputs;
- preserve functional Darwin support while adding NixOS hardware support;
- never commit passwords, private keys, Wi-Fi PSKs, disk keys, filesystem UUIDs, or generated machine hardware state.

Remote and branch:

- GitHub: `git@github.com:codingtino/nix.git`
- default branch: `main`

## Source of truth and stale notes

Read `README.md` before changing installation, deployment, hardware, or architecture behavior. It is the user-facing operational source of truth and must be updated with behavior changes.

`task_plan.md`, `findings.md`, and `progress.md` are historical research/work logs. They contain useful rationale but also stale earlier target names and pre-validation statements. Prefer current code, `README.md`, local wrapper configuration, and current Git history when they conflict.

## Architecture

The repository uses the dendritic pattern:

- `flake.nix` is intentionally thin and invokes `flake-parts` plus `import-tree`.
- Every Nix file under `modules/` is auto-imported as a top-level flake-parts module.
- `modules/dendritic.nix` defines typed deferred module collections.
- `dendritic.nixos.NIXOS` contains reusable NixOS policy.
- `dendritic.darwin."MACOS-NIX"` contains reusable nix-darwin policy.
- `dendritic.home.default` contains shared Home Manager policy.
- `dendritic.hardwareProfiles` contains repository-owned profiles layered over pinned nixos-hardware modules.
- `modules/outputs.nix` composes hosts and exports builders.

Exported API:

- `lib.mkNixosConfiguration`
- `lib.mkDarwinConfiguration`
- `lib.hardwareProfileNames`
- `lib.hardwareProfileNamesText`

Do not replace this with a conventional host/module tree or duplicate shared policy per host unless explicitly requested. Keep OS-specific settings in their corresponding deferred module collection.

## Important files

- `flake.nix`: pinned-input declarations and import-tree entry point.
- `flake.lock`: shared dependency lock; update intentionally.
- `install.sh`: cross-platform bootstrap; destructive on the NixOS ISO and non-destructive on macOS.
- `modules/outputs.nix`: builders, upstream/local hardware profile composition, formatter/dev shell, compatibility outputs.
- `modules/hardware-profiles.nix`: repository-owned hardware extensions, including A1706 Apple quirks, BCM43602 calibration, NVMe resume fix, and exact-profile T1 Touch Bar module.
- `packages/apple-t1-touchbar.nix`: pinned experimental out-of-tree T1 kernel modules, built against the selected NixOS kernel.
- `modules/base.nix`: platform/state versions, Nix settings, shells, root lock, Darwin user declaration.
- `modules/hardware.nix`: trim/fwupd, zram, hibernation resume, optional Broadcom STA.
- `modules/networking.nix`: NetworkManager, firewall, and OpenSSH policy.
- `modules/user.nix`: NixOS user, authorized public key, groups, and passwordless sudo.
- `modules/desktop.nix`: MangoWC, DankMaterialShell, DankGreeter/Niri host, PipeWire, Bluetooth, and Mango configuration.
- Other feature modules under `modules/`: shared CLI tools, fonts, Ghostty, Helix, Git, shell, locale, Herdr, and macOS apps/defaults.

## Local wrappers and state boundaries

Installed machines do not normally build the public compatibility output directly.

NixOS local wrapper:

- path: `/etc/nixos`
- output: `#system`
- owns username, hostname, generated `hardware-configuration.nix`, selected hardware profile, filesystems/UUIDs, encryption declaration, hibernation, zram, and Broadcom STA consent.

macOS local wrapper:

- path: `/etc/nix-darwin`
- output: `#system`
- owns the existing admin username and Darwin architecture.
- the configuration must not overwrite the existing macOS computer name.

Private SSH keys and Wi-Fi credentials are local state. Authorized **public** SSH keys may be declarative NixOS policy. The Wi-Fi connection profile/PSK on MBP-NIXOS is a root-owned NetworkManager keyfile and must never be copied into Git, commands, logs, or responses.

## Current targets and hardware profiles

Supported NixOS platform is `x86_64-linux`; Darwin supports `aarch64-darwin` and `x86_64-darwin`.

Built-in exact-DMI mappings include:

- ThinkPad L14 Gen 1 Intel (20U1/20U2);
- MacBookAir6,2;
- MacBookPro13,2 (2016 A1706);
- MacBookPro14,2 (2017 A1706).

The currently live-tested NixOS machine is `MBP-NIXOS`, a MacBookPro14,2. It can be reached as user `tino` when network access is available. Prefer explicit, currently verified addresses over hostname resolution during network troubleshooting, but do not commit transient addresses.

Darwin support is active and must remain evaluable. Its user declaration is in `modules/base.nix` with home `/Users/${userName}` and Zsh shell. NixOS-only SSH/sudo policy must not leak into Darwin.

## NixOS user and remote administration

`modules/user.nix` declares the normal NixOS user, its authorized Ed25519 public key, and passwordless sudo. These settings apply only through `dendritic.nixos.NIXOS`.

OpenSSH currently:

- permits public-key login;
- has root login disabled;
- keeps password authentication enabled globally;
- disables keyboard-interactive authentication.

Do not claim password login is globally disabled unless the configuration is actually changed and validated.

## MacBook Pro A1706 requirements

These machines use Apple SPI input and T1/iBridge firmware stored on the Apple EFI System Partition. Preserve the installer safeguards:

- load Apple SPI keyboard dependencies in initrd so LUKS can be unlocked;
- archive and verify the existing Apple ESP before destructive repartitioning;
- require non-empty `EFI/APPLE/EMBEDDEDOS/combined.memboot`, `FDRData`, and `version.plist`; boot logs alone are not valid T1 firmware;
- restore and verify the ESP after formatting;
- never imply that ESP preservation saves macOS volumes or user data;
- keep the NVMe D3cold workaround;
- enable the experimental Touch Bar driver only in the exact MacBookPro14,2 profile and never permit its hard-freeze-prone ACPI power call;
- do not claim Touch ID support.

Live inspection on 2026-08-10 found the MacBookPro14,2 T1 stuck as `05ac:1281 Apple Mobile Device (Recovery Mode)` after the old installer preserved only `EFI/APPLE/LOG`. A cold power cycle did not recover it. Installing and fully updating macOS 13.7.8 restored Apple T1 firmware `14Y910` and a working Touch Bar. The restored ESP has three required files under `EFI/APPLE/EMBEDDEDOS`: `combined.memboot`, `FDRData`, and `version.plist`. Preserve and verify all three before erasure. The corrected reinstall retained all files and T1 now enumerates as `05ac:8600 iBridge`.

Experimental Linux Touch Bar support uses pinned `AJ-dev-i60/t1-touchbar` revision `20d65c7b0fe6d05ea9734f869b27384a62de5109`. It builds on the live 6.18.40 kernel and is enabled directly only by the `apple-macbook-pro-14-2` profile; do not extend it to untested profiles implicitly. Both modules load from initrd so activation does not live-rebind USB. The profile forces `apple_ibridge skip_acpi_power=1`; never expose or set `skip_acpi_power=0`, because the original `ASOC.SOCW` call can hard-freeze T1 machines. macOS confirmed that the far-right Touch Bar region on the live machine is physically defective. Touch ID remains unsupported.

A1706 BCM43602 Wi-Fi uses in-kernel `brcmfmac`, never proprietary `broadcom_sta`/`wl`. The hardware module asserts that STA is disabled.

The verified Wi-Fi repair in `modules/hardware-profiles.nix` consists of:

- community NVRAM calibration pinned to commit `1d52273baa4d86f71113b4e65a181c839fce94fb` and SHA-256;
- generic firmware initialization MAC `00:90:4c:0d:f4:3e`;
- NetworkManager `wifi.cloned-mac-address=stable` for the actual transmitted address;
- disabled scan MAC randomization and Wi-Fi power saving;
- `brcmfmac feature_disable=0x82000 roamoff=1`, disabling broken firmware WPA/SAE handling and roaming offload;
- expected missing `.clm_blob` and `.txcap_blob` warnings.

This was built, activated, reboot-tested, and traffic-tested on MacBookPro14,2 at commit `9a7057f`: automatic 5 GHz WPA2 connection, DHCP, gateway/internet pings with 0% loss, and HTTPS all passed while Ethernet was disconnected. MacBookPro13,2 uses the same profile logic but has not received equivalent live validation.

## Installer safety rules

Treat `install.sh` as high-risk code. The NixOS path erases the selected disk. Preserve or strengthen all pre-erasure checks:

- NixOS installer environment, root, UEFI, dependencies, and network;
- exact disk selection, writable/non-removable checks, and mounted-device refusal;
- conservative DMI/profile selection;
- exact `--confirm-erase` match or typed confirmation;
- all secret validation before erasure;
- Apple ESP backup verification before erasure on A1706;
- explicit filesystem types when mounting freshly created filesystems;
- explicit outer-LUKS initrd declaration for LVM-over-LUKS.

Never run destructive installer paths merely to test them. Use mocks/fixtures for destructive logic and validate final Nix builds on the target when appropriate. Do not use Docker for this project unless the user explicitly reverses that preference.

## Common commands

From a Nix-capable checkout:

```bash
nix fmt
nix flake check --all-systems --no-build
```

NixOS local wrapper:

```bash
sudo nixos-rebuild build --flake /etc/nixos#system
sudo nixos-rebuild test --flake /etc/nixos#system
sudo nixos-rebuild switch --flake /etc/nixos#system
sudo nix flake update --flake /etc/nixos nix-config
```

Darwin local wrapper:

```bash
sudo darwin-rebuild build --flake /etc/nix-darwin#system
sudo darwin-rebuild switch --flake /etc/nix-darwin#system
sudo nix flake update --flake /etc/nix-darwin nix-config
```

Shell/static checks for installer changes:

```bash
bash -n install.sh
shellcheck install.sh
git diff --check
```

Parse every Nix file on a Nix host when changing modules:

```bash
find . -name '*.nix' -type f -print0 | xargs -0 -n1 nix-instantiate --parse >/dev/null
```

## Validation expectations

For Nix changes:

1. run formatting/whitespace and syntax checks;
2. evaluate both NixOS and Darwin paths affected by the change;
3. build the full target system when practical;
4. deploy only when requested/appropriate;
5. verify runtime behavior directly, not only evaluation;
6. keep `README.md` synchronized;
7. report the exact validation boundary without overclaiming.

For networking changes on MBP-NIXOS, keep Ethernet available as a recovery path, avoid depending on hostname resolution while interfaces change, and use a timed test that automatically reconnects Ethernet.

## Coding and Git conventions

- Keep changes minimal, modular, and dendritic.
- Prefer typed NixOS/nix-darwin/Home Manager options over raw generated configuration.
- Pin external source revisions and hashes.
- Do not broaden unfree/insecure package permission globally; use narrow predicates.
- Preserve stable release branches unless explicitly asked to upgrade.
- Never expose secrets in shell arguments, tool output, Git diffs, or final responses.
- Do not rewrite or discard unrelated user changes.
- Use concise commit messages and push only when requested or clearly part of the task.
- Before claiming success, check `git status`, relevant builds/tests, and remote/runtime state where applicable.
