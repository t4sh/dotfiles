.PHONY: all help link unlink brew brew-check brewfile-audit macos dock terminal services restore-apps restore-canary restore-shottr backup backup-canary backup-shottr audit-apps hooks ssh-setup skills-audit skills skills-manifest secrets-backup secrets-mount secrets-pass rules-audit default-apps capture-default-apps doctor docs-audit

# Make targets operate on this checkout, even when reviewing/developing from a
# path other than ~/.dotfiles. Fresh installs still clone to ~/.dotfiles.
export DOTFILES := $(CURDIR)

all: link rules-audit skills-audit brew services restore-apps dock hooks ssh-setup macos ## Re-apply the full existing-Mac setup
	@echo "Full setup complete."
# macos last: defaults.sh has interactive prompts; a Ctrl-C there previously
# aborted the sequence before dock/hooks/ssh-setup could run.
# terminal is NOT in `all` (would kill parent Terminal.app shell).
# default-apps, doctor, docs-audit, skills, and terminal stay manual.

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

restore-apps: ## Restore repo-tracked app preference snapshots
	@bash scripts/restore-apps.sh

restore-canary: ## Restore Canary Mail prefs from the secrets vault
	@bash scripts/restore-canary-vault.sh

restore-shottr: ## Restore Shottr prefs from the secrets vault
	@bash scripts/restore-shottr-vault.sh

backup-canary: ## Back up Canary Mail prefs into ~/.secrets
	@bash scripts/backup-canary-vault.sh

backup-shottr: ## Back up Shottr prefs into ~/.secrets
	@bash scripts/backup-shottr-vault.sh

ssh-setup: ## Generate/register the GitHub SSH key if needed
	@bash scripts/ssh-setup.sh


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

# Install all global skills from the manifest (the `brew bundle`). Not in
# `make all`: needs node + GitHub auth (private sources) set up first.
skills: skills-manifest ## Install global agent skills from Skillsfile
	@bash Skillsfile

hooks: ## Install local git hooks and diff drivers
	@git config --local core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "  ✓ git hooks path → .githooks/ (tracked, dotfiles-managed)"
	@git config --local diff.plist.textconv "plutil -p"
	@git config --local diff.plist.binary true
	@echo "  ✓ plist diff driver (.gitattributes wires *.plist → plist)"

link: ## Apply symlinks from symlinks.tsv
	@bash scripts/link.sh

unlink: ## Remove only symlinks managed by symlinks.tsv
	@bash scripts/unlink.sh

brew: ## Install packages from Brewfile
	brew bundle --file=Brewfile

brew-check: ## Check whether Brewfile entries are installed
	brew bundle check --file=Brewfile

macos: ## Apply interactive macOS defaults
	@bash macos/defaults.sh

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
	count=0; \
	for workflow in services/*.workflow; do \
		[ -e "$$workflow" ] || continue; \
		name=$$(basename "$$workflow"); \
		tmp="$$HOME/Library/Services/.$$name.dotfiles-tmp"; \
		rm -rf "$$tmp"; \
		cp -R "$$workflow" "$$tmp"; \
		rm -rf "$$HOME/Library/Services/$$name"; \
		mv "$$tmp" "$$HOME/Library/Services/$$name"; \
		echo "  ✓ $$name"; \
		count=$$((count + 1)); \
	done; \
	[ "$$count" -gt 0 ] || { echo "  ✗ no Automator workflows found" >&2; exit 1; }; \
	echo "Automator services installed ($$count)."

default-apps: ## Apply repo default-app policy from config/duti
	@bash scripts/apply-duti.sh "$(DOTFILES)/config/duti"

capture-default-apps: ## Refresh config/duti from current handlers on this Mac
	@bash scripts/capture-duti.sh

doctor: ## Run read-only bootstrap preflight checks
	@bash scripts/doctor.sh

docs-audit: ## Check docs/scripts for typos when typos is installed
	@if command -v typos >/dev/null 2>&1; then \
		typos README.md AGENTS.md Makefile install.sh scripts macos zsh config hammerspoon bin; \
	else \
		echo "  - typos not installed; run 'make brew' first"; \
	fi

audit-apps: ## Scan app preference snapshots for secrets/local paths
	@bash scripts/audit-app-prefs.sh

backup: ## Refresh repo-tracked app prefs, Dock, services, and Brewfile
	@echo "Backing up app configs..."
	@# Bulk `defaults`-managed apps — driven by apps.tsv. Container-copy apps
	@# (Dato, Sublime, VS Code) stay as explicit lines below.
	@captured=0; skipped=0; \
	while IFS=$$'\t' read -r domain label plist; do \
		case "$$domain" in ''|\#*) continue ;; esac; \
		if defaults export "$$domain" "$$plist" 2>/dev/null; then \
			echo "  ✓ $$label"; captured=$$((captured + 1)); \
		else \
			echo "  ⚠ $$label not captured (app/domain unavailable)"; skipped=$$((skipped + 1)); \
		fi; \
	done < apps.tsv; \
	echo "  defaults snapshots: $$captured captured, $$skipped skipped"
	@cp ~/Library/Group\ Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist apps/dato/dato.plist 2>/dev/null && echo "  ✓ Dato" || echo "  ⚠ Dato not captured"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-settings apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text settings" || echo "  - no Sublime Text settings to capture"
	@rm -f "apps/sublime-text/Theme - Monokai Pro.sublime-settings"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-keymap apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text keybindings" || echo "  - no Sublime Text keybindings to capture"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-snippet apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text snippets" || echo "  - no Sublime Text snippets to capture"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-macro apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text macros" || echo "  - no Sublime Text macros to capture"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.palettes apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text palettes" || echo "  - no Sublime Text palettes to capture"
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.py apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text user plugins" || echo "  - no Sublime Text user plugins to capture"
	@cp ~/Library/Application\ Support/Code/User/settings.json apps/vscode/settings.json 2>/dev/null && echo "  ✓ VS Code" || echo "  ⚠ VS Code settings not captured"
	@defaults export com.apple.dock macos/dock-backup.plist 2>/dev/null && echo "  ✓ Dock layout" || { echo "  ✗ Dock layout export failed" >&2; exit 1; }
	@defaults export com.apple.Terminal apps/terminal/terminal.plist 2>/dev/null && echo "  ✓ Terminal.app profiles" || echo "  ⚠ Terminal.app profiles not captured"
	@# Shottr + Monokai Pro license settings are NOT kept in the repo — vault only
	@# (~/.secrets/apps/…). Monokai is stripped above; copy license file to vault
	@# after purchase/renewal, then make secrets-backup.
	@for workflow in services/*.workflow; do \
		[ -e "$$workflow" ] || continue; \
		name=$$(basename "$$workflow"); \
		if [ -d "$$HOME/Library/Services/$$name" ]; then \
			rm -rf "services/$$name"; \
			cp -R "$$HOME/Library/Services/$$name" services/ && echo "  ✓ Automator workflow $$name"; \
		fi; \
	done
	@bash scripts/sanitize-app-prefs.sh && echo "  ✓ Sanitized portable app prefs"
	@brew bundle dump --file=Brewfile --force && echo "  ✓ Brewfile"
	@echo ""
	@echo "Done. Manual exports still needed (sensitive — into the secret"
	@echo "store, NOT the repo; ~/.secrets is vault-backed via 'make secrets-backup'):"
	@echo "  - Canary Mail: make backup-canary"
	@echo "  - Shottr: make backup-shottr"
	@echo "  - Transmit: Servers > Export → ~/.secrets/apps/transmit/"
	@echo "  - Raycast: Settings > Advanced > Export → ~/.secrets/apps/raycast/"
	@echo ""
	@bash scripts/audit-app-prefs.sh
	@echo ""
	@echo "Now commit: git add -A && git commit -m 'chore: backup configs'"

secrets-backup: ## Snapshot ~/.secrets into the encrypted sparseimage vault
	@bash scripts/secrets-backup.sh

secrets-mount: ## Mount the encrypted secrets sparseimage
	@bash scripts/secrets-mount.sh

secrets-pass: ## Copy the secrets vault password from Keychain
	@security find-generic-password -s DotfilesSecretsVault -a "$(USER)" -w | tr -d '\n' | pbcopy && echo "vault password → clipboard"
