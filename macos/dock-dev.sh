#!/usr/bin/env bash
set -euo pipefail

# Dock REBUILD script — reference / dev-mode only. NOT run by `make dock`.
#
# `make dock` now imports macos/dock-backup.plist (captured by `make backup`
# after you arrange the dock interactively). This script is kept for two
# cases:
#   1. First-run on a Mac where dock-backup.plist doesn't yet exist.
#   2. Regenerating the backup plist from a declarative known-good list —
#      edit the add_app lines below, run this script, then `make backup` to
#      snapshot the result.
#
# Usage: bash macos/dock-dev.sh  (then `make backup` if you want to commit)

echo "Rebuilding Dock from hardcoded list (dock-dev.sh)..."

# Clear existing Dock apps
defaults write com.apple.dock persistent-apps -array

add_app() {
    defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$1</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

add_spacer() {
    defaults write com.apple.dock persistent-apps -array-add '{"tile-type"="spacer-tile";}'
}

# Email
add_app "/Applications/Airmail.app"

# Writing
add_app "/Applications/Sublime Text.app"
add_app "/Applications/Obsidian.app"
add_app "/Applications/Craft.app"
add_app "/Applications/Notion.app"

add_spacer

# Browse & Chat
add_app "/Applications/Microsoft Edge.app"
add_app "/Applications/Comet.app"
add_app "/Applications/WhatsApp.app"
add_app "/Applications/Discord.app"

add_spacer

# Design & Dev tools
add_app "/Applications/Figma.app"
add_app "/Applications/Kaleidoscope.app"
add_app "/System/Applications/Utilities/Terminal.app"
add_app "/Applications/Tower.app"

add_spacer

# AI & Code
add_app "/Applications/Craft Agents.app"
add_app "/Applications/Claude.app"
add_app "/Applications/Visual Studio Code.app"
add_app "/Applications/Cursor.app"

# Right side — Downloads folder
defaults write com.apple.dock persistent-others -array
defaults write com.apple.dock persistent-others -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$HOME/Downloads</string><key>_CFURLStringType</key><integer>0</integer></dict><key>file-type</key><integer>2</integer><key>arrangement</key><integer>2</integer><key>displayas</key><integer>0</integer><key>showas</key><integer>0</integer></dict><key>tile-type</key><string>directory-tile</string></dict>"

killall Dock

echo "Dock layout restored."
