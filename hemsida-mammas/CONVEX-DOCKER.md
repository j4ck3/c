# Convex + TanStack in Docker Compose

Reference for running a Convex + Vite/React (and TanStack Query) app in Docker.

## Convex deployment URL

- **Client (browser):** Use `VITE_CONVEX_URL` so Vite exposes it as `import.meta.env.VITE_CONVEX_URL`.
- **Server (SSR/Node):** Must read the URL at **runtime** (e.g. `process.env.CONVEX_URL` or `process.env.VITE_CONVEX_URL`). If the server bundle inlines env at build time, the container env will be ignored.

From [Convex: Configuring Deployment URL](https://docs.convex.dev/client/react/deployment-urls):

- Vite: env vars for frontend must be prefixed with `VITE_` → use `VITE_CONVEX_URL`.
- Create the client with: `new ConvexReactClient(import.meta.env.VITE_CONVEX_URL)` (client) or `process.env.CONVEX_URL` / `process.env.VITE_CONVEX_URL` (server).

## Docker Compose env

In your compose service, pass the same URL to both client and server:

```yaml
environment:
  # Client (Vite) and server (Node) – server must read at runtime
  VITE_CONVEX_URL: ${VITE_CONVEX_URL}
  CONVEX_URL: ${VITE_CONVEX_URL}   # if your server code uses CONVEX_URL
  VITE_CONVEX_SITE_URL: ${VITE_CONVEX_SITE_URL}
```

In `.env`:

```env
VITE_CONVEX_URL=https://your-deployment.convex.cloud
VITE_CONVEX_SITE_URL=https://your-deployment.convex.site
```

## SSR / server bundle gotcha

If the app uses Vite SSR and the **server** creates a Convex client:

- Vite often inlines `import.meta.env.*` at **build time**. If the image is built without `VITE_CONVEX_URL`, the server bundle can have `undefined` for the URL and will fail at runtime even if the container has the env set.
- **Fix in app code:** In **server-only** code (e.g. SSR entry or Convex provider for server), use Node’s `process.env` so the value is read at runtime:
  - `process.env.CONVEX_URL || process.env.VITE_CONVEX_URL`
- **Fix at build time:** Build the Docker image with the env set, e.g. in Dockerfile:
  - `ARG VITE_CONVEX_URL` / `ENV VITE_CONVEX_URL=$VITE_CONVEX_URL` before `npm run build` (or use a build-time ARG and pass it in CI).

## TanStack Query (React Query)

TanStack Query is client-side only; no special Docker or Convex env is needed. Use it as usual inside your React tree (e.g. with Convex’s `ConvexProvider`). For Convex + TanStack, `@convex-dev/react-query` wires Convex reactivity to TanStack Query.

## Convex docs

- [Environment variables](https://docs.convex.dev/production/environment-variables)
- [Configuring deployment URL (React)](https://docs.convex.dev/client/react/deployment-urls)
- Convex backend **self-hosted** (optional): [convex-backend self-hosted](https://github.com/get-convex/convex-backend/tree/main/self-hosted) has Docker Compose for running Convex yourself; your current setup uses Convex Cloud (single URL in env).
