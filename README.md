# tino's reusable macOS and NixOS configuration

One flake-based, dendritic configuration with a single interactive bootstrap script:

- **NixOS:** installs the same system and Home Manager configuration on supported x86-64 machines while keeping username, hostname, disks, UUIDs, encryption choices, and generated hardware configuration local under `/etc/nixos`.
- **macOS:** installs official upstream Nix when needed and applies nix-darwin, Home Manager, and Homebrew without changing the existing macOS computer name.

The currently tested NixOS hardware is:

- Lenovo ThinkPad L14 Gen 1 Intel, machine types 20U1/20U2
- Apple MacBook Air 13-inch Early 2014, model identifier MacBookAir6,2

> [!CAUTION]
> The NixOS path is a destructive operating-system installer. It shows writable disks and requires an exact confirmation, but the selected disk is then erased completely.

## Quick start

Boot the NixOS 26.05 minimal ISO in UEFI mode, or open Terminal on an existing macOS installation. Connect to the network, inspect the script if desired, and run:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/codingtino/nix/main/install.sh | bash
```

The script reads prompts directly from `/dev/tty`, so interaction works even when the script is piped to Bash.

A safer download-and-review workflow is:

```bash
curl --proto '=https' --tlsv1.2 -fLo /tmp/install.sh \
  https://raw.githubusercontent.com/codingtino/nix/main/install.sh
less /tmp/install.sh
bash /tmp/install.sh
```

Piping a mutable GitHub branch into a shell trusts the GitHub account and current repository contents. Pin the raw URL to a reviewed commit for repeatable installation.

## NixOS installer

The Linux path refuses to run unless it detects the NixOS installer, root privileges, UEFI boot, required tools, and working GitHub access. Network validation happens before disk changes.

### Interactive choices

The installer asks for:

- username and a hidden, confirmed login password
- hostname
- nixos-hardware profile
- target disk from the writable disks reported by `lsblk`
- disk encryption
- zram
- dedicated disk swap and its size
- hibernation
- an encryption passphrase when encryption is selected
- explicit consent for proprietary/insecure Broadcom STA Wi-Fi when matching hardware is detected
- exact final destructive confirmation

No password is written to Git, a Nix expression, logs, or the Nix store. The login password is set directly in the installed shadow database. Root password login is locked and root SSH login is disabled; the selected user has `sudo` through the `wheel` group.

### Btrfs layouts

All NixOS installations use Btrfs with Zstandard compression, `noatime`, and these subvolumes:

```text
@root
@home
@nix
@log
@snapshots
```

Without encryption:

```text
GPT
├── EFI System Partition
├── optional swap partition
└── Btrfs root
```

With encryption:

```text
GPT
├── EFI System Partition
└── LUKS2
    └── LVM
        ├── optional swap LV
        └── Btrfs root LV
```

The encrypted layout needs one LUKS unlock during boot and keeps both root data and hibernated memory encrypted. The installer recommends a separate disk passphrase but allows explicitly reusing the login password.

zram and disk swap are independent. Hibernation requires disk swap and enforces at least RAM plus 4 GiB. Without disk encryption, a hibernation image is not confidential.

### Hardware discovery and nixos-hardware

`nixos-generate-config` always creates the machine-specific local hardware module. It records filesystems, UUIDs, initrd modules, swap, CPU details, and storage topology.

A nixos-hardware profile is an additional set of model-specific quirks and defaults. Upstream nixos-hardware does not currently provide a complete automatic DMI resolver, so the installer offers:

- conservative automatic suggestion
- no profile
- list all profiles exported by the pinned nixos-hardware input
- exact validated profile name

Built-in suggestions are:

| Detected model | Suggested profile |
|---|---|
| ThinkPad L14 20U1/20U2 | `lenovo-thinkpad-l14-intel` |
| MacBookAir6,2 | `apple-macbook-air-6` |

The MacBookAir6,2 commonly has BCM4360 Wi-Fi. The installer asks before permitting and enabling the proprietary `broadcom_sta`/`wl` driver. Use wired USB Ethernet during installation because the minimal ISO may not support that Wi-Fi adapter.

### Local-only machine configuration

The installer creates:

```text
/etc/nixos/
├── flake.nix
├── flake.lock
├── hardware-configuration.nix
└── configuration.nix          # generated fallback; the wrapper uses the hardware file
```

The local wrapper has a fixed output named `system` and imports this public repository through its lock file. Username, hostname, hardware profile choice, UUIDs, encryption devices, zram, Broadcom consent, and hibernation remain outside Git.

Nix does not select a configuration from the hostname. The explicit `#system` output selects it:

```bash
sudo nixos-rebuild build --flake /etc/nixos#system
sudo nixos-rebuild test --flake /etc/nixos#system
sudo nixos-rebuild switch --flake /etc/nixos#system
```

Update the shared configuration explicitly:

```bash
sudo nix flake update --flake /etc/nixos nix-config
sudo nixos-rebuild build --flake /etc/nixos#system
sudo nixos-rebuild switch --flake /etc/nixos#system
```

NixOS keeps bootable system generations. Roll back from the boot menu or run:

```bash
sudo nixos-rebuild switch --rollback
```

Hibernation, when selected, is tested with:

```bash
systemctl hibernate
```

## macOS bootstrap

On Darwin, `install.sh` is non-destructive. It:

1. asks for the existing macOS admin short username
2. verifies the account exists and belongs to the `admin` group
3. asks macOS `sudo` to authenticate the password securely
4. installs official upstream multi-user Nix when Nix is absent
5. creates a local wrapper under `/etc/nix-darwin`
6. applies nix-darwin, integrated Home Manager, nix-homebrew, and Homebrew declarations

The script does not capture or store the admin password. `sudo` handles it through the terminal. Run the script while logged in as the selected admin account.

The existing macOS `ComputerName`, `LocalHostName`, and hostname are not declared and therefore remain unchanged.

Local files are:

```text
/etc/nix-darwin/
├── flake.nix
└── flake.lock
```

Future updates and activation:

```bash
sudo nix flake update --flake /etc/nix-darwin nix-config
sudo darwin-rebuild switch --flake /etc/nix-darwin#system
```

The Darwin builder supports Apple Silicon and Intel Darwin. `macmon` and the pinned Herdr binary are installed only on Apple Silicon because their upstream artifacts are unavailable for Intel macOS.

## Managed configuration

### Shared Home Manager configuration

- eza
- fzf
- bat
- btop
- Helix
- Ghostty settings
- Git
- Zsh
- JetBrains Mono Nerd Font
- Herdr 0.7.5 pinned upstream binary and configuration
- rsync
- Terraform
- tree
- wget
- curl
- current stable Bash

### NixOS

- x86-64 platform and UEFI systemd-boot
- Btrfs and optional encrypted storage generated by the installer
- optional hibernation and zram
- selected nixos-hardware profile
- NetworkManager and DHCP
- OpenSSH with root login disabled
- SDDM Wayland greeter
- MangoWC as the default session
- DankMaterialShell
- PipeWire
- Bluetooth
- firmware updates
- German keyboard and locale
- `Europe/Berlin`

### macOS

- nix-darwin and integrated Home Manager
- nix-homebrew
- Ghostty
- Hidden Bar
- Hyperkey
- Leader Key
- Rectangle
- macmon on Apple Silicon
- conservative Homebrew activation without automatic upgrades or cleanup
- small Finder and Dock defaults

## Architecture

`flake.nix` uses flake-parts and import-tree. Feature files under `modules/` contribute deferred modules to:

- `dendritic.nixos.NIXOS` — reusable shared NixOS system behavior
- `dendritic.darwin."MACOS-NIX"` — reusable Darwin system behavior
- `dendritic.home.default` — reusable Home Manager behavior

The flake exports:

- `lib.mkNixosConfiguration`
- `lib.mkDarwinConfiguration`
- `lib.hardwareProfileNames`
- `lib.hardwareProfileNamesText`
- a default `darwinConfigurations.MACOS-NIX` for compatibility

Local wrapper flakes call the exported builders with local values. This separates reusable policy from machine identity and generated state.

## Reproducibility boundaries

- The repository `flake.lock` pins shared inputs.
- Each local wrapper has its own lock that pins the repository revision used by that machine.
- Disk partitioning, UUIDs, encryption metadata, passwords, SSH keys, and hostnames are local state.
- Homebrew and the Mac App Store remain mutable external systems rather than Nix-store reproducible artifacts.
- Btrfs snapshots are not backups.
- Broadcom STA is proprietary and may be marked insecure; it is enabled only after explicit installer consent.
- macOS itself and Apple system updates remain outside nix-darwin.
