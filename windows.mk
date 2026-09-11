.PHONY: help all link packages packages-check brew-check fonts restore-apps backup doctor verify-bootstrap hooks hooks-check upgrade shims skills skills-audit skills-manifest skills-update rules-audit brewfile-audit ssh-setup
DOT := "$(CURDIR)/bin/dot.cmd"
help:
	@$(DOT) help
all:
	@$(DOT) setup -Apply
link:
	@$(DOT) link
packages:
	@$(DOT) packages -Apply
packages-check brew-check:
	@$(DOT) packages-check
fonts:
	@$(DOT) fonts -Apply
restore-apps:
	@$(DOT) restore-apps -Apply
backup:
	@$(DOT) backup -Apply
doctor:
	@$(DOT) doctor
verify-bootstrap:
	@$(DOT) doctor -Strict
hooks:
	@$(DOT) hooks
hooks-check:
	@$(DOT) hooks -Check
upgrade:
	@$(DOT) upgrade
shims:
	@$(DOT) path
skills skills-audit rules-audit:
	@$(DOT) skills
skills-manifest:
	@$(DOT) skills -UpdateManifest
skills-update:
	@$(DOT) upgrade -SkipApps
brewfile-audit:
	@$(DOT) packages-check -CoverageOnly
ssh-setup:
	@$(DOT) ssh-setup
.PHONY: secrets-backup
secrets-backup:
	@$(DOT) secrets-backup -Apply
.PHONY: secrets-open secrets-close
secrets-open:
	@$(DOT) secrets-open -Apply $(if $(ARCHIVE),-Archive "$(ARCHIVE)")
secrets-close:
	@$(DOT) secrets-close -Apply $(if $(VIEW),-View "$(VIEW)")
# Explicit rejection also covers names of existing directories (make would otherwise
# report macos/services as already up to date, incorrectly implying success).
MAC_ONLY := macos macos-user macos-dry-run macos-check dock services services-check brew brew-core brew-apps brew-base brew-mas brew-npm brew-without-mas node unlink terminal touch-id-sudo touch-id-sudo-check default-apps default-apps-check capture-default-apps post-vault secrets-backup-legacy secrets-compat-fixtures secrets-mount secrets-mount-legacy secrets-health secrets-manifest secrets-restore secrets-restore-apply secrets-pass secrets-pass-import restore-canary restore-shottr backup-canary backup-shottr
.PHONY: $(MAC_ONLY)
$(MAC_ONLY):
	$(error $@ is macOS-only; use the Windows commands in WINDOWS.md)

.PHONY: restore-hermes hermes-check
restore-hermes:
	@$(DOT) hermes -Apply
hermes-check:
	@$(DOT) hermes -Check
