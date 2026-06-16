-- Training logic: per-frame toggle enforcement, dummy controls and the
-- one-shot actions used by the overlay buttons.

Training = {}

-- ---- Controller bit masks -------------------------------------------
local DPAD_UP    = 1 << 4
local DPAD_DOWN  = 1 << 5
local DPAD_LEFT  = 1 << 6
local DPAD_RIGHT = 1 << 7
local BTN_B = 1 << 1
local BTN_A = 1 << 2
local BTN_Y = 1 << 9
local BTN_X = 1 << 10

-- =====================================================================
--  Per-frame enforcement (called every frame while in a match)
-- =====================================================================
function Training.apply_toggles()
    -- auto-facing first (auto-guard / dummy controls depend on it)
    PlayersInfo.refresh_facing(1)
    PlayersInfo.refresh_facing(2)

    local g = GAME_ADDRESSES
    if FREEZE_TIMER then
        for _, a in ipairs(g.timer) do Utils.w8(a, 99) end
    end

    for side = 1, 2 do
        local o = OPT[side]
        if o.inf_hp then
            for c = 0, 2 do
                if PlayersInfo.slot_active(side, c) then
                    Utils.w16(PlayersInfo.extra(side, c, g.f_health), g.hp_max)
                    Utils.w16(PlayersInfo.extra(side, c, g.f_vishp),  g.hp_max)
                end
            end
        end
        if o.inf_stun then
            for c = 0, 2 do
                if PlayersInfo.slot_active(side, c) then
                    Utils.w16(PlayersInfo.extra(side, c, g.f_stun),  g.stun_max)
                    Utils.w16(PlayersInfo.extra(side, c, g.f_guard), g.guard_max)
                end
            end
        end
        if o.inf_meter then
            Utils.w8(PlayersInfo.team_field(side, g.super_off), g.super_max)
            Utils.w8(PlayersInfo.team_field(side, g.tag_off),   g.tag_max)
        end
        if o.guard then
            Training.block(side, PlayersInfo.facing_right(side))
        end
    end
end

-- =====================================================================
--  One-shot actions (overlay buttons)
-- =====================================================================
function Training.restore_health(side)
    local g = GAME_ADDRESSES
    for c = 0, 2 do
        Utils.w16(PlayersInfo.extra(side, c, g.f_health), g.hp_max)
        Utils.w16(PlayersInfo.extra(side, c, g.f_vishp),  g.hp_max)
    end
end

function Training.refill_meter(side)
    local g = GAME_ADDRESSES
    Utils.w8(PlayersInfo.team_field(side, g.super_off), g.super_max)
    Utils.w8(PlayersInfo.team_field(side, g.tag_off),   g.tag_max)
end

function Training.clear_stun(side)
    local g = GAME_ADDRESSES
    for c = 0, 2 do
        Utils.w16(PlayersInfo.extra(side, c, g.f_stun),  g.stun_max)
        Utils.w16(PlayersInfo.extra(side, c, g.f_guard), g.guard_max)
    end
end

function Training.forfeit(side)
    local g = GAME_ADDRESSES
    for c = 0, 2 do Utils.w16(PlayersInfo.extra(side, c, g.f_health), 0) end
    for _, a in ipairs(g.timer) do Utils.w8(a, 0) end
end

-- =====================================================================
--  Dummy input helpers (shared with cvs2/mvsc2 dojo scripts)
-- =====================================================================
function Training.jump(player)
    INPUT.releaseButtons(player, DPAD_DOWN)
    INPUT.pressButtons(player, DPAD_UP)
end

function Training.crouch(player)
    INPUT.releaseButtons(player, DPAD_UP)
    INPUT.pressButtons(player, DPAD_DOWN)
end

function Training.forward(player, facing_right)
    if facing_right == 1 then
        INPUT.releaseButtons(player, DPAD_LEFT)
        INPUT.pressButtons(player, DPAD_RIGHT)
    else
        INPUT.releaseButtons(player, DPAD_RIGHT)
        INPUT.pressButtons(player, DPAD_LEFT)
    end
end

function Training.block(player, facing_right)
    if facing_right == 1 then
        INPUT.releaseButtons(player, DPAD_RIGHT)
        INPUT.pressButtons(player, DPAD_LEFT)
    else
        INPUT.releaseButtons(player, DPAD_LEFT)
        INPUT.pressButtons(player, DPAD_RIGHT)
    end
end

function Training.release_all(player)
    INPUT.releaseButtons(player, DPAD_UP | DPAD_DOWN | DPAD_LEFT | DPAD_RIGHT)
    INPUT.releaseButtons(player, BTN_X | BTN_A | BTN_Y | BTN_B)
end
