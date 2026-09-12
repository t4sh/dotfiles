# Git / GitHub / dotfiles aliases + gh CLI helpers.
# Each gh function uses existing `gh auth` credentials — no PATs, no env vars.

# --- dotfiles management ---
alias dot-link='bash ~/.dotfiles/scripts/link.sh'
dot-backup() {
  cd ~/.dotfiles || return
  # Surface Brewfile drift before `make backup` silently absorbs it into the dump.
  bash scripts/audit-brewfile.sh || true
  # Resync Skillsfile only if .skill-lock.json drifted (--check avoids the
  # timestamp churn a blind regen would add to every backup commit).
  python3 scripts/gen-skillsfile.py --check >/dev/null 2>&1 || make skills-manifest
  make backup || return
  local -a backup_paths=(
    Brewfile Skillsfile THIRD_PARTY_NOTICES.md
    apps services agents/skills/README.md
    macos/dock-backup.plist macos/hitoolbox.plist macos/symbolichotkeys.plist
  )
  echo "Backup changes proposed:"
  git status --short -- "${backup_paths[@]}"
  git diff --stat -- "${backup_paths[@]}"
  read -q "REPLY?Stage only these managed backup paths and commit? (y/n) " || { echo; return 1; }
  echo
  git add -A -- "${backup_paths[@]}" || return
  local default="chore: backup configs on $(date '+%Y-%m-%d %H:%M')"
  local msg
  vared -p "commit message [${default}]: " -c msg
  # --only builds the commit from this pathspec while preserving any unrelated
  # entries the operator already had staged before running dot-backup.
  git commit --only -m "${msg:-$default}" -- "${backup_paths[@]}"
}


# -----------------------------------------------------------------------------
# pr-digest — cross-org open-PR triage
#
#   Usage:  pr-digest <org> [org ...]
#           pr-digest t4sh
#
#   Labels (sorted most-urgent first):
#     HELD     Balanced auto-merge workflow flagged for human review
#              (bot comment starts with "dependabot-auto-merge: held")
#     FAIL     CI failure — needs investigation
#     HUMAN    non-bot PR awaiting review/merge
#     AUTO-BH  auto-merge armed but branch BEHIND main (rebase pending)
#     AUTO     auto-merge armed, will land once CI greens
#     WAIT     bot PR not yet picked up by workflow (rare — usually timing)
#
#   Runtime: ~10–20s (enumerates active repos, then one gh pr list per repo).
#   Output:  tab-aligned table with clickable URLs in modern terminals.
# -----------------------------------------------------------------------------
pr-digest() {
  local orgs=("$@")
  local repos=()
  local org repo repo_output pr_output rows=""
  (( ${#orgs[@]} == 0 )) && { echo "usage: pr-digest <org> [org ...]" >&2; return 2; }

  for org in "${orgs[@]}"; do
    if ! repo_output="$(gh api "/orgs/$org/repos?per_page=100" --paginate \
      --jq '.[] | select(.archived==false) | .full_name')"; then
      echo "pr-digest: failed to list repositories for $org" >&2
      return 1
    fi
    [[ -n "$repo_output" ]] && repos+=("${(@f)repo_output}")
  done

  for repo in "${repos[@]}"; do
    if ! pr_output="$(gh pr list --repo "$repo" --state open --limit 1000 \
      --json number,url,title,author,autoMergeRequest,mergeStateStatus,statusCheckRollup,comments \
      --jq 'if length >= 1000 then error("pr-digest: 1000-PR limit reached; results may be incomplete") else . end | .[] |
        (if   any(.comments[]?;         .body | startswith("dependabot-auto-merge: held")) then "1|HELD"
         elif any(.statusCheckRollup[]?; .conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .conclusion == "CANCELLED" or .conclusion == "ACTION_REQUIRED" or .conclusion == "STARTUP_FAILURE" or .state == "FAILURE" or .state == "ERROR")                         then "2|FAIL"
         elif .autoMergeRequest == null and .author.login != "app/dependabot"              then "3|HUMAN"
         elif .autoMergeRequest != null and .mergeStateStatus == "BEHIND"                  then "4|AUTO-BH"
         elif .autoMergeRequest != null                                                    then "5|AUTO"
         else                                                                                   "6|WAIT"
         end) as $lbl |
        "\($lbl)\t\(.url)\t\(.title)"')"; then
      echo "pr-digest: failed to list pull requests for $repo" >&2
      return 1
    fi
    [[ -n "$pr_output" ]] && rows+="$pr_output"$'\n'
  done

  printf '%s' "$rows" | sort | awk -F'\t' '
    BEGIN {
      printf "%-8s  %-55s  %s\n", "STATUS", "PR", "TITLE"
      printf "%-8s  %-55s  %s\n", "──────", "──", "─────"
    }
    { split($1, p, "|"); printf "%-8s  %-55s  %s\n", p[2], $2, $3 }
    END {
      if (NR == 0) print "(no open PRs)"
    }'
}

# -----------------------------------------------------------------------------
# pr-merged — local branches whose current tip matches a PR merged into the default branch (squash-safe)
#
#   Usage:  pr-merged
#
#   Why: `git branch --merged` (and every git client that uses it, including
#   Tower) relies on commit reachability. A squash-merge creates a new commit
#   hash on main, so the original branch's tip is never reachable — the branch
#   looks "unmerged" locally even though its PR landed days ago. This helper
#   queries GitHub directly via gh to find the truth.
#
#   Output columns:
#     BRANCH        local branch name
#     PR            merged PR number
#     MERGED        merge date (YYYY-MM-DD)
#     UPSTREAM      'gone' if remote was auto-deleted, '-' otherwise
#     URL           direct PR link
#
#   Runtime: ~1s per local branch (one gh call each).
#   Skips:   default branch (main/master), currently-checked-out branch.
# -----------------------------------------------------------------------------
pr-merged() {
  local current default branches
  current=$(git symbolic-ref --short HEAD 2>/dev/null) || return 1
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || {
    echo "pr-merged: cannot resolve origin/HEAD; set the remote default branch first" >&2
    return 1
  }
  default=${default#origin/}
  branches=$(git branch --format='%(refname:short)|%(upstream:track)|%(objectname)') || return 1

  local rows=""
  local b track tip
  while IFS='|' read -r b track tip; do
    [[ -z "$b" || "$b" == "$default" || "$b" == "master" || "$b" == "$current" ]] && continue
    local pr_line
    if ! pr_line=$(gh pr list --head "$b" --base "$default" --state merged --limit 1 \
      --json number,url,mergedAt,headRefOid \
      --jq '.[0] | select(. != null) | [(.number|tostring), .url, (.mergedAt[0:10]), .headRefOid] | @tsv'); then
      echo "pr-merged: failed to query merged PRs for $b" >&2
      return 1
    fi
    [[ -z "$pr_line" ]] && continue
    local number url merged_at pr_tip upstream='-'
    IFS=$'\t' read -r number url merged_at pr_tip <<<"$pr_line"
    [[ "$tip" == "$pr_tip" ]] || continue
    [[ "$track" == *gone* ]] && upstream='gone'
    rows+="$b"$'\t'"#$number"$'\t'"$merged_at"$'\t'"$upstream"$'\t'"$url"$'\n'
  done <<<"$branches"

  if [[ -z "$rows" ]]; then
    echo "(no merged local branches)"
    return 0
  fi
  {
    printf "%s\t%s\t%s\t%s\t%s\n" "BRANCH" "PR" "MERGED" "UPSTREAM" "URL"
    print -rn -- "$rows"
  } | column -t -s $'\t'
}

# Compatibility names.
alias dotlink='dot-link'
alias dotbackup='dot-backup'
alias local-merged='pr-merged'
