#!/bin/bash
#
# heroku-bulk-deploy — tick the Heroku apps you want, then rebuild each one.
#
#   heroku-bulk-deploy            -> list deployed apps, pick, rebuild
#   heroku-bulk-deploy --dry-run  -> pick, then fetch the source each app would build, build nothing
#
# Every build uses the commit in the app's current release and purges the build cache first,
# so it's a full rebuild of what's already running.
#
# The source tarball comes from the first place that has that commit, checking the app and
# then the other apps in its pipeline: the linked GitHub repo, then the Heroku git repo.
# Production apps promoted from staging have an empty Heroku git repo, so their source
# usually comes from the staging app.
#
# Keys: up/down or j/k move, space toggles, a toggles all, enter rebuilds, q quits.
# Builds run one at a time with the build log shown live. A failed build doesn't stop the
# rest; the summary lists each result and the exit code is 1 if any failed.

set -euo pipefail

HEROKU=/opt/homebrew/bin/heroku
GH=/opt/homebrew/bin/gh

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [--dry-run]

  --dry-run  fetch the source each picked app would build, build nothing
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Read `heroku apps --all --json` on stdin. Print "<id>\t<name>\t<runtime>" for each app that
# has been deployed and isn't archived, sorted by name.
parse_apps() {
    jq -r '
        [.[] | select(.slug_size != null and .archived_at == null)]
        | sort_by(.name | ascii_downcase)[]
        | [.id, .name, (.buildpack_provided_description // "unknown")] | @tsv'
}

# Read `heroku pipelines:info --json` on stdin. Print "<id>\t<name>" for each app except $1.
parse_pipeline_apps() {
    jq -r --arg skip "$1" '.apps[] | select(.name != $skip) | [.id, .name] | @tsv'
}

# GET a Heroku API URL. The token goes in on stdin so it stays out of `ps`.
api() {
    printf 'Authorization: Bearer %s\n' "$TOKEN" |
        curl -sf -H @- -H 'Accept: application/vnd.heroku+json; version=3' "$1"
}

# Print the commit of the slug in app $1's current release.
live_commit() {
    local slug
    slug=$("$HEROKU" releases:info -a "$1" --json | jq -r '.slug.id // empty')
    [ -n "$slug" ] || return 1
    api "https://api.heroku.com/apps/$1/slugs/$slug" | jq -r '.commit // empty'
}

# Print "<id>\t<name>" for app $2 (id $1), then for the other apps in its pipeline.
source_candidates() {
    local pipeline
    printf '%s\t%s\n' "$1" "$2"
    pipeline=$("$HEROKU" apps:info -a "$2" --json | jq -r '.pipeline_coupling.pipeline.name // empty')
    if [ -n "$pipeline" ]; then
        "$HEROKU" pipelines:info "$pipeline" --json | parse_pipeline_apps "$2"
    fi
}

# Write a tarball of commit $3 to $4, taken from app $2's (id $1) linked GitHub repo or its
# Heroku git repo. Prints where it came from, or returns 1 if neither has the commit.
fetch_source() {
    local id=$1 app=$2 commit=$3 out=$4 repo git_dir
    # The GitHub link is only looked up by app id; a 404 means the app isn't linked.
    repo=$(api "https://kolkrabbi.heroku.com/apps/$id/github" | jq -r '.repo // empty') || repo=''
    # GitHub nests the files in one top-level folder, which the Heroku build API unwraps.
    if [ -n "$repo" ] && "$GH" api "repos/$repo/tarball/$commit" > "$out" 2> /dev/null; then
        echo "GitHub $repo"
        return 0
    fi

    git_dir=$(mktemp -d)
    if git clone --bare --quiet "https://git.heroku.com/$app.git" "$git_dir" 2> /dev/null &&
        git --git-dir="$git_dir" cat-file -e "$commit^{commit}" 2> /dev/null &&
        git --git-dir="$git_dir" archive --format=tar.gz -o "$out" "$commit"; then
        rm -rf "$git_dir"
        echo "Heroku git $app"
        return 0
    fi
    rm -rf "$git_dir"
    return 1
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
            printf '\033[H\033[1m%s\033[0m\033[K\n' "Heroku apps"
            printf '\033[2m↑/↓ move  space toggle  a all  enter rebuild  q quit\033[0m\033[K\n\033[K\n'
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

# Purge app $1's build cache, then build it from tarball $2 tagged with commit $3.
rebuild() {
    "$HEROKU" builds:cache:purge -a "$1" --confirm "$1" &&
        "$HEROKU" builds:create -a "$1" --source-tar "$2" --version "$3"
}

main() {
    local dry_run=false arg
    for arg in "$@"; do
        case $arg in
            --dry-run) dry_run=true ;;
            *) usage ;;
        esac
    done

    [ -x "$HEROKU" ] || die "heroku CLI not found at $HEROKU (brew install heroku/brew/heroku)"
    [ -x "$GH" ] || die "gh CLI not found at $GH (brew install gh)"
    command -v jq > /dev/null || die "jq is required"
    "$HEROKU" builds --help > /dev/null 2>&1 || die "builds plugin missing; run: heroku plugins:install @heroku-cli/heroku-builds"
    TOKEN=$("$HEROKU" auth:token 2> /dev/null) || die "not logged in; run: heroku login"

    IDS=() NAMES=() LABELS=()
    local id name runtime
    while IFS=$'\t' read -r id name runtime; do
        IDS+=("$id")
        NAMES+=("$name")
        LABELS+=("$name  ($runtime)")
    done < <("$HEROKU" apps --all --json | parse_apps)
    [ ${#IDS[@]} -gt 0 ] || die "no deployed apps found"

    pick

    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    local i commit from cand_id cand tarball summary='' failed=0
    for i in "${SELECTED[@]}"; do
        id=${IDS[i]}
        name=${NAMES[i]}
        tarball=$work/$name.tar.gz
        printf '\n\033[1m==> %s\033[0m\n' "$name"

        commit=$(live_commit "$name") || commit=''
        if [ -z "$commit" ]; then
            echo "no commit found on the current release of $name" >&2
            summary+=$'\033[31m✗\033[0m '"$name (no live commit)"$'\n'
            failed=$((failed + 1))
            continue
        fi

        from=''
        while IFS=$'\t' read -r cand_id cand; do
            if from=$(fetch_source "$cand_id" "$cand" "$commit" "$tarball"); then break; fi
        done < <(source_candidates "$id" "$name")
        if [ -z "$from" ]; then
            echo "commit ${commit:0:7} not found in GitHub or Heroku git for $name or its pipeline" >&2
            summary+=$'\033[31m✗\033[0m '"$name ${commit:0:7} (source not found)"$'\n'
            failed=$((failed + 1))
            continue
        fi

        echo "source: ${commit:0:7} from $from"
        if $dry_run; then
            echo "would purge the build cache and rebuild"
            summary+="  $name ${commit:0:7} from $from"$'\n'
        elif rebuild "$name" "$tarball" "$commit"; then
            summary+=$'\033[32m✓\033[0m '"$name ${commit:0:7}"$'\n'
        else
            summary+=$'\033[31m✗\033[0m '"$name ${commit:0:7}"$'\n'
            failed=$((failed + 1))
        fi
        rm -f "$tarball"
    done

    local note=''
    if $dry_run; then note=' (dry run)'; fi
    printf '\n\033[1mSummary%s\033[0m\n%s' "$note" "$summary"
    [ "$failed" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
