#!/usr/bin/env bash
# Cross-platform bootstrap for codingtino/nix.
# - NixOS minimal ISO: interactive or flag-driven destructive Btrfs installation.
# - macOS: non-destructive official Nix + nix-darwin bootstrap.

set -Eeuo pipefail
IFS=$'\n\t'

TTY_DEVICE="/dev/tty"
readonly REPOSITORY_REF="github:codingtino/nix"

REPLY=""
SECRET_REPLY=""
FILE_SECRET=""
LOGIN_PASSWORD=""
DISK_PASSWORD=""
NON_INTERACTIVE=false
NIXOS_OPTIONS_USED=false
CLI_USER_NAME=""
CLI_PASSWORD=""
CLI_PASSWORD_FILE=""
CLI_HOST_NAME=""
CLI_HARDWARE_PROFILE=""
CLI_DISK=""
CLI_ENCRYPT=""
CLI_ENCRYPTION_PASSWORD=""
CLI_ENCRYPTION_PASSWORD_FILE=""
CLI_REUSE_LOGIN_PASSWORD=false
CLI_HIBERNATION=""
CLI_SWAP=""
CLI_DISK_SWAP=""
CLI_ZRAM=""
CLI_SWAP_GIB=""
CLI_BROADCOM_STA=""
CLI_CONFIRM_ERASE=""
DETECTED_HARDWARE_MODEL=""
PRESERVE_APPLE_ESP=false
APPLE_ESP_BACKUP=""

show_help() {
  cat <<'EOF'
Usage: install.sh [options]

Values supplied as options skip their corresponding prompts. Omitted values stay
interactive unless --non-interactive is used, in which case missing required values
cause an error before the selected disk is erased.

General:
  -h, --help                         Show this help
  --non-interactive                  Never prompt; fail on missing required values
  --user NAME                        NixOS username or existing macOS admin user

NixOS identity:
  --password PASSWORD                Login password in plain text (insecure in argv/history)
  --password-file PATH               File containing only the login password
  --hostname NAME                    Installed hostname

NixOS hardware and target:
  --hardware-profile auto|none|NAME  Supported hardware profile selection
  --disk DEVICE                      Exact writable target disk, for example /dev/nvme0n1
  --broadcom-sta yes|no              Enable proprietary Broadcom STA/WL support

NixOS storage:
  --encrypt yes|no                   Enable LUKS2 encryption
  --encryption-password PASSWORD     Separate LUKS passphrase in plain text
  --encryption-password-file PATH    File containing only the LUKS passphrase
  --reuse-login-password             Reuse the login password for LUKS
  --hibernation yes|no               Enable hibernation (forces disk swap, disables zram)
  --swap yes|no                      Enable any swap when hibernation is disabled
  --disk-swap yes|no                 Enable persistent disk swap
  --zram yes|no                      Enable compressed RAM swap
  --swap-size GIB, --swapsize GIB    Persistent swap size in whole GiB

Destructive authorization:
  --confirm-erase DEVICE             Skip the final prompt only when DEVICE exactly
                                     matches the selected disk and any --disk value

Options accept either '--name value' or '--name=value'. Boolean values accept
'yes/no', 'true/false', '1/0', and 'y/n'. Password options are NixOS-only; macOS
continues to authenticate securely through sudo.
EOF
}

normalize_yes_no() {
  local option=$1
  local value
  value=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    y | yes | true | 1) BOOL_VALUE=true ;;
    n | no | false | 0) BOOL_VALUE=false ;;
    *) die "$option expects yes or no, not: $2" ;;
  esac
}

parse_args() {
  local raw
  local option
  local value

  while [[ $# -gt 0 ]]; do
    raw=$1
    shift
    case "$raw" in
      -h | --help)
        show_help
        exit 0
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        continue
        ;;
      --reuse-login-password)
        CLI_REUSE_LOGIN_PASSWORD=true
        NIXOS_OPTIONS_USED=true
        continue
        ;;
    esac

    case "$raw" in
      --*=*)
        option=${raw%%=*}
        value=${raw#*=}
        ;;
      *)
        option=$raw
        [[ $# -gt 0 ]] || die "$option requires a value."
        value=$1
        shift
        ;;
    esac
    [[ -n $value ]] || die "$option requires a non-empty value."

    case "$option" in
      --user) CLI_USER_NAME=$value ;;
      --password)
        CLI_PASSWORD=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --password-file)
        CLI_PASSWORD_FILE=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --hostname)
        CLI_HOST_NAME=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --hardware-profile)
        CLI_HARDWARE_PROFILE=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --disk)
        CLI_DISK=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --encrypt)
        normalize_yes_no "$option" "$value"
        CLI_ENCRYPT=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --encryption-password)
        CLI_ENCRYPTION_PASSWORD=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --encryption-password-file)
        CLI_ENCRYPTION_PASSWORD_FILE=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --hibernation)
        normalize_yes_no "$option" "$value"
        CLI_HIBERNATION=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --swap)
        normalize_yes_no "$option" "$value"
        CLI_SWAP=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --disk-swap)
        normalize_yes_no "$option" "$value"
        CLI_DISK_SWAP=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --zram)
        normalize_yes_no "$option" "$value"
        CLI_ZRAM=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --swap-size | --swapsize)
        CLI_SWAP_GIB=$value
        NIXOS_OPTIONS_USED=true
        ;;
      --broadcom-sta)
        normalize_yes_no "$option" "$value"
        CLI_BROADCOM_STA=$BOOL_VALUE
        NIXOS_OPTIONS_USED=true
        ;;
      --confirm-erase)
        CLI_CONFIRM_ERASE=$value
        NIXOS_OPTIONS_USED=true
        ;;
      *) die "Unknown option: $option. Use --help for supported options." ;;
    esac
  done

  [[ -z $CLI_PASSWORD || -z $CLI_PASSWORD_FILE ]] || \
    die "Use only one of --password and --password-file."
  [[ -z $CLI_ENCRYPTION_PASSWORD || -z $CLI_ENCRYPTION_PASSWORD_FILE ]] || \
    die "Use only one encryption-password source."
  if [[ $CLI_REUSE_LOGIN_PASSWORD == true ]] && \
    [[ -n $CLI_ENCRYPTION_PASSWORD || -n $CLI_ENCRYPTION_PASSWORD_FILE ]]; then
    die "--reuse-login-password cannot be combined with a separate encryption password."
  fi
}

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
  FILE_SECRET=""
  CLI_PASSWORD=""
  CLI_ENCRYPTION_PASSWORD=""
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

require_interactive_value() {
  [[ $NON_INTERACTIVE == false ]] || die "$1 is required with --non-interactive."
}

ask_or_use_bool() {
  local supplied_value=$1
  local option=$2
  local question=$3
  local default_answer=$4
  local help_text=$5

  if [[ -n $supplied_value ]]; then
    ANSWER_BOOL=$supplied_value
  else
    require_interactive_value "$option"
    ask_yes_no_help "$question" "$default_answer" "$help_text"
  fi
}

read_secret_file() {
  local path=$1
  local label=$2

  [[ -f $path && -r $path ]] || die "$label file is not a readable regular file: $path"
  FILE_SECRET=$(<"$path")
  [[ -n $FILE_SECRET ]] || die "$label file is empty: $path"
  [[ $FILE_SECRET != *$'\n'* ]] || die "$label file must contain exactly one line."
}

validate_password() {
  local value=$1
  local label=$2
  [[ -n $value ]] || die "$label cannot be empty."
  [[ $value != *:* ]] || die "$label cannot contain a colon."
  [[ $value != *$'\n'* && $value != *$'\r'* ]] || die "$label cannot contain a newline."
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
  [[ $NON_INTERACTIVE == false ]] || die "--non-interactive is currently supported only by the NixOS installer."
  [[ $NIXOS_OPTIONS_USED == false ]] || die "NixOS-specific options cannot be used on macOS."
  require_commands curl dscl grep id install mktemp rm scutil sh sudo sw_vers tr uname

  current_user=$(id -un)
  computer_name=$(scutil --get ComputerName 2>/dev/null || printf 'unknown')
  printf 'Detected macOS %s on %s. The computer name will remain %s.\n' \
    "$(sw_vers -productVersion)" "$(uname -m)" "$computer_name" >"$TTY_DEVICE"

  while true; do
    if [[ -n $CLI_USER_NAME ]]; then
      admin_user=$CLI_USER_NAME
    else
      prompt "macOS admin username [$current_user]: "
      admin_user=${REPLY:-$current_user}
    fi
    if ! validate_macos_user_name "$admin_user"; then
      [[ -z $CLI_USER_NAME ]] || die "Invalid macOS username supplied through --user: $admin_user"
      printf 'Enter an existing macOS short username using lowercase letters, digits, ., _ or -.\n' >"$TTY_DEVICE"
      continue
    fi
    if ! dscl . -read "/Users/$admin_user" >/dev/null 2>&1; then
      [[ -z $CLI_USER_NAME ]] || die "The macOS account supplied through --user does not exist: $admin_user"
      printf 'That macOS account does not exist.\n' >"$TTY_DEVICE"
      continue
    fi
    if ! printf '%s\n' "$(id -Gn "$admin_user")" | tr ' ' '\n' | grep -Fxq admin; then
      [[ -z $CLI_USER_NAME ]] || die "The macOS account supplied through --user is not an administrator: $admin_user"
      printf 'That account is not in the macOS admin group.\n' >"$TTY_DEVICE"
      continue
    fi
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
  if [[ -n $CLI_DISK ]]; then
    SELECTED_DISK=""
    for device in "${DISKS[@]}"; do
      if [[ $device == "$CLI_DISK" ]]; then
        SELECTED_DISK=$device
        break
      fi
    done
    [[ -n $SELECTED_DISK ]] || die "--disk must exactly match one of the displayed writable disks: $CLI_DISK"
  else
    require_interactive_value "--disk"
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
  fi

  printf '\nSelected disk and existing layout:\n' >"$TTY_DEVICE"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL "$SELECTED_DISK" >"$TTY_DEVICE"
}

select_hardware_profile() {
  local dmi
  local product_name
  local choice
  local normalized

  product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
  dmi="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true) $product_name $(cat /sys/class/dmi/id/product_version 2>/dev/null || true)"
  DETECTED_HARDWARE_MODEL=$product_name
  PRESERVE_APPLE_ESP=false
  AUTO_HARDWARE_PROFILE=""
  case "$dmi" in
    *20U1* | *20U2* | *"ThinkPad L14 Gen 1"*) AUTO_HARDWARE_PROFILE="lenovo-thinkpad-l14-intel" ;;
    *MacBookAir6,2*) AUTO_HARDWARE_PROFILE="apple-macbook-air-6" ;;
    *MacBookPro13,2*) AUTO_HARDWARE_PROFILE="apple-macbook-pro-13-2" ;;
    *MacBookPro14,2*) AUTO_HARDWARE_PROFILE="apple-macbook-pro-14-2" ;;
  esac
  case "$product_name" in
    MacBookPro13,2 | MacBookPro14,2) PRESERVE_APPLE_ESP=true ;;
  esac

  log "Fetching the pinned supported hardware profile list"
  HARDWARE_PROFILE_NAMES=$(nix --extra-experimental-features 'nix-command flakes' \
    eval --raw "$REPOSITORY_REF#lib.hardwareProfileNamesText")

  printf 'Detected hardware: %s\n' "$dmi" >"$TTY_DEVICE"
  if [[ -n $AUTO_HARDWARE_PROFILE ]]; then
    printf 'Suggested hardware profile: %s\n' "$AUTO_HARDWARE_PROFILE" >"$TTY_DEVICE"
  else
    printf 'No conservative hardware profile mapping is known for this model.\n' >"$TTY_DEVICE"
  fi
  if [[ $PRESERVE_APPLE_ESP == true ]]; then
    printf 'Apple T1 MacBook Pro detected: the existing Apple EFI contents must be preserved before erasing its disk.\n' >"$TTY_DEVICE"
  fi

  if [[ -n $CLI_HARDWARE_PROFILE ]]; then
    normalized=$(printf '%s' "$CLI_HARDWARE_PROFILE" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      auto) SELECTED_HARDWARE_PROFILE=$AUTO_HARDWARE_PROFILE ;;
      none) SELECTED_HARDWARE_PROFILE="" ;;
      *)
        printf '%s\n' "$HARDWARE_PROFILE_NAMES" | grep -Fxq "$CLI_HARDWARE_PROFILE" || \
          die "Unknown --hardware-profile: $CLI_HARDWARE_PROFILE"
        SELECTED_HARDWARE_PROFILE=$CLI_HARDWARE_PROFILE
        ;;
    esac
    return
  fi

  require_interactive_value "--hardware-profile"
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
        printf '\nThe generated hardware scan supplies filesystems, UUIDs and detected modules.\nA supported profile adds model-specific quirks and defaults. Auto uses only known\nDMI mappings; none is valid; exact-name accepts a profile exported by this flake.\n\n' >"$TTY_DEVICE"
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
  if [[ -n $CLI_USER_NAME ]]; then
    USER_NAME=$CLI_USER_NAME
    validate_linux_user_name "$USER_NAME" || die "Invalid Linux username supplied through --user: $USER_NAME"
  else
    require_interactive_value "--user"
    while true; do
      prompt "Username for the installed system: "
      USER_NAME=$REPLY
      validate_linux_user_name "$USER_NAME" && break
      printf 'Use 1-31 lowercase letters, digits, _ or -, starting with a letter or _. Root is not allowed.\n' >"$TTY_DEVICE"
    done
  fi

  if [[ -n $CLI_PASSWORD ]]; then
    LOGIN_PASSWORD=$CLI_PASSWORD
  elif [[ -n $CLI_PASSWORD_FILE ]]; then
    read_secret_file "$CLI_PASSWORD_FILE" "Login password"
    LOGIN_PASSWORD=$FILE_SECRET
    FILE_SECRET=""
  else
    require_interactive_value "--password or --password-file"
    prompt_confirmed_secret "Login password for $USER_NAME"
    LOGIN_PASSWORD=$CONFIRMED_SECRET
    CONFIRMED_SECRET=""
  fi
  validate_password "$LOGIN_PASSWORD" "Login password"

  if [[ -n $CLI_HOST_NAME ]]; then
    HOST_NAME=$CLI_HOST_NAME
    validate_host_name "$HOST_NAME" || die "Invalid hostname supplied through --hostname: $HOST_NAME"
  else
    require_interactive_value "--hostname"
    while true; do
      prompt "Hostname for the installed system: "
      HOST_NAME=$REPLY
      validate_host_name "$HOST_NAME" && break
      printf 'Use 1-63 letters, digits or hyphens; do not start or end with a hyphen.\n' >"$TTY_DEVICE"
    done
  fi
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
  local hibernation_default="yes"

  encryption_help='No encryption is simplest but exposes files and hibernated memory if the disk is stolen.\nEncrypted mode uses one LUKS2 container with LVM root and optional swap volumes.\nIt requires a passphrase during boot and keeps both root and hibernation encrypted.'
  swap_help='Swap protects against memory exhaustion. It can use compressed RAM through zram, persistent disk space, or both.\nHibernation automatically requires persistent disk swap; zram alone cannot store a hibernation image.'
  disk_swap_help='Dedicated disk swap provides persistent swap capacity but consumes fixed disk space and causes writes.\nHibernation requires disk swap at least as large as RAM; a partition or encrypted LV is the most reliable design.'
  zram_help='zram provides fast compressed swap in RAM and reduces SSD writes. It cannot store a hibernation image.\nIt can be used alone for normal swapping or together with lower-priority disk swap.'
  hibernation_help='Hibernation writes memory to disk and powers off. It requires persistent disk swap with sufficient capacity.\nThis installer disables zram in hibernation mode for a simple, deterministic swap layout.\nIf encryption is disabled, the hibernated memory image is readable from the disk.'
  case "$DETECTED_HARDWARE_MODEL" in
    MacBookPro13,2 | MacBookPro14,2)
      hibernation_default="no"
      hibernation_help="$hibernation_help\nSuspend/resume and hibernation remain unreliable on this MacBook Pro family, so hibernation defaults off."
      ;;
  esac

  ask_or_use_bool "$CLI_ENCRYPT" "--encrypt" "Encrypt the NixOS system?" "yes" "$encryption_help"
  ENABLE_ENCRYPTION=$ANSWER_BOOL

  ask_or_use_bool "$CLI_HIBERNATION" "--hibernation" "Enable hibernation?" "$hibernation_default" "$hibernation_help"
  ENABLE_HIBERNATION=$ANSWER_BOOL

  ENABLE_DISK_SWAP=false
  ENABLE_ZRAM=false
  if [[ $ENABLE_HIBERNATION == true ]]; then
    [[ $CLI_SWAP != false ]] || die "--hibernation yes conflicts with --swap no."
    [[ $CLI_DISK_SWAP != false ]] || die "--hibernation yes conflicts with --disk-swap no."
    [[ $CLI_ZRAM != true ]] || die "--hibernation yes conflicts with --zram yes."
    ENABLE_DISK_SWAP=true
    printf 'Dedicated disk swap is enabled; zram is disabled for the hibernation layout.\n' >"$TTY_DEVICE"
  else
    ask_or_use_bool "$CLI_SWAP" "--swap" "Enable swap?" "yes" "$swap_help"
    enable_swap=$ANSWER_BOOL
    if [[ $enable_swap == true ]]; then
      ask_or_use_bool "$CLI_DISK_SWAP" "--disk-swap" "Create dedicated disk swap?" "yes" "$disk_swap_help"
      ENABLE_DISK_SWAP=$ANSWER_BOOL
      ask_or_use_bool "$CLI_ZRAM" "--zram" "Also enable compressed zram swap?" "yes" "$zram_help"
      ENABLE_ZRAM=$ANSWER_BOOL
      [[ $ENABLE_DISK_SWAP == true || $ENABLE_ZRAM == true ]] || \
        die "--swap yes requires --disk-swap yes, --zram yes, or an interactive selection."
    else
      [[ $CLI_DISK_SWAP != true ]] || die "--swap no conflicts with --disk-swap yes."
      [[ $CLI_ZRAM != true ]] || die "--swap no conflicts with --zram yes."
      [[ -z $CLI_SWAP_GIB ]] || die "--swap-size cannot be used when swap is disabled."
    fi
  fi

  SWAP_GIB=0
  if [[ $ENABLE_DISK_SWAP == true ]]; then
    minimum_swap=1
    recommended_swap=$RAM_GIB
    if [[ $ENABLE_HIBERNATION == true ]]; then
      minimum_swap=$((RAM_GIB + 4))
      recommended_swap=$minimum_swap
    fi

    if [[ -n $CLI_SWAP_GIB ]]; then
      answer=$CLI_SWAP_GIB
      [[ $answer =~ ^[0-9]+$ ]] || die "--swap-size must be a whole number of GiB."
      (( answer >= minimum_swap )) || \
        die "--swap-size must be at least ${minimum_swap} GiB for the selected options."
      SWAP_GIB=$answer
    else
      require_interactive_value "--swap-size"
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
  elif [[ -n $CLI_SWAP_GIB ]]; then
    die "--swap-size requires persistent disk swap."
  fi

  DISK_PASSWORD=""
  if [[ $ENABLE_ENCRYPTION == true ]]; then
    if [[ $CLI_REUSE_LOGIN_PASSWORD == true ]]; then
      DISK_PASSWORD=$LOGIN_PASSWORD
    elif [[ -n $CLI_ENCRYPTION_PASSWORD ]]; then
      DISK_PASSWORD=$CLI_ENCRYPTION_PASSWORD
    elif [[ -n $CLI_ENCRYPTION_PASSWORD_FILE ]]; then
      read_secret_file "$CLI_ENCRYPTION_PASSWORD_FILE" "Encryption password"
      DISK_PASSWORD=$FILE_SECRET
      FILE_SECRET=""
    else
      require_interactive_value "--encryption-password, --encryption-password-file, or --reuse-login-password"
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
    [[ -n $DISK_PASSWORD ]] || die "Encryption password cannot be empty."
    [[ $DISK_PASSWORD != *$'\n'* && $DISK_PASSWORD != *$'\r'* ]] || \
      die "Encryption password cannot contain a newline."
  elif [[ -n $CLI_ENCRYPTION_PASSWORD || -n $CLI_ENCRYPTION_PASSWORD_FILE || $CLI_REUSE_LOGIN_PASSWORD == true ]]; then
    die "Encryption password options require --encrypt yes."
  fi
}

configure_broadcom() {
  local vendor_file
  local vendor_id
  local device_id
  local class_id
  local broadcom_network=false
  local broadcom_sta_candidate=false

  ENABLE_BROADCOM_STA=false
  for vendor_file in /sys/bus/pci/devices/*/vendor; do
    [[ -r $vendor_file ]] || continue
    vendor_id=$(<"$vendor_file")
    device_id=$(<"${vendor_file%/vendor}/device")
    class_id=$(<"${vendor_file%/vendor}/class")
    if [[ $vendor_id == "0x14e4" && $class_id == 0x02* ]]; then
      broadcom_network=true
      [[ $device_id == "0x43a0" ]] && broadcom_sta_candidate=true
    fi
  done
  if [[ $DETECTED_HARDWARE_MODEL == "MacBookAir6,2" && $broadcom_network == true ]]; then
    broadcom_sta_candidate=true
  fi

  case "$DETECTED_HARDWARE_MODEL:$SELECTED_HARDWARE_PROFILE" in
    MacBookPro13,2:* | MacBookPro14,2:* | *:apple-macbook-pro-13-2 | *:apple-macbook-pro-14-2)
      [[ $CLI_BROADCOM_STA != true ]] || \
        die "--broadcom-sta yes is incompatible with A1706 hardware profiles; BCM43602 uses brcmfmac."
      [[ $broadcom_network == false ]] || \
        printf 'Broadcom BCM43602-class Wi-Fi will use brcmfmac; proprietary STA is not enabled.\n' >"$TTY_DEVICE"
      return
      ;;
  esac

  if [[ -n $CLI_BROADCOM_STA ]]; then
    ENABLE_BROADCOM_STA=$CLI_BROADCOM_STA
  elif [[ $broadcom_sta_candidate == true ]]; then
    require_interactive_value "--broadcom-sta"
    ask_yes_no_help "Broadcom BCM4360 Wi-Fi detected. Enable proprietary broadcom_sta/wl?" "yes" \
      'The BCM4360 commonly needs the proprietary wl driver. nixpkgs may mark broadcom_sta insecure.\nAccepting permits only this unfree/insecure package and blacklists conflicting open drivers.\nDeclining may leave Wi-Fi unavailable; wired Ethernet remains unaffected.'
    ENABLE_BROADCOM_STA=$ANSWER_BOOL
  elif [[ $broadcom_network == true ]]; then
    printf 'Broadcom network hardware detected without a known STA mapping; keeping the kernel default driver.\n' >"$TTY_DEVICE"
  fi
}

find_efi_system_partition() {
  local disk=$1
  local device
  local partition_type

  while IFS= read -r device; do
    partition_type=$(blkid -s PART_ENTRY_TYPE -o value "$device" 2>/dev/null || true)
    partition_type=$(printf '%s' "$partition_type" | tr '[:upper:]' '[:lower:]')
    if [[ $partition_type == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
      printf '%s\n' "$device"
      return
    fi
  done < <(lsblk -nrpo NAME "$disk")
  return 0
}

has_apple_esp_files() {
  local root=$1
  local apple_directory

  apple_directory=$(find "$root/EFI" -maxdepth 1 -type d -iname apple -print -quit 2>/dev/null || true)
  [[ -n $apple_directory ]] && \
    [[ -n $(find "$apple_directory" -type f -print -quit 2>/dev/null || true) ]]
}

backup_apple_esp() {
  local esp_partition
  local mount_dir

  [[ $(findmnt -no FSTYPE /run) == "tmpfs" ]] || \
    die "Refusing to preserve Apple EFI files outside the installer's memory-backed /run."
  esp_partition=$(find_efi_system_partition "$SELECTED_DISK")
  [[ -n $esp_partition ]] || \
    die "No EFI System Partition was found on $SELECTED_DISK; refusing to erase this Apple T1 MacBook Pro."

  mount_dir=$(mktemp -d /run/nixos-apple-esp.XXXXXX)
  if ! mount -t vfat -o ro,umask=0077 "$esp_partition" "$mount_dir"; then
    rm -rf "$mount_dir"
    die "Could not mount the existing Apple EFI System Partition: $esp_partition"
  fi

  if ! has_apple_esp_files "$mount_dir"; then
    umount "$mount_dir"
    rm -rf "$mount_dir"
    die "The existing ESP has no EFI/APPLE files; refusing to erase firmware needed by the T1/Touch Bar."
  fi

  APPLE_ESP_BACKUP=/run/nixos-apple-esp.tar
  rm -f "$APPLE_ESP_BACKUP"
  if ! tar -C "$mount_dir" -cpf "$APPLE_ESP_BACKUP" .; then
    umount "$mount_dir"
    rm -rf "$mount_dir" "$APPLE_ESP_BACKUP"
    APPLE_ESP_BACKUP=""
    die "Could not archive the existing Apple EFI contents; the disk was not erased."
  fi
  if ! umount "$mount_dir"; then
    rm -rf "$APPLE_ESP_BACKUP"
    APPLE_ESP_BACKUP=""
    die "Could not unmount the existing Apple EFI partition; the disk was not erased."
  fi
  rm -rf "$mount_dir"
  if [[ ! -s $APPLE_ESP_BACKUP ]] || ! tar -tf "$APPLE_ESP_BACKUP" >/dev/null; then
    rm -f "$APPLE_ESP_BACKUP"
    APPLE_ESP_BACKUP=""
    die "The Apple EFI backup could not be verified; the disk was not erased."
  fi
  log "Verified an in-memory backup of the existing Apple EFI contents"
}

restore_apple_esp() {
  [[ -s $APPLE_ESP_BACKUP ]] || die "The verified Apple EFI backup is unavailable after repartitioning."
  tar -C /mnt/boot -xpf "$APPLE_ESP_BACKUP"
  sync
  has_apple_esp_files /mnt/boot || \
    die "The Apple EFI contents were not restored successfully. Keep the installer running for recovery."
  log "Restored the preserved Apple EFI contents"
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
  local luks_uuid=${1:-}
  local profile_expression="null"
  local luks_configuration=""
  if [[ -n $SELECTED_HARDWARE_PROFILE ]]; then
    profile_expression="\"$SELECTED_HARDWARE_PROFILE\""
  fi
  if [[ -n $luks_uuid ]]; then
    luks_configuration="        boot.initrd.luks.devices.cryptroot.device = \"/dev/disk/by-uuid/$luks_uuid\";"
  fi

  cat >/mnt/etc/nixos/flake.nix <<EOF
{
  description = "Local NixOS wrapper; machine values stay outside Git";

  inputs.nix-config.url = "$REPOSITORY_REF";

  outputs = { nix-config, ... }: {
    nixosConfigurations.system = nix-config.lib.mkNixosConfiguration {
      userName = "$USER_NAME";
      hostName = "$HOST_NAME";
      hardwareConfiguration = {
        imports = [ ./hardware-configuration.nix ];
$luks_configuration
      };
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
  local luks_uuid=""
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

  require_commands awk blkid blockdev btrfs cat curl find findmnt grep install lsblk mkfs.btrfs \
    mkfs.fat mktemp mkswap mount nix nixos-enter nixos-generate-config nixos-install parted \
    partprobe rm sed sleep swapon swapoff sync systemctl tar tr udevadm umount wipefs xargs

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
  if [[ $PRESERVE_APPLE_ESP == true ]]; then
    printf '  Apple EFI files:  preserve and restore before installation\n' >"$TTY_DEVICE"
  fi
  printf '  zram:             %s\n' "$ENABLE_ZRAM" >"$TTY_DEVICE"
  printf '  hibernation:      %s\n' "$ENABLE_HIBERNATION" >"$TTY_DEVICE"
  printf '\nEVERY PARTITION ON %s WILL BE DESTROYED.\n' "$SELECTED_DISK" >"$TTY_DEVICE"
  if [[ -n $CLI_CONFIRM_ERASE ]]; then
    [[ $CLI_CONFIRM_ERASE == "$SELECTED_DISK" ]] || \
      die "--confirm-erase must exactly match the selected disk: $SELECTED_DISK"
  else
    require_interactive_value "--confirm-erase $SELECTED_DISK"
    prompt "Type exactly 'ERASE $SELECTED_DISK' to continue: "
    confirmation=$REPLY
    [[ $confirmation == "ERASE $SELECTED_DISK" ]] || die "Destructive confirmation did not match; nothing was changed."
  fi

  if [[ $PRESERVE_APPLE_ESP == true ]]; then
    log "Preserving Apple EFI contents before any destructive operation"
    backup_apple_esp
  fi

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
    luks_uuid=$(cryptsetup luksUUID "$crypt_partition")
    [[ -n $luks_uuid ]] || die "Could not determine the LUKS UUID for $crypt_partition."
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
  if [[ $PRESERVE_APPLE_ESP == true ]]; then
    restore_apple_esp
  fi

  if [[ $ENABLE_DISK_SWAP == true ]]; then
    mkswap -L swap "$swap_partition"
    swapon "$swap_partition"
  fi

  log "Generating local machine hardware configuration"
  nixos-generate-config --root /mnt
  # nixos-generate-config does not trace a Btrfs-on-LVM root through LVM to
  # its outer LUKS container, so declare that initrd device explicitly.
  write_local_nixos_flake "$luks_uuid"

  log "Locking the local wrapper and installing the shared configuration"
  nix --extra-experimental-features 'nix-command flakes' flake lock /mnt/etc/nixos
  nixos-install --root /mnt --flake /mnt/etc/nixos#system --no-root-passwd

  log "Setting the requested user password and locking root"
  printf '%s:%s\n' "$USER_NAME" "$LOGIN_PASSWORD" | nixos-enter --root /mnt -c chpasswd
  LOGIN_PASSWORD=""
  nixos-enter --root /mnt -c 'passwd --lock root'
  sync
  if [[ -n $APPLE_ESP_BACKUP ]]; then
    has_apple_esp_files /mnt/boot || \
      die "Apple EFI files disappeared during installation; the in-memory backup remains available for recovery."
    rm -f "$APPLE_ESP_BACKUP"
    APPLE_ESP_BACKUP=""
  fi

  log "NixOS installation completed successfully"
  printf 'Local configuration: /etc/nixos\nFuture rebuild: sudo nixos-rebuild switch --flake /etc/nixos#system\n' >"$TTY_DEVICE"
  log "Rebooting in 5 seconds; remove the installer USB"
  sleep 5
  systemctl reboot
}

main() {
  parse_args "$@"
  if [[ $NON_INTERACTIVE == true ]]; then
    TTY_DEVICE="/dev/stderr"
  else
    [[ -c $TTY_DEVICE ]] || die "$TTY_DEVICE is required for interactive installation."
  fi
  case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_nixos ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
}

main "$@"
