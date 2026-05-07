---
id: TASK-46
title: 'Address tab: /address/:addr/bridges (counter + conditional render)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-05-06 13:50'
updated_date: '2026-05-07 12:27'
labels:
  - pages
  - address
  - bridge
dependencies:
  - TASK-45
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2d-fork frontend slice of `2d` TASK-13.4 (AC #5) — add a Bridges tab to the address page, populated from `/api/v2/addresses/:address/bridge-mints` (`2d` TASK-13.18).

**Tab visibility rule:**
- Tab is hidden when `bridge_mints_count == 0` for that address
- When > 0, tab header shows the count (e.g. "Bridges (3)") — match formatting of existing tab counters

**Implementation notes:**
- Address tabs are rendered in the address-page header partial. Mirror the conditional pattern that was used for `/tokens` etc. before they were stripped (see git history pre-2d-fork for reference).
- Counter source: easiest is to read `bridge_mints_count` from `/api/v2/addresses/:address` payload (same endpoint that already populates the address header). If the count is not yet exposed there, surface it on the API side first — file as a follow-up on `2d` rather than calling the per-address bridge endpoint twice.
- Page rendering reuses the `/bridges` row template from TASK-45 — extract it into a shared partial when wiring this task.

**Blocked on:** `2d` TASK-13.18 (API endpoint + fixture) and TASK-45 (shared row template).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GET /address/:addr/bridges renders SSR (classic skin) with rows filtered by recipient
- [ ] #2 Bridges tab in address-page nav appears only when bridge_mints_count > 0
- [ ] #3 Tab header displays the count
- [ ] #4 Cursor pagination via next_page_params
- [ ] #5 Empty 200 from API (zero mints) renders empty state, not an error
- [ ] #6 Golden HTML snapshot test driven by stubbed /api/v2/addresses/:addr/bridge-mints fixture

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
**Dependencies satisfied / blocker filed:**
- `2d` TASK-13.18 (per-recipient API) — Done 2026-05-07; live API verified returning correct flat shape
- `TASK-45` (frontend list page + row template) — Done 2026-05-06
- **`bridge_mints_count` not exposed on `/api/v2/addresses/:address`** — filed as `2d` TASK-13.25. Frontend reads optimistically (`parse_u64(addr_json["bridge_mints_count"]) || 0`); tab stays hidden until 13.25 ships, then activates without a frontend redeploy.

**Plan:**

1. **Route** in `lib/frontend_ex_web/router.ex` — same scope as the existing `/address/:address`:
   - `get "/address/:address/bridges", AddressController, :bridges`

2. **Controller action** `AddressController.bridges/2` (sibling to `show/2`) — mirrors `BridgesController.index/2` from TASK-45 for cursor + page-size handling, but scoped to a single recipient:
   - parallel-fetch via `await_many_ok`: `stats` + `addresses/:address` (for chrome) + `addresses/:address/bridge-mints` (for tab content) — 3 tasks
   - `ps` via `FrontendExWeb.Pagination.normalize_page_size/3` (10/25/50/100, default 50)
   - cursor params: `block_number` + `event_id` (per `2d` TASK-13.17 decision (b))
   - upstream URL: `/api/v2/addresses/:address/bridge-mints?items_count=<ps>[&block_number=<N>&event_id=<X>]`
   - decorate items via the same row-shape from `BridgesController.display_bridge/2`
   - render `:classic_bridges_content` (new template)

3. **Tab visibility on the address INDEX page** (`AddressController.show/2`):
   - parse `bridge_mints_count = parse_u64(addr_json["bridge_mints_count"]) || 0` (defaults to 0 until `2d` TASK-13.25 lands)
   - thread into base_assigns
   - in `address_html/classic_content.html.eex`, add conditional tab inside the existing `<div class="tabs">` block: `<%= if @bridge_mints_count > 0 do %><a href="/address/<%= @address.hash %>/bridges" class="tab">Bridges (<%= @bridge_mints_count %>)</a><% end %>`

4. **Reuse vs duplicate row HTML** — codebase has no partial pattern (verified: tx_html splits into 3 templates each duplicating the tabs block; no shared `<tr>` partials exist). For TASK-46 v1: **duplicate the table HTML** from `bridges_html/classic_content.html.eex` into the new template, with comment pointing at the source. Extract to a Phoenix.HTML helper later if a third consumer appears.

5. **Refactor existing controller code where it pays off:**
   - `BridgesController.display_bridge/2` is row-shape decoration — extract to `lib/frontend_ex/bridges/row.ex` or expose as public `BridgesController.display_bridge/2` helper, called from `AddressController.bridges/2`. Saves the 100-line copy.
   - Cursor handling (`cursor_query_from_params/1`, `merge_cursor_params/2`, `maybe_append_*`, `normalize_*`) is also a near-clone — defer extraction (would touch 2 controllers; clean refactor for follow-up).

6. **New template** `address_html/classic_bridges_content.html.eex`:
   - Address-page header card (same as `classic_content.html.eex` — duplicate or extract a partial — go with duplicate for v1 mirroring `tx_html` pattern)
   - Tabs block with **Bridges** active
   - "More info" / hash card / etc. — same chrome as the existing address page
   - Bridges table (duplicated from `bridges_html/classic_content.html.eex`)
   - Pagination chrome (same as TASK-45)
   - Empty-state ("No bridge mints for this address.")

7. **Tests** `test/frontend_ex_web/address_bridges_render_test.exs`:
   - Reuse the `Adapter` pattern from `bridges_render_test.exs` (Application env-driven payload + clock freeze)
   - **t1: full-row rendering** for `/address/:addr/bridges` with a recipient that has 2 mints — assert table has both rows with correct cells
   - **t2: empty result** — recipient with 0 mints → empty state, no error
   - **t3: tab visibility on index** — `/address/:addr` with `bridge_mints_count=0` → no Bridges tab in HTML; with `bridge_mints_count=3` → tab present with text "Bridges (3)"
   - **t4: cursor passthrough** — `?cursor=block_number=42&event_id=0x...` reaches upstream URL (mirrors TASK-45 t5)
   - **t5: ps clamp** — `?ps=999` → 50 (mirrors TASK-45 t4)

8. **Pre-flight:** `mix compile --warnings-as-errors`, target test file, full suite.

**No open design points** — all carried over from TASK-45 (event_id link → plain text per A1, mainnet-only Etherscan link per (d), no CSV per (c)). Page chrome conventions follow the existing `tx_html`/`address_html` pattern (duplication over partials).
<!-- SECTION:PLAN:END -->
