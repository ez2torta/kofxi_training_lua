require "kofxi_training.training.training"

-- The Game / Team / Dummy windows (the interactive training controls).
TrainingOverlay = {}

function TrainingOverlay.start()
    local ui = flycast.ui
    local W  = STATE.display.width

    TrainingOverlay.game_window(ui)
    TrainingOverlay.team_window(ui, "P1", 1, 10,      120)
    TrainingOverlay.team_window(ui, "P2", 2, W - 260, 120)
    TrainingOverlay.dummy_window(ui, "P1 Dummy", 1, 10,      470)
    TrainingOverlay.dummy_window(ui, "P2 Dummy", 2, W - 230, 470)
end

-- ---- health bar color (matches cvs2 thresholds) ---------------------
local function health_color(ui, hp, maxhp)
    if hp >= math.floor(0.75 * maxhp) then
        ui.rightTextColor(hp, 0.99, 0.99, 0.11, 0.8)
    elseif hp >= math.floor(0.50 * maxhp) then
        ui.rightTextColor(hp, 0.99, 0.76, 0.03, 0.8)
    elseif hp >= math.floor(0.25 * maxhp) then
        ui.rightTextColor(hp, 0.99, 0.44, 0.03, 0.8)
    else
        ui.rightTextColor(hp, 0.99, 0.24, 0.03, 0.8)
    end
end

function TrainingOverlay.game_window(ui)
    ui.beginWindow("Game", 10, 10, 210, 0)
    ui.text("Timer")
    ui.rightText(Utils.r8(GAME_ADDRESSES.timer[1]))
    if FREEZE_TIMER then
        ui.button('Unfreeze Timer', function() FREEZE_TIMER = false end)
    else
        ui.button('Freeze Timer', function() FREEZE_TIMER = true end)
    end
    ui.endWindow()
end

function TrainingOverlay.team_window(ui, title, side, x, y)
    local g = GAME_ADDRESSES
    ui.beginWindow(title, x, y, 250, 0)
    for c = 0, 2 do
        if PlayersInfo.slot_active(side, c) then
            local id   = Utils.r8(PlayersInfo.extra(side, c, g.f_charid))
            local hp   = Utils.r16(PlayersInfo.extra(side, c, g.f_health))
            local stun = Utils.r8(PlayersInfo.extra(side, c, g.f_stun))
            ui.text(PlayersInfo.char_name(id))
            health_color(ui, hp, g.hp_max)
            ui.text("  stun")
            if stun <= math.floor(0.25 * g.stun_max) then
                ui.rightTextColor(stun, 0.99, 0.24, 0.03, 0.8)
            else
                ui.rightText(stun)
            end
        end
    end
    ui.text("")
    ui.text("Super")
    ui.rightText(Utils.r8(PlayersInfo.team_field(side, g.super_off)))
    ui.text("Skill / Tag")
    ui.rightText(Utils.r8(PlayersInfo.team_field(side, g.tag_off)))
    ui.text("Facing")
    ui.rightText((PlayersInfo.facing_right(side) == 1) and "Right" or "Left")
    ui.endWindow()
end

function TrainingOverlay.dummy_window(ui, title, side, x, y)
    local o = OPT[side]
    ui.beginWindow(title, x, y, 220, 0)

    ui.button('Jump',    function() Training.jump(side) end)
    ui.button('Crouch',  function() Training.crouch(side) end)
    ui.button('Toward',  function() Training.forward(side, PlayersInfo.facing_right(side)) end)
    ui.button('Away',    function() Training.block(side, PlayersInfo.facing_right(side)) end)
    ui.button('Release', function() Training.release_all(side) end)

    -- Facing is auto by default; toggle a manual override and flip the side.
    if MANUAL_FACE[side] then
        ui.button((FACE[side] == 1) and 'Facing[man]: Right' or 'Facing[man]: Left',
            function() FACE[side] = 1 - FACE[side] end)
        ui.button('Facing: use Auto', function() MANUAL_FACE[side] = false end)
    else
        ui.button((FACE[side] == 1) and 'Facing[auto]: Right' or 'Facing[auto]: Left',
            function() MANUAL_FACE[side] = true end)
    end

    if o.guard then
        ui.button('Auto-Guard: ON',  function() o.guard = false end)
    else
        ui.button('Auto-Guard: OFF', function() o.guard = true end)
    end

    ui.text("")
    ui.button('Restore Health', function() Training.restore_health(side) end)
    ui.button('Refill Super/Tag', function() Training.refill_meter(side) end)
    ui.button('Clear Stun', function() Training.clear_stun(side) end)

    ui.text("")
    if o.inf_hp then ui.button('Inf Health: ON', function() o.inf_hp = false end)
    else             ui.button('Inf Health: OFF', function() o.inf_hp = true end) end
    if o.inf_meter then ui.button('Inf Meter: ON', function() o.inf_meter = false end)
    else                ui.button('Inf Meter: OFF', function() o.inf_meter = true end) end
    if o.inf_stun then ui.button('No Dizzy: ON', function() o.inf_stun = false end)
    else               ui.button('No Dizzy: OFF', function() o.inf_stun = true end) end

    ui.button('Forfeit', function() Training.forfeit(side) end)
    ui.endWindow()
end
