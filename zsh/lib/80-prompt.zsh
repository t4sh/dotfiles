# Terminal theme + prompt — loaded late so starship's precmd runs after all other hooks.

# Monokai Pro colors / keybindings
[[ -f ~/.z-monokai ]] && source ~/.z-monokai

# Starship — https://starship.rs/guide/#%F0%9F%9A%80-installation
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"

  # Remove Monokai's precmd hook — `color2` is undefined in lprompt and breaks the prompt.
  # Starship owns the prompt; Monokai aliases/colors/keybindings still load fine.
  precmd_functions=(${precmd_functions:#_monokai_precmd})
fi
