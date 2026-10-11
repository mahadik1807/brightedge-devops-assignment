# BrightEdge Platform Assignment - data-sync

Helm chart + Kustomize overlay (Kubernetes), Ansible role (VMs) and a written design.

| Part | Location |
|------|----------|
| 1. Helm chart, values, ServiceMonitor | `helm/charts/data-sync/` |
| 1. Kustomize overlay (production) | `standard/data-sync/production/` |
| 2. Ansible role, playbook, group_vars | `ansible/` |
| 3. Design question | `DESIGN.md` |
| Options and trade-offs | `docs/OPTIONS_AND_TRADEOFFS.md` |
| Architecture, NFRs, maintaining the repo | `docs/ARCHITECTURE.md` |

## Prerequisites
helm >= 3.12, kubectl/kustomize >= 5, ansible-core >= 2.14, ansible-lint. Optional: kind/minikube.
The `ServiceMonitor` CRD is only needed on a real cluster (`helm template`/`lint` do not need it).

## Validate (no cluster needed)
```bash
make lint        # helm lint: defaults, staging, production
make template    # helm template for all three values combinations
make kustomize   # render chart -> kustomize build production overlay
make ansible-lint
```
Staging and production deliberately blank `redis.password`, so rendering fails
unless a password is supplied (fail fast, never ship a default password).
The Makefile passes a dummy value for validation only.

## Helm: install / upgrade
Chart-managed Secret (password injected from CI, never committed):
```bash
# Staging
helm upgrade --install data-sync helm/charts/data-sync \
  --namespace data-sync-staging --create-namespace \
  -f helm/charts/data-sync/values.yaml -f helm/charts/data-sync/values.staging.yaml \
  --set image.tag=1.0.0 --set-string redis.password="$REDIS_PASSWORD" --atomic --timeout 5m

# Production
helm upgrade --install data-sync helm/charts/data-sync \
  --namespace data-sync --create-namespace \
  -f helm/charts/data-sync/values.yaml -f helm/charts/data-sync/values.production.yaml \
  --set image.tag=1.0.0 --set-string redis.password="$REDIS_PASSWORD" --atomic --timeout 5m
```
Preferred in production: pre-create a Secret (External Secrets / Sealed Secrets) with key
`REDIS_PASSWORD` and pass `--set redis.existingSecret=<name>` instead of `redis.password`.
Rollback: `helm rollback data-sync <revision> -n <namespace>`.

## Kustomize (production)
```bash
REDIS_PASSWORD=... standard/data-sync/production/render.sh   # renders chart + SECRET_CHECKSUM
kustomize build standard/data-sync/production | kubectl apply -f -
```
`rendered/` is git-ignored because it contains the rendered Secret.

## Ansible
```bash
cd ansible
ansible-playbook playbooks/playbook-data-sync.yml -i inventory/hosts.example.yml --tags install
ansible-playbook playbooks/playbook-data-sync.yml -i inventory/hosts.example.yml --tags deploy
ansible-playbook playbooks/playbook-data-sync.yml -i inventory/hosts.example.yml --check --diff
```
Put `data_sync_redis_password` in an `ansible-vault` file (`group_vars/service/vault.yml`).

## Shortcuts called out
* **Placeholder image** `ghcr.io/example/data-sync`; the service source repo URL in the role defaults is a placeholder.
* **Redis is not deployed by this chart.** The brief gives an existing host
  (`redis-master.data-sync.svc.cluster.local`). A Bitnami Redis sub-chart is the
  obvious local shortcut; see trade-offs doc for why it is not a dependency.
* **Verified locally with make check (helm lint, helm template, kustomize build, ansible-lint). Not run against a live cluster or VM.** Ansible: `ansible-lint` (production profile) and `--syntax-check` pass.
  Run `make check` locally to confirm helm/kustomize output before submitting.
