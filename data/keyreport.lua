-- keyreport.lua: lets Sleepy Shell's keybind overlay name the keybinds used, without reading any input.
--
-- Loaded by one line near the top of hyprland.lua, before the binds (Sleepysettings offers to add it and asks first):
--     pcall(dofile, os.getenv("HOME") .. "/.config/quickshell/sleepyshell/data/keyreport.lua")
-- (pcall: without this file Hyprland starts as before.)
--
-- Every keyboard bind made after it reports itself, when it fires, as the custom event
-- "sleepyshell:keypress:<modmask>:<r|p>:<key>" (r: a repeating bind, which fires again while held; p: a plain one),
-- then does what it always did. Only binds that fire are reported, never typing, and only while the overlay is on: the
-- shell sets sleepyshell_keys_on through `hyprctl eval` and clears it when the overlay goes off. Drag and resize binds
-- are left exactly as they are and reported by a pass-through bind on the same keys. The click circles make their own
-- binds with the unwrapped hl.bind, so a click is never reported here.

if sleepyshell_bind_original == nil then
    -- kept across a config reload, so the wrapper never wraps itself
    sleepyshell_bind_original = hl.bind
end
sleepyshell_keys_on = sleepyshell_keys_on or false
-- the shell asks for this when the overlay goes on: no answer means Hyprland does not load this file
sleepyshell_keyreport_loaded = true

local bind = sleepyshell_bind_original

local function report(kb, kind)
    if sleepyshell_keys_on and kb then
        hl.dispatch(hl.dsp.event("sleepyshell:keypress:" .. tostring(kb.modmask) .. ":" .. kind .. ":" .. tostring(kb.key)))
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
