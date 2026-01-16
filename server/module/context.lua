voiceContexts = voiceContexts or {}
contextPlayers = contextPlayers or {}

local function normalizeRole(role)
	if role == 'participant' or role == 'monitor' then
		return role
	end
	return 'participant'
end

local function normalizeVolumeOverride(value)
	if type(value) ~= 'number' then
		return nil
	end
	if value > 0 and value <= 1 then
		value = value * 100
	end
	if value < 0 then
		value = 0
	elseif value > 100 then
		value = 100
	end
	return value
end

local function buildContextState(contextId, context, playerData)
	local label = playerData.label
	if label == nil then
		label = context.label
		if label == nil then
			label = contextId
		end
	end
	local effect = playerData.effect
	if effect == nil then
		effect = context.effect
	end
	local volumeOverride = playerData.volumeOverride
	if volumeOverride == nil then
		volumeOverride = context.volumeOverride
	end
	return {
		contextId = contextId,
		role = playerData.role,
		canTalk = playerData.canTalk,
		isolateIncoming = playerData.isolateIncoming,
		isolateOutgoing = playerData.isolateOutgoing,
		label = label,
		effect = effect,
		volumeOverride = volumeOverride,
	}
end

local function syncContextPlayer(source, contextId, context, playerData)
	local plyState = Player(source).state
	plyState:set('voiceContext', buildContextState(contextId, context, playerData), true)
end

local function clearContextPlayer(source)
	Player(source).state:set('voiceContext', nil, true)
end

local function getContext(contextId)
	return voiceContexts[contextId]
end

local function createContextInternal(contextId, opts)
	local context = voiceContexts[contextId]
	if not context then
		context = {
			id = contextId,
			label = nil,
			effect = nil,
			volumeOverride = nil,
			players = {}
		}
		voiceContexts[contextId] = context
		logger.verbose('[context] Created context %s (label=%s effect=%s volumeOverride=%s)', contextId, tostring(context.label), tostring(context.effect), tostring(context.volumeOverride))
	end

	if opts then
		if opts.label ~= nil then
			type_check({ opts.label, 'string' })
			context.label = opts.label
		end
		if opts.effect ~= nil then
			type_check({ opts.effect, 'string' })
			context.effect = opts.effect
		end
		if opts.volumeOverride ~= nil then
			type_check({ opts.volumeOverride, 'number' })
			context.volumeOverride = normalizeVolumeOverride(opts.volumeOverride)
		end
		logger.verbose('[context] Updated context %s settings (label=%s effect=%s volumeOverride=%s)', contextId, tostring(context.label), tostring(context.effect), tostring(context.volumeOverride))
	end

	return context
end

local function removePlayerFromContext(source, contextId)
	local context = voiceContexts[contextId]
	if not context then
		return false
	end
	if not context.players[source] then
		return false
	end

	context.players[source] = nil
	contextPlayers[source] = nil
	clearContextPlayer(source)
	logger.verbose('[context] Removed player %s from context %s', source, contextId)

	return true
end

exports('createContext', function(contextId, opts)
	type_check({ contextId, 'string' })
	if opts ~= nil then
		type_check({ opts, 'table' })
	end
	local context = createContextInternal(contextId, opts)

	for source, playerData in pairs(context.players) do
		syncContextPlayer(source, contextId, context, playerData)
	end

	return true
end)

exports('destroyContext', function(contextId)
	type_check({ contextId, 'string' })
	local context = voiceContexts[contextId]
	if not context then
		return false
	end

	local members = {}
	for source, _ in pairs(context.players) do
		members[#members + 1] = source
	end
	for i = 1, #members do
		removePlayerFromContext(members[i], contextId)
	end

	voiceContexts[contextId] = nil
	logger.verbose('[context] Destroyed context %s (members=%s)', contextId, #members)
	return true
end)

exports('addContextPlayer', function(contextId, source, opts)
	type_check({ contextId, 'string' }, { source, 'number' })
	local context = getContext(contextId)
	if not context then
		error(('Context %s does not exist. Create it first.'):format(contextId))
	end

	if not isValidPlayer(source) then
		logger.warn('[context] Tried to add invalid player %s to context %s', source, contextId)
		return false
	end

	local existingContext = contextPlayers[source]
	if existingContext and existingContext ~= contextId then
		removePlayerFromContext(source, existingContext)
	end

	if opts ~= nil then
		type_check({ opts, 'table' })
	end
	opts = opts or {}

	local canTalk = opts.canTalk
	if type(canTalk) ~= 'boolean' then
		canTalk = true
	end
	local isolateIncoming = opts.isolateIncoming
	if type(isolateIncoming) ~= 'boolean' then
		isolateIncoming = false
	end
	local isolateOutgoing = opts.isolateOutgoing
	if type(isolateOutgoing) ~= 'boolean' then
		isolateOutgoing = false
	end

	local playerData = {
		role = normalizeRole(opts.role),
		canTalk = canTalk,
		isolateIncoming = isolateIncoming,
		isolateOutgoing = isolateOutgoing,
		label = opts.label,
		effect = opts.effect,
		volumeOverride = normalizeVolumeOverride(opts.volumeOverride),
	}

	if playerData.label ~= nil then
		type_check({ playerData.label, 'string' })
	end
	if playerData.effect ~= nil then
		type_check({ playerData.effect, 'string' })
	end
	if opts.volumeOverride ~= nil then
		type_check({ opts.volumeOverride, 'number' })
	end

	context.players[source] = playerData
	contextPlayers[source] = contextId
	syncContextPlayer(source, contextId, context, playerData)
	logger.verbose(
		'[context] Added player %s to context %s (role=%s opts=%s)',
		source,
		contextId,
		playerData.role,
		json.encode(opts)
	)

	return true
end)

exports('setContextPlayerState', function(contextId, source, changes)
	type_check({ contextId, 'string' }, { source, 'number' }, { changes, 'table' })
	local context = getContext(contextId)
	if not context then
		return false
	end

	local playerData = context.players[source]
	if not playerData then
		return false
	end

	if changes.role ~= nil then
		playerData.role = normalizeRole(changes.role)
	end

	if changes.canTalk ~= nil then
		if type(changes.canTalk) == 'boolean' then
			playerData.canTalk = changes.canTalk
		end
	end

	if changes.isolateIncoming ~= nil then
		if type(changes.isolateIncoming) == 'boolean' then
			playerData.isolateIncoming = changes.isolateIncoming
		end
	end

	if changes.isolateOutgoing ~= nil then
		if type(changes.isolateOutgoing) == 'boolean' then
			playerData.isolateOutgoing = changes.isolateOutgoing
		end
	end

	if changes.label ~= nil then
		if changes.label == false then
			playerData.label = nil
		else
			type_check({ changes.label, 'string' })
			playerData.label = changes.label
		end
	end

	if changes.effect ~= nil then
		if changes.effect == false then
			playerData.effect = nil
		else
			type_check({ changes.effect, 'string' })
			playerData.effect = changes.effect
		end
	end

	if changes.volumeOverride ~= nil then
		if changes.volumeOverride == false then
			playerData.volumeOverride = nil
		else
			type_check({ changes.volumeOverride, 'number' })
			playerData.volumeOverride = normalizeVolumeOverride(changes.volumeOverride)
		end
	end

	syncContextPlayer(source, contextId, context, playerData)
	logger.verbose(
		'[context] Updated player %s in context %s (changes=%s)',
		source,
		contextId,
		json.encode(changes)
	)
	return true
end)

exports('removeContextPlayer', function(contextId, source)
	type_check({ contextId, 'string' }, { source, 'number' })
	return removePlayerFromContext(source, contextId)
end)

AddEventHandler('playerDropped', function()
	local contextId = contextPlayers[source]
	if contextId then
		removePlayerFromContext(source, contextId)
	end
end)
