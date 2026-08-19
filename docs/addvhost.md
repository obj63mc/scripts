# `addvhost.sh`

Adds an Apache virtual host to Homebrew httpd, points a `.loc` domain at it in
`/etc/hosts`, issues a locally-trusted TLS certificate with `mkcert`, and restarts httpd.
Every step is idempotent — re-running only fills in what is missing.

## Usage

```sh
addvhost.sh [--ssl] <domain> [docroot]
```

| Argument    | Meaning |
| ----------- | ------- |
| `--ssl`     | Only add the HTTPS vhost (and cert) to a site that already has an HTTP vhost. The document root is read from the existing `*:80` block. |
| `<domain>`  | Site name, with or without the `.loc` suffix. |
| `[docroot]` | Document root. Defaults to `~/Sites/<domain>`. |

```sh
addvhost.sh mysite                                   # mysite.loc -> ~/Sites/mysite
addvhost.sh tobaccoreviews ~/Sites/tobacco-reviews/site
addvhost.sh --ssl oldsite                            # retrofit HTTPS onto an existing site
```

## What it writes

- An `*:80` and an `*:443` vhost in `/opt/homebrew/etc/httpd/extra/httpd-vhosts.conf`
  (`ServerName <domain>.loc`, `ServerAlias www.<domain>.loc`).
- A certificate pair in `~/devcerts/<domain>.loc.pem` / `<domain>.loc-key.pem`, covering
  `<domain>.loc`, `www.<domain>.loc` and `*.<domain>.loc`.
- A `127.0.0.1` entry in `/etc/hosts`.

HTTP and HTTPS are both served — there is no `:80` → `:443` redirect.

Before writing `/etc/hosts` the script runs `apachectl configtest`; if the config is bad it
restores the backup it took at `httpd-vhosts.conf.bak` and aborts, so a failed run never
leaves a stray hosts entry behind.

Run it **without** `sudo` — Homebrew refuses to run as root, and the script elevates on its
own for just the `/etc/hosts` append. It still behaves correctly if you sudo out of habit.

## Dependencies

```sh
brew install httpd
brew install mkcert nss     # nss makes the local CA trusted in Firefox
mkcert -install             # one time: install the local CA into the system keychain
brew services start httpd
```

`mkcert` is optional. Without it the script still creates the HTTP vhost, prints the install
hint and skips HTTPS; `--ssl` mode, however, requires it.

Apache needs `mod_ssl` loaded and `Listen 443` set. Homebrew's default `httpd.conf` does
both by way of `extra/httpd-ssl.conf` — check for these lines if HTTPS does not come up:

```apache
LoadModule ssl_module lib/httpd/modules/mod_ssl.so
Include /opt/homebrew/etc/httpd/extra/httpd-ssl.conf
```
