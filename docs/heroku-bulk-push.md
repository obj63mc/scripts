# `heroku-bulk-push.sh`

Lists the git repos in a folder that have a `heroku` remote, lets you tick the ones you want,
then pushes each one's checked-out branch to Heroku.

## Usage

```sh
heroku-bulk-push.sh [--dry-run] [dir]
```

| Argument    | Meaning |
| ----------- | ------- |
| `dir`       | Folder whose immediate subfolders are scanned. Defaults to the current directory. |
| `--dry-run` | Run each push as `git push --dry-run`, so you see what would be sent without sending it. |

```sh
heroku-bulk-push ~/Sites
```

Each row shows the folder, its current branch and the Heroku app it pushes to, for example
`nag  (dev -> stage-newamsterdam-gin)`.

## Which branch gets pushed where

The current branch is pushed to whichever branch the Heroku repo deploys from, read from the
remote's `HEAD`. So a repo on `dev` whose Heroku repo uses `main` runs:

```sh
git push heroku dev:main
```

A Heroku repo with nothing pushed yet gets `main`. Pushes are never forced, so a push Heroku
rejects as non-fast-forward is reported as a failure. A repo on a detached HEAD has no branch
to push and fails too.

Pushes run one at a time with git's output, including the Heroku build log, shown live. A
failed push doesn't stop the rest. A summary at the end lists each repo with ✓ or ✗ and the
branch, and the script exits 1 if any failed.

## Keys

| Key            | Action |
| -------------- | ------ |
| `↑` / `↓`, `k` / `j` | Move the cursor |
| `space`        | Tick or untick the repo under the cursor |
| `a`            | Tick all, or untick all if everything is ticked |
| `enter`        | Push the ticked repos. With nothing ticked, pushes the repo under the cursor. |
| `q`            | Quit without pushing anything |

## Install

```sh
ln -s "$PWD/heroku-bulk-push/heroku-bulk-push.sh" /opt/homebrew/bin/heroku-bulk-push
```

## Test

```sh
bash heroku-bulk-push/heroku-bulk-push-test.sh
```

## Dependencies

`git`, with Heroku git credentials set up by `heroku login`.
