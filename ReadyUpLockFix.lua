ReadyUpLockFix = ReadyUpLockFix or {}

if not ReadyUpLockFix.setup then
    ReadyUpLockFix.setup = true

    -- Close the lobby while the ready up screen is open.
    --
    -- ReadyUpGui builds its peer list (_layout_player_list) and the character
    -- visuals (_spawn_character_units) exactly once, when the screen opens, and
    -- only listens for PLAYER_KICKED / PLAYER_LEFT - there is no join handler.
    -- The host meanwhile re-opens the lobby in _layout_buttons by switching the
    -- session state to "in_game" (HostStateInGame:is_joinable() returns true),
    -- so anyone can drop into a screen that cannot represent them.
    ReadyUpLockFix.CLOSE_LOBBY_IN_READY_UP = true

    -- The currently open ReadyUpGui, set from its init/close hooks.
    ReadyUpLockFix.gui = nil

    function ReadyUpLockFix:log(msg)
        log("[ReadyUpLockFix] " .. tostring(msg))
    end

    -- Only logs when the value for that key actually changed, so callers that
    -- run every frame (update, _are_peer_visuals_assembled) stay quiet.
    -- msg = nil setzt den Zustand nur zurueck, ohne etwas zu loggen, damit ein
    -- spaeter wieder auftretender Fall erneut gemeldet wird.
    function ReadyUpLockFix:log_once(key, msg)
        self._last_logged = self._last_logged or {}

        if self._last_logged[key] == msg then
            return false
        end

        self._last_logged[key] = msg

        if msg == nil then
            return false
        end

        self:log(msg)

        return true
    end

    function ReadyUpLockFix:count(what)
        self.stats = self.stats or {}
        self.stats[what] = (self.stats[what] or 0) + 1
    end

    function ReadyUpLockFix:peer_str(peer)
        if not peer then
            return "<nil>"
        end

        local ok_name, name = pcall(function() return peer:name() end)
        local ok_id, id = pcall(function() return peer:id() end)

        return string.format("%s(id=%s)",
            ok_name and tostring(name) or "?",
            ok_id and tostring(id) or "?")
    end

    function ReadyUpLockFix:peer_count()
        local session = managers.network and managers.network:session()

        if not session then
            return "?"
        end

        local n = 0

        for _ in pairs(session:all_peers()) do
            n = n + 1
        end

        return tostring(n)
    end

    function ReadyUpLockFix:set_gui(gui)
        self.gui = gui
        self.stats = {}
        self._last_logged = {}
        self:log(string.format("ready up screen opened (server=%s, peers=%s, close_lobby=%s)",
            tostring(Network:is_server()), self:peer_count(), tostring(self.CLOSE_LOBBY_IN_READY_UP)))
        self:refresh_joinable()
    end

    -- Pass the gui to only clear that one, or nothing to clear unconditionally.
    function ReadyUpLockFix:clear_gui(gui)
        if not self.gui or (gui and self.gui ~= gui) then
            return
        end

        self.gui = nil
        self:log_summary()
        self:refresh_joinable()
    end

    -- What did the fix actually have to do while the screen was open? Anything
    -- other than all-zero means the unpatched game would have been stuck here.
    function ReadyUpLockFix:log_summary()
        local stats = self.stats or {}
        local order = {
            "lobby_kept_closed",
            "stale_gui_cleared",
            "orphan_visuals_dropped",
            "peer_removed",
            "spawn_weapon_dropped",
            "assemble_dropped",
            "cards_override",
            "leave_button_restored",
        }
        local parts = {}
        local any = false

        for _, key in ipairs(order) do
            if stats[key] then
                table.insert(parts, string.format("%s=%d", key, stats[key]))
                any = true
            end
        end

        if any then
            self:log("ready up screen closed, fix was active: " .. table.concat(parts, " "))
        else
            self:log("ready up screen closed, nothing to fix")
        end

        self.stats = {}
        self._last_logged = {}
    end

    function ReadyUpLockFix:in_ready_up()
        if not self.CLOSE_LOBBY_IN_READY_UP or not self.gui then
            return false
        end

        -- Never let a stale flag keep the lobby shut: if the screen went away
        -- without close() running, MenuComponentManager has already dropped it.
        if managers.menu_component and managers.menu_component._raid_ready_up_gui ~= self.gui then
            self:log("stale gui reference dropped - close() never ran, releasing the lobby")
            self:count("stale_gui_cleared")
            self.gui = nil

            return false
        end

        return true
    end

    function ReadyUpLockFix:refresh_joinable()
        if not Network:is_server() then
            return
        end

        local session = managers.network and managers.network:session()

        if session and session.chk_server_joinable_state then
            self:log("re-checking joinable state (in_ready_up=" .. tostring(self:in_ready_up()) .. ")")
            session:chk_server_joinable_state()
        else
            self:log("no session yet, joinable state unchanged")
        end
    end

    function ReadyUpLockFix:peer_in_session(peer)
        if not peer then
            return false
        end

        local session = managers.network and managers.network:session()

        if not session then
            return false
        end

        for _, session_peer in pairs(session:all_peers()) do
            if session_peer == peer then
                return true
            end
        end

        return false
    end

    -- peer_index -> true for every peer the open ReadyUpGui actually knows
    -- about, or nil when there is no usable list to go by.
    function ReadyUpLockFix:known_peer_indices()
        local gui = self.gui

        if not gui or not gui._player_control_list then
            return nil
        end

        local indices = {}
        local any = false

        for _, control in pairs(gui._player_control_list) do
            local params = control.params and control:params()

            if params and params.peer_index then
                indices[params.peer_index] = true
                any = true
            end
        end

        return any and indices or nil
    end
end
