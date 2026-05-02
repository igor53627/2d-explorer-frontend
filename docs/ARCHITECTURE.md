# Architecture

`frontend-ex` is a Phoenix SSR application intended to replace `fast-frontend` (Rust) while keeping byte-for-byte HTML output parity per skin.

## Request Flow

```
Browser
  -> Phoenix Endpoint (Bandit)
    -> Router pipeline
      -> Controller
        -> (optional) Blockscout API client
        -> EEx templates (skin-specific root layout + content fragments)
      -> Response (HTML)
```

## Router Pipelines

- `:fast_browser`
  - Used for parity routes.
  - No session/CSRF plugs (avoid extra HTML/meta tags and cookies).
  - Sets a skin-specific root layout via `FrontendExWeb.Plugs.FastLayout`.
  - Disables view layouts (`put_layout false`) to keep HTML 1:1.
  - Trims the final trailing newline via `FrontendExWeb.Plugs.TrimTrailingNewline` to match Askama output.

- `:browser`
  - Standard Phoenix pipeline (currently unused).
  - Reserved for future non-parity pages (e.g. LiveView/admin/debug) where sessions/CSRF are acceptable.

## Skins

The 2d fork supports only the `classic` skin —
`lib/frontend_ex_web/fast_layouts/classic.html.eex`. `FrontendExWeb.Skin.current/0`
always returns `:classic`; the upstream `FF_SKIN` env var was removed.

## Templates and Parity

Parity-critical rendering uses `.html.eex` (not HEEx) to minimize framework-driven formatting.

Key configuration:

- `config :phoenix_template, :trim_on_html_eex_engine, false`
  - Prevents whitespace trimming in HTML EEx templates.

## Upstream API Client

`FrontendEx.Blockscout.Client` wraps `Req` + a shared `Finch` pool.

- Base URL: `BLOCKSCOUT_API_URL`
- Timeouts: 10s (connect + receive)
- Request adapter is pluggable via `:frontend_ex, :blockscout_request_adapter`:
  - Default: `FrontendEx.Blockscout.RequestAdapter.Req` (real HTTP)
  - Tests: `FrontendEx.Blockscout.RequestAdapter.Fixture` (reads on-disk fixtures)

`get_json/1` (uncached) error mapping/retry behavior follows `fast-frontend/src/api/client.rs`:
  - 404 -> `:not_found` (no retry)
  - 429/5xx/transport -> retry once after 250ms
  - invalid JSON -> retry up to 3 attempts; then treat as `:not_found`

`get_json_cached/2` uses the standard cache (60s) and also negative-caches `:not_found` for a short TTL (5s). Callers must pass a cache context (e.g. `:public`) that includes any inputs that can vary the upstream response:

- `:not_found` -> cached for 5s (returned to callers as `{:error, :not_found}`)
- Other upstream errors are not cached and are returned as-is.

## Cursor Pagination

Blockscout v2 uses cursor (keyset) pagination via `next_page_params`.

Helpers:

- `FrontendEx.Blockscout.Cursor`
  - Builds a `k=v&k2=v2...` query string from `next_page_params`.
  - Encodes it as a single `cursor=` value by percent-encoding the full string.

- `FrontendExWeb.CursorLinks`
  - Builds deterministic query strings, merges existing query params, and safely encodes `cursor`.

Important nuance:

- Plug/Phoenix decode query params once. If you read `cursor` from `conn.params`, it is already decoded and may contain `&`.
- When placing a cursor back into a link, encode the decoded cursor query string before embedding it in `cursor=...` (handled by `FrontendExWeb.CursorLinks.with_cursor/3`).

## Caching

- `FrontendEx.Application` starts in-memory caches for Blockscout API responses.

`FrontendEx.Cache` implements a standard TTL cache with request coalescing (`FrontendEx.ApiCache`).

- TTL: 60s (per entry, matching Rust's standard cache)
- Cache key: `{context, kind, url}` where `url` is full URL (base URL + path + query)

`FrontendEx.Cache.SWR` implements stale-while-revalidate caching (`FrontendEx.ApiSWRCache`).

- 0-5s: serve fresh from cache
- 5-20s: serve stale and refresh in background (deduped per key)
- >20s: fetch fresh before serving (coalesced per key)

Note: Rust uses a separate "immutable" 300s TTL cache for tx/block-by-hash. `frontend-ex` approximates this by using the standard cache with a per-call TTL override (e.g. tx-by-hash and tx tab API calls use 300s TTL).

## Static Assets

For parity, `frontend-ex` serves static assets at `/static/**` (CSS/JS) copied from `fast-frontend/static/**` into `priv/static/static/**`.

## Parity Tests

- Golden HTML snapshots live under `test/golden/` and are compared byte-for-byte in tests.
- Blockscout API calls are served from fixtures in tests (no network). See `config/test.exs` for fixture adapter configuration.
