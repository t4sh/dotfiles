# Generic aliases

alias ls-recent='command ls -lahtGFp'
# Heavy cleanup below the current physical directory; no depth limit or symlink following.
# Preserve home metadata and every Applications tree. No backup is made.
alias ds-clean='find "$(pwd -P)" \( -type d -iname applications -prune \) -o \( -type f -name .DS_Store ! -path "${HOME:A}/.DS_Store" ! -ipath "*/applications/*" -exec rm -f {} + \)'
alias mkdir='mkdir -p'
alias path='print -l ${(s.:.)PATH}'

# Easier parent navigation.
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Modern CLI replacements. Keep the original commands available by calling them
# with `command <name>` or their absolute paths.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias l='eza -lah --group-directories-first --icons=auto'
  alias ll='eza -lh --git --group-directories-first --icons=auto'
  alias la='eza -lah --git --group-directories-first --icons=auto'
  alias tree='eza --tree --group-directories-first --icons=auto'
fi

if command -v bat >/dev/null 2>&1; then
  alias bcat='bat'
  alias view='bat --paging=always'
fi

if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

# Compatibility names; implementations above use the canonical names.
alias lis='ls-recent'
alias dstClean='ds-clean'
