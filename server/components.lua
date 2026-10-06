-- =========================================================================
-- server/components.lua -- rig assembly (install/remove build components)
-- =========================================================================
-- A placed rig is an empty shell; the owner assembles it one part at a time
-- (motherboard, CPU, RAM, PSU, optional cooling), each via its own minigame on
-- the Assembly tab. The minigame itself is resolved client-side (installing a
-- part you own into a rig you own is not an economy exploit) but the SERVER
-- owns every consequence: ownership, proximity, rate, item consumption, slot
-- state and the dependency order (a board before anything mounts on it).

---@param source number
---@param rig MiningRig?
local function hasAccess(source, rig)
    if not rig then return false end
    return HasRigAccess(rig, GetCitizenId(source))
end

-- itemName -> category, tierKey, def. Lets the server trust the item in the
-- player's inventory over the category/tier the client claims.
---@param itemName string
---@return string? category, string? tierKey, table? def
local function componentByItem(itemName)
    for category, cat in pairs(Config.Components) do
        for tierKey, def in pairs(cat.tiers) do
            if def.item == itemName then
                return category, tierKey, def
            end
        end
    end
    return nil
end

-- Mounting dependency: everything except the motherboard itself needs a board
-- already installed to mount onto. PSU is wired to the board too, so it's
-- gated the same way -- only the motherboard has no prerequisite.
---@param rig MiningRig
---@param category string
---@return boolean ok, string? reason
local function dependencyMet(rig, category)
    if category == 'motherboard' then return true end
    local mb = rig.components and rig.components.motherboard
    if not mb or not mb.key then
        return false, 'Install a motherboard first'
    end
    return true
end

-- The player's build components sitting in inventory, grouped for the Assembly
-- tab's install picker. Counts only -- these items are stackable and carry no
-- metadata (unlike GPUs).
---@param source number
lib.callback.register('anxious_btcmining:server:getMyComponents', function(source)
    local out = {}
    for category, cat in pairs(Config.Components) do
        for tierKey, def in pairs(cat.tiers) do
            local count = exports.ox_inventory:Search(source, 'count', def.item) or 0
            if count > 0 then
                out[#out + 1] = {
                    category = category,
                    key = tierKey,
                    label = def.label,
                    item = def.item,
                    count = count,
                }
            end
        end
    end
    return out
end)

---@param source number
---@param rigId integer
---@param category string
---@param tierKey string
lib.callback.register('anxious_btcmining:server:installComponent', function(source, rigId, category, tierKey)
    local rig = GetRig(rigId)
    if not hasAccess(source, rig) then return false end
    if not GuardRigAction(source, rig, 'installComponent') then return false end

    -- Legacy rigs (placed before the assembly system) are grandfathered as
    -- already-built and don't take parts -- nothing to assemble.
    if not rig.components then
        return false, 'This rig predates the assembly system'
    end

    local cat = Config.Components[category]
    if not cat then
        FlagExploit(source, 'bad-args', ('installComponent category=%s'):format(tostring(category)))
        return false
    end

    local def = cat.tiers[tierKey]
    if not def then
        FlagExploit(source, 'bad-args', ('installComponent tier=%s'):format(tostring(tierKey)))
        return false
    end

    if rig.components[category] and rig.components[category].key then
        return false, ('%s slot is already filled'):format(cat.label)
    end

    local depOk, depReason = dependencyMet(rig, category)
    if not depOk then return false, depReason end

    -- Must actually own the item -- the server removes the real item, it never
    -- trusts that the client "had" it.
    local held = exports.ox_inventory:Search(source, 'count', def.item) or 0
    if held < 1 then return false, ('You don\'t have a %s'):format(def.label) end

    local removed = exports.ox_inventory:RemoveItem(source, def.item, 1)
    if not removed then return false, 'Failed to consume the part' end

    rig.components[category] = { key = tierKey }
    MarkDirty(rigId)

    Log('hardware', {
        title = 'Component Installed',
        severity = 'info',
        fields = {
            { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
            { name = 'Rig', value = ('#%d'):format(rigId), inline = true },
            { name = 'Part', value = ('%s: %s'):format(cat.label, def.label), inline = true },
        },
    })

    return true
end)

---@param source number
---@param rigId integer
---@param category string
lib.callback.register('anxious_btcmining:server:removeComponent', function(source, rigId, category)
    local rig = GetRig(rigId)
    if not hasAccess(source, rig) then return false end
    if not GuardRigAction(source, rig, 'removeComponent') then return false end

    if not rig.components then
        return false, 'This rig predates the assembly system'
    end

    local cat = Config.Components[category]
    if not cat then
        FlagExploit(source, 'bad-args', ('removeComponent category=%s'):format(tostring(category)))
        return false
    end

    local installed = rig.components[category]
    if not installed or not installed.key then
        return false, ('%s slot is already empty'):format(cat.label)
    end

    -- Can't pull the board out from under the parts (and GPUs) mounted on it.
    if category == 'motherboard' then
        for other, otherCat in pairs(Config.Components) do
            if other ~= 'motherboard' then
                local oc = rig.components[other]
                if oc and oc.key then
                    return false, ('Remove the %s first'):format(otherCat.label)
                end
            end
        end
        for _, slot in ipairs(rig.slots) do
            if slot and slot.tier then
                return false, 'Remove the GPUs first'
            end
        end
    end

    local def = cat.tiers[installed.key]
    local itemName = def and def.item
    if not itemName then
        -- Config changed under a saved rig -- clear the dangling slot rather
        -- than trapping the player, but don't mint an item that no longer exists.
        rig.components[category] = false
        MarkDirty(rigId)
        return true
    end

    local added = exports.ox_inventory:AddItem(source, itemName, 1)
    if not added then return false, 'Your inventory is full' end

    rig.components[category] = false
    MarkDirty(rigId)

    Log('hardware', {
        title = 'Component Removed',
        severity = 'info',
        fields = {
            { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(source) or '?', source), inline = true },
            { name = 'Rig', value = ('#%d'):format(rigId), inline = true },
            { name = 'Part', value = ('%s: %s'):format(cat.label, def.label), inline = true },
        },
    })

    return true
end)
