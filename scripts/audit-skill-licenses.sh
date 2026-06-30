#!/usr/bin/env bash
# Audit agents/skills/* licenses and gate non-redistributable ones out of
# the eventual public dotfiles fork.
#
# Criterion is the REDISTRIBUTION GRANT, not authorship:
#   permissible  Apache / MIT / BSD / ISC / MPL / Unlicense / CC-BY (LICENSE file
#                or SKILL.md frontmatter)
#   restricted   "all rights reserved" / proprietary / no-redistribution
#   first-party  source local or t4sh/skills4sh → kept public
#   attributed   third-party, listed in THIRD_PARTY_NOTICES.md → kept public
#   review       missing license evidence and not attributed → block --check
#
# Restricted skills are written into a delimited auto-block in .gitignore.
# The hand-curated entries above that block (org ops skills, brand/trademark,
# deprecated upstreams) are infra/curation calls — NOT license-detectable —
# and are never touched here. A skill already listed manually is skipped
# (reported as "covered manually"), so no duplicate patterns are emitted.
#
# Idempotent. Re-run any time a skill is added or its license changes.
#
#   scripts/audit-skill-licenses.sh            apply (rewrites the auto-block)
#   scripts/audit-skill-licenses.sh --dry-run  report only, no write
#   dot audit-skill-licenses                    same, via the dispatcher
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
SKILLS_DIR="$DOTFILES/agents/skills"
LOCK_FILE="$DOTFILES/agents/.skill-lock.json"
NOTICES="$DOTFILES/THIRD_PARTY_NOTICES.md"
GITIGNORE="$DOTFILES/.gitignore"
BEGIN="# >>> auto: license-restricted skills (managed by scripts/audit-skill-licenses.sh) >>>"
END="# <<< auto: license-restricted skills <<<"

DRY_RUN=0
CHECK=0
case "${1:-}" in
  -n|--dry-run) DRY_RUN=1 ;;
  -c|--check)   CHECK=1; DRY_RUN=1 ;;  # report only, exit non-zero if action needed
esac

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# In --check (hook / CI / pre-bootstrap) a missing skills tree or gitignore
# means "cannot audit yet", not "fail the commit". Skip cleanly.
if [[ ! -d "$SKILLS_DIR" || ! -f "$GITIGNORE" ]]; then
  if [[ $CHECK -eq 1 ]]; then
    warn "skills dir or .gitignore absent — license gate skipped (not bootstrapped)"
    exit 0
  fi
  [[ -d "$SKILLS_DIR" ]] || die "skills dir not found: $SKILLS_DIR"
  [[ -f "$GITIGNORE"  ]] || die "gitignore not found: $GITIGNORE"
fi

# Classify one license file's text. Echoes: permissible|restricted|review
classify() {
  local text; text="$(tr 'A-Z' 'a-z' < "$1" | tr -s '[:space:]' ' ')"
  case "$text" in
    *"all rights reserved"*)
      # Permissive licenses never carry this phrase; proprietary ones do.
      echo restricted; return ;;
  esac
  case "$text" in
    *"apache license"*|*"mit license"*|*"permission is hereby granted, free of charge"*) echo permissible; return ;;
    *"bsd "*|*"redistribution and use in source and binary"*)                            echo permissible; return ;;
    *"isc license"*|*"mozilla public license"*|*"this is free and unencumbered software"*) echo permissible; return ;;
    *"creative commons attribution"*)
      case "$text" in
        *noncommercial*|*"non-commercial"*) echo review;      return ;;
        *)                                   echo permissible; return ;;
      esac ;;
    *"proprietary"*|*"no redistribution"*|*"internal use only"*|*"not be redistributed"*) echo restricted; return ;;
  esac
  echo review
}

# Classify license text from a LICENSE file or SKILL.md frontmatter line.
classify_text() {
  local text="$1"
  text="$(printf '%s' "$text" | tr 'A-Z' 'a-z' | tr -s '[:space:]' ' ')"
  case "$text" in
    mit|apache-2.0|apache-2|bsd|bsd-2-clause|bsd-3-clause|isc|unlicense) echo permissible; return ;;
    *"all rights reserved"*) echo restricted; return ;;
  esac
  case "$text" in
    *"apache license"*|*"mit license"*|*"permission is hereby granted, free of charge"*) echo permissible; return ;;
    *"bsd "*|*"redistribution and use in source and binary"*) echo permissible; return ;;
    *"isc license"*|*"mozilla public license"*|*"this is free and unencumbered software"*) echo permissible; return ;;
    *"creative commons attribution"*)
      case "$text" in
        *noncommercial*|*"non-commercial"*) echo review; return ;;
        *) echo permissible; return ;;
      esac ;;
    *"proprietary"*|*"no redistribution"*|*"internal use only"*|*"not be redistributed"*) echo restricted; return ;;
  esac
  echo review
}

skill_lock_source() {
  local name="$1"
  [[ -f "$LOCK_FILE" ]] || return 1
  local source
  source="$(jq -r --arg n "$name" '.skills[$n].source // empty' "$LOCK_FILE")"
  if [[ -n "$source" ]]; then
    printf '%s' "$source"
    return 0
  fi
  source="$(jq -r --arg n "$name" '
    .skills | to_entries[] |
    select(.value.skillPath | test("/" + $n + "/"; "i")) |
    .value.source
  ' "$LOCK_FILE" | head -1)"
  [[ -n "$source" ]] && printf '%s' "$source"
}

is_first_party_source() {
  case "$1" in
    local|t4sh/skills4sh) return 0 ;;
    *) return 1 ;;
  esac
}

skill_frontmatter_license() {
  local skill_md="$1/SKILL.md"
  [[ -f "$skill_md" ]] || return 1
  awk '/^---$/{ if (++n == 2) exit; next }
       n == 1 && /^license:/ {
         sub(/^license:[[:space:]]*/, "")
         print
         exit
       }' "$skill_md"
}

listed_in_notices() {
  local name="$1"
  [[ -f "$NOTICES" ]] || return 1
  grep -Fq "| \`$name\` |" "$NOTICES"
}

# Is "agents/skills/<name>/" already present anywhere in .gitignore
# (hand-curated entry or a prior auto-block write)?
listed_in_gitignore() {
  grep -qxF "agents/skills/$1/" "$GITIGNORE"
}

declare -a RESTRICTED=() REVIEW=() MANUAL=()
permissible_n=0 firstparty_n=0 attributed_n=0

for dir in "$SKILLS_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  lic="$(find "$dir" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \) 2>/dev/null | head -1)"

  if [[ -n "$lic" ]]; then
    case "$(classify "$lic")" in
      permissible) permissible_n=$((permissible_n + 1)) ;;
      review)      REVIEW+=("$name") ;;
      restricted)
        if listed_in_gitignore "$name"; then MANUAL+=("$name")
        else RESTRICTED+=("$name"); fi ;;
    esac
    continue
  fi

  source="$(skill_lock_source "$name" || true)"
  if is_first_party_source "$source"; then
    firstparty_n=$((firstparty_n + 1))
    continue
  fi

  fm_license="$(skill_frontmatter_license "$dir" || true)"
  fm_review=0
  if [[ -n "$fm_license" ]]; then
    case "$(classify_text "$fm_license")" in
      permissible) permissible_n=$((permissible_n + 1)); continue ;;
      review)      fm_review=1 ;;
      restricted)
        if listed_in_gitignore "$name"; then MANUAL+=("$name")
        else RESTRICTED+=("$name"); fi
        continue ;;
    esac
  fi

  if listed_in_notices "$name"; then
    attributed_n=$((attributed_n + 1))
    continue
  fi

  if (( fm_review )); then
    REVIEW+=("$name")
    continue
  fi

  REVIEW+=("$name")
done

info "skill license audit ($(ls -d "$SKILLS_DIR"/*/ | wc -l | tr -d ' ') skills)"
ok   "permissible (kept public): $permissible_n"
ok   "first-party (kept public): $firstparty_n"
ok   "attributed in THIRD_PARTY_NOTICES.md: $attributed_n"
[[ ${#MANUAL[@]}  -gt 0 ]] && for s in "${MANUAL[@]}";  do warn "restricted but already gitignored: $s"; done
[[ ${#REVIEW[@]}  -gt 0 ]] && for s in "${REVIEW[@]}";  do warn "REVIEW (missing license/attribution): $s"; done

if [[ ${#RESTRICTED[@]} -eq 0 ]]; then
  ok "no new license-restricted skills to gate"
else
  warn "license-restricted → public-split exclusion: ${RESTRICTED[*]}"
fi

# --check: pass/fail gate for hooks, make all, idempotency. A restrictive
# license not yet in .gitignore = it would be committed → block.
if [[ $CHECK -eq 1 ]]; then
  if [[ ${#RESTRICTED[@]} -gt 0 ]]; then
    die "license gate: ${#RESTRICTED[@]} restricted skill(s) not gitignored — run: dot audit-skill-licenses"
  fi
  if [[ ${#REVIEW[@]} -gt 0 ]]; then
    die "license gate: ${#REVIEW[@]} skill(s) need LICENSE, attribution, or THIRD_PARTY_NOTICES entry — ${REVIEW[*]}"
  fi
  ok "license gate: clean"
  exit 0
fi

# Current auto-block (if any) for idempotency check.
current_block="$(awk -v b="$BEGIN" -v e="$END" '
  $0==b {c=1} c {print} $0==e {c=0}' "$GITIGNORE")"

strip_auto_block() {
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip' "$GITIGNORE"
}

# Nothing to auto-gate → drop a stale auto-block, or leave .gitignore alone.
if [[ ${#RESTRICTED[@]} -eq 0 ]]; then
  if [[ -z "$current_block" ]]; then
    ok "nothing to write — .gitignore left untouched"
    exit 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    info "--dry-run: would remove the .gitignore auto-block"
    exit 0
  fi
  tmp="$(mktemp)"
  strip_auto_block > "$tmp"
  mv "$tmp" "$GITIGNORE"
  ok "removed empty auto-block from $GITIGNORE"
  exit 0
fi

# Build the desired auto-block body (sorted, stable).
block_body=""
while IFS= read -r s; do block_body+="agents/skills/$s/"$'\n'; done \
  < <(printf '%s\n' "${RESTRICTED[@]}" | sort -u)

new_block="$BEGIN"$'\n'"$block_body""$END"

if [[ "$current_block" == "$new_block" ]]; then
  ok "gitignore auto-block already current — no change"
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  info "--dry-run: would update the .gitignore auto-block to:"
  printf '%s\n' "$new_block" | sed 's/^/    /'
  exit 0
fi

tmp="$(mktemp)"
repl="$(mktemp)"
printf '%s\n' "$new_block" > "$repl"
if grep -qxF "$BEGIN" "$GITIGNORE"; then
  awk -v b="$BEGIN" -v e="$END" -v repl="$repl" '
    $0==b {
      while ((getline line < repl) > 0) print line
      close(repl)
      skip=1
      next
    }
    $0==e {skip=0; next}
    !skip' "$GITIGNORE" > "$tmp"
else
  cp "$GITIGNORE" "$tmp"
  [[ -n "$(tail -c1 "$tmp")" ]] && printf '\n' >> "$tmp"
  printf '\n%s\n' "$new_block" >> "$tmp"
fi
rm -f "$repl"
mv "$tmp" "$GITIGNORE"
ok "updated $GITIGNORE auto-block (${#RESTRICTED[@]} entr$([[ ${#RESTRICTED[@]} -eq 1 ]] && echo y || echo ies))"
info "review the diff before committing: git diff -- .gitignore"
