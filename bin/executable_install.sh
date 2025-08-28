
#!/bin/bash
# install.sh - Arch Linux Auto-install Script

# --- Configuration ---
# List of official Arch packages to install
# Ensure 'wget' is included for downloading .tar.xz files
PACMAN_PACKAGES=(
    "git"          # Essential for cloning repos (chezmoi, custom tools)
    "wget"         # For downloading files from URLs
    "tar"          # For extracting .tar.xz files (usually part of base install, but good to ensure)
    "chezmoi"      # We'll install chezmoi itself
    "kitty" # terminal emulator
    "neovim" # Text editor
    "brightnessctl" # backlight brightness cli tool
    "fastfetch" # fun graphic
    "fd" # better find
    "du" # estimates file sizes
    "gdu" # cli for du
    # Fun
    "scrcpy" # copy android scrren into pc
    # UI
    "kvantum" # theme manager
    "qt5ct" # theme manager for qt apps
    "qt6ct" # theme manager for qt apps
    "starship" # cute terminal prompt
    "waybar" # status bar for hyprland
    "hyprpaper" # wallpaper manager for hyprland
    # Dev
    "uv" # everything you need for python in terminal
    "hugo" # static site generator
)

# --- General Script Settings ---
set -e          # Exit immediately if a command exits with a non-zero status.
set -u          # Treat unset variables as an error.
set -o pipefail # If any command in a pipeline fails, that return code will be used.

# Function for logging messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure script is run with sudo
check_sudo() {
    log "Checking sudo access..."
    sudo -v || { log "Sudo access required. Please enter password and run again."; exit 1; }
    log "Sudo access confirmed."
}

# Install an official Arch package if it's not already installed
install_package() {
    local package_name="$1"
    if ! pacman -Qs "$package_name" > /dev/null; then
        log "Installing $package_name..."
        sudo pacman -S --noconfirm "$package_name" || log "ERROR: Failed to install $package_name"
    else
        log "$package_name is already installed."
    fi
}

# --- Custom Software Handlers ---

# Function to download, extract, and install a .tar.xz file from a URL
# Arguments:
#   $1: URL of the .tar.xz file
#   $2: Expected name of the top-level directory within the archive (e.g., 'my-app-1.0.0')
#   $3: Destination directory where the extracted content should go (e.g., '/opt', '$HOME/.local')
#   $4: (Optional) New name for the installed directory (defaults to $2 if not provided)
download_and_install_tar_xz() {
    local url="$1"
    local archive_name="$(basename "$url")"
    local expected_top_dir="$2"
    local install_base_dir="$3"
    local installed_name="${4:-$expected_top_dir}" # Use $4 if provided, else $2

    local temp_dir="/tmp/tar-xz-install-$$" # Unique temporary directory
    local final_install_path="$install_base_dir/$installed_name"

    # Check for idempotency: if the final path already exists, assume installed
    if [ -d "$final_install_path" ] || [ -f "$final_install_path" ]; then
        log "$installed_name already appears to be installed at $final_install_path."
        return 0
    fi

    log "Downloading and installing $archive_name from $url..."
    mkdir -p "$temp_dir" || { log "ERROR: Failed to create temp directory $temp_dir"; return 1; }
    mkdir -p "$install_base_dir" || { log "ERROR: Failed to create install directory $install_base_dir"; return 1; }

    cd "$temp_dir" || { log "ERROR: Failed to cd into $temp_dir"; return 1; }

    log "Downloading $archive_name..."
    wget -q --show-progress "$url" -O "$archive_name" || { log "ERROR: Failed to download $archive_name"; rm -rf "$temp_dir"; return 1; }

    log "Extracting $archive_name..."
    tar -xf "$archive_name" || { log "ERROR: Failed to extract $archive_name"; rm -rf "$temp_dir"; return 1; }

    # Verify the extracted directory exists
    if [ ! -d "$expected_top_dir" ]; then
        log "WARNING: Extracted archive did not contain expected top-level directory '$expected_top_dir'. Please check the archive structure or adjust script."
        # Attempt to find the first directory if the name mismatch. This is a heuristic.
        local first_dir=$(find . -maxdepth 1 -mindepth 1 -type d -print -quit)
        if [ -n "$first_dir" ]; then
            log "Found directory '$first_dir'. Using that as the source."
            expected_top_dir=$(basename "$first_dir")
        else
            log "ERROR: No top-level directory found after extraction in $temp_dir. Cannot proceed."
            rm -rf "$temp_dir"; return 1;
        fi
    fi

    log "Moving extracted content to $final_install_path..."
    # Use sudo if installing to a system-wide location like /opt
    # Using 'mv' to ensure proper permissions/ownership in final location if root.
    if [[ "$install_base_dir" == "/opt" || "$install_base_dir" == "/usr/local" ]]; then
        sudo mv "$expected_top_dir" "$final_install_path" || { log "ERROR: Failed to move $expected_top_dir to $final_install_path"; rm -rf "$temp_dir"; return 1; }
    else
        mv "$expected_top_dir" "$final_install_path" || { log "ERROR: Failed to move $expected_top_dir to $final_install_path"; rm -rf "$temp_dir"; return 1; }
    fi

    cd - > /dev/null # Go back to the previous directory
    rm -rf "$temp_dir" # Clean up temporary directory
    log "$installed_name installed successfully to $final_install_path."
}

# --- Main Installation Steps ---
main() {
    check_sudo

    log "Starting initial system update..."
    sudo pacman -Syu --noconfirm || log "WARNING: Initial system update failed, but continuing."

    log "Installing official Arch packages..."
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        install_package "$pkg"
    done

    log "Running custom software installations and builds..."
    # Example for a .tar.xz file:
    # URL: The direct link to your .tar.xz file
    # Expected_top_dir: When you extract the tar.xz, what is the name of the folder created?
    #                   e.g., if foo-1.0.tar.xz extracts to a folder named 'foo-1.0', then use 'foo-1.0'.
    # Install_base_dir: Where do you want to place this folder?
    #                   Common choices:
    #                   - /opt : For self-contained third-party software (system-wide)
    #                   - $HOME/.local : For user-specific software (e.g., $HOME/.local/bin)
    # New_installed_name: (Optional) If you want to rename the folder on install (e.g., 'foo' instead of 'foo-1.0')
    download_and_install_tar_xz \
        "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US" \
        "firefox" \
        "/opt" \

    log "All auto-install script steps completed successfully!"
}

# Execute the main function
main "$@"
