# `composer-bulk-update.sh`

Lists the subfolders of a directory that have a `composer.json`, lets you tick the ones you
want, then runs `composer update` in each, one at a time.

## Usage

```sh
composer-bulk-update.sh [-g|--git] [dir]
```

| Argument      | Meaning |
| ------------- | ------- |
| `-g`, `--git` | Also sync each project with git. See [Git mode](#git-mode). |
| `dir`         | Folder whose immediate subfolders are scanned. Defaults to the current directory. |

Only one level down is scanned, so running it in `~/Sites` lists `~/Sites/<site>` folders
and ignores anything nested deeper.

## Keys

| Key            | Action |
| -------------- | ------ |
| `↑` / `↓`, `k` / `j` | Move the cursor |
| `space`        | Tick or untick the folder under the cursor |
| `a`            | Tick all, or untick all if everything is ticked |
| `enter`        | Run `composer update` in the ticked folders. With nothing ticked, runs it in the folder under the cursor. |
| `q`            | Quit without running anything |

Composer's output is shown live. A failed update doesn't stop the rest. A summary at the end
lists each folder with ✓ or ✗, and the script exits 1 if any failed.

## Git mode

With `--git`, each ticked project goes through these steps:

1. `git pull`
2. `composer update`
3. `git commit -m 'updating composer deps'` with only `composer.json` and `composer.lock`
4. `git push origin <current branch>`

Other changes in the working tree, staged or not, stay out of the commit. A gitignored
`composer.lock` is skipped. If the update changes nothing, the commit
and push are skipped and the project still counts as a success. A project fails, and moves on
to the next one, if it's on a detached HEAD or if any step errors.

## Install

```sh
ln -s "$PWD/composer-bulk-update/composer-bulk-update.sh" /opt/homebrew/bin/composer-bulk-update
```

## Test

```sh
bash composer-bulk-update/composer-bulk-update-test.sh
```

## Dependencies

[Composer](https://getcomposer.org) on your `PATH`:

```sh
brew install composer
```
