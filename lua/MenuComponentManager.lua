-- The authoritative teardown path: close_raid_ready_up_gui() is what drops
-- _raid_ready_up_gui and calls close() on it. Hooking it as well means the
-- lobby is handed back to the game even if ReadyUpGui:close() is ever bypassed.

Hooks:PostHook(MenuComponentManager, "close_raid_ready_up_gui", "ReadyUpLockFix_close_raid_ready_up_gui", function(self)
    ReadyUpLockFix:clear_gui()
end)
