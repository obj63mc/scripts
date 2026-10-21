# `heroku-maintenance.sh`

Turns Heroku maintenance mode on or off for every PHP app you can see (personal and team)
that has at least one dyno. Apps scaled to zero and non-PHP apps are skipped.

An app counts as PHP when Heroku detected PHP on its last build. Most apps have no buildpack
set and rely on that detection, so the configured buildpack list isn't checked. Apps that
mix runtimes, such as PHP plus Node.js, are included.

## Usage

```sh
heroku-maintenance.sh [on|off] [--dry-run]
```

| Argument    | Meaning |
| ----------- | ------- |
| `on`        | Turn maintenance mode on. The default. |
| `off`       | Turn maintenance mode off. |
| `--dry-run` | List the apps that would change and change nothing. |

```sh
heroku-maintenance.sh --dry-run     # see which apps are affected
heroku-maintenance.sh               # maintenance on
heroku-maintenance.sh off           # maintenance off
```

Maintenance mode does not stop dynos, so `off` picks up the same apps that `on` changed.
Apps already in the requested state are reported and left alone.

The script checks each app one at a time, so a full run over ~125 apps takes about two
minutes. It exits non-zero if any app failed to change.

## Dependencies

```sh
brew install heroku/brew/heroku
heroku login
```

`jq` is also required. macOS ships it at `/usr/bin/jq`.
