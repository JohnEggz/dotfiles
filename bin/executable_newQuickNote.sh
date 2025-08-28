#!/bin/bash

# Base path for your notes. No spaces around '=' for variable assignment in Bash.
path='/tmp/qnotes/'

# Ensure the directory exists, regardless of whether we're creating a file or opening the directory.
mkdir -p "$path"

# Check if the first argument is '--dir' or '-d'
if [[ "$1" == "--dir" || "$1" == "-d" ]]; then
    echo "Opening directory: '$path' in preferred file viewer..."
    # xdg-open uses your system's default application to open the directory.
    # On Wayland/Hyprland, this will typically respect your file manager associations.
    xdg-open "$path"
else
    # Original logic: create a new note file and open it with nvim

    # Get current date and time in the desired format
    filename="temp$(date '+%Y-%m-%d-%H-%M-%S').md"
    # Construct the full path for the new file
    filepath="${path}${filename}"

    echo "Creating new note: '$filepath' and opening with nvim..."
    touch "$filepath"

    nvim "$filepath"
fi
