# Mac-specific aliases — dock, brew, cleanup
# Heavy pipelines live in ~/.dotfiles/scripts/ so they are shellcheck-able and grep-friendly.

alias logs-check='bash ~/.dotfiles/scripts/clean-mac.sh --dry-run'
alias logs-clean='bash ~/.dotfiles/scripts/clean-mac.sh --yes'

# Finder: Columns / Date Modified groups / Name within groups, previews and hidden items.
# Daily metadata scope: FileVault and linked directories, one child level deep.
# Home and existing Applications folders use alphabetical List; grouping stays manual.
# Supports --dry-run and --depth.
alias view-reset='python3 "$HOME/.dotfiles/scripts/apply-finder-views.py"'

# Upgrade packages; re-brew adds explicit cleanup and diagnostics.
alias up-brew='brew update && brew upgrade --greedy-auto-updates'
alias re-brew='up-brew && brew cleanup && brew autoremove && brew doctor'

# Dock lock / unlock
alias dock-lock="defaults write com.apple.dock contents-immutable -bool true;defaults write com.apple.Dock size-immutable -bool yes;defaults write com.apple.Dock position-immutable -bool yes;killall Dock"
alias dock-unlock="defaults write com.apple.dock contents-immutable -bool false;defaults write com.apple.Dock size-immutable -bool no;defaults write com.apple.Dock position-immutable -bool no;killall Dock"

# Dock spacers
alias dock-gap="defaults write com.apple.dock persistent-apps -array-add '{tile-type=\"spacer-tile\";}';killall Dock"
alias dock-gap-small="defaults write com.apple.dock persistent-apps -array-add '{tile-type=\"small-spacer-tile\";}';killall Dock"
alias dock-gap-files="defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type=\"spacer-tile\";}' ;killall Dock"
alias dock-gap-files-small="defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type=\"small-spacer-tile\";}';killall Dock"

# colima — lighter alternative to Docker Desktop. `colima start` without
# --runtime can land with the RUNTIME column empty in `colima list` (no
# docker daemon inside the VM), so always pass it explicitly.
alias colima-up='colima start --cpu 2 --memory 2 --runtime docker'
alias colima-down='colima stop'
alias colima-status='colima list'

# Compatibility names; implementations above use the canonical names.
alias cleanMac='logs-check'
alias cleanMacNow='logs-clean'
alias applyColumnDateView='view-reset'
alias upBrew='up-brew'
alias reBrew='re-brew'
alias lkDock='dock-lock'
alias ulkDock='dock-unlock'
alias aDckspace='dock-gap'
alias aDckspaceSmall='dock-gap-small'
alias aDckspaceRight='dock-gap-files'
alias aDckspaceRightSmall='dock-gap-files-small'
alias colimaUp='colima-up'
alias colimaDown='colima-down'
alias colimaStatus='colima-status'
