# Deploy kit: online demo on an Ubuntu ARM64 VM

Cloud-agnostic. Target: Oracle Always Free `VM.Standard.A1.Flex` (aarch64). Any aarch64 Ubuntu VM works.
No registry and no public repo: files go to the server with `scp`.

```
Internet -> :80/:443 Caddy (TLS) -> /demo/* only -> iris:52773   (docker network, no host ports on iris)
```

Files: `bootstrap.sh`, `load-image.sh`, `docker-compose.demo.yml`, `Caddyfile`, `.env.example`.

Shorthand used below (run from the repo root on the server):
`DC="docker compose -f docker-compose.yml -f deploy/docker-compose.demo.yml"`

## a) Create the VM
1. OCI: shape `VM.Standard.A1.Flex`, 4 OCPU / 24 GB (Always Free limit). Minimum 2 OCPU / 8-12 GB.
2. Image: Canonical Ubuntu 24.04, aarch64. Boot volume: 100 GB or more (the IRIS image is several GB).
3. Assign a public IPv4 address.
4. Security list or NSG: add ingress TCP 80 and TCP 443 from 0.0.0.0/0. TCP 22 is open by default.
5. DNS: add an A record `DEMO_DOMAIN` -> the public IP. Caddy needs it before it can get a certificate.

## b) Bootstrap
```
scp deploy/bootstrap.sh <user>@<server>:~/
ssh <user>@<server> 'sudo ./bootstrap.sh'
```
It checks `aarch64`, installs Docker and the compose plugin (Docker apt repo), adds the user to group `docker`,
opens ufw 22/80/443, and creates 4 GB swap if none is active. Log out and in again.
OCI images ship iptables REJECT rules. Check with `sudo iptables -L INPUT -n --line-numbers` (details in the script).
Check `docker compose version`: the overlay needs v2.24.4 or newer.

## c) IRIS image
```
scp irishealth_arm64-community-2027.1.0AI.109.0-docker.tar.gz deploy/load-image.sh <user>@<server>:~/
ssh <user>@<server> './load-image.sh'
```
The script runs `docker image load -i` and retags to `irishealth-aihub:2027.1.0AI.109.0`. This is the `ARG IMAGE`
default in `Dockerfile` and the `LOCAL_TAG` logic of `run.sh:22-50`.

## d) Project code and build
From a clean checkout on your workstation:
```
git archive --format=tar.gz -o ioa.tar.gz HEAD
scp ioa.tar.gz <user>@<server>:~/
ssh <user>@<server> 'mkdir -p ~/interop-ops-agent && tar -xzf ioa.tar.gz -C ~/interop-ops-agent'
```
(`git bundle create ioa.bundle HEAD` also works.) Then on the server:
`cd ~/interop-ops-agent && $DC build`

Alternative: build on your workstation (ARM64 Mac), then `docker save` the project image, `scp` it, and
`docker load -i` on the server. The image name is `interop-ops-agent-iris` (compose default for project `interop-ops-agent`; not verified).
Note: the base compose file bind-mounts `./` into the container, so the code directory must stay on the server.
On Linux the bind mount keeps host ownership; if IRIS (user `irisowner`) cannot write under `./` (logs, `cases/in`, `replay`),
check `$DC logs iris` and fix ownership of those directories. Not verified on a server (tested only on macOS Docker).

## e) Server .env
```
cd ~/interop-ops-agent && cp deploy/.env.example .env && chmod 600 .env
```
Edit `.env`. Put `OPENAI_API_KEY` only in this server file. Never commit it, never paste it in chat or logs.
Set `IOA_REVIEWER_PASSWORD`, `DEMO_DOMAIN` and `ACME_EMAIL` (both required by the overlay). Optional basic auth:
```
docker run --rm caddy:2 caddy hash-password        # prompts for a password, prints a bcrypt hash
```
Put the hash in `DEMO_BASIC_AUTH_HASH`, the name in `DEMO_BASIC_AUTH_USER`, and set `DEMO_AUTH=auth_on`.
Single-quote the hash in `.env` (`DEMO_BASIC_AUTH_HASH='$2a$14$...'`) so compose does not interpolate its `$` signs. (Not verified on a server.)

## f) Start
```
# Prints only the ports per service (plain `$DC config` would print .env values, incl. the key):
$DC config --format json | python3 -c 'import json,sys; d=json.load(sys.stdin); print({k: v.get("ports") for k, v in d["services"].items()})'
# expected: iris None, caddy 80/443
$DC up -d --build
$DC ps ; docker ps --format '{{.Names}}\t{{.Ports}}'   # only caddy shows 0.0.0.0:80/443
$DC exec -T iris iris session IRIS -U IRISAPP 'do ##class(InteropOps.Setup).InitAndStartProduction()'
```
Alternative to the commands above: `./run.sh --demo` (same overlay; image load/tag, build, reload, `InitAndStartProduction`;
it skips the host port and localhost HTTP checks). Plain `./run.sh` must not be used on the server: it publishes the iris
ports, and it refuses (exit 3, before any docker command) when `DEMO_DOMAIN` is set in the environment or `.env`.
The `InitAndStartProduction` call above is the same as the `run.sh:248` step, and it is the only step that installs the daily reset (see i).
Open `https://DEMO_DOMAIN/`: it returns 404 (expected). `/csp/sys/UtilHome.csp` must also return 404.
The judge page is `https://DEMO_DOMAIN/demo/`. On the server the `/demo` -> `/demo/` redirect (308) is done by Caddy
(`redir` in `deploy/Caddyfile`); `scripts/demo-redirect.sh` is only for the local container, where there is no Caddy.
If `ports:` still shows on iris, your compose is older than v2.24.4. Upgrade it.

## g) Smoke test
The scripts use `docker exec` on `interop-ops-agent-iris-1` and read `.env` on the host, so run them from the repo
root on the server.
1. REPLAY, 12/12, 0 LLM calls:
   `./scripts/demo.sh --replay` then `EXPECT_REPLAY=1 ./scripts/check.sh` and `./scripts/smoke_generic.sh`.
2. LIVE: `./scripts/demo.sh --live` (needs the key). It runs all 12 cases, paid, bounded by `IOA_MAX_USD`.
   One case only: `./scripts/demo.sh --live --case C01` (score `correct 1/1`; the cost estimate covers that case's cassette).
3. Cap exhaustion -> REPLAY fallback, without recreating the container. The check is `Operation.cls:169-172`
   (`usd` >= `IOA_MAX_USD`), made before each LIVE/MOCK agent run.
   ```
   ./scripts/demo.sh --live --exhaust-budget            # all 12 cases; or add --case C01 for one
   ```
   After the reset, `--exhaust-budget` sets `^IOA.Budget("usd")` to `IOA_MAX_USD` + 0.01 (never lowers it) and prints
   `BUDGET_EXHAUSTED usd=.51 cap=.5 over_usd=1 ...`. Each agent case with a cassette in `replay/` is then replayed
   (`provider_kind` REPLAY, warning `budget_cap_replay`); a case without one escalates with `budget_cap`. All 12 cases
   have a cassette, so no API call is expected. On exit the added amount is subtracted again (`BUDGET_RESTORED ...`).
   Works with `--no-reset` too (the existing counter is kept and raised). With `--replay` the budget does not apply.
   Checked locally in REPLAY only: the flag sets the global, `OverUSD()` returns 1, and the value is restored on exit.
   The LIVE run itself was not made (it needs the key). The unit-level proof is `LLMConfig.CheckSwitching()` test 16
.
4. Reset the counter afterwards: `$DC exec -T iris iris session IRIS -U IRISAPP 'kill ^IOA.Budget'`

## h) Rollback
- Stop, keep data: `$DC down`
- DESTRUCTIVE, full removal (deletes volumes incl. Caddy certificates, images, firewall and swap changes):
  ```
  $DC down -v
  docker image rm interop-ops-agent-iris irishealth-aihub:2027.1.0AI.109.0 caddy:2
  sudo ufw delete allow 80/tcp ; sudo ufw delete allow 443/tcp
  sudo swapoff /swapfile && sudo rm /swapfile && sudo sed -i '\#^/swapfile #d' /etc/fstab
  ```

## i) Environment variables (evidence: file:line)
`GetVar` (`LLMConfig.cls:21`) reads the process env via `$SYSTEM.Util.GetEnviron` (`:31`), else `^IOA.Config`.

| Variable | Status | Evidence |
|---|---|---|
| `IOA_LIVE` | wired | `LLMConfig.cls:174`, `ProviderFactory` via `LLMConfig` |
| `IOA_MAX_USD` | wired (default 0.50) | `Operation.cls:172` (`Price`, `:177`) |
| `LLM_PRICE_IN_PER_M`, `LLM_PRICE_OUT_PER_M` | wired (0.75 / 4.50) | `Operation.cls:164` |
| `IOA_DAILY_RESET` | wired, but only at `InitAndStartProduction` / `Reload` | `Setup.cls:635` (`EnvFlagRaw`), called from `Setup.cls:514`, `:599`; callers: `run.sh:248`, `scripts/reload.sh:14` |
| `LLM_PROFILE`, `LLM_MODEL` | wired | `LLMConfig.cls:299`, `:302` |
| `OPENAI_API_KEY`, `OPENROUTER_API_KEY` | wired | `LLMConfig.cls:53`, `:83`; `Setup.cls:65` |
| `REPLAY` | wired | `LLMConfig.cls:322`, `ProviderFactory.cls:84` |
| `IOA_RECORD` | wired | `LLMConfig.cls:272` |
| `IOA_CASES_IN`, `IOA_REPLAY_DIR` | wired | `LLMConfig.cls:248`, `:285` |
| `IOA_REVIEWER_USER`, `IOA_REVIEWER_PASSWORD` | wired | `Setup.cls:153`, `:164` |
| `IOA_AUTOAPPROVE` | wired | `Setup.cls:393` (`.env` template only; not in compose `environment`, it arrives via `env_file`) |
| `DEMO_DOMAIN`, `ACME_EMAIL`, `DEMO_AUTH`, `DEMO_BASIC_AUTH_*` | deploy only (compose overlay + Caddy) | `deploy/docker-compose.demo.yml`, `deploy/Caddyfile` |

Not wired: no variable in the list is unused in `src/`. One caveat: `IOA_DAILY_RESET=1` does nothing after a plain
`docker compose up`. The Task Manager task is installed only when `InitAndStartProduction()` or `Reload()` runs.
`docker-compose.yml` has no `IOA_MAX_USD`, `LLM_PRICE_*` or `IOA_DAILY_RESET` in `environment`. They reach the container only through `env_file: .env`.
Editing `.env` needs a container recreate (`$DC up -d`). Not verified on a server.

## j) Open questions
1. Domain name for `DEMO_DOMAIN`, and an `ACME_EMAIL`.
2. Basic auth: yes or no? (Off by default.)
3. Closed: the demo page exists (`/demo/`, README "Judge demo page"); the trace is a table from `Ens.MessageHeader`, no portal.
4. VM size: 4 OCPU / 24 GB or smaller?
5. Closed: a single-case LIVE run is `./scripts/demo.sh --live --case C01` (see g) item 2).
6. Caddy `import {$DEMO_AUTH:auth_off}` was not tested. Validate on the server before `up`:
   `docker run --rm --env-file .env -v "$PWD/deploy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2 caddy validate --config /etc/caddy/Caddyfile`
