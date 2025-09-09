#
#!/bin/bash
#
#
# --- Configuration ---
# Directory where multi-file/directory packages will be installed (e.g., AnyDesk)
PACKAGES_OPT_DIR="$HOME/opt"
# Directory where single binaries (e.g., AppImages, extracted tools like lazygit) will be installed
PACKAGES_BIN_DIR="$HOME/bin"
# File to keep track of successfully installed URLs to avoid re-downloading
INSTALLED_URLS_FILE="$HOME/.local/share/web_packages_urls.txt" 

# --- Setup Directories ---
# Ensure target directories exist
mkdir -p "$PACKAGES_OPT_DIR" || { echo "Error: Could not create $PACKAGES_OPT_DIR"; exit 1; }
mkdir -p "$PACKAGES_BIN_DIR" || { echo "Error: Could not create $PACKAGES_BIN_DIR"; exit 1; }
mkdir -p "$(dirname "$INSTALLED_URLS_FILE")" || { echo "Error: Could not create directory for $INSTALLED_URLS_FILE"; exit 1; }
touch "$INSTALLED_URLS_FILE" # Ensure the URLs file exists

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
    "less" # shows console output as a scrollable
    "firefox"
    "yazi"
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

# Formats:
# tar.gz
# tar.xz
# AppImage
# zip
#
# Formating: URL|extension
WEB_PACKAGES=(
    "https://download.anydesk.com/linux/anydesk-7.0.2-amd64.tar.gz|tar.gz"
    "https://github.com/localsend/localsend/releases/download/v1.17.0/LocalSend-1.17.0-linux-x86-64.tar.gz|tar.gz"
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
# --- Generic Installation Function ---
# This function handles downloading, extracting (if needed), and installing
# different types of archive files.
install_web_package() {
    local url="$1"                 # The URL to download the package from
    local archive_type_hint="$2"   # A hint for the archive type: "tar.xz", "tar.gz", "zip", "AppImage"

    log "Attempting to install: $url (Type: $archive_type_hint)"

    # 1. Check if current url is in urls.txt
    if grep -qF "$url" "$INSTALLED_URLS_FILE"; then
        log "URL '$url' already found in '$INSTALLED_URLS_FILE'. Skipping."
        return 0 # Success, already installed
    fi

    local download_filename=$(basename "$url")
    local tmp_download_path=$(mktemp "/tmp/$download_filename.XXXXXX")
    local tmp_extract_dir # Will be created later if needed

    # Ensure temporary files/dirs are cleaned up on function exit
    # This trap will run whether the function succeeds or fails.
    trap 'rm -rf "$tmp_download_path" "$tmp_extract_dir"' RETURN

    log "Downloading '$url' to '$tmp_download_path'..."
    # 2. Download file with wget
    if ! wget -q --show-progress -O "$tmp_download_path" "$url"; then
        log "Error: Failed to download '$url'."
        return 1
    fi
    log "Download complete."

    local package_base_name=$(echo "$download_filename" | sed -E 's/\.(tar\.gz|tar\.xz|zip|appimage)$//i')
    local install_success=0

    # Special handling for AppImage: move directly to ~/bin
    if [[ "$archive_type_hint" == "AppImage" ]]; then
        local target_path="$PACKAGES_BIN_DIR/$download_filename"
        log "Moving AppImage '$download_filename' to '$target_path'..."
        if mv "$tmp_download_path" "$target_path"; then
            chmod +x "$target_path"
            log "AppImage installed and made executable: '$target_path'"
            install_success=1
        else
            log "Error: Failed to move AppImage."
        fi
    else
        # 3. Make a temporary dir and extract files into it (for non-AppImage types)
        tmp_extract_dir=$(mktemp -d)
        log "Extracting '$tmp_download_path' to '$tmp_extract_dir'..."
        case "$archive_type_hint" in
            "tar.gz")
                if ! tar -xzf "$tmp_download_path" -C "$tmp_extract_dir"; then
                    log "Error: Failed to extract tar.gz archive."
                    return 1
                fi
                ;;
            "tar.xz")
                if ! tar -xJf "$tmp_download_path" -C "$tmp_extract_dir"; then
                    log "Error: Failed to extract tar.xz archive."
                    return 1
                fi
                ;;
            "zip")
                # -q for quiet, -d for directory
                if ! unzip -q "$tmp_download_path" -d "$tmp_extract_dir"; then
                    log "Error: Failed to extract zip archive."
                    return 1
                fi
                ;;
            *)
                log "Error: Unsupported archive type hint '$archive_type_hint'."
                return 1
                ;;
        esac
        log "Extraction complete."

        # 4. Check the contents of temporary dir and depending on contents:
        # Use `find` to handle hidden files and complex names better,
        # but for common cases, globbing `*` is sufficient and simpler.
        # Let's use globbing `"$tmp_extract_dir"/*` for simplicity as requested.
        local extracted_contents=( "$tmp_extract_dir"/* )
        local num_contents="${#extracted_contents[@]}"

        if (( num_contents == 0 )); then
            log "Warning: No contents found in extracted directory '$tmp_extract_dir'."
            return 1
        elif (( num_contents > 1 )); then
            # 4.1 if dir contains multiple files/dirs, make new dir in ~/opt and move contents into new dir
            local target_dir="$PACKAGES_OPT_DIR/$package_base_name"
            log "Multiple items found. Creating '$target_dir' and moving contents."
            mkdir -p "$target_dir"
            if mv "$tmp_extract_dir"/* "$target_dir/"; then
                log "Contents moved to '$target_dir'."
                install_success=1
            else
                log "Error: Failed to move multiple contents to '$target_dir'."
            fi
        elif (( num_contents == 1 )); then
            local first_item="${extracted_contents[0]}"
            if [[ -d "$first_item" ]]; then
                # 4.2 if it contains only a dir, just move that dir into ~/opt directly
                log "Single directory found. Moving '$first_item' to '$PACKAGES_OPT_DIR/'."
                # Rename if package_base_name is different from actual extracted dir name
                local final_dir_name="$(basename "$first_item")"
                if mv "$first_item" "$PACKAGES_OPT_DIR/$final_dir_name"; then
                    log "Directory moved to '$PACKAGES_OPT_DIR/$final_dir_name'."
                    install_success=1
                else
                    log "Error: Failed to move single directory to '$PACKAGES_OPT_DIR'."
                fi
            else
                # 4.3 if it contains only a single file/binary, move it into ~/bin
                local target_path="$PACKAGES_BIN_DIR/$(basename "$first_item")"
                log "Single file/binary found. Moving '$first_item' to '$target_path'."
                if mv "$first_item" "$target_path"; then
                    chmod +x "$target_path" # Ensure executability for single files
                    log "File moved to '$target_path' and made executable."
                    install_success=1
                else
                    log "Error: Failed to move single file to '$PACKAGES_BIN_DIR'."
                fi
            fi
        fi
    fi

    # 5. If succeeded, append url into urls.txt
    if (( install_success == 1 )); then
        echo "$url" >> "$INSTALLED_URLS_FILE"
        log "URL added to '$INSTALLED_URLS_FILE'."
        return 0
    else
        log "Installation failed for '$url'."
        return 1
    fi
}

# --- Main Installation Steps ---
main() {
    check_sudo

    # log "Starting initial system update..."
    # sudo pacman -Syu --noconfirm || log "WARNING: Initial system update failed, but continuing."

    log "Installing official Arch packages..."
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        install_package "$pkg"
    done

    log "Running custom software installations and builds..."

    for task_string in "${WEB_PACKAGES[@]}"; do
        # Split the string by the delimiter (pipe '|') into four variables
        IFS='|' read -r url archive_type_hint <<< "$task_string"

        # Call the generic installation function
        install_web_package "$url" "$archive_type_hint"
        echo # Add a blank line for readability between tasks
    done

    log "All auto-install script steps completed successfully!"
}

# Execute the main function
main "$@"
