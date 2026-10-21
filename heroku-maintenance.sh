#!/bin/bash
#
# heroku-maintenance — toggle maintenance mode on every running PHP app on Heroku.
#
#   heroku-maintenance [on|off] [--dry-run]
#
#   heroku-maintenance               -> maintenance on for every running PHP app
#   heroku-maintenance off           -> maintenance off for the same apps
#   heroku-maintenance --dry-run     -> list the apps that would change, change nothing
#
# "Running" means the app has at least one dyno. "PHP" means Heroku detected PHP on the
# app's last build; most apps have no buildpack set and rely on that detection.
# Maintenance mode leaves dynos up, so `off` finds the same apps that `on` changed.

set -euo pipefail

HEROKU=/opt/homebrew/bin/heroku

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [on|off] [--dry-run]

  on         turn maintenance mode on (default)
  off        turn maintenance mode off
  --dry-run  list the apps that would change without changing them
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

all_app_names() {
    "$HEROKU" apps --all --json | jq -r '.[].name'
}

has_dynos() {
    local app=$1
    [[ $("$HEROKU" ps -a "$app" --json | jq 'length') -gt 0 ]]
}

# Print "<is php> <maintenance enabled>", e.g. "true false". The detected runtime is a
# comma-separated list such as "PHP,Node.js,Multi-procfile".
php_and_maintenance() {
    local app=$1
    "$HEROKU" apps:info -a "$app" --json | jq -r '.app
        | "\((.buildpack_provided_description // "") | split(",") | index("PHP") != null) \(.maintenance)"'
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

    [[ -x $HEROKU ]] || die "heroku CLI not found at $HEROKU (brew install heroku/brew/heroku)"
    command -v jq >/dev/null || die "jq is required"
    "$HEROKU" auth:whoami >/dev/null 2>&1 || die "not logged in; run: heroku login"

    local want_enabled=false
    [[ $mode == on ]] && want_enabled=true

    local apps
    apps=$(all_app_names)

    local changed=0 skipped=0 failed=0
    local app is_php current
    for app in $apps; do
        has_dynos "$app" || continue

        read -r is_php current <<<"$(php_and_maintenance "$app")"
        [[ $is_php == true ]] || continue

        if [[ $current == "$want_enabled" ]]; then
            echo "  $app: already $mode"
            skipped=$((skipped + 1))
            continue
        fi

        if $dry_run; then
            echo "  $app: would turn $mode"
            changed=$((changed + 1))
        elif "$HEROKU" "maintenance:$mode" -a "$app" >/dev/null 2>&1; then
            echo "  $app: $mode"
            changed=$((changed + 1))
        else
            echo "  $app: FAILED" >&2
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
