
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
    "less" # shows console output as a scrollable
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
WEB_PACKAGES=(
    # Format: "URL|Name_inside_archive_and_final_install_name|Target_parent_directory|Archive_type_hint"
    "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US|firefox|$HOME/opt|tar.xz"
    "https://download.anydesk.com/linux/anydesk-7.0.2-amd64.tar.gz|anydesk-7.0.2|$HOME/opt|tar.gz"
    # EXAMPLES
    # Example 3: Tutanota (AppImage) - installs 'tutanota-desktop' file into '$HOME/opt'
    # "https://download.tutanota.com/desktop/tutanota-desktop-linux.AppImage|tutanota-desktop|$HOME/opt|AppImage"
    # Example 4: Terraform (zip, single binary) - extracts 'terraform' binary to '/usr/local/bin'
    # "https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip|terraform|/usr/local/bin|zip"
    # "https://github.com/syncthing/syncthing/releases/download/v2.0.6/syncthing-linux-amd64-v2.0.6.tar.gz|syncthing-linux-amd64-v2.0.6|$HOME/opt|tar.gz"
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
    local name_inside_archive="$2" # The expected name of the top-level item (file or directory) inside the archive,
                                   # and also the final name of the installed item in target_parent_dir.
    local target_parent_dir="$3"   # The parent directory where the package will be installed (e.g., /opt, $HOME/opt)
    local archive_type_hint="$4"   # A hint for the archive type: "tar.xz", "tar.gz", "zip", "AppImage"

    local final_install_path="$target_parent_dir/$name_inside_archive"
    local temp_dir="/tmp/pkg-install-$$" # Unique temporary directory for downloads and extraction
    local downloaded_file="$temp_dir/download_payload.${archive_type_hint}" # Temp filename with type hint

    log "--- Processing '$name_inside_archive' ---"

    # --- Idempotency Check ---
    if [ -d "$final_install_path" ] || [ -f "$final_install_path" ]; then
        log "Package '$name_inside_archive' already appears to be installed at $final_install_path. Skipping."
        return 0
    fi

    # --- Create target parent directory ---
    # Determine if sudo is needed for target_parent_dir creation
    local mkdir_cmd="mkdir -p \"$target_parent_dir\""
    if [[ "$target_parent_dir" == "/opt" || "$target_parent_dir" == "/usr/local/bin" ]]; then
        log "Target directory '$target_parent_dir' requires root permissions for creation. Using sudo."
        sudo bash -c "$mkdir_cmd" || { log "ERROR: Failed to create target directory $target_parent_dir with sudo."; return 1; }
    else
        bash -c "$mkdir_cmd" || { log "ERROR: Failed to create target directory $target_parent_dir."; return 1; }
    fi

    # --- Handle AppImage as a special case (download directly, no extraction) ---
    if [[ "$archive_type_hint" == "AppImage" ]]; then
        log "Downloading AppImage directly to $final_install_path..."
        # Use curl with progress bar and follow redirects (-L)
        curl -L --progress-bar -o "$final_install_path" "$url" || { log "ERROR: Failed to download AppImage from $url"; return 1; }
        log "Making $final_install_path executable..."
        chmod +x "$final_install_path" || { log "ERROR: Failed to make AppImage executable"; rm -f "$final_install_path"; return 1; }
        log "AppImage '$name_inside_archive' installed successfully to $final_install_path."
        return 0 # Installation complete for AppImage, exit function
    fi

    # --- Handle other archive types (require download to temp, then extraction) ---
    mkdir -p "$temp_dir" || { log "ERROR: Failed to create temp directory $temp_dir"; return 1; }
    # Change into temp directory for easier extraction/manipulation
    cd "$temp_dir" || { log "ERROR: Failed to cd into $temp_dir"; rm -rf "$temp_dir"; return 1; }

    log "Downloading '$url' to temporary file '$downloaded_file'..."
    curl -L --progress-bar -o "$downloaded_file" "$url" || { log "ERROR: Failed to download $url"; rm -rf "$temp_dir"; return 1; }

    log "Extracting '$downloaded_file' (Type: $archive_type_hint)..."
    case "$archive_type_hint" in
        "tar.xz")
            if ! command -v xz &> /dev/null; then log "ERROR: 'xz' command (for .tar.xz) not found. Please install it."; rm -rf "$temp_dir"; return 1; fi
            tar -Jxf "$downloaded_file" || { log "ERROR: Failed to extract tar.xz archive."; rm -rf "$temp_dir"; return 1; }
            ;;
        "tar.gz")
            tar -zxf "$downloaded_file" || { log "ERROR: Failed to extract tar.gz archive."; rm -rf "$temp_dir"; return 1; }
            ;;
        "zip")
            if ! command -v unzip &> /dev/null; then
                log "ERROR: 'unzip' command not found. Please install it to handle .zip files."
                rm -rf "$temp_dir"; return 1;
            fi
            unzip -q "$downloaded_file" || { log "ERROR: Failed to extract zip archive."; rm -rf "$temp_dir"; return 1; }
            ;;
        *)
            log "ERROR: Unsupported archive type '$archive_type_hint'. Cannot extract."
            rm -rf "$temp_dir"; return 1;
            ;;
    esac

    # --- Verify extracted content and move to final destination ---
    # Check if the expected item (file or directory) exists in the temp extraction path
    if [ ! -e "$name_inside_archive" ]; then # Checks for file OR directory existence
        log "ERROR: After extraction, expected item '$name_inside_archive' not found in $temp_dir."
        log "Please verify the content of the archive and the 'name_inside_archive' parameter."
        # Attempt a heuristic for common tarball behavior: single, differently named top-level directory.
        if [[ "$archive_type_hint" == tar.* ]]; then
            local extracted_dir_guess=$(find . -maxdepth 1 -mindepth 1 -type d ! -name "$name_inside_archive" -print -quit)
            if [ -n "$extracted_dir_guess" ]; then
                log "WARNING: Found a different top-level directory '$extracted_dir_guess'. Using this instead of '$name_inside_archive'."
                name_inside_archive=$(basename "$extracted_dir_guess") # Update for move
                final_install_path="$target_parent_dir/$name_inside_archive" # Update final path too
            else
                log "ERROR: No suitable content found for moving after extraction in '$temp_dir'."
                cd - > /dev/null # Go back before removing temp dir
                rm -rf "$temp_dir"; return 1;
            fi
        else # For zip or other types, if it's not found, it's a hard error.
            cd - > /dev/null # Go back before removing temp dir
            rm -rf "$temp_dir"; return 1;
        fi
    fi

    log "Moving extracted content '$name_inside_archive' from $temp_dir to $final_install_path..."
    # Determine if sudo is needed for 'mv' operation
    local mv_cmd="mv \"$name_inside_archive\" \"$final_install_path\""
    if [[ "$target_parent_dir" == "/opt" || "$target_parent_dir" == "/usr/local/bin" ]]; then
        sudo bash -c "$mv_cmd" || { log "ERROR: Failed to move '$name_inside_archive' to $final_install_path with sudo."; cd - > /dev/null; rm -rf "$temp_dir"; return 1; }
    else
        bash -c "$mv_cmd" || { log "ERROR: Failed to move '$name_inside_archive' to $final_install_path."; cd - > /dev/null; rm -rf "$temp_dir"; return 1; }
    fi

    # Make executable if it's a single file (not a directory)
    if [ -f "$final_install_path" ]; then # Check if the installed item is a file
        if ! [ -x "$final_install_path" ]; then # If it's a file and not already executable
            log "Making $final_install_path executable."
            # Use sudo if target_parent_dir required it
            if [[ "$target_parent_dir" == "/opt" || "$target_parent_dir" == "/usr/local/bin" ]]; then
                sudo chmod +x "$final_install_path" || log "WARNING: Failed to make $final_install_path executable with sudo."
            else
                chmod +x "$final_install_path" || log "WARNING: Failed to make $final_install_path executable."
            fi
        fi
    fi

    cd - > /dev/null # Go back to the directory from which the function was called
    rm -rf "$temp_dir" # Clean up temporary directory
    log "Package '$name_inside_archive' installed successfully to $final_install_path."
    return 0
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
        IFS='|' read -r url name_inside_archive target_parent_dir archive_type_hint <<< "$task_string"

        # Call the generic installation function
        install_web_package "$url" "$name_inside_archive" "$target_parent_dir" "$archive_type_hint"
        echo # Add a blank line for readability between tasks
    done

    log "All auto-install script steps completed successfully!"
}

# Execute the main function
main "$@"
