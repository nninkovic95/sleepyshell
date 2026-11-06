-- Test fixture: a few binds for the Keybinds window and tab.
local app = require("modules.programs")
hl.bind("SUPER + Return", hl.dsp.exec_cmd(app.terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(app.fileManager))
hl.bind("SUPER + Q", hl.dsp.window.close())
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
end
