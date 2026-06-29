.PHONY: all link unlink brew brewfile-audit macos dock terminal services restore-apps restore-canary backup backup-canary audit-apps hooks ssh-setup skills-audit skills skills-manifest secrets-backup secrets-mount secrets-pass rules-audit

all: link skills-audit brew services restore-apps dock hooks ssh-setup macos
	@echo "Full setup complete."
# macos last: defaults.sh has interactive prompts; a Ctrl-C there previously
# aborted the sequence before dock/hooks/ssh-setup could run.
# terminal is NOT in `all` (would kill parent Terminal.app shell).

restore-apps:
	@bash scripts/restore-apps.sh

restore-canary:
	@bash scripts/restore-canary-vault.sh

backup-canary:
	@bash scripts/backup-canary-vault.sh

ssh-setup:
	@bash scripts/ssh-setup.sh

# Not in `all`: network-heavy, needs gh auth + GitLab keychain after secrets restore.
projects:
	@bash/sync.sh

skills-audit:
	@bash scripts/audit-skill-licenses.sh --check

# Assert agents/AGENTS.md @-includes and agents/rules/*.md stay 1:1 in sync.
rules-audit:
	@bash scripts/audit-rules.sh

brewfile-audit:
	@bash scripts/audit-brewfile.sh --check

# Regenerate ./Skillsfile from agents/.skill-lock.json (the `bundle dump`).
skills-manifest:
	@python3 scripts/gen-skillsfile.py

# Install all global skills from the manifest (the `brew bundle`). Not in
# `make all`: needs node, git, and network access set up first.
skills: skills-manifest
	@bash Skillsfile

hooks:
	@git config --local core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "  ✓ git hooks path → .githooks/ (tracked, dotfiles-managed)"
	@git config --local diff.plist.textconv "plutil -p"
	@git config --local diff.plist.binary true
	@echo "  ✓ plist diff driver (.gitattributes wires *.plist → plist)"

link:
	@bash scripts/link.sh

unlink:
	@bash scripts/unlink.sh

brew:
	brew bundle --file=Brewfile

macos:
	@bash macos/defaults.sh

dock:
	@bash macos/dock.sh

# terminal is NOT part of `make all` because `osascript ... to quit` would
# kill the parent shell when invoked from Terminal.app. Run manually from
# iTerm / Ghostty / VS Code integrated terminal, or accept that you'll need
# to reopen Terminal.app afterwards.
terminal:
	@if [ -f apps/terminal/terminal.plist ]; then \
		osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true; \
		defaults import com.apple.Terminal apps/terminal/terminal.plist && \
			echo "  ✓ Terminal.app profiles imported (reopen Terminal to see)"; \
	else \
		echo "  - apps/terminal/terminal.plist not found; skipping"; \
	fi

services:
	@mkdir -p ~/Library/Services
	@cp -R services/*.workflow ~/Library/Services/ 2>/dev/null || true
	@echo "Automator services installed."

audit-apps:
	@bash scripts/audit-app-prefs.sh

backup:
	@echo "Backing up app configs..."
	@# Bulk `defaults`-managed apps — driven by apps.tsv. Container-copy apps
	@# (Dato, Sublime, VS Code) stay as explicit lines below.
	@while IFS=$$'\t' read -r domain label plist; do \
		case "$$domain" in ''|\#*) continue ;; esac; \
		defaults export "$$domain" "$$plist" 2>/dev/null && echo "  ✓ $$label" || true; \
	done < apps.tsv
	@cp ~/Library/Group\ Containers/group.com.sindresorhus.Dato/Library/Preferences/group.com.sindresorhus.Dato.plist apps/dato/dato.plist 2>/dev/null && echo "  ✓ Dato" || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-settings apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text settings" || true
	@rm -f "apps/sublime-text/Theme - Monokai Pro.sublime-settings" 2>/dev/null || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-keymap apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text keybindings" || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-snippet apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text snippets" || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.sublime-macro apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text macros" || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.palettes apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text palettes" || true
	@cp ~/Library/Application\ Support/Sublime\ Text/Packages/User/*.py apps/sublime-text/ 2>/dev/null && echo "  ✓ Sublime Text user plugins" || true
	@cp ~/Library/Application\ Support/Code/User/settings.json apps/vscode/settings.json 2>/dev/null && echo "  ✓ VS Code" || true
	@defaults export com.apple.dock macos/dock-backup.plist 2>/dev/null && echo "  ✓ Dock layout" || true
	@defaults export com.apple.Terminal apps/terminal/terminal.plist 2>/dev/null && echo "  ✓ Terminal.app profiles" || true
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
	@echo "  - Transmit: Servers > Export → ~/.secrets/apps/transmit/"
	@echo "  - Raycast: Settings > Advanced > Export → ~/.secrets/apps/raycast/"
	@echo ""
	@bash scripts/audit-app-prefs.sh
	@echo ""
	@echo "Now commit: git add -A && git commit -m 'chore: backup configs'"

secrets-backup:
	@bash scripts/secrets-backup.sh

secrets-mount:
	@bash scripts/secrets-mount.sh

secrets-pass:
	@security find-generic-password -s DotfilesSecretsVault -a "$(USER)" -w | tr -d '\n' | pbcopy && echo "vault password → clipboard"
