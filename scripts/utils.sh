set -uo pipefail

function cache_lsblk_output() {
	CACHED_LSBLK_OUTPUT="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID)" \
		|| die "Error while executing lsblk to cache output"
}

function die() {
	eerror "$*"
	[[ -v GENTOO_INSTALL_REPO_SCRIPT_PID && $$ -ne $GENTOO_INSTALL_REPO_SCRIPT_PID ]] \
		&& kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"
	exit 1
}

function download() {
    local url="$1"
    local output="$2"
    wget -q --show-progress -O "$output" "$url" || curl -fLo "$output" "$url"
}

function download_stdout() {
    local url="$1"
    wget -qO- "$url" || curl -fsSL "$url"
}

function eerror() {
	echo "[1;31merror:[m $*" >&2
}

function einfo() {
	echo "[[1m+[m] [1;33m$*[m"
}

function env_update() {
    env-update \
        || die "Error in env-update"
    export DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-}"
    export DEBUGINFOD_IMA_CERT_PATH="${DEBUGINFOD_IMA_CERT_PATH:-}"
    source /etc/profile \
        || die "Could not source /etc/profile"
}

function flush_stdin() {
	local empty_stdin
	# Unused variable is intentional.
	# shellcheck disable=SC2034
	while read -r -t 0.01 empty_stdin; do true; done
}

function init_bash() {
	source /etc/profile
	umask 0077
	export PS1='(chroot) \[[0;31m\]\u\[[1;31m\]@\h \[[1;34m\]\w \[[m\]\$ \[[m\]'
}; export -f init_bash

function mkdir_or_die() {
	# shellcheck disable=SC2174
	mkdir -m "$1" -p "$2" \
		|| die "Could not create directory '$2'"
}

function try() {
	local response
	local cmd_status
	local prompt_parens="([1mS[mhell/[1mr[metry/[1ma[mbort/[1mc[montinue/[1mp[mrint)"

	# Outer loop, allows us to retry the command
	while true; do
		# Try command
		"$@"
		cmd_status="$?"

		if [[ $cmd_status != 0 ]]; then
			echo "[1;31m * Command failed: [1;33m\$[m $*"
			echo "Last command failed with exit code $cmd_status"

			# Prompt until input is valid
			while true; do
				echo -n "Specify next action $prompt_parens "
				flush_stdin
				read -r response \
					|| die "Error in read"
				case "${response,,}" in
					''|s|shell)
						echo "You will be prompted for action again after exiting this shell."
						/bin/bash --init-file <(echo "init_bash")
						;;
					r|retry) continue 2 ;;
					a|abort) die "Installation aborted" ;;
					c|continue) return 0 ;;
					p|print) echo "[1;33m\$[m $*" ;;
					*) ;;
				esac
			done
		fi

		return
	done
}

function validate_block_device() {
    local device="$1"
    if [[ ! -b "$device" ]]; then
        echo "Error: $device is not a valid block device."
        exit 1
    fi
}

function validate_variable() {
    local var_name="$1"
    local var_value="${!1}" # Indirect expansion to get the value of the variable name
    if [[ -z "$var_value" ]]; then
        echo "Error: Variable $var_name is not set in $CONFIG_FILE."
        exit 1
    fi
}

function verify_partitions() {
    echo ""
    echo "Please review the partition layout below before formatting."
    echo ""

    # 1. Show a clean tree view of the disks
    echo "--- Visual Layout (lsblk) ---"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL $EFI_DISK $ROOT_DISK
    echo ""

    # 2. Show detailed partition table for EFI disk
    echo "--- Detailed Info for EFI Disk ($EFI_DISK) ---"
    parted "$EFI_DISK" print
    echo ""

    # 3. Show detailed partition table for Root/Swap disk
    echo "--- Detailed Info for Root/Swap Disk ($ROOT_DISK) ---"
    parted "$ROOT_DISK" print
    echo ""

    echo "========================================================"
    echo "Expected Layout:"
    echo "  $EFI_DISK -> 1 partition (ESP, fat32, size: $EFI_SIZE)"
    echo "  $ROOT_DISK -> 2 partitions (1: linux-swap size: $SWAP_SIZE, 2: btrfs size: rest of disk)"
    echo "========================================================"
    echo ""

    # Prompt for confirmation. Using 'yes' instead of 'y' prevents accidental Enter presses.
    read -p "Does the layout match your expectations? Type 'YES' to continue: " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo "Aborting script. No filesystems were created."
        exit 1
    fi

    echo "Verification passed. Proceeding to filesystem creation..."
}
