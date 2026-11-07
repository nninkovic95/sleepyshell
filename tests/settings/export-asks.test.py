"""Tier 1 (a user's file replaced without a yes, or an Export that silently does nothing): Keybinds > Export onto a file
that exists must ask first, in the real window: the question can only appear when the window hands its confirm dialog
to the Keybinds tab, which a script or harness test cannot see.

Drives the real Sleepysettings on the private test screen: Keybinds tab, Export…, the window's own file browser,
Select. Checks that the dialog opens and names the file, that Cancel leaves the file as it was with no backup, that
Replace writes it after one backup of the old text, and that a new name is written with no question."""
import sys
import time
from ui import Shell, check, done, RUN

HOME = RUN / "home"
target = HOME / "my-keybinds.lua"
target.write_text("mine\n")
backups = lambda name: sorted(p.name for p in HOME.iterdir() if p.name.startswith(name + ".bak-"))

s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.click(text="Keybinds")
check(s.wait(lambda: s.js("win.tab") == "keybinds"), "the Keybinds tab opens from the sidebar")


def export_to_default_name():
    s.click(objectName="exportButton")
    ok = s.wait_visible(objectName="browserTitle", text="Save keybinds as")
    if ok:
        field = s.one(objectName="browserFileName")
        check(field.get("text", "") in ("my-keybinds.lua", ""), "the browser offers the default name", field.get("text"))
        s.click(objectName="browserPick")
    return ok


check(export_to_default_name(), "Export… opens the window's file browser")
asked = s.wait_visible(contains="Replace my-keybinds.lua?")
check(asked, "exporting onto an existing file opens the question")
check(s.visible(text="~/my-keybinds.lua"), "the question names the file's path")
if not asked:
    done()
check(target.read_text() == "mine\n", "nothing is written while the question is open")

s.click(type="BarButton", text="Cancel")
check(s.wait_gone(contains="Replace my-keybinds.lua?"), "Cancel closes the question")
time.sleep(1)
check(target.read_text() == "mine\n" and not backups("my-keybinds.lua"), "after Cancel the file is unchanged and no backup exists",
      f"{target.read_text()!r}, {backups('my-keybinds.lua')}")

export_to_default_name()
check(s.wait_visible(contains="Replace my-keybinds.lua?"), "a second export asks again")
s.click(type="BarButton", text="Replace")
written = s.wait(lambda: target.read_text() != "mine\n")
b = backups("my-keybinds.lua")
check(written and "hl.bind" in target.read_text() or (written and target.read_text().startswith("--")),
      "Replace writes the keybinds into the file", target.read_text()[:120])
check(len(b) == 1 and (HOME / b[0]).read_text() == "mine\n", "one backup holds the old text", f"{b}")
check(s.wait_visible(objectName="exportMessage") and not s.js("Keybinds.exportFailed"), "the tab reports the export",
      s.js("Keybinds.exportMessage"))

s.click(objectName="exportButton")
s.wait_visible(objectName="browserTitle", text="Save keybinds as")
s.click(objectName="browserFileName")
s.click(objectName="browserFileName")
from ui import Input
Input.key("ctrl", "a")
Input.type("fresh.lua")
s.wait(lambda: s.one(objectName="browserFileName").get("text") == "fresh.lua", 3)
s.click(objectName="browserPick")
fresh = HOME / "fresh.lua"
check(s.wait(lambda: fresh.exists()), "a new name is written", str(fresh))
check(not s.visible(contains="Replace fresh.lua?") and not backups("fresh.lua"), "a new name gets no question and no backup")

check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
