#!/usr/bin/env python3
"""osk-entry.py — ventana GTK4 de prueba con un solo campo de texto (clase uke.oskprueba).
Escribe el contenido del campo en /tmp/osk-entry.txt en cada cambio, para que las pruebas lean el texto REAL sin
portapapeles ni borradores de otras apps. Uso: osk-entry.py [fichero] | osk-entry.py --sin-campo (clase uke.osksincampo:
una ventana con solo un boton, para medir que el teclado se oculta)"""
import sys
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

SIN = len(sys.argv) > 1 and sys.argv[1] == "--sin-campo"
OUT = sys.argv[1] if len(sys.argv) > 1 and not SIN else "/tmp/osk-entry.txt"


def activate(app):
    if SIN:
        win = Gtk.ApplicationWindow(application=app, title="osk-sin-campo")
        win.set_child(Gtk.Button(label="sin campo de texto"))
        win.present()
        return
    win = Gtk.ApplicationWindow(application=app, title="osk-prueba")
    entry = Gtk.Entry(hexpand=True, margin_top=40, margin_start=40, margin_end=40)
    entry.connect("changed", lambda e: open(OUT, "w").write(e.get_text()))
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.append(entry)
    win.set_child(box)
    win.present()
    entry.grab_focus()


if not SIN:
    open(OUT, "w").close()
app = Gtk.Application(application_id="uke.osksincampo" if SIN else "uke.oskprueba")
app.connect("activate", activate)
app.run([])
