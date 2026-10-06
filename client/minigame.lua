-- Bridges Lua-triggered minigames (hacking a rig, fighting a fire -- both
-- started from an ox_target option out in the world, with no dashboard
-- open) into the same NUI the dashboard uses. GpuTab.tsx runs its own
-- install minigame inline instead, since that one only ever happens while
-- the dashboard is already open and focused.

local pending = {} ---@type table<integer, any> -- requestId -> promise
local nextRequestId = 0

---@param kind 'extinguish'|'hack'
---@param difficulty table -- SweepDifficulty or SequenceDifficulty, shape must match `kind`
---@return boolean success
---@return number[]? input -- for 'hack', the cells the player clicked (echoed to the server to validate); nil otherwise
function RunMinigame(kind, difficulty)
    nextRequestId += 1
    local requestId = nextRequestId

    local p = promise.new()
    pending[requestId] = p

    -- DashboardOpen (client/dashboard.lua) is only true here if a player
    -- somehow triggers a world minigame while their own dashboard is open --
    -- shouldn't normally happen, but if it does, don't fight the dashboard
    -- for NUI focus or clobber it on close.
    if not DashboardOpen then
        SetNuiFocus(true, true)
    end

    SendNUIMessage({
        action = 'openMinigame',
        data = { requestId = requestId, kind = kind, difficulty = difficulty },
    })

    local result = Citizen.Await(p)

    if not DashboardOpen then
        SetNuiFocus(false, false)
    end

    -- result is { success = boolean, input = number[]? } -- the input array is
    -- only present for the hack minigame, where the server needs the player's
    -- actual clicks to validate the attempt itself (it can't trust a boolean).
    return result.success == true, result.input
end

RegisterNUICallback('minigameResult', function(data, cb)
    local p = pending[data.requestId]
    if p then
        pending[data.requestId] = nil
        p:resolve({ success = data.success == true, input = data.input })
    end
    cb(1)
end)
