-- =========================================================================
-- server/config_server.lua -- SERVER-ONLY configuration
-- =========================================================================
-- These blocks live here, registered as a `server_script` in fxmanifest.lua,
-- instead of in the shared `config.lua` ON PURPOSE: config.lua is a
-- `shared_script`, so everything in it is replicated to every connected
-- client and can be read straight out of a player's game memory. A Discord
-- webhook URL, your dispatch wiring and your anti-exploit thresholds are not
-- things clients should ever see -- a leaked webhook can be spammed/deleted
-- by anyone, and exposing the exploit thresholds just tells a cheater exactly
-- how hard to push. Keeping them in a server_script means they exist only on
-- the server.
--
-- They still hang off the same global `Config` table (the shared config.lua
-- has already run by the time this server_script loads), so every server file
-- reads `Config.Security` / `Config.Dispatch` / `Config.Logs` exactly as
-- before. On the client those three keys are simply nil -- and nothing
-- client-side reads them.

-- =========================================================================
-- SECURITY / ANTI-EXPLOIT  (server/security.lua)
-- =========================================================================
-- The whole resource is server-authoritative -- the client never decides a
-- reward, balance, ownership, price or machine state, it only ever *requests*
-- an action and the server computes the result. This block tightens the two
-- things a raw callback can't infer on its own: WHERE the requester is
-- standing, and HOW OFTEN they're firing a callback. A client that calls a rig
-- action from across the map, or spams one faster than a human can click, is
-- not a legitimate UI -- it's an injected event, so we reject it and
-- (optionally) log/kick it rather than trusting it.

Config.Security = {
    -- Max distance (metres) a player may be from a rig for ANY rig-scoped
    -- action (install/remove GPU, collect, toggle power, buy GPU, manage
    -- access, hack, steal). The server measures the requester's real ped
    -- position against the rig's stored coords -- a client cannot fake this.
    maxInteractDistance = 5.0,

    -- Per-action rate limiting. A legitimate dashboard can't physically fire
    -- these faster than a human clicks; anything faster is a script.
    rateLimit = {
        enabled = true,
        default = 300, -- ms minimum between any two callbacks from one source
        actions = {    -- per-action overrides (ms), for the expensive/abusable ones
            sellBtc = 1000,
            buyGpu = 750,
            collectBtc = 1000,
            installGpu = 400,
            removeGpu = 400,
            togglePower = 600,
            grantAccess = 1000,
            requestHack = 2000,
        },
    },

    -- When a request fails a *structural* check that a real client could never
    -- trip (wrong distance, impossible slot, acting on a rig you can't see,
    -- spamming past the rate limit), treat it as a probable exploit: count it,
    -- log it (see Config.Logs.events.exploit) and optionally drop the player.
    flagExploits = true,
    kickOnExploitThreshold = false, -- set true to auto-kick repeat offenders
    exploitThreshold = 12,          -- flagged events from one source before a kick
    exploitDecayMs = 120000,        -- a source's flag counter resets after this quiet period
}

-- =========================================================================
-- POLICE / DISPATCH  (server/dispatch.lua + client/dispatch.lua)  -- spec §40/§41
-- =========================================================================
-- A framework-agnostic bridge so a data-centre/rig break-in can raise a police
-- alert on whatever dispatch resource a server already runs. 'auto' picks the
-- first provider it can detect; set it explicitly to skip detection. The
-- 'standalone' provider needs no dispatch resource at all -- it notifies every
-- on-duty officer and drops a temporary map blip via client/dispatch.lua.

Config.Dispatch = {
    enabled = true,

    -- 'auto' | 'ps-dispatch' | 'cd_dispatch' | 'qs-dispatch' | 'core_dispatch'
    --        | 'linden_outlawalert' | 'standalone' | 'custom'
    -- 'custom' fires `anxious_btcmining:dispatch:custom` (server event) with the
    -- alert table so you can route it into any bespoke system -- see the handler
    -- stub at the bottom of server/dispatch.lua.
    provider = 'auto',

    -- Job names treated as police for the standalone provider and the
    -- min-cops gate below. Framework-specific; edit to match your server.
    policeJobs = { 'police', 'bcso', 'sheriff', 'sast', 'lspd' },

    -- Require at least this many on-duty police online before any alert fires
    -- (0 = always alert). Stops break-ins being risk-free when no one can
    -- respond, without baking a specific duty system in -- see getOnDutyPolice
    -- in server/dispatch.lua if your framework tracks duty differently.
    minPoliceOnline = 1,

    -- Default blip used by the standalone provider when an alert omits its own.
    blip = { sprite = 459, colour = 1, scale = 1.1, lengthSeconds = 90 },

    -- Each break-in event can raise an alert. `chance` (0-1) gates how often it
    -- actually dispatches, so not every attempt lights up the map. A rig's
    -- security level (Config.Theft.difficulty) raises the chance -- a hardened
    -- rig is louder when touched (see server/dispatch.lua).
    alerts = {
        hackStarted = {
            enabled = false, chance = 0.25,
            code = '10-31', title = 'Suspicious Network Activity',
            message = 'Possible unauthorised access to a mining rig',
        },
        hackFailed = {
            enabled = true, chance = 0.60,
            code = '10-90', title = 'Mining Rig Intrusion Alarm',
            message = 'A failed intrusion tripped a mining rig\'s alarm',
        },
        hackSuccess = {
            enabled = true, chance = 0.40,
            code = '10-90', title = 'Crypto Theft In Progress',
            message = 'A mining rig is being drained of Bitcoin',
        },
        gpuTheft = {
            enabled = true, chance = 1.00,
            code = '10-68', title = 'Hardware Theft',
            message = 'Someone is physically stripping a mining rig',
        },
        unauthorizedAccess = {
            enabled = true, chance = 0.50,
            code = '10-31', title = 'Unauthorised Terminal Access',
            message = 'A mining terminal was opened by a non-owner',
        },
    },
}

-- =========================================================================
-- DISCORD LOGS  (server/logs.lua)  -- spec §43
-- =========================================================================
-- Fire-and-forget Discord webhook logging. Off by default (no webhook). Every
-- category can be toggled independently so you can, say, log exploit attempts
-- and theft without the noise of every BTC sale. The webhook URL stays on the
-- server (that's the whole point of this file).

Config.Logs = {
    enabled = false,
    webhook = '', -- paste a Discord channel webhook URL here to turn logging on
    botName = 'P7H Crypto',
    botAvatar = '',
    footer = 'anxious_btcmining',

    -- Per-category on/off. Categories map to the Log(category, ...) calls
    -- sprinkled through the server files.
    events = {
        mining = false,     -- collect / sell / market payouts
        hardware = true,    -- GPU install / remove / purchase / destruction
        theft = true,       -- hack attempts, GPU theft, crypto theft
        access = true,      -- grant / revoke shared access
        admin = true,       -- every /btc* admin command
        exploit = true,     -- anti-exploit flags from server/security.lua
        power = false,      -- power billing shut-downs, fires
    },

    -- Embed colours (decimal) per severity -- used by server/logs.lua.
    colors = {
        info = 3447003,     -- blue
        success = 3066993,  -- green
        warn = 15844367,    -- amber
        danger = 15158332,  -- red
        admin = 10181046,   -- purple
    },
}
