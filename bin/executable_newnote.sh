#!/bin/bash

mkdir -p ~/Documents/notes
# Get current date and time in the desired format
filename="$(date '+%Y-%m-%d-%H-%M-%S').md"
touch ~/Documents/notes/"$filename"

nvim ~/Documents/notes/"$filename"
