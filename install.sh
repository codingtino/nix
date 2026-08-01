#!/usr/bin/env bash
# Cross-platform bootstrap for codingtino/nix.
# - NixOS minimal ISO: interactive, destructive Btrfs installation.
# - macOS: non-destructive official Nix + nix-darwin bootstrap.

set -Eeuo pipefail
IFS=$'\n\t'

readonly TTY_DEVICE="/dev/tty"
readonly REPOSITORY_REF="github:codingtino/nix"

REPLY=""
SECRET_REPLY=""
LOGIN_PASSWORD=""
DISK_PASSWORD=""

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '\nERROR: installation failed at line %s (exit %s).\n' \
    "${BASH_LINENO[0]}" "$exit_code" >&2
  exit "$exit_code"
}

clear_secrets() {
  LOGIN_PASSWORD=""
  DISK_PASSWORD=""
  SECRET_REPLY=""
}

trap on_error ERR
trap clear_secrets EXIT

prompt() {
  printf '%s' "$1" >"$TTY_DEVICE"
  IFS= read -r REPLY <"$TTY_DEVICE" || die "Unable to read from $TTY_DEVICE."
}

prompt_secret() {
  printf '%s' "$1" >"$TTY_DEVICE"
  IFS= read -r -s SECRET_REPLY <"$TTY_DEVICE" || die "Unable to read a secret from $TTY_DEVICE."
  printf '\n' >"$TTY_DEVICE"
}

ask_yes_no_help() {
  local question=$1
  local default_answer=$2
  local help_text=$3
  local suffix
  local answer

  if [[ $default_answer == "yes" ]]; then
    suffix="[Y/n/help]"
  else
    suffix="[y/N/help]"
  fi

  while true; do
    prompt "$question $suffix "
    answer=$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]')
    [[ -n $answer ]] || answer=$default_answer
    case "$answer" in
      y | yes)
        ANSWER_BOOL=true
        return
        ;;
      n | no)
        ANSWER_BOOL=false
        return
        ;;
      h | help | \?)
        printf '\n%b\n\n' "$help_text" >"$TTY_DEVICE"
        ;;
      *)
        printf 'Please answer yes, no, or help.\n' >"$TTY_DEVICE"
        ;;
    esac
  done
}

prompt_confirmed_secret() {
  local label=$1
  local first
  while true; do
    prompt_secret "$label: "
    first=$SECRET_REPLY
    [[ -n $first ]] || {
      printf 'The value cannot be empty.\n' >"$TTY_DEVICE"
      continue
    }
    prompt_secret "Confirm $label: "
    if [[ $first == "$SECRET_REPLY" ]]; then
      CONFIRMED_SECRET=$first
      SECRET_REPLY=""
      return
    fi
    printf 'The values did not match; try again.\n' >"$TTY_DEVICE"
  done
}

validate_linux_user_name() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [[ $1 != "root" ]]
}

validate_macos_user_name() {
  [[ $1 =~ ^[a-z_][a-z0-9_.-]{0,62}$ ]] && [[ $1 != "root" ]]
}

validate_host_name() {
  [[ ${#1} -le 63 ]] && [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]
}

require_commands() {
  local command
  for command in "$@"; do
    command -v "$command" >/dev/null || die "Required command is missing: $command"
  done
}

load_nix_environment() {
  if command -v nix >/dev/null; then
    return
  fi

  if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
  command -v nix >/dev/null || die "Nix was installed but is not available in this shell. Open a new terminal and rerun install.sh."
}

write_local_darwin_flake() {
  local output_path=$1
  local admin_user=$2
  local nix_system=$3

  cat >"$output_path" <<EOF
{
  description = "Local nix-darwin wrapper; machine values stay outside Git";

  inputs.nix-config.url = "$REPOSITORY_REF";

  outputs = { nix-config, ... }: {
    darwinConfigurations.system = nix-config.lib.mkDarwinConfiguration {
      userName = "$admin_user";
      system = "$nix_system";
    };
  };
}
EOF
}

install_macos() {
  local current_user
  local admin_user
  local architecture
  local nix_system
  local computer_name
  local installer_dir
  local installer_path
  local wrapper_path
  local nix_bin

  [[ $EUID -ne 0 ]] || die "Run the macOS path as the admin user, not through sudo. The script invokes sudo when needed."
  require_commands curl dscl grep id install mktemp rm scutil sh sudo sw_vers tr uname

  current_user=$(id -un)
  computer_name=$(scutil --get ComputerName 2>/dev/null || printf 'unknown')
  printf 'Detected macOS %s on %s. The computer name will remain %s.\n' \
    "$(sw_vers -productVersion)" "$(uname -m)" "$computer_name" >"$TTY_DEVICE"

  while true; do
    prompt "macOS admin username [$current_user]: "
    admin_user=${REPLY:-$current_user}
    validate_macos_user_name "$admin_user" || {
      printf 'Enter an existing macOS short username using lowercase letters, digits, ., _ or -.\n' >"$TTY_DEVICE"
      continue
    }
    dscl . -read "/Users/$admin_user" >/dev/null 2>&1 || {
      printf 'That macOS account does not exist.\n' >"$TTY_DEVICE"
      continue
    }
    printf '%s\n' "$(id -Gn "$admin_user")" | tr ' ' '\n' | grep -Fxq admin || {
      printf 'That account is not in the macOS admin group.\n' >"$TTY_DEVICE"
      continue
    }
    [[ $admin_user == "$current_user" ]] || die "Log in as $admin_user and rerun install.sh; sudo authenticates the invoking account."
    break
  done

  log "macOS will now request the password for $admin_user through sudo"
  # The caller-side redirect deliberately gives sudo the controlling terminal.
  # shellcheck disable=SC2024
  sudo -v <"$TTY_DEVICE"

  if ! command -v nix >/dev/null && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
    log "Installing official upstream Nix in multi-user mode"
    installer_dir=$(mktemp -d)
    installer_path="$installer_dir/nix-install"
    curl --proto '=https' --tlsv1.2 --fail --show-error --location \
      https://nixos.org/nix/install -o "$installer_path"
    sh "$installer_path" --daemon <"$TTY_DEVICE"
    rm -rf "$installer_dir"
  fi
  load_nix_environment
  nix_bin=$(command -v nix)

  architecture=$(uname -m)
  case "$architecture" in
    arm64) nix_system="aarch64-darwin" ;;
    x86_64) nix_system="x86_64-darwin" ;;
    *) die "Unsupported macOS architecture: $architecture" ;;
  esac

  wrapper_path=$(mktemp)
  write_local_darwin_flake "$wrapper_path" "$admin_user" "$nix_system"

  sudo mkdir -p /etc/nix-darwin
  sudo install -m 0644 "$wrapper_path" /etc/nix-darwin/flake.nix
  rm -f "$wrapper_path"

  log "Locking the local nix-darwin wrapper"
  sudo "$nix_bin" --extra-experimental-features 'nix-command flakes' \
    flake lock /etc/nix-darwin

  log "Building and activating nix-darwin"
  sudo "$nix_bin" --extra-experimental-features 'nix-command flakes' \
    run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
    switch --flake /etc/nix-darwin#system

  log "macOS configuration complete; ComputerName remains: $computer_name"
  printf 'Future updates:\n  sudo nix flake update --flake /etc/nix-darwin nix-config\n  sudo darwin-rebuild switch --flake /etc/nix-darwin#system\n'
}

partition_path() {
  local disk=$1
  local number=$2
  case "$disk" in
    *[0-9]) printf '%sp%s' "$disk" "$number" ;;
    *) printf '%s%s' "$disk" "$number" ;;
  esac
}

select_disk() {
  local device
  local disk_type
  local read_only
  local size
  local model
  local transport
  local index
  local selection

  DISKS=()
  printf '\nAvailable writable disks:\n' >"$TTY_DEVICE"
  while IFS= read -r device; do
    disk_type=$(lsblk -dno TYPE "$device" | tr -d '[:space:]')
    read_only=$(lsblk -dno RO "$device" | tr -d '[:space:]')
    [[ $disk_type == "disk" && $read_only == "0" ]] || continue
    DISKS[${#DISKS[@]}]=$device
    size=$(lsblk -dno SIZE "$device" | xargs)
    model=$(lsblk -dno MODEL "$device" | xargs)
    transport=$(lsblk -dno TRAN "$device" | xargs)
    printf '  %d) %-16s %-8s %-8s %s\n' "${#DISKS[@]}" "$device" "$size" "$transport" "$model" >"$TTY_DEVICE"
  done < <(lsblk -dpno NAME)

  [[ ${#DISKS[@]} -gt 0 ]] || die "No writable disks were found."
  while true; do
    prompt "Select the disk number to erase: "
    selection=$REPLY
    [[ $selection =~ ^[0-9]+$ ]] || {
      printf 'Enter one of the displayed numbers.\n' >"$TTY_DEVICE"
      continue
    }
    (( selection >= 1 && selection <= ${#DISKS[@]} )) || {
      printf 'Selection is out of range.\n' >"$TTY_DEVICE"
      continue
    }
    index=$((selection - 1))
    SELECTED_DISK=${DISKS[$index]}
    break
  done

  printf '\nSelected disk and existing layout:\n' >"$TTY_DEVICE"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL "$SELECTED_DISK" >"$TTY_DEVICE"
}

select_hardware_profile() {
  local dmi
  local choice
  local normalized

  dmi="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true) $(cat /sys/class/dmi/id/product_name 2>/dev/null || true) $(cat /sys/class/dmi/id/product_version 2>/dev/null || true)"
  AUTO_HARDWARE_PROFILE=""
  case "$dmi" in
    *20U1* | *20U2* | *"ThinkPad L14 Gen 1"*) AUTO_HARDWARE_PROFILE="lenovo-thinkpad-l14-intel" ;;
    *MacBookAir6,2*) AUTO_HARDWARE_PROFILE="apple-macbook-air-6" ;;
  esac

  log "Fetching the pinned nixos-hardware profile list"
  HARDWARE_PROFILE_NAMES=$(nix --extra-experimental-features 'nix-command flakes' \
    eval --raw "$REPOSITORY_REF#lib.hardwareProfileNamesText")

  printf 'Detected hardware: %s\n' "$dmi" >"$TTY_DEVICE"
  if [[ -n $AUTO_HARDWARE_PROFILE ]]; then
    printf 'Suggested nixos-hardware profile: %s\n' "$AUTO_HARDWARE_PROFILE" >"$TTY_DEVICE"
  else
    printf 'No conservative nixos-hardware profile mapping is known for this model.\n' >"$TTY_DEVICE"
  fi

  while true; do
    prompt "Hardware profile [auto/none/list/exact-name/help] (auto): "
    choice=${REPLY:-auto}
    normalized=$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      auto)
        SELECTED_HARDWARE_PROFILE=$AUTO_HARDWARE_PROFILE
        return
        ;;
      none)
        SELECTED_HARDWARE_PROFILE=""
        return
        ;;
      list)
        printf '\n%s\n\n' "$HARDWARE_PROFILE_NAMES" >"$TTY_DEVICE"
        ;;
      help | h | \?)
        printf '\nThe generated hardware scan supplies filesystems, UUIDs and detected modules.\nA nixos-hardware profile adds model-specific quirks and defaults. Auto uses only\nknown DMI mappings; none is valid; exact-name accepts an exported official module.\n\n' >"$TTY_DEVICE"
        ;;
      *)
        if printf '%s\n' "$HARDWARE_PROFILE_NAMES" | grep -Fxq "$choice"; then
          SELECTED_HARDWARE_PROFILE=$choice
          return
        fi
        printf 'Unknown profile. Enter list to see valid exported names.\n' >"$TTY_DEVICE"
        ;;
    esac
  done
}

prompt_linux_identity() {
  while true; do
    prompt "Username for the installed system: "
    USER_NAME=$REPLY
    validate_linux_user_name "$USER_NAME" && break
    printf 'Use 1-31 lowercase letters, digits, _ or -, starting with a letter or _. Root is not allowed.\n' >"$TTY_DEVICE"
  done

  prompt_confirmed_secret "Login password for $USER_NAME"
  LOGIN_PASSWORD=$CONFIRMED_SECRET
  CONFIRMED_SECRET=""

  while true; do
    prompt "Hostname for the installed system: "
    HOST_NAME=$REPLY
    validate_host_name "$HOST_NAME" && break
    printf 'Use 1-63 letters, digits or hyphens; do not start or end with a hyphen.\n' >"$TTY_DEVICE"
  done
}

prompt_storage_choices() {
  local minimum_swap
  local recommended_swap
  local answer
  local enable_swap
  local encryption_help
  local swap_help
  local disk_swap_help
  local zram_help
  local hibernation_help

  encryption_help='No encryption is simplest but exposes files and hibernated memory if the disk is stolen.\nEncrypted mode uses one LUKS2 container with LVM root and optional swap volumes.\nIt requires a passphrase during boot and keeps both root and hibernation encrypted.'
  swap_help='Swap protects against memory exhaustion. It can use compressed RAM through zram, persistent disk space, or both.\nHibernation automatically requires persistent disk swap; zram alone cannot store a hibernation image.'
  disk_swap_help='Dedicated disk swap provides persistent swap capacity but consumes fixed disk space and causes writes.\nHibernation requires disk swap at least as large as RAM; a partition or encrypted LV is the most reliable design.'
  zram_help='zram provides fast compressed swap in RAM and reduces SSD writes. It cannot store a hibernation image.\nIt can be used alone for normal swapping or together with lower-priority disk swap.'
  hibernation_help='Hibernation writes memory to disk and powers off. It requires persistent disk swap with sufficient capacity.\nThis installer disables zram in hibernation mode for a simple, deterministic swap layout.\nIf encryption is disabled, the hibernated memory image is readable from the disk.'

  ask_yes_no_help "Encrypt the NixOS system?" "yes" "$encryption_help"
  ENABLE_ENCRYPTION=$ANSWER_BOOL

  ask_yes_no_help "Enable hibernation?" "yes" "$hibernation_help"
  ENABLE_HIBERNATION=$ANSWER_BOOL

  ENABLE_DISK_SWAP=false
  ENABLE_ZRAM=false
  if [[ $ENABLE_HIBERNATION == true ]]; then
    ENABLE_DISK_SWAP=true
    printf 'Dedicated disk swap is enabled; zram is disabled for the hibernation layout.\n' >"$TTY_DEVICE"
  else
    while true; do
      ask_yes_no_help "Enable swap?" "yes" "$swap_help"
      enable_swap=$ANSWER_BOOL
      [[ $enable_swap == true ]] || break

      ask_yes_no_help "Create dedicated disk swap?" "yes" "$disk_swap_help"
      ENABLE_DISK_SWAP=$ANSWER_BOOL
      ask_yes_no_help "Also enable compressed zram swap?" "yes" "$zram_help"
      ENABLE_ZRAM=$ANSWER_BOOL
      [[ $ENABLE_DISK_SWAP == true || $ENABLE_ZRAM == true ]] && break
      printf 'Select at least one swap type, or disable swap.\n' >"$TTY_DEVICE"
    done
  fi

  SWAP_GIB=0
  if [[ $ENABLE_DISK_SWAP == true ]]; then
    minimum_swap=1
    recommended_swap=$RAM_GIB
    if [[ $ENABLE_HIBERNATION == true ]]; then
      minimum_swap=$((RAM_GIB + 4))
      recommended_swap=$minimum_swap
    fi

    while true; do
      prompt "Disk swap size in GiB [$recommended_swap]: "
      answer=${REPLY:-$recommended_swap}
      [[ $answer =~ ^[0-9]+$ ]] || {
        printf 'Enter a whole number of GiB.\n' >"$TTY_DEVICE"
        continue
      }
      (( answer >= minimum_swap )) || {
        printf 'At least %s GiB is required for the selected options.\n' "$minimum_swap" >"$TTY_DEVICE"
        continue
      }
      SWAP_GIB=$answer
      break
    done
  fi

  DISK_PASSWORD=""
  if [[ $ENABLE_ENCRYPTION == true ]]; then
    while true; do
      prompt "Encryption passphrase [separate/reuse/help] (separate): "
      answer=${REPLY:-separate}
      case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
        separate)
          prompt_confirmed_secret "Disk-encryption passphrase"
          DISK_PASSWORD=$CONFIRMED_SECRET
          CONFIRMED_SECRET=""
          break
          ;;
        reuse)
          DISK_PASSWORD=$LOGIN_PASSWORD
          break
          ;;
        help | h | \?)
          printf '\nA separate passphrase limits credential reuse and is recommended. Reuse is easier,\nbut one compromised password then unlocks both disk and account. Changing the login\npassword later does not change the LUKS passphrase.\n\n' >"$TTY_DEVICE"
          ;;
        *) printf 'Enter separate, reuse, or help.\n' >"$TTY_DEVICE" ;;
      esac
    done
  fi
}

configure_broadcom() {
  local vendor_file
  local vendor_id
  local class_id
  local broadcom_network=false

  ENABLE_BROADCOM_STA=false
  for vendor_file in /sys/bus/pci/devices/*/vendor; do
    [[ -r $vendor_file ]] || continue
    vendor_id=$(<"$vendor_file")
    class_id=$(<"${vendor_file%/vendor}/class")
    if [[ $vendor_id == "0x14e4" && $class_id == 0x02* ]]; then
      broadcom_network=true
      break
    fi
  done

  if [[ $broadcom_network == true ]]; then
    ask_yes_no_help "Broadcom Wi-Fi detected. Enable proprietary broadcom_sta/wl?" "yes" \
      'The BCM4360 commonly needs the proprietary wl driver. nixpkgs may mark broadcom_sta insecure.\nAccepting permits only this unfree/insecure package and blacklists conflicting open drivers.\nDeclining may leave Wi-Fi unavailable; wired Ethernet remains unaffected.'
    ENABLE_BROADCOM_STA=$ANSWER_BOOL
  fi
}

create_btrfs_layout() {
  local root_device=$1
  local mount_options="compress=zstd,noatime"
  local subvolume

  mkfs.btrfs -f -L nixos "$root_device"
  # Do not let mount reuse stale filesystem metadata after repartitioning.
  mount -t btrfs "$root_device" /mnt
  for subvolume in @root @home @nix @log @snapshots; do
    btrfs subvolume create "/mnt/$subvolume"
  done
  umount /mnt

  mount -t btrfs -o "subvol=@root,$mount_options" "$root_device" /mnt
  mkdir -p /mnt/home /mnt/nix /mnt/var/log /mnt/.snapshots /mnt/boot
  mount -t btrfs -o "subvol=@home,$mount_options" "$root_device" /mnt/home
  mount -t btrfs -o "subvol=@nix,$mount_options" "$root_device" /mnt/nix
  mount -t btrfs -o "subvol=@log,$mount_options" "$root_device" /mnt/var/log
  mount -t btrfs -o "subvol=@snapshots,$mount_options" "$root_device" /mnt/.snapshots
}

write_local_nixos_flake() {
  local profile_expression="null"
  if [[ -n $SELECTED_HARDWARE_PROFILE ]]; then
    profile_expression="\"$SELECTED_HARDWARE_PROFILE\""
  fi

  cat >/mnt/etc/nixos/flake.nix <<EOF
{
  description = "Local NixOS wrapper; machine values stay outside Git";

  inputs.nix-config.url = "$REPOSITORY_REF";

  outputs = { nix-config, ... }: {
    nixosConfigurations.system = nix-config.lib.mkNixosConfiguration {
      userName = "$USER_NAME";
      hostName = "$HOST_NAME";
      hardwareConfiguration = ./hardware-configuration.nix;
      hardwareProfile = $profile_expression;
      enableBroadcomSta = $ENABLE_BROADCOM_STA;
      enableHibernation = $ENABLE_HIBERNATION;
      enableZram = $ENABLE_ZRAM;
    };
  };
}
EOF
}

install_nixos() {
  local source_mounts
  local mem_kib
  local disk_bytes
  local disk_gib
  local required_gib
  local esp_partition
  local root_partition
  local swap_partition=""
  local crypt_partition
  local swap_end
  local vg_name
  local confirmation
  local layout_description

  [[ $EUID -eq 0 ]] || die "Run the NixOS installer path as root."
  [[ -r /etc/os-release ]] || die "Cannot identify the operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == "nixos" ]] || die "The Linux path only supports the NixOS minimal installer."
  [[ -d /sys/firmware/efi/efivars ]] || die "Boot the installer in UEFI mode."
  command -v nixos-install >/dev/null || die "nixos-install is unavailable; run this from the minimal ISO."

  require_commands awk blockdev btrfs cat curl findmnt grep install lsblk mkfs.btrfs \
    mkfs.fat mkswap mount nix nixos-enter nixos-generate-config nixos-install parted \
    partprobe sed sleep swapon swapoff sync systemctl tr udevadm umount wipefs xargs

  log "Checking network access before collecting destructive choices"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 30 https://github.com/ >/dev/null

  prompt_linux_identity
  select_hardware_profile
  configure_broadcom
  select_disk

  mem_kib=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
  RAM_GIB=$(( (mem_kib + 1048575) / 1048576 ))
  prompt_storage_choices
  if [[ $ENABLE_ENCRYPTION == true ]]; then
    require_commands cryptsetup date lvcreate pvcreate vgcreate
  fi

  disk_bytes=$(blockdev --getsize64 "$SELECTED_DISK")
  disk_gib=$((disk_bytes / 1073741824))
  required_gib=$((1 + SWAP_GIB + 16))
  (( disk_gib >= required_gib )) || die "Selected disk has ${disk_gib} GiB; at least ${required_gib} GiB is required."

  source_mounts=$(lsblk -nrpo MOUNTPOINTS "$SELECTED_DISK" | grep -Ev '^[[:space:]]*$|^\[SWAP\]$' || true)
  [[ -z $source_mounts ]] || die "The selected disk contains mounted filesystems (possibly the installer itself): $source_mounts"

  if [[ $ENABLE_ENCRYPTION == true ]]; then
    layout_description="1 GiB EFI + LUKS2 containing LVM Btrfs root"
  else
    layout_description="1 GiB EFI + unencrypted Btrfs root"
  fi
  [[ $ENABLE_DISK_SWAP == true ]] && layout_description="$layout_description + ${SWAP_GIB} GiB swap"

  printf '\nInstallation summary:\n' >"$TTY_DEVICE"
  printf '  Disk:             %s (%s GiB)\n' "$SELECTED_DISK" "$disk_gib" >"$TTY_DEVICE"
  printf '  Layout:           %s\n' "$layout_description" >"$TTY_DEVICE"
  printf '  Username:         %s\n' "$USER_NAME" >"$TTY_DEVICE"
  printf '  Hostname:         %s\n' "$HOST_NAME" >"$TTY_DEVICE"
  printf '  Hardware profile: %s\n' "${SELECTED_HARDWARE_PROFILE:-none}" >"$TTY_DEVICE"
  printf '  zram:             %s\n' "$ENABLE_ZRAM" >"$TTY_DEVICE"
  printf '  hibernation:      %s\n' "$ENABLE_HIBERNATION" >"$TTY_DEVICE"
  printf '\nEVERY PARTITION ON %s WILL BE DESTROYED.\n' "$SELECTED_DISK" >"$TTY_DEVICE"
  prompt "Type exactly 'ERASE $SELECTED_DISK' to continue: "
  confirmation=$REPLY
  [[ $confirmation == "ERASE $SELECTED_DISK" ]] || die "Destructive confirmation did not match; nothing was changed."

  log "Erasing $SELECTED_DISK"
  swapoff -a || true
  umount -R /mnt 2>/dev/null || true
  wipefs --all --force "$SELECTED_DISK"

  esp_partition=$(partition_path "$SELECTED_DISK" 1)
  if [[ $ENABLE_ENCRYPTION == true ]]; then
    crypt_partition=$(partition_path "$SELECTED_DISK" 2)
    parted --script "$SELECTED_DISK" \
      mklabel gpt \
      mkpart ESP fat32 1MiB 1GiB \
      set 1 esp on \
      mkpart cryptroot 1GiB 100%
    partprobe "$SELECTED_DISK"
    udevadm settle

    mkfs.fat -F 32 -n BOOT "$esp_partition"
    printf '%s' "$DISK_PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$crypt_partition"
    printf '%s' "$DISK_PASSWORD" | cryptsetup open --key-file - "$crypt_partition" cryptroot
    DISK_PASSWORD=""

    vg_name="nixosvg$(date +%s)"
    pvcreate /dev/mapper/cryptroot
    vgcreate "$vg_name" /dev/mapper/cryptroot
    if [[ $ENABLE_DISK_SWAP == true ]]; then
      lvcreate -L "${SWAP_GIB}G" -n swap "$vg_name"
      swap_partition="/dev/$vg_name/swap"
    fi
    lvcreate -l 100%FREE -n root "$vg_name"
    root_partition="/dev/$vg_name/root"
  else
    if [[ $ENABLE_DISK_SWAP == true ]]; then
      swap_end=$((SWAP_GIB + 1))
      swap_partition=$(partition_path "$SELECTED_DISK" 2)
      root_partition=$(partition_path "$SELECTED_DISK" 3)
      parted --script "$SELECTED_DISK" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 1GiB \
        set 1 esp on \
        mkpart swap linux-swap 1GiB "${swap_end}GiB" \
        mkpart nixos btrfs "${swap_end}GiB" 100%
    else
      root_partition=$(partition_path "$SELECTED_DISK" 2)
      parted --script "$SELECTED_DISK" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 1GiB \
        set 1 esp on \
        mkpart nixos btrfs 1GiB 100%
    fi
    partprobe "$SELECTED_DISK"
    udevadm settle
    mkfs.fat -F 32 -n BOOT "$esp_partition"
  fi

  log "Creating Btrfs subvolumes"
  create_btrfs_layout "$root_partition"
  mount -t vfat -o umask=0077 "$esp_partition" /mnt/boot

  if [[ $ENABLE_DISK_SWAP == true ]]; then
    mkswap -L swap "$swap_partition"
    swapon "$swap_partition"
  fi

  log "Generating local machine hardware configuration"
  nixos-generate-config --root /mnt
  write_local_nixos_flake

  log "Locking the local wrapper and installing the shared configuration"
  nix --extra-experimental-features 'nix-command flakes' flake lock /mnt/etc/nixos
  nixos-install --root /mnt --flake /mnt/etc/nixos#system --no-root-passwd

  log "Setting the requested user password and locking root"
  printf '%s:%s\n' "$USER_NAME" "$LOGIN_PASSWORD" | nixos-enter --root /mnt -c chpasswd
  LOGIN_PASSWORD=""
  nixos-enter --root /mnt -c 'passwd --lock root'
  sync

  log "NixOS installation completed successfully"
  printf 'Local configuration: /etc/nixos\nFuture rebuild: sudo nixos-rebuild switch --flake /etc/nixos#system\n' >"$TTY_DEVICE"
  log "Rebooting in 5 seconds; remove the installer USB"
  sleep 5
  systemctl reboot
}

main() {
  [[ -c $TTY_DEVICE ]] || die "$TTY_DEVICE is required for interactive installation."
  case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_nixos ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
}

main "$@"
