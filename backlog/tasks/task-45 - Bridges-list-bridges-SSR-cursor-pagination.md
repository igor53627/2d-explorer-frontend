---
id: TASK-45
title: 'Bridges list: /bridges (SSR + cursor pagination)'
status: Done
assignee:
  - '@claude'
created_date: '2026-05-06 13:49'
updated_date: '2026-05-07 13:30'
labels:
  - pages
  - bridge
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2d-fork frontend slice of `2d` TASK-13.4 — render `/bridges` as a classic-skin SSR list page consuming `/api/v2/bridges` (`2d` TASK-13.17).

Mirrors TASK-20 (`/txs`) in shape: cursor-paginated list with `ps` page-size param, no fake page numbers, `next_page_params` plumbed through link helpers (TASK-6).

**Columns** (per AC #4 of `2d` TASK-13.4):
- `eth_event_id` — short-form, links to `/bridges/:eth_event_id` once TASK-47 lands
- `htlc_hash` — short-form or em-dash when null
- `amount` — formatted via `Format.format_native_amount/1` (USDC, 6 decimals)
- `recipient` — links to `/address/:addr`
- source-chain ref (flat fields `source_chain_id` / `source_tx_hash` / `source_log_index` — see `2d` TASK-13.17 Resolved design decisions): render the cell as `{tx_hash short-form}#{log_index}` text + `<a>` to `https://etherscan.io/tx/0x{source_tx_hash}` when `source_chain_id == 1` (mainnet); plain text fallback for unknown chain ids. **Why surface `log_index` in the cell:** batch-refill emits multiple Locked events from a single ETH tx, so two `/bridges` rows can share the same `source_tx_hash`. Without the `#log_index` suffix they appear identical even though they are distinct mints with distinct `eth_event_id`s. Etherscan does not expose log index in the URL path, so visual disambiguation is the explorer's responsibility.
- age — relative timestamp from `inserted_at`

**Blocked on:** `2d` TASK-13.17 (API endpoint + golden JSON fixture). Once that ships, copy the fixture into `test/fixtures/blockscout/2d/bridges_index.json` so render-tests can drive the controller via the stub adapter.

**Anti-scope:** no detail page wiring here (TASK-47); no address-tab wiring (TASK-46); no Rust-parity goldens (this is a 2d-fork-only page, no upstream equivalent).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GET /bridges renders SSR (classic skin)
- [x] #2 Cursor pagination via next_page_params (no page numbers)
- [x] #3 ps query param normalized (10/25/50/100, default 50) — match TASK-20 helper
- [x] #4 Empty result renders cleanly with empty-state copy (no error)
- [x] #5 Golden HTML snapshot test driven by stubbed /api/v2/bridges fixture
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. **Copy the API golden fixture** from the 2d repo into the fork's stub-adapter tree:
   - source: `~/pse/2d/test/support/explorer_api_golden/bridges_index.json` (1 item, flat shape per `2d` TASK-13.17 resolved decisions: `source_chain_id`, `source_tx_hash`, `source_log_index`)
   - destination: under `test/fixtures/blockscout/api/v2/` per the existing fixture-adapter naming scheme (`<path>__<canonical_query>--<sha256_hash8>.json`). Easiest approach: run the controller test once, let the fixture adapter raise a "missing fixture" error that includes the expected filename, copy the fixture to that path, run again. Faster than recomputing the canonical-query hash by hand.

2. **Route** in `lib/frontend_ex_web/router.ex` — same scope as `/blocks` and `/txs`:
   - `get "/bridges", BridgesController, :index`

3. **Controller** `lib/frontend_ex_web/controllers/bridges_controller.ex` — mirror `TxsController` shape:
   - `@page_size_options [10, 25, 50, 100]`, `@default_page_size 50`
   - `index/2`:
     - `ps` parsed via `FrontendExWeb.Pagination.normalize_page_size/3` (same helper as `/txs`)
     - cursor params: `block_number` + `event_id` (per `2d` TASK-13.17 decision (b)). Decode via existing `FrontendEx.Blockscout.Cursor` helpers if reusable; otherwise pass-through verbatim.
     - upstream URL: `GET <api_url>/api/v2/bridges?items_count=<ps>[&block_number=<N>&event_id=<X>]` (cursor params only when present)
     - parse `{items, next_page_params}` and decorate items for the view (step 4)
     - render `:classic_content` with `is_first_page`, `next_cursor`, `page_size`, `bridges`, `native_coin`, etc.

4. **Item view-model** — pure-data per row, decorated in the controller (mirrors `TxsController` row-shape):
   - `eth_event_id_short` — `Format.truncate_hash` (6/4, same as tx hashes)
   - `htlc_hash_short` — `truncate_hash` or `nil` → renders em-dash in template
   - `amount_formatted` — `Format.format_native_amount/1` (USDC 6 decimals)
   - `recipient_short` + `recipient_hash` — pair so the cell renders `<a href="/address/:hash" title=":hash">:short</a>`
   - `source_tx_hash_short` — `truncate_hash`
   - `source_log_index` — passthrough integer
   - `source_chain_explorer_url` — string or `nil`. Helper logic:
     - `1` → `"https://etherscan.io/tx/0x" <> source_tx_hash`
     - `11155111` → `"https://sepolia.etherscan.io/tx/0x" <> source_tx_hash` (Sepolia useful in dev)
     - other → `nil` → cell renders plain text
   - `time_ago` — `Format.format_blocks_time_ago(inserted_at)` (already accepts ISO-8601 binary, verified)
   - `timestamp_readable` — `Format.format_readable_date_classic(inserted_at)` for `title=` tooltip (mirror /blocks listing pattern: relative-only display, full date on hover)

5. **View module** `lib/frontend_ex_web/controllers/bridges_html.ex` — minimal; just `embed_templates "bridges_html/*"`.

6. **Templates:**
   - `bridges_html/classic_content.html.eex` — page-header (title "Bridges", page-info row), card-toolbar, table, empty-state. Mirror `txs_html/classic_content.html.eex` for pagination + table layout. **Skip CSV download button for v1** (not in AC).
   - `bridges_html/classic_styles.html.eex` — minimal scoped CSS for any cell-specific quirks (likely empty; reuse existing `.card`, `.list-table`, `.hash` classes).

7. **Tests** `test/frontend_ex_web/bridges_render_test.exs` (mirror existing render-test pattern):
   - **t1: full row rendering** — script stubs `/api/v2/bridges?items_count=50` to return the copied fixture (1 item). Assert HTML contains: short event_id, short htlc_hash, formatted amount + symbol, recipient short with link to /address/, source-chain cell text `0xabcd…0000#7`, `<a href="https://etherscan.io/tx/0xabcd…">`, time-ago span with title attr.
   - **t2: batch-refill disambiguation** — stub returns 2 items sharing `source_tx_hash` but different `source_log_index` (4 and 7). Assert both `#4` and `#7` appear in distinct cells.
   - **t3: empty result** — stub returns `{"items":[], "next_page_params":null}`. Assert 200, empty-state copy, no error.
   - **t4: ps normalization** — `?ps=999` clamps to 50 (TASK-20 pattern).
   - **t5: cursor passthrough** — `?cursor=block_number%3D42%26event_id%3D0xabcd…` produces upstream URL containing `block_number=42&event_id=0xabcd…`.
   - **t6: non-mainnet chain** — stub item with `source_chain_id: 999`. Assert no `<a href="https://etherscan` in source-chain cell.

8. **Pre-flight:** `mix compile --warnings-as-errors`, targeted test file, full suite (`FF_METRICS_ENABLED=false mix test`).

**Open design points to confirm with user before coding:**
- (a) **`/bridges/:eth_event_id` link in event-id column.** TASK-47 (detail page) is LOW priority and still blocked on `2d` TASK-13.19. Three options:
  - A1: render `eth_event_id` as plain text now; flip to `<a>` once TASK-47 lands. No broken links.
  - A2: render as `<a href="/bridges/:eth_event_id">` now; clicks 404 until TASK-47 lands. Bad UX.
  - A3: gate behind a feature flag (`FF_BRIDGE_DETAIL_PAGE`). More wiring, low payoff.
  - **My pick: A1.**
- (b) **Navigation link.** Where should `/bridges` be discoverable?
  - B1: add "Bridges" as 5th item in global header nav (Home / Transactions / Blocks / **Bridges** / Docs). Most discoverable; nav becomes 5-wide, may need small CSS tightening.
  - B2: home-hero CTA only ("View bridges" link below stats strip), no global header entry. Keeps header lean.
  - B3: link only from footer / address-tab (TASK-46). Lowest discoverability.
  - **My pick: B1** — flagship 2d feature deserves first-class nav. Visual decision though, your call.
- (c) **CSV export button.** AC doesn't require it; `/txs` and `/blocks` have it. **My pick: skip for v1**, add as follow-up if needed.
- (d) **Sepolia (chain_id 11155111) Etherscan link.** Spec requires only mainnet (1); adding Sepolia is ~3 lines and helps dev iteration. **My pick: include both.**
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped in commit ef15d67. /bridges list page renders with 7 columns (Event/HTLC/Amount/Recipient/Source ETH Tx/2D Tx/Age), cursor pagination via next_page_params (block_number+event_id keys per 2d TASK-13.17), batch-refill disambiguation via tx_hash#log_index, mainnet-only Etherscan link. 5th nav item Bridges added to global header. items_count bypass discovered post-merge in roborev #2210 — fixed in 7626368. 14 tests covering full row, batch-refill, empty, ps clamp, cursor passthrough, non-mainnet fallback, items_count bypass.
<!-- SECTION:FINAL_SUMMARY:END -->
