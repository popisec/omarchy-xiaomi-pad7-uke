-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- >>> uke-t5 (18-oct-2026): lanzador tactil residente (nwg-drawer -r); se alterna con /usr/local/bin/uke-drawer-toggle. Revertir con tablet-t5/deploy.sh revert.
o.launch_on_start("/usr/local/bin/uke-drawer-toggle start")
-- <<< uke-t5
