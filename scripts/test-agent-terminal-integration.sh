#!/usr/bin/env bash

# Behavioral fixture for the agent rulebook's terminal integration contract.
# Proves that branch-to-worktree discovery survives platform path edge cases, that
# fast-forward/squash/merge/rebase results can be pushed by pinned OID, and that
# locally created or replayed commits use the configured identity and signing
# backend without modifying unrelated dirty worktrees.
set -euo pipefail

# Git hooks export repository-local variables that must not leak into fixture repositories.
while IFS= read -r git_local_variable; do
  unset "$git_local_variable"
done < <(git rev-parse --local-env-vars)
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
unset GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-terminal-integration.XXXXXX")"
fixture_root="$(cd -- "$fixture_root" && pwd -P)"
case "$fixture_root" in
  /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
  *)
    echo "refusing unsafe fixture path: $fixture_root" >&2
    exit 1
    ;;
esac

cleanup() {
  rm -rf -- "$fixture_root"
}
trap cleanup EXIT

# Git for Windows reports native paths in porcelain output. Use the same form
# for expected paths; keep spaces/Unicode coverage on every platform.
windows_paths=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    windows_paths=1
    fixture_root="$(cygpath -m "$fixture_root")"
    ;;
esac

remote_repo="$fixture_root/remote.git"
main_worktree="$fixture_root/Main Checkout"
worktree_parent="$main_worktree/.worktrees"
topic_worktree="$worktree_parent/feature/exact-object"
if [[ "$windows_paths" -eq 1 ]]; then
  # Windows forbids newlines in filenames; Unix retains that edge case.
  unrelated_worktree="$worktree_parent/feature/unrelated worktree-å"
else
  unrelated_worktree="$worktree_parent/feature/unrelated"$'\n'"worktree-å"
fi
squash_worktree="$worktree_parent/.integration/squash"
merge_worktree="$worktree_parent/.integration/merge"
rebase_worktree="$worktree_parent/.integration/rebase"

git init --quiet --bare --initial-branch=main "$remote_repo"
clone_output="$(git clone --quiet "$remote_repo" "$main_worktree" 2>&1)" || {
  printf '%s\n' "$clone_output" >&2
  exit 1
}
git -C "$main_worktree" config user.name 'Agent Rule Fixture'
git -C "$main_worktree" config user.email 'agent-rule-fixture@example.invalid'
git -C "$main_worktree" config commit.gpgsign false

printf '.worktrees/\n' >>"$main_worktree/.git/info/exclude"
printf 'base\n' >"$main_worktree/base.txt"
git -C "$main_worktree" add -- base.txt
git -C "$main_worktree" commit --quiet -m 'test: establish base'
git -C "$main_worktree" push --quiet -u origin main
base_oid="$(git -C "$main_worktree" rev-parse HEAD)"
git -C "$main_worktree" push --quiet origin \
  "$base_oid:refs/heads/ff-target" \
  "$base_oid:refs/heads/squash-target" \
  "$base_oid:refs/heads/merge-target" \
  "$base_oid:refs/heads/rebase-target"

mkdir -p -- "$worktree_parent/feature" "$worktree_parent/.integration"
git -C "$main_worktree" check-ignore -q .worktrees/
git -C "$main_worktree" worktree add --quiet -b feature/exact-object "$topic_worktree" main
printf 'topic\n' >"$topic_worktree/topic.txt"
git -C "$topic_worktree" add -- topic.txt
GIT_AUTHOR_NAME='Reviewed Author' GIT_AUTHOR_EMAIL='reviewed-author@example.invalid' \
  git -C "$topic_worktree" commit --quiet -m 'test: add topic change'
topic_oid="$(git -C "$topic_worktree" rev-parse HEAD)"

signing_key="$fixture_root/fixture-signing-key"
allowed_signers="$fixture_root/allowed_signers"
ssh-keygen -q -t ed25519 -N '' -f "$signing_key"
read -r key_type key_data _ <"$signing_key.pub"
printf 'agent-rule-fixture@example.invalid %s %s\n' "$key_type" "$key_data" >"$allowed_signers"
git -C "$main_worktree" config gpg.format ssh
git -C "$main_worktree" config user.signingkey "$signing_key"
git -C "$main_worktree" config gpg.ssh.allowedSignersFile "$allowed_signers"
git -C "$main_worktree" config commit.gpgsign true

printf 'dirty local main\n' >>"$main_worktree/base.txt"
dirty_before="$(git -C "$main_worktree" diff -- base.txt)"

git -C "$main_worktree" worktree add --quiet -b feature/unrelated-wip "$unrelated_worktree" main
unrelated_head_before="$(git -C "$unrelated_worktree" rev-parse HEAD)"
printf 'dirty unrelated worktree\n' >>"$unrelated_worktree/base.txt"
unrelated_dirty_before="$(git -C "$unrelated_worktree" diff -- base.txt)"

current_worktree=''
resolved_main_worktree=''
resolved_topic_worktree=''
resolved_unrelated_worktree=''
while IFS= read -r -d '' field; do
  case "$field" in
    'worktree '*) current_worktree="${field#worktree }" ;;
    'branch refs/heads/main') resolved_main_worktree="$current_worktree" ;;
    'branch refs/heads/feature/exact-object') resolved_topic_worktree="$current_worktree" ;;
    'branch refs/heads/feature/unrelated-wip') resolved_unrelated_worktree="$current_worktree" ;;
    '') current_worktree='' ;;
  esac
done < <(git -C "$main_worktree" worktree list --porcelain -z)

[[ "$resolved_main_worktree" == "$main_worktree" ]] || {
  echo "NUL-safe worktree discovery mapped main to the wrong path" >&2
  exit 1
}
[[ "$resolved_topic_worktree" == "$topic_worktree" ]] || {
  echo "NUL-safe worktree discovery mapped the topic branch to the wrong path" >&2
  exit 1
}
[[ "$resolved_unrelated_worktree" == "$unrelated_worktree" ]] || {
  echo "NUL-safe worktree discovery lost the platform-specific Unicode worktree path" >&2
  exit 1
}

git -C "$resolved_topic_worktree" push --quiet origin "$topic_oid:refs/heads/ff-target"

remote_oid="$(git --git-dir="$remote_repo" rev-parse refs/heads/ff-target)"
[[ "$remote_oid" == "$topic_oid" ]] || {
  echo "remote fast-forward target does not equal the pinned topic OID" >&2
  exit 1
}

git -C "$main_worktree" worktree add --quiet --detach "$squash_worktree" "$base_oid"
git -C "$squash_worktree" merge --squash "$topic_oid" >/dev/null
git -C "$squash_worktree" commit --quiet -S -m 'test: squash topic change'
squash_oid="$(git -C "$squash_worktree" rev-parse HEAD)"
expected_ident='Agent Rule Fixture <agent-rule-fixture@example.invalid>|Agent Rule Fixture <agent-rule-fixture@example.invalid>'
[[ "$(git -C "$squash_worktree" show -s --format='%an <%ae>|%cn <%ce>' HEAD)" == "$expected_ident" ]] || {
  echo "local squash did not use the configured author and committer identity" >&2
  exit 1
}
git -C "$squash_worktree" verify-commit "$squash_oid"
[[ "$(git -C "$squash_worktree" rev-parse 'HEAD^{tree}')" == "$(git -C "$resolved_topic_worktree" rev-parse 'HEAD^{tree}')" ]] || {
  echo "local squash tree does not match the reviewed topic tree" >&2
  exit 1
}
git -C "$squash_worktree" push --quiet origin "$squash_oid:refs/heads/squash-target"
[[ "$(git --git-dir="$remote_repo" rev-parse refs/heads/squash-target)" == "$squash_oid" ]] || {
  echo "remote squash target does not equal the pinned local squash OID" >&2
  exit 1
}

git -C "$main_worktree" worktree add --quiet --detach "$merge_worktree" "$base_oid"
git -C "$merge_worktree" merge --quiet --no-ff --no-edit -S "$topic_oid"
merge_oid="$(git -C "$merge_worktree" rev-parse HEAD)"
[[ "$(git -C "$merge_worktree" show -s --format='%an <%ae>|%cn <%ce>' HEAD)" == "$expected_ident" ]] || {
  echo "local merge commit did not use the configured author and committer identity" >&2
  exit 1
}
git -C "$merge_worktree" verify-commit "$merge_oid"
[[ "$(git -C "$merge_worktree" rev-parse HEAD^1)" == "$base_oid" ]] || {
  echo "local merge commit has the wrong first parent" >&2
  exit 1
}
[[ "$(git -C "$merge_worktree" rev-parse HEAD^2)" == "$topic_oid" ]] || {
  echo "local merge commit has the wrong second parent" >&2
  exit 1
}
git -C "$merge_worktree" push --quiet origin "$merge_oid:refs/heads/merge-target"
[[ "$(git --git-dir="$remote_repo" rev-parse refs/heads/merge-target)" == "$merge_oid" ]] || {
  echo "remote merge target does not equal the pinned local merge OID" >&2
  exit 1
}

git -C "$main_worktree" worktree add --quiet --detach "$rebase_worktree" "$topic_oid"
git -C "$rebase_worktree" rebase --quiet --force-rebase --gpg-sign \
  --onto "$base_oid" "$base_oid"
rebase_oid="$(git -C "$rebase_worktree" rev-parse HEAD)"
[[ "$rebase_oid" != "$topic_oid" ]] || {
  echo "selected rebase preserved the reviewed OID instead of replaying it" >&2
  exit 1
}
[[ "$(git -C "$rebase_worktree" show -s --format='%an <%ae>' HEAD)" == \
    'Reviewed Author <reviewed-author@example.invalid>' ]] || {
  echo "local rebase did not preserve the reviewed author" >&2
  exit 1
}
[[ "$(git -C "$rebase_worktree" show -s --format='%cn <%ce>' HEAD)" == \
    'Agent Rule Fixture <agent-rule-fixture@example.invalid>' ]] || {
  echo "local rebase did not use the effective committer" >&2
  exit 1
}
[[ "$(git -C "$rebase_worktree" rev-parse 'HEAD^{tree}')" == \
    "$(git -C "$resolved_topic_worktree" rev-parse 'HEAD^{tree}')" ]] || {
  echo "local rebase tree does not match the reviewed topic tree" >&2
  exit 1
}
git -C "$rebase_worktree" verify-commit "$rebase_oid"
git -C "$rebase_worktree" push --quiet origin "$rebase_oid:refs/heads/rebase-target"
[[ "$(git --git-dir="$remote_repo" rev-parse refs/heads/rebase-target)" == "$rebase_oid" ]] || {
  echo "remote rebase target does not equal the pinned replayed OID" >&2
  exit 1
}

current_worktree=''
while IFS= read -r -d '' field; do
  case "$field" in
    'worktree '*)
      current_worktree="${field#worktree }"
      case "$current_worktree" in
        "$main_worktree"|"$worktree_parent"/*) ;;
        *)
          echo "worktree escaped canonical .worktrees parent: $current_worktree" >&2
          exit 1
          ;;
      esac
      ;;
  esac
done < <(git -C "$main_worktree" worktree list --porcelain -z)
[[ ! -e "$main_worktree/worktrees" ]] || {
  echo "legacy worktrees parent was created" >&2
  exit 1
}
[[ ! -e "$main_worktree/.git/agent-integration" ]] || {
  echo "integration worktree was created inside Git metadata" >&2
  exit 1
}

git -C "$main_worktree" worktree remove "$squash_worktree"
git -C "$main_worktree" worktree remove "$merge_worktree"
git -C "$main_worktree" worktree remove "$rebase_worktree"
[[ ! -e "$squash_worktree" && ! -e "$merge_worktree" && ! -e "$rebase_worktree" ]] || {
  echo "proven integration worktrees were not removed" >&2
  exit 1
}
[[ "$(git -C "$main_worktree" rev-parse HEAD)" == "$base_oid" ]] || {
  echo "local main moved during remote promotion" >&2
  exit 1
}
[[ "$(git -C "$main_worktree" diff -- base.txt)" == "$dirty_before" ]] || {
  echo "dirty local main changed during remote promotion" >&2
  exit 1
}
[[ "$(git -C "$unrelated_worktree" rev-parse HEAD)" == "$unrelated_head_before" ]] || {
  echo "unrelated worktree HEAD moved during remote promotion" >&2
  exit 1
}
[[ "$(git -C "$unrelated_worktree" diff -- base.txt)" == "$unrelated_dirty_before" ]] || {
  echo "dirty unrelated worktree changed during remote promotion" >&2
  exit 1
}

# Refusal contract: the procedure pushes without force, so a divergent object must be
# rejected rather than silently rewriting the target. Build it with plumbing so no
# worktree is touched.
base_tree="$(git -C "$main_worktree" rev-parse "$base_oid^{tree}")"
divergent_oid="$(git -C "$main_worktree" commit-tree "$base_tree" -p "$base_oid" \
  -m 'test: divergent object that must not fast-forward')"
[[ "$divergent_oid" != "$topic_oid" ]] || {
  echo "divergent fixture object collided with the topic OID" >&2
  exit 1
}
ff_target_before="$(git --git-dir="$remote_repo" rev-parse refs/heads/ff-target)"
if git -C "$main_worktree" push --quiet origin \
    "$divergent_oid:refs/heads/ff-target" 2>/dev/null; then
  echo "non-fast-forward push was accepted without force" >&2
  exit 1
fi
[[ "$(git --git-dir="$remote_repo" rev-parse refs/heads/ff-target)" == "$ff_target_before" ]] || {
  echo "rejected push still moved the remote ref" >&2
  exit 1
}

echo "  ✓ terminal integration preserves identity, signatures, strategy, and dirty worktrees"
echo "  ✓ every created worktree stays under the primary checkout's .worktrees parent"
echo "  ✓ non-fast-forward promotion is refused without force"
