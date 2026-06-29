# zsh options + history

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt AUTO_CD
unsetopt CORRECT
HISTSIZE=50000
SAVEHIST=50000

# Never record secret-setting commands in history (in-memory OR on-disk).
# Extended-glob pattern matched against the full command line; edit to add forms.
HISTORY_IGNORE='(gh secret set*|gh auth login*|echo *TOKEN*|echo *SECRET*|echo *PAT*|export *TOKEN*=*|export *SECRET*=*|export *KEY*=*|export *PAT*=*|*TOKEN*=*|*SECRET*=*|*KEY*=*)'
zshaddhistory() {
  emulate -L zsh
  [[ ${1%%$'\n'} != ${~HISTORY_IGNORE} ]]
}
