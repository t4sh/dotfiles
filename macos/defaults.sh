#!/usr/bin/env bash
set -eo pipefail

trap 'printf "  ✗ macos/defaults.sh failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

MODE=apply
PRIVILEGED=1
while (($# > 0)); do
    case "$1" in
        --dry-run) MODE=dry-run ;;
        --check) MODE=check ;;
        --user-only) PRIVILEGED=0 ;;
        -h|--help)
            cat <<'EOF'
usage: macos/defaults.sh [--dry-run|--check] [--user-only]

  --dry-run    print mutations without applying them
  --check      read back representative managed settings; do not mutate
  --user-only  skip sudo-backed identity, security, login, and energy policy
EOF
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

APPLICATION_FIREWALL_TOOL=/usr/libexec/ApplicationFirewall/socketfilterfw
if [[ "$MODE" == check && -n "${DOTFILES_FIREWALL_TOOL:-}" ]]; then
    APPLICATION_FIREWALL_TOOL="$DOTFILES_FIREWALL_TOOL"
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "macos/defaults.sh requires macOS" >&2; exit 1; }
MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
DEFAULT_CAPTURE_PARENT="$HOME/odrive/ash.a.t@live/Workspace"
if [[ -n "${DOTFILES_CAPTURE_DIR:-}" ]]; then
    CAPTURE_DIR="$DOTFILES_CAPTURE_DIR"
elif [[ -d "$DEFAULT_CAPTURE_PARENT" ]]; then
    CAPTURE_DIR="$DEFAULT_CAPTURE_PARENT/Screengrabs"
else
    CAPTURE_DIR="$HOME/Desktop/Screengrabs"
    echo "  ⚠ odrive workspace unavailable; screenshot policy uses $CAPTURE_DIR until make macos is rerun" >&2
fi
[[ "$CAPTURE_DIR" == /* && -n "${CAPTURE_DIR//\//}" ]] || {
    echo "screenshot destination must be an absolute non-root path: $CAPTURE_DIR" >&2
    exit 2
}
case "$MACOS_MAJOR" in
    15|26) ;;
    *)
        if [[ "$MODE" == apply && "${DOTFILES_MACOS_ALLOW_UNTESTED:-0}" != "1" ]]; then
            echo "macOS $MACOS_VERSION is outside the tested majors (15, 26)." >&2
            echo "Review the dry-run, then set DOTFILES_MACOS_ALLOW_UNTESTED=1 to proceed." >&2
            exit 1
        fi
        echo "  ⚠ macOS $MACOS_VERSION is outside the tested majors (15, 26); $MODE remains read-only" >&2
        ;;
esac
echo "macOS defaults policy: mode=$MODE scope=$([[ $PRIVILEGED -eq 1 ]] && echo full || echo user-only) host=$MACOS_VERSION"

verify_defaults() {
    local failures=0 actual domain key expected firewall stealth capture
    while IFS=$'\t' read -r domain key expected; do
        actual="$(command defaults read "$domain" "$key" 2>/dev/null || true)"
        actual="${actual%\"}"; actual="${actual#\"}"
        if [[ "$actual" == "$expected" ]]; then
            printf '  ✓ %s %s = %s\n' "$domain" "$key" "$expected"
        else
            printf '  ✗ %s %s expected %s, got %s\n' "$domain" "$key" "$expected" "${actual:-<unset>}" >&2
            failures=$((failures + 1))
        fi
    done <<'EOF'
NSGlobalDomain	AppleShowAllExtensions	0
com.apple.finder	AppleShowAllFiles	1
com.apple.finder	ShowPathbar	1
com.apple.dock	autohide	0
com.apple.dock	show-recents	0
com.apple.screensaver	askForPassword	1
com.apple.screensaver	askForPasswordDelay	0
com.apple.desktopservices	DSDontWriteNetworkStores	1
com.apple.SoftwareUpdate	AutomaticCheckEnabled	1
EOF
    capture="$(command defaults read com.apple.screencapture location 2>/dev/null || true)"
    capture="${capture%\"}"; capture="${capture#\"}"
    if [[ "$capture" == "$CAPTURE_DIR" ]]; then
        printf '  ✓ com.apple.screencapture location = %s\n' "$CAPTURE_DIR"
    else
        printf '  ✗ com.apple.screencapture location expected %s, got %s\n' \
            "$CAPTURE_DIR" "${capture:-<unset>}" >&2
        failures=$((failures + 1))
    fi
    if (( PRIVILEGED )) && [[ -x "$APPLICATION_FIREWALL_TOOL" ]]; then
        firewall="$("$APPLICATION_FIREWALL_TOOL" --getglobalstate 2>/dev/null || true)"
        stealth="$("$APPLICATION_FIREWALL_TOOL" --getstealthmode 2>/dev/null || true)"
        [[ "$firewall" == *"is enabled"* || "$firewall" == *"State = 1"* ]] || {
            echo "  ✗ application firewall is not enabled" >&2
            failures=$((failures + 1))
        }
        [[ "$stealth" == *"stealth mode is on"* || "$stealth" == *"is enabled"* ]] || {
            echo "  ✗ firewall stealth mode is not enabled" >&2
            failures=$((failures + 1))
        }
    fi
    (( failures == 0 ))
}

if [[ "$MODE" == check ]]; then
    verify_defaults
    exit $?
fi

if [[ "$MODE" == dry-run ]]; then
    # sudo is wrapped too, so sudo-backed calls are printed as whole commands.
    # shellcheck disable=SC2032
    defaults() { printf '  would run: defaults'; printf ' %q' "$@"; echo; }
    osascript() { printf '  would run: osascript'; printf ' %q' "$@"; echo; }
    if (( PRIVILEGED )); then
        sudo() { printf '  would run: sudo'; printf ' %q' "$@"; echo; }
    else
        sudo() { printf '  skipped privileged command:'; printf ' %q' "$@"; echo; }
    fi
    killall() { printf '  would run: killall'; printf ' %q' "$@"; echo; }
    # shellcheck disable=SC2032
    chflags() { printf '  would run: chflags'; printf ' %q' "$@"; echo; }
elif (( ! PRIVILEGED )); then
    sudo() { printf '  - skipped privileged command:' >&2; printf ' %q' "$@" >&2; echo >&2; }
fi

warn_on_fail() {
    local msg="$1"
    shift
    "$@" || {
        printf '  ⚠ %s\n' "$msg" >&2
        return 0
    }
}

write_safari_default() {
    local key="$1"
    shift
    warn_on_fail "could not set Safari $key (Full Disk Access may be required)" \
        defaults write com.apple.Safari "$key" "$@"
}

###############################################################################
# Snippets From .macos file by Mathias Byens            https://mths.be/macos #
###############################################################################

# Close any open "System Settings" panes, to prevent them from overriding
# settings we’re about to change
osascript -e 'tell application "System Settings" to quit'

# Ask for the administrator password upfront and keep it alive only for a full
# real apply. Dry-run and user-only modes never prompt for sudo.
if [[ "$MODE" == apply && $PRIVILEGED -eq 1 ]]; then
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# System identity + lock-screen recovery info.
#
# Resolution order (first non-empty wins, no prompt if already resolved):
#   1. Env vars: DOTFILES_SYSNAME / DOTFILES_RECOVERY_PHONE / DOTFILES_RECOVERY_EMAIL
#   2. Cached file at ~/.dotfiles-local/macos-prefs (sourced; written after first prompt)
#   3. Interactive prompt — only path for a fresh Mac with no cache
#
# No fallback to `scutil --get ComputerName`: on a fresh Mac that would return
# the Apple default ("Ashs-MacBook-Pro") and silently skip the prompt, so
# the new name would never actually get set. Cache-only keeps the
# "prompt-on-new-Mac, silent-on-re-run" contract exact.
#
# Cache lives outside the repo (gitignored convention) because phone/email are
# personal data, not secrets.
CACHE_DIR="$HOME/.dotfiles-local"
CACHE_FILE="$CACHE_DIR/macos-prefs"
# shellcheck source=/dev/null
[ -f "$CACHE_FILE" ] && . "$CACHE_FILE"

NewSysName="${DOTFILES_SYSNAME:-${NewSysName:-}}"
RecoveryPhone="${DOTFILES_RECOVERY_PHONE:-${RecoveryPhone:-}}"
RecoveryEmail="${DOTFILES_RECOVERY_EMAIL:-${RecoveryEmail:-}}"

if [[ "$MODE" == dry-run ]]; then
    NewSysName="${NewSysName:-<prompted-on-apply>}"
    RecoveryPhone="<configured-on-apply>"
    RecoveryEmail="<configured-on-apply>"
elif [ -z "$NewSysName" ] || [ -z "$RecoveryPhone" ] || [ -z "$RecoveryEmail" ]; then
    echo ":::::: System identity — one-time setup (values will be cached) ::::::"
    [ -z "$NewSysName" ]     && read -r -p '::::::::::::::::::: Discoverable as: ' NewSysName
    [ -z "$RecoveryPhone" ]  && read -r -p ':::::: Recovery Phone at LockScreen: ' RecoveryPhone
    [ -z "$RecoveryEmail" ]  && read -r -p ':::::: Recovery Email at LockScreen: ' RecoveryEmail
    mkdir -p "$CACHE_DIR"
    {
        echo "# Cached by macos/defaults.sh — regenerate by deleting this file."
        echo "NewSysName=$(printf '%q' "$NewSysName")"
        echo "RecoveryPhone=$(printf '%q' "$RecoveryPhone")"
        echo "RecoveryEmail=$(printf '%q' "$RecoveryEmail")"
    } > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
    echo "  ✓ cached to $CACHE_FILE"
fi

# Set computer name (as done via "System Settings" → Sharing)
# NewSysName="atari44"
sudo scutil --set ComputerName "$NewSysName"
sudo scutil --set HostName "$NewSysName"
sudo scutil --set LocalHostName "$NewSysName"
# The dry-run wrapper intentionally cannot intercept the command behind sudo.
# shellcheck disable=SC2033
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$NewSysName"

# Set Text for the Lock message
LoginMsg=$(printf '%s\n%s\n%s\n%s' \
    "    F E D E R É A L     W A R N I N G" \
    "   ━━━━━━━━━━━━━━━━━" \
    "Certain Nuclear meltdown when wrong credentials are used." \
    "Call $RecoveryPhone, or mail at $RecoveryEmail")

# Helper: PlistBuddy Set with Add fallback for fresh installs
plist_set() {
    if [[ "$MODE" == dry-run ]]; then
        printf '  would set plist key %q (%s) to %q in %q\n' "$1" "$2" "$3" "$4"
        return 0
    fi
    /usr/libexec/PlistBuddy -c "Set ${1} ${3}" "${4}" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add ${1} ${2} ${3}" "${4}"
}

FINDER_PLIST=~/Library/Preferences/com.apple.finder.plist

###############################################################################
# Appearance                  https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# System Settings → Appearance → Show scroll bars
# Automatic | WhenScrolling | Always
defaults write NSGlobalDomain AppleShowScrollBars -string "Automatic"

###############################################################################
# Dock                        https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Set the Dock position (default value is "bottom")
defaults write com.apple.dock "orientation" -string "bottom"

# Set the icon size of Dock items in pixels (default value is 48)
defaults write com.apple.dock "tilesize" -int "26"

# Lock the declared Dock layout: no resizing, repositioning, or item changes.
defaults write com.apple.dock "size-immutable" -bool "true"
defaults write com.apple.dock "position-immutable" -bool "true"
defaults write com.apple.dock "contents-immutable" -bool "true"

# Keep the Dock visible and prevent changing the auto-hide setting.
defaults write com.apple.dock "autohide" -bool "false"
defaults write com.apple.dock "autohide-immutable" -bool "true"

# Change the Dock opening and closing animation times (default value is 0.5)
defaults write com.apple.dock "autohide-time-modifier" -float "0"

# Change the Dock opening delay (default value is 0.5)
defaults write com.apple.dock "autohide-delay" -float "0"

# Show recently used apps in a separate section of the Dock (default value is "true")
defaults write com.apple.dock "show-recents" -bool "false"

# Change the Dock minimize animation (default value is "genie")
defaults write com.apple.dock "mineffect" -string "scale"

# Only show opened apps in Dock (default value is "false")
defaults write com.apple.dock "static-only" -bool "false"

# Minimize Applications to their icon in dock
defaults write com.apple.dock "minimize-to-application" -bool "true"

# Enable spring loading for all Dock items
defaults write com.apple.dock "enable-spring-load-actions-on-all-items" -bool "true"

# Show indicator lights for open applications in the Dock
defaults write com.apple.dock "show-process-indicators" -bool "true"

# Don’t animate opening applications from the Dock
defaults write com.apple.dock "launchanim" -bool "false"

# Make Dock icons of hidden applications translucent
defaults write com.apple.dock "showhidden" -bool "true"


###############################################################################
# Screenshots                 https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Disable screenshot shadow when capturing an app (default value is "false")
defaults write com.apple.screencapture "disable-shadow" -bool "false"

# Include date and time in screenshot filenames (default value is "true")
defaults write com.apple.screencapture "include-date" -bool "true"

# Save screenshots and screen recordings to the same custom location.
# `location-last` preserves Screenshot.app's Options → Save to → Other Location
# choice, while `target=file` prevents an app/clipboard target from taking over.
[[ "$MODE" == dry-run ]] || mkdir -p "$CAPTURE_DIR"
defaults write com.apple.screencapture "location" -string "$CAPTURE_DIR"
defaults write com.apple.screencapture "location-last" -string "$CAPTURE_DIR"
defaults write com.apple.screencapture "target" -string "file"

# Choose whether to display a thumbnail after taking a screenshot (default value is "true")
defaults write com.apple.screencapture "show-thumbnail" -bool "true"

# Choose the screenshots image format (default value is "png")
defaults write com.apple.screencapture "type" -string "png"

# Change the default screenshot file name
defaults write com.apple.screencapture "name" -string "screengrab"

###############################################################################
# Finder                      https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Add a quit option to the Finder (default value is "false")
defaults write com.apple.finder "QuitMenuItem" -bool "false"

# Show all filename extensions in the Finder (default value is "false")
defaults write NSGlobalDomain "AppleShowAllExtensions" -bool "false"

# Show hidden files in the Finder (default value is "false")
defaults write com.apple.finder "AppleShowAllFiles" -bool "true"

# Show path bar in the bottom of the Finder windows (default value is "false")
defaults write com.apple.finder "ShowPathbar" -bool "true"

# Display full POSIX path as Finder window title
defaults write com.apple.finder "_FXShowPosixPathInTitle" -bool "true"

# Show status bar in the bottom of the Finder windows (default value is "false")
defaults write com.apple.finder "ShowStatusBar" -bool "true"

# Set the default view style for folders without custom setting (default value is "icnv")
# Icon View : `icnv`
# List View : `Nlsv`
# Column View : `clmv`
# Gallery View : `Flwv`   (was "Cover Flow" before Mojave)
defaults write com.apple.finder "FXPreferredViewStyle" -string "clmv"

# Set the default path for new Window's location
# Computer : `PfCm`
# Volume : `PfVo`
# $HOME : `PfHm`
# Desktop : `PfDe`
# Documents : `PfDo`
# All My Files : `PfAF`
# Other… : `PfLo`
defaults write com.apple.finder "NewWindowTarget" -string "PfHm"

# Keep folders on top when sorting by name (default value is "false")
defaults write com.apple.finder "_FXSortFoldersFirst" -bool "true"

# Set the default search scope when performing a search (default value is "SCev")
defaults write com.apple.finder "FXDefaultSearchScope" -string "SCcf"

# Remove items in the bin after 30 days (default value is "false")
defaults write com.apple.finder "FXRemoveOldTrashItems" -bool "true"

# Choose whether to display a warning when changing a file extension (default value is "true")
defaults write com.apple.finder "FXEnableExtensionChangeWarning" -bool "false"

# Choose whether the default file save location is on disk or iCloud (default value is "true")
defaults write NSGlobalDomain "NSDocumentSaveNewDocumentsToCloud" -bool "false"

# Choose the delay of the auto-hidden document-proxy icon (default value is "0.5")
defaults write NSGlobalDomain "NSToolbarTitleViewRolloverDelay" -float "0"

# Choose the size of Finder sidebar icons (default value is "2")
defaults write NSGlobalDomain "NSTableViewDefaultSizeMode" -int "1"

###############################################################################
# Desktop                     https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Keep folders on top when sorting (default value is "false")
defaults write com.apple.finder "_FXSortFoldersFirstOnDesktop" -bool "true"

# Hide all icons on desktop (default value is "true")
defaults write com.apple.finder "CreateDesktop" -bool "true"

# Disable "Click wallpaper to reveal desktop" outside Stage Manager (Sonoma+).
# false = "Only in Stage Manager" in System Settings → Desktop & Dock; default is true ("Always").
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

# Show hard disks on desktop (default value is "false")
defaults write com.apple.finder "ShowHardDrivesOnDesktop" -bool "false"

# Show external disks on desktop (default value is "true")
defaults write com.apple.finder "ShowExternalHardDrivesOnDesktop" -bool "true"

# Show removable media on desktop (default value is "true")
defaults write com.apple.finder "ShowRemovableMediaOnDesktop" -bool "true"

# Show connected servers on desktop (default value is "false")
defaults write com.apple.finder "ShowMountedServersOnDesktop" -bool "false"

# Show item info near icons on the desktop and in other icon views
plist_set ":DesktopViewSettings:IconViewSettings:showItemInfo" "bool" "true" "$FINDER_PLIST"
plist_set ":FK_StandardViewSettings:IconViewSettings:showItemInfo" "bool" "true" "$FINDER_PLIST"
plist_set ":StandardViewSettings:IconViewSettings:showItemInfo" "bool" "true" "$FINDER_PLIST"

# Show item info to the right of the icons on the desktop
plist_set ":DesktopViewSettings:IconViewSettings:labelOnBottom" "bool" "false" "$FINDER_PLIST"

# Enable snap-to-grid for icons on the desktop and in other icon views
plist_set ":DesktopViewSettings:IconViewSettings:arrangeBy" "string" "grid" "$FINDER_PLIST"
plist_set ":FK_StandardViewSettings:IconViewSettings:arrangeBy" "string" "grid" "$FINDER_PLIST"
plist_set ":StandardViewSettings:IconViewSettings:arrangeBy" "string" "grid" "$FINDER_PLIST"

# Increase grid spacing for icons on the desktop and in other icon views
plist_set ":DesktopViewSettings:IconViewSettings:gridSpacing" "integer" "66" "$FINDER_PLIST"
plist_set ":FK_StandardViewSettings:IconViewSettings:gridSpacing" "integer" "66" "$FINDER_PLIST"
plist_set ":StandardViewSettings:IconViewSettings:gridSpacing" "integer" "66" "$FINDER_PLIST"

# Increase the size of icons on the desktop and in other icon views
plist_set ":DesktopViewSettings:IconViewSettings:iconSize" "integer" "35" "$FINDER_PLIST"
plist_set ":FK_StandardViewSettings:IconViewSettings:iconSize" "integer" "35" "$FINDER_PLIST"
plist_set ":StandardViewSettings:IconViewSettings:iconSize" "integer" "35" "$FINDER_PLIST"

# set the minimum number of entries for the “Services” Context menu
defaults write -g NSServicesMinimumItemCountForContextSubmenu -int 10

# Services menu — disable "New Terminal at Folder" (prefer the Tab variant).
# Absent key = default. Apply via `pbs -flush` or logout.
# Discover keys: `defaults read pbs NSServicesStatus`.
defaults write pbs NSServicesStatus -dict-add "com.apple.Terminal - New Terminal at Folder - newTerminalAtFolder" \
    '{ "enabled_context_menu" = 0; "enabled_services_menu" = 0; "presentation_modes" = { ContextMenu = 0; ServicesMenu = 0; }; }'
if [[ "$MODE" == dry-run ]]; then
    echo "  would run: /System/Library/CoreServices/pbs -flush"
else
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
fi

###############################################################################
# Mission Control             https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Choose whether to rearrange Spaces automatically (default value is "true")
defaults write com.apple.dock "mru-spaces" -bool "false"

# Speed up Mission Control animations
defaults write com.apple.dock "expose-animation-duration" -float "0.1"

###############################################################################
# Mouse, Keyboard, Trackpad   https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Enable full keyboard access for all controls
# (e.g. enable Tab in modal dialogs)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Set mouse tracking speed to reasonably fast
defaults write NSGlobalDomain com.apple.mouse.scaling -float 2

# Set a ~blazingly~ normally fast keyboard repeat rate
defaults write -g InitialKeyRepeat -int 15 # normal minimum is 15 (225 ms)
defaults write -g KeyRepeat -int 2 # normal minimum is 2 (30 ms)

# Disable press-and-hold for keys in favor of key repeat (default value is "true")
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool "false"

# Trackpad: enable tap to click for this user and for the login screen
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "Clicking" -bool "true"
defaults write com.apple.AppleMultitouchTrackpad "Clicking" -bool "true"
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Trackpad: map bottom right corner to right-click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "TrackpadCornerSecondaryClick" -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "TrackpadRightClick" -bool "true"
defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool "true"

# Trackpad: enable three-finger drag (default value is "false"). Written to both
# the built-in/USB (AppleMultitouchTrackpad) and Magic Trackpad
# (driver.AppleBluetoothMultitouch.trackpad) domains — they don't share this key.
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool "true"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool "true"

# Magic Mouse: enable right-click (default is single-button "OneButton") and
# the two-finger swipe/double-tap gestures.
defaults write com.apple.AppleMultitouchMouse MouseButtonMode -string "TwoButton"
defaults write com.apple.AppleMultitouchMouse MouseTwoFingerHorizSwipeGesture -int 2
defaults write com.apple.AppleMultitouchMouse MouseTwoFingerDoubleTapGesture -int 3

###############################################################################
# Panels                      https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Expand save panel by default
defaults write NSGlobalDomain "NSNavPanelExpandedStateForSaveMode" -bool "true"
defaults write NSGlobalDomain "NSNavPanelExpandedStateForSaveMode2" -bool "true"

# Expand print panel by default
defaults write NSGlobalDomain "NSNavPanelExpandedStateForPrintMode" -bool "true"
defaults write NSGlobalDomain "NSNavPanelExpandedStateForPrintMode2" -bool "true"

# Expand the following File Info panes: “General”, “Open with”, and “Sharing & Permissions”
defaults write com.apple.finder FXInfoPanesExpanded -dict \
	General -bool true \
	OpenWith -bool true \
	Privileges -bool true

# Always open new documents in tabs
defaults write NSGlobalDomain "AppleWindowTabbingMode" -string "always"

# Use plain text mode for new TextEdit documents
defaults write com.apple.TextEdit RichText -int 0
# Open and save files as UTF-8 in TextEdit
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

###############################################################################
# Hot Corners                                                                  #
###############################################################################
# Values: 0=no-op, 2=Mission Control, 3=App Windows, 4=Desktop,
#         5=Screen Saver, 6=Disable Screen Saver, 10=Put Display to Sleep,
#         11=Launchpad, 12=Notification Center, 13=Lock Screen, 14=Quick Note

# Bottom-left → Desktop
defaults write com.apple.dock wvous-bl-corner -int 4
defaults write com.apple.dock wvous-bl-modifier -int 0

###############################################################################
# DS_Store                                                                     #
###############################################################################

# Prevent .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Prevent .DS_Store files on USB volumes
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Enable spring loading for directories and remove the delay
defaults write NSGlobalDomain com.apple.springing.enabled -bool true
defaults write NSGlobalDomain com.apple.springing.delay -float 0

###############################################################################
# Safari                      https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Privacy: don't send search queries to Apple
write_safari_default UniversalSearchEnabled -bool false
write_safari_default SuppressSearchSuggestions -bool true

# Enable the Develop menu and the Web Inspector in Safari
write_safari_default IncludeDevelopMenu -bool "true"
write_safari_default WebKitDeveloperExtrasEnabledPreferenceKey -bool "true"
write_safari_default com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool "true"
write_safari_default ShowFullURLInSmartSearchField -bool "true"

# Safer downloads and form handling
write_safari_default AutoOpenSafeDownloads -bool false
write_safari_default AutoFillFromAddressBook -bool false
write_safari_default AutoFillPasswords -bool false
write_safari_default AutoFillCreditCardData -bool false
write_safari_default AutoFillMiscellaneousForms -bool false
write_safari_default WarnAboutFraudulentWebsites -bool true
write_safari_default InstallExtensionUpdatesAutomatically -bool true

###############################################################################
# Chrome / Chrome Canary                                                       #
###############################################################################

# Disable oversensitive back-swipe navigation and use the native print dialog
defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false
defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
defaults write com.google.Chrome.canary AppleEnableMouseSwipeNavigateWithScrolls -bool false
defaults write com.google.Chrome DisablePrintPreview -bool true
defaults write com.google.Chrome.canary DisablePrintPreview -bool true
defaults write com.google.Chrome PMPrintingExpandedStateForPrint2 -bool true
defaults write com.google.Chrome.canary PMPrintingExpandedStateForPrint2 -bool true

###############################################################################
# Microsoft Edge                                                              #
###############################################################################

# Use the native macOS print dialog and expand it by default.
# Installed Edge domain verified on this Mac: com.microsoft.edgemac.
defaults write com.microsoft.edgemac DisablePrintPreview -bool true
defaults write com.microsoft.edgemac PMPrintingExpandedStateForPrint2 -bool true

###############################################################################
# Time Machine                https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# Prevent Time Machine from prompting to use newly connected storage as backup volumes (default value is "false")
defaults write com.apple.TimeMachine "DoNotOfferNewDisksForBackup" -bool "true"

##############################################################################
# Security                                                                   #
##############################################################################
# Also see: https://github.com/drduh/macOS-Security-and-Privacy-Guide
# https://www.cisecurity.org/benchmark/apple_os

# Enable Firewall. Possible values: 0 = off, 1 = on for specific services,
# 2 = on for essential services.
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Disable guest account login
# shellcheck disable=SC2033
warn_on_fail "could not disable guest account login (sudo/defaults permission issue)" \
    sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

# Require password immediately after sleep or screen saver
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Disable AirDrop for file transfers (reduce attack surface)
# defaults write com.apple.NetworkBrowser DisableAirDrop -bool true

# Disable remote Apple events. `systemsetup` may return non-zero when the
# setting is already off, so treat that state as success instead of aborting
# the rest of the macOS defaults run.
if ! remote_events_output="$(sudo systemsetup -setremoteappleevents off 2>&1)"; then
    case "$remote_events_output" in
        *"already off"*) printf '  ✓ remote Apple events already off\n' ;;
        *) printf '  ⚠ could not disable remote Apple events: %s\n' "$remote_events_output" >&2 ;;
    esac
fi
unset remote_events_output

# Reveal IP address, hostname, OS version on login window click
# shellcheck disable=SC2033
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName

###############################################################################
# Set custom lock message                                                     #
###############################################################################

# shellcheck disable=SC2033
sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "$LoginMsg"

###############################################################################
# Misc UX                                                                      #
###############################################################################

# Show ~/Library folder
chflags nohidden ~/Library

# Show /Volumes folder
# shellcheck disable=SC2033
sudo chflags nohidden /Volumes

# Faster window resize animations
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# Auto-quit printer app when jobs complete
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Disable auto-termination of inactive apps
defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true

# Increase Bluetooth audio quality
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

###############################################################################
# Energy                                                                       #
###############################################################################

# Disable machine sleep while charging
sudo pmset -c sleep 0

# Set display sleep to 15 min on battery
sudo pmset -b displaysleep 15

# Set display sleep to 30 min when charging
sudo pmset -c displaysleep 30

# Disable sudden motion sensor (irrelevant on SSDs, but harmless)
sudo pmset -a sms 0

###############################################################################
# Mac App Store                                                               #
###############################################################################

# Enable the WebKit Developer Tools in the Mac App Store
# defaults write com.apple.appstore WebKitDeveloperExtras -bool true

# Enable Debug Menu in the Mac App Store
# defaults write com.apple.appstore ShowDebugMenu -bool true

# Enable the automatic update check
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

# Download newly available updates in background
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1

# Install System data files & security updates
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1

# Automatically download apps purchased on other Macs
# defaults write com.apple.SoftwareUpdate ConfigDataInstall -int 1

# Turn on app auto-update
defaults write com.apple.commerce AutoUpdate -bool true

# Allow the App Store to reboot machine on macOS updates
defaults write com.apple.commerce AutoUpdateRestartRequired -bool true

###############################################################################
# Activity Monitor            https://macos-defaults.com/#💻-list-of-commands #
###############################################################################

# How frequently Activity Monitor should update its data, in seconds (default value is "5")
defaults write com.apple.ActivityMonitor "UpdatePeriod" -int "1"

# Choose what information should be shown in the app's Dock icon, if any (default value is "0")
defaults write com.apple.ActivityMonitor "IconType" -int "6"

# Show all processes and sort by CPU usage
defaults write com.apple.ActivityMonitor "ShowCategory" -int "0"
defaults write com.apple.ActivityMonitor "SortColumn" -string "CPUUsage"
defaults write com.apple.ActivityMonitor "SortDirection" -int "0"

###############################################################################
# Photos / Image Capture                                                       #
###############################################################################

# Prevent Photos from opening automatically when devices are plugged in
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

###############################################################################
# Menu Bar — Clock                                                            #
###############################################################################

# Analog clock face with date + day of week (default is digital, date hidden).
defaults write com.apple.menuextra.clock IsAnalog -bool "true"
defaults write com.apple.menuextra.clock ShowDate -int 1
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool "true"
defaults write com.apple.menuextra.clock ShowAMPM -bool "true"

###############################################################################
# Accessibility — Zoom                                                        #
###############################################################################

# Enable scroll-gesture zoom with a modifier key (default value is "false").
# closeViewScrollWheelModifiersInt 262144 = Control.
warn_on_fail "could not set Accessibility zoom toggle (Full Disk Access/Accessibility may be required)" \
    defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool "true"
warn_on_fail "could not set Accessibility zoom modifier (Full Disk Access/Accessibility may be required)" \
    defaults write com.apple.universalaccess closeViewScrollWheelModifiersInt -int 262144
warn_on_fail "could not set Accessibility zoom hotkeys (Full Disk Access/Accessibility may be required)" \
    defaults write com.apple.universalaccess closeViewHotkeysEnabled -bool "true"

###############################################################################
# Kill affected applications                                                  #
###############################################################################

for app in "Activity Monitor" \
	"Dock" \
	"Screenshot" \
	"SystemUIServer" \
	"ControlCenter" \
	"Finder" \
	"WindowManager" \
	"TextEdit"; do
	killall "${app}" &> /dev/null || true
done

if [[ "$MODE" == dry-run ]]; then
    echo "macOS dry-run complete. No settings were changed."
    exit 0
fi

verify_defaults || {
    echo "macOS configuration applied, but read-back verification failed." >&2
    exit 1
}

echo "macOS Configuration Applied and verified."
echo "Note that - "
echo "           some of these changes require a logout/restart to take effect."
echo "	         the Mouse and Trackpad Gestures still need to be set via System Settings"
echo "	         the Highlight color and the Displays need to be set manually!"
