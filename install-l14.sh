#!/usr/bin/env bash
# Unattended, destructive installer for tino's Lenovo ThinkPad L14 Gen 1.
# This script erases /dev/nvme0n1 without prompting.

set -Eeuo pipefail
IFS=$'\n\t'

readonly DISK="/dev/nvme0n1"
readonly ESP_PART="${DISK}p1"
readonly SWAP_PART="${DISK}p2"
readonly ROOT_PART="${DISK}p3"
readonly REPOSITORY_URL="https://github.com/codingtino/nix.git"
readonly REPOSITORY_DIR="/mnt/home/tino/nix-config"
readonly TEST_PASSWORD="asdasd"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '\nERROR: installation failed at line %s (exit %s). The machine will not reboot automatically.\n' \
    "${BASH_LINENO[0]}" "$exit_code" >&2
  exit "$exit_code"
}
trap on_error ERR

[[ $EUID -eq 0 ]] || die "Run this script as root from the NixOS minimal installer."
[[ -d /sys/firmware/efi/efivars ]] || die "The installer was not booted in UEFI mode."
[[ -b $DISK ]] || die "Expected internal disk $DISK was not found."
[[ $(< /sys/class/block/nvme0n1/removable) == 0 ]] || die "$DISK is marked removable."

DMI_VENDOR="$(< /sys/class/dmi/id/sys_vendor)"
DMI_PRODUCT="$(< /sys/class/dmi/id/product_name)"
DMI_VERSION="$(< /sys/class/dmi/id/product_version)"
readonly DMI_VENDOR DMI_PRODUCT DMI_VERSION

[[ $DMI_VENDOR == *LENOVO* ]] || die "Expected Lenovo hardware; found: $DMI_VENDOR"
case "$DMI_PRODUCT $DMI_VERSION" in
  *20U1* | *20U2* | *"ThinkPad L14 Gen 1"*) ;;
  *) die "Expected ThinkPad L14 Gen 1 type 20U1/20U2; found: $DMI_PRODUCT / $DMI_VERSION" ;;
esac

for command in awk curl findmnt grep install lsblk mount mkfs.ext4 mkfs.fat mkswap \
  nix nixos-enter nixos-generate-config nixos-install parted partprobe sleep swapon \
  swapoff sync systemctl udevadm umount wipefs; do
  command -v "$command" >/dev/null || die "Required installer command is missing: $command"
done

curl --fail --silent --show-error --location --connect-timeout 15 \
  --max-time 30 https://github.com/ >/dev/null

swapoff -a || true
umount -R /mnt 2>/dev/null || true
if lsblk -nrpo MOUNTPOINTS "$DISK" | grep -q '[^[:space:]]'; then
  die "A partition on $DISK remains mounted and cannot be erased safely."
fi

run_git() {
  if command -v git >/dev/null; then
    command git "$@"
  else
    nix --extra-experimental-features 'nix-command flakes' \
      shell github:NixOS/nixpkgs/nixos-26.05#git --command git "$@"
  fi
}

log "Validated $DMI_VENDOR $DMI_PRODUCT ($DMI_VERSION)"
log "WARNING: erasing every partition on $DISK in 5 seconds"
sleep 5

MEM_KIB="$(awk '/MemTotal/ { print $2 }' /proc/meminfo)"
readonly MEM_KIB
readonly SWAP_GIB="$(( (MEM_KIB + 1048575) / 1048576 + 4 ))"
readonly SWAP_END_GIB="$(( SWAP_GIB + 1 ))"

log "Creating a 1 GiB ESP, ${SWAP_GIB} GiB swap, and an ext4 root partition"
wipefs --all --force "$DISK"
parted --script "$DISK" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1GiB \
  set 1 esp on \
  mkpart swap linux-swap 1GiB "${SWAP_END_GIB}GiB" \
  mkpart nixos ext4 "${SWAP_END_GIB}GiB" 100%
partprobe "$DISK"
udevadm settle

[[ -b $ESP_PART && -b $SWAP_PART && -b $ROOT_PART ]] \
  || die "Expected partitions were not created."

log "Formatting partitions"
mkfs.fat -F 32 -n BOOT "$ESP_PART"
mkswap -L swap "$SWAP_PART"
mkfs.ext4 -F -L nixos "$ROOT_PART"

log "Mounting the target system"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$ESP_PART" /mnt/boot
swapon "$SWAP_PART"

log "Generating machine-specific hardware configuration"
nixos-generate-config --root /mnt

log "Cloning $REPOSITORY_URL"
mkdir -p "$(dirname "$REPOSITORY_DIR")"
run_git clone --depth 1 "$REPOSITORY_URL" "$REPOSITORY_DIR"

install -m 0644 /mnt/etc/nixos/hardware-configuration.nix \
  "$REPOSITORY_DIR/hosts/NIXOS/hardware-configuration.nix"
run_git -C "$REPOSITORY_DIR" add hosts/NIXOS/hardware-configuration.nix

if [[ ! -f $REPOSITORY_DIR/flake.lock ]]; then
  log "Creating flake.lock"
  nix --extra-experimental-features 'nix-command flakes' flake lock "$REPOSITORY_DIR"
fi
run_git -C "$REPOSITORY_DIR" add flake.lock

log "Installing the NIXOS flake"
nixos-install \
  --root /mnt \
  --flake "$REPOSITORY_DIR#NIXOS" \
  --no-root-passwd

log "Setting the temporary test password and locking root password login"
nixos-enter --root /mnt -c "printf '%s:%s\\n' tino '$TEST_PASSWORD' | chpasswd"
nixos-enter --root /mnt -c 'passwd --lock root'
nixos-enter --root /mnt -c "chown -R tino:users /home/tino/nix-config"

sync
log "Installation complete. User: tino; temporary password: $TEST_PASSWORD"
log "The temporary password is public and must be changed immediately after login."
log "Rebooting in 5 seconds; remove the installer USB."
sleep 5
systemctl reboot
