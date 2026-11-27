# Retire old Paseo links and Windows PATH entry

This one-time migration removes only the six former dotfiles-owned Codex skill
links and, on Windows, the known default Paseo resources\bin User PATH entry.
It does not uninstall Paseo, delete its app or user data, remove custom
installations, or change the normal additive link and PATH repair workflows.
Application removal is a separate owner decision. On a Mac with the Homebrew
cask, the owner can run brew uninstall --cask paseo without --zap. On Windows,
the owner can review Paseo under Settings > Apps > Installed apps and uninstall
it there if desired. The Mac app has already been removed for this setup; no
Windows app removal is claimed here.

Before applying on an adopted setup, follow the owner checkpoint in
[AGENT-SETUP.md](AGENT-SETUP.md#adopt-an-existing-setup): review the proposed
scope and obtain the owner's confirmation that the existing setup and linked
source files are backed up, or that the setup was unorganized and they explicitly
accept migrating the reviewed scope without a backup. If neither applies, pause
for the owner to arrange a backup or decide how to proceed. The helper does not
create a backup, and no new backup is required by this migration. Its scope is
limited to the retired links and the one known PATH value.

## macOS

Preview first:

    bash scripts/retire-paseo.sh

After reviewing the exact links it reports, apply explicitly:

    bash scripts/retire-paseo.sh --apply

The helper removes a link only when the entry is a symlink whose recorded target
is exactly this checkout's former agents/skills/paseo* source. It leaves real
files and directories, links to another checkout, and unrelated Codex skills
alone. If ~/.codex or ~/.codex/skills is a symlink, it stops before
traversing that tree; inspect the ownership and handle it manually.

## Windows

Run from the repository root in standard PowerShell 7.4 or newer:

    pwsh -NoLogo -NoProfile -File .\scripts\retire-paseo.ps1

Review the listed junctions and PATH change, then explicitly apply:

    pwsh -NoLogo -NoProfile -File .\scripts\retire-paseo.ps1 -Apply

Only junctions or directory symbolic links at the six former Codex skill names whose recorded target
matches this checkout's old agents\skills\paseo* path are eligible. The helper
uses non-recursive directory deletion so the source skill data is not traversed.
It removes only the default
%LOCALAPPDATA%\Programs\Paseo\resources\bin entry from the User PATH. Matching
ignores surrounding whitespace, case, slash direction and trailing separators; every unrelated PATH
entry keeps its original spelling and order. Custom Paseo install paths require
owner review and are left unchanged. If .codex or .codex\skills is a
reparse point, the helper stops before traversing it.

The Windows junction and directory symbolic-link identity plus non-recursive
deletion behavior are covered by tests/test_paseo_retirement.ps1, but that
fixture must be run on Windows.
On a Mac, only the portable Python fixture and static review are available; do
not treat those as native Windows execution evidence.
