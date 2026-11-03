-- showoff.lua: lets the showoff overlay name the shortcuts used in a demo without reading any input.
--
-- Loaded by one line near the top of hyprland.lua, before the binds:
--     pcall(dofile, os.getenv("HOME") .. "/.config/quickshell/showoff/showoff.lua")
-- (pcall: without this file Hyprland starts as before.)
--
-- Every keyboard bind made after it first reports itself as the custom event "showoff:bind:<modmask>:<r|p>:<key>"
-- (r: a repeating bind, which fires again while held; p: a plain one) and then
-- does what it always did. Only binds that fire are reported, never typing, and only while the overlay is on: it
-- sets showoff_keys_on through `hyprctl eval` and clears it when it goes off. Drag and resize binds are left exactly
-- as they are and reported by a pass-through bind on the same keys. The plain-click rings use their own pass-through
-- binds, which the overlay adds and removes.

if showoff_bind_original == nil then
    -- kept across a config reload, so the wrapper never wraps itself
    showoff_bind_original = hl.bind
end
showoff_keys_on = showoff_keys_on or false

local bind = showoff_bind_original

local function report(kb, kind)
    -- a plain click is shown by the overlay's own click binds; reported here too it would show twice
    if kb and kb.modmask == 0 and tostring(kb.key):find("^mouse:%d") then
        return
    end
    if showoff_keys_on and kb then
        hl.dispatch(hl.dsp.event("showoff:bind:" .. tostring(kb.modmask) .. ":" .. kind .. ":" .. tostring(kb.key)))
    end
end

hl.bind = function(keys, dispatcher, opts)
    if opts and (opts.mouse or opts.drag) then
        -- a drag or resize action is never wrapped. A pass-through bind on the same keys reports it instead; it
        -- must be made first: made after, the drag takes the press and it never fires
        local companion
        companion = bind(keys, function() report(companion, "p") end, { non_consuming = true })
        return bind(keys, dispatcher, opts)
    end
    local kb
    local kind = (opts and opts.repeating) and "r" or "p"
    local function fire(...)
        report(kb, kind)
        if type(dispatcher) == "function" then
            return dispatcher(...)
        end
        return hl.dispatch(dispatcher)
    end
    kb = bind(keys, fire, opts)
    return kb
end
