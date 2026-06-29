# Generic aliases

alias lis='command ls -lahtGFp'
alias dstClean="find . -name '.DS_Store' -delete"

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
