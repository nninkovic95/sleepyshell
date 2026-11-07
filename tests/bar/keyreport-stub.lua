-- The sandboxed half of bar/keyreport.test.sh: loads the shell's data/keyreport.lua against a stand-in `hl` table
-- (no Hyprland) and prints PASS or FAIL per check.
-- lua keyreport-stub.lua PATH_TO_KEYREPORT_LUA
local path = arg[1]
local fails = 0
local function check(ok, what, detail)
    print((ok and "PASS " or "FAIL ") .. what .. ((ok or not detail) and "" or (": " .. tostring(detail))))
    if not ok then fails = fails + 1 end
end

-- the stand-in: binds are kept with their handler, dispatches and events are recorded
local binds, dispatched = {}, {}
local masks = { SUPER = 64, SHIFT = 1, CTRL = 4, ALT = 8 }
hl = {
    dsp = { event = function(name) return { event = name } end },
    dispatch = function(d) dispatched[#dispatched + 1] = d end,
}
hl.bind = function(keys, dispatcher, opts)
    local mask, key = 0, keys
    for part in keys:gmatch("[^+%s]+") do
        if masks[part] then mask = mask + masks[part] else key = part end
    end
    local kb = { modmask = mask, key = key, keys = keys, handler = dispatcher, opts = opts or {} }
    binds[#binds + 1] = kb
    return kb
end
-- what pressing a bind does in Hyprland: its function runs, or its dispatcher is dispatched
local function press(kb)
    if type(kb.handler) == "function" then kb.handler() else hl.dispatch(kb.handler) end
end
local function events()
    local out = {}
    for _, d in ipairs(dispatched) do
        if type(d) == "table" and d.event then out[#out + 1] = d.event end
    end
    return out
end
local function clear() dispatched = {} end

dofile(path)
check(sleepyshell_keyreport_loaded == true, "loading it marks the reporter as loaded")
check(sleepyshell_keys_on == false, "the overlay starts off")

local term = hl.bind("SUPER + Return", "exec kitty")
local vol = hl.bind("XF86AudioRaiseVolume", "exec wpctl", { repeating = true })
press(term)
check(#events() == 0, "while the overlay is off nothing is reported", table.concat(events(), ", "))
check(dispatched[1] == "exec kitty", "the bind still does what it did", tostring(dispatched[1]))

sleepyshell_keys_on = true
clear()
press(term)
check(events()[1] == "sleepyshell:keypress:64:p:Return", "while on a fired bind is reported with its mask and key", table.concat(events(), ", "))
check(dispatched[#dispatched] == "exec kitty", "and still does what it did")
clear()
press(vol)
check(events()[1] == "sleepyshell:keypress:0:r:XF86AudioRaiseVolume", "a repeating bind is reported as r", table.concat(events(), ", "))

-- a drag bind: left alone, reported by a pass-through bind made first
local before = #binds
local drag = hl.bind("SUPER + mouse:272", "movewindow", { mouse = true })
local companion = binds[before + 1]
check(#binds == before + 2 and companion.opts.non_consuming == true and drag.opts.mouse == true and drag.handler == "movewindow",
    "a drag bind is kept as it is, after a pass-through bind on the same keys", #binds - before)
clear()
press(companion)
check(events()[1] == "sleepyshell:keypress:64:p:mouse:272", "the pass-through bind reports the drag", table.concat(events(), ", "))

-- a config reload loads the file again: the wrapper must not wrap itself
dofile(path)
local again = hl.bind("SUPER + E", "exec files")
clear()
press(again)
check(#events() == 1, "after a reload a press is reported once, not twice", #events())
check(sleepyshell_keys_on == true, "a reload keeps the overlay's state")

-- typing is not a bind: nothing the reporter makes listens to keys on its own
local count = 0
for _, kb in ipairs(binds) do if kb.keys:match("^%a$") then count = count + 1 end end
check(count == 0, "the reporter makes no bind of its own on a plain key")

sleepyshell_keys_on = false
clear()
press(term)
check(#events() == 0, "off again: nothing reported")
os.exit(fails == 0 and 0 or 1)
