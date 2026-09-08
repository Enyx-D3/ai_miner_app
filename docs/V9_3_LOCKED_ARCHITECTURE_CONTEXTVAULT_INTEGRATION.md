# V9.3 Locked Architecture / ContextVault Integration

V9.3 rebases the source-bearing mobile release onto the corrected locked routing architecture.

Key changes:

- canonical schema version 10 / SQLite migration 11;
- MRS persistent tables added;
- Ask now executes the conditional MRS router instead of stopping at B2JOB creation;
- deterministic/capability/specialist paths may finish without neural inference;
- hard residuals use the pluggable `MobileModelAdapter` boundary;
- missing model runtime becomes `BLOCKED_EXTERNAL_DEPENDENCY` rather than a shortcut;
- `.B2M` and P2P bootstrap include persistent-intelligence tables;
- full ContextVault Android integration documentation and verification scripts included inside the ZIP.
