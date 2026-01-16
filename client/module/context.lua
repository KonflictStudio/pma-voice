contextStates = contextStates or {}
contextTargets = contextTargets or {}
contextOverrides = contextOverrides or {}

local function normalizeVolumeOverride(value)
	if type(value) ~= 'number' then
		return nil
	end
	if value >= 0 and value <= 1 then
		return value
	end
	if value < 0 then
		value = 0
	elseif value > 100 then
		value = 100
	end
	return value / 100
end

local function parseContextState(value)
	if type(value) ~= 'table' then
		return nil
	end
	local canTalk = value.canTalk
	if type(canTalk) ~= 'boolean' then
		canTalk = true
	end
	local isolateIncoming = value.isolateIncoming
	if type(isolateIncoming) ~= 'boolean' then
		isolateIncoming = false
	end
	local isolateOutgoing = value.isolateOutgoing
	if type(isolateOutgoing) ~= 'boolean' then
		isolateOutgoing = false
	end
	return {
		contextId = value.contextId,
		role = value.role,
		canTalk = canTalk,
		isolateIncoming = isolateIncoming,
		isolateOutgoing = isolateOutgoing,
		label = value.label,
		effect = value.effect,
		volumeOverride = value.volumeOverride,
	}
end

local function canSendToContextTarget(localState, targetState)
	if not localState or not targetState then
		return false
	end
	if localState.contextId ~= targetState.contextId then
		return false
	end
	if localState.role == targetState.role then
		return true
	end
	return localState.canTalk == true
end

local function canHearContextSpeaker(listenerState, speakerState)
	if not listenerState or not speakerState then
		return false
	end
	if listenerState.contextId ~= speakerState.contextId then
		return false
	end
	if listenerState.role == speakerState.role then
		return true
	end
	return speakerState.canTalk == true
end

local function isRadioActiveFor(serverId)
	if not radioData or not radioData[serverId] then
		return false
	end
	if type(isRadioEnabled) ~= 'function' then
		return false
	end
	return isRadioEnabled()
end

local function shouldOverrideVolume(serverId)
	local distance = currentTargets and currentTargets[serverId] or nil
	return not distance or distance > 4.0
end

local function applyNonContextVolume(serverId)
	if isPlayerMuted(serverId) then
		return
	end
	if not shouldOverrideVolume(serverId) then
		MumbleSetVolumeOverrideByServerId(serverId, -1.0)
		return
	end
	if isRadioActiveFor(serverId) then
		local volume = getVolumeFraction('radio')
		MumbleSetVolumeOverrideByServerId(serverId, volume or -1.0)
	elseif callData and callData[serverId] then
		local volume = getVolumeFraction('call')
		MumbleSetVolumeOverrideByServerId(serverId, volume or -1.0)
	else
		MumbleSetVolumeOverrideByServerId(serverId, -1.0)
	end
end

local function applyNonContextSubmix(serverId)
	if GetConvarInt('voice_enableSubmix', 1) ~= 1 then
		return
	end
	if isRadioActiveFor(serverId) then
		local submix = submixIndicies and submixIndicies['radio'] or nil
		if submix then
			MumbleSetSubmixForServerId(serverId, submix)
		end
	elseif callData and callData[serverId] then
		local submix = submixIndicies and submixIndicies['call'] or nil
		if submix then
			MumbleSetSubmixForServerId(serverId, submix)
		end
	else
		restoreDefaultSubmix(serverId)
	end
end

local function applyContextOverride(serverId, override)
	if isPlayerMuted(serverId) then
		return
	end
	if override.volume ~= nil then
		MumbleSetVolumeOverrideByServerId(serverId, override.volume)
	end
	if override.effect and GetConvarInt('voice_enableSubmix', 1) == 1 then
		local submix = submixIndicies and submixIndicies[override.effect] or nil
		if submix then
			MumbleSetSubmixForServerId(serverId, submix)
		else
			logger.warn('[context] Submix %s is not registered, skipping.', override.effect)
		end
	end
end

local function applyRemovedOverride(serverId, oldOverride)
	if not oldOverride then
		return
	end
	if oldOverride.volume ~= nil then
		applyNonContextVolume(serverId)
	end
	if oldOverride.effect ~= nil then
		applyNonContextSubmix(serverId)
	end
end

local function refreshContextTargets()
	local localState = contextStates[playerServerId]
	local newTargets = {}
	local newOverrides = {}

	if localState and localState.contextId then
		for serverId, state in pairs(contextStates) do
			if serverId ~= playerServerId and state.contextId == localState.contextId then
				if canSendToContextTarget(localState, state) then
					newTargets[serverId] = true
				end
				if localState.role ~= state.role and canHearContextSpeaker(localState, state) then
					local override = {}
					local vol = normalizeVolumeOverride(state.volumeOverride)
					if vol ~= nil then
						override.volume = vol
					end
					if type(state.effect) == 'string' then
						override.effect = state.effect
					end
					if override.volume ~= nil or override.effect ~= nil then
						newOverrides[serverId] = override
					end
				end
			end
		end
	end

	for serverId, oldOverride in pairs(contextOverrides) do
		local newOverride = newOverrides[serverId]
		if not newOverride then
			applyRemovedOverride(serverId, oldOverride)
		else
			if oldOverride.volume ~= newOverride.volume then
				if newOverride.volume ~= nil then
					applyContextOverride(serverId, { volume = newOverride.volume })
				else
					applyNonContextVolume(serverId)
				end
			end
			if oldOverride.effect ~= newOverride.effect then
				if newOverride.effect ~= nil then
					applyContextOverride(serverId, { effect = newOverride.effect })
				else
					applyNonContextSubmix(serverId)
				end
			end
		end
	end

	for serverId, newOverride in pairs(newOverrides) do
		if not contextOverrides[serverId] then
			applyContextOverride(serverId, newOverride)
		end
	end

	contextTargets = newTargets
	contextOverrides = newOverrides

	rebuildVoiceTargets()

	logger.verbose('[context] Refreshed targets. localContext=%s', localState and localState.contextId or 'none')
end

function getLocalContextState()
	return contextStates[playerServerId]
end

function isContextProximityBlocked(localContext)
	return localContext and (localContext.isolateIncoming == true or localContext.isolateOutgoing == true)
end

function shouldSkipContextProximity(serverId, localContext)
	local targetState = contextStates[serverId]
	local sameContext = localContext and targetState and localContext.contextId == targetState.contextId
	if sameContext then
		return true
	end
	if localContext and localContext.isolateOutgoing and not sameContext then
		return true
	end
	if targetState and targetState.isolateIncoming and not sameContext then
		return true
	end
	return false
end

AddStateBagChangeHandler('voiceContext', '', function(bagName, _, value)
	local tgtId = tonumber(bagName:gsub('player:', ''), 10)
	if not tgtId then return end
	if value == nil then
		contextStates[tgtId] = nil
		logger.verbose('[context] Cleared context state for player %s', tgtId)
	else
		contextStates[tgtId] = parseContextState(value)
		logger.verbose('[context] Updated context state for player %s (context=%s)', tgtId, value.contextId or 'none')
	end
	refreshContextTargets()
end)

AddEventHandler('onClientResourceStart', function(resource)
	if resource ~= GetCurrentResourceName() then
		return
	end
	Wait(0)
	local players = GetActivePlayers()
	for i = 1, #players do
		local ply = players[i]
		local serverId = GetPlayerServerId(ply)
		local state = Player(serverId).state.voiceContext
		if state then
			contextStates[serverId] = parseContextState(state)
		end
	end
	logger.verbose('[context] Initialized context states for %s players', #players)
	refreshContextTargets()
end)

RegisterNetEvent('onPlayerJoining', function(serverId)
	local state = Player(serverId).state.voiceContext
	if state then
		contextStates[serverId] = parseContextState(state)
	end
	logger.verbose('[context] Player %s joined (context=%s)', serverId, state and state.contextId or 'none')
	refreshContextTargets()
end)

RegisterNetEvent('onPlayerDropped', function(serverId)
	contextStates[serverId] = nil
	logger.verbose('[context] Player %s dropped', serverId)
	refreshContextTargets()
end)

AddEventHandler('mumbleConnected', function()
	logger.verbose('[context] Mumble connected, rebuilding targets')
	refreshContextTargets()
end)
