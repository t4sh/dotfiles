# zoxide — frecency-based directory jumping.
#
# zoxide recommends initializing at the end of shell config so its `cd`
# wrapper and completion hooks are not overwritten by later prompt/plugin code.
# This file loads after 80-prompt.zsh and before the gitignored 99-local.zsh.
if command -v zoxide >/dev/null 2>&1; then
  # Load order is correct (this file is last); the doctor still fires in
  # non-interactive / wrapped shells (CI, tool harnesses) that source extra
  # setup after rc. Order is verified, so silence the dev-time nag globally.
  export _ZO_DOCTOR=0
  eval "$(zoxide init zsh --cmd cd)"
fi
