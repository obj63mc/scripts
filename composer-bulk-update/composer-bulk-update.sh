#!/bin/bash
#
# composer-bulk-update — tick the subfolders you want, then run `composer update` in each.
#
#   composer-bulk-update          -> list ./*/ folders that have a composer.json, pick, update
#   composer-bulk-update ~/Sites  -> same, for another directory
#
# Keys: up/down or j/k move, space toggles, a toggles all, enter runs, q quits.
# Updates run one at a time with composer's output shown live. A failed update doesn't stop
# the rest; the summary lists each result and the exit code is 1 if any failed.

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [dir]

  dir  folder whose immediate subfolders are scanned for composer.json (default: current dir)
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Print each immediate subfolder of $1 that has a composer.json, sorted.
find_projects() {
    local dir
    for dir in "$1"/*/; do
        if [ -f "$dir/composer.json" ]; then
            echo "${dir%/}"
        fi
    done
}

restore_terminal() {
    { tput cnorm; tput rmcup; } > /dev/tty
    stty echo < /dev/tty
}

# Checkbox picker over PROJECTS. Leaves the chosen paths in SELECTED.
pick() {
    local count=${#PROJECTS[@]} cursor=0 top=0 rows key i mark n
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
            printf '\033[H\033[1m%s\033[0m\033[K\n' "$ROOT"
            printf '\033[2m↑/↓ move  space toggle  a all  enter update  q quit\033[0m\033[K\n\033[K\n'
            for ((i = top; i < count && i < top + rows; i++)); do
                mark=' '
                if [ "${checked[i]}" = 1 ]; then mark=x; fi
                if ((i == cursor)); then
                    printf '\033[7m> [%s] %s\033[0m\033[K\n' "$mark" "${PROJECTS[i]##*/}"
                else
                    printf '  [%s] %s\033[K\n' "$mark" "${PROJECTS[i]##*/}"
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
        if [ "${checked[i]}" = 1 ]; then SELECTED+=("${PROJECTS[i]}"); fi
    done
}

main() {
    case "${1:-}" in -h | --help) usage ;; esac
    [ $# -le 1 ] || usage

    ROOT=$(cd "${1:-.}" && pwd) || die "no such directory: $1"
    command -v composer > /dev/null || die "composer not found on PATH"

    PROJECTS=()
    local dir
    while IFS= read -r dir; do PROJECTS+=("$dir"); done < <(find_projects "$ROOT")
    [ ${#PROJECTS[@]} -gt 0 ] || die "no subfolders with a composer.json in $ROOT"

    pick

    local name summary='' failed=0
    for dir in "${SELECTED[@]}"; do
        name=${dir##*/}
        printf '\n\033[1m==> %s\033[0m\n' "$name"
        if (cd "$dir" && composer update); then
            summary+=$'\033[32m✓\033[0m '"$name"$'\n'
        else
            summary+=$'\033[31m✗\033[0m '"$name"$'\n'
            failed=$((failed + 1))
        fi
    done

    printf '\n\033[1mSummary\033[0m\n%s' "$summary"
    [ "$failed" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
