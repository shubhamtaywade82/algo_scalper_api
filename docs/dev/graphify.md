# Graphify Development Guide

[Graphify](https://github.com/safishamsi/graphify) (`graphifyy` on PyPI) maps this Rails trading codebase into a queryable knowledge graph for Cursor agents and optional runtime RAG.

## Install

```bash
uv tool install "graphifyy[ollama,pdf,leiden,mcp]"
graphify cursor install --project
bin/install-graphify-hooks   # pre-commit AST refresh + merge driver + post-checkout
```

## Git Hooks (Pre-Commit)

AST graph refresh runs **before** each commit so `graphify-out/` lands in the same commit:

```bash
bin/install-graphify-hooks
```

- **Pre-commit** — `bin/graphify-pre-commit` → `bin/graphify-update` → stages `graph.json` / `manifest.json`
- **Post-checkout** — background rebuild on branch switch (from `graphify hook install`)
- **Merge driver** — union-merge for `graphify-out/graph.json` conflicts

Skip once: `GRAPHIFY_SKIP_HOOK=1 git commit ...`

## Bootstrap / Refresh Graph

```bash
# AST-only update (no LLM cost) — run after code changes
bin/graphify-update

# Full semantic extraction (docs/PDFs) — uses Ollama local or cloud from .env
bin/graphify-extract
```

### Ollama: Local vs Cloud

| Mode | Env | Notes |
|------|-----|-------|
| Local | `GRAPHIFY_OLLAMA_USE_CLOUD=false` (default) | `OLLAMA_BASE_URL=http://localhost:11434` |
| Cloud | `GRAPHIFY_OLLAMA_USE_CLOUD=true` | `OLLAMA_BASE_URL=https://ollama.com` + `OLLAMA_API_KEY` |

`bin/graphify-extract` reads `.env` and picks the endpoint automatically. Override model with `GRAPHIFY_OLLAMA_MODEL` or `OLLAMA_MODEL`.

Manual examples:

```bash
# Local
OLLAMA_BASE_URL=http://localhost:11434 OLLAMA_MODEL=llama3.2 \
  graphify extract ./docs --backend ollama

# Cloud
OLLAMA_BASE_URL=https://ollama.com OLLAMA_API_KEY=... OLLAMA_MODEL=gpt-oss:120b-cloud \
  graphify extract ./docs --backend ollama
```

## Query Commands

```bash
graphify query "signal engine entry guard pipeline" \
  --graph graphify-out/graph.json --budget 2000

graphify path "Signal::Engine" "Entries::EntryGuard" \
  --graph graphify-out/graph.json

graphify explain "RiskManagerService" \
  --graph graphify-out/graph.json
```

## PR Triage

```bash
graphify prs
GRAPHIFY_TRIAGE_BACKEND=ollama graphify prs --triage
graphify prs --conflicts --graph graphify-out/graph.json
```

## Committed Artifacts

| File | Policy |
|------|--------|
| `graphify-out/graph.json` | Commit |
| `graphify-out/GRAPH_REPORT.md` | Commit |
| `graphify-out/cache/` | Gitignored |
| `graphify-out/graph.html` | Gitignored |

## Runtime RAG (Optional)

`Graphify::ContextService.fetch` calls `graphify query` before LLM prompts. Returns empty string when the CLI or graph is missing — generation continues without RAG.

## MCP Server (Team Dev)

```bash
python -m graphify.serve graphify-out/graph.json \
  --transport http --host 0.0.0.0 --port 8080 --api-key "$GRAPHIFY_SECRET"
```

See `docs/dev/graphify-mcp.md` for Cursor MCP config.
