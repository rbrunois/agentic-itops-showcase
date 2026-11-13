# Runbook 04 — App slow / high latency

**Symptom:** pages load but feel sluggish; requests take seconds. The app
still works, so this is a **degradation**, not an outage.

> Note the app uses `Connect Timeout=5` on its SQL connection. A *partial* DB
> problem can make every page pause ~5 s per call while still eventually
> rendering — which reads as "slow", not "broken".

---

## Hypotheses

1. **Host resource pressure** — CPU saturation, low memory, disk full on web or DB VM.
2. **DB slow** — blocking/locking, long-running queries, or SQL under CPU/IO pressure.
3. **Intermittent DB connectivity** — connections timing out at 5 s then retrying.
4. **App pool recycling / cold starts** — first-request recompiles after a recycle.

---

## Investigate

### Step 1 — Resource pressure on both tiers
Run `kql-library.md` §5.1 for `<WEB_HOST>` and `<SQL_HOST>`, and §5.2 for a
fast threshold breach check. Sustained `% Processor Time > 90` or
`Available MBytes < 512` on either tier explains latency (**Hypothesis 1**).

### Step 2 — Intermittent DB degradation
Run `kql-library.md` §1.1. Intermittent `1002` bins *interleaved* with `1001`
(rather than a clean flip) = the web tier is periodically failing/timing out on
DB calls (**Hypothesis 3**).

### Step 3 — SQL-side errors / warnings
Run `kql-library.md` §3.1. Timeouts, deadlocks, or memory-pressure warnings
from `MSSQLSERVER` point to **Hypothesis 2**.

### Step 4 — App pool churn
Run the WAS query from [02 §Step 2](02-app-errors-5xx.md). Frequent recycles
cause cold-start latency (**Hypothesis 4**).

---

## Remediate
- **Resource pressure:** identify the top consumer; if the VM is undersized for
  the load, resize or offload. For a stuck process, restart the offending
  service.
- **SQL slow:** clear blocking, restart `MSSQLSERVER` only as a last resort;
  capture the blocking chain first.
- **App pool churn:** raise/adjust recycle settings; investigate why it's
  recycling (memory limit, config change).

## Report
[templates/rca-report.md](../templates/rca-report.md). Include the Perf
timechart from §5.1 as evidence; quantify latency and the resource metric that
correlates with it.
