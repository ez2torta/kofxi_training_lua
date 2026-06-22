-- Extras: runtime graphics + developer-menu helpers.
--
-- Unlike the training toggles (which only matter inside a match), these work
-- EVERYWHERE — including the boot/test menus — because they touch global state
-- and the program code that already lives in RAM. Everything here is RAM-only
-- and fully reversible (reset the emulator and it's gone).
--
-- Background / full reverse-engineering writeup:
--   ../../../estudio_bilinear_y_menus_ocultos.md
--   ../../../ejecutable_alternativo_CHANGELOG.md
--
-- Address convention (same as the rest of the project): RAW offsets, helpers
-- add BASE (0x0C000000). A SH-4 address 0x8C0xxxxx maps to RAW 0x0xxxxx
-- (i.e. addr & 0x1FFFFFFF - 0x0C000000). The AW program is loaded at
-- 0x8C010000, so its code offsets are simply (file_body_offset + 0x010000).

Extras = {}

-- =====================================================================
--  1) Bilinear filter — runtime toggle  (the "those RAM things" you wanted)
-- ---------------------------------------------------------------------
--  The game builds the PowerVR2 texture-filter bits with three `or`
--  instructions. Overwriting each with `nop` (0x0009) forces Filter Mode = 0
--  = point sampling (sharp pixels). Writing the originals back re-enables
--  bilinear. This is exactly the patch baked into
--  ax3201p01.fmem1.dec_bilinear, but live and reversible.
-- =====================================================================
local NOP = 0x0009
local BILINEAR_SITES = {
    { off = 0x010522, orig = 0x204B },  -- RAM 0x8C010522  global filter setter (or R4,R0)
    { off = 0x0B9084, orig = 0x201B },  -- RAM 0x8C0B9084  poly path, bit 0x2000 (or R1,R0)
    { off = 0x0B9108, orig = 0x212B },  -- RAM 0x8C0B9108  poly path, bit 0x4000 (or R2,R1)
}

-- Default OFF = sharp/point sampling (your preference; flip with the button).
BILINEAR_ON = false

-- Re-enforce the desired state. Cheap and self-stabilising: once a site already
-- holds the target opcode no write happens. The guard makes sure we only ever
-- touch a site that currently holds either the original `or` or our `nop`, so
-- it is a no-op before the program is in RAM, or if offsets ever drift.
function Extras.apply_bilinear()
    for _, s in ipairs(BILINEAR_SITES) do
        local cur    = Utils.r16(s.off)
        local target = BILINEAR_ON and s.orig or NOP
        if cur ~= target and (cur == s.orig or cur == NOP) then
            Utils.w16(s.off, target)
        end
    end
end

function Extras.toggle_bilinear()
    BILINEAR_ON = not BILINEAR_ON
    Extras.apply_bilinear()
    print("KOF XI: bilinear " .. (BILINEAR_ON and "ON" or "OFF (point sampling)"))
end

-- =====================================================================
--  2) Developer DEBUG menu — live explorer
-- ---------------------------------------------------------------------
--  The dev debug menu (MUTEKI/No Life/Death/Time Stop/...) is a state of the
--  test-menu state machine. It is fully present in the ROM but not reachable
--  by normal navigation. These are its runtime variables so you can watch how
--  they change while you move around the test menu and discover the transition
--  that opens the debug screen — then it can be baked into the ROM safely.
--
--  NOTE: the debug *flags* (0x126DF8+) are menu-internal; the gameplay does NOT
--  read them, so poking them does not give invincibility. For real cheats use
--  the training toggles (Inf Health, etc.). This block is a reversing aid.
-- =====================================================================
Extras.DBG = {
    menu_state  = 0x189128,   -- RAM 0x8C189128  test-menu screen state (u8)
    menu_cursor = 0x18926C,   -- RAM 0x8C18926C  cursor index (u8)
    dbg_flags   = 0x126DF8,   -- RAM 0x8C126DF8  debug toggles base (menu-internal)
    handler     = 0x05C9C8,   -- RAM 0x8C05C9C8  debug-menu draw handler (for reference)
}

MENU_LOG = false                      -- print state/cursor changes to the console
local _last_state, _last_cursor = -1, -1

function Extras.log_menu_changes()
    local st = Utils.r8(Extras.DBG.menu_state)
    local cu = Utils.r8(Extras.DBG.menu_cursor)
    if st ~= _last_state or cu ~= _last_cursor then
        print(string.format("[KOFXI menu] state=0x%02X cursor=0x%02X", st, cu))
        _last_state, _last_cursor = st, cu
    end
end

-- EXPERIMENTAL: force the menu state byte. Safe (RAM only) — use it to probe
-- which state value opens the debug screen. If it misbehaves, just reset.
function Extras.poke_menu_state(v)
    Utils.w8(Extras.DBG.menu_state, v)
    print(string.format("KOF XI: forced menu_state = 0x%02X (experimental)", v))
end

-- =====================================================================
--  3) Char-engine code sites — live A/B test ("personajes raros")
-- ---------------------------------------------------------------------
--  Three sites differ between a clean dump and the modified backup. They are
--  forced-return stubs in the character/animation engine and the prime suspect
--  for weird character behaviour. Because the program runs from RAM you can
--  flip each one live (factory <-> patched) and watch a running match — no
--  re-flash, no re-extract. Offsets are RAW (BASE-relative); bytes are the exact
--  factory/patched forms verified against the .dec dumps.
--    factory = original game code   |   patched = the unwanted stub
--  See ../../../patch_kofxi_aw.py and ../../../metodo_parcheo_y_diagnostico.md
-- =====================================================================
Extras.CODE_SITES = {
    { name = "char @7C854", off = 0x07C854,
      factory = {0x22,0x4F,0xF0,0x7F,0x43,0x1F}, patched = {0x01,0xE0,0x0B,0x00,0x09,0x00},
      force = nil },   -- force: nil = observe, "factory", or "patched"
    { name = "char @7EE94", off = 0x07EE94,
      factory = {0x22,0x4F,0xEC,0x7F,0xF3,0x63}, patched = {0xFF,0xE0,0x0B,0x00,0x09,0x00},
      force = nil },
    { name = "char @8109C", off = 0x08109C,
      factory = {0x01,0x60}, patched = {0x05,0xE0},
      force = nil },
}

local function _bytes_at(off, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = Utils.r8(off + i) end
    return t
end
local function _eq(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function _write(off, b)
    for i = 1, #b do Utils.w8(off + i - 1, b[i]) end
end

-- "factory" / "patched" / "unknown"  (read live from RAM)
function Extras.site_state(s)
    local cur = _bytes_at(s.off, #s.factory)
    if _eq(cur, s.factory) then return "factory" end
    if _eq(cur, s.patched) then return "patched" end
    return "unknown"
end

-- Enforce any site that has a forced state. Only ever overwrites a site that
-- currently holds a recognised form, so it is a no-op before the program is in
-- RAM or if offsets drift.
function Extras.apply_code_sites()
    for _, s in ipairs(Extras.CODE_SITES) do
        if s.force then
            local cur = _bytes_at(s.off, #s.factory)
            if _eq(cur, s.factory) or _eq(cur, s.patched) then
                local target = (s.force == "factory") and s.factory or s.patched
                if not _eq(cur, target) then _write(s.off, target) end
            end
        end
    end
end

-- Cycle one site: observe -> factory -> patched -> observe
function Extras.cycle_site(s)
    if     s.force == nil       then s.force = "factory"
    elseif s.force == "factory" then s.force = "patched"
    else                             s.force = nil end
    Extras.apply_code_sites()
    print(string.format("KOF XI: %s -> %s", s.name, tostring(s.force)))
end

-- Quick A/B: force ALL char sites to factory / clear all forcing (observe)
function Extras.all_char(force)
    for _, s in ipairs(Extras.CODE_SITES) do s.force = force end
    Extras.apply_code_sites()
    print("KOF XI: char-engine -> " .. (force or "observe"))
end

-- =====================================================================
--  Per-frame entry point (called from Overlay every frame, in or out of match)
-- =====================================================================
function Extras.apply()
    Extras.apply_bilinear()
    Extras.apply_code_sites()
    if MENU_LOG then Extras.log_menu_changes() end
end
