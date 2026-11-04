# Online demo on k3s (pod on node-bg): https://ioa.antonyartsev.com/demo/

```
Internet -> node-bg:443 svclb -> Traefik pod (node-us; cert-manager, letsencrypt-prod)
         -> /demo/* -> Service iris:52773 -> Pod iris on node-bg (flannel)
         -> any other path -> 302 to /demo/
Pod iris -> openrouter.ai (direct, node-bg IP; DNS 1.1.1.1 / 8.8.8.8, not CoreDNS)
```

Why this layout:
- IRIS 2026.3 needs AVX2. node-us (Xeon E5-2697 v2) has none: `[FATAL] Unsupported CPU`. node-bg (AMD EPYC 7K62) has it.
- openrouter.ai answers 403 to the node-ru IP. From node-bg it answers 200, so no proxy.
- node-bg: 2 vCPU, 7.8 GB RAM, 58 GB disk. svclb runs there (label `svccontroller.k3s.cattle.io/enablelb=true`).
- Traefik is shared by the cluster and stays where k3s puts it (node-us now). It is not pinned to node-bg:
  node-bg may be temporary, and a pinned Traefik would go `Pending` and take all sites down.
  So requests go node-bg -> node-us -> node-bg. If node-bg goes away: point DNS back to node-ru, move the pod.
- LIVE: OpenRouter `openai/gpt-6-luna` ($0.10 / $0.50 per 1M tokens), capped by `IOA_MAX_USD` (0.50/day, reset daily).

No registry: the image is built on the workstation and imported into k3s containerd on node-bg.
Commands run from the repo root. `agent001` is the ssh alias of node-bg.

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
3. Import into k3s on node-bg (~30 min upload). node-bg has disk for the layer blob, keep it: without it
   `ctr images export` fails ("content digest ... not found"), and the image cannot move to another node.
   ```
   docker save ioa-k8s:1 | gzip -1 | ssh agent001 'gunzip | sudo k3s ctr images import -'
   ```
4. Secret from the local `.env` (same as compose `env_file`; values are not printed). The Deployment `env` overrides
   profile, model, prices, LIVE and the proxy:
   ```
   kubectl apply -f deploy/k8s/ioa.yaml
   kubectl -n ioa create secret generic ioa-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n ioa rollout restart deploy/iris
   ```
5. svclb on node-bg: `kubectl label node node-bg svccontroller.k3s.cattle.io/enablelb=true`.
6. DNS: A record `ioa.antonyartsev.com` -> 2.58.32.51 (node-bg, Timeweb).

New code: bump the tag (`ioa-k8s:2`), repeat 2-3, then `kubectl -n ioa set image deploy/iris iris=ioa-k8s:2`.
State lives in the container layer: a pod restart resets the demo.
Check: `curl -s https://ioa.antonyartsev.com/demo/api/status` (mode, model, budget).
