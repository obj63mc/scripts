#!/bin/bash
#
# render-bulk-deploy — tick the Render services you want, then redeploy each one.
#
#   render-bulk-deploy            -> list services in the active workspace, pick, deploy
#   render-bulk-deploy --wait     -> same, but wait for each deploy to finish before the next
#   render-bulk-deploy --dry-run  -> pick, then print the commit each service would get
#
# Every deploy uses the commit that's live on the service right now and clears the build
# cache first, so it's a full rebuild of what's already running.
#
# Keys: up/down or j/k move, space toggles, a toggles all, enter deploys, q quits.
# A failed deploy doesn't stop the rest; the summary lists each result and the exit code
# is 1 if any failed.

set -euo pipefail

RENDER=/opt/homebrew/bin/render

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [--wait] [--dry-run]

  --wait     wait for each deploy to finish and count a failed build as a failure
  --dry-run  show the commit each picked service would deploy, deploy nothing
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Read `render services --output json` on stdin. Print "<id>\t<name>\t<type>" for each
# service that isn't suspended, sorted by name. Datastores have no .service and are skipped.
parse_services() {
    jq -r '
        [.[].service | select(. != null) | select(.suspended != "suspended")]
        | sort_by(.name | ascii_downcase)[]
        | [.id, .name, .type] | @tsv'
}

# Read `render deploys list --output json` on stdin. Print the commit of the newest deploy
# whose status is "live", or nothing if there isn't one.
parse_live_commit() {
    jq -r '
        [.[] | (.deploy // .) | select(.status == "live")]
        | sort_by(.createdAt) | last
        | .commit.id // empty'
}

live_commit() {
    "$RENDER" deploys list "$1" --output json --confirm | parse_live_commit
}

restore_terminal() {
    { tput cnorm; tput rmcup; } > /dev/tty
    stty echo < /dev/tty
}

# Checkbox picker over LABELS. Leaves the chosen indexes in SELECTED.
pick() {
    local count=${#LABELS[@]} cursor=0 top=0 rows key i mark n
    local checked=()
    for ((i = 0; i < count; i++)); do checked[i]=0; done

    { tput smcup; tput civis; } > /dev/tty
    trap restore_terminal EXIT
    trap 'exit 130' INT

    while true; do
        n=0
        for ((i = 0; i < count; i++)); do n=$((n + checked[i])); done

        # header (2) + blank (1) + footer (1) take 4 lines
        rows=$(($(tput lines) - 4))
        if ((rows < 1)); then rows=1; fi
        if ((cursor < top)); then top=$cursor; fi
        if ((cursor >= top + rows)); then top=$((cursor - rows + 1)); fi

        {
            printf '\033[H\033[1m%s\033[0m\033[K\n' "Render services"
            printf '\033[2m↑/↓ move  space toggle  a all  enter deploy  q quit\033[0m\033[K\n\033[K\n'
            for ((i = top; i < count && i < top + rows; i++)); do
                mark=' '
                if [ "${checked[i]}" = 1 ]; then mark=x; fi
                if ((i == cursor)); then
                    printf '\033[7m> [%s] %s\033[0m\033[K\n' "$mark" "${LABELS[i]}"
                else
                    printf '  [%s] %s\033[K\n' "$mark" "${LABELS[i]}"
                fi
            done
            printf '%d of %d selected\033[K\033[J' "$n" "$count"
        } > /dev/tty

        IFS= read -rsn1 key < /dev/tty
        # Arrow keys arrive as ESC [ A / ESC [ B.
        if [ "$key" = $'\033' ]; then read -rsn2 key < /dev/tty; fi

        case $key in
            '[A' | k) if ((cursor > 0)); then cursor=$((cursor - 1)); fi ;;
            '[B' | j) if ((cursor < count - 1)); then cursor=$((cursor + 1)); fi ;;
            ' ') checked[cursor]=$((1 - checked[cursor])) ;;
            a)
                mark=1
                if ((n == count)); then mark=0; fi
                for ((i = 0; i < count; i++)); do checked[i]=$mark; done
                ;;
            '') break ;;
            q) exit 0 ;;
        esac
    done

    restore_terminal
    trap - EXIT INT

    # Enter with nothing ticked means "just the row under the cursor".
    if ((n == 0)); then checked[cursor]=1; fi
    SELECTED=()
    for ((i = 0; i < count; i++)); do
        if [ "${checked[i]}" = 1 ]; then SELECTED+=("$i"); fi
    done
}

# Deploy service $1 at commit $2 with a cleared build cache. $3 is "true" to wait.
deploy() {
    local args=(deploys create "$1" --commit "$2" --clear-cache --confirm --output text)
    if [ "$3" = true ]; then args+=(--wait); fi
    "$RENDER" "${args[@]}"
}

main() {
    local wait=false dry_run=false arg
    for arg in "$@"; do
        case $arg in
            --wait) wait=true ;;
            --dry-run) dry_run=true ;;
            *) usage ;;
        esac
    done

    [ -x "$RENDER" ] || die "render CLI not found at $RENDER (brew install render)"
    command -v jq > /dev/null || die "jq is required"
    "$RENDER" whoami --output json > /dev/null 2>&1 || die "not logged in; run: render login"

    IDS=() NAMES=() LABELS=()
    local id name type
    while IFS=$'\t' read -r id name type; do
        IDS+=("$id")
        NAMES+=("$name")
        LABELS+=("$name  ($type)")
    done < <("$RENDER" services --output json --confirm | parse_services)
    [ ${#IDS[@]} -gt 0 ] || die "no active services in the current workspace"

    pick

    local i commit summary='' failed=0
    for i in "${SELECTED[@]}"; do
        id=${IDS[i]}
        name=${NAMES[i]}
        printf '\n\033[1m==> %s\033[0m\n' "$name"

        commit=$(live_commit "$id") || commit=''
        if [ -z "$commit" ]; then
            echo "no live commit found for $id" >&2
            summary+=$'\033[31m✗\033[0m '"$name (no live commit)"$'\n'
            failed=$((failed + 1))
            continue
        fi

        if $dry_run; then
            echo "would deploy $commit with a cleared build cache"
            summary+="  $name ${commit:0:7}"$'\n'
        elif deploy "$id" "$commit" "$wait"; then
            summary+=$'\033[32m✓\033[0m '"$name ${commit:0:7}"$'\n'
        else
            summary+=$'\033[31m✗\033[0m '"$name ${commit:0:7}"$'\n'
            failed=$((failed + 1))
        fi
    done

    local note=''
    if $dry_run; then note=' (dry run)'; fi
    printf '\n\033[1mSummary%s\033[0m\n%s' "$note" "$summary"
    [ "$failed" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
