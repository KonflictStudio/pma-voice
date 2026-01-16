## setContextPlayerState

## Description

Updates a players state within a voice context.

## Parameters

* **contextId**: The context identifier
* **source**: The player server ID
* **changes**: Table of changes to apply
  * **role** (string): `participant` or `monitor`
  * **canTalk** (boolean)
  * **isolateIncoming** (boolean)
  * **isolateOutgoing** (boolean)
  * **label** (string|false): Set a label override, or `false` to clear the override
  * **effect** (string|false): Set a submix override, or `false` to clear the override
  * **volumeOverride** (number|false): Set a volume override (0-100, or 0.0-1.0), or `false` to clear it

```lua
exports['pma-voice']:setContextPlayerState('interview-room', source, {
  canTalk = true,
  volumeOverride = 60
})
```

