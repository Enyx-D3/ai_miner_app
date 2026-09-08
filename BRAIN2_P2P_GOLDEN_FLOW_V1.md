# Brain2 AI Miner — Web ↔ Mobile P2P Golden Flow V1

## What this build syncs

Replicated Brain2 user/intelligence tables (25):

`sources`, `conversations`, `messages`, `atoms`, `truths`, `projects`, `ticks`, `decisions`, `patterns`, `experiments`, `missions`, `checkpoints`, `verifications`, `transactions`, `patternTests`, `portableExpertise`, `compiledCapabilities`, `reasoningTrajectories`, `failureMemories`, `databoxes`, `evidenceBlocks`, `mrsRuns`, `intelligenceSnapshots`, `wikiSnapshots`, `notebookSnapshots`.

Mobile storage aliases are translated on the wire:

- `capabilities` ↔ `compiledCapabilities`
- `failureMemory` ↔ `failureMemories`

Transport credentials, peer cursors, conflicts, search-index cache, and device-local metadata are intentionally **not** replicated as user intelligence.

## Protocol

1. Web creates a five-minute, single-use pairing token and QR.
2. QR carries protocol v2, inviter device ID, expiry, and signaling origin when needed.
3. Mobile scans QR and registers with the signaling server.
4. Server binds mobile to the web memory root and returns its credential + ICE configuration.
5. Mobile creates WebRTC offer; signaling mailbox carries offer/answer/ICE.
6. ICE received before SDP is queued instead of discarded.
7. Data channel opens and both replicas exchange `hello` summaries.
8. Memory roots must match.
9. Empty replica requests bootstrap. Populated peer does not simultaneously replay the whole mutation log.
10. Bootstrap is hashed, chunked, paged, backpressured, and includes the mutation log.
11. Receiver ACKs the mutation sequence already represented by bootstrap.
12. Normal operation sends only ordered missing mutations in batches of 128.
13. Mutation payload + envelope hashes are verified. Duplicates are idempotent and gaps are rejected.
14. ACK cursors are durable, so reconnect resumes from the missing sequence.
15. Mobile restores its saved P2P session after app restart.

## Local development: Mac browser + Android emulator/USB device

### Web

```bash
cd ai-miner-web-main
npm install
```

For a browser opened through a LAN-reachable Mac IP, leave the signaling URL blank so same-origin APIs are used:

```env
NEXT_PUBLIC_BRAIN2_SIGNALING_URL=
NEXT_PUBLIC_BRAIN2_ICE_SERVERS_JSON=[{"urls":"stun:stun.l.google.com:19302"}]
BRAIN2_ICE_SERVERS_JSON=[{"urls":"stun:stun.l.google.com:19302"}]
```

Run Next on all interfaces:

```bash
npm run dev -- --hostname 0.0.0.0
```

Find the Mac LAN IP, for example:

```bash
ipconfig getifaddr en0
```

Open the web app using that IP, not `localhost`, e.g. `http://192.168.1.20:3000`, then open **Devices** and generate the QR.

Alternative for Android connected by ADB: if the QR/web origin is `http://localhost:3000`, run this before scanning:

```bash
adb reverse tcp:3000 tcp:3000
```

This makes the Android device/emulator's localhost:3000 reach the Mac development server.

### Mobile

Build/run the Android app normally, then open:

`Devices & Sync → Scan Brain2 QR`

Expected status progression:

```text
QR detected. Validating Brain2 invitation…
QR valid. Registering this phone as an authorized replica…
Creating WebRTC offer…
Offer sent. Waiting for the web replica…
Direct WebRTC channel connected.
Verifying Brain2 memory root…
Memory verified. Requesting initial bootstrap…
Receiving Brain2 bootstrap · <table>
Bootstrap complete. Checking for newer deltas…
Brain2 replicas are synchronized.
```

## Golden acceptance test

### A. First bootstrap

1. Put real Brain2 data on web.
2. Start with an empty mobile Brain2 memory.
3. Generate QR on web and scan on mobile.
4. Wait for `Synced`.
5. Compare counts and representative IDs for messages, atoms, truths, projects, patterns, LifeWiki/notebook snapshots, Databox/MRS tables.

### B. Web → mobile delta

1. While paired, create/import one new web change.
2. Verify mobile receives only the new mutation(s), not a second bootstrap.
3. Verify the resulting canonical record and mutation ID/hash match.

### C. Mobile → web delta

1. Make one mobile-side Brain2 change that commits a mutation.
2. Verify web receives and applies it.
3. Verify ACK advances the mobile peer cursor.

### D. Reconnect

1. Disconnect mobile/network.
2. Make changes while offline.
3. Reconnect/restart the app.
4. Mobile should restore the saved P2P session.
5. Only missing deltas should transfer and both replicas should converge.

### E. Safety tests

- Re-scan the same QR: must fail because token is single-use.
- Pair a non-empty phone with a different memory root: must fail.
- Replay a mutation: must be idempotent.
- Tamper payload/hash: must be rejected.
- Introduce an origin sequence gap: must be rejected/preserved for retry.
- Interrupt bootstrap and pair/retry with a fresh invite: should safely restart bootstrap into an empty/reset replica.

## Production networking

For same-LAN tests, host/STUN candidates may be sufficient. For reliable internet/cellular/restrictive-NAT sync, configure TURN. Use TLS/HTTPS for the signaling origin in production. TURN credentials should preferably be short-lived rather than permanently embedded in the app or public web bundle.
