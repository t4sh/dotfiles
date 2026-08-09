#!/usr/bin/env bash
# Audit agents/skills/* licenses and gate non-redistributable ones out of
# the eventual public dotfiles fork.
#
# Criterion is the REDISTRIBUTION GRANT, not authorship:
#   permissible  Apache / MIT / BSD / ISC / MPL / GPL / AGPL / Unlicense / CC-BY
#   restricted   "all rights reserved" / proprietary / no-redistribution
#   reviewed     remote source has explicit source-level metadata in
#                agents/skills/source-licenses.tsv because installed skill dirs
#                often omit the upstream repo LICENSE file
#   first-party  no license file + local/no lock source → assumed yours
#   review       unclear or remote no-license source not reviewed
#
# Restricted skills are written into a delimited auto-block in .gitignore.
# Hand-curated entries elsewhere in .gitignore are never touched.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
SKILLS_DIR="$DOTFILES/agents/skills"
LOCK_FILE="$DOTFILES/agents/.skill-lock.json"
SOURCE_LICENSES="$DOTFILES/agents/skills/source-licenses.tsv"
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

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
META_TSV="$TMPDIR/skill-meta.tsv"

# Lock key/frontmatter display names may contain spaces and punctuation while
# installed skill directories use slugs. Keep this slug logic aligned with
# scripts/gen-skillsfile.py.
if [[ -f "$LOCK_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$LOCK_FILE" > "$META_TSV" <<'PY'
import json, re, sys

def slugify(value):
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")

with open(sys.argv[1]) as f:
    data = json.load(f)
for key, meta in data.get("skills", {}).items():
    print("\t".join([
        slugify(key),
        meta.get("sourceType", ""),
        meta.get("source", ""),
    ]))
PY
else
  : > "$META_TSV"
fi

meta_for() {
  awk -F '\t' -v n="$1" '$1 == n {print; exit}' "$META_TSV"
}

source_license_for() {
  local source="$1"
  [[ -n "$source" && -f "$SOURCE_LICENSES" ]] || return 1
  awk -F '\t' -v s="$source" '$1 == s {print $2; found=1; exit} END {exit found ? 0 : 1}' "$SOURCE_LICENSES"
}

# Classify a reviewed source-level license identifier from source-licenses.tsv.
# "reviewed" preserves grandfathered entries that predate explicit identifiers.
classify_source_license() {
  local license; license="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$license" in
    reviewed|mit|mit-0|apache|apache-2.0|bsd|bsd-2-clause|bsd-3-clause|isc|mpl|mpl-2.0|unlicense|cc-by|cc-by-*)
      echo permissible ;;
    restricted|proprietary|all-rights-reserved|no-redistribution)
      echo restricted ;;
    *)
      echo review ;;
  esac
}

# Classify one license file's text. Echoes: permissible|restricted|review
classify() {
  local text; text="$(tr '[:upper:]' '[:lower:]' < "$1" | tr -s '[:space:]' ' ')"
  case "$text" in
    *"all rights reserved"*) echo restricted; return ;;
  esac
  case "$text" in
    *"apache license"*|*"mit license"*|*"permission is hereby granted, free of charge"*) echo permissible; return ;;
    *"gnu general public license"*|*"gnu affero general public license"*)               echo permissible; return ;;
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

# Is "agents/skills/<name>/" already present anywhere in .gitignore
# (hand-curated entry or a prior auto-block write)?
listed_in_gitignore() {
  grep -qxF "agents/skills/$1/" "$GITIGNORE"
}

RESTRICTED=()
REVIEW=()
MANUAL=()
permissible_n=0
firstparty_n=0
source_reviewed_n=0

for dir in "$SKILLS_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  lic="$(/usr/bin/find "$dir" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \) 2>/dev/null | head -1)"
  meta_line="$(meta_for "$name")"
  source_type="$(printf '%s' "$meta_line" | awk -F '\t' '{print $2}')"
  source="$(printf '%s' "$meta_line" | awk -F '\t' '{print $3}')"

  if [[ -z "$lic" ]]; then
    if [[ "$source_type" == "github" ]]; then
      source_license="$(source_license_for "$source" || :)"
      case "$(classify_source_license "$source_license")" in
        permissible)
          source_reviewed_n=$((source_reviewed_n + 1)) ;;
        restricted)
          if listed_in_gitignore "$name"; then MANUAL+=("$name")
          else RESTRICTED+=("$name"); fi ;;
        review)
          if listed_in_gitignore "$name"; then MANUAL+=("$name")
          elif [[ -n "$source_license" ]]; then
            REVIEW+=("$name (unrecognized source license '$source_license': ${source:-unknown})")
          else
            REVIEW+=("$name (remote source has no reviewed license metadata: ${source:-unknown})")
          fi ;;
      esac
    else
      firstparty_n=$((firstparty_n + 1))
    fi
    continue
  fi

  case "$(classify "$lic")" in
    permissible) permissible_n=$((permissible_n + 1)) ;;
    review)
      if listed_in_gitignore "$name"; then MANUAL+=("$name")
      else REVIEW+=("$name (unclear local license)"); fi ;;
    restricted)
      if listed_in_gitignore "$name"; then MANUAL+=("$name")
      else RESTRICTED+=("$name"); fi ;;
  esac
done

skill_count="$(/usr/bin/find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
info "skill license audit ($skill_count skills)"
ok   "permissible local licenses (kept public): $permissible_n"
ok   "reviewed source-level licenses (kept public): $source_reviewed_n"
ok   "first-party / local no-license (kept public): $firstparty_n"
[[ ${#MANUAL[@]}  -gt 0 ]] && for s in "${MANUAL[@]}";  do warn "license-gated in .gitignore: $s"; done
[[ ${#REVIEW[@]}  -gt 0 ]] && for s in "${REVIEW[@]}";  do warn "REVIEW: $s"; done

if [[ ${#RESTRICTED[@]} -eq 0 ]]; then
  ok "no new license-restricted skills to gate"
else
  warn "license-restricted → public-split exclusion: ${RESTRICTED[*]}"
fi

# --check: pass/fail gate for hooks, make all, idempotency.
if [[ $CHECK -eq 1 ]]; then
  if [[ ${#RESTRICTED[@]} -gt 0 ]]; then
    die "license gate: ${#RESTRICTED[@]} restricted skill(s) not gitignored — run: dot audit-skill-licenses"
  fi
  if [[ ${#REVIEW[@]} -gt 0 ]]; then
    die "license gate: ${#REVIEW[@]} skill(s) need source-level review — update agents/skills/source-licenses.tsv or gate them"
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
    if [[ ${#REVIEW[@]} -gt 0 ]]; then
      die "review required before this audit can be clean"
    fi
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
