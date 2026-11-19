#!/bin/bash
#
# Self-check for the JSON parsing in heroku-bulk-deploy.

set -euo pipefail

source "$(dirname "$0")/heroku-bulk-deploy.sh"

failures=0

check() {
    local label=$1 expected=$2 actual=$3
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s\nexpected:\n%s\nactual:\n%s\n' "$label" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
}

# Never-deployed (no slug) and archived apps are dropped; the rest sort by name.
apps='[
    {"id": "b", "name": "beta", "slug_size": 10, "archived_at": null, "buildpack_provided_description": "PHP"},
    {"id": "x", "name": "empty", "slug_size": null, "archived_at": null, "buildpack_provided_description": null},
    {"id": "o", "name": "old", "slug_size": 10, "archived_at": "2026-01-01T00:00:00Z", "buildpack_provided_description": "PHP"},
    {"id": "a", "name": "Alpha", "slug_size": 10, "archived_at": null, "buildpack_provided_description": null}
]'
check "parse_apps" \
    "$(printf 'a\tAlpha\tunknown\nb\tbeta\tPHP')" \
    "$(parse_apps <<< "$apps")"

# The app itself is left out of its pipeline siblings.
pipeline='{"pipeline": {"name": "site"}, "apps": [
    {"id": "p", "name": "site"},
    {"id": "s", "name": "stage-site"}
]}'
check "parse_pipeline_apps" "$(printf 's\tstage-site')" "$(parse_pipeline_apps site <<< "$pipeline")"

[ "$failures" -eq 0 ] || exit 1
echo ok
