local addonName, T = ...

function T.createSettingsResetManager(onChange)
    local snapshots = {}
    local manager = {}

    function manager:invalidate(keys)
        for scope, snapshot in pairs(snapshots) do
            for _, key in ipairs(keys) do
                for savedKey in pairs(snapshot.keys) do
                    if savedKey == key or
                        (key == "models" and savedKey:sub(1, 6) == "model:") or
                        (savedKey == "models" and key:sub(1, 6) == "model:") then
                        snapshots[scope] = nil
                        break
                    end
                end
            end
        end
    end

    function manager:canUndo(scope)
        return snapshots[scope] ~= nil
    end

    function manager:toggle(scope, entries)
        local snapshot = snapshots[scope]
        local keys = {}
        for _, entry in ipairs(entries) do keys[#keys + 1] = entry.key end
        self:invalidate(keys)

        self.applying = true
        if snapshot then
            for _, saved in ipairs(snapshot.values) do
                saved.entry.set(T.deepCopy(saved.value))
            end
        else
            snapshot = {keys = {}, values = {}}
            for _, entry in ipairs(entries) do
                snapshot.keys[entry.key] = true
                snapshot.values[#snapshot.values + 1] = {
                    entry = entry,
                    value = T.deepCopy(entry.get())
                }
            end
            for _, entry in ipairs(entries) do entry.reset() end
            snapshots[scope] = snapshot
        end
        self.applying = false
        onChange()
    end

    return manager
end
