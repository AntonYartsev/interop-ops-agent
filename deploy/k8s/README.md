# Online demo on k3s (node-ru): https://ioa.antonyartsev.com/demo/

```
Internet -> node-ru:443 Traefik (cert-manager, letsencrypt-prod)
         -> /demo/* -> Service iris:52773 -> Pod iris on node-ru
         -> any other path -> 302 to /demo/
Pod iris --HTTPS_PROXY--> Service llm-proxy (squid on node-us) -> openrouter.ai
```

Why this layout:
- IRIS 2026.3 needs AVX2. node-us (Xeon E5-2697 v2) has none: `[FATAL] Unsupported CPU`. node-ru has it.
- openrouter.ai answers 403 to the node-ru IP, so LLM calls leave through squid on node-us (US IP).
- LIVE: OpenRouter `openai/gpt-6-luna` ($0.10 / $0.50 per 1M tokens), capped by `IOA_MAX_USD` (0.50/day, reset daily).

No registry: the image is built on the workstation and imported into k3s containerd on node-ru.
Commands run from the repo root. `agent003` is the ssh alias of node-ru.

1. amd64 IRIS base (the archive is `irishealth-community-2026.3.0AI.154.0-docker.tar.gz`). `docker load` takes the
   same name as the arm64 image, so retag it and point the original name back at arm64:
   ```
   ARM=$(docker image inspect -f '{{.Id}}' irishealth-aihub:2026.3.0AI.154.0)
   docker image load -i ../irishealth-community-2026.3.0AI.154.0-docker.tar.gz
   ISC=docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0
   docker tag $ISC irishealth-aihub-amd64:2026.3.0AI.154.0 && docker tag $ARM $ISC
   ```
2. Build (amd64 under emulation, then the flattened k8s image). The image does not run on the Mac (Rosetta has no AVX2):
   ```
   docker build --platform linux/amd64 --build-arg IMAGE=irishealth-aihub-amd64:2026.3.0AI.154.0 -t interop-ops-agent-iris:amd64 .
   docker build --platform linux/amd64 -f deploy/k8s/Dockerfile -t ioa-k8s:1 .
   ```
3. Import into k3s on node-ru (~30 min upload), then drop the uncompressed layer blob: containerd keeps it next to the
   unpacked snapshot, ~6 GB extra, and node-ru (30 GB disk) goes into DiskPressure:
   ```
   docker save ioa-k8s:1 | gzip -1 | ssh agent003 'gunzip | sudo k3s ctr images import -'
   ssh agent003 'sudo k3s ctr content ls | sort -k2 -h | tail -1'   # the ~6 GB blob
   ssh agent003 'sudo k3s ctr content rm sha256:<that digest>'
   ```
4. Secret from the local `.env` (same as compose `env_file`; values are not printed). The Deployment `env` overrides
   profile, model, prices, LIVE and the proxy:
   ```
   kubectl apply -f deploy/k8s/ioa.yaml
   kubectl -n ioa create secret generic ioa-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n ioa rollout restart deploy/iris
   ```
5. DNS: A record `ioa.antonyartsev.com` -> 82.202.143.93 (Timeweb).

New code: bump the tag (`ioa-k8s:2`), repeat 2-3, then `kubectl -n ioa set image deploy/iris iris=ioa-k8s:2`.
Delete the old image first (`sudo k3s ctr images rm docker.io/library/ioa-k8s:1`): two copies do not fit on node-ru.
State lives in the container layer: a pod restart resets the demo.
Check: `curl -s https://ioa.antonyartsev.com/demo/api/status` (mode, model, budget).
