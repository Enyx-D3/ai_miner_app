# Current V9.0.2 compatibility

Web constants mirrored exactly:
- `BRAIN2_SCHEMA_VERSION = 9`
- `BRAIN2_IDENTITY_VERSION = B2_ID_V9_ASIF_READER`
- `BRAIN2_SYNC_PROTOCOL_VERSION = 2`
- channel `brain2-sync`
- batch limit `128`

Mutation payload v1 supports UPSERT / UPSERT_BUNDLE / DELETE, record writes grouped by canonical table, payload SHA-256 and envelope SHA-256. Remote mutations are rejected on memory-root mismatch, payload mismatch or envelope mismatch.
