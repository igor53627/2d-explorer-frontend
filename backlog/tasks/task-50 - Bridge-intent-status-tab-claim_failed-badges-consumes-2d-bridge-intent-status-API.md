---
id: TASK-50
title: >-
  Bridge intent status tab + claim_failed badges (consumes 2d bridge-intent
  status API)
status: Done
assignee:
  - '@agent'
created_date: '2026-05-29 18:02'
updated_date: '2026-06-05 14:20'
labels:
  - bridge
  - explorer
  - ui
  - frontend
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Render bridge intent lifecycle visibility in the explorer (carved out of 2d TASK-93, whose backend ships the JSON API). Adds a bridge-intent status surface that consumes the new 2d endpoint GET /api/v2/bridge/intents/:intent_id (TASK-93 backend, 2d repo) and shows per-intent status badges + bump attempt count. The 2d backend (TASK-93) delivers AC#1 (public per-intent status), AC#3 (terminal claim error reason), AC#4 (operator /admin/bridge/intents); this task is the frontend UI half (original TASK-93 AC#2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bridge intent status badge: green=consumed, red=claim_failed, yellow=in-progress
- [x] #2 Badge/row shows the gas-bump attempt count (bump_count)
- [x] #3 claim_failed intents surface the terminal reason from the 2d API (state_eth_claim_last_error)
- [x] #4 Data is fetched from the 2d backend endpoint (GET /api/v2/bridge/intents/:intent_id), not a direct DB query
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SSR /bridge/intents/:intent_id with status badges (green/yellow/red), bump_count, claim_failed last_error. Consumes GET /api/v2/bridge/intents/:intent_id.
<!-- SECTION:FINAL_SUMMARY:END -->
