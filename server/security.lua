-- =========================================================================
-- server/security.lua -- server-authoritative request validation
-- =========================================================================
-- Shared, cross-file globals (no `local`), same convention as rig_state.lua.
-- Every sensitive callback funnels through these three guards:
--
--   RequireNearRig(source, rig, action)  -- is the requester actually at the rig?
--   RateOk(source, action)               -- are they firing this faster than a human could?
--   FlagExploit(source, reason, detail)  -- count + log + maybe kick a bad request
--
-- The point: the client is never trusted to tell us where it is, how often it
-- clicked, or whether it "should" be allowed -- the server derives all of that
-- from the player's real session and the rig's stored state. A request that
-- fails a structural guard is something a legitimate UI can't produce, so it's
-- treated as an injected event, not a mistake.

local Security = Config.Security or {}

-- source -> { [action] = lastCallMs } for rate limiting.
local LastCall = {} ---@type table<number, table<string, number>>

-- source -> { count = n, resetAt = ms } for exploit flagging.
local Flags = {} ---@type table<number, { count: integer, resetAt: number }>

---Real, server-side position of a player's ped. A client cannot spoof this
---the way it could a value passed up in a callback argument.
---@param source number
---@return vector3?
function PlayerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

---Distance gate for any rig-scoped action. Returns false (and flags an
---exploit) when the requester is nowhere near the rig they're acting on.
---@param source number
---@param rig MiningRig?
---@param action string -- logical action name, for logging
---@return boolean
function RequireNearRig(source, rig, action)
    if not rig then return false end

    local coords = PlayerCoords(source)
    if not coords then
        FlagExploit(source, 'no-ped', action)
        return false
    end

    local maxDist = Security.maxInteractDistance or 5.0
    local dist = #(coords - rig.coords)
    if dist > maxDist then
        FlagExploit(source, 'distance', ('%s rig=%d dist=%.1f max=%.1f'):format(action, rig.id, dist, maxDist))
        return false
    end

    return true
end

---Per-action rate limiter. True = allowed (and the timestamp is recorded),
---false = too soon (and the attempt is flagged). Keyed per source + action.
---@param source number
---@param action string
---@return boolean
function RateOk(source, action)
    if not Security.rateLimit or not Security.rateLimit.enabled then return true end

    local now = GetGameTimer()
    local window = (Security.rateLimit.actions and Security.rateLimit.actions[action])
        or Security.rateLimit.default or 300

    local bucket = LastCall[source]
    if not bucket then
        bucket = {}
        LastCall[source] = bucket
    end

    local last = bucket[action]
    if last and (now - last) < window then
        FlagExploit(source, 'rate-limit', ('%s interval=%dms min=%dms'):format(action, now - last, window))
        return false
    end

    bucket[action] = now
    return true
end

---Records a structural violation against a source. Logs it (if Discord logging
---and the `exploit` category are on) and, when configured, kicks a source that
---trips too many flags inside the decay window.
---@param source number
---@param reason string
---@param detail string?
function FlagExploit(source, reason, detail)
    if not Security.flagExploits then return end

    local name = GetPlayerName(source) or ('src:%s'):format(source)
    local citizenid = GetCitizenId(source) or 'unknown'

    if Log then
        Log('exploit', {
            title = 'Anti-Exploit Flag',
            severity = 'danger',
            description = ('`%s` was rejected by a server guard.'):format(reason),
            fields = {
                { name = 'Player', value = ('%s (%s)'):format(name, source), inline = true },
                { name = 'CitizenID', value = citizenid, inline = true },
                { name = 'Detail', value = detail or '-', inline = false },
            },
        })
    end

    print(('^3[anxious_btcmining] [anti-exploit] %s (src %s / %s) -- %s | %s^7')
        :format(reason, source, citizenid, detail or '-', name))

    local now = GetGameTimer()
    local decay = Security.exploitDecayMs or 120000
    local entry = Flags[source]
    if not entry or now > entry.resetAt then
        entry = { count = 0, resetAt = now + decay }
        Flags[source] = entry
    end
    entry.count += 1
    entry.resetAt = now + decay

    if Security.kickOnExploitThreshold and entry.count >= (Security.exploitThreshold or 12) then
        Flags[source] = nil
        DropPlayer(source, 'Kicked for repeated invalid mining requests (anti-cheat).')
    end
end

---Convenience combined guard used by the rig callbacks: access + distance +
---rate, in that order, with a single return. `rig` is looked up by the caller
---so the ownership check (HasRigAccess) stays where the business logic is.
---@param source number
---@param rig MiningRig?
---@param action string
---@return boolean
function GuardRigAction(source, rig, action)
    if not rig then return false end
    if not RateOk(source, action) then return false end
    if not RequireNearRig(source, rig, action) then return false end
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    LastCall[src] = nil
    Flags[src] = nil
end)
