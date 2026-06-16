-- Player/team reads: the reliable team struct plus the live player struct
-- reached through the global pointer table.

PlayersInfo = {}

function PlayersInfo.char_name(id)
    return ROSTER[id] or string.format("Char %02X", id)
end

-- address of a PlayerExtra field for (side, char-slot, field)
function PlayersInfo.extra(side, idx, field)
    local g = GAME_ADDRESSES
    return g.team[side] + g.extra_off + idx * g.extra_step + field
end

function PlayersInfo.team_field(side, field)
    return GAME_ADDRESSES.team[side] + field
end

-- a team slot holds a real character if its charID is in the roster
function PlayersInfo.slot_active(side, c)
    return ROSTER[Utils.r8(PlayersInfo.extra(side, c, GAME_ADDRESSES.f_charid))] ~= nil
end

function PlayersInfo.in_match()
    if not PlayersInfo.slot_active(1, 0) then return false end
    local g = GAME_ADDRESSES
    local hp = Utils.r16(PlayersInfo.extra(1, 0, g.f_health))
             + Utils.r16(PlayersInfo.extra(2, 0, g.f_health))
    return hp > 0
end

-- Active (point) char's live struct base for a side (1 or 2), plus the
-- derived team.point index; nil if none is on screen. Scans this side's
-- 3 slots and keeps the live, on-its-feet one. NEVER hardcode the index:
-- it moves with tag/KO.
function PlayersInfo.active_struct(side)
    local g  = GAME_ADDRESSES
    local lo = (side == 1) and 0 or 3
    for i = lo, lo + 2 do
        local b = Utils.deref(g.player_table + i * 4)
        if b then
            local face = Utils.r8(b + g.p_facing)
            if (Utils.r32(b + g.p_animptr) >> 24) == 0x8C
               and (face == 0 or face == 2) then
                return b, (i - lo)
            end
        end
    end
    return nil
end

-- Snapshot the state-machine fields of a live struct at base `b`.
function PlayersInfo.read_fighter(b)
    local g = GAME_ADDRESSES
    return {
        x      = Utils.s16(b + g.p_posx),
        y      = Utils.s16(b + g.p_posy),
        facing = Utils.r8(b + g.p_facing),       -- 0 left, 2 right
        action = Utils.r16(b + g.p_action),
        anifr  = Utils.r16(b + g.p_animfr),
        cat    = Utils.r16(b + g.p_category),
        bank   = Utils.r16(b + g.p_charbank),
        hbmask = Utils.r8(b + g.p_hbactive),
    }
end

-- Refresh auto-facing for `side` from its live struct; returns the base.
function PlayersInfo.refresh_facing(side)
    local b = PlayersInfo.active_struct(side)
    if not b then return nil end
    if not MANUAL_FACE[side] then
        FACE[side] = (Utils.r8(b + GAME_ADDRESSES.p_facing) == 2) and 1 or 0
    end
    return b
end

function PlayersInfo.facing_right(side) return FACE[side] end
