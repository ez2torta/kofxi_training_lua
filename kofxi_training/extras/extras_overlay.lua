require "kofxi_training.extras.extras"

-- The "Extras" window: bilinear toggle + live debug-menu explorer.
-- Rendered every frame (also outside a match), placed next to the Game window.
ExtrasOverlay = {}

function ExtrasOverlay.window(ui)
    ui.beginWindow("Extras", 230, 10, 220, 0)

    -- ---- Graphics: bilinear filter ----
    if BILINEAR_ON then
        ui.button('Bilinear: ON',          function() Extras.toggle_bilinear() end)
    else
        ui.button('Bilinear: OFF (sharp)', function() Extras.toggle_bilinear() end)
    end

    ui.text("")
    -- ---- Debug-menu explorer (reversing aid) ----
    ui.text("Test-menu state")
    ui.rightText(string.format("0x%02X", Utils.r8(Extras.DBG.menu_state)))
    ui.text("cursor")
    ui.rightText(string.format("0x%02X", Utils.r8(Extras.DBG.menu_cursor)))

    if MENU_LOG then
        ui.button('Menu log: ON',  function() MENU_LOG = false end)
    else
        ui.button('Menu log: OFF', function() MENU_LOG = true end)
    end

    ui.text("")
    -- ---- Char-engine A/B (diagnose "personajes raros") ----
    ui.text("Char-engine (live A/B):")
    for _, s in ipairs(Extras.CODE_SITES) do
        local st  = Extras.site_state(s)
        local tag = s.force and (" [" .. s.force .. "]") or ""
        ui.button(s.name .. ": " .. st .. tag, function() Extras.cycle_site(s) end)
    end
    ui.button('All -> FACTORY',  function() Extras.all_char("factory") end)
    ui.button('All -> observe',  function() Extras.all_char(nil) end)

    ui.endWindow()
end
