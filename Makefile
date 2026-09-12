export DOTFILES_PUBLIC_SNAPSHOT := 1
.DEFAULT_GOAL := help

ifeq ($(OS),Windows_NT)
include windows.mk
else

.PHONY: all help link unlink brew brew-without-mas brew-core brew-apps node brew-npm brew-mas brew-check brewfile-audit shims macos macos-user macos-dry-run macos-check touch-id-sudo touch-id-sudo-check dock terminal services services-check restore-apps restore-canary restore-shottr post-vault backup backup-canary backup-shottr audit-apps apps-drift hooks hooks-check ssh-setup skills-audit skills skills-update skills-manifest secrets-backup secrets-backup-legacy secrets-compat-fixtures secrets-mount secrets-mount-legacy secrets-health secrets-manifest secrets-restore secrets-restore-apply secrets-pass secrets-pass-import upgrade rules-audit default-apps default-apps-check capture-default-apps doctor verify-bootstrap docs-audit

export DOTFILES := $(CURDIR)

.PHONY: cursor-extensions vscode-extensions restore-zed zed-check
cursor-extensions: ## Install the minimal reviewed Cursor extension set
	@cursor --install-extension esbenp.prettier-vscode

vscode-extensions: ## Apply the verified formatter version; upstream 7.2.8 is broken
	@code --install-extension foxundermoon.shell-format@7.2.5 --force

restore-zed: ## Restore only Zed settings and keymap with the running-app gate
	@bash scripts/restore-apps.sh --only zed

zed-check: ## Check Zed settings, keymap, declared extensions and theme assets
	@python3 scripts/check-zed.py

all: ## Re-apply the full existing-Mac setup, including node shims, in a fixed order
	@$(MAKE) --no-print-directory link
	@$(MAKE) --no-print-directory rules-audit
	@$(MAKE) --no-print-directory skills-audit
	@$(MAKE) --no-print-directory brew-without-mas
	@$(MAKE) --no-print-directory shims
	@$(MAKE) --no-print-directory services
	@$(MAKE) --no-print-directory restore-apps
	@$(MAKE) --no-print-directory dock
	@$(MAKE) --no-print-directory hooks
	@$(MAKE) --no-print-directory macos
	@echo "Full setup complete."
# macos last: defaults.sh has interactive prompts; a Ctrl-C there previously
# aborted the sequence before dock/hooks could run.
# post-vault / ssh-setup stay manual: never touch canonical key material
# before the existing secret tree has had a chance to be restored.
# terminal is NOT in `all` (would kill parent Terminal.app shell).
# default-apps, doctor, docs-audit, skills, and terminal stay manual.

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

restore-apps: ## Restore repo-tracked app preference snapshots
	@bash scripts/restore-apps.sh

.PHONY: sublime-check
sublime-check: ## Check Sublime helper, declared packages, theme and syntax resources
	@python3 scripts/check-sublime.py

restore-canary: ## Restore Canary Mail prefs from the secrets vault
	@bash scripts/restore-canary-vault.sh

restore-shottr: ## Restore Shottr prefs from the secrets vault
	@bash scripts/restore-shottr-vault.sh

backup-canary: ## Back up Canary Mail prefs into ~/.secrets
	@bash scripts/backup-canary-vault.sh

backup-shottr: ## Back up Shottr prefs into ~/.secrets
	@bash scripts/backup-shottr-vault.sh

.PHONY: shottr-backup backup-dato restore-dato backup-deskflow
shottr-backup: backup-shottr ## Alias for backup-shottr

backup-dato: ## Back up full Dato preferences into ~/.secrets
	@bash scripts/backup-dato-vault.sh

restore-dato: ## Restore full Dato preferences after launching Dato once
	@bash scripts/restore-dato-vault.sh

backup-deskflow: ## Back up Mac Deskflow configuration and TLS files into ~/.secrets
	@bash scripts/backup-deskflow-vault.sh

.PHONY: ssh-sockets
ssh-sockets: ## Create the local SSH connection-sharing directory
	@mkdir -p "$(HOME)/.ssh/sockets"
	@chmod 700 "$(HOME)/.ssh/sockets"

ssh-setup: ssh-sockets ## Verify/register restored GitHub auth + signing key
	@bash scripts/ssh-setup.sh

secrets-manifest: ## Install the default vault backup manifest when absent
	@umask 077; mkdir -p "$(HOME)/.dotfiles-local"; \
	if [ -e "$(HOME)/.dotfiles-local/backup.manifest" ]; then \
		echo "  ✓ backup manifest already exists (left unchanged)"; \
	else \
		cp scripts/backup-manifest.example "$(HOME)/.dotfiles-local/backup.manifest"; \
		chmod 600 "$(HOME)/.dotfiles-local/backup.manifest"; \
		echo "  ✓ installed default backup manifest → ~/.dotfiles-local/backup.manifest"; \
	fi

# After transactional secrets restore + secrets-pass-import. Soft-skips Shottr/Canary when payload
# absent. Not in `all` — requires ~/.secrets first.
post-vault: ## After secrets land: link, ssh-setup, vault app restores, restore-apps
	@bash scripts/post-vault.sh


upgrade: ## Update apps/tools and agent skills
	@topgrade


skills-audit: ## Check tracked agent skills for redistribution/license safety
	@bash scripts/audit-skill-licenses.sh --check

# Assert agents/AGENTS.md @-includes and agents/rules/*.md stay 1:1 in sync.
rules-audit: ## Check agent rule includes stay in sync
	@bash scripts/audit-rules.sh

brewfile-audit: ## Check Brewfile consistency rules
	@bash scripts/audit-brewfile.sh --check

# Regenerate ./Skillsfile and agents/skills/README.md from agents/.skill-lock.json.
skills-manifest: ## Regenerate Skillsfile and skills README from the skill lockfile
	@python3 scripts/gen-skillsfile.py
	@python3 agents/compareskills.py

# The checked-in agents/ tree is the reproducible restore source. `make link`
# exposes it at ~/.agents; network installs are an explicit update workflow.
skills: skills-audit ## Verify the vendored global skills restored by make link
	@python3 scripts/gen-skillsfile.py --check
	@python3 agents/compareskills.py --check
	@echo "  ✓ vendored skills are repo-managed at $(CURDIR)/agents/skills"
	@echo "  → upstream refresh is explicit: make skills-update"

skills-update: ## Explicitly refresh vendored skills from current upstream sources
	@bash Skillsfile
	@$(MAKE) --no-print-directory skills-manifest
	@$(MAKE) --no-print-directory skills-audit
	@git status --short -- Skillsfile agents/.skill-lock.json agents/skills agents/skills/README.md

hooks: ## Install local git hooks and diff drivers
	@git config --local core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "  ✓ git hooks path → .githooks/ (tracked, dotfiles-managed)"
	@git config --local diff.plist.textconv "plutil -p"
	@git config --local diff.plist.binary true
	@echo "  ✓ plist diff driver (.gitattributes wires *.plist → plist)"

hooks-check: ## Verify this checkout uses the tracked executable git hooks
	@bash scripts/check-hooks.sh

link: ## Apply symlinks from symlinks.tsv
	@bash scripts/link.sh

unlink: ## Remove only symlinks managed by symlinks.tsv
	@bash scripts/unlink.sh

brew: ## Install packages; confirm MAS interactively or defer it safely
	@$(MAKE) brew-base
	@$(MAKE) node
	@$(MAKE) brew-npm
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh mas-optional

brew-without-mas: ## Install all non-App-Store Brewfile phases
	@$(MAKE) brew-base
	@$(MAKE) node
	@$(MAKE) brew-npm
	@echo "  - App Store phase deferred; after sign-in run: make brew-mas"

brew-base: ## Install Brewfile except npm and App Store entries
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh base
	@$(MAKE) --no-print-directory vscode-extensions
	@$(MAKE) --no-print-directory cursor-extensions

brew-core: ## Install bootstrap taps, formulae, and uv tools
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh core

brew-apps: ## Install casks, fonts, and editor extensions (resumable phase)
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh apps
	@$(MAKE) --no-print-directory vscode-extensions
	@$(MAKE) --no-print-directory cursor-extensions

node: ## Install and activate the exact Node version from .node-version
	@DOTFILES="$(CURDIR)" bash scripts/setup-node.sh

brew-npm: ## Install Brewfile npm globals under the pinned Node runtime
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh npm

brew-mas: ## Install only App Store apps after signing into the App Store
	@echo "Installing App Store apps (ensure the App Store is signed in)..."
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh mas

shims: ## Create/repair node-stable + npx-stable shims from .node-version
	@bash scripts/link-node-shims.sh

brew-check: ## Check whether Brewfile entries are installed
	@DOTFILES="$(CURDIR)" bash scripts/brewfile.sh check

macos: ## Apply interactive macOS defaults
	@bash macos/defaults.sh
	@bash scripts/touch-id-sudo.sh --apply

macos-user: ## Apply only non-privileged per-user macOS defaults
	@bash macos/defaults.sh --user-only

macos-dry-run: ## Preview macOS defaults without changing the machine
	@bash macos/defaults.sh --dry-run
	@bash scripts/touch-id-sudo.sh --dry-run

macos-check: ## Read back managed macOS defaults and Finder view policy
	@bash macos/defaults.sh --check
	@if [ "$(SKIP_FINDER_VIEWS)" != "1" ]; then python3 scripts/apply-finder-views.py --check; fi
	@bash scripts/touch-id-sudo.sh --check

touch-id-sudo: ## Idempotently enable Touch ID authentication for sudo
	@bash scripts/touch-id-sudo.sh --apply

touch-id-sudo-check: ## Check whether Touch ID authentication for sudo is enabled
	@bash scripts/touch-id-sudo.sh --check

dock: ## Restore Dock layout from macos/dock-backup.plist
	@bash macos/dock.sh

# terminal is NOT part of `make all` because `osascript ... to quit` would
# kill the parent shell when invoked from Terminal.app. Run manually from
# iTerm / Ghostty / VS Code integrated terminal, or accept that you'll need
# to reopen Terminal.app afterwards.
terminal: ## Import Terminal.app profiles (quits Terminal.app)
	@if [ -f apps/terminal/terminal.plist ]; then \
		osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true; \
		defaults import com.apple.Terminal apps/terminal/terminal.plist && \
			echo "  ✓ Terminal.app profiles imported (reopen Terminal to see)"; \
	else \
		echo "  - apps/terminal/terminal.plist not found; skipping"; \
	fi

services: ## Install Automator Quick Actions into ~/Library/Services
	@set -e; \
		mkdir -p ~/Library/Services; \
		restore_service() { \
			rc=$$?; \
			trap - EXIT HUP INT TERM; \
			if [ ! -e "$$dest" ] && [ -e "$$old" ]; then \
				mv "$$old" "$$dest" || true; \
			fi; \
			rm -rf "$$tmp"; \
			exit "$$rc"; \
		}; \
		count=0; \
		for workflow in services/*.workflow; do \
			[ -e "$$workflow" ] || continue; \
			name=$$(basename "$$workflow"); \
			dest="$$HOME/Library/Services/$$name"; \
			tmp="$$HOME/Library/Services/.$$name.dotfiles-tmp"; \
			old="$$HOME/Library/Services/.$$name.dotfiles-old"; \
			rm -rf "$$tmp"; \
			if [ ! -e "$$dest" ] && [ -e "$$old" ]; then mv "$$old" "$$dest"; fi; \
			rm -rf "$$old"; \
			cp -R "$$workflow" "$$tmp"; \
			trap restore_service EXIT HUP INT TERM; \
			if [ -e "$$dest" ]; then mv "$$dest" "$$old"; fi; \
			mv "$$tmp" "$$dest"; \
			rm -rf "$$old"; \
			trap - EXIT HUP INT TERM; \
			echo "  ✓ $$name"; \
		count=$$((count + 1)); \
	done; \
	[ "$$count" -gt 0 ] || { echo "  ✗ no Automator workflows found" >&2; exit 1; }; \
	echo "Automator services installed ($$count)."; \
	if [ -x /System/Library/CoreServices/pbs ]; then /System/Library/CoreServices/pbs -update; fi; \
	echo "Enable restored actions in System Settings > General > Login Items & Extensions > Finder."; \
	echo "services-check compares workflow files; verify Finder menus separately."

services-check: ## Compare installed Automator workflows with the repo copies
	@bash scripts/check-services.sh

default-apps: ## Apply repo default-app policy from config/duti
	@bash scripts/apply-duti.sh

default-apps-check: ## Compare live default-app handlers with config/duti
	@bash scripts/check-duti.sh

capture-default-apps: ## Refresh config/duti from current handlers on this Mac
	@bash scripts/capture-duti.sh

doctor: ## Run read-only bootstrap preflight checks
	@bash scripts/doctor.sh

verify-bootstrap: ## Fail unless the post-vault Mac bootstrap is complete
	@$(MAKE) --no-print-directory rules-audit
	@$(MAKE) --no-print-directory skills
	@$(MAKE) --no-print-directory audit-apps
	@bash scripts/link.sh --check
	@$(MAKE) --no-print-directory services-check
	@$(MAKE) --no-print-directory hooks-check
	@$(MAKE) --no-print-directory macos-check
	@$(MAKE) --no-print-directory default-apps-check
	@bash scripts/doctor.sh --strict

docs-audit: ## Check docs/scripts for typos when typos is installed
	@if command -v typos >/dev/null 2>&1; then \
		typos README.md AGENTS.md Makefile install.sh scripts macos zsh config hammerspoon bin git starship; \
	else \
		echo "  - typos not installed; run 'make brew' first"; \
	fi


.PHONY: test-public
test-public: ## Run checkout-safe public bootstrap, recovery and preference fixtures
	@python3 -m unittest discover -s tests -p "test_*.py"

audit-apps: ## Scan app preference snapshots for secrets/local paths
	@bash scripts/audit-app-prefs.sh

apps-drift: ## Check app preference snapshots against current system state
	@bash scripts/audit-apps-drift.sh

backup: ## Check macOS policy, refresh repo snapshots, then capture Dato/Shottr/Deskflow into ~/.secrets
	@$(MAKE) --no-print-directory macos-check SKIP_FINDER_VIEWS=1 || { echo "macOS preferences differ or could not be checked. Review and confirm each difference before backup; update policy or restore the saved value, then retry."; exit 1; }
	@bash scripts/backup-apps.sh
	@if [ -f "$(HOME)/Library/Containers/com.sindresorhus.Dato/Data/Library/Preferences/com.sindresorhus.Dato.plist" ]; then $(MAKE) --no-print-directory backup-dato; else echo "Dato private capture skipped: launch Dato first; previous backup retained."; fi
	@if defaults read cc.ffitch.shottr >/dev/null 2>&1; then $(MAKE) --no-print-directory backup-shottr; else echo "Shottr private capture skipped: preferences unavailable; previous backup retained."; fi
	@if [ -d "$(HOME)/Library/Deskflow" ]; then $(MAKE) --no-print-directory backup-deskflow; else echo "Deskflow private capture skipped: configure Deskflow first; previous backup retained."; fi

secrets-backup: ## Update DotfilesSecrets.dmg with five verified snapshots
	@bash scripts/secrets-backup.sh --persistent

.PHONY: secrets-backup-portable
secrets-backup-portable: ## Publish a separate immutable APFS/UDZO recovery DMG
	@bash scripts/secrets-backup-portable.sh

secrets-backup-legacy: ## Append to the legacy mutable sparseimage vault
	@bash scripts/secrets-backup.sh

secrets-compat-fixtures: ## Create disposable APFS UDSP/UDZO compatibility images
	@bash scripts/secrets-format-compat.sh create

secrets-mount: ## Verify and open the persistent vault (or latest portable fallback)
	@bash scripts/secrets-mount.sh

secrets-mount-legacy: ## Open the preserved legacy sparseimage
	@bash scripts/secrets-mount-legacy.sh

secrets-health: ## Validate mounted vault snapshot freshness (day-2 check)
	@bash scripts/secrets-health.sh

secrets-restore: ## Read-only validation of the newest mounted vault snapshot
	@bash scripts/secrets-restore.sh --check

secrets-restore-apply: ## Restore ~/.secrets from the newest validated snapshot
	@bash scripts/secrets-restore.sh --apply

secrets-pass: ## Copy the local vault password from Keychain
	@bash scripts/secrets-pass.sh

secrets-pass-import: ## Import a recovered vault password into the local Keychain
	@bash scripts/secrets-pass-import.sh
endif
