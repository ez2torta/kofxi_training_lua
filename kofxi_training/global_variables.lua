-- Global handles and persistent training state (mirrors VF4's
-- global_variables.lua). These are intentionally globals so every module
-- can reach them after `require`.

STATE  = flycast.state
MEMORY = flycast.memory
INPUT  = flycast.input

-- SH-4 cached RAM base. Flycast masks the high address bits, so any RAM
-- mirror base works; the memory table stores RAW offsets and helpers add BASE.
BASE = 0x0C000000

GAME_ADDRESSES = nil       -- set to KOFXI_MEMORY_TABLE once the ROM is known
DEBUG   = false
HIDE_UI = false

-- ---- Persistent training toggles / state ----------------------------
FREEZE_TIMER = true

-- Facing: 1 = right, 0 = left. Auto-detected from the live struct each
-- frame; MANUAL_FACE[side] forces it (override) when true.
FACE        = { 1, 0 }            -- P1 right, P2 left
MANUAL_FACE = { false, false }

-- Per-side dummy toggles
OPT = {
    [1] = { guard = false, inf_hp = false, inf_meter = false, inf_stun = false },
    [2] = { guard = false, inf_hp = false, inf_meter = false, inf_stun = false },
}
