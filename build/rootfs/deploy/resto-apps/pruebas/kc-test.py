#!/usr/bin/python3 -I
# Prueba minima: ¿una GtkSearchBar oculta con key-capture-widget = ventana activa el input method (y el OSK)?
# uso: kc-test.py on|off   (on = como Komikku library/__init__.py:101)
import sys
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib

mode = sys.argv[1] if len(sys.argv) > 1 else "on"


def activate(app):
    win = Gtk.ApplicationWindow(application=app, title="kc-test-" + mode)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    bar = Gtk.SearchBar()
    entry = Gtk.SearchEntry()
    bar.set_child(entry)
    bar.connect_entry(entry)
    if mode == "on":
        bar.set_key_capture_widget(win)
    box.append(bar)
    b = Gtk.Button(label="Añadir")
    box.append(b)
    GLib.idle_add(b.grab_focus)
    win.set_child(box)
    win.present()
    GLib.timeout_add_seconds(8, app.quit)


app = Gtk.Application(application_id="uke.kctest." + mode)
app.connect("activate", activate)
app.run([])
