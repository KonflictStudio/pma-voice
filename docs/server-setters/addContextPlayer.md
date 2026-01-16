## addContextPlayer

## Description

Adds a player to a voice context.

If the player is already in another context, they will be removed from the previous context first.

## Parameters

* **contextId**: The context identifier (must already exist)
* **source**: The player server ID
* **opts** (optional):
  * **role** (string): `participant` or `monitor` (default: `participant`)
  * **canTalk** (boolean): Allows cross-role voice when roles differ (default: `true`)
  * **isolateIncoming** (boolean): Blocks proximity voice from players not in the same context (default: `false`)
  * **isolateOutgoing** (boolean): Blocks your proximity voice to players not in the same context (default: `false`)
  * **label** (string): Player label override (falls back to context label / contextId)
  * **effect** (string): Player submix override for cross-role voice
  * **volumeOverride** (number): Player volume override for cross-role voice (0-100, or 0.0-1.0)

```lua
exports['pma-voice']:createContext('interview-room', { label = 'Interview Room' })
exports['pma-voice']:addContextPlayer('interview-room', source, {
  role = 'monitor',
  canTalk = false,
  isolateIncoming = true
})
```

