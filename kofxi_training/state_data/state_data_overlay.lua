-- Live state-machine window per side: action / category / animFrame /
-- charBank / facing / position + active hitboxes, read by following the
-- global pointer table to the active char struct.
--
-- NOTE: flycast.ui exposes only text/buttons (no rect primitive), so the
-- hitboxes are shown numerically (slot, type, world center, size) rather
-- than drawn as boxes over the characters.

StateDataOverlay = {}

function StateDataOverlay.start()
    local ui = flycast.ui
    StateDataOverlay.window(ui, 1, 290, 120)
    StateDataOverlay.window(ui, 2, 820, 120)
end

function StateDataOverlay.window(ui, side, x, y)
    local g = GAME_ADDRESSES
    ui.beginWindow("State P" .. side, x, y, 250, 0)

    local b, point = PlayersInfo.active_struct(side)
    if not b then
        ui.text("(no live struct - transition)")
        ui.endWindow()
        return
    end

    local f = PlayersInfo.read_fighter(b)
    ui.text("point char"); ui.rightText(point)
    ui.text("action");     ui.rightText(f.action)
    ui.text("category");   ui.rightText(f.cat)
    ui.text("anim frame"); ui.rightText(f.anifr)
    ui.text("char bank");  ui.rightText(f.bank)
    ui.text("facing");     ui.rightText((f.facing == 2) and "Right" or "Left")
    ui.text("pos X / Y");  ui.rightText(string.format("%d / %d", f.x, f.y))
    ui.text("airborne");   ui.rightText((f.y < g.ground_y) and "yes" or "no")

    ui.text("")
    ui.text(string.format("hitboxes active 0x%02X", f.hbmask))
    local fsign = (f.facing == 2) and 1 or -1
    for i = 0, 6 do
        if (f.hbmask & (1 << i)) ~= 0 then
            local hb  = b + g.p_hitboxes + i * g.hitbox_stride
            local rx  = Utils.s16(hb + g.hb_relx)
            local ry  = Utils.s16(hb + g.hb_rely)
            local w   = Utils.r8(hb + g.hb_w)
            local h   = Utils.r8(hb + g.hb_h)
            local bid = Utils.r8(hb + g.hb_boxid)
            local cx  = f.x + rx * 2 * fsign      -- world center (game.lua proj.)
            local cy  = f.y - ry * 2
            ui.text(string.format("  %d:%-4s c=(%d,%d) %dx%d",
                i, Utils.box_label(bid), cx, cy, w * 2, h * 2))
        end
    end
    ui.endWindow()
end
