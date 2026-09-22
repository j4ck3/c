---
name: context7
description: Fetch current library and framework documentation from Context7 instead of relying on training data. Use for setup, API references, and code that involves a named library.
---

When the user asks about libraries, frameworks, or needs code examples, use Context7 MCP tools (`mcp__context7__resolve-library-id` then `mcp__context7__query-docs`).

## When to use

- Setup or configuration questions
- Code that involves a named library or framework
- API references
- Mentions of specific frameworks (React, Vue, Next.js, Prisma, Express, Tailwind, etc.)

## How to fetch docs

1. Call `resolve-library-id` with `libraryName` (official name, e.g. `Next.js`) and `query` (the user's full question).
2. Pick the best match: exact name, official source, version if the user named one, higher benchmark score.
3. Call `query-docs` with that `libraryId` (e.g. `/vercel/next.js`) and a focused `query`.
4. Answer from the fetched docs. Cite the library version when it matters.

Do not combine unrelated topics in one `query-docs` call. Prefer official packages over forks.
