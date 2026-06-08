# app-praxis — Praxis on Quant Cloud

A Quant Cloud template that deploys the [Praxis framework](https://github.com/steveworley/praxis-framework) dashboard backed by Quant Cloud inference. One Quant application hosts one Praxis role.

## What you get

- **The Praxis dashboard** at the environment URL — `/setup` for the wizard, `/chat` for the role's conversational runtime, `/triage` for the operator's triage queue, `/role` for the role's interior, plus the rest of the supervisor surfaces.
- **Quant Cloud inference** via `@praxis-framework/inference-quantcloud`. `claude-sonnet-4-6` by default; override via `PRAXIS_CHAT_MODEL`.
- **EFS-backed persistence at `/role`.** The role's persona, memory, escalations, output, verbs, lib reference data, decision logs, and `.git` audit history all live on the volume. Redeploys preserve everything.
- **The Quant MCP sidecar.** A bundled `mcp-quant` container exposes the Quant API to the role as MCP tools — see below.

## Quant MCP — let the role manage your stack

This template bundles **`mcp-quant`**, a standard MCP server that exposes the Quant API to the role as tools. It runs as an internal sidecar alongside the dashboard; the role reaches it via `PRAXIS_MCPS=quant=http://mcp-quant:8080/mcp`. Through it the role can administer the Quant stack (projects, domains, cache, crawls) **and** drive Quant's agentic platform — listing and chatting with your Quant **AI agents** and executing your **custom edge-function tools**, which surface automatically as the role's tools (build them on Quant; the role picks them up).

- **Credentials:** the sidecar authenticates to Quant with the same `QUANT_API_TOKEN` / `QUANT_ORGANISATION` secrets the dashboard already uses (declared on both containers in `quant/compose.json`).
- **Internal-only:** `mcp-quant` must not be publicly exposed. The dashboard→MCP hop is unauthenticated and trusts network isolation — the sidecar holds the API token; the dashboard never forwards it.
- **Enable it on the role:** the capability ships in the framework catalog as `mcp:quant`. Select it during `/setup` (or add `mcp:quant` under `capabilities:` in the role's `lib/tools.yaml`), then allow it in `lib/autonomy.yaml`:
  ```yaml
  mcps:
    quant: allow
  ```
  If `mcp:quant` is declared but the sidecar isn't reachable, `/health` surfaces an MCP drift warning.

## One-time pre-step (operator)

Before the first deploy, **create a logical volume named `role`** in the Quant dashboard for the application's environment:

1. Open the Quant dashboard → your application → environment → **Volumes** tab.
2. Click **Define New Logical Volume**.
3. Name: `role`. Description: "Praxis role-home (persona, memory, audit `.git`)".
4. Save.

Quant assigns the underlying EFS access point. The `compose_spec` shipped with this template mounts the volume at `/role` inside the container.

> ⚠️ Deleting the volume definition in Quant does **not** necessarily delete the underlying EFS data — but treat the EFS volume as the source of truth for the role. Take snapshots out-of-band for production roles.

## Required GitHub secrets

Configure these on the `app-praxis` repo:

| Secret | Purpose |
|---|---|
| `QUANT_API_KEY` | Used by `quant-cloud-init-action` + `quant-cloud-environment-action`. |
| `QUANT_ORGANIZATION` | Quant org (US spelling — Quant's GHA inputs use this form). |

## Required environment secrets (Quant-side)

On the Quant environment, configure the following secrets so the runtime container can call the Quant inference API:

| Secret | Purpose |
|---|---|
| `QUANT_API_TOKEN` | Bearer token for the AI Inference API. |
| `QUANT_ORGANISATION` | Organisation id (note: i18n spelling — the praxis provider reads this var). |

The shipped `quant/compose.json` declares both secrets in the container's `secrets` array; Quant injects them at container start.

## Optional environment variables

| Var | Default | Purpose |
|---|---|---|
| `QUANT_BASE_URL` | `https://dashboard.quantcdn.io` | Override for QuantGov (`https://dash.quantgov.cloud`). Trailing `/api/v3` accepted. |
| `QUANT_PREFER_STREAMING` | `true` | Set `false` only when needing Quant's server-side `autoExecute` cloud tools. |
| `PRAXIS_OPERATOR_NAME` | `Quant Operator` | Author name for operator-side audit commits. |
| `PRAXIS_OPERATOR_EMAIL` | `operator@quant.cloud` | Author email for operator-side audit commits. |
| `PRAXIS_CHAT_MODEL` | `claude-sonnet-4-6` | Model the chat surface routes requests to. |
| `PRAXIS_LOG_GLOB` | `**/logs/*.jsonl` | Activity-feed glob (rooted at role-home). |

## First-deploy flow

1. Push to `main` (or fork this template and push to `main` on your fork). The GHA workflow builds the image, creates the environment if it doesn't exist, and uploads the image.
2. Open the environment URL in your browser. You'll land on `/setup`.
3. Walk the wizard: pick a role name, voice, capabilities, hard inhibitions. Submit. Two visible git commits land on the `/role` volume.
4. The role is now operable. Use `/chat` to talk to it, `/triage` to review what it raises.

## Local development

```bash
mkdir role-home
QUANT_API_TOKEN=… QUANT_ORGANISATION=… docker compose up
```

Open `http://localhost:4321/`. The host `./role-home` directory is the role-home — commits land on the host clone so you can `git log` the role's growth from your shell.

## Upgrading the underlying Praxis dashboard

The template's Dockerfile pins `ghcr.io/steveworley/praxis-framework/dashboard:latest`. Tag a new release of `app-praxis` (or just push to `main`) to rebuild against the latest framework dashboard.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Boot log: `praxis: ERROR /role is not mounted` | The logical volume isn't declared or the compose_spec mount didn't bind. Verify volume `role` exists in the Quant dashboard. |
| Boot log: `praxis: ERROR /role is not writable by uid 1000` | EFS access point isn't permissioned for UID 1000. Check the volume's access-point config in Quant. |
| `/chat` shows "Chat is disabled — QUANT_API_TOKEN / QUANT_ORGANISATION are not set" | Inference credentials missing from the environment. Add them as Quant secrets and redeploy. |
| Audit commits show `Author: Quant Operator <operator@quant.cloud>` and you wanted your name | Set `PRAXIS_OPERATOR_NAME` and `PRAXIS_OPERATOR_EMAIL` on the environment and redeploy. |
| `/setup` wizard refuses to seed | Working tree has uncommitted changes on `/role`. Check `git status` against the volume (e.g. by shelling into the container). |

## License

MIT.
