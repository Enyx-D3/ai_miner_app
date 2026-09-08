# Brain2 AI Miner Mobile — V9 .ASIF Reader Rebase

This package supersedes the first V9.0.2 mobile integration package. The earlier package carried V9 contracts but still behaved like the pre-rebase architecture: SQLite/table search remained the practical retrieval owner and P2P did not automatically flush mutations committed after the initial handshake.

## Canonical ownership

```text
.ASIF Reader / RapidRetrieve
        ↓
selective verified evidence
        ↓
B2DATABOX
        ↓
Global Memory / ContextOS / .B2M
        ↓
Global Delta / B2 Network
        ↓
Brain2 AI Miner mobile surfaces
```

- `AsifReaderCore` is the mobile retrieval/evidence owner.
- Global Memory tables remain durable state, not a competing search product.
- `reader_search_docs` is a rebuildable Reader projection, not canonical history.
- Reader results are materialized selectively and verified against canonical-record hashes before entering a Databox.
- Native `.ASIF` Reader ABI remains the preferred low-level file reader when the verified native library is available.

## Delta-local sync

Remote mutations update only affected Reader documents transactionally. They do not trigger a corpus-wide rebuild.

Local mutations publish a mutation event. Connected P2P sessions coalesce it for ~80ms and send missing local deltas using an ACK-gated peer cursor. The old "handshake only" behavior is removed.

## Compatibility

Canonical Brain2 values remain:

- schema: `9`
- identity: `B2_ID_V9_ASIF_READER`
- sync protocol: `2`
- channel: `brain2-sync`

The SQLite storage migration level is `10`; this is an implementation migration number and does not change the cross-surface Brain2 schema version.

## External gate

The exact recovered historical Flutter tree and verified ARM64 native `.ASIF`/ContextVault binaries were not available as mounted bytes in this session. They are not fabricated here. Their adapter slots are preserved.
