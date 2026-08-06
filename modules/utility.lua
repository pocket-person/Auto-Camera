local addonName, T = ...

function T.deepCopy(tree)
    if not tree then return nil
    elseif type(tree) == "table" then
        local branch = {}
        
        for key, value in pairs(tree) do
            branch[key] = T.deepCopy(value)
        end
        
        return branch
    else
        return tree
    end
end

function T.assign(target, source)
    table.foreach(source, function(key, value)
        target[key] = value
    end)
end

function T.set(list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end

function T.merge(target, source, prune)
    if (prune == nil) then prune = false end
    for key, value in pairs(source) do
        if (not prune or target[key] ~= nil) then
            target[key] = value
        end
    end
    return target
end

function T.deepMerge(target, source, prune)
    if (prune == nil) then prune = false end
    for key, value in pairs(source) do
        if (not prune or target[key] ~= nil) then
            if (type(value) == "table") then
                target[key] = T.deepMerge(target[key] or {}, value)
            else
                target[key] = value
            end
        end
    end
    return target
end

function T.camelCase(str)
    return str:gsub("^.", string.lower):gsub(" ", "")
end

function T.splitCamelCase(str)
	return str:gsub("%u", " %1")
end

function T.capitalize(str)
    return str:gsub("^%l", string.upper)
end

function T.unCapitalize(str)
    return str:gsub("^%u", string.lower)
end

function T.getOrderOfMagnitude(value)
    return 10^math.floor(math.log(value) / math.log(10))
end

-- join elements of a table as a string
function T.joinTable(tbl, glue)
    glue = glue or ""

    local str = ""

    for key, value in pairs(tbl) do
        str = str .. (str ~= "" and glue or "") .. value
    end

    return str
end

-- Builds a WoW binding key string for the current modifier state + a base key.
-- Matches the format returned by GetBindingKey() (SHIFT > CTRL > ALT prefix order).
function T.buildModifiedKey(baseKey)
    local key = baseKey
    if IsShiftKeyDown() then key = "SHIFT-" .. key end
    if IsControlKeyDown() then key = "CTRL-" .. key end
    if IsAltKeyDown() then key = "ALT-" .. key end
    return key
end

function T.isScrollKey(key)
    return key ~= nil and (key:find("MOUSEWHEELUP", 1, true) ~= nil or key:find("MOUSEWHEELDOWN", 1, true) ~= nil)
end

-- recursively print a table
function T.printTable(tbl, depth)
    local depth = depth or 0;
    
    for key, value in pairs(tbl) do
        local indent = ""

        for i = 0, depth do
            indent = indent .. "  "
        end
        
        if (type(value) == 'table') then
            print(indent .. key .. ': {')
            T.printTable(value, depth + 1)
            print(indent .. '}')
        elseif (type(value) == 'string') then
            print (indent .. key .. ': ' .. value)
        else
            print (indent .. key .. ': ' .. type(value))
        end
    end
end
