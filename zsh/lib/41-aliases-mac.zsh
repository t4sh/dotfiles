# Mac-specific aliases — dock, brew, cleanup
# Heavy pipelines live in ~/.dotfiles/scripts/ so they are shellcheck-able and grep-friendly.

alias cleanMac='bash ~/.dotfiles/scripts/clean-mac.sh --dry-run'
alias cleanMacNow='sudo bash ~/.dotfiles/scripts/clean-mac.sh --yes'

# Homebrew update + cleanup
alias reBrew='echo "Update, Cleanup and Doctoring the HomeBrew"; brew outdated; brew update; brew upgrade; brew upgrade --cask $(brew list --cask); brew cleanup; brew autoremove; brew doctor'
alias upBrew='echo "Upgrade Casks";brew update && brew upgrade && brew upgrade --cask $(brew list --cask) --greedy-auto-updates'

# Dock lock / unlock
alias lkDock="defaults write com.apple.dock contents-immutable -bool true;defaults write com.apple.Dock size-immutable -bool yes;defaults write com.apple.Dock position-immutable -bool yes;killall Dock"
alias ulkDock="defaults write com.apple.dock contents-immutable -bool false;defaults write com.apple.Dock size-immutable -bool no;defaults write com.apple.Dock position-immutable -bool no;killall Dock"

# Dock spacers
alias aDckspace="defaults write com.apple.dock persistent-apps -array-add '{tile-type=\"spacer-tile\";}';killall Dock"
alias aDckspaceSmall="defaults write com.apple.dock persistent-apps -array-add '{tile-type=\"small-spacer-tile\";}';killall Dock"
alias aDckspaceRight="defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type=\"spacer-tile\";}' ;killall Dock"
alias aDckspaceRightSmall="defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type=\"small-spacer-tile\";}';killall Dock"

# colima — lighter alternative to Docker Desktop. `colima start` without
# --runtime can land with the RUNTIME column empty in `colima list` (no
# docker daemon inside the VM), so always pass it explicitly.
alias colimaUp='colima start --cpu 2 --memory 2 --runtime docker'
alias colimaDown='colima stop'
alias colimaStatus='colima list'

