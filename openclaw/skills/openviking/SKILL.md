---
name: openviking
description: >
  Long-term memory and semantic search via OpenViking context database.
  Use when you need to: remember important information across sessions,
  index documents or URLs into a knowledge base, search for context by meaning,
  browse or explore previously indexed resources, get summaries/overviews of
  indexed documents, or retrieve relevant context for sub-agent tasks.
  Trigger words: "remember this", "search memory", "index this document",
  "find in knowledge base", "long-term memory", "recall", "look up in resources".
metadata: {"clawdis":{"emoji":"🧠","requires":{"bins":[]},"primaryEnv":null}}
---

# OpenViking — Long-Term Memory & Context Database

OpenViking is running as a server on this network. Use it for persistent memory,
document indexing, and semantic search across sessions.

## Server Connection

- **URL**: `http://openviking:1933`
- **Auth header** (required on every request): `Authorization: Bearer ov-internal-docker-key`
- **API docs**: `http://openviking:1933/docs`

## Core Commands

All commands use `curl`. Always include the auth header.

### Add a resource (URL or file path)

```bash
curl -s -X POST http://openviking:1933/api/v1/resources \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json" \
  -d '{"path": "https://example.com/article"}'
```

### Semantic search (find by meaning)

```bash
curl -s -X POST http://openviking:1933/api/v1/search/find \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json" \
  -d '{"query": "YOUR SEARCH QUERY", "limit": 5}'
```

### Grep (pattern match in content)

```bash
curl -s -X POST http://openviking:1933/api/v1/search/grep \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json" \
  -d '{"pattern": "PATTERN", "uri": "viking://resources/"}'
```

### List directory contents

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  "http://openviking:1933/api/v1/fs/ls?uri=viking://resources/"
```

### Tree view

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  "http://openviking:1933/api/v1/fs/tree?uri=viking://resources/&depth=2"
```

### Read full content (L2)

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  "http://openviking:1933/api/v1/content/read?uri=viking://resources/my_doc"
```

### Get abstract (L0 — one-sentence summary)

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  "http://openviking:1933/api/v1/content/abstract?uri=viking://resources/my_doc"
```

### Get overview (L1 — structured summary)

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  "http://openviking:1933/api/v1/content/overview?uri=viking://resources/my_doc"
```

### System status

```bash
curl -s -H "Authorization: Bearer ov-internal-docker-key" \
  http://openviking:1933/api/v1/system/status
```

### Health check (no auth needed)

```bash
curl -s http://openviking:1933/health
```

## Session Memory (auto-extraction)

OpenViking supports session-based memory extraction.

```bash
# Create a session
curl -s -X POST http://openviking:1933/api/v1/sessions \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"source": "openclaw"}}'

# Add messages to a session
curl -s -X POST http://openviking:1933/api/v1/sessions/SESSION_ID/messages \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]}'

# Extract memories from session
curl -s -X POST http://openviking:1933/api/v1/sessions/SESSION_ID/extract \
  -H "Authorization: Bearer ov-internal-docker-key" \
  -H "Content-Type: application/json"
```

## When to Use OpenViking

1. **Storing important context**: When the user shares important preferences, project
   details, or reference material — index it into OpenViking for future recall.
2. **Research tasks**: Before writing or analyzing, search OpenViking for previously
   indexed relevant content to provide better context.
3. **Sub-agent context**: When delegating tasks to sub-agents, search OpenViking first
   and pass relevant results as context (saves tokens vs stuffing full documents).
4. **Cross-session recall**: Information stored in OpenViking persists across conversations.

## Context Layers

OpenViking stores content in three layers:
- **L0 (Abstract)**: One-sentence summary (~100 tokens) — quick relevance check
- **L1 (Overview)**: Core info and structure (~2k tokens) — planning and decisions
- **L2 (Details)**: Full original content — deep reading when necessary

Always try L0/L1 first before loading full L2 content to save tokens.

## Tips

- Wait a moment after indexing before searching — OpenViking processes content
  asynchronously (generates embeddings and summaries via VLM).
- Use descriptive search queries — OpenViking performs semantic matching, not keyword search.
- For large document collections, index them once and search repeatedly.
- If a request returns 401/403, the auth header is missing or wrong.
- Visit `http://openviking:1933/docs` for interactive API documentation.
