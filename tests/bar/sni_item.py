"""A stand-in tray app for the image tests: one StatusNotifierItem on the session bus, with the icon fields given.

sni_item.py ID ICON_NAME ICON_THEME_PATH
Owns org.kde.StatusNotifierItem-<pid>-1, serves /StatusNotifierItem (no menu), registers with the tray's watcher
(retried until the watcher is there, 15 s at most), then runs until killed. ICON_THEME_PATH may be "". Uses the
system's python-gobject (gi), no other package.
"""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

ITEM_ID, ICON_NAME, THEME_PATH = sys.argv[1], sys.argv[2], sys.argv[3]
NAME = f"org.kde.StatusNotifierItem-{os.getpid()}-1"

XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg name="status" type="s"/></signal>
  </interface>
</node>
"""

PROPS = {
    "Category": GLib.Variant("s", "ApplicationStatus"),
    "Id": GLib.Variant("s", ITEM_ID),
    "Title": GLib.Variant("s", ITEM_ID),
    "Status": GLib.Variant("s", "Active"),
    "IconName": GLib.Variant("s", ICON_NAME),
    "IconThemePath": GLib.Variant("s", THEME_PATH),
    "IconPixmap": GLib.Variant("a(iiay)", []),
    "OverlayIconName": GLib.Variant("s", ""),
    "OverlayIconPixmap": GLib.Variant("a(iiay)", []),
    "AttentionIconName": GLib.Variant("s", ""),
    "AttentionIconPixmap": GLib.Variant("a(iiay)", []),
    "ItemIsMenu": GLib.Variant("b", False),
    "Menu": GLib.Variant("o", "/NO_DBUSMENU"),
}


def on_call(conn, sender, path, iface, method, params, invocation):
    invocation.return_value(None)


def on_get(conn, sender, path, iface, prop):
    return PROPS.get(prop)


loop = GLib.MainLoop()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
node = Gio.DBusNodeInfo.new_for_xml(XML)
bus.register_object("/StatusNotifierItem", node.interfaces[0], on_call, on_get, None)
Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE, None, None)

tries = [0]


def register():
    try:
        bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                      "RegisterStatusNotifierItem", GLib.Variant("(s)", (NAME,)), None, Gio.DBusCallFlags.NONE, 2000, None)
        print(f"sni: {ITEM_ID} registered as {NAME}", flush=True)
        return False
    except GLib.Error as exc:
        tries[0] += 1
        if tries[0] > 30:
            print(f"sni: {ITEM_ID} could not register: {exc.message}", flush=True)
            loop.quit()
            return False
        return True


GLib.timeout_add(500, register)
loop.run()
