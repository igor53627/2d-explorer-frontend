# Feature Flags and Runtime Config

This project is configured primarily via environment variables (read in `config/runtime.exs`).

## Skins

The 2d fork supports only the `classic` skin. The `FF_SKIN` env var
that upstream `frontend-ex` parsed has been removed; setting it in the
environment is silently ignored.

## Networking

- `LISTEN_ADDR`
  - Format: `ip:port` (IPv4 only)
  - Default: `0.0.0.0:3000`

- `PORT`
  - Used as a fallback if `LISTEN_ADDR` is invalid.
  - Default: `3000`

## Blockscout URLs

- `BLOCKSCOUT_API_URL`
  - Base URL for upstream Blockscout API calls (e.g. `https://sepolia.53627.org`).
  - Trailing `/` is trimmed.

- `BLOCKSCOUT_TXS_API_URL`
  - Optional override for `/txs` upstream calls to `/api/v2/transactions`.
  - Useful when your primary `BLOCKSCOUT_API_URL` does not return `next_page_params` for
    `/api/v2/transactions` (pagination arrows would be disabled).
  - Trailing `/` is trimmed.

- `BLOCKSCOUT_URL`
  - Base URL used for links to the "classic explorer".
  - Default: `BLOCKSCOUT_API_URL`.
  - Trailing `/` is trimmed.

- `BLOCKSCOUT_WS_URL`
  - WebSocket URL for live updates (home page).
  - If unset, `frontend-ex` derives:
    - `wss://<BLOCKSCOUT_URL host>/socket/v2/websocket?vsn=2.0.0`

## Home page tiles

- `FF_HOME_BLOCK_META_FULL`
  - When `true`, home block tiles render the `Proposer …` and `Fees 0 USDC`
    rows. On 2d these are static by design (single validator, gasless USDC),
    so they default to hidden to keep the at-a-glance home view focused on
    fields that actually change block-to-block (height, age, txn count).
  - Set to `true` if the chain ever moves to multi-proposer or fee-bearing
    modes, or for upstream forks reusing this codebase against a non-2d
    backend.
  - Block detail page (`/block/:id`) is unaffected — it always shows full
    metadata.
  - Default: `false`.

## Misc

- `BASE_URL`
  - Base URL of this service used in some templates (parity with Rust).
  - Default: `https://fast.53627.org`.
  - Trailing `/` is trimmed.

- `EVM_RPC_URL`
  - JSON-RPC endpoint for optional block page augmentation (parity with Rust).
  - Not wired yet in `frontend-ex` (tracked by backlog tasks).

## Phoenix Release Settings

- `PHX_SERVER`
  - When set (non-empty), starts the Phoenix endpoint in releases.

- `SECRET_KEY_BASE`
  - Required in `MIX_ENV=prod` at runtime (start-up). Used to sign/encrypt cookies.

- `SESSION_SIGNING_SALT`
  - Required in `MIX_ENV=prod` at *build* time (`mix release`). Signs the
    cookie session store. Generate with `mix phx.gen.secret 32`.

- `LIVE_VIEW_SIGNING_SALT`
  - Required in `MIX_ENV=prod` at *build* time. Signs LiveView tokens
    (used by the local-only dashboard). Generate with `mix phx.gen.secret 32`.
