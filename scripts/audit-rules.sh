#!/usr/bin/env bash
# Rulebook drift guard. Asserts exact-once top-level rule links, matching loading
# classifications, loader timing, and a fail-closed nested routing inventory.
#
#   missing — referenced in AGENTS.md but not on disk
#   orphan  — on disk but not referenced in AGENTS.md
#   duplicate/misclassified — indexed more than once or under the wrong loader
#
# Exits non-zero on any mismatch. Wired via `make rules-audit`.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
AGENTS_MD="$DOTFILES/agents/AGENTS.md"
RULES_DIR="$DOTFILES/agents/rules"
INIT_SKILL="$DOTFILES/agents/skills/init-rulebook/SKILL.md"
ROUTING_RULE="$RULES_DIR/11-skill-routing.md"
ROUTING_DIR="$RULES_DIR/routing"
DESIGN_POSTURE_RULE="$RULES_DIR/10-design-posture.md"
DESIGN_UX_ROUTING_RULE="$ROUTING_DIR/design-ux.md"
DESIGN_INTERFACE_ROUTING_RULE="$ROUTING_DIR/design-interface.md"
DESIGN_SYSTEM_ROUTING_RULE="$ROUTING_DIR/design-system.md"
DEVELOPMENT_ROUTING_RULE="$ROUTING_DIR/development.md"
INTERFACE_ROUTING_DIR="$ROUTING_DIR/interface"
INTERFACE_IMPLEMENTATION_RULE="$INTERFACE_ROUTING_DIR/implementation.md"
INTERFACE_REVIEW_RULE="$INTERFACE_ROUTING_DIR/review.md"
INTERFACE_CREATIVE_RULE="$INTERFACE_ROUTING_DIR/creative.md"
INTERFACE_QUALITY_RULE="$INTERFACE_ROUTING_DIR/quality.md"
ENVIRONMENT_RULE="$RULES_DIR/22-environment.md"
ENVIRONMENT_DIR="$RULES_DIR/environment"
ATTRIBUTION_RULE="$RULES_DIR/02-attribution.md"
ATTRIBUTION_DIR="$RULES_DIR/attribution"
ATTRIBUTION_STAGING_RULE="$ATTRIBUTION_DIR/staging.md"
ATTRIBUTION_MESSAGE_RULE="$ATTRIBUTION_DIR/message.md"
ATTRIBUTION_IDENTITY_RULE="$ATTRIBUTION_DIR/identity.md"

[ -f "$AGENTS_MD" ] || { echo "not found: $AGENTS_MD" >&2; exit 1; }
[ -d "$RULES_DIR" ] || { echo "not found: $RULES_DIR" >&2; exit 1; }
[ -f "$INIT_SKILL" ] || { echo "not found: $INIT_SKILL" >&2; exit 1; }

# Indexed entries: classification plus basename for every top-level rule link.
# Keep duplicates until after validation; deduplicating first would hide drift.
indexed_entries="$(awk '
    /^## Always on[[:space:]]*$/ { section = "always"; next }
    /^## Action-gated:/ { section = "action"; next }
    /^## Activate / { section = "conditional"; next }
    /^## / { section = ""; next }
    match($0, /\(\.\/rules\/[A-Za-z0-9._-]+\.md\)/) {
        file = substr($0, RSTART + 9, RLENGTH - 10)
        print section "\t" file
    }
' "$AGENTS_MD")"
referenced_raw="$(grep -oE '\(\./rules/[A-Za-z0-9._-]+\.md\)' "$AGENTS_MD" \
    | sed -e 's#^(\./rules/##' -e 's#)$##' | sort || true)"
referenced="$(printf '%s\n' "$referenced_raw" | awk 'NF' | uniq)"
duplicates="$(printf '%s\n' "$referenced_raw" | awk 'NF' | uniq -d)"
unclassified="$(printf '%s\n' "$indexed_entries" | awk -F '\t' '$1 == "" { print $2 }')"

# On disk: basenames of agents/rules/*.md, sorted.
on_disk="$(/usr/bin/find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort -u)"

missing="$(comm -23 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"
orphan="$(comm -13 <(printf '%s\n' "$referenced") <(printf '%s\n' "$on_disk"))"

status=0
fail_contract() {
    printf '\033[31m✗ rulebook contract: %s\033[0m\n' "$1" >&2
    status=1
}

check_nested_inventory() {
    dispatcher="$1"
    directory="$2"
    prefix="$3"
    label="$4"
    [ -f "$dispatcher" ] || { fail_contract "missing $label dispatcher: $dispatcher"; return; }
    [ -d "$directory" ] || { fail_contract "missing $label reference directory: $directory"; return; }

    nested_on_disk="$(/usr/bin/find "$directory" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort -u)"
    nested_linked_raw="$(grep -oE "\\(${prefix}/[A-Za-z0-9._-]+\\.md\\)" "$dispatcher" \
        | sed -e "s#^(${prefix}/##" -e 's#)$##' | sort || true)"
    nested_linked="$(printf '%s\n' "$nested_linked_raw" | awk 'NF' | uniq)"
    nested_duplicates="$(printf '%s\n' "$nested_linked_raw" | awk 'NF' | uniq -d)"
    nested_missing="$(comm -23 <(printf '%s\n' "$nested_linked") <(printf '%s\n' "$nested_on_disk"))"
    nested_orphan="$(comm -13 <(printf '%s\n' "$nested_linked") <(printf '%s\n' "$nested_on_disk"))"

    [ -n "$nested_linked" ] || fail_contract "$label dispatcher must link at least one reference"
    [ -n "$nested_on_disk" ] || fail_contract "$label reference directory must contain Markdown files"
    [ -z "$nested_duplicates" ] || fail_contract "$label dispatcher has duplicate reference link(s): $(printf '%s' "$nested_duplicates" | tr '\n' ' ')"
    [ -z "$nested_missing" ] || fail_contract "$label dispatcher links missing reference(s): $(printf '%s' "$nested_missing" | tr '\n' ' ')"
    [ -z "$nested_orphan" ] || fail_contract "$label dispatcher has unlinked reference(s): $(printf '%s' "$nested_orphan" | tr '\n' ' ')"
}

if [ -n "$missing" ]; then
    printf '\033[31m✗ referenced in AGENTS.md but missing on disk:\033[0m\n' >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    status=1
fi
if [ -n "$orphan" ]; then
    printf '\033[31m✗ on disk but not referenced in AGENTS.md:\033[0m\n' >&2
    printf '%s\n' "$orphan" | sed 's/^/    /' >&2
    status=1
fi
if [ -n "$duplicates" ]; then
    fail_contract "duplicate top-level rule link(s): $(printf '%s' "$duplicates" | tr '\n' ' ')"
fi
if [ -n "$unclassified" ]; then
    fail_contract "top-level rule link(s) outside a recognized loading section: $(printf '%s' "$unclassified" | tr '\n' ' ')"
fi

# Loading mechanics belong to init-rulebook; membership and applicability do not.
# Backticks are literal Markdown syntax.
# shellcheck disable=SC2016
grep -Fq 'Discover every top-level `~/.agents/rules/*.md` file' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must require exhaustive top-level inventory discovery"
grep -Fq 'Loading is not applying' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must distinguish loading from applying"
grep -Fq 'Read every rule under **Always on** completely' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must eagerly load the always-on rule set"
grep -Fq 'Do not preload an **Action-gated** rule' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must defer action-gated rules until the matching operation"
grep -Fq 'Re-evaluate task-conditional sections before later requests and action gates before later operations' "$AGENTS_MD" \
    || fail_contract "AGENTS.md must re-evaluate task and action applicability as scope changes"

# Backticks are literal Markdown syntax.
# shellcheck disable=SC2016
grep -Fq 'enumerate every top-level `*.md` file' "$INIT_SKILL" \
    || fail_contract "init-rulebook must discover every top-level rule from disk"
grep -Fq 'compare the discovered inventory with the indexed inventory' "$INIT_SKILL" \
    || fail_contract "init-rulebook must compare discovered and indexed inventories"
grep -Fq 'selected count equals the successfully read count' "$INIT_SKILL" \
    || fail_contract "init-rulebook must compare selected and successfully read counts"
grep -Fq 'read every selected rule in one pass' "$INIT_SKILL" \
    || fail_contract "init-rulebook must read every selected rule completely"
grep -Fq 'loading a rule is distinct from applying it' "$INIT_SKILL" \
    || fail_contract "init-rulebook must defer applicability to the rulebook"
grep -Fq 'before acting on each later user request' "$INIT_SKILL" \
    || fail_contract "init-rulebook must re-evaluate conditions for later requests"
# Backticks are literal Markdown syntax.
# shellcheck disable=SC2016
grep -Fq 'Exclude every `Action-gated` rule from task-start selection' "$INIT_SKILL" \
    || fail_contract "init-rulebook must not preload action-gated rules"
grep -Fq 'immediately before each operation' "$INIT_SKILL" \
    || fail_contract "init-rulebook must open action gates immediately before matching operations"

if grep -Eq '[0-9]{2}-[A-Za-z0-9._-]+\.md' "$INIT_SKILL"; then
    fail_contract "init-rulebook must not contain a static top-level rule inventory"
fi

while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    declaration="$(sed -n '2,5p' "$RULES_DIR/$rule" | grep -E '^Always on\.|^Action-gated\.|^Activate |^Never do' | head -n 1 || true)"
    if [ -z "$declaration" ]; then
        fail_contract "$rule does not declare applicability near the top"
        continue
    fi
    case "$declaration" in
        "Always on."*|"Never do"*) expected_class="always" ;;
        "Action-gated."*) expected_class="action" ;;
        "Activate "*) expected_class="conditional" ;;
        *)
            fail_contract "$rule has an unrecognized applicability declaration"
            continue
            ;;
    esac
    actual_class="$(printf '%s\n' "$indexed_entries" | awk -F '\t' -v rule="$rule" '$2 == rule { print $1 }')"
    if [ "$actual_class" != "$expected_class" ]; then
        fail_contract "$rule classification mismatch: index=${actual_class:-unclassified}, declaration=$expected_class"
    fi
done <<< "$on_disk"

[ -f "$ROUTING_RULE" ] || fail_contract "missing canonical skill router: $ROUTING_RULE"
[ -d "$ROUTING_DIR" ] || fail_contract "missing routing reference directory: $ROUTING_DIR"

if [ -d "$ROUTING_DIR" ] && [ -f "$ROUTING_RULE" ]; then
    routing_on_disk="$(/usr/bin/find "$ROUTING_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort -u)"
    routing_linked_raw="$(grep -oE '\(routing/[A-Za-z0-9._-]+\.md\)' "$ROUTING_RULE" \
        | sed -e 's#^(routing/##' -e 's#)$##' | sort || true)"
    routing_linked="$(printf '%s\n' "$routing_linked_raw" | awk 'NF' | uniq)"
    routing_duplicates="$(printf '%s\n' "$routing_linked_raw" | awk 'NF' | uniq -d)"
    routing_missing="$(comm -23 <(printf '%s\n' "$routing_linked") <(printf '%s\n' "$routing_on_disk"))"
    routing_orphan="$(comm -13 <(printf '%s\n' "$routing_linked") <(printf '%s\n' "$routing_on_disk"))"
    [ -n "$routing_linked" ] || fail_contract "skill router must link at least one routing reference"
    [ -n "$routing_on_disk" ] || fail_contract "routing reference directory must contain at least one Markdown file"
    [ -z "$routing_duplicates" ] || fail_contract "duplicate routing reference link(s): $(printf '%s' "$routing_duplicates" | tr '\n' ' ')"
    [ -z "$routing_missing" ] || fail_contract "skill router links missing reference(s): $(printf '%s' "$routing_missing" | tr '\n' ' ')"
    [ -z "$routing_orphan" ] || fail_contract "skill router has unlinked reference(s): $(printf '%s' "$routing_orphan" | tr '\n' ' ')"
    grep -Fq 'Installed and third-party skill descriptions are retrieval hints' "$ROUTING_RULE" \
        || fail_contract "skill router must declare precedence over installed descriptions"
    grep -Fq 'Cross-skill references inside an installed skill are advisory only' "$ROUTING_RULE" \
        || fail_contract "skill router must fail closed on unavailable sibling-skill references"
    grep -Fq 'load multiple only for independent artifacts, in phase order' "$ROUTING_RULE" \
        || fail_contract "skill router must reserve multi-reference loading for independent artifacts"
    grep -Fq 'Non-interface planning, typed-semantic AI or explicitly requested test-first work, source review, minimalism, debugging, architecture, or skill authoring' "$ROUTING_RULE" \
        || fail_contract "development routing must preserve specialist implementation without claiming ordinary implementation"
    ! grep -Fq 'Non-interface planning or implementation' "$ROUTING_RULE" \
        || fail_contract "development routing must not load for specified implementation"
    grep -Fq 'Core workflow when no conditional route matches; no manufactured skill gate' "$ROUTING_RULE" \
        || fail_contract "core workflow must defer to matching conditional routes"

    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    routing_skill_tokens="$(grep -RhoE '`[A-Za-z0-9][A-Za-z0-9._-]*`' \
        "$ROUTING_RULE" "$ROUTING_DIR" | tr -d '`' | sort -u)"
    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    retired_skill_tokens="$(sed -n '/following skills are retired/,/^## User-invoked preferences/p' "$ROUTING_RULE" \
        | grep -oE '`[A-Za-z0-9][A-Za-z0-9._-]*`' | tr -d '`' | sort -u || true)"
    while IFS= read -r token; do
        [ -n "$token" ] || continue
        case "$token" in
            *.md) continue ;;
        esac
        if [ -f "$DOTFILES/agents/skills/$token/SKILL.md" ]; then
            continue
        fi
        if printf '%s\n' "$retired_skill_tokens" | grep -qxF "$token"; then
            continue
        fi
        fail_contract "skill router names unavailable, non-retired skill: $token"
    done <<< "$routing_skill_tokens"

    grep -Fq '## User-invoked preferences' "$ROUTING_RULE" \
        || fail_contract "skill router must declare a User-invoked preferences section"
    grep -Fq 'never edit installed skill files to impose local routing policy' "$ROUTING_RULE" \
        || fail_contract "skill router must keep local preferences out of installed skill files"
    user_invoked_section="$(awk '
        /^## User-invoked preferences[[:space:]]*$/ { p=1; next }
        /^## / { p=0 }
        p { print }
    ' "$ROUTING_RULE")"
    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    user_invoked_tokens="$(printf '%s\n' "$user_invoked_section" \
        | grep -oE '`[A-Za-z0-9][A-Za-z0-9._-]*`' | tr -d '`' | awk 'NF && !x[$0]++')"
    [ -n "$user_invoked_tokens" ] || fail_contract "User-invoked preferences section listed no skill names"
    while IFS= read -r token; do
        [ -n "$token" ] || continue
        case "$token" in
            *.md) continue ;;
        esac
        if [ ! -f "$DOTFILES/agents/skills/$token/SKILL.md" ]; then
            fail_contract "user-invoked preference is not installed: $token"
        fi
    done <<< "$user_invoked_tokens"
fi

check_nested_inventory "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_ROUTING_DIR" "interface" "interface routing"
check_nested_inventory "$ENVIRONMENT_RULE" "$ENVIRONMENT_DIR" "environment" "environment routing"
check_nested_inventory "$ATTRIBUTION_RULE" "$ATTRIBUTION_DIR" "attribution" "attribution routing"

[ -f "$DESIGN_POSTURE_RULE" ] || fail_contract "missing always-on design posture: $DESIGN_POSTURE_RULE"
[ -f "$DESIGN_UX_ROUTING_RULE" ] || fail_contract "missing UX design routing contract: $DESIGN_UX_ROUTING_RULE"
[ -f "$DESIGN_INTERFACE_ROUTING_RULE" ] || fail_contract "missing interface design routing contract: $DESIGN_INTERFACE_ROUTING_RULE"
[ -f "$DESIGN_SYSTEM_ROUTING_RULE" ] || fail_contract "missing system/content design routing contract: $DESIGN_SYSTEM_ROUTING_RULE"
[ -f "$DEVELOPMENT_ROUTING_RULE" ] || fail_contract "missing development routing contract: $DEVELOPMENT_ROUTING_RULE"
if [ -f "$DESIGN_POSTURE_RULE" ] \
    && [ -f "$DESIGN_UX_ROUTING_RULE" ] \
    && [ -f "$DESIGN_INTERFACE_ROUTING_RULE" ] \
    && [ -f "$DESIGN_SYSTEM_ROUTING_RULE" ] \
    && [ -f "$DEVELOPMENT_ROUTING_RULE" ]; then
    grep -Fq '## Design-led priority' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must define design-led priority"
    grep -Fq '## UX Architect' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must define the UX Architect role"
    grep -Fq '## Visual Designer' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must define the Visual Designer role"
    grep -Fq '## Design Engineer' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must define the Design Engineer role"
    grep -Fq '## Completion standard' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must define a completion standard"
    grep -Fq 'Completion is mode-specific.' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design completion must remain mode-specific"
    grep -Fq 'do not manufacture visual treatment for a nonvisual deliverable' "$DESIGN_POSTURE_RULE" \
        || fail_contract "nonvisual design modes must not be forced through visual treatment"
    grep -Fq 'Repository and Git mechanics are silent support' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must keep repository and Git mechanics supporting"
    grep -Fq 'it owns its modes, artifacts, sequence, and quality gates' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must delegate procedural ownership to the selected design reference"
    grep -Fq 'first-use, returning-user, permissions, destructive confirmation' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must retain the complete material-state guardrail"
    ! grep -Fq 'routing/design.md' "$DESIGN_POSTURE_RULE" \
        || fail_contract "design posture must not force the retired umbrella design router"

    grep -Fq '## Select the UX mode' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must select a mode"
    grep -Fq '## UX operating sequence' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must define its operating sequence"
    grep -Fq '`user-research`' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must retain research ownership"
    grep -Fq '`design-handoff`' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must retain handoff ownership"
    grep -Fq '`prototype`' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must retain prototype ownership"
    grep -Fq 'selected only from this reference' "$DESIGN_UX_ROUTING_RULE" \
        || fail_contract "UX design routing must be the sole prototype selector"

    grep -Fq '## Select the interface job' "$DESIGN_INTERFACE_ROUTING_RULE" \
        || fail_contract "interface dispatcher must select one artifact-led job"
    grep -Fq 'A complete review also loads the [shared quality contract](quality.md)' "$INTERFACE_REVIEW_RULE" \
        || fail_contract "complete interface review must retain the shared quality gate"
    grep -Fq '[shared quality](quality.md)' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must load the shared quality gate"
    grep -Fq '[Specialized creative](interface/creative.md), which loads the implementation contract' "$DESIGN_INTERFACE_ROUTING_RULE" \
        || fail_contract "specialized creative routing must retain the implementation quality contract"
    grep -Fq '## Interface operating sequence' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must define its operating sequence"
    grep -Fq '## Aesthetic quality gate' "$INTERFACE_QUALITY_RULE" \
        || fail_contract "shared interface quality must define the aesthetic gate"
    grep -Fq '## Frontend art direction' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must define product-specific art direction"
    grep -Fq 'hide the logo and product copy' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "frontend art direction must retain its specificity test"
    grep -Fq 'indiscriminate card grids, excessive pills, gratuitous gradients or glow' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must retain concrete anti-slop guardrails"
    grep -Fq '## Designer-eye pass' "$INTERFACE_QUALITY_RULE" \
        || fail_contract "shared interface quality must define the rendered designer-eye pass"
    grep -Fq '## Frontend pressure cases' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must retain frontend pressure cases"
    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    grep -Fq '| Review UI changes at a Git fixed point | `better-interface` |' "$INTERFACE_REVIEW_RULE" \
        || fail_contract "interface design routing must keep fixed-point UI review design-owned"
    grep -Fq 'Use the gate internally; do not emit a scored table unless the user requests one.' "$INTERFACE_QUALITY_RULE" \
        || fail_contract "interface design routing must apply its quality gate without forcing scorecard output"
    grep -Fq '[Frontend verification](../../24-frontend-verification.md)' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface design routing must link its rendered verification procedure"
    grep -Fq '[Design posture](../../10-design-posture.md)' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface design routing must source material states from design posture"
    grep -Fq 'Applied screen copy and typography stay in interface review' "$DESIGN_INTERFACE_ROUTING_RULE" \
        || fail_contract "interface design routing must own applied screen copy and typography"
    grep -Fq 'findings and remediation guidance for review, or an applied change with in-context verification' "$INTERFACE_REVIEW_RULE" \
        || fail_contract "interface design routing must define an applied artifact for narrow implementation"
    grep -Fq 'applied screen copy or typography' "$ROUTING_RULE" \
        || fail_contract "skill router must send applied screen copy and typography to interface routing"
    grep -Fq 'reusable type/copy authorities, font research, or conversion copy' "$ROUTING_RULE" \
        || fail_contract "skill router must keep reusable type/copy authorities on system/content routing"
    [ "$(grep -h -o '`frontend-design`' "$DESIGN_UX_ROUTING_RULE" "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_ROUTING_DIR"/*.md "$DESIGN_SYSTEM_ROUTING_RULE" | wc -l | tr -d '[:space:]')" -eq 1 ] \
        || fail_contract "design routing must declare frontend-design in one canonical row"
    [ "$(grep -h -o '`impeccable`' "$DESIGN_UX_ROUTING_RULE" "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_ROUTING_DIR"/*.md "$DESIGN_SYSTEM_ROUTING_RULE" | wc -l | tr -d '[:space:]')" -eq 1 ] \
        || fail_contract "design routing must declare impeccable in one canonical row"
    ! grep -Fq '| Holistic rendered-interface review | `better-interface` |' "$INTERFACE_REVIEW_RULE" \
        || fail_contract "design routing must not duplicate the holistic review mode"
    ! grep -Fq 'Sleek and modern means' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "design routing must keep modern-style guidance in the pressure-case contract"
    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    grep -Fq 'including Git-fixed-point UI reviews' "$INTERFACE_REVIEW_RULE" \
        || fail_contract "canonical routing must keep UI fixed-point reviews design-owned"
    grep -Fq '## Design systems and tokens' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must retain design-system ownership"
    grep -Fq '## Typography and writing' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must retain typography and writing ownership"
    grep -Fq 'A one-off content change stays with its narrow consumer' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must not expand local writing into system work"
    grep -Fq 'Applied screen copy or typography belongs to the interface design route' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must send applied screen copy and typography to the interface route"
    grep -Fq 'Use `design-system` for reusable type/copy authorities' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must assign reusable type/copy authorities an owner"
    ! grep -Fq 'Use `better-typography` for rendered interface text' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must not own applied screen typography"
    ! grep -Fq 'Use `better-writing` when copy helps someone operate a product' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must not own applied screen copy"
    grep -Fq '[Frontend verification](../24-frontend-verification.md)' "$DESIGN_SYSTEM_ROUTING_RULE" \
        || fail_contract "system/content routing must link rendered verification when applicable"
    grep -Fq '| Design request | Primary owner | Required artifact |' "$INTERFACE_IMPLEMENTATION_RULE" \
        || fail_contract "interface implementation must define owner and artifact rows"
    [ "$(grep -h -c '^Required artifact:' "$INTERFACE_REVIEW_RULE" "$INTERFACE_CREATIVE_RULE" | awk -F: '{ total += $NF } END { print total + 0 }')" -eq 2 ] \
        || fail_contract "interface review and creative routing must each define an artifact"
    [ "$(grep -c '^Required artifact:' "$DESIGN_SYSTEM_ROUTING_RULE")" -eq 2 ] \
        || fail_contract "system/content routing must define system and content artifacts"
    # Backticks are literal Markdown syntax.
    # shellcheck disable=SC2016
    grep -Fq 'sequence a `better-interface` pass for visual and experiential quality; source review does not substitute for rendered verification' "$DEVELOPMENT_ROUTING_RULE" \
        || fail_contract "development routing must preserve design ownership for UI diff review"
    grep -Fq 'Load this reference for non-interface planning, typed-semantic AI or explicitly requested test-first work, source review' "$DEVELOPMENT_ROUTING_RULE" \
        || fail_contract "development routing must preserve its specialist triggers without claiming ordinary implementation"
    ! grep -Fq '`prototype`' "$DEVELOPMENT_ROUTING_RULE" \
        || fail_contract "development routing must not own prototype"
    grep -Fq 'owned by [UX routing](design-ux.md)' "$DEVELOPMENT_ROUTING_RULE" \
        || fail_contract "development routing must point prototype ownership at UX routing"
fi

if [ -f "$ENVIRONMENT_RULE" ] && [ -d "$ENVIRONMENT_DIR" ]; then
    grep -Fq 'Load task-touched ecosystems in one pass' "$ENVIRONMENT_RULE" \
        || fail_contract "environment dispatcher must load task-touched runtimes in one pass"
    grep -Fq 'load every relevant ecosystem only for repo-wide setup or cross-runtime work' "$ENVIRONMENT_RULE" \
        || fail_contract "environment dispatcher must reserve all-runtime loading for cross-runtime work"
    grep -Fq 'With no match, load none' "$ENVIRONMENT_RULE" \
        || fail_contract "environment dispatcher must stop after detection for non-ecosystem code"
    grep -Fq 'Add monorepo only when workspace configuration or package layout proves it' "$ENVIRONMENT_RULE" \
        || fail_contract "environment dispatcher must gate monorepo rules on repository evidence"
    # Match a literal Markdown contract, not a shell path.
    # shellcheck disable=SC2088
    grep -Fq '~/.local/bin/node-stable' "$ENVIRONMENT_DIR/node.md" \
        || fail_contract "Node routing must retain the stable binary contract"
    grep -Fq 'Keep one lockfile' "$ENVIRONMENT_DIR/node.md" \
        || fail_contract "Node routing must reject conflicting lockfiles"
    grep -Fq 'prefer `uv` when `uv.lock` exists' "$ENVIRONMENT_DIR/python.md" \
        || fail_contract "Python routing must preserve uv detection"
    grep -Fq 'Never edit `Cargo.lock` by hand' "$ENVIRONMENT_DIR/rust.md" \
        || fail_contract "Rust routing must preserve Cargo lock ownership"
    grep -Fq 'Never edit `go.sum` by hand' "$ENVIRONMENT_DIR/go.md" \
        || fail_contract "Go routing must preserve module checksum ownership"
    grep -Fq 'Respect the task runner' "$ENVIRONMENT_DIR/monorepo.md" \
        || fail_contract "monorepo routing must preserve task-runner ownership"
fi

if [ -f "$ATTRIBUTION_RULE" ] && [ -d "$ATTRIBUTION_DIR" ]; then
    grep -Fq 'A complete local commit loads all three in that order' "$ATTRIBUTION_RULE" \
        || fail_contract "attribution dispatcher must preserve commit phase order"
    grep -Fq 'a planned commit does not preload a later contract' "$ATTRIBUTION_RULE" \
        || fail_contract "attribution dispatcher must defer later commit operations"
    grep -Fq 'A pre-staged index requires an explicit commit pathspec' "$ATTRIBUTION_STAGING_RULE" \
        || fail_contract "attribution staging must protect unrelated staged changes"
    grep -Fq 'exactly one semantically appropriate Unicode emoji' "$ATTRIBUTION_MESSAGE_RULE" \
        || fail_contract "commit messages must retain the single Unicode emoji contract"
    grep -Fq 'Never add attribution trailers or tool branding' "$ATTRIBUTION_MESSAGE_RULE" \
        || fail_contract "commit messages must reject attribution trailers"
    grep -Fq 'footer explaining impact and migration' "$ATTRIBUTION_MESSAGE_RULE" \
        || fail_contract "breaking-change footers must explain impact and migration"
    grep -Fq "GitHub's Contributors graph" "$ATTRIBUTION_MESSAGE_RULE" \
        || fail_contract "trailer rationale must stay with the message contract"
    grep -Fq 'The effective repository fields are authoritative' "$ATTRIBUTION_IDENTITY_RULE" \
        || fail_contract "identity must honor effective repository configuration"
    grep -Fq 'Identity preservation is an integration invariant' "$ATTRIBUTION_IDENTITY_RULE" \
        || fail_contract "integration must retain effective identity"
    grep -Fq 'If signing is configured or required but fails' "$ATTRIBUTION_IDENTITY_RULE" \
        || fail_contract "signing failure must stop integration"
fi

grep -Fq 'Before handing work back after branch, worktree, integration, PR, merge, or cleanup work:' "$RULES_DIR/07-worktree-lifecycle.md" \
    || fail_contract "lifecycle handoff must match the index action gate"

word_count() {
    wc -w < "$1" | tr -d '[:space:]'
}

check_path_budget() {
    local label="$1"
    local budget="$2"
    local words=0
    shift 2

    for path in "$@"; do
        [ -f "$path" ] || return
        words=$((words + $(word_count "$path")))
    done
    if [ "$words" -gt "$budget" ]; then
        fail_contract "$label selected path is ${words} words; budget is ${budget}"
    fi
}

ALWAYS_ON_WORD_MAX=3429
ROUTER_WORD_MAX=650
ENVIRONMENT_MONOLITH_WORDS=382
ATTRIBUTION_MONOLITH_WORDS=1752
INTERFACE_IMPLEMENTATION_PREVIOUS=1202
INTERFACE_NARROW_REVIEW_PREVIOUS=410
INTERFACE_COMPLETE_REVIEW_PREVIOUS=1452
INTERFACE_CREATIVE_PREVIOUS=1401
DESIGN_UX_WORD_MAX=400
DESIGN_INTERFACE_WORD_MAX=200
INTERFACE_IMPLEMENTATION_WORD_MAX=650
INTERFACE_REVIEW_WORD_MAX=300
INTERFACE_CREATIVE_WORD_MAX=250
INTERFACE_QUALITY_WORD_MAX=450
DESIGN_SYSTEM_WORD_MAX=400
ENVIRONMENT_DISPATCHER_WORD_MAX=180
ENVIRONMENT_NODE_WORD_MAX=140
ENVIRONMENT_RUNTIME_WORD_MAX=60
ENVIRONMENT_MONOREPO_WORD_MAX=150
ATTRIBUTION_DISPATCHER_WORD_MAX=160
ATTRIBUTION_STAGING_WORD_MAX=150
ATTRIBUTION_MESSAGE_WORD_MAX=700
ATTRIBUTION_IDENTITY_WORD_MAX=650

always_words="$(word_count "$AGENTS_MD")"
while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    always_words=$((always_words + $(word_count "$RULES_DIR/$rule")))
done < <(printf '%s\n' "$indexed_entries" | awk -F '\t' '$1 == "always" { print $2 }')
if [ "$always_words" -gt "$ALWAYS_ON_WORD_MAX" ]; then
    fail_contract "always-on kernel is ${always_words} words; budget is ${ALWAYS_ON_WORD_MAX}"
fi

if [ -f "$ROUTING_RULE" ]; then
    router_words="$(word_count "$ROUTING_RULE")"
    if [ "$router_words" -gt "$ROUTER_WORD_MAX" ]; then
        fail_contract "skill router is ${router_words} words; budget is ${ROUTER_WORD_MAX}"
    fi
fi

for route_budget in \
    "$DESIGN_UX_ROUTING_RULE:$DESIGN_UX_WORD_MAX" \
    "$DESIGN_INTERFACE_ROUTING_RULE:$DESIGN_INTERFACE_WORD_MAX" \
    "$INTERFACE_IMPLEMENTATION_RULE:$INTERFACE_IMPLEMENTATION_WORD_MAX" \
    "$INTERFACE_REVIEW_RULE:$INTERFACE_REVIEW_WORD_MAX" \
    "$INTERFACE_CREATIVE_RULE:$INTERFACE_CREATIVE_WORD_MAX" \
    "$INTERFACE_QUALITY_RULE:$INTERFACE_QUALITY_WORD_MAX" \
    "$DESIGN_SYSTEM_ROUTING_RULE:$DESIGN_SYSTEM_WORD_MAX"; do
    route="${route_budget%:*}"
    budget="${route_budget##*:}"
    [ -f "$route" ] || continue
    route_words="$(word_count "$route")"
    if [ "$route_words" -gt "$budget" ]; then
        fail_contract "$(basename "$route") is ${route_words} words; budget is ${budget}"
    fi
done

for route_budget in \
    "$ENVIRONMENT_RULE:$ENVIRONMENT_DISPATCHER_WORD_MAX" \
    "$ENVIRONMENT_DIR/node.md:$ENVIRONMENT_NODE_WORD_MAX" \
    "$ENVIRONMENT_DIR/python.md:$ENVIRONMENT_RUNTIME_WORD_MAX" \
    "$ENVIRONMENT_DIR/rust.md:$ENVIRONMENT_RUNTIME_WORD_MAX" \
    "$ENVIRONMENT_DIR/go.md:$ENVIRONMENT_RUNTIME_WORD_MAX" \
    "$ENVIRONMENT_DIR/monorepo.md:$ENVIRONMENT_MONOREPO_WORD_MAX" \
    "$ATTRIBUTION_RULE:$ATTRIBUTION_DISPATCHER_WORD_MAX" \
    "$ATTRIBUTION_STAGING_RULE:$ATTRIBUTION_STAGING_WORD_MAX" \
    "$ATTRIBUTION_MESSAGE_RULE:$ATTRIBUTION_MESSAGE_WORD_MAX" \
    "$ATTRIBUTION_IDENTITY_RULE:$ATTRIBUTION_IDENTITY_WORD_MAX"; do
    route="${route_budget%:*}"
    budget="${route_budget##*:}"
    [ -f "$route" ] || continue
    route_words="$(word_count "$route")"
    if [ "$route_words" -gt "$budget" ]; then
        fail_contract "$(basename "$route") is ${route_words} words; budget is ${budget}"
    fi
done

# Each common selected path must remain smaller than its former monolith.
check_path_budget "Node monorepo environment" "$((ENVIRONMENT_MONOLITH_WORDS - 1))" \
    "$ENVIRONMENT_RULE" "$ENVIRONMENT_DIR/node.md" "$ENVIRONMENT_DIR/monorepo.md"
check_path_budget "Python environment" "$((ENVIRONMENT_MONOLITH_WORDS - 1))" \
    "$ENVIRONMENT_RULE" "$ENVIRONMENT_DIR/python.md"
check_path_budget "all-runtime environment" "$((ENVIRONMENT_MONOLITH_WORDS - 1))" \
    "$ENVIRONMENT_RULE" "$ENVIRONMENT_DIR/node.md" "$ENVIRONMENT_DIR/python.md" \
    "$ENVIRONMENT_DIR/rust.md" "$ENVIRONMENT_DIR/go.md" "$ENVIRONMENT_DIR/monorepo.md"
check_path_budget "interface implementation" "$((INTERFACE_IMPLEMENTATION_PREVIOUS - 1))" \
    "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_IMPLEMENTATION_RULE" "$INTERFACE_QUALITY_RULE"
check_path_budget "narrow interface review" "$((INTERFACE_NARROW_REVIEW_PREVIOUS - 1))" \
    "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_REVIEW_RULE"
check_path_budget "complete interface review" "$((INTERFACE_COMPLETE_REVIEW_PREVIOUS - 1))" \
    "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_REVIEW_RULE" "$INTERFACE_QUALITY_RULE"
check_path_budget "specialized interface creative" "$((INTERFACE_CREATIVE_PREVIOUS - 1))" \
    "$DESIGN_INTERFACE_ROUTING_RULE" "$INTERFACE_CREATIVE_RULE" "$INTERFACE_IMPLEMENTATION_RULE" "$INTERFACE_QUALITY_RULE"
check_path_budget "complete local commit" "$((ATTRIBUTION_MONOLITH_WORDS - 1))" \
    "$ATTRIBUTION_RULE" "$ATTRIBUTION_STAGING_RULE" "$ATTRIBUTION_MESSAGE_RULE" "$ATTRIBUTION_IDENTITY_RULE"

if [ "$status" -eq 0 ]; then
    bash "$DOTFILES/scripts/test-agent-terminal-integration.sh" || status=1
fi

if [ "$status" -eq 0 ]; then
    count="$(printf '%s\n' "$on_disk" | grep -c .)"
    printf '\033[32m  ✓\033[0m rulebook in sync (%s rules, %s always-on words; design: UX %s, interface %s + %s/%s/%s, system/content %s; environment %s; attribution %s)\n' \
        "$count" \
        "$always_words" \
        "$(word_count "$DESIGN_UX_ROUTING_RULE")" \
        "$(word_count "$DESIGN_INTERFACE_ROUTING_RULE")" \
        "$(word_count "$INTERFACE_IMPLEMENTATION_RULE")" \
        "$(word_count "$INTERFACE_REVIEW_RULE")" \
        "$(word_count "$INTERFACE_CREATIVE_RULE")" \
        "$(word_count "$DESIGN_SYSTEM_ROUTING_RULE")" \
        "$(word_count "$ENVIRONMENT_RULE")" \
        "$(word_count "$ATTRIBUTION_RULE")"
fi

exit "$status"
