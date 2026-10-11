# data-sync design: scaling, isolation and secret rotation

**Load:** about 50M requests/day, bursts near 2,000 req/s. Today: one Deployment, CPU-based HPA, 90 s scale-out, shared nodes with ClickHouse.

---

## 1. Scaling: scale-out in under 20 seconds

**Where the 90 s goes:** metric scrape lag (15-30 s) + HPA sync (15 s) + scheduling, image pull and app boot. CPU is also a lagging signal: it rises after queues have already built.

**Proposal**

1. **Leading metric via KEDA.** Scale on in-flight requests per pod from Prometheus (`pollingInterval: 5`), with CPU as a second trigger. Scrape it every 5-10 s; the chart's 30 s ServiceMonitor interval suits dashboards, not scaling.
2. **Aggressive HPA behaviour.** Scale-up stabilization 0 s and +100 % per 15 s, slow scale-down (300 s), CPU target 60 %. *(Implemented in the chart.)*
3. **Remove start-up time.** Keep warm headroom with low-priority "pause" pods that are evicted instantly, so node autoscaling (1-3 min) is off the hot path. Use a slim, pre-pulled image and a `startupProbe` *(implemented)*. Production `minReplicas: 3` covers baseline load.
4. **Protect Redis.** Each pod caps its pool at `MAX_CONNECTIONS` (100), so 20 pods means at most 2,000 connections; check Redis `maxclients`. Add backpressure (HTTP 429) instead of unbounded retries.

**Budget:** metric 5-10 s + poll 5 s + schedule/start 5-8 s = roughly 15-20 s.

**Trade-offs:** KEDA is one more controller; warm headroom costs money; fast scale-up can overshoot and stress Redis; Prometheus joins the scaling path, so keep the CPU HPA as a fallback.

---

## 2. Workload isolation from noisy neighbours

Escalate from cheapest to heaviest:

1. **Guaranteed QoS and priority.** Requests = limits and a `PriorityClass` so data-sync preempts batch pods and is evicted last. Give ClickHouse a lower class plus a `LimitRange` and `ResourceQuota`.
2. **Taints, tolerations, affinity.** Taint analytics nodes and keep data-sync off them with node affinity. Zone spread already comes from topology constraints.
3. **Dedicated node pool** (taint, label, toleration, required affinity) when 1-2 are not enough. Requests do not stop shared L3 cache, memory-bandwidth or CFS-throttling effects. For stubborn p99 jitter, use the kubelet static CPU manager for exclusive cores.

**Trade-offs:** dedicated pools reduce bin-packing efficiency and need their own autoscaling; preemption evicts lower-tier pods. Start with 1-2 and move to 3 only when measurements show interference.

---

## 3. Zero-downtime REDIS_PASSWORD rotation (every 90 days)

**Delivery.** The password lives in GCP Secret Manager; External Secrets Operator syncs it into a Kubernetes Secret (the chart supports this via `redis.existingSecret`).

**Key idea: overlap, don't swap.** Redis 6+ ACL users can hold several passwords at once.

1. Add the NEW password to the Redis ACL user. The OLD one still works.
2. Store the NEW secret version in Secret Manager; ESO updates the Kubernetes Secret.
3. The checksum annotation changes (`SECRET_CHECKSUM` in the overlay, `checksum/secret` in the chart), starting a rolling update with `maxUnavailable: 0`, gated by readiness probes and the PDB. Pods restart gradually, never all at once.
4. Canary one pod first, then the rest.
5. Verify, then remove the OLD password.

**Verification.** Watch auth-failure counters, error rate and p99, Redis `ACL LOG` and `CLIENT LIST`, and `kubectl rollout status`.

**Rollback.** The old password stays valid until the last step, so rollback is reverting the Secret.

**Trade-offs:** the overlap is a short extra exposure, and it needs Redis 6 or newer.

---

## Implemented vs proposed

**In the repo:** fast-scale-up HPA, three probes, PDB, zone spread, checksum-triggered rollouts, `existingSecret`. 
**Proposed only:** KEDA, warm headroom, priority classes, node pools, ESO and the Redis ACL steps. Nothing was load-tested; the numbers are estimates to validate.
