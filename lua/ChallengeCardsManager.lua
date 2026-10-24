-- The original walks managers.network:session():all_peers(), so a peer that
-- joined after ReadyUpGui built its list has no suggested_cards entry, can
-- never get one, and pins the result to false - the raid never starts.
--
-- Closing the lobby (see HostNetworkSession.lua) should keep that from
-- happening at all; this covers whoever still slips in during the gap.

local did_everyone_locked_sugested_card_original = ChallengeCardsManager.did_everyone_locked_sugested_card

function ChallengeCardsManager:did_everyone_locked_sugested_card(...)
    local known_peer_indices = ReadyUpLockFix:known_peer_indices()

    if not known_peer_indices then
        return did_everyone_locked_sugested_card_original(self, ...)
    end

    local suggested_cards = self:get_suggested_cards()

    if not suggested_cards then
        return false
    end

    local result = true

    for peer_index, _ in pairs(known_peer_indices) do
        local card_data = suggested_cards[peer_index]

        if not card_data or not card_data.locked_suggestion then
            result = false

            break
        end
    end

    -- Weicht unser Ergebnis vom Original ab, haette das Original hier blockiert
    local vanilla = did_everyone_locked_sugested_card_original(self, ...)

    -- laeuft aus ReadyUpGui:update, also jeden Frame: nur den Wechsel melden
    if vanilla ~= result then
        if ReadyUpLockFix:log_once("cards", string.format(
                "suggested cards: vanilla=%s, patched=%s - %d peer(s) known to the screen, %d with a card",
                tostring(vanilla), tostring(result),
                table.size(known_peer_indices), table.size(suggested_cards))) then
            ReadyUpLockFix:count("cards_override")
        end
    else
        ReadyUpLockFix:log_once("cards", nil)
    end

    return result
end
