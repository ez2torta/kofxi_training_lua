-- =====================================================================
--  The King of Fighters XI (Atomiswave) - Flycast Dojo Training Overlay
-- ---------------------------------------------------------------------
--  Modular entry point, structured like the VF4-Training project:
--  this thin file wires the modules together and defines the callbacks.
--  See kofxi_training/ for the actual code.
--
--    global_variables           STATE/MEMORY/INPUT/BASE + persistent state
--    memory_addresses.kofxi      KOFXI_MEMORY_TABLE + ROSTER
--    utils.utils                 BASE-relative reads, deref, box labels
--    players_info                team reads + live struct via pointer table
--    state_data.state_data_overlay   live state-machine window
--    training.training(_overlay)     toggles, dummy controls, windows
--
--  Globals resolved offline (kofxi_aw_modding/docs/runtime_globals_aw.md):
--  player_table 0x217FD0, camera 0x27CAA8 -> auto-facing, real position
--  and the per-frame state machine for any character / any match.
-- =====================================================================

-- Make `require` find the kofxi_training/ modules sitting next to THIS file,
-- no matter what Flycast's working directory is. (Lua's default package.path
-- is relative to flycast.exe, so without this the modules only load if both
-- kofxi.lua and kofxi_training/ are copied next to the exe, VF4-style.)
do
    local src = (debug and debug.getinfo) and debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*[/\\])")       -- strip leading '@' and filename
    if dir then
        package.path = dir .. "?.lua;" .. dir .. "?/init.lua;" .. package.path
        print("KOF XI: module path = " .. dir)
    else
        print("KOF XI: could not derive script dir; relying on default package.path")
    end
end

require "kofxi_training.global_variables"
require "kofxi_training.memory_addresses.kofxi"
require "kofxi_training.utils.utils"
require "kofxi_training.players_info"
require "kofxi_training.state_data.state_data_overlay"
require "kofxi_training.training.training_overlay"
require "kofxi_training.extras.extras_overlay"

function Overlay()
    if GAME_ADDRESSES == nil or HIDE_UI then return end

    -- Extras (bilinear toggle, debug-menu explorer) work everywhere, including
    -- the boot/test menus, so they run BEFORE the in-match gate.
    Extras.apply()
    if flycast.config.dojo.ShowTrainingGameOverlay then
        ExtrasOverlay.window(flycast.ui)
    end

    if not PlayersInfo.in_match() then return end

    -- persistent enforcement (runs even if the overlay windows are hidden)
    Training.apply_toggles()

    if not flycast.config.dojo.ShowTrainingGameOverlay then return end
    TrainingOverlay.start()
    StateDataOverlay.start()
end

function CheckRom()
    local s = flycast.state
    print("KOF XI training overlay loaded.")
    print("Game Id: " .. tostring(s.gameId))
    print("Media:   " .. tostring(s.media))
    print("Display: " .. s.display.width .. "x" .. s.display.height)
    -- The exact Atomiswave gameId string is not asserted here; the AW memory
    -- map is the only one this script ships, so use it directly.
    GAME_ADDRESSES = KOFXI_MEMORY_TABLE
end

GAME_ADDRESSES = KOFXI_MEMORY_TABLE

flycast_callbacks = {
    start   = CheckRom,
    overlay = Overlay,
}

print("KOF XI callbacks set")
