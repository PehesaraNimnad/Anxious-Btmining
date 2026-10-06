-- =========================================================================
-- server/logs.lua -- fire-and-forget Discord webhook logging  (spec §43)
-- =========================================================================
-- One global entry point, Log(category, data), used across the server files.
-- Everything is a no-op unless Config.Logs.enabled is true, a webhook is set,
-- and that specific category is switched on in Config.Logs.events -- so leaving
-- logging off costs nothing, and a server owner can log only the categories
-- they care about (e.g. exploit + theft, not every BTC sale).
--
--   Log('theft', {
--       title = 'Rig Hacked',
--       severity = 'danger',            -- info | success | warn | danger | admin
--       description = '...',
--       fields = { { name='Player', value='...', inline=true }, ... },
--   })
--
-- Never pass client-supplied strings straight into a field without sanitising
-- -- SanitiseField strips Discord markdown/mentions so a player can't inject
-- @everyone or break the embed out of a crafted character name.

local Cfg = Config.Logs or {}

---@param s any
---@return string
local function SanitiseField(s)
    s = tostring(s or '-')
    -- Neutralise mass mentions and backtick/markdown escapes.
    s = s:gsub('@everyone', '@\226\128\139everyone')
         :gsub('@here', '@\226\128\139here')
         :gsub('`', '\226\128\139`')
    if #s > 1000 then s = s:sub(1, 997) .. '...' end
    return s
end

---@param category string -- must match a key in Config.Logs.events
---@param data table
function Log(category, data)
    if not Cfg.enabled then return end
    if not Cfg.webhook or Cfg.webhook == '' then return end
    if Cfg.events and Cfg.events[category] == false then return end

    local color = (Cfg.colors and Cfg.colors[data.severity or 'info'])
        or (Cfg.colors and Cfg.colors.info) or 3447003

    local fields = {}
    if data.fields then
        for _, f in ipairs(data.fields) do
            fields[#fields + 1] = {
                name = SanitiseField(f.name),
                value = SanitiseField(f.value),
                inline = f.inline or false,
            }
        end
    end

    local embed = {
        title = SanitiseField(data.title or category),
        description = data.description and SanitiseField(data.description) or nil,
        color = color,
        fields = fields,
        footer = { text = ('%s | %s'):format(Cfg.footer or 'anxious_btcmining', category) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }

    local body = json.encode({
        username = Cfg.botName or 'P7H Crypto',
        avatar_url = (Cfg.botAvatar ~= '' and Cfg.botAvatar) or nil,
        embeds = { embed },
    })

    PerformHttpRequest(Cfg.webhook, function(status)
        -- Discord returns 204 on success; anything else is logged once to the
        -- server console rather than retried, so a bad webhook can't spam.
        if status ~= 200 and status ~= 204 then
            print(('^3[anxious_btcmining] Discord log webhook returned HTTP %s^7'):format(status))
        end
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end
