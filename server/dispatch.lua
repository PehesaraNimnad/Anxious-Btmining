-- =========================================================================
-- server/dispatch.lua -- framework-agnostic police alert bridge  (spec §40/§41)
-- =========================================================================
-- One global entry point, SendPoliceAlert(kind, rig, extra), used by the theft
-- and access code. It resolves the configured provider, applies the per-kind
-- enable/chance gate, enforces the "enough cops online" gate, and dispatches.
--
-- Nothing here trusts the client -- alerts are raised purely from server-side
-- state (which rig, where it is, who touched it), so a thief can't suppress an
-- alert and a non-thief can't spoof one.

local Cfg = Config.Dispatch or {}

-- Resolved once on first use: 'auto' is turned into a concrete provider name
-- by probing which dispatch resources are actually started.
local resolvedProvider = nil

---@param resource string
---@return boolean
local function started(resource)
    return GetResourceState(resource) == 'started'
end

local function resolveProvider()
    if resolvedProvider then return resolvedProvider end

    local p = Cfg.provider or 'auto'
    if p ~= 'auto' then
        resolvedProvider = p
        return p
    end

    -- Detection order: most specific/common dispatch resources first, then
    -- fall back to the self-contained standalone implementation so an alert
    -- always goes *somewhere* even with no dispatch resource installed.
    if started('ps-dispatch') then resolvedProvider = 'ps-dispatch'
    elseif started('cd_dispatch') then resolvedProvider = 'cd_dispatch'
    elseif started('qs-dispatch') then resolvedProvider = 'qs-dispatch'
    elseif started('core_dispatch') then resolvedProvider = 'core_dispatch'
    elseif started('linden_outlawalert') then resolvedProvider = 'linden_outlawalert'
    else resolvedProvider = 'standalone' end

    print(('^2[anxious_btcmining] dispatch provider resolved to "%s"^7'):format(resolvedProvider))
    return resolvedProvider
end

-- -------------------------------------------------------------------------
-- On-duty police lookup (also used by the min-cops gate)
-- -------------------------------------------------------------------------
-- qbx_core players expose job + onduty; edit this one function if your
-- framework models duty differently and every provider follows suit.
---@return number[] sources of on-duty officers
local function getOnDutyPolice()
    local out = {}
    local jobs = {}
    for _, j in ipairs(Cfg.policeJobs or { 'police' }) do jobs[j] = true end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = src and exports.qbx_core:GetPlayer(src)
        if player then
            local job = player.PlayerData.job
            if job and jobs[job.name] and job.onduty then
                out[#out + 1] = src
            end
        end
    end
    return out
end

-- -------------------------------------------------------------------------
-- Per-provider senders. Each receives a normalised `alert` table:
--   { coords, title, message, code, blip = {sprite,colour,scale,lengthSeconds},
--     policeSources = { ... } }
-- -------------------------------------------------------------------------
local Providers = {}

function Providers.standalone(alert)
    -- No dispatch resource required: notify every on-duty officer and ask
    -- their clients to drop a temporary blip (client/dispatch.lua).
    for _, src in ipairs(alert.policeSources) do
        exports.qbx_core:Notify(src, ('%s: %s'):format(alert.code or '911', alert.message), 'inform')
        TriggerClientEvent('anxious_btcmining:client:dispatchBlip', src, {
            coords = alert.coords,
            label = alert.title,
            sprite = alert.blip.sprite,
            colour = alert.blip.colour,
            scale = alert.blip.scale,
            lengthSeconds = alert.blip.lengthSeconds,
        })
    end
end

Providers['ps-dispatch'] = function(alert)
    -- ps-dispatch exposes a CustomAlert export; wrapped in pcall because its
    -- signature has shifted across versions and we'd rather no-op than error.
    pcall(function()
        exports['ps-dispatch']:CustomAlert({
            coords = alert.coords,
            message = alert.message,
            dispatchcode = alert.code,
            description = alert.title,
            radius = 0,
            sprite = alert.blip.sprite,
            color = alert.blip.colour,
            scale = alert.blip.scale,
            length = alert.blip.lengthSeconds / 60,
            jobs = Cfg.policeJobs,
        })
    end)
end

function Providers.cd_dispatch(alert)
    -- cd_dispatch is driven by a server event carrying a job table.
    local info = {
        job_table = Cfg.policeJobs,
        coords = alert.coords,
        title = alert.code or '10-90',
        message = alert.message,
        flash = 0,
        unique_id = tostring(math.random(0000000, 9999999)),
        blip = {
            sprite = alert.blip.sprite,
            scale = alert.blip.scale,
            colour = alert.blip.colour,
            flashes = false,
            text = alert.title,
            time = (alert.blip.lengthSeconds * 1000),
        },
    }
    TriggerEvent('cd_dispatch:AddNotification', info)
end

Providers['qs-dispatch'] = function(alert)
    pcall(function()
        exports['qs-dispatch']:CustomAlert({
            coords = alert.coords,
            title = alert.title,
            message = alert.message,
            code = alert.code,
            jobs = Cfg.policeJobs,
            blipData = {
                sprite = alert.blip.sprite,
                color = alert.blip.colour,
                scale = alert.blip.scale,
            },
        })
    end)
end

function Providers.core_dispatch(alert)
    -- core_dispatch takes a server-side addCall with a fixed arg order.
    TriggerEvent('core_dispatch:addCall',
        alert.title,
        alert.message,
        { { icon = 'fa-microchip', detail = alert.code or '10-90' } },
        { alert.coords.x, alert.coords.y, alert.coords.z },
        'police',
        (alert.blip.lengthSeconds * 1000),
        alert.blip.sprite,
        alert.blip.colour,
        alert.blip.scale
    )
end

function Providers.linden_outlawalert(alert)
    pcall(function()
        TriggerEvent('wk:addDispatchCall', {
            coords = alert.coords,
            message = alert.message,
            name = alert.title,
            blip = { sprite = alert.blip.sprite, colour = alert.blip.colour, scale = alert.blip.scale },
        })
    end)
end

function Providers.custom(alert)
    -- Route it into whatever bespoke system a server runs. Handle this event
    -- in your own resource; the stub at the bottom of this file just logs it.
    TriggerEvent('anxious_btcmining:dispatch:custom', alert)
end

-- -------------------------------------------------------------------------
-- Public entry point
-- -------------------------------------------------------------------------
---@param kind string -- key into Config.Dispatch.alerts
---@param rig MiningRig
---@param extra table? -- optional { securityLevel = n, chanceBonus = 0..1, by = source }
function SendPoliceAlert(kind, rig, extra)
    if not Cfg.enabled then return end
    if not rig then return end
    extra = extra or {}

    local def = Cfg.alerts and Cfg.alerts[kind]
    if not def or not def.enabled then return end

    -- A hardened rig (higher security level) is louder when tampered with.
    -- Clamped to 1.0 so a high base chance + bonus just means "always", and
    -- the roll below stays a real probability.
    local chance = math.min(1.0, (def.chance or 1.0) + (extra.chanceBonus or 0))
    if math.random() > chance then return end

    local police = getOnDutyPolice()
    if #police < (Cfg.minPoliceOnline or 0) then return end

    local blip = Cfg.blip or {}
    local alert = {
        coords = rig.coords,
        title = def.title or 'Mining Rig Alert',
        message = def.message or 'Activity at a mining rig',
        code = def.code or '10-90',
        blip = {
            sprite = blip.sprite or 459,
            colour = blip.colour or 1,
            scale = blip.scale or 1.1,
            lengthSeconds = blip.lengthSeconds or 90,
        },
        policeSources = police,
    }

    local provider = resolveProvider()
    local sender = Providers[provider]
    if not sender then
        print(('^1[anxious_btcmining] unknown dispatch provider "%s" -- alert dropped^7'):format(provider))
        return
    end

    sender(alert)

    if Log then
        Log('theft', {
            title = 'Police Dispatched',
            severity = 'warn',
            description = ('%s via `%s`'):format(alert.title, provider),
            fields = {
                { name = 'Rig', value = ('#%d'):format(rig.id), inline = true },
                { name = 'Cops on duty', value = tostring(#police), inline = true },
                { name = 'Code', value = alert.code, inline = true },
            },
        })
    end
end

-- Default handler for the 'custom' provider so it isn't silently swallowed if
-- a server owner selects it but hasn't wired their own listener yet.
AddEventHandler('anxious_btcmining:dispatch:custom', function(alert)
    if resolveProvider() ~= 'custom' then return end
    print(('^3[anxious_btcmining] Config.Dispatch.provider = "custom" but no handler is wired -- alert: %s @ %s^7')
        :format(alert.title, alert.coords))
end)
