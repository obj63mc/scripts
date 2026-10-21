#!/bin/bash
#
# render-maintenance — toggle maintenance mode on a fixed list of Render services.
#
#   render-maintenance [on|off] [--dry-run]
#
#   render-maintenance               -> maintenance on for every service in SERVICES
#   render-maintenance off           -> maintenance off for the same services
#   render-maintenance --dry-run     -> list the services that would change, change nothing
#
# Edit SERVICES below to add or remove services. Each entry is "<service id> <label>";
# the label is only used in output.

set -euo pipefail

RENDER=/opt/homebrew/bin/render

SERVICES=(
    "srv-cv8rlltumphs73dcdcbg Gallo-Brand-Standards"
    "srv-cu82orlds78s738lu0pg Cigar-World"
    "srv-d4sp9tccjiac739oi59g STGEdu-staging"
    "srv-d7j8q567r5hc73b1blj0 tobacco-reviews"
    "srv-d86unarbc2fs73befjm0 soonhari"
)

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [on|off] [--dry-run]

  on         turn maintenance mode on (default)
  off        turn maintenance mode off
  --dry-run  list the services that would change without changing them
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Print "<id> <true|false>" for every service in the active workspace.
maintenance_states() {
    "$RENDER" services --output json --confirm \
        | jq -r '.[].service | select(. != null) | "\(.id) \(.serviceDetails.maintenanceMode.enabled // false)"'
}

main() {
    local mode=on dry_run=false

    for arg in "$@"; do
        case $arg in
            on|off)    mode=$arg ;;
            --dry-run) dry_run=true ;;
            *)         usage ;;
        esac
    done

    [[ -x $RENDER ]] || die "render CLI not found at $RENDER (brew install render)"
    command -v jq >/dev/null || die "jq is required"
    "$RENDER" whoami --output json >/dev/null 2>&1 || die "not logged in; run: render login"

    local want_enabled=false
    [[ $mode == on ]] && want_enabled=true

    local states
    states=$(maintenance_states)

    local changed=0 skipped=0 failed=0
    local entry id label current
    for entry in "${SERVICES[@]}"; do
        id=${entry%% *}
        label=${entry#* }
        current=$(awk -v id="$id" '$1 == id { print $2 }' <<<"$states")

        if [[ -z $current ]]; then
            echo "  $label ($id): not found in the active workspace" >&2
            failed=$((failed + 1))
            continue
        fi

        if [[ $current == "$want_enabled" ]]; then
            echo "  $label: already $mode"
            skipped=$((skipped + 1))
            continue
        fi

        if $dry_run; then
            echo "  $label: would turn $mode"
            changed=$((changed + 1))
        elif "$RENDER" services update "$id" --maintenance-mode="$want_enabled" \
                --output json --confirm >/dev/null; then
            echo "  $label: $mode"
            changed=$((changed + 1))
        else
            echo "  $label: FAILED" >&2
            failed=$((failed + 1))
        fi
    done

    local note=""
    $dry_run && note="  (dry run)"
    echo
    echo "changed: $changed  already $mode: $skipped  failed: $failed$note"
    [[ $failed -eq 0 ]]
}

main "$@"
