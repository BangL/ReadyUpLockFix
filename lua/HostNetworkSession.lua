-- ReadyUpGui:_layout_buttons() puts the session into "in_game" and re-checks
-- the joinable state. HostStateInGame:is_joinable() returns true, so the lobby
-- is wide open for the whole ready up screen.

local chk_server_joinable_state_original = HostNetworkSession.chk_server_joinable_state

function HostNetworkSession:chk_server_joinable_state(...)
    if ReadyUpLockFix:in_ready_up() then
        -- Dies ist der eigentliche Eingriff: ohne ihn waere die Lobby offen
        ReadyUpLockFix:log_once("lobby", "lobby kept CLOSED while ready up screen is open")
        ReadyUpLockFix:count("lobby_kept_closed")
        managers.network.matchmake:set_server_joinable(false)

        return
    end

    ReadyUpLockFix:log_once("lobby", "joinable state handed back to the game")

    return chk_server_joinable_state_original(self, ...)
end
