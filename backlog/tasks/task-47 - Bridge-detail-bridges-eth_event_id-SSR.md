---
id: TASK-47
title: 'Bridge detail: /bridges/:eth_event_id (SSR)'
status: Done
assignee:
  - '@agent'
created_date: '2026-05-06 13:50'
updated_date: '2026-06-05 14:14'
labels:
  - pages
  - bridge
dependencies:
  - TASK-45
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2d-fork frontend slice of the optional detail bullet from `2d` TASK-13.4 — per-event detail page consuming `/api/v2/bridges/:eth_event_id` (`2d` TASK-13.19).

Deep-link target from the list page (TASK-45) and the address tab (TASK-46) — short-form `eth_event_id` cells link here once this lands.

Low priority: the list views cover the primary UX; detail page is mostly for sharing/inspection. Keep the layout simple — single-card rendering of the same fields shown in the list, plus the link out to the source-chain tx.

**Blocked on:** `2d` TASK-13.19.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GET /bridges/:eth_event_id renders SSR (classic skin) with full bridge_mint detail
- [x] #2 Returns 404 when event_id is unknown (proxy from API 404)
- [x] #3 Source-chain tx_hash and 2d tx_hash are linked out to the appropriate explorers
- [x] #4 Golden HTML snapshot test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SSR /bridges/:eth_event_id consumes GET /api/v2/bridges/:eth_event_id. Tx bridge card links to detail page. Tests in bridges_show_render_test.exs.
<!-- SECTION:FINAL_SUMMARY:END -->
