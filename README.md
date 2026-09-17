# Kestra Demo Flows — We Are Developers 2026

Demo flows for the San Jose We Are Developers 2026 conference, built for **Kestra 2.0**.

Every flow here is designed to be **explained and executed in under a minute** on stage, and to be
deployed to any Kestra 2.0 instance straight from this repository.

```
flows/     flows synced into Kestra (this is the GitOps source of truth)
gitops/    the bootstrap flow that pulls flows/ into Kestra — not itself synced
```

---

## The demos

Two flows, each standalone and each explainable in about a minute:

| Flow | Story | Runs in |
|---|---|---|
| [`ai_incident_response`](flows/ai_incident_response.yaml) | **Booth demo** — agentic AI incident response with a human approval gate | ~2s + approval |
| [`server_health_report`](flows/server_health_report.yaml) | Infrastructure guardrail — check a fleet, page on-call if a host is over budget | ~2s |
| [`daily_orders_elt`](flows/daily_orders_elt.yaml) | Data pipeline — extract, load, dbt build, quality gate | ~3s |

`ai_incident_response` is the one agreed for the WeAreDevelopers booth in the
[Demo quick sync](https://docs.google.com/document/d/1mdr7aLlM6Rh3RtU4bZ-DO2A69iWZfMGTAabU49uD86c/edit)
(Sep 17, 2026). The other two are backups for deeper technical conversations.

---

## Booth demo: `ai_incident_response`

[`flows/ai_incident_response.yaml`](flows/ai_incident_response.yaml)

An alert fires. An AI agent gathers context across all four orchestration domains at once, proposes
a root cause and a remediation — **and then stops**. Nothing touches production until a human
approves. Kestra executes the approved action deterministically and records the decision.

This is the agentic AI narrative from the messaging brief, made concrete: *"Kestra serves as both an
execution and governance layer... apply permissions, approval gates, audit trails, monitoring, and
failure controls to agent actions."* The agent decides; the orchestrator enforces.

### Why this flow, and where it came from

From the Demo quick sync:

- **Fernando** — structure it as "an incident remediation scenario where an agent aggregates data,
  requests human approval, and executes corrective actions", and show MCP so agents can invoke flows.
- **Robert** — an AI incident response demo showing data summarization from multiple sources, with
  dummy data, highlighting governance and granular access control.
- **Melissa** — one high-impact demo, not several. 30–60 seconds to capture attention; narrated
  video 1–2 minutes.

Mapped onto the four domains from the messaging brief — the agent reads all of them in parallel,
which is the unified-orchestration point:

| Domain | What the agent pulls |
|---|---|
| Infrastructure automation | pod health, CPU, OOMKills |
| Data orchestration | upstream pipeline state, schema drift |
| Application / microservice ops | recent deploys and last stable version |
| Business process automation | support ticket volume, accounts affected |

### The 60-second booth script

| Beat | Say this | ~Time |
|---|---|---|
| 0 | *Hook:* "You know cron jobs? This is cron jobs on steroids." | 5s |
| 1 | "Checkout is down. One agent pulls context from four places at once — infra, data pipelines, deploys, and the support queue. Most tools only see one of those." | 15s |
| 2 | "It gives you a root cause, a blast radius, a confidence score, and what it wants to do about it." | 10s |
| 3 | **"And then it stops."** "The agent is not allowed to touch production. It needs a human." — point at the paused execution | 10s |
| 4 | Click **Resume**, approve. "Now Kestra runs the rollback — deterministically, with the whole thing on the audit record." | 15s |
| 5 | "And this flow is registered as an MCP tool. Claude or Cursor can call it directly — and still hits the same approval gate." | 10s |

**The encore.** Reject instead of approving. Nothing happens to production and on-call gets paged.
Same for a gate that expires — no approval means no change.

### What it demonstrates

- **Human-in-the-loop governance** — `Pause` with `onResume` inputs. The execution genuinely stops;
  this is the moment that sells the story.
- **MCP tool registration** — `McpToolTrigger` exposes the flow as a tool named
  `respond_to_incident`, with annotations (`destructive: true`, `idempotent: false`) that tell the
  calling agent this has real side effects.
- **Audit trail** — `Labels` stamps severity, service and agent confidence onto the execution, so
  incidents are filterable after the fact rather than buried in logs.
- **Cross-domain context** — `Parallel` fan-out across the four domains.
- **Fail-safe defaults** — no approval means no production change, whether rejected or timed out.

### Simulated vs. real

The agent reasoning and the remediation calls use dummy data, so it runs anywhere with no model
credentials and no extra plugins. Each simulated task names what it stands in for:

| Step | Demo uses | Real pipeline uses |
|---|---|---|
| Gather context | `log.Log` ×4 in `Parallel` | prometheus / JDBC / GitHub / `servicenow.Get` |
| Agent triage | `output.OutputValues` | `io.kestra.plugin.ai.agent.AIAgent`, or `ai.completion.JSONStructuredExtraction` to force the schema |
| Remediation | `log.Log` | the helm / kubernetes / argocd task |

Bring any model, including a self-hosted one — the governance around it does not change.

### Running it

```bash
AUTH="admin@kestra.io:your-password"
BASE="http://localhost:8081/api/v1/default"

curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.wearedevelopers/ai_incident_response"
```

The execution runs to the approval gate and sits in `PAUSED`. **Approve it from the UI** — open the
execution and use the Resume button, which prompts for the `approved` and `approver_note` inputs.

> The gate is set to `pauseDuration: PT1H`. If it expires, the flow takes the not-approved path and
> ends green rather than hanging or erroring.

---

## Backup demo: `server_health_report`

[`flows/server_health_report.yaml`](flows/server_health_report.yaml) — a nightly infrastructure
guardrail. It checks every server in a fleet against a CPU threshold, rolls the results into one
report, and pages the on-call engineer if any host is over budget.

Each host is sized like a real cloud instance — vCPU maxima are powers of two (8, 16, 32, 64) and
utilization is derived from cores in use over that maximum, so the numbers on screen are ones a
platform engineer would actually recognize.

It uses **core tasks only** — no credentials, no network calls, no plugins to install. Clone, sync,
run. It finishes in about two seconds.

### The 60-second script

| Beat | Say this | ~Time |
|---|---|---|
| 1 | "This whole workflow is one YAML file, and it lives in Git — not in the UI." | 5s |
| 2 | "It takes inputs: which environment, and what percentage of a box's vCPUs counts as too hot." | 10s |
| 3 | "It loops over the fleet. In Kestra 2.0, **every loop iteration is its own isolated sub-execution** — so looping over 4 servers and looping over 40,000 behave the same way. No single flow can take down the instance." | 15s |
| 4 | "Each server reports cores in use against its vCPU maximum — 13 of 16, 57 of 64 — and we turn that into a verdict." | 10s |
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
  - web-01 using 3 of 8 vCPU (37%) -> OK
  - web-02 using 13 of 16 vCPU (81%) -> OK
  - api-01 using 21 of 32 vCPU (65%) -> OK
  - db-01 using 57 of 64 vCPU (89%) -> OK

All servers within budget.
```

At an 80% threshold the run **fails on purpose**:

```
PROD fleet report - 4 servers checked against a 80% threshold.
  - web-02 using 13 of 16 vCPU (81%) -> BREACH
  - db-01 using 57 of 64 vCPU (89%) -> BREACH
  - api-01 using 21 of 32 vCPU (65%) -> OK
  - web-01 using 3 of 8 vCPU (37%) -> OK

ERROR  CPU budget breached in prod - page the on-call engineer.
```

> Report lines are not in a fixed order — `concurrencyLimit: 4` means the four servers are checked
> concurrently. Set `concurrencyLimit: 1` if you want deterministic ordering on stage.

> Per-server logs live in the **sub-executions**, not the parent. Click into any loop iteration in
> the Gantt or Topology view to see them. The parent execution shows the rolled-up report.

---

## Backup demo: `daily_orders_elt`

[`flows/daily_orders_elt.yaml`](flows/daily_orders_elt.yaml) — the data-team counterpart: extract
orders and customers from the app database, load them into the warehouse, transform with dbt, and
gate on data quality before anyone downstream is allowed to trust the result.

**The warehouse and dbt connections are simulated.** The pipeline runs anywhere with no credentials
and no extra plugins, and every simulated task carries a comment naming the real task type you would
swap in. The shape of the pipeline — and everything it demonstrates about Kestra — is unchanged:

| Stage | Demo uses | Real pipeline uses |
|---|---|---|
| Extract | `storage.Write` (two sources, in `Parallel`) | `jdbc.postgresql.Query` with `fetchType: STORE` |
| Load | `log.Log` printing the `COPY INTO` | `snowflake.Query` / your warehouse's bulk load |
| Transform | `flow.Loop` over the model list | `dbt.cli.Build` |
| Quality gate | `execution.Assert` | `dbt.cli.Test` |

### The 60-second script

| Beat | Say this | ~Time |
|---|---|---|
| 1 | "Two sources, extracted **in parallel** — you can see both branches light up at once." | 10s |
| 2 | "They land in Kestra's internal storage, and the load step gets the URI. That's a real file — it's in the Outputs tab." | 10s |
| 3 | "Then dbt builds four models. Each one is its own node, so you can see exactly where a build died." | 10s |
| 4 | "And here's the part that matters: a **quality gate**. Every model has to produce rows and the extract has to be non-empty, or nothing downstream runs." | 15s |
| 5 | "Cleanup is in a `finally` block, so staging files get purged even when the run fails." | 10s |

**The encore.** Set any model's `rows` to `0` in the `dbt_models` variable and re-run. The gate
fails with `Data quality gate failed - holding the snowflake release.`, `publish_metrics` and
`summary` never run — and `cleanup` still does, because it is in `finally`. That contrast is the
whole point of the flow.

### What it shows off

- **`Parallel`** — fan out the extracts, no orchestration code.
- **Internal storage** — `Write` returns a `kestra://` URI that the next task consumes, the same
  handoff a real query task gives you.
- **`Assert`** — a first-class data-quality gate. Each condition is logged individually when it fails.
- **`finally`** — cleanup that runs whether the pipeline succeeded or not.
- **`metric.Publish`** — row counts land in the execution's Metrics tab, tagged by warehouse.

### Expected output

```
Loading into SNOWFLAKE.
  COPY INTO raw.orders    FROM 'kestra:///demo/wearedevelopers/daily-orders-elt/.../...jsonl'    FILE_FORMAT = (TYPE = JSON);
  COPY INTO raw.customers FROM 'kestra:///demo/wearedevelopers/daily-orders-elt/.../...jsonl' FILE_FORMAT = (TYPE = JSON);
Staged 385 bytes of orders.

SNOWFLAKE refreshed - 4 models built, quality gate passed.
  - stg_orders (1284 rows)
  - stg_customers (417 rows)
  - fct_orders (1284 rows)
  - mart_revenue_daily (30 rows)
```

The `warehouse` input switches the target between Snowflake, BigQuery and Postgres, and
`full_refresh` toggles `--full-refresh` onto the rendered dbt command — both only change what is
printed, but they make the point that inputs drive real behaviour.

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

Deploy all three flows and run them without leaving the terminal:

```bash
AUTH="admin@kestra.io:your-password"
BASE="http://localhost:8081/api/v1/default"

# deploy everything under flows/
cd flows && zip -qr ../flows.zip . && cd ..
curl -u "$AUTH" -X POST -F "fileUpload=@flows.zip" "$BASE/flows/import" && rm flows.zip

# run them
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.wearedevelopers/server_health_report"
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.wearedevelopers/daily_orders_elt"
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.wearedevelopers/ai_incident_response"
```

`ai_incident_response` will sit in `PAUSED` until you approve it from the UI.

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
- Pebble does **integer division**: `used / vcpus` evaluates to `0`. Multiply before dividing
  (`used * 100 / vcpus`), which is why the utilization expression is written that way.
- You cannot compare a task output to a number — `outputs.x.values.y > 90` throws
  `invalid operands for mathematical comparison`, because outputs are strings. Do the arithmetic
  and the comparison in the same expression, or push the numbers through `jq` with `tonumber`.
- `metric.Publish` metrics take `name`, not `id`. Using `id` fails at runtime with the
  unhelpful `No value present`.
- When a `Pause` auto-resumes on `pauseDuration` expiry, `onResume` is **not populated at all** —
  not even with the defaults declared on those inputs. An unguarded
  `{{ outputs.<pause>.onResume.<id> }}` then fails the execution. Guard it with
  `{{ outputs.<pause>.onResume is defined and ... }}`. `outputs.<pause>.resumed` *is* always
  populated, as `{"on": <timestamp>, "to": <state>}`.

Full detail: [Kestra 2.0 migration guide](https://kestra.io/docs/migration-guide/v2.0.0) and
[What's New in 2.0](https://kestra.io/docs/whats-new-2-0).
