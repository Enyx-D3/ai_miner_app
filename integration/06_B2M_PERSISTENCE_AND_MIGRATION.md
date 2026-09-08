# .B2M Persistent Intelligence Integration

V9.3 includes the following new persistent-intelligence tables in `.B2M` export and P2P bootstrap:

```text
capabilities
reasoningTrajectories
failureMemory
mrsRuns
intelligenceSnapshots
wikiSnapshots
notebookSnapshots
```

Existing canonical tables remain included.

## Migration

- Canonical Brain2 schema version: 10.
- Local SQLite migration level: 11.
- On upgrade, the new tables are created without deleting existing memory.

## Required verification

1. open an existing V9.2 database;
2. upgrade to V9.3;
3. confirm old records remain;
4. confirm all new tables exist;
5. create an MRS run/trajectory;
6. export `.B2M`;
7. verify new tables are in the snapshot;
8. restore/import in the eventual restore path and confirm identities remain stable.

`.B2M` is persistent intelligence/state. It is not the ordinary live P2P transport.
