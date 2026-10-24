-- Track the open screen, so the lobby can be closed for as long as it is up.

Hooks:PostHook(ReadyUpGui, "init", "ReadyUpLockFix_init", function(self)
    ReadyUpLockFix:set_gui(self)
end)

Hooks:PostHook(ReadyUpGui, "close", "ReadyUpLockFix_close", function(self)
    ReadyUpLockFix:clear_gui(self)
end)

-- Original leaks _weapon_assembled[peer] and indexes three tables without a
-- nil check: the control is missing for anyone who joined after the layout ran,
-- and the weapon tables are missing while the async assembly is still going.
function ReadyUpGui:_peer_no_longer_in_lobby(peer, state)
    local peer_control = self._player_control_list and self._player_control_list[peer]
    local had_assembled = self._weapon_assembled and self._weapon_assembled[peer] ~= nil

    ReadyUpLockFix:log(string.format(
        "peer gone: %s state=%s control=%s weapon_assembled=%s current_peer=%s",
        ReadyUpLockFix:peer_str(peer), tostring(state),
        peer_control and "yes" or "no",
        had_assembled and tostring(self._weapon_assembled[peer]) or "none",
        tostring(peer == self._current_peer)))
    ReadyUpLockFix:count("peer_removed")

    if peer_control then
        peer_control:set_state(state)

        -- Keep the control on screen ("LEFT" / "KICKED"), but take it out of
        -- the list: its ready flag stays false and would block all_ready in
        -- _update_status forever.
        self._player_control_list[peer] = nil
    end

    if peer == self._current_peer then
        if peer_control then
            peer_control:select_off()
        end

        self._current_peer = nil
        self._current_peer_index = nil

        local local_peer = managers.network:session():local_peer()
        local local_control = self._player_control_list and self._player_control_list[local_peer]

        if peer ~= local_peer and local_control then
            local_control:on_mouse_clicked()
        end
    end

    if self._spawned_weapon_parts and self._spawned_weapon_parts[peer] then
        for _, part in ipairs(self._spawned_weapon_parts[peer]) do
            if alive(part) then
                part:set_slot(0)
            end
        end

        self._spawned_weapon_parts[peer] = nil
    end

    if self._spawned_character_units and self._spawned_character_units[peer] then
        if alive(self._spawned_character_units[peer]) then
            self._spawned_character_units[peer]:set_slot(0)
        end

        self._spawned_character_units[peer] = nil
    end

    -- The actual hardlock: left behind as false, this entry makes
    -- _are_peer_visuals_assembled() fail forever, which makes update() bail out
    -- on its first line every frame - no status update, no cleanup, no start.
    if self._weapon_assembled then
        if had_assembled and self._weapon_assembled[peer] == false then
            -- Genau dieser Eintrag haette _are_peer_visuals_assembled() dauerhaft
            -- scheitern lassen und damit update() jeden Frame abbrechen
            ReadyUpLockFix:log("  -> cleared stuck weapon_assembled=false (this was the hardlock)")
        end

        self._weapon_assembled[peer] = nil
    end
end

-- Safety net: drop entries of peers that are gone, no matter how they got lost.
local _are_peer_visuals_assembled_original = ReadyUpGui._are_peer_visuals_assembled

function ReadyUpGui:_are_peer_visuals_assembled(...)
    if self._weapon_assembled then
        for peer, _ in pairs(self._weapon_assembled) do
            if not ReadyUpLockFix:peer_in_session(peer) then
                ReadyUpLockFix:log("orphan visuals entry for peer no longer in session: " ..
                    ReadyUpLockFix:peer_str(peer))
                ReadyUpLockFix:count("orphan_visuals_dropped")
                self:_peer_no_longer_in_lobby(peer, "left")
            end
        end
    end

    return _are_peer_visuals_assembled_original(self, ...)
end

-- Both callbacks below run from dyn_resource:load / assemble_from_blueprint,
-- long after the peer may have left.
local _spawn_weapon_original = ReadyUpGui._spawn_weapon

function ReadyUpGui:_spawn_weapon(params, ...)
    if not params or not alive(params.character_unit) or not ReadyUpLockFix:peer_in_session(params.peer) then
        ReadyUpLockFix:log(string.format(
            "dropped late _spawn_weapon: peer=%s unit_alive=%s",
            params and ReadyUpLockFix:peer_str(params.peer) or "<no params>",
            tostring(params and alive(params.character_unit))))
        ReadyUpLockFix:count("spawn_weapon_dropped")

        if params and params.peer and self._weapon_assembled then
            self._weapon_assembled[params.peer] = nil
        end

        return
    end

    return _spawn_weapon_original(self, params, ...)
end

local _assemble_completed_original = ReadyUpGui._assemble_completed

function ReadyUpGui:_assemble_completed(params, parts, ...)
    if not params or not ReadyUpLockFix:peer_in_session(params.peer) then
        ReadyUpLockFix:log(string.format(
            "dropped late _assemble_completed: peer=%s parts=%d",
            params and ReadyUpLockFix:peer_str(params.peer) or "<no params>",
            parts and table.size(parts) or 0))
        ReadyUpLockFix:count("assemble_dropped")

        -- Don't park the parts under a peer that is no longer there.
        for _, part in pairs(parts or {}) do
            if part.unit and alive(part.unit) then
                part.unit:set_slot(0)
            end
        end

        if params and params.peer and self._weapon_assembled then
            self._weapon_assembled[params.peer] = nil
        end

        return
    end

    return _assemble_completed_original(self, params, parts, ...)
end

Hooks:PreHook(ReadyUpGui, "update", "ReadyUpLockFix_update", function(self, t, dt)
    if not self._player_control_list then
        return
    end

    -- In the original, _update_peers() sits behind the
    -- _are_peer_visuals_assembled() gate - it never runs in exactly the
    -- situation it is meant to clean up after.
    self:_update_peers()

    -- _show_characters() indexes _player_control_list[_current_peer] without a
    -- check, which throws once the selected peer is gone.
    if not self._player_control_list[self._current_peer] then
        local local_control = self._player_control_list[managers.network:session():local_peer()]

        if local_control then
            local_control:on_mouse_clicked()
        end
    end

    -- Last resort: while the screen cannot proceed, backing out has to work.
    -- _update_status() hides this button for good once everyone was ready, and
    -- _show_characters() only ever brings it back while not self._ready.
    if self._leave_lobby_button and not self:_are_peer_visuals_assembled() then
        -- laeuft jeden Frame: nur den Zustandswechsel zaehlen, nicht die Frames
        if ReadyUpLockFix:log_once("gate", "visuals gate is blocking - leave button forced back on") then
            ReadyUpLockFix:count("leave_button_restored")
        end
        self._leave_lobby_button:enable()

        if managers.raid_menu:is_pc_controller() then
            self._leave_lobby_button:show()
        end
    end
end)
