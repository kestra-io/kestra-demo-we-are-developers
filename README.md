# Kestra Demo Flows — We Are Developers 2026

Demo flows for the San Jose We Are Developers 2026 conference, built for **Kestra 2.0**.

Every flow here is designed to be **explained and executed in under a minute** on stage, and to be
deployed to any Kestra 2.0 instance straight from this repository.

```
flows/     flows synced into Kestra (this is the GitOps source of truth)
gitops/    the bootstrap flow that pulls flows/ into Kestra — not itself synced
```

---

## The demo: `server_health_report`

[`flows/server_health_report.yaml`](flows/server_health_report.yaml) — a nightly infrastructure
guardrail. It checks every server in a fleet against a CPU threshold, rolls the results into one
report, and pages the on-call engineer if any host is over budget.

It uses **core tasks only** — no credentials, no network calls, no plugins to install. Clone, sync,
run. It finishes in about two seconds.

### The 60-second script

| Beat | Say this | ~Time |
|---|---|---|
| 1 | "This whole workflow is one YAML file, and it lives in Git — not in the UI." | 5s |
| 2 | "It takes inputs: which environment, and what CPU threshold counts as too hot." | 10s |
| 3 | "It loops over the fleet. In Kestra 2.0, **every loop iteration is its own isolated sub-execution** — so looping over 4 servers and looping over 40,000 behave the same way. No single flow can take down the instance." | 15s |
| 4 | "Each server gets evaluated against the threshold and returns a verdict." | 10s |
| 5 | "Then we roll every verdict up into one report — and the guardrail decides whether to page someone." | 10s |
| 6 | Hit **Execute**. Green. Show the report in the logs. | 10s |

**The encore (10 seconds).** Run it again with `cpu_threshold` set to `80`. Two servers breach, the
guardrail fires, and the execution fails with
`CPU budget breached in prod - page the on-call engineer.` That red execution is the point — it is
the flow doing its job.

### What it shows off in 2.0

- **`Loop`** — replaces `ForEach`/`ForEachItem`, with isolated sub-executions per iteration and
  `item.value` / `item.index` available at any nesting depth.
- **Declared loop `outputs`** — because iterations are isolated, you explicitly declare what escapes
  the loop, then read it downstream with `loopOutputs()`.
- **`SELECT` inputs with `label`/`value` pairs** — the UI shows "Production", the expression
  resolves to `prod`.
- **Conditional branching** with `If` plus `Fail` as a real alerting path.

### Expected output

At the default 90% threshold:

```
PROD fleet report - 4 servers checked against a 90% threshold.
  - web-01 at 34% -> OK
  - web-02 at 85% -> OK
  - api-01 at 67% -> OK
  - db-01 at 88% -> OK

All servers within budget.
```

At an 80% threshold the run **fails on purpose**:

```
PROD fleet report - 4 servers checked against a 80% threshold.
  - web-02 at 85% -> BREACH
  - db-01 at 88% -> BREACH
  - api-01 at 67% -> OK
  - web-01 at 34% -> OK

ERROR  CPU budget breached in prod - page the on-call engineer.
```

> Report lines are not in a fixed order — `concurrencyLimit: 4` means the four servers are checked
> concurrently. Set `concurrencyLimit: 1` if you want deterministic ordering on stage.

> Per-server logs live in the **sub-executions**, not the parent. Click into any loop iteration in
> the Gantt or Topology view to see them. The parent execution shows the rolled-up report.

---

## Syncing these flows to a Kestra 2.0 instance

Three options, in the order you should reach for them.

### Option A — GitOps from inside Kestra (recommended)

Kestra pulls from Git on a schedule or on push. Nothing outside Kestra needs credentials to your
instance.

1. Store your Git credentials as [secrets](https://kestra.io/docs/concepts/secret) in Kestra:
   `GITHUB_USERNAME` and `GITHUB_ACCESS_TOKEN` (a PAT with `Contents: Read`, or the classic `repo`
   scope).
2. Create [`gitops/sync_from_git.yaml`](gitops/sync_from_git.yaml) in Kestra **once** — paste it
   into the UI editor, or POST it (see Option B). Adjust `url`, `branch`, and `targetNamespace`.
3. Run it. Every flow under `flows/` lands in `demo.wearedevelopers`.

From then on the schedule trigger (or the webhook trigger, if you point a GitHub webhook at it)
keeps Kestra in step with `main`.

Start with `dryRun: true` the first time — the task writes a diff of what it *would* change without
touching anything. Flip it to `false` once the diff looks right.

Two things worth knowing:

- `gitDirectory` defaults to `_flows`. This repo uses `flows/`, so the property is set explicitly.
- `sync_from_git` is in the `system` namespace, which makes it a
  [System Flow](https://kestra.io/docs/concepts/system-flows). To see it or its executions in the
  UI, set the **Scope** filter to `SYSTEM`.

**Requires the Git plugin** (`io.kestra.plugin.git`), which ships with the standard `kestra/kestra`
and `kestra-ee` images. On a `-slim` image, set `KESTRA_PLUGINS_AUTO_INSTALL_ENABLED=true` or
install `plugin-git` yourself. If the plugin is not available, use Option B.

### Option B — Push from CI/CD over the REST API

Works on any 2.0 instance, with or without plugins. This is what a GitHub Actions job should do on
every merge to `main`.

Kestra 2.0 is **multi-tenant by default**, so every flow API path is tenant-scoped:
`/api/v1/{tenant}/flows`. Replace `{tenant}` below with your tenant ID.

Validate first, then import the whole directory:

```bash
KESTRA_URL="http://localhost:8081"
TENANT="default"
AUTH="admin@kestra.io:your-password"   # or: -H "Authorization: Bearer $KESTRA_API_TOKEN"

# 1. Validate every flow — fails the build before anything is deployed
for f in flows/*.yaml; do
  curl -sf -u "$AUTH" -X POST \
    -H 'Content-Type: application/x-yaml' \
    --data-binary "@$f" \
    "$KESTRA_URL/api/v1/$TENANT/flows/validate"
done

# 2. Import the whole flows/ directory in one call
cd flows && zip -qr ../flows.zip . && cd ..
curl -sf -u "$AUTH" -X POST \
  -F "fileUpload=@flows.zip" \
  "$KESTRA_URL/api/v1/$TENANT/flows/import"
```

`/flows/import` accepts either a zip of YAML files or a single `.yaml`, and upserts — new flows are
created, existing ones get a new revision. It returns `[]` when everything imported cleanly.

To deploy a single flow instead:

```bash
# create
curl -u "$AUTH" -X POST -H 'Content-Type: application/x-yaml' \
  --data-binary @flows/server_health_report.yaml \
  "$KESTRA_URL/api/v1/$TENANT/flows"

# update (idempotent — use this in CI)
curl -u "$AUTH" -X PUT -H 'Content-Type: application/x-yaml' \
  --data-binary @flows/server_health_report.yaml \
  "$KESTRA_URL/api/v1/$TENANT/flows/demo.wearedevelopers/server_health_report"
```

And to trigger a run:

```bash
curl -u "$AUTH" -X POST -F 'cpu_threshold=80' \
  "$KESTRA_URL/api/v1/$TENANT/executions/demo.wearedevelopers/server_health_report"
```

### Option C — Terraform

For teams that already manage Kestra as infrastructure, the
[Kestra Terraform provider](https://kestra.io/docs/terraform) manages flows as resources. Kestra 2.0
requires provider version `~> 2.0`.

---

## Running the demo locally

This repo was developed against Kestra EE `2.0.2` in Docker:

| | |
|---|---|
| UI | http://localhost:8081/ui |
| Tenant | `default` |
| Namespace | `demo.wearedevelopers` |

Deploy and run without leaving the terminal:

```bash
AUTH="admin@kestra.io:your-password"

curl -u "$AUTH" -X POST -H 'Content-Type: application/x-yaml' \
  --data-binary @flows/server_health_report.yaml \
  "http://localhost:8081/api/v1/default/flows"

curl -u "$AUTH" -X POST -F 'dummy=1' \
  "http://localhost:8081/api/v1/default/executions/demo.wearedevelopers/server_health_report"
```

Then open the execution in the UI to walk the Topology and Gantt views on stage.

---

## Kestra 2.0 gotchas these flows account for

Worth knowing if you adapt these examples from older Kestra material:

- `ForEach` and `ForEachItem` are **removed**. Use `Loop`; `taskrun.value` → `item.value`,
  `taskrun.iteration` → `item.index`.
- Loop iterations are isolated, so task outputs **do not** escape the loop unless you declare them
  in the loop's `outputs:` block. Read them back with `loopOutputs(outputs.<loop>.outputs, '<id>')`.
- `pluginDefaults` is **removed** from flows.
- The `json()` Pebble function is **removed** — use `fromJson()`.
- Trigger `conditions` is renamed to `when`.
- Multi-tenancy is mandatory: all flow API routes are `/api/v1/{tenant}/...`.
- Input `defaults` requires `required: true`. Use `prefill` for optional inputs with a suggested
  starting value.

Full detail: [Kestra 2.0 migration guide](https://kestra.io/docs/migration-guide/v2.0.0) and
[What's New in 2.0](https://kestra.io/docs/whats-new-2-0).
