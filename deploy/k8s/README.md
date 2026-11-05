# Online demo on k3s: https://ioa.antonyartsev.com/demo/

```
Internet -> :443 -> Traefik (cert-manager, Let's Encrypt)
         -> /demo/* -> Service iris:52773 -> Pod iris (one replica, node with label ioa/iris=true)
         -> any other path -> 302 to /demo/
Pod iris -> openrouter.ai (LIVE; public DNS resolvers, not the cluster DNS)
```

- IRIS needs a CPU with AVX2 (`[FATAL] Unsupported CPU` without it), so the pod runs only on a node with the label `ioa/iris=true`.
- The node must be allowed to reach openrouter.ai (some regions get HTTP 403).
- LIVE: OpenRouter `openai/gpt-6-luna` ($0.10 / $0.50 per 1M tokens), capped by `IOA_MAX_USD` (0.50/day, reset daily).
- The page is anonymous: any visitor can run cases and approve their review tasks (`IOA_DEMO=1`). Synthetic data only.

No registry: the image is built on the workstation and imported into k3s containerd on the node.
Commands run from the repo root. `<node>` is the node name, `<ssh-host>` its ssh host.

1. amd64 IRIS base (the archive is `irishealth-community-2027.1.0AI.109.0-docker.tar.gz`). `docker load` takes the
   same name as the arm64 image, so retag it and point the original name back at arm64:
   ```
   ARM=$(docker image inspect -f '{{.Id}}' irishealth-aihub:2027.1.0AI.109.0)
   docker image load -i ../irishealth-community-2027.1.0AI.109.0-docker.tar.gz
   ISC=docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0
   docker tag $ISC irishealth-aihub-amd64:2027.1.0AI.109.0 && docker tag $ARM $ISC
   ```
2. Build (amd64 under emulation, then the flattened k8s image). The image does not run on the Mac (Rosetta has no AVX2):
   ```
   docker build --platform linux/amd64 --build-arg IMAGE=irishealth-aihub-amd64:2027.1.0AI.109.0 -t interop-ops-agent-iris:amd64 .
   docker build --platform linux/amd64 -f deploy/k8s/Dockerfile -t ioa-k8s:1 .
   ```
3. Import into k3s on the node (an upload of about 30 min). Keep the layer blob on the node: without it
   `ctr images export` fails ("content digest ... not found"), and the image cannot move to another node.
   ```
   docker save ioa-k8s:1 | gzip -1 | ssh <ssh-host> 'gunzip | sudo k3s ctr images import -'
   ```
4. Secret from the local `.env` (same as compose `env_file`; values are not printed). The Deployment `env` overrides
   profile, model, prices and LIVE:
   ```
   kubectl apply -f deploy/k8s/ioa.yaml
   kubectl -n ioa create secret generic ioa-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n ioa rollout restart deploy/iris
   ```
5. Node labels: `kubectl label node <node> ioa/iris=true`, and for the k3s service load balancer
   `kubectl label node <node> svccontroller.k3s.cattle.io/enablelb=true`.
6. DNS: an A record for the demo host to the node IP.

New code: bump the tag (`ioa-k8s:3`), repeat 2-3, then `kubectl -n ioa set image deploy/iris iris=ioa-k8s:3`.
State lives in the container layer: a pod restart resets the demo.
Check: `curl -s https://ioa.antonyartsev.com/demo/api/status` (mode, model, budget).
