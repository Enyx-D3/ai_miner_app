# B2 Network / P2P Mobile Integration

The mobile client expects the paired Brain2 web origin to expose:

```text
POST /api/brain2-sync/devices
GET/POST /api/brain2-sync/signals
```

QR pairing supplies the web origin, inviter device ID, join token and expiry.

## Required integrations

- Internet permission: already declared.
- Camera permission: already declared for QR scanning.
- Deployed Brain2 web signaling endpoints.
- WebRTC-compatible network environment.
- STUN servers for ordinary NAT traversal.
- TURN server for restrictive NAT/firewall conditions if production requires reliable remote pairing.

## ICE configuration

`Brain2P2PSync` accepts an `iceServers` list. Production should inject the deployed STUN/TURN configuration instead of relying on an empty list.

Example shape:

```dart
[
  {'urls': ['stun:stun.example.com:3478']},
  {
    'urls': ['turn:turn.example.com:3478'],
    'username': '<ephemeral-user>',
    'credential': '<ephemeral-credential>',
  }
]
```

Do not hard-code long-lived TURN credentials in the application bundle.

## Golden flow

```text
web generates pairing QR
  ↓
mobile scans
  ↓
register/join token
  ↓
WebRTC signaling
  ↓
ordered brain2-sync DataChannel
  ↓
empty-device bootstrap if needed
  ↓
memoryRoot equality
  ↓
mutation/delta sync
  ↓
ACK/cursor advancement
```

## Acceptance gates

- empty mobile bootstrap;
- same memory root;
- same canonical IDs;
- same Current Truth state for synced canonical data;
- disconnect → mutations → reconnect → convergence;
- duplicate replay safety;
- pairing expiry/replay rejection;
- STUN/TURN cross-network test.
