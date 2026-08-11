# tino's reusable macOS and NixOS configuration

One flake-based, dendritic configuration with a single interactive or flag-driven bootstrap script:

- **NixOS:** installs the same system and Home Manager configuration on supported x86-64 machines while keeping username, hostname, disks, UUIDs, encryption choices, and generated hardware configuration local under `/etc/nixos`.
- **macOS:** installs official upstream Nix when needed and applies nix-darwin, Home Manager, and Homebrew without changing the existing macOS computer name.

Built-in exact-DMI NixOS mappings currently cover:

- Lenovo ThinkPad L14 Gen 1 Intel, machine types 20U1/20U2 (live-tested)
- Apple MacBook Air 13-inch Early 2014, model identifier MacBookAir6,2
- Apple MacBook Pro 13-inch Touch Bar 2016/2017, enclosure A1706, model identifiers MacBookPro13,2 and MacBookPro14,2 (the MacBookPro14,2 system and Wi-Fi are live-tested; MacBookPro13,2 remains untested)

There is no known Apple MacBook Pro **A1606**; A1706 is the likely enclosure number intended. Verify the model identifier as described in [MacBook Pro A1706 notes](#macbook-pro-a1706-notes).

> [!CAUTION]
> The NixOS path is a destructive operating-system installer. It shows writable disks and requires either a typed confirmation or an exact matching `--confirm-erase` device, but every partition on the selected disk is then destroyed and recreated. On detected A1706/T1 models only, the installer requires, verifies, and restores the existing `EFI/APPLE` files; this does not preserve macOS or user data.

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

### Installer options

Options can supply some or all answers. Supplied values skip their corresponding prompts; omitted values remain interactive. Pass arguments to a curl-piped script with `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/codingtino/nix/main/install.sh |
  bash -s -- --user tino --hostname NIXOS --disk /dev/nvme0n1
```

Use `--non-interactive` to prohibit every prompt. Missing or contradictory required values then fail before disk erasure. The exact value passed to `--confirm-erase` must match the selected disk.

| Option | Meaning |
|---|---|
| `-h`, `--help` | Show built-in option help and exit |
| `--non-interactive` | Never prompt; currently NixOS-only |
| `--user NAME` | NixOS username or existing macOS admin short name |
| `--password PASSWORD` | NixOS login password as a plain command-line argument |
| `--password-file PATH` | Read the NixOS login password from a file |
| `--hostname NAME` | Installed NixOS hostname |
| `--hardware-profile auto\|none\|NAME` | Use the conservative DMI suggestion, no profile, or an exact supported profile exported by this flake |
| `--disk DEVICE` | Exact writable target disk shown by `lsblk` |
| `--broadcom-sta yes\|no` | Explicitly enable or disable proprietary Broadcom STA/WL support |
| `--encrypt yes\|no` | Enable or disable LUKS2 encryption |
| `--encryption-password PASSWORD` | Supply a separate LUKS passphrase in plain text |
| `--encryption-password-file PATH` | Read a separate LUKS passphrase from a file |
| `--reuse-login-password` | Reuse the login password as the LUKS passphrase |
| `--hibernation yes\|no` | Enable hibernation; `yes` forces disk swap and disables zram |
| `--swap yes\|no` | Enable or disable all swap when hibernation is disabled |
| `--disk-swap yes\|no` | Select persistent partition/LV swap when swap is enabled |
| `--zram yes\|no` | Select compressed RAM swap when swap is enabled |
| `--swap-size GIB`, `--swapsize GIB` | Persistent swap size as a whole number of GiB |
| `--confirm-erase DEVICE` | Authorize erasure without the final typed prompt only when it exactly matches the selected disk |

Options support both `--name value` and `--name=value`. Boolean values accept `yes/no`, `true/false`, `1/0`, and `y/n` case-insensitively.

#### Password input

Plain-text password flags are supported as requested, but they can expose secrets in shell history and process listings:

```bash
# Convenient, but intentionally insecure:
curl -fsSL https://raw.githubusercontent.com/codingtino/nix/main/install.sh |
  bash -s -- --user tino --password asdasd
```

Password files are safer. Each must contain only the password, optionally followed by a newline. Use restrictive permissions; `/run` is temporary memory-backed storage on the installer:

```bash
umask 077
read -r -s -p 'Login password: ' login_password; printf '\n'
printf '%s' "$login_password" >/run/nixos-login-password
unset login_password

read -r -s -p 'Disk password: ' disk_password; printf '\n'
printf '%s' "$disk_password" >/run/nixos-disk-password
unset disk_password
```

The installer reads these files before erasing the disk and does not copy them into the installed system or Nix store. A reboot clears `/run`.

#### Fully unattended examples

Encrypted hibernation with password files:

```bash
curl -fsSL https://raw.githubusercontent.com/codingtino/nix/main/install.sh |
  bash -s -- \
    --non-interactive \
    --user tino \
    --password-file /run/nixos-login-password \
    --hostname NIXOS \
    --hardware-profile auto \
    --disk /dev/nvme0n1 \
    --broadcom-sta no \
    --encrypt yes \
    --encryption-password-file /run/nixos-disk-password \
    --hibernation yes \
    --swap-size 20 \
    --confirm-erase /dev/nvme0n1
```

With hibernation enabled, `--swap yes` and `--disk-swap yes` are implicit and zram is forced off. Supplying conflicting values such as `--swap no`, `--disk-swap no`, or `--zram yes` is rejected.

An unencrypted installation using both ordinary disk swap and zram:

```bash
curl -fsSL https://raw.githubusercontent.com/codingtino/nix/main/install.sh |
  bash -s -- \
    --non-interactive \
    --user tino \
    --password asdasd \
    --hostname NIXOS \
    --hardware-profile auto \
    --disk /dev/nvme0n1 \
    --broadcom-sta no \
    --encrypt no \
    --hibernation no \
    --swap yes \
    --disk-swap yes \
    --zram yes \
    --swap-size 8 \
    --confirm-erase /dev/nvme0n1
```

Use `--swap no` after `--hibernation no` for no swap. When `--swap yes` is selected, at least one of `--disk-swap yes` and `--zram yes` is required. `--swap-size` is required only for disk-backed swap and must be at least RAM plus 4 GiB for hibernation.

## NixOS installer

The Linux path refuses to run unless it detects the NixOS installer, root privileges, UEFI boot, required tools, and working GitHub access. Network validation happens before disk changes.

### Interactive choices

The installer asks for:

- username and a hidden, confirmed login password
- hostname
- supported hardware profile
- target disk from the writable disks reported by `lsblk`
- disk encryption
- hibernation; enabling it automatically enables dedicated disk swap and disables zram
- whether to enable swap at all when hibernation is disabled
- dedicated disk swap and compressed zram choices only when hibernation is disabled and swap is enabled
- an encryption passphrase when encryption is selected
- explicit consent for proprietary/insecure Broadcom STA Wi-Fi only when a known BCM4360 path is detected
- automatic in-memory backup and verified restoration of Apple EFI firmware files on MacBookPro13,2/14,2
- exact final destructive confirmation

No password is written to Git, a Nix expression, logs, or the Nix store. The login password is set directly in the installed shadow database. Root password login is locked and root SSH login is disabled; the selected user has `sudo` through the `wheel` group. After a successful installation, the system reboots automatically after a five-second USB-removal notice.

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

The encrypted layout needs one LUKS unlock during boot and keeps both root data and hibernated memory encrypted. The installer recommends a separate disk passphrase but allows explicitly reusing the login password. The EFI partition uses a restrictive `umask=0077` mount option so systemd-boot's random seed is not accessible to non-root users. On MacBookPro13,2/14,2, Apple SPI keyboard modules are included in initrd so the built-in keyboard can enter the LUKS passphrase.

The installer asks about hibernation first. Enabling it automatically enables disk swap, disables zram, and enforces at least RAM plus 4 GiB. Without hibernation, the installer first asks whether to enable swap at all and only then offers disk swap, zram, or both. Without disk encryption, a hibernation image is not confidential.

### Hardware discovery and nixos-hardware

`nixos-generate-config` always creates the machine-specific local hardware module. It records filesystems, UUIDs, initrd modules, swap, CPU details, and storage topology. For LVM inside LUKS, the installer additionally records the outer LUKS UUID in the local wrapper because `nixos-generate-config` does not trace a filesystem through LVM to its encrypted container.

A hardware profile is an additional set of model-specific quirks and defaults. Most names come directly from the pinned nixos-hardware input; this repository also supplies profiles for the two A1706 DMI identifiers that upstream does not currently cover. Repository-owned extensions live in `modules/hardware-profiles.nix`: they import the nearest upstream nixos-hardware profiles and layer only this project’s additional fixes on top, rather than forking nixos-hardware. Upstream nixos-hardware does not provide a complete automatic DMI resolver, so the installer offers:

- conservative automatic suggestion
- no profile
- list all profiles exported by the pinned nixos-hardware input
- exact validated profile name

Built-in suggestions are:

| Detected model | Suggested profile |
|---|---|
| ThinkPad L14 20U1/20U2 | `lenovo-thinkpad-l14-intel` |
| MacBookAir6,2 | `apple-macbook-air-6` |
| MacBookPro13,2 | `apple-macbook-pro-13-2` |
| MacBookPro14,2 | `apple-macbook-pro-14-2` |

The MacBookAir6,2 commonly has BCM4360 Wi-Fi. The installer asks before permitting and enabling the proprietary `broadcom_sta`/`wl` driver. Use wired USB Ethernet during installation because the minimal ISO may not support that Wi-Fi adapter.

#### MacBook Pro A1706 notes

A1706 is the enclosure number for two 13-inch Touch Bar generations. Check the exact model before installation:

```bash
# Existing macOS:
system_profiler SPHardwareDataType | awk -F ': ' '/Model Identifier/ { print $2 }'

# NixOS installer ISO:
cat /sys/class/dmi/id/product_name
```

The result must be `MacBookPro13,2` (2016) or `MacBookPro14,2` (2017) for automatic support. The profiles provide early Apple SPI keyboard/trackpad loading, the driver’s ISO-layout correction for German keyboards, HiDPI/Intel/firmware defaults, libinput quirks, and an NVMe D3cold workaround needed for resume.

These T1 models need Apple firmware files from the original EFI System Partition to initialize iBridge devices. After destructive confirmation but **before `wipefs`**, the installer:

1. locates the existing EFI System Partition on the selected disk
2. requires non-empty `EFI/APPLE/EMBEDDEDOS/combined.memboot`, `FDRData`, and `version.plist` T1 firmware files
3. archives and verifies the entire ESP in memory-backed `/run`
4. recreates the disk and 1 GiB ESP
5. restores the preserved files before installing systemd-boot

Any pre-erasure backup or archive-verification failure aborts before disk erasure. The check requires all three observed MacBookPro14,2 T1 payload files and rejects an `EFI/APPLE` tree containing only boot logs. A restoration failure after repartitioning stops the install and leaves the archive in `/run` for recovery. Missing Apple EFI firmware also aborts; restore it through macOS Internet Recovery/update first. Keeping macOS is the safest route for future Apple firmware updates, but it requires manual dual-boot partitioning or a separate target disk—the full-disk installer does not preserve a macOS volume. The automatic preservation step protects firmware only—**all volumes and user files on the selected disk are erased**.

Known validation boundaries for the first installation:

- BCM43602 Wi-Fi uses the in-kernel `brcmfmac` driver; proprietary `broadcom_sta` is rejected. The A1706 profiles install pinned community NVRAM calibration, disable broken firmware WPA/SAE and roaming offload, use a stable generated connection MAC, and disable Wi-Fi power saving. Missing `.clm_blob`/`.txcap_blob` warnings remain expected.
- The complete MacBookPro14,2 system has been built, activated, and rebooted successfully. Wi-Fi, camera, and the T1 Touch Bar are live-tested; internal audio, Bluetooth, Thunderbolt, and suspend/resume still need focused hardware validation. MacBookPro13,2 has not been live-tested.
- After an earlier ESP preserved only boot logs, the live MacBookPro14,2 T1 remained in `05ac:1281` recovery mode even after a cold power cycle. Installing and fully updating macOS 13.7.8 restored T1 firmware `14Y910`. The pinned Linux driver now works with its dangerous ACPI power call forcibly disabled. macOS testing confirmed that the far-right part of this machine's Touch Bar is physically defective; this is not a Linux key-mapping failure. Touch ID has no supported Linux driver.
- Internal audio is not claimed until tested; USB or HDMI audio is the fallback.
- The NVMe workaround improves resume, but suspend/resume can remain slow or unreliable. Hibernation therefore defaults to `no` on these models; test it only after ordinary boot and suspend are stable.

#### Experimental T1 Touch Bar support

The exact `apple-macbook-pro-14-2` profile automatically builds the pinned out-of-tree `apple-ibridge` and `apple-touchbar` modules for the selected NixOS kernel and loads them from the initrd. The closely related but untested MacBookPro13,2 profile does not enable them. The module forces `skip_acpi_power=1` on probe, suspend, and resume because executing the original `ASOC.SOCW` ACPI power method can hard-freeze T1 MacBooks.

The fixed configuration uses the firmware-rendered media controls, switches to F1–F12 while Fn is held, and keeps the bar lit. It does not implement custom application controls, movable buttons, or Touch ID. Because the driver remains experimental and out of tree, keep an installer USB available during testing.

### Local-only machine configuration

The installer creates:

```text
/etc/nixos/
├── flake.nix
├── flake.lock
├── hardware-configuration.nix
└── configuration.nix          # generated fallback; the wrapper uses the hardware file
```

The local wrapper has a fixed output named `system` and imports this public repository through its lock file. Username, hostname, hardware profile choice, UUIDs, encryption devices, zram, Broadcom consent, and hibernation remain outside Git. Preserved Apple EFI files stay on the local EFI partition and are never added to Git or the Nix store.

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

### Recover an encrypted install missing its LUKS initrd declaration

Installer versions before the explicit outer-LUKS fix could install successfully but then time out waiting for `/dev/mapper/nixosvg…-root` on first boot. Boot the NixOS minimal ISO, reconnect the network, and run:

```bash
sudo -i
cryptsetup open /dev/nvme0n1p2 cryptroot
vgchange -ay

root_device=$(find /dev/mapper -maxdepth 1 -name 'nixosvg*-root' -print -quit)
test -n "$root_device"
umount -R /mnt 2>/dev/null || true
mount -t btrfs -o subvol=@root,compress=zstd,noatime "$root_device" /mnt
mkdir -p /mnt/nix /mnt/boot
mount -t btrfs -o subvol=@nix,compress=zstd,noatime "$root_device" /mnt/nix
mount -t vfat -o umask=0077 /dev/nvme0n1p1 /mnt/boot

luks_uuid=$(cryptsetup luksUUID /dev/nvme0n1p2)
sed -i \
  's|hardwareConfiguration = ./hardware-configuration.nix;|hardwareConfiguration = { imports = [ ./hardware-configuration.nix ]; boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-uuid/'"$luks_uuid"'"; };|' \
  /mnt/etc/nixos/flake.nix

nixos-install --root /mnt --flake /mnt/etc/nixos#system --no-root-passwd
reboot
```

Enter the installation's disk passphrase at `cryptsetup open` and again during the repaired boot. These commands do not repartition or format the disk.

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

### Shared update alias

Home Manager defines the same `nrs` (`Nix rebuild switch`) alias in Bash and Zsh on both platforms. It updates the local wrapper's locked `nix-config` input and switches to the resulting configuration only when the update succeeds:

```bash
nrs
```

On NixOS it operates on `/etc/nixos#system` with `nixos-rebuild`; on macOS it operates on `/etc/nix-darwin#system` with `darwin-rebuild`.

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
- Lazygit
- Zsh
- JetBrains Mono Nerd Font
- Herdr 0.7.5 pinned upstream binary and configuration
- rsync
- Terraform
- tree
- wget
- curl
- current stable Bash

### Application configuration files

Each configured shared application has its own typed Nix/Home Manager module under `modules/programs/`, including Ghostty, Helix, Git, Lazygit, Bat, Btop, Bash, Zsh, Eza, Fzf, and Herdr. These modules are applied to both NixOS and macOS through `dendritic.home.default`.

Ghostty is the only platform-specific installation exception: `modules/programs/ghostty.nix` installs the Nix package on NixOS and the Homebrew cask on macOS, while applying the same Home Manager settings on both systems. Tools that currently need installation but no application settings—Curl, Rsync, Terraform, Tree, and Wget—remain grouped in `modules/packages.nix` rather than having empty per-tool modules.

To change an application's configuration, edit its matching file, for example:

```text
modules/programs/ghostty.nix
modules/programs/helix.nix
modules/programs/zsh.nix
```

New `.nix` files anywhere below `modules/` are automatically imported by `import-tree`; no central import list needs updating.

### NixOS

- x86-64 platform and UEFI systemd-boot
- Btrfs and optional encrypted storage generated by the installer
- optional hibernation and zram
- selected upstream or repository-owned hardware profile
- NetworkManager and DHCP
- calibrated BCM43602 `brcmfmac` support on A1706, including stable generated MAC policy and disabled power saving
- OpenSSH with root login disabled and the declared `tino` public key authorized
- passwordless sudo for the declared NixOS user
- Tailscale
- DankGreeter login screen with synchronized DankMaterialShell theming
- MangoWC as the default session
- DankMaterialShell with UPower-backed battery percentage and charging status
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

`flake.nix` uses flake-parts and import-tree. Feature files anywhere below `modules/`, including the per-application files in `modules/programs/`, contribute deferred modules to:

- `dendritic.nixos.NIXOS` — reusable shared NixOS system behavior
- `dendritic.darwin."MACOS-NIX"` — reusable Darwin system behavior
- `dendritic.home.default` — reusable Home Manager behavior
- `dendritic.hardwareProfiles` — repository-owned profiles layered over pinned nixos-hardware modules

The flake exports:

- `lib.mkNixosConfiguration`
- `lib.mkDarwinConfiguration`
- `lib.hardwareProfileNames`
- `lib.hardwareProfileNamesText`
- a default `darwinConfigurations.MACOS-NIX` for compatibility

Local wrapper flakes call the exported builders with local values. This separates reusable policy from machine identity and generated state.

`AGENTS.md` is the durable project context for Pi and compatible coding agents. Pi loads it automatically when started in this repository; run `/reload` after editing it in an existing session.

## Reproducibility boundaries

- The repository `flake.lock` pins shared inputs.
- Each local wrapper has its own lock that pins the repository revision used by that machine.
- Disk partitioning, UUIDs, encryption metadata, passwords, private SSH keys, and hostnames are local state. Authorized public SSH keys may be declared as shared NixOS policy.
- Homebrew and the Mac App Store remain mutable external systems rather than Nix-store reproducible artifacts.
- Btrfs snapshots are not backups.
- Broadcom STA is proprietary and may be marked insecure; it is enabled only after explicit consent for known-compatible hardware and is rejected on A1706.
- A1706 Apple EFI firmware is copied only between the old and new local ESP through a temporary `/run` archive; it is not made reproducible by Nix.
- macOS itself and Apple system updates remain outside nix-darwin.
