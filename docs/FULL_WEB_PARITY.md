# V9 Mobile Web-Parity Matrix

| V9 web surface | Mobile V9.1 | Notes |
|---|---|---|
| Dashboard | YES | local counts, Reader, mutation status |
| Projects / detail | YES | same canonical project records |
| Conversations / detail | YES | exact local message records |
| Discover | YES | Reader-backed discovery |
| Search | YES | `.ASIF Reader` bounded retrieval |
| Ask | YES | verified Databox + B2JOB |
| Memory | YES | import, export `.B2M`, repair, hard reset |
| Wiki | YES | truth projection |
| Live Notebooks | YES | project projection |
| Pattern Lab | YES | canonical pattern records |
| Experiments | YES | canonical experiment records |
| Missions | YES | canonical mission records |
| Ticks | YES | canonical human-control records |
| Decisions | YES | Current Truth-linked decisions |
| Timeline | YES | Global Delta mutation timeline |
| Outputs | YES | B2 transactions/results surface |
| Devices & Sync | YES | **Scan QR only**; web generates QR |
| Operations | YES | runtime truth/status counts |
| Extension | Indirect | extension → web canonical ingest → Global Delta → mobile |

The mobile app does not invent separate memory, search, Current Truth or sync semantics.

## Bootstrap parity
Empty mobile replicas request the same bounded bootstrap used by V9 web (`bootstrap_request` → hash-verified `bootstrap_chunk` → `bootstrap_complete`) before delta-only sync.

## Writable parity
Ticks can be created/resolved; Experiments can be created/started/completed/failed; Missions can be created/checkpointed/blocked/completed. Search exposes Find/Current/History/Evidence/Discover modes. Timeline is source-message chronology.
