#!/bin/bash
#
# Self-checks:
#   - find_projects only lists immediate subfolders with a composer.json
#   - update_project with GIT=1 pulls, commits only the composer files and pushes to origin

set -euo pipefail

source "$(dirname "$0")/composer-bulk-update.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

test_find_projects() {
    local root="$tmp/find"
    mkdir -p "$root/a" "$root/b" "$root/c d" "$root/e/nested"
    touch "$root/composer.json" "$root/a/composer.json" "$root/c d/composer.json" "$root/e/nested/composer.json"

    local expected actual
    expected=$(printf '%s\n' "$root/a" "$root/c d")
    actual=$(find_projects "$root")
    [ "$actual" = "$expected" ] || fail "find_projects: expected '$expected', got '$actual'"
}

test_update_project_git() {
    local root="$tmp/git"
    mkdir -p "$root/bin"

    # Stub composer: each run changes composer.lock, like a real update with new versions.
    cat > "$root/bin/composer" <<'EOF'
#!/bin/bash
echo updated >> composer.lock
EOF
    chmod +x "$root/bin/composer"
    PATH="$root/bin:$PATH"

    # Isolate from the user's git config and give commits an identity.
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

    git init -q --bare -b main "$root/origin.git"
    git clone -q "$root/origin.git" "$root/project" 2> /dev/null
    git -C "$root/project" checkout -q -b main
    echo '{}' > "$root/project/composer.json"
    git -C "$root/project" add -A
    git -C "$root/project" commit -qm init
    git -C "$root/project" push -q -u origin main

    # A commit pushed from elsewhere, which the pull should bring in.
    git clone -q "$root/origin.git" "$root/other"
    echo other > "$root/other/other.txt"
    git -C "$root/other" add -A
    git -C "$root/other" commit -qm other
    git -C "$root/other" push -q

    # Unrelated work in progress, one file staged and one not; neither should be committed.
    echo wip > "$root/project/staged.txt"
    git -C "$root/project" add staged.txt
    echo wip > "$root/project/unstaged.txt"

    GIT=1
    update_project "$root/project" > /dev/null || fail "update_project returned non-zero"

    [ -f "$root/project/other.txt" ] || fail "git pull didn't run"
    local subject
    subject=$(git -C "$root/origin.git" log -1 --format=%s main)
    [ "$subject" = "$COMMIT_MESSAGE" ] || fail "origin head is '$subject', expected '$COMMIT_MESSAGE'"
    git -C "$root/origin.git" show main:composer.lock > /dev/null || fail "composer.lock not pushed"

    local committed
    committed=$(git -C "$root/origin.git" show --name-only --format= main)
    [ "$committed" = composer.lock ] || fail "commit should only hold composer.lock, got: $committed"
}

test_find_projects
test_update_project_git
echo ok
