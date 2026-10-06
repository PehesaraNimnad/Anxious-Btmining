---@param rigId integer
function StartHack(rigId)
    local ok, difficultyOrReason = lib.callback.await('anxious_btcmining:server:requestHack', false, rigId)
    if not ok then
        if difficultyOrReason then
            lib.notify({ type = 'error', description = difficultyOrReason })
        end
        return
    end

    -- The server generated and kept the real sequence; the minigame just
    -- displays it and reports back the cells the player actually clicked. The
    -- server re-checks those clicks -- the client's own idea of success is only
    -- used for the local notification feel, never trusted for the outcome.
    local _, input = RunMinigame('hack', difficultyOrReason)

    local ok = lib.callback.await('anxious_btcmining:server:submitHack', false, rigId, input or {})

    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'You got into the rig' or 'The hack failed',
    })
end

---@param rigId integer
function StealGpu(rigId)
    if lib.progressCircle({
        duration = Config.Theft.gpuTheftDurationMs,
        label = 'Removing GPU...',
        canCancel = true,
        disable = { move = true, combat = true },
    }) then
        local ok = lib.callback.await('anxious_btcmining:server:stealGpu', false, rigId)
        lib.notify({
            type = ok and 'success' or 'error',
            description = ok and 'GPU removed' or 'Failed to remove a GPU',
        })
    end
end
