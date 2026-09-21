# Kestra Demo Flows - We Are Developers 2026

Demo flows for the San Jose We Are Developers 2026 conference, built for **Kestra 2.0**.

The booth demo is six flows across three domains, all exposed as MCP tools and driven from Claude
Desktop. A visitor picks their domain; we run the read tool to answer a question, then the write
tool, which stops for human approval before it changes anything.

**[BOOTH.md](BOOTH.md) is the operator guide** - tool list, Claude Desktop config, run of show, and
the one thing that can break the demo. Read that before the floor opens.

```
flows/     the six booth flows (this is the GitOps source of truth)
gitops/    the bootstrap flow that pulls flows/ into Kestra - not itself synced
archive/   superseded demos, kept for reference and not deployed
```

---

## The six flows

| Domain | Read tool | Write tool | Namespace |
|---|---|---|---|
| Infra | [`server_health_report`](flows/server_health_report.yaml) &rarr; `get_server_health` | [`restart_host`](flows/restart_host.yaml) &rarr; `restart_host` | `demo.infra` |
| Data | [`pipeline_status`](flows/pipeline_status.yaml) &rarr; `get_pipeline_status` | [`backfill_orders`](flows/backfill_orders.yaml) &rarr; `backfill_orders` | `demo.data` |
| Apps | [`service_status`](flows/service_status.yaml) &rarr; `get_service_status` | [`restart_service`](flows/restart_service.yaml) &rarr; `restart_service` | `demo.apps` |

Every flow follows the same shape, so the story is identical whichever domain the visitor picks.

**Read flows** gather mock telemetry, then expose the answer through flow-level `outputs:` - which
is what the MCP tool returns to Claude. Annotated `readOnly: true`.

**Write flows** estimate the change first, then hit a `Pause` with `onResume` inputs. Nothing
happens until a human approves in the UI. Annotated `destructive: true`. The decision is guarded so
an expired gate means no change rather than a failed execution.

All data is mocked - no external credentials anywhere. Each simulated task names the real task type
it stands in for.

### What this demonstrates

- **MCP tool registration** - `McpToolTrigger` turns each flow into a named tool with a
  JSON schema generated from its inputs, and annotations that tell the agent about side effects.
- **Human-in-the-loop governance** - the agent can read anything and change nothing on its own.
- **Observability of agent actions** - every MCP-initiated run is labelled `system.from: mcp`
  with the server and session id.
- **Namespaces** - one per domain, which in EE maps onto access control granular to the flow.

---

## Archived demos

[`archive/`](archive/) holds the earlier single-demo flows (`ai_incident_response`,
`daily_orders_elt`). They are not deployed and not registered as MCP tools - keeping them out of
`flows/` is what keeps the tool list at exactly six. Move one back into `flows/` to bring it back.

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
3. Run it. Set `targetNamespace` per domain, or use `includeChildNamespaces` - the six flows
   declare `demo.infra`, `demo.data` and `demo.apps` themselves.

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
  "$KESTRA_URL/api/v1/$TENANT/flows/demo.infra/server_health_report"
```

And to trigger a run:

```bash
curl -u "$AUTH" -X POST -F 'cpu_threshold=80' \
  "$KESTRA_URL/api/v1/$TENANT/executions/demo.infra/server_health_report"
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
| Namespaces | `demo.infra`, `demo.data`, `demo.apps` |

Deploy all six flows and run them without leaving the terminal:

```bash
AUTH="admin@kestra.io:your-password"
BASE="http://localhost:8081/api/v1/default"

# deploy everything under flows/
cd flows && zip -qr ../flows.zip . && cd ..
curl -u "$AUTH" -X POST -F "fileUpload=@flows.zip" "$BASE/flows/import" && rm flows.zip

# run them
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.infra/server_health_report"
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.data/pipeline_status"
curl -u "$AUTH" -X POST -F 'd=1' "$BASE/executions/demo.apps/service_status"
```

The three write flows sit in `PAUSED` until you approve them from the UI. Normally you drive all six
through Claude Desktop instead - see [BOOTH.md](BOOTH.md).

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
- An MCP `tools/call` **blocks for the entire execution**, including while it sits in `Pause`. The
  agent is not told "waiting on approval" and does not poll - the call stays open until the
  execution finishes. Approve promptly or the client times out.
- Flow-level `outputs:` are what the MCP tool returns, and they do **not** appear on the execution
  in `GET /executions/{id}` (the field is `null`). Verify them through an MCP `tools/call`, not the
  execution API.
- When a `Pause` auto-resumes on `pauseDuration` expiry, `onResume` is **not populated at all** —
  not even with the defaults declared on those inputs. An unguarded
  `{{ outputs.<pause>.onResume.<id> }}` then fails the execution. Guard it with
  `{{ outputs.<pause>.onResume is defined and ... }}`. `outputs.<pause>.resumed` *is* always
  populated, as `{"on": <timestamp>, "to": <state>}`.

Full detail: [Kestra 2.0 migration guide](https://kestra.io/docs/migration-guide/v2.0.0) and
[What's New in 2.0](https://kestra.io/docs/whats-new-2-0).
