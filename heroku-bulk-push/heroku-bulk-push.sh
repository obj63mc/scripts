#!/bin/bash
#
# heroku-bulk-push — tick the subfolders you want, then push each one's current branch to Heroku.
#
#   heroku-bulk-push            -> list ./*/ git repos with a `heroku` remote, pick, push
#   heroku-bulk-push ~/Sites    -> same, for another directory
#   heroku-bulk-push --dry-run  -> pick, then show what each push would do, push nothing
#
# Each repo's checked-out branch is pushed to the branch Heroku deploys from, whatever the
# local name is: a repo on `dev` gets `git push heroku dev:main` (or `dev:master`).
#
# Keys: up/down or j/k move, space toggles, a toggles all, enter pushes, q quits.
# Pushes run one at a time with git's output shown live. A failed push doesn't stop the
# rest; the summary lists each result and the exit code is 1 if any failed.

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [--dry-run] [dir]

  --dry-run  run each push with git push --dry-run
  dir        folder whose immediate subfolders are scanned for a heroku remote (default: current dir)
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Print each immediate subfolder of $1 that is a git repo with a `heroku` remote, sorted.
find_projects() {
    local dir
    for dir in "$1"/*/; do
        if git -C "$dir" remote get-url heroku > /dev/null 2>&1; then
            echo "${dir%/}"
        fi
    done
}

# Print the branch Heroku deploys repo $1 from: whatever the remote HEAD points at, or main
# for an empty Heroku repo. Heroku builds pushes to either main or master.
heroku_branch() {
    local head
    head=$(git -C "$1" ls-remote --symref heroku HEAD |
        awk '$1 == "ref:" && $3 == "HEAD" { sub("^refs/heads/", "", $2); print $2 }') || return 1
    echo "${head:-main}"
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
            printf '\033[H\033[1m%s\033[0m\033[K\n' "Heroku pushes"
            printf '\033[2m↑/↓ move  space toggle  a all  enter push  q quit\033[0m\033[K\n\033[K\n'
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

# Push repo $1's branch $2 to Heroku. $3 is "true" for a dry run.
push_project() {
    local target
    target=$(heroku_branch "$1") || return 1
    echo "git push heroku $2:$target"
    if [ "$3" = true ]; then
        git -C "$1" push --dry-run heroku "$2:$target"
    else
        git -C "$1" push heroku "$2:$target"
    fi
}

main() {
    local root=. positional=0 dry_run=false
    while [ $# -gt 0 ]; do
        case $1 in
            --dry-run) dry_run=true ;;
            -*) usage ;;
            *)
                root=$1
                positional=$((positional + 1))
                ;;
        esac
        shift
    done
    [ "$positional" -le 1 ] || usage

    ROOT=$(cd "$root" && pwd) || die "no such directory: $root"
    command -v git > /dev/null || die "git not found on PATH"

    PROJECTS=() BRANCHES=() LABELS=()
    local dir branch
    while IFS= read -r dir; do
        # A detached HEAD has no branch to push; it shows up and fails at push time.
        branch=$(git -C "$dir" symbolic-ref --short -q HEAD) || branch=''
        PROJECTS+=("$dir")
        BRANCHES+=("$branch")
        LABELS+=("${dir##*/}  (${branch:-detached HEAD} -> $(git -C "$dir" remote get-url heroku | sed 's|.*/||; s|\.git$||'))")
    done < <(find_projects "$ROOT")
    [ ${#PROJECTS[@]} -gt 0 ] || die "no subfolders with a heroku remote in $ROOT"

    pick

    local i name summary='' failed=0
    for i in "${SELECTED[@]}"; do
        dir=${PROJECTS[i]}
        branch=${BRANCHES[i]}
        name=${dir##*/}
        printf '\n\033[1m==> %s\033[0m\n' "$name"

        if [ -z "$branch" ]; then
            echo "detached HEAD; check out a branch first" >&2
            summary+=$'\033[31m✗\033[0m '"$name (detached HEAD)"$'\n'
            failed=$((failed + 1))
        elif push_project "$dir" "$branch" "$dry_run"; then
            summary+=$'\033[32m✓\033[0m '"$name $branch"$'\n'
        else
            summary+=$'\033[31m✗\033[0m '"$name $branch"$'\n'
            failed=$((failed + 1))
        fi
    done

    local note=''
    if $dry_run; then note=' (dry run)'; fi
    printf '\n\033[1mSummary%s\033[0m\n%s' "$note" "$summary"
    [ "$failed" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
