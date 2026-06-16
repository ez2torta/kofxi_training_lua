-- Low-level helpers: BASE-relative memory access, signed conversion,
-- SH-4 pointer dereference, and hitbox type labels.

Utils = {}

-- ---- BASE-relative memory access ------------------------------------
function Utils.r8(off)  return MEMORY.read8(BASE + off)  end
function Utils.r16(off) return MEMORY.read16(BASE + off) end
function Utils.r32(off) return Utils.r16(off) | (Utils.r16(off + 2) << 16) end
function Utils.w8(off, v)  MEMORY.write8(BASE + off, v)  end
function Utils.w16(off, v) MEMORY.write16(BASE + off, v) end

function Utils.to_signed16(value)
    if value == nil then return 0 end
    if value >= 0x8000 then return value - 0x10000 end
    return value
end

function Utils.s16(off) return Utils.to_signed16(Utils.r16(off)) end

-- Dereference a SH-4 pointer stored at `off`; returns a raw RAM offset or nil.
function Utils.deref(off)
    local p  = Utils.r32(off)
    local hi = p >> 24
    if hi ~= 0x8C and hi ~= 0x0C and hi ~= 0xAC then return nil end
    return (p & 0x1FFFFFFF) - 0x0C000000
end

-- ---- Hitbox boxID -> short type label (mirrors kof_xi/boxtypes.lua) --
-- Each char in BOX_LUT is the type of boxID = its 0-based position.
local BOX_LUT = table.concat({
    ".vvVVvVv",  -- 00-07
    "vvvvvv.p",  -- 08-0F
    "pppppppp",  -- 10-17
    "ppppgggv",  -- 18-1F
    "AAAAAAAA",  -- 20-27
    "AAAAAAAA",  -- 28-2F
    "AAAAAAAA",  -- 30-37
    "AAAAAAAA",  -- 38-3F
    "AAAAAAAA",  -- 40-47
    "AAAAAAAA",  -- 48-4F
    "AAAAAAAA",  -- 50-57
    "AAAAAAAA",  -- 58-5F
    "Avvvvvv.",  -- 60-67
    "......AA",  -- 68-6F
    "AAAAAAAA",  -- 70-77
    "AAAAAAAA",  -- 78-7F
    "LLLL....",  -- 80-87
})
local BOX_NAME = {
    ["."]="-",   ["o"]="col", ["c"]="cnt", ["v"]="vul", ["V"]="cvl",
    ["a"]="avl", ["O"]="ovl", ["g"]="grd", ["A"]="ATK", ["L"]="cls",
    ["p"]="pvl", ["P"]="pat", ["t"]="tbl", ["T"]="thr",
}
function Utils.box_label(id)
    local c = (id < #BOX_LUT) and BOX_LUT:sub(id + 1, id + 1) or "."
    return BOX_NAME[c] or string.format("b%02X", id)
end
