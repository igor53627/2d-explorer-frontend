---
id: TASK-48
title: 'Block page: bridge-ops summary section'
status: In Progress
assignee:
  - '@agent'
created_date: '2026-05-12 20:14'
updated_date: '2026-06-05 17:14'
labels:
  - pages
  - bridge
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today the block page (`/block/:height`) renders the generic Blockscout view: tx count, producer (stub `@system_producer`), state root, etc. When a block contains bridge operations — `bridge_refill_mint`, `bridge_lock`, HTLC `settle`/`refund` — there is no indication on the page that the block has any bridge activity. The dedicated `/bridges` list (TASK-45) shows the same data globally but doesn't let an investigator confirm "did anything bridge-y happen in block 12345?" without manual filtering.

This task adds a small summary section / panel to the block page that surfaces, at a glance, how many bridge ops the block contained and links out for detail.

Scope is deliberately the **counter variant**: count bridge-related transactions in the per-block tx list (already fetched by the page) and render `"N bridge ops in this block"` with a deep link. No chain-side endpoint changes are needed for this slice — `to ∈ {0x2D00…0001 (HTLC), 0x2D00…0003 (BridgeRefillMint)}` is a sufficient detector on the existing per-block tx response. An inline table with decoded amounts / counterparties is explicitly **out of scope** here (would require backend enrichment); leaving that to a follow-up if the counter view proves insufficient.

Deep-link target: if `/bridges` accepts a `?block=:height` filter (or equivalent), link there. Otherwise (more likely v1), link to the global `/bridges` list with the block height surfaced as a UI breadcrumb. Worth confirming during implementation; either is fine for the first slice.

References: TASK-45 (`/bridges` list), TASK-12 (block page), TASK-13 (transaction page that the bridge-tx detail card sibling task hangs on).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Block page detects bridge transactions in the per-block tx list by to ∈ {0x2D00…0001, 0x2D00…0003}
- [ ] #2 Renders a 'N bridge ops in this block' counter / summary panel only when N > 0; absent for blocks with no bridge activity (no empty-state clutter)
- [ ] #3 Counter links to /bridges (filtered by block height if the API supports it; otherwise to the global list with the block height visible as a breadcrumb)
- [ ] #4 Pure SSR — no JS required for this slice (matches the existing block page posture)
- [ ] #5 Golden HTML snapshot covers blocks with zero / one / multiple bridge ops
- [ ] #6 Bridge tx detection lives in a small reusable helper module (e.g. FrontendExWeb.BridgeDetect) — the sibling transaction-page task reuses it
<!-- AC:END -->
