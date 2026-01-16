## createContext

## Description

Creates (or updates) a voice context.

Contexts are server-managed groups that sync to clients via the `voiceContext` state bag.

## Parameters

* **contextId**: The context identifier
* **opts** (optional):
  * **label** (string): Default label for players in this context
  * **effect** (string): Default submix name to apply for cross-role voice (requires `voice_enableSubmix`)
  * **volumeOverride** (number): Default volume override for cross-role voice (0-100, or 0.0-1.0)

```lua
exports['pma-voice']:createContext('interview-room', {
  label = 'Interview Room',
  effect = 'radio',
  volumeOverride = 0.8
})
```

