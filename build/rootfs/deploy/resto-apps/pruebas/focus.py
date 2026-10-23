import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
desk = Atspi.get_desktop(0)
def walk(o, depth, path):
    try:
        st = o.get_state_set()
        role = o.get_role_name(); name = o.get_name()
    except Exception:
        return
    if st.contains(Atspi.StateType.FOCUSED) or (role in ("text","entry","password text","search bar") ):
        print(depth, path + "/" + role, repr(name), "FOCUSED" if st.contains(Atspi.StateType.FOCUSED) else "", "showing" if st.contains(Atspi.StateType.SHOWING) else "hidden", "editable" if st.contains(Atspi.StateType.EDITABLE) else "")
    if depth > 30: return
    for i in range(o.get_child_count()):
        c = o.get_child_at_index(i)
        if c: walk(c, depth+1, path + "/" + role)
for i in range(desk.get_child_count()):
    a = desk.get_child_at_index(i)
    if a and "omikku" in (a.get_name() or ""):
        walk(a, 0, a.get_name())
