#!/bin/bash
#
# addvhost — add a local Apache vhost + /etc/hosts entry for Homebrew httpd on macOS,
#            with an HTTPS vhost backed by mkcert dev certificates.
#
#   addvhost [--ssl] <domain> [docroot]
#
#   addvhost mysite                       -> mysite.loc  ->  ~/Sites/mysite  (http + https)
#   addvhost tobaccoreviews ~/Sites/tobacco-reviews/site
#   addvhost --ssl cw                     -> add https to an existing http-only site
#
# Run WITHOUT sudo: httpd runs as a user LaunchAgent and Homebrew refuses to run as
# root. Only the /etc/hosts append needs elevation, and the script sudo's for just
# that step. (It still behaves correctly if you run it with sudo out of habit.)

set -euo pipefail

VHOSTS=/opt/homebrew/etc/httpd/extra/httpd-vhosts.conf
HOSTS=/etc/hosts
SITES_ROOT=/Users/joemadden/Sites
APACHECTL=/opt/homebrew/bin/apachectl
MKCERT=/opt/homebrew/bin/mkcert
SUFFIX=.loc

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
USER_HOME=$(eval echo "~$REAL_USER")
CERTS="$USER_HOME/devcerts"

usage() {
    cat >&2 <<EOF
usage: $(basename "$0") [--ssl] <domain> [docroot]

  --ssl      only add the HTTPS vhost (and certs) for a site that already has
             an HTTP vhost; the document root is read from the existing block
  <domain>   site name, with or without the ${SUFFIX} suffix (e.g. "mysite" or "mysite${SUFFIX}")
  [docroot]  document root; defaults to ${SITES_ROOT}/<domain>

examples:
  $(basename "$0") mysite
  $(basename "$0") tobaccoreviews ~/Sites/tobacco-reviews/site
  $(basename "$0") --ssl mysite
EOF
    exit 1
}

die() { echo "error: $*" >&2; exit 1; }

# Run a command as the real (non-root) user — needed for brew and for keeping
# file ownership sane if the script was invoked under sudo.
as_user() {
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# Run a command as root — prompts for a password only when not already root.
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# find_vhost <port> — if a <VirtualHost *:port> block for $host exists, print its
# DocumentRoot and return 0; otherwise return 1.
find_vhost() {
    awk -v host="$host" -v port="$1" '
        index($0, "<VirtualHost *:" port ">") { inblk = 1; dr = ""; ok = 0; next }
        inblk && $1 == "DocumentRoot" { dr = $2; gsub(/^"|"$/, "", dr) }
        inblk && $1 == "ServerName"   { sn = $2; sub(/:.*/, "", sn); if (sn == host) ok = 1 }
        inblk && /<\/VirtualHost>/ {
            if (ok) { print dr; done = 1; exit }
            inblk = 0
        }
        END { exit !done }
    ' "$VHOSTS"
}

# --- Arguments ----------------------------------------------------------------

ssl_only=0
[[ ${1:-} == "--ssl" ]] && { ssl_only=1; shift; }
[[ ${1:-} == "-h" || ${1:-} == "--help" ]] && usage
[[ $# -ge 1 && $# -le 2 ]] || usage

domain="${1%$SUFFIX}"
[[ "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    echo "error: invalid domain name '${1}' — use lowercase letters, digits and hyphens" >&2
    usage
}

host="${domain}${SUFFIX}"

[[ -f "$VHOSTS" ]] || die "vhosts file not found: $VHOSTS"
[[ -x "$APACHECTL" ]] || die "apachectl not found or not executable: $APACHECTL"

# --- Idempotency: figure out what (if anything) is missing --------------------

if http_docroot=$(find_vhost 80); then need_vhost=0; else need_vhost=1; http_docroot=""; fi
if find_vhost 443 >/dev/null;     then need_ssl_vhost=0; else need_ssl_vhost=1; fi

need_hosts=1
grep -qE "(^|[[:space:]])${host}([[:space:]]|$)" "$HOSTS" && need_hosts=0

# Document root: explicit argument wins, then the existing :80 block, then default.
if [[ -n ${2:-} ]]; then
    docroot="$2"
elif [[ -n "$http_docroot" ]]; then
    docroot="$http_docroot"
elif [[ $ssl_only -eq 1 ]]; then
    die "no HTTP vhost found for ${host} — run '$(basename "$0") ${domain}' first, or pass a docroot"
else
    docroot="$SITES_ROOT/$domain"
fi

# Canonicalise: expand a leading ~ and make relative paths absolute.
case "$docroot" in
    "~")   docroot="$USER_HOME" ;;
    "~/"*) docroot="$USER_HOME/${docroot#\~/}" ;;
esac
[[ "$docroot" = /* ]] || docroot="$PWD/$docroot"
docroot="${docroot%/}"

[[ $ssl_only -eq 1 ]] && need_vhost=0

# --- mkcert ------------------------------------------------------------------

cert="$CERTS/${host}.pem"
key="$CERTS/${host}-key.pem"
need_cert=1

if [[ -x "$MKCERT" ]]; then
    [[ -f "$cert" && -f "$key" ]] && need_cert=0
else
    if [[ $ssl_only -eq 1 ]]; then
        die "mkcert not found — install it with: brew install mkcert nss && mkcert -install"
    fi
    echo "note: mkcert not found — skipping HTTPS. Install with:" >&2
    echo "        brew install mkcert nss && mkcert -install" >&2
    need_cert=0
    need_ssl_vhost=0
fi

if [[ $need_vhost -eq 0 && $need_ssl_vhost -eq 0 && $need_hosts -eq 0 && $need_cert -eq 0 ]]; then
    echo "${host} is already configured — nothing to do."
    exit 0
fi

if [[ ! -d "$docroot" ]]; then
    echo "warning: document root does not exist yet: $docroot" >&2
    echo "         Apache will 404 until you create it." >&2
fi

# --- 1. Issue the dev certificate --------------------------------------------

if [[ $need_cert -eq 1 ]]; then
    caroot=$(as_user "$MKCERT" -CAROOT)
    [[ -f "$caroot/rootCA.pem" ]] || {
        echo "warning: mkcert's local CA is not installed — browsers will still warn." >&2
        echo "         Fix with: mkcert -install" >&2
    }

    as_user mkdir -p "$CERTS"
    as_user "$MKCERT" -cert-file "$cert" -key-file "$key" \
        "$host" "www.${host}" "*.${host}" >/dev/null
    echo "issued dev certificate: $cert"
else
    [[ -f "$cert" ]] && echo "certificate for ${host} already present — skipping"
fi

# --- 2. Append the vhost blocks ----------------------------------------------

if [[ $need_vhost -eq 1 || $need_ssl_vhost -eq 1 ]]; then
    [[ -w "$VHOSTS" ]] || die "cannot write to $VHOSTS"

    backup="${VHOSTS}.bak"
    as_user cp "$VHOSTS" "$backup"

    if [[ $need_vhost -eq 1 ]]; then
        as_user tee -a "$VHOSTS" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName ${host}
    ServerAlias www.${host}
    DocumentRoot ${docroot}
    <Directory ${docroot}>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
        echo "added http vhost for ${host} -> ${docroot}"
    else
        echo "http vhost for ${host} already present — skipping"
    fi

    if [[ $need_ssl_vhost -eq 1 ]]; then
        as_user tee -a "$VHOSTS" >/dev/null <<EOF
<VirtualHost *:443>
    ServerName ${host}
    ServerAlias www.${host}
    DocumentRoot ${docroot}
    Protocols h2 h2c http/1.1
    SSLEngine on
    SSLCertificateFile "${cert}"
    SSLCertificateKeyFile "${key}"
    <Directory ${docroot}>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
        echo "added https vhost for ${host} -> ${docroot}"
    else
        echo "https vhost for ${host} already present — skipping"
    fi

    # Validate before touching /etc/hosts, so a bad config never leaves a stray entry.
    if ! "$APACHECTL" configtest; then
        as_user cp "$backup" "$VHOSTS"
        die "Apache config test failed — reverted ${VHOSTS} (backup kept at ${backup})"
    fi
fi

# --- 3. Append the /etc/hosts entry ------------------------------------------

if [[ $need_hosts -eq 1 ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "sudo password needed to add ${host} to ${HOSTS}:"
    fi
    printf '127.0.0.1\t%s\n' "$host" | as_root tee -a "$HOSTS" >/dev/null
    echo "added ${host} to ${HOSTS}"
else
    echo "${host} already in ${HOSTS} — skipping"
fi

# --- 4. Restart Apache --------------------------------------------------------

echo "restarting httpd..."
as_user brew services restart httpd

echo
echo "done:  http://${host}/"
[[ -f "$cert" ]] && echo "       https://${host}/"
echo "  docroot: ${docroot}"
