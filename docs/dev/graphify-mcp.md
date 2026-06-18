# Graphify MCP Server

Exposes the knowledge graph to team assistants. Rails uses the CLI via `Graphify::ContextService` — MCP is for development tooling.

## Install MCP Extra

```bash
uv tool install "graphifyy[mcp]"
```

## Run Server

```bash
python -m graphify.serve graphify-out/graph.json \
  --transport http \
  --host 0.0.0.0 \
  --port 8080 \
  --api-key "$GRAPHIFY_SECRET"
```

## Environment Variables

- `GRAPHIFY_GRAPH_PATH` — path to committed graph (default: `graphify-out/graph.json`)
- `GRAPHIFY_MCP_URL` — HTTP MCP endpoint
- `GRAPHIFY_SECRET` — Bearer token for MCP auth
- `GRAPHIFY_TOKEN_BUDGET` — default query budget (2000)
- `GRAPHIFY_QUERY_TIMEOUT` — CLI timeout in seconds (3)

## Cursor MCP Config

Project-local config is written by `bin/install-graphify-cursor` to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "graphify": {
      "command": "graphify-mcp",
      "args": ["graphify-out/graph.json"]
    }
  }
}
```

For a shared HTTP server (team), use instead:

```json
{
  "mcpServers": {
    "algo-scalper-graph": {
      "url": "http://localhost:8080/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_SECRET"
      }
    }
  }
}
```

## Available Tools

- `query_graph` — subgraph retrieval within token budget
- `get_node` / `get_neighbors` — local graph navigation
- `shortest_path` — structural path between concepts
- `list_prs` / `get_pr_impact` / `triage_prs` — PR impact analysis
