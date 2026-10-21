# `render-maintenance.sh`

Turns Render maintenance mode on or off for a fixed list of services.

## Usage

```sh
render-maintenance.sh [on|off] [--dry-run]
```

| Argument    | Meaning |
| ----------- | ------- |
| `on`        | Turn maintenance mode on. The default. |
| `off`       | Turn maintenance mode off. |
| `--dry-run` | List the services that would change and change nothing. |

## Services

The list lives in the `SERVICES` array at the top of the script. Each entry is a service
ID followed by a label used in the output:

| Service                 | ID                         |
| ----------------------- | -------------------------- |
| Gallo-Brand-Standards   | `srv-cv8rlltumphs73dcdcbg` |
| Cigar-World             | `srv-cu82orlds78s738lu0pg` |
| STGEdu-staging          | `srv-d4sp9tccjiac739oi59g` |
| tobacco-reviews         | `srv-d7j8q567r5hc73b1blj0` |
| soonhari                | `srv-d86unarbc2fs73befjm0` |

A service ID that isn't in the CLI's active workspace is reported as a failure. Switch
workspaces with `render workspace set`.

## Dependencies

```sh
brew install render
render login
```

`jq` is also required. macOS ships it at `/usr/bin/jq`.
