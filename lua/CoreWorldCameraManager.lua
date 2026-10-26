-- Menu cameras (stay_active) remember the game state they have to return to,
-- _suspended_game_state_name, and hand it back on stop_sequences. When a menu
-- is closed and reopened right away (the ReadyUpGui does that when a peer
-- leaves), the state is still "world_camera" at the second open, which then
-- becomes the state to return to: the next close switches from world_camera
-- to world_camera and the game stays there, the controls dead.

local FALLBACK_STATE = "ingame_standard"

local play_world_camera_sequence_original = CoreWorldCameraManager.play_world_camera_sequence

function CoreWorldCameraManager:play_world_camera_sequence(...)
    play_world_camera_sequence_original(self, ...)

    for _, key in ipairs({ "_suspended_game_state_name", "_old_game_state_name" }) do
        if self[key] == "world_camera" then
            ReadyUpLockFix:log("world camera would return to world_camera (" .. key .. "), using " .. FALLBACK_STATE)
            ReadyUpLockFix:count("world_camera_state_fixed")
            self[key] = FALLBACK_STATE
        end
    end
end
