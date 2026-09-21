# Booth operator guide

WeAreDevelopers World Congress NA 2026 — booth 615.

Six flows, three domains, two flows each: one that **answers a question**, one that
**changes something** and stops for human approval. All six are exposed as MCP tools, so
Claude Desktop on the booth laptop drives the whole demo.

The point the visitor should leave with: **the agent can look at anything, and it cannot change
anything without a human.**

---

## The six tools

| Domain | Read tool | Write tool | Namespace |
|---|---|---|---|
| Infra | `get_server_health` | `restart_host` | `demo.infra` |
| Data | `get_pipeline_status` | `backfill_orders` | `demo.data` |
| Apps | `get_service_status` | `restart_service` | `demo.apps` |

Read tools are annotated `readOnly: true, destructive: false`. Write tools are
`readOnly: false, destructive: true, idempotent: false` — Claude surfaces that before it calls them.

Each read tool is seeded so it finds exactly one problem, and the write tool in the same pair
fixes that problem:

| Read tool finds | Write tool fixes |
|---|---|
| `db-01` at 89% CPU (and `web-02` at 81%) | restart `db-01` |
| `orders_elt` failed, 2026-09-19 has no data | backfill `2026-09-19` |
| `checkout-api` degraded, p99 4200ms since v2.14.0 | restart `checkout-api` |

All data is mocked. No external credentials are needed anywhere.

---

## Run of show

Roughly 90 seconds per visitor.

1. **Hook.** "You know cron jobs? This is cron jobs on steroids — and it's what we let AI drive."
2. **Show the tool list in Claude.** Six tools. Point out that three are read-only and three are
   marked destructive. **Ask them to pick a domain: infra, data, or apps.**
3. **Ask the read question.** For infra: *"How is the fleet doing?"* Claude calls the tool — switch
   to Kestra and show the execution appear, then switch back for the answer.
4. **Ask for the action.** *"Restart db-01 then."* Claude calls the write tool — **and hangs.**
   The execution is sitting in `PAUSED`.
5. **Approve in the Kestra UI.** Open the paused execution, hit Resume, fill the approval form.
   The rollout runs and Claude's answer lands.
6. **Land it.** "The agent never got permission to touch production. A human did. And the whole
   thing is on the audit record."

Prompts that reliably hit the right tool:

| Domain | Read | Write |
|---|---|---|
| Infra | "How is the fleet doing?" | "Restart db-01" |
| Data | "Are the data pipelines healthy?" | "Backfill the gap you found" |
| Apps | "How are our services looking?" | "Restart checkout-api" |

---

## The one thing that can break the demo

**The MCP tool call blocks while the execution is paused.** Claude sits and waits for the whole
approval — it does not get told "waiting on approval" and come back later. Verified: the call stays
open and only returns once the execution finishes.

That is good theatre (Claude is visibly blocked on a human), but it means **you have to approve
reasonably promptly.** If Claude Desktop's tool-call timeout expires first, Claude reports an error
even though the Kestra execution is fine.

Rehearse the approval click before the floor opens. Target under 30 seconds from Claude calling the
tool to you hitting Resume — narrate while you walk to the other screen.

The gate is set to `pauseDuration: PT1H`. If a demo gets abandoned, the execution takes the
not-approved path and ends green rather than hanging or erroring.

---

## Connecting Claude Desktop

Claude Desktop does not speak HTTP MCP natively, so the config bridges through `mcp-remote`.

Generate the auth header value:

```bash
echo -n 'admin@kestra.io:YOUR_PASSWORD' | base64
```

Then in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "kestra-local": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "http://localhost:8081/api/v1/default/mcp/default",
        "--header", "Authorization: Basic PASTE_BASE64_HERE"
      ]
    }
  }
}
```

Restart Claude Desktop. The six tools appear under the `kestra-local` server.

> The `${VAR}` placeholder style shown in Kestra's Connect tab does **not** expand at connection
> time — paste the literal base64 value.

**Run only one server at a time in the config.** If both local and cloud are connected, Claude sees
twelve tools with duplicate names and picks unpredictably. Keep the second one commented out or in a
separate config, and switch deliberately.

---

## Verifying the connection without Claude

If the tools do not show up, check the server directly:

```bash
AUTH='admin@kestra.io:YOUR_PASSWORD'
URL='http://localhost:8081/api/v1/default/mcp/default'

SID=$(curl -s -D - -o /dev/null -u "$AUTH" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -X POST -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cli","version":"1"}}}' \
  "$URL" | grep -i 'mcp-session-id' | tr -d '\r' | cut -d' ' -f2)

curl -s -u "$AUTH" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Mcp-Session-Id: $SID" -X POST -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$URL" > /dev/null

curl -s -u "$AUTH" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Mcp-Session-Id: $SID" -X POST -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "$URL"
```

Six tools in the response means the booth demo will work.

---

## Reset between visitors

Nothing needs resetting — the flows are stateless and the mock data is fixed, so every visitor sees
the same problem and the same fix.

To clear the Executions list so it looks tidy:

```bash
AUTH='admin@kestra.io:YOUR_PASSWORD'
BASE='http://localhost:8081/api/v1/default'
IDS=$(curl -s -u "$AUTH" "$BASE/executions/search?size=200" \
  | python3 -c "import sys,json;print(json.dumps([e['id'] for e in json.load(sys.stdin)['results']]))")
curl -s -u "$AUTH" -X DELETE -H 'Content-Type: application/json' -d "$IDS" "$BASE/executions/by-ids"
```

Leaving a few successful executions up is fine, and arguably better — it shows the demo has been
run. Clear it if there are failures from a timed-out gate.

---

## Worth showing if they linger

- **Filter executions by `system.from: mcp`** — every agent-initiated run is labelled, alongside
  `system.mcpServerId` and `system.mcpSessionId`. That is the "what has the AI been doing" answer.
- **Namespaces** — `demo.infra` / `demo.data` / `demo.apps`. In EE, access control is granular down
  to the individual flow, so an agent can be given the read tools in one domain and nothing else.
- **The YAML** — every tool is a flow in Git. The `toolDescription` is what Claude reads to decide
  when to call it, so tool selection is reviewable in a pull request.
