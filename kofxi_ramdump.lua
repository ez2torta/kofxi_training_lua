-- =====================================================================
--  KOF XI / Flycast Dojo  -  RAM exporter + Moveset capture driver
-- ---------------------------------------------------------------------
--  Two tools in one script:
--
--  (1) FULL RAM EXPORT  -- streams the 16 MB Atomiswave RAM to a file
--      (a chunk per frame) for offline analysis. Press "Export full RAM".
--
--  (2) MOVESET DRIVER   -- the deterministic loop the study plan asked for:
--      it DRIVES P1's inputs through a scripted list of moves (the
--      `guion_inputs_captura.md` universal block + per-char specials) and,
--      for every frame, LOGS the resulting live state (actionID, category,
--      animFrame, facing, position, active hitboxes) to an NDJSON, labeled
--      with the move that produced it. Result: a reproducible dataset
--      `move -> actionID -> frame_ids` with no external gamepad/Arduino.
--
--      This is possible now that the global pointer table is resolved
--      (see kofxi_aw_modding/docs/runtime_globals_aw.md): the driver reads
--      the active P1 struct each frame to know what move actually came out.
--
--  HOW TO USE THE DRIVER
--    1. Load THIS script in Flycast Dojo (instead of kofxi.lua).
--    2. Enter TRAINING with P1 = the char you want to map, dummy idle.
--    3. Stand P1 a bit away from the dummy, facing right, neutral.
--    4. Press "Run moveset". It plays the universal block automatically,
--       writing kofxi_moveset.ndjson. "Stop" aborts. Watch the console.
--    5. For specials/supers, fill SCRIPT_CHAR below for that character.
--
--  !! BUTTON MAPPING MUST BE VERIFIED !! KOF XI A/B/C/D/E -> DC buttons is
--  a guess (see BTN_* constants). If the wrong move comes out, fix the
--  mapping to match your Flycast input config. Directions are reliable.
-- =====================================================================

local BASE  = 0x0C000000        -- SH-4 cached RAM base (Flycast masks high bits)

-- =====================================================================
--  (1) Full RAM export
-- =====================================================================
local SIZE  = 0x1000000         -- 16 MB
local CHUNK = 0x40000           -- 256 KB per frame  (~64 frames total)
local RAM_PATH = "kofxi_ram.bin"          -- relative to Flycast's working dir

local dump = { state = "idle", pos = 0, fh = nil, err = "" }  -- idle|running|done|error

local function startDump()
    dump.pos, dump.err = 0, ""
    if not io or not io.open then
        dump.state, dump.err = "error", "lua io unavailable in this build"
        return
    end
    local f, e = io.open(RAM_PATH, "wb")
    if not f then dump.state, dump.err = "error", tostring(e); return end
    dump.fh, dump.state = f, "running"
    print("RAM export started -> " .. RAM_PATH)
end

local function stepDump()
    if dump.state ~= "running" then return end
    local read8 = flycast.memory.read8
    local buf, n = {}, math.min(CHUNK, SIZE - dump.pos)
    for i = 0, n - 1 do buf[i + 1] = string.char(read8(BASE + dump.pos + i) % 256) end
    dump.fh:write(table.concat(buf))
    dump.pos = dump.pos + n
    if dump.pos >= SIZE then
        dump.fh:close(); dump.fh, dump.state = nil, "done"
        print(string.format("RAM export DONE: %d bytes -> %s", SIZE, RAM_PATH))
    end
end

-- =====================================================================
--  Live player struct (via the resolved global pointer table)
-- =====================================================================
local PLAYER_TABLE = 0x217FD0
local P_POSX, P_POSY   = 0x000, 0x002
local P_FACING         = 0x08C
local P_ACTION         = 0x0EC
local P_ANIMPTR        = 0x200
local P_CATEGORY       = 0x204
local P_ANIMFR         = 0x2A4
local P_HBACTIVE       = 0x39E

local function r8(off)  return flycast.memory.read8(BASE + off)  end
local function r16(off) return flycast.memory.read16(BASE + off) end
local function r32(off) return r16(off) | (r16(off + 2) << 16)   end
local function rs16(off)
    local v = r16(off); if v >= 0x8000 then v = v - 0x10000 end; return v
end
local function derefPtr(off)
    local p = r32(off); local hi = p >> 24
    if hi ~= 0x8C and hi ~= 0x0C and hi ~= 0xAC then return nil end
    return (p & 0x1FFFFFFF) - 0x0C000000
end

-- Active (point) struct base for a side (1 or 2): the live, on-its-feet slot.
local function activeStruct(side)
    local lo = (side == 1) and 0 or 3
    for i = lo, lo + 2 do
        local b = derefPtr(PLAYER_TABLE + i * 4)
        if b then
            local face = r8(b + P_FACING)
            if (r32(b + P_ANIMPTR) >> 24) == 0x8C and (face == 0 or face == 2) then
                return b
            end
        end
    end
    return nil
end

-- =====================================================================
--  Input mapping
-- =====================================================================
local DPAD_UP, DPAD_DOWN = 1 << 4, 1 << 5
local DPAD_LEFT, DPAD_RIGHT = 1 << 6, 1 << 7
-- KOF XI attack buttons -> Dreamcast button bits. GUESS per guion (A->X,
-- B->A, C->Y, D->B, E->Z). VERIFY against your Flycast config and fix here.
local BTN = {
    A = 1 << 10,  -- DC X
    B = 1 << 2,   -- DC A
    C = 1 << 9,   -- DC Y
    D = 1 << 1,   -- DC B
    E = 1 << 8,   -- DC Z (shift) -- uncertain
}
local ALL_DIRS = DPAD_UP | DPAD_DOWN | DPAD_LEFT | DPAD_RIGHT
local ALL_BTNS = BTN.A | BTN.B | BTN.C | BTN.D | BTN.E

-- numpad digit -> dpad mask, honoring facing (forward = toward opponent).
local function dirMask(d, facingRight)
    local m = 0
    local fwd  = facingRight and DPAD_RIGHT or DPAD_LEFT
    local back = facingRight and DPAD_LEFT  or DPAD_RIGHT
    if d == "7" or d == "8" or d == "9" then m = m | DPAD_UP   end
    if d == "1" or d == "2" or d == "3" then m = m | DPAD_DOWN end
    if d == "1" or d == "4" or d == "7" then m = m | back end
    if d == "3" or d == "6" or d == "9" then m = m | fwd  end
    return m
end

-- button string ("C", "AB", "CD"...) -> mask
local function btnMask(s)
    local m = 0
    for c in s:gmatch(".") do m = m | (BTN[c] or 0) end
    return m
end

local function applyInput(mask)
    -- set exactly `mask`: release everything not in it, press everything in it
    flycast.input.releaseButtons(1, (ALL_DIRS | ALL_BTNS) & ~mask)
    flycast.input.pressButtons(1, mask)
end

-- =====================================================================
--  Move script (data). Each move:
--    label    : name written to the log
--    motion   : numpad directions executed in order (last one is held)
--    btn      : attack buttons pressed during the last direction (may be "")
--    holdLast : frames to hold the last direction/button (default 3)
--    record   : frames of neutral recording after the input (settle + capture)
--  The universal block mirrors guion_inputs_captura.md section 2.
-- =====================================================================
local DIR_FRAMES   = 3     -- frames per intermediate motion direction
local NEUTRAL_PRE  = 18    -- neutral frames before each move (return to idle)

local SCRIPT_UNIVERSAL = {
    { label = "idle",        motion = "5", btn = "",  holdLast = 1,  record = 50 },
    { label = "walk_fwd",    motion = "6", btn = "",  holdLast = 40, record = 6  },
    { label = "walk_back",   motion = "4", btn = "",  holdLast = 40, record = 6  },
    { label = "crouch",      motion = "2", btn = "",  holdLast = 30, record = 6  },
    { label = "jump_up",     motion = "8", btn = "",  holdLast = 2,  record = 58 },
    { label = "jump_fwd",    motion = "9", btn = "",  holdLast = 2,  record = 58 },
    { label = "jump_back",   motion = "7", btn = "",  holdLast = 2,  record = 58 },
    { label = "run_fwd",     motion = "66",btn = "",  holdLast = 30, record = 6  },
    { label = "backdash",    motion = "44",btn = "",  holdLast = 2,  record = 36 },
    { label = "5A", motion = "5", btn = "A", holdLast = 3, record = 30 },
    { label = "5B", motion = "5", btn = "B", holdLast = 3, record = 30 },
    { label = "5C", motion = "5", btn = "C", holdLast = 3, record = 36 },
    { label = "5D", motion = "5", btn = "D", holdLast = 3, record = 36 },
    { label = "2A", motion = "2", btn = "A", holdLast = 3, record = 30 },
    { label = "2B", motion = "2", btn = "B", holdLast = 3, record = 30 },
    { label = "2C", motion = "2", btn = "C", holdLast = 3, record = 36 },
    { label = "2D", motion = "2", btn = "D", holdLast = 3, record = 36 },
    { label = "jA", motion = "8", btn = "A", holdLast = 3, record = 50 },
    { label = "jB", motion = "8", btn = "B", holdLast = 3, record = 50 },
    { label = "jC", motion = "8", btn = "C", holdLast = 3, record = 50 },
    { label = "jD", motion = "8", btn = "D", holdLast = 3, record = 50 },
    { label = "CD_blowback", motion = "5", btn = "CD", holdLast = 3, record = 40 },
    { label = "2CD",         motion = "2", btn = "CD", holdLast = 3, record = 40 },
    { label = "AB_roll",     motion = "5", btn = "AB", holdLast = 3, record = 40 },
}

-- Per-character specials/supers. Fill this for the char loaded in P1 and add
-- it after the universal block. Example shown for Ash (see guion section 4).
local SCRIPT_CHAR = {
    -- { label = "236A", motion = "236", btn = "A", holdLast = 3, record = 40 },
    -- { label = "236C", motion = "236", btn = "C", holdLast = 3, record = 40 },
    -- { label = "214A", motion = "214", btn = "A", holdLast = 3, record = 40 },
    -- { label = "623C", motion = "623", btn = "C", holdLast = 3, record = 40 },
    -- { label = "236236A_super", motion = "236236", btn = "A", holdLast = 4, record = 80 },
}

-- =====================================================================
--  Moveset driver state machine (advances one frame per cbOverlay call)
-- =====================================================================
local MOVE_PATH = "kofxi_moveset.ndjson"  -- relative to Flycast's working dir
local drv = {
    state = "idle",     -- idle | running | done | error
    err   = "",
    list  = {},         -- the active script (universal + char)
    mi    = 1,          -- current move index
    phase = "pre",      -- pre | motion | record
    pf    = 0,          -- frames elapsed in current phase
    di    = 1,          -- current motion-direction index
    fh    = nil,
    logged = 0,
}

local function drvFinish(msg)
    applyInput(0)
    if drv.fh then drv.fh:close(); drv.fh = nil end
    drv.state = msg or "done"
    print(string.format("Moveset driver %s: %d frames -> %s", drv.state, drv.logged, MOVE_PATH))
end

local function startDriver()
    if not io or not io.open then
        drv.state, drv.err = "error", "lua io unavailable in this build"; return
    end
    local f, e = io.open(MOVE_PATH, "w")
    if not f then drv.state, drv.err = "error", tostring(e); return end
    -- build the run list = universal + char-specific
    drv.list = {}
    for _, m in ipairs(SCRIPT_UNIVERSAL) do drv.list[#drv.list + 1] = m end
    for _, m in ipairs(SCRIPT_CHAR)      do drv.list[#drv.list + 1] = m end
    drv.fh, drv.state, drv.mi, drv.phase, drv.pf, drv.di, drv.logged = f, "running", 1, "pre", 0, 1, 0
    print("Moveset driver started -> " .. MOVE_PATH)
end

-- log one frame of live P1 state, labeled with the current move/phase
local function logFrame(move)
    local b = activeStruct(1)
    if not b then return end
    drv.fh:write(string.format(
        '{"move":"%s","phase":"%s","pf":%d,"action":%d,"category":%d,'
        .. '"animframe":%d,"facing":%d,"x":%d,"y":%d,"hbmask":%d}\n',
        move.label, drv.phase, drv.pf,
        r16(b + P_ACTION), r16(b + P_CATEGORY), r16(b + P_ANIMFR),
        r8(b + P_FACING), rs16(b + P_POSX), rs16(b + P_POSY), r8(b + P_HBACTIVE)))
    drv.logged = drv.logged + 1
end

local function stepDriver()
    if drv.state ~= "running" then return end
    local move = drv.list[drv.mi]
    if not move then drvFinish("done"); return end

    local b = activeStruct(1)
    local facingRight = b and (r8(b + P_FACING) == 2) or true
    local motion = move.motion
    local holdLast = move.holdLast or DIR_FRAMES

    if drv.phase == "pre" then
        applyInput(0)                       -- neutral, let char return to idle
        if drv.pf >= NEUTRAL_PRE then
            drv.phase, drv.pf, drv.di = "motion", 0, 1
        else
            drv.pf = drv.pf + 1
        end

    elseif drv.phase == "motion" then
        local d = motion:sub(drv.di, drv.di)
        local isLast = (drv.di >= #motion)
        local mask = dirMask(d, facingRight)
        if isLast then mask = mask | btnMask(move.btn) end
        applyInput(mask)
        logFrame(move)
        local dur = isLast and holdLast or DIR_FRAMES
        if drv.pf >= dur - 1 then
            if isLast then
                drv.phase, drv.pf = "record", 0
            else
                drv.di, drv.pf = drv.di + 1, 0
            end
        else
            drv.pf = drv.pf + 1
        end

    elseif drv.phase == "record" then
        applyInput(0)                       -- neutral, capture the resulting action
        logFrame(move)
        if drv.pf >= (move.record or 30) then
            drv.mi, drv.phase, drv.pf, drv.di = drv.mi + 1, "pre", 0, 1
            if not drv.list[drv.mi] then drvFinish("done") end
        else
            drv.pf = drv.pf + 1
        end
    end
end

-- =====================================================================
--  Callbacks / UI
-- =====================================================================
function cbStart()
    local s = flycast.state
    print("KOF XI RAM exporter + moveset driver loaded.")
    print("Game Id : " .. tostring(s.gameId))
    print("RAM out : " .. RAM_PATH)
    print("Move out: " .. MOVE_PATH)
end

function cbOverlay()
    local ui = flycast.ui
    stepDump()
    stepDriver()

    -- RAM export window
    ui.beginWindow("KOF XI - RAM Export", 30, 30, 420, 0)
    ui.text("Output");  ui.rightText(RAM_PATH)
    ui.text("Status");  ui.rightText(dump.state)
    if dump.state == "running" then
        ui.text("Progress")
        ui.rightText(string.format("%3d%%  (%06X / %06X)",
            math.floor(dump.pos * 100 / SIZE), dump.pos, SIZE))
    elseif dump.state == "error" then
        ui.text("Error"); ui.rightText(dump.err)
    end
    if dump.state ~= "running" then
        ui.button("Export full RAM", function() startDump() end)
    end
    ui.endWindow()

    -- Moveset driver window
    ui.beginWindow("KOF XI - Moveset Driver", 30, 260, 420, 0)
    ui.text("Output");  ui.rightText(MOVE_PATH)
    ui.text("Status");  ui.rightText(drv.state)
    if drv.state == "running" then
        local move = drv.list[drv.mi]
        ui.text("Move")
        ui.rightText(string.format("%d/%d  %s", drv.mi, #drv.list,
            move and move.label or "-"))
        ui.text("Phase");   ui.rightText(drv.phase)
        ui.text("Logged");  ui.rightText(drv.logged)
        ui.button("Stop", function() drvFinish("idle") end)
    else
        if drv.state == "error" then ui.text("Error"); ui.rightText(drv.err) end
        ui.text("P1 idle & facing right, then:")
        ui.button("Run moveset", function() startDriver() end)
    end
    ui.endWindow()
end

flycast_callbacks = {
    start = cbStart,
    overlay = cbOverlay,
}

print("RAM exporter + moveset driver ready")
