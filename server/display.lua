-- =========================================================================
-- server/display.lua -- public "world screen" snapshots for nearby rigs
-- =========================================================================
-- Feeds the floating monitor that client/screen.lua renders on a rig when a
-- player walks up to it. This data is intentionally PUBLIC (status, heat,
-- hashrate, power, temps) -- it's what a real rig's screen would show to anyone
-- standing in front of it, and the spec calls for shared screen state: two
-- players looking at the same rig see the same numbers. Nothing sensitive
-- (balances, ownership, who has access) is exposed here.
--
-- Requests are still proximity-gated so a client can't scrape every rig on the
-- map in one call -- you only get snapshots for rigs you're actually near.

local Heat = Config.Heat

-- Derive a screen status + severity from a rig's live state.
local function deriveStatus(rig, assembled)
    if rig.status and rig.status.onFire then
        return 'FIRE', 'danger'
    end
    if not assembled then
        return 'ASSEMBLE', 'warn'
    end
    if not rig.power_state then
        return 'POWERED OFF', 'idle'
    end
    if rig.heat >= Heat.meltdownPct then
        return 'CRITICAL', 'danger'
    end
    if rig.heat >= Heat.criticalPct then
        return 'OVERHEAT', 'danger'
    end
    if rig.heat >= Heat.warmPct then
        return 'MINING · WARM', 'warn'
    end
    return 'MINING', 'good'
end

---@param rig MiningRig
local function toDisplay(rig)
    local model = Config.RigModels[rig.rig_model]
    local assembled = RigIsAssembled(rig)
    local live = RigLiveStats(rig)
    local online = assembled and rig.power_state and not (rig.status and rig.status.onFire)

    local status, severity = deriveStatus(rig, assembled)

    -- Temperatures read off the single heat value (0-100) the sim tracks, split
    -- into plausible CPU/GPU numbers around a ~28C ambient room.
    local gpuTemp = math.floor(28 + rig.heat * 0.62)
    local cpuTemp = math.floor(28 + rig.heat * 0.42)

    local usedSlots = 0
    for _, slot in ipairs(rig.slots) do
        if slot and slot.tier then usedSlots = usedSlots + 1 end
    end

    local hasCooling = GetRigComponent(rig, 'cooling') ~= nil

    return {
        id = rig.id,
        label = (model and model.label) or rig.rig_model,
        status = status,
        severity = severity,
        online = online and true or false,
        assembled = assembled,
        powered = rig.power_state and true or false,
        legacy = rig.components == nil,
        heat = math.floor(rig.heat + 0.5),
        powerKw = math.floor(live.draw / 10) / 100, -- draw(W) -> kW, 2dp
        -- Show effective hashrate only while actually running; a stopped or
        -- half-built rig reads 0 the way a real idle miner would.
        hashrate = online and (math.floor(live.hashrate * 100) / 100) or 0,
        btcPerHour = online and (math.floor((live.microBtcPerHour / Config.MicroBtcPerItem) * 1e6) / 1e6) or 0,
        gpuTemp = gpuTemp,
        cpuTemp = cpuTemp,
        usedSlots = usedSlots,
        maxSlots = (model and model.maxSlots) or #rig.slots,
        hasCooling = hasCooling,
    }
end

---@param source number
---@param rigIds integer[] -- the rig ids the client currently has streamed in near it
lib.callback.register('anxious_btcmining:server:getRigDisplays', function(source, rigIds)
    if not Config.Screen or not Config.Screen.enabled then return {} end
    if type(rigIds) ~= 'table' then return {} end

    local coords = PlayerCoords(source)
    if not coords then return {} end

    local range = (Config.Screen.range or 9.0) + 3.0 -- small buffer over the client's render range
    local maxReturn = Config.Screen.maxOnScreen or 5

    local out = {}
    local n = 0
    for _, rigId in ipairs(rigIds) do
        if n >= maxReturn then break end
        local rig = GetRig(rigId)
        if rig and #(coords - rig.coords) <= range then
            out[tostring(rigId)] = toDisplay(rig)
            n = n + 1
        end
    end

    return out
end)
