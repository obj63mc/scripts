# `render-bulk-deploy.sh`

Lists the services in the Render CLI's active workspace, lets you tick the ones you want,
then redeploys each one. Every deploy uses the commit that's live on the service right now
and clears the build cache first, so you get a full rebuild of what's already running.

## Usage

```sh
render-bulk-deploy.sh [--wait] [--dry-run]
```

| Argument    | Meaning |
| ----------- | ------- |
| `--wait`    | Wait for each deploy to finish before starting the next. A failed build counts as a failure in the summary. |
| `--dry-run` | Show the commit each ticked service would deploy and deploy nothing. |

Without `--wait`, the script triggers each deploy and moves on, so the deploys build in
parallel on Render and a ✓ only means the deploy was accepted. Check the dashboard or rerun
with `--wait` to see whether the builds succeeded.

Suspended services and datastores (Postgres, Key Value) aren't listed. To deploy services
in another workspace, switch first with `render workspace set`.

## Keys

| Key            | Action |
| -------------- | ------ |
| `↑` / `↓`, `k` / `j` | Move the cursor |
| `space`        | Tick or untick the service under the cursor |
| `a`            | Tick all, or untick all if everything is ticked |
| `enter`        | Deploy the ticked services. With nothing ticked, deploys the service under the cursor. |
| `q`            | Quit without deploying anything |

## Which commit gets deployed

The script reads the service's deploy history and takes the commit from the newest deploy
with status `live`. If a newer deploy is still building or has failed, the commit that's
serving traffic is the one that gets redeployed. A service with no live deploy (never
deployed, or deployed from a Docker image) is reported as a failure and skipped.

A failed deploy doesn't stop the rest. A summary at the end lists each service with ✓ or ✗
and the short commit hash, and the script exits 1 if any failed.

## Install

```sh
ln -s "$PWD/render-bulk-deploy/render-bulk-deploy.sh" /opt/homebrew/bin/render-bulk-deploy
```

## Test

```sh
bash render-bulk-deploy/render-bulk-deploy-test.sh
```

## Dependencies

```sh
brew install render
render login
```

`jq` is also required. macOS ships it at `/usr/bin/jq`.
