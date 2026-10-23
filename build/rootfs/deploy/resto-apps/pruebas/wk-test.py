import sys, gi
gi.require_version("Gtk", "4.0"); gi.require_version("WebKit", "6.0")
from gi.repository import Gtk, GLib, WebKit
mode = sys.argv[1]
def activate(app):
    win = Gtk.ApplicationWindow(application=app, title="wk-test-" + mode)
    stack = Gtk.Stack()
    stack.add_named(Gtk.Button(label="boton visible"), "main")
    if mode != "none":
        wv = WebKit.WebView()
        wv.load_uri("about:blank")
        stack.add_named(wv, "web")      # oculto: la pagina visible es "main"
    stack.set_visible_child_name("main")
    win.set_child(stack); win.present()
    GLib.timeout_add_seconds(9, app.quit)
app = Gtk.Application(application_id="uke.wktest." + mode)
app.connect("activate", activate); app.run([])
