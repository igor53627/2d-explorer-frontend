# 2d-explorer-frontend

Phoenix SSR block-explorer frontend for [2d](https://github.com/igor53627/2d) — a fork of [`igor53627/frontend-ex`](https://github.com/igor53627/frontend-ex) trimmed to the surface 2d actually has.

> **This is a 2d-specific fork.** If you want a general-purpose Blockscout SSR frontend, use upstream `frontend-ex`. Pull from upstream periodically with `git fetch upstream && git merge upstream/main` and resolve conflicts as they come.

## What changed from upstream

- **Pages stripped** — 2d does not surface ERC-20s, NFTs, internal transactions, or contract verification, so the corresponding controllers, templates, routes, and tests were removed:
  - `/tokens`, `/token/:address[/holders]`, `/nft-transfers`, `/nft-latest-mints[.csv]`, `/exportData`
  - Address tabs `/address/:addr/{tokens,token-transfers,internal}`
  - Tx tab `/tx/:hash/internal`
- **`53627` skin removed** — the fork is committed to the `classic` visual idiom by product decision; `FrontendExWeb.Skin.current/0` always returns `:classic` and the `s53627_*.html.eex` templates are gone.
- **Native coin → USDC** — every "ETH" literal in templates is rendered from a `@native_coin.symbol` assign, defaulting to `%{symbol: "USDC", decimals: 6}` (exposed by `FrontendExWeb.ControllerHelpers.default_native_coin/0`). `FrontendEx.Format.format_native_amount/1` and `format_native_amount_exact/1` divide by `10^6` instead of `10^18`.
- **API contract pinned to 2d** — `BLOCKSCOUT_API_URL` defaults to `http://localhost:4000` (where the 2d Phoenix endpoint serves `/api/v2/*`). 2d's read-side API is implemented in [TASK-13.2](https://github.com/igor53627/2d) and follows the Blockscout v2 conventions for the subset 2d supports.
- **Goldens** — Rust-`fast-frontend` parity goldens were dropped; render-tests now drive the controllers with stub adapters that return 2d-shaped JSON. The 2d JSON contract lives at `test/fixtures/blockscout/2d/{stats,block_show,transaction_show,address_show}.json` (copies of 2d's own golden fixtures, regenerable via `UPDATE_EXPLORER_API_GOLDENS=1` in the 2d repo).

## Architecture

```text
Browser -> 2d-explorer-frontend (Phoenix SSR)
            -> 2d /api/v2/* (Phoenix, classic skin only, USDC native)
                -> Postgres (state + history schemas, role: explorer)
```

The frontend is stateless — no database, no sessions. It makes upstream HTTP calls to 2d's `/api/v2/*` endpoints, caches responses in-memory (standard TTL + stale-while-revalidate), and renders HTML via EEx templates. See `docs/ARCHITECTURE.md` for request flow and `docs/API_ENDPOINTS.md` for the upstream subset consumed.

## Running

```bash
mix setup

# Start 2d's Phoenix endpoint (in another terminal, in ~/pse/2d):
#   mix phx.server   # default :4000

LISTEN_ADDR=127.0.0.1:3010 \
BLOCKSCOUT_API_URL=http://localhost:4000 \
mix phx.server
```

Visit http://127.0.0.1:3010.

## Tests

```bash
mix test
```

The render smoke-tests (`test/frontend_ex_web/usdc_render_test.exs`) drive controllers with a stub adapter and assert that `USDC` surfaces on pages with token-symbol display, while `ETH` does not — catches the most common regression class (a hardcoded "ETH" literal slipping back in).

## Pulling upstream changes

`upstream` is the `igor53627/frontend-ex` remote configured at clone time:

```bash
git fetch upstream
git merge upstream/main      # or rebase, depending on policy
```

Expected conflicts: anywhere upstream touches code we deleted (NFT/tokens/internal-tx/53627) or files we adapted to USDC. Resolve by keeping the 2d-fork stance.

## Docs

- `docs/ARCHITECTURE.md` — Request flow, templates, caching
- `docs/API_ENDPOINTS.md` — HTTP surface and upstream usage
- `docs/FEATURE_FLAGS.md` — Environment variables and runtime config
- `docs/DEPLOYMENT.md` — Release builds, systemd, Caddy

## Project Backlog

Active tasks tracked in [igor53627/2d](https://github.com/igor53627/2d) under TASK-13 (block explorer). This repo's `backlog/` retains upstream's per-feature implementation records for historical context.
