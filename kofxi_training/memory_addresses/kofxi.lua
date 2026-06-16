-- KOF XI (Atomiswave) memory map. All values are RAW RAM offsets (helpers
-- add BASE). Sources: kofxi.cht, kof_xi/types.lua, and the resolved global
-- pointer table (kofxi_aw_modding/docs/runtime_globals_aw.md).

KOFXI_MEMORY_TABLE = {
    -- timer (main + two mirrors in the team region); freeze writes 99
    timer = { 0x131E2C, 0x27CB78, 0x27CB7E },

    -- team struct (P1, P2), stride 0x1F8
    team       = { 0x27CB54, 0x27CD4C },
    super_off  = 0x88,                 -- super meter (max 0xE0)
    tag_off    = 0x8C,                 -- tag / skill meter (max 0xE0)
    extra_off  = 0x150,                -- PlayerExtra[3] base
    extra_step = 0x20,                 -- per-character stride
    f_charid   = 0x00,
    f_health   = 0x04,                 -- word, max 0x70 (112)
    f_vishp    = 0x06,
    f_stun     = 0x08,                 -- max 0x70, 0 = dizzy
    f_guard    = 0x0A,                 -- max 0x70, 0 = guard crush

    -- caps
    hp_max = 0x70, stun_max = 0x70, guard_max = 0x70,
    super_max = 0xE0, tag_max = 0xE0,

    -- live player struct, reached via the global pointer table.
    -- p[2][3]: indices 0..2 = P1's chars, 3..5 = P2's chars (team.point
    -- selects); [6..11] are projectiles/effects. Each entry is a SH-4 ptr.
    player_table = 0x217FD0,
    camera       = 0x27CAA8,           -- camera.X @ +0, camera.Y @ +2 (s16)

    -- internal struct field offsets (identical to PS2, verified in AW)
    p_posx     = 0x000,                -- s16 world X
    p_posy     = 0x002,                -- s16 world Y (ground = 672 = 0x2A0)
    p_facing   = 0x08C,                -- 0 = left, 2 = right (bench: 0x3C/0x3E)
    p_action   = 0x0EC,                -- u16 actionID
    p_animptr  = 0x200,                -- u32 animDataPtr (!=0 => slot is live)
    p_category = 0x204,                -- u16 actionCategory (bench = 0xFF)
    p_charbank = 0x226,                -- u16 charBankSelector
    p_animfr   = 0x2A4,                -- u16 animFrameIndex
    p_hitboxes = 0x314,                -- 7 hitboxes x 10 bytes
    p_hbactive = 0x39E,                -- u8 bitmask of active hitboxes

    -- hitbox (10 B): relX s16 @+0, relY s16 @+2, boxID @+4, w @+7, h @+8
    hitbox_stride = 0x0A,
    hb_relx = 0x00, hb_rely = 0x02, hb_boxid = 0x04, hb_w = 0x07, hb_h = 0x08,

    ground_y = 672,
}

-- charID -> name (from kof_xi/roster.lua)
ROSTER = {
    [0x00]="Ash",      [0x01]="Oswald",   [0x02]="Shen Woo",  [0x03]="Elisabeth",
    [0x04]="Duo Lon",  [0x05]="Benimaru", [0x06]="Terry",     [0x07]="Kim",
    [0x08]="Duck King",[0x09]="Ryo",      [0x0A]="Yuri",      [0x0B]="King",
    [0x0C]="B. Jenet", [0x0D]="Gato",     [0x0E]="Tizoc",     [0x0F]="Ralf",
    [0x10]="Clark",    [0x11]="Whip",     [0x12]="Athena",    [0x13]="Kensou",
    [0x14]="Momoko",   [0x15]="Vanessa",  [0x16]="Mary",      [0x17]="Ramon",
    [0x18]="Malin",    [0x19]="Kasumi",   [0x1A]="Eiji",      [0x1B]="K'",
    [0x1C]="Kula",     [0x1D]="Maxima",   [0x1E]="Kyo",       [0x1F]="Iori",
    [0x20]="Shingo",   [0x21]="Gai",      [0x22]="Hayate",    [0x23]="Adelheid",
    [0x24]="Silber",   [0x25]="Jyazu",    [0x26]="Shion",     [0x27]="Magaki",
    [0x29]="Mai",      [0x2A]="Robert",   [0x2B]="Mr. Big",   [0x2C]="Geese",
    [0x2D]="Hotaru",   [0x2E]="Tung",     [0x2F]="Kyo (EX)",
}
