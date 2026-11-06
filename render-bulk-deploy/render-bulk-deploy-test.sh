#!/bin/bash
#
# Self-check for the JSON parsing in render-bulk-deploy.

set -euo pipefail

source "$(dirname "$0")/render-bulk-deploy.sh"

failures=0

check() {
    local label=$1 expected=$2 actual=$3
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s\nexpected:\n%s\nactual:\n%s\n' "$label" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
}

# Datastores (no .service) and suspended services are dropped; the rest sort by name.
services='[
    {"service": {"id": "srv-b", "name": "beta", "type": "web_service", "suspended": "not_suspended"}},
    {"postgres": {"id": "dpg-x", "name": "db"}},
    {"service": {"id": "srv-c", "name": "gone", "type": "web_service", "suspended": "suspended"}},
    {"service": {"id": "srv-a", "name": "Alpha", "type": "static_site", "suspended": "not_suspended"}}
]'
check "parse_services" \
    "$(printf 'srv-a\tAlpha\tstatic_site\nsrv-b\tbeta\tweb_service')" \
    "$(parse_services <<< "$services")"

# The newest live deploy wins, even when a newer build is in progress or failed.
deploys='[
    {"id": "dep-4", "status": "build_in_progress", "createdAt": "2026-11-04T00:00:00Z", "commit": {"id": "ddd"}},
    {"id": "dep-3", "status": "build_failed", "createdAt": "2026-11-03T00:00:00Z", "commit": {"id": "ccc"}},
    {"id": "dep-2", "status": "live", "createdAt": "2026-11-02T00:00:00Z", "commit": {"id": "bbb"}},
    {"id": "dep-1", "status": "deactivated", "createdAt": "2026-11-01T00:00:00Z", "commit": {"id": "aaa"}}
]'
check "parse_live_commit" "bbb" "$(parse_live_commit <<< "$deploys")"

# Same, with each deploy wrapped the way the Render API returns it.
wrapped='[
    {"deploy": {"id": "dep-2", "status": "live", "createdAt": "2026-11-02T00:00:00Z", "commit": {"id": "bbb"}}, "cursor": "x"}
]'
check "parse_live_commit wrapped" "bbb" "$(parse_live_commit <<< "$wrapped")"

check "parse_live_commit none live" "" \
    "$(parse_live_commit <<< '[{"status": "build_failed", "createdAt": "2026-11-01T00:00:00Z", "commit": {"id": "aaa"}}]')"

check "parse_live_commit empty" "" "$(parse_live_commit <<< '[]')"

[ "$failures" -eq 0 ] || exit 1
echo ok
