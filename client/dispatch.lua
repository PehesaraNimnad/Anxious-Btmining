-- =========================================================================
-- client/dispatch.lua -- temporary map blip for the standalone dispatch provider
-- =========================================================================
-- Only used when Config.Dispatch.provider resolves to 'standalone' (no real
-- dispatch resource installed). A real dispatch resource draws its own blip,
-- so the server only ever sends this event to the standalone path.
--
-- The blip is created at a slightly randomised point near the real coords so
-- responding officers get a search *area* rather than a pixel-perfect marker,
-- and it auto-cleans after lengthSeconds so stale alerts don't pile up.

RegisterNetEvent('anxious_btcmining:client:dispatchBlip', function(data)
    if not data or not data.coords then return end

    local jitter = 40.0
    local x = data.coords.x + (math.random() * 2 - 1) * jitter
    local y = data.coords.y + (math.random() * 2 - 1) * jitter

    -- Radius blip (the search area) + a coord blip (the icon) layered together.
    local area = AddBlipForRadius(x, y, data.coords.z, jitter + 20.0)
    SetBlipHighDetail(area, true)
    SetBlipColour(area, data.colour or 1)
    SetBlipAlpha(area, 128)

    local icon = AddBlipForCoord(x, y, data.coords.z)
    SetBlipSprite(icon, data.sprite or 459)
    SetBlipColour(icon, data.colour or 1)
    SetBlipScale(icon, data.scale or 1.1)
    SetBlipAsShortRange(icon, false)
    SetBlipFlashes(icon, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.label or 'Mining Rig Alert')
    EndTextCommandSetBlipName(icon)

    local life = (data.lengthSeconds or 90) * 1000
    SetTimeout(life, function()
        if DoesBlipExist(icon) then RemoveBlip(icon) end
        if DoesBlipExist(area) then RemoveBlip(area) end
    end)
end)
