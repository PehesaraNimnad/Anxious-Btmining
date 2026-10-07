-- =========================================================================
-- client/screen.lua -- the live "monitor" that floats on a rig up close
-- =========================================================================
-- Renders a small screen on each nearby rig prop showing its real server state
-- (status, hashrate, power, temperature, usage), the way a rig-monitoring
-- display would. It reflects shared server state, so everyone looking at the
-- same rig sees the same numbers.
--
-- Two cadences:
--   * a per-frame loop projects each nearby prop to 2D (World3dToScreen2d) and
--     tells the NUI where to draw its panel and how big (scaled by distance);
--   * a slow loop refreshes the live numbers from the server every couple of
--     seconds (server/display.lua), so the per-frame message stays tiny.
-- The panels are passive overlays -- no NUI focus is ever taken, so they never
-- block input or the crosshair.

local Screen = Config.Screen or {}

-- Which rig props are currently within screen range, with their live entities.
local function nearbyRigEntries(pedCoords)
    local list = {}
    for id, entry in pairs(RigProps) do
        if entry.entity and DoesEntityExist(entry.entity) then
            local dist = #(pedCoords - GetEntityCoords(entry.entity))
            if dist <= (Screen.range or 9.0) then
                list[#list + 1] = { id = id, entity = entry.entity, dist = dist }
            end
        end
    end
    return list
end

-- Per-frame: project each nearby prop to screen space and push positions.
CreateThread(function()
    while true do
        if not Screen.enabled then
            Wait(2000)
        else
            -- While the full dashboard is open it owns the screen -- don't
            -- clutter it with floating panels.
            if DashboardOpen then
                SendNUIMessage({ action = 'rigScreenFrame', data = {} })
                Wait(400)
            else
                local pedCoords = GetEntityCoords(cache.ped)
                local near = nearbyRigEntries(pedCoords)

                local frame = {}
                for _, e in ipairs(near) do
                    local ec = GetEntityCoords(e.entity)
                    local onScreen, sx, sy = World3dToScreen2d(ec.x, ec.y, ec.z + (Screen.heightOffset or 0.45))
                    if onScreen then
                        -- Closer = bigger. Clamped so it never gets tiny or huge.
                        local t = math.min(1.0, e.dist / (Screen.range or 9.0))
                        local scale = math.max(0.5, 1.15 - t * 0.6)
                        frame[#frame + 1] = { id = e.id, x = sx, y = sy, scale = scale }
                    end
                end

                SendNUIMessage({ action = 'rigScreenFrame', data = frame })

                -- Spin fast only while something is actually on screen; back off
                -- otherwise so an idle player isn't paying for a 60fps loop.
                if #frame > 0 then
                    Wait(0)
                elseif #near > 0 then
                    Wait(150)
                else
                    Wait(500)
                end
            end
        end
    end
end)

-- Slow: refresh live numbers from the server for the rigs in range.
CreateThread(function()
    while true do
        Wait(Screen.statsIntervalMs or 2000)
        if Screen.enabled and not DashboardOpen then
            local pedCoords = GetEntityCoords(cache.ped)
            local near = nearbyRigEntries(pedCoords)
            if #near > 0 then
                local ids = {}
                for _, e in ipairs(near) do ids[#ids + 1] = e.id end

                local stats = lib.callback.await('anxious_btcmining:server:getRigDisplays', false, ids)
                SendNUIMessage({ action = 'rigScreenStats', data = stats or {} })
            end
        end
    end
end)
