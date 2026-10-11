# Options considered and trade-offs

## Helm / Kubernetes
| Decision | Options | Chosen and why |
|----------|---------|----------------|
| Redis | Bitnami sub-chart; external Redis | **External** (brief gives `redis-master...` host). A sub-chart would couple data-sync's release lifecycle to Redis state and fail `helm lint` until `helm dependency build`. Easy to add behind `redis.enabled`. |
| REDIS_PASSWORD | Plain `values`; chart Secret from `--set`; `existingSecret`; Sealed/External Secrets | **Chart Secret injected at deploy time + `existingSecret` escape hatch.** Staging/prod values blank the password and `required` fails if missing, so no default password can leak into real environments. |
| Rollout on config change | Reloader operator; checksum annotations | **Checksum annotations** (no extra controller). |
| Resources | requests only; requests = limits | Prod uses a tight CPU limit and memory limit near request: predictable, at the cost of possible CPU throttling (revisit with data). |
| HPA | CPU only; custom/KEDA | **CPU (as required)** with fast scale-up `behavior`; KEDA proposed in DESIGN.md. |
| PDB | Always on; env-specific | Off in default values (1 replica + `minAvailable: 1` blocks drains locally), on in staging/prod. |
| Security | Defaults; hardened | Non-root, read-only root FS, dropped caps, seccomp, no SA token. Costs: `/tmp` emptyDir needed. |
| Probes | liveness+readiness; + startup | Added **startupProbe** so slow boot does not trigger liveness restarts. |

## Kustomize over Helm output
* **Chosen:** `render.sh` runs `helm template` into `rendered/` and Kustomize patches it. Works with plain `kustomize build`/`kubectl apply -k`.
* **Alternatives:** Kustomize `helmCharts` generator (needs `--enable-helm`, chart packaging); Helm `--post-renderer` (patches live in a script); ArgoCD multi-source. Chosen option is the most transparent for a take-home and for the team's existing Kustomize overlays.
* **SECRET_CHECKSUM:** Kustomize cannot hash a resource itself, so `render.sh` hashes the rendered Secret and writes the annotation patch. It is a second checksum next to the chart's own `checksum/secret`; redundancy is intentional (Helm-only users still roll).
* **topologySpread:** zone `DoNotSchedule` (real HA across zones) but node `ScheduleAnyway`. Risk: a zone without capacity can block scale-out; mitigate with node pool per zone and autoscaler headroom.
* `rendered/` is git-ignored (contains a Secret). Trade-off: overlay builds need the render step first.

## Ansible
* **dnf vs yum:** module is `ansible.builtin.dnf` (yum is an alias on EL8; lint requires the FQCN of the real module).
* **Code deployment:** `git` pull to `/srv/data-sync` as requested. Simple, but not immutable: for production prefer a pinned tag/commit (`data_sync_repo_version`) or a built artifact.
* **Secrets on VM:** root-owned `0640` env file via `EnvironmentFile`, `no_log`, value from Ansible Vault. Not in the unit file (visible via `systemctl show`).
* **Code owned by root**, service runs unprivileged: the app cannot modify its own code.
* **Restarts:** handlers restart only on change (repo, deps, unit, secrets); `flush_handlers` before enable/start so a new unit is loaded on first run.
* **Lint config:** `role-name` and `var-naming[no-role-prefix]` skipped on purpose; the team `be-*` naming and requested `data_sync_*` vars conflict with default rules.
* **be_role gate:** applied with `when` at import level, tags on imports (`install`, `deploy`).

## Not done / next steps
Live cluster smoke test (kind), CI pipeline (`make check` + `kubeconform`), NetworkPolicy, Grafana dashboard / alert rules, image build, real source repo.
