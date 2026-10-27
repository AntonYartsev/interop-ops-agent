#!/usr/bin/env bash
# Local container only: make /demo (no slash) redirect to /demo/ in the
# IRIS private web server (PWS Apache). IRIS matches a web application only
# with the trailing slash, so without this /demo is a CSP 404.
# Idempotent; writes the empty hook file conf/httpd-local.conf and does a
# graceful httpd restart. Lost if the container is recreated (rerun it).
# On the public host Caddy does the same redirect (see deploy/Caddyfile).
set -euo pipefail
CONTAINER_NAME="${CONTAINER_NAME:-interop-ops-agent-iris-1}"
docker exec "$CONTAINER_NAME" sh -c '
H=/usr/irissys/httpd
F=$H/conf/httpd-local.conf
grep -q "RedirectMatch 308 \^/demo\\$ /demo/" "$F" 2>/dev/null || printf "%s\n" "# interop-ops-agent: /demo -> /demo/ (local container only; on the public host Caddy does this)" "RedirectMatch 308 ^/demo\$ /demo/" >> "$F"
$H/bin/httpd -f $H/conf/httpd.conf -d $H -c "Listen 52773" -t
$H/bin/httpd -f $H/conf/httpd.conf -d $H -c "Listen 52773" -k graceful
'
echo "DEMO_REDIRECT OK (/demo -> /demo/)"
