# Pulse Protocol Specification

## Versioning
- Protocol Version: `1`
- Envelope Schema: `protocol/schema/v1/envelope.json`

## Supported Messages (Phase 1)
- `agent.hello`: Sent immediately by the agent upon WebSocket connection or returned on `GET /api/v1/info`.
- `agent.heartbeat`: Broadcast every 5 seconds by the agent over the WebSocket channel.
- `connection.accepted`: Acknowledgment from client.
