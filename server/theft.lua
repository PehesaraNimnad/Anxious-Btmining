local Cooldowns = {} ---@type table<integer, integer> -- rigId -> os.time() the cooldown ends
local InProgress = {} ---@type table<integer, number> -- rigId -> source currently attempting it
local AttemptsToday = {} ---@type table<integer, integer>

-- Resets the daily attempt cap once every 24h -- simple in-memory counter,
-- not tied to real calendar days, which is fine for an anti-farming backstop.
CreateThread(function()
    while true do
        Wait(86400000)
        AttemptsToday = {}
    end
end)

local function getSecurityLevel(rig)
    -- Config.SecurityUpgrades maps an ox_inventory item to a level -- left
    -- empty by default (see config.lua), so every rig is level 1 unless a
    -- buyer wires up their own upgrade item check here.
    return 1
end

-- A more hardened rig is noisier when touched: each security level past 1 adds
-- 15% to the dispatch chance, so a locked-down rig is likelier to raise a
-- police raid than an undefended one. Capped so it can't exceed 1.0 upstream.
local function dispatchBonus(rig)
    return math.max(0, (getSecurityLevel(rig) - 1)) * 0.15
end

---@param source number
---@param rigId integer
lib.callback.register('anxious_btcmining:server:requestHack', function(source, rigId)
    if not Config.Theft.enabled then return false end

    local rig = GetRig(rigId)
    if not rig then return false end

    -- A thief has to be physically at the rig, and can't spam the request --
    -- same server-side guards as every authorized action.
    if not RateOk(source, 'requestHack') then return false end
    if not RequireNearRig(source, rig, 'requestHack') then return false end

    local citizenid = GetCitizenId(source)
    if HasRigAccess(rig, citizenid) then
        return false, 'You already have access to this rig'
    end

    if rig.status.seized or rig.status.onFire then
        return false, 'This rig isn\'t accessible right now'
    end

    if InProgress[rigId] then
        return false, 'Someone is already attempting this'
    end

    if Cooldowns[rigId] and Cooldowns[rigId] > os.time() then
        return false, 'This rig was hit recently, try again later'
    end

    if Config.Theft.maxAttemptsPerDay > 0 then
        local attempts = AttemptsToday[rigId] or 0
        if attempts >= Config.Theft.maxAttemptsPerDay then
            return false, 'This rig has hit its daily attempt limit'
        end
    end

    AttemptsToday[rigId] = (AttemptsToday[rigId] or 0) + 1

    -- Generate the "Firewall Breach" sequence HERE, on the server, and keep it
    -- -- the client is sent the sequence only so it can display it, and must
    -- echo the player's actual clicks back (submitHack) to be checked against
    -- this stored copy. The server, not the client, decides success. This is
    -- what closes the "just call resolve(true) and skip the minigame" hole:
    -- a crafted submit now has to reproduce a server-chosen sequence, not send
    -- a boolean.
    local level = math.min(getSecurityLevel(rig), #Config.Theft.difficulty)
    local diff = Config.Theft.difficulty[level]

    local sequence = {}
    local last = -1
    for i = 1, diff.length do
        local n = math.random(0, diff.gridSize - 1)
        while n == last and diff.gridSize > 1 do
            n = math.random(0, diff.gridSize - 1)
        end
        sequence[i] = n
        last = n
    end

    InProgress[rigId] = { source = source, sequence = sequence, startedAt = os.time() }

    -- The moment a break-in starts can optionally raise a (low-chance) alert,
    -- so a sharp dispatcher sometimes gets a head start before the hack even
    -- resolves. Off by default (see Config.Dispatch.alerts.hackStarted).
    SendPoliceAlert('hackStarted', rig, { chanceBonus = dispatchBonus(rig) })

    Log('theft', {
        title = 'Hack Started',
        severity = 'warn',
        fields = {
            { name = 'Thief', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
            { name = 'Rig', value = ('#%d (owner %s)'):format(rigId, rig.citizenid), inline = true },
        },
    })

    -- Copy the difficulty (never hand out a reference to the config table) and
    -- attach the sequence the client must display.
    return true, {
        gridSize = diff.gridSize,
        length = diff.length,
        showDelayMs = diff.showDelayMs,
        inputTimeoutMs = diff.inputTimeoutMs,
        sequence = sequence,
    }
end)

---@param source number
---@param rigId integer
---@param input number[] -- the cells the player actually clicked, in order
lib.callback.register('anxious_btcmining:server:submitHack', function(source, rigId, input)
    local rig = GetRig(rigId)

    local attempt = InProgress[rigId]
    -- Must be the same player who started this attempt (no hijacking someone
    -- else's in-progress hack, no submitting without ever calling requestHack).
    if not attempt or attempt.source ~= source then
        return false
    end
    -- Always clear the lock, even if the rig vanished or the submit is bogus.
    InProgress[rigId] = nil

    if not rig then return false end

    -- SUCCESS IS DECIDED HERE, not by the client: the submitted input must
    -- reproduce the sequence the server generated in requestHack, exactly and
    -- in order. A missing/short/wrong submission simply fails.
    local success = type(input) == 'table' and #input == #attempt.sequence
    if success then
        for i = 1, #attempt.sequence do
            if input[i] ~= attempt.sequence[i] then
                success = false
                break
            end
        end
    end

    if success then
        local fraction = Config.Theft.stealFraction.min +
            math.random() * (Config.Theft.stealFraction.max - Config.Theft.stealFraction.min)
        local stolenMicro = math.floor(rig.banked_micro_btc * fraction)

        if stolenMicro > 0 then
            rig.banked_micro_btc -= stolenMicro
            MarkDirty(rigId)

            local wholeItems = math.floor(stolenMicro / Config.MicroBtcPerItem)
            if wholeItems > 0 then
                exports.ox_inventory:AddItem(source, Config.BtcItemName, wholeItems)
            end
        end

        Cooldowns[rigId] = os.time() + math.floor(Config.Theft.cooldownMs / 1000)

        if Config.Theft.alertOwner then
            local owner = exports.qbx_core:GetPlayerByCitizenId(rig.citizenid)
            if owner then
                exports.qbx_core:Notify(owner.PlayerData.source, 'Your mining rig was just hacked', 'error')
            end
        end

        -- A successful drain is the loudest event -- raise a crypto-theft raid.
        SendPoliceAlert('hackSuccess', rig, { chanceBonus = dispatchBonus(rig) })

        Log('theft', {
            title = 'Rig Drained',
            severity = 'danger',
            fields = {
                { name = 'Thief', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
                { name = 'Rig', value = ('#%d (owner %s)'):format(rigId, rig.citizenid), inline = true },
                { name = 'Stolen', value = ('%d micro-BTC'):format(stolenMicro), inline = true },
            },
        })

        return true
    end

    Cooldowns[rigId] = os.time() + math.floor(Config.Theft.failCooldownMs / 1000)

    -- A tripped alarm raises a (higher-chance) raid, and still fires the
    -- original generic hook for anyone who wired their own dispatch to it.
    SendPoliceAlert('hackFailed', rig, { chanceBonus = dispatchBonus(rig) })

    if Config.Theft.alertPoliceOnFail then
        TriggerEvent('anxious_btcmining:hackFailedNearby', rig.coords)
    end

    Log('theft', {
        title = 'Hack Failed',
        severity = 'warn',
        fields = {
            { name = 'Thief', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
            { name = 'Rig', value = ('#%d (owner %s)'):format(rigId, rig.citizenid), inline = true },
        },
    })

    return false
end)

---@param source number
---@param rigId integer
lib.callback.register('anxious_btcmining:server:stealGpu', function(source, rigId)
    if not Config.Theft.allowGpuTheft then return false end

    local rig = GetRig(rigId)
    if not rig then return false end

    if not RateOk(source, 'stealGpu') then return false end
    if not RequireNearRig(source, rig, 'stealGpu') then return false end

    local citizenid = GetCitizenId(source)
    if HasRigAccess(rig, citizenid) then return false end

    local occupiedIndexes = {}
    for i, slot in ipairs(rig.slots) do
        if slot and slot.tier then occupiedIndexes[#occupiedIndexes + 1] = i end
    end
    if #occupiedIndexes == 0 then return false end

    local index = occupiedIndexes[math.random(#occupiedIndexes)]
    local slot = rig.slots[index]
    local tier = GetGpuTier(slot.tier)
    if not tier then return false end

    local loss = math.random(Config.Theft.gpuTheftConditionLoss.min, Config.Theft.gpuTheftConditionLoss.max)
    local durability = math.max(1, slot.durability - loss)

    rig.slots[index] = false
    MarkDirty(rigId)

    exports.ox_inventory:AddItem(source, tier.item, 1, { durability = durability })

    -- Physically ripping hardware out is always worth a dispatch (chance 1.0).
    SendPoliceAlert('gpuTheft', rig, { chanceBonus = dispatchBonus(rig) })

    Log('theft', {
        title = 'GPU Stolen',
        severity = 'danger',
        fields = {
            { name = 'Thief', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
            { name = 'Rig', value = ('#%d (owner %s)'):format(rigId, rig.citizenid), inline = true },
            { name = 'GPU', value = ('%s (%.0f%%)'):format(tier.label, durability), inline = true },
        },
    })

    return true
end)
