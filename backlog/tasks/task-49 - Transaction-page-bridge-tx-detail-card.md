---
id: TASK-49
title: 'Transaction page: bridge-tx detail card'
status: Done
assignee:
  - '@agent'
created_date: '2026-05-12 20:15'
updated_date: '2026-06-05 14:04'
labels:
  - pages
  - bridge
dependencies:
  - TASK-48
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today the transaction page (`/tx/:hash`) renders the generic Blockscout view — `from`, `to`, `input` as raw hex, `value`, gas, status. When the transaction is a bridge operation (bridge_refill_mint, bridge_lock, HTLC settle, HTLC refund), there is no semantic rendering — investigators see raw calldata bytes and have to manually correlate against the `/bridges` list to understand what happened.

This task adds an SSR-rendered "Bridge" card to the transaction page that surfaces decoded bridge fields and cross-links into the existing bridge views.

Strategy:

  1. Reuse the bridge-tx detector helper introduced by the sibling task TASK-48 (block-page summary) — when `to ∈ {0x2D00…0001 (HTLC), 0x2D00…0003 (BridgeRefillMint)}`, the tx is a bridge candidate.
  2. Fetch the new chain-side endpoint `/api/v2/transactions/:hash/bridge` (depends on **2d / TASK-69**). The endpoint returns a `kind`-discriminated payload per the four recognised bridge-tx kinds (bridge_refill_mint / bridge_lock / htlc_settle / htlc_refund); render type-specific cards.
  3. Cross-link the card outward:
     - `bridge_refill_mint` → link to `/bridges/:eth_event_id` (TASK-47) and out to the configured Etherscan host for the source tx_hash.
     - `bridge_lock` → link to the matching `/bridges/:eth_event_id` row (same eth_event_id as the BridgeLocked event the precompile emits) and to the HTLC swap state on the recipient's address page.
     - `htlc_settle` / `htlc_refund` → link back to the originating lock tx hash (settle additionally surfaces the revealed preimage).
  4. SSR-only. The card slots above the input/calldata section so the bridge meaning is visible before the raw hex.

Out of scope: dynamic state polling (e.g. live "claim deadline X minutes remaining"). Keep the card a static snapshot of the joined row; if the user wants live state they can refresh.

**Hard dependency on 2d / TASK-69** (the chain-side endpoint). Until that lands, this task is blocked. Worth noting in implementation: confirm the JSON shape matches what 2d / TASK-69 actually shipped — if drift, sync as part of this task.

References: TASK-13 (transaction page foundation), TASK-45/46/47 (existing bridge views — the cross-link targets), TASK-48 (sibling block-page summary — shares the bridge-tx detector helper), 2d / TASK-69 (chain-side endpoint we consume).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tx page detects bridge candidates via the shared helper from TASK-48 (to ∈ {0x2D00…0001, 0x2D00…0003})
- [x] #2 When the tx is bridge-related, fetches /api/v2/transactions/:hash/bridge and renders a kind-specific SSR card above the input/calldata section; non-bridge txs render unchanged
- [x] #3 bridge_refill_mint card: shows source chain id + tx_hash + log_index + amount + eth_event_id, links eth_event_id to /bridges/:eth_event_id, links source tx_hash to the configured Etherscan host
- [x] #4 bridge_lock card: shows htlc_hash, recipient, preimage_hash, amount, deadline, current state (pending / claimed / refunded), links to /bridges/:eth_event_id and to recipient address page
- [x] #5 htlc_settle card: shows the lock id it settles, the revealed preimage, link back to the originating bridge_lock tx
- [x] #6 htlc_refund card: shows the lock id it refunds, link back to the originating bridge_lock tx
- [x] #7 Endpoint 404 (tx not bridge-related): card is not rendered, page falls back to generic shape — no error toast / banner
- [x] #8 Endpoint 404 (tx unknown): page returns its own 404 — does not depend on the bridge endpoint succeeding
- [x] #9 Etherscan host is read from runtime config so staging / mainnet point at the right host
- [ ] #10 Golden HTML snapshots for each of the four card kinds plus the bridge-detect-but-endpoint-404 case
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bridge SSR card on /tx/:hash — consumes 2d TASK-69 endpoint.
<!-- SECTION:FINAL_SUMMARY:END -->
