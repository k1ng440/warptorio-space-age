local shared = require("shared")
local sp = require("modules.surface_position")
local eh = require("modules.entity_helper")
local events = require("modules.events")
local warp_settings = require("internal_settings")
local warp_constant_combinator = require("warp_constant_combinator")

local M = {}

function M.researched_level(prefix)
  local level = 0
  for i = 1, 50 do
    local tech = game.forces["player"].technologies[prefix .. i]
    if tech and tech.researched then
      level = i
    else
      break
    end
  end
  return level
end

function M.restore_save_state()
  if not storage.warptorio then return end
  if not game then return end
  local force = game.forces and game.forces["player"]
  if not force then return end
  local ground = storage.warptorio.ground_level or 0
  local level = M.researched_level("warp-ground-platform-")
  if level > ground then
    storage.warptorio.ground_level = level
    storage.warptorio.ground_size = warp_settings.floor.levels[level] * 2
    log("[warptorio] restore_save_state: raised ground level " .. ground .. " -> " .. level)
  end
  local factory = storage.warptorio.factory_level or 0
  level = M.researched_level("warp-factory-platform-")
  if level > factory then
    storage.warptorio.factory_level = level
    log("[warptorio] restore_save_state: raised factory level " .. factory .. " -> " .. level)
  end
end

function M.pollution_settings()
  game.map_settings.pollution.enabled = true
  game.map_settings.pollution.diffusion_ratio = 0.1
end

function M.trigger_game_over()
  if storage.warptorio.game_over then return end
  storage.warptorio.game_over = true
  game.print({"warptorio.capacitor-destroyed"})
  game.set_lose_ending_info{title = {"warptorio.lose-screen-title"}, message = {"warptorio.lose-screen-text"}}
  game.set_game_state{game_finished = true, player_won = false, can_continue = true}
  events.raise(shared.events.game_over, {
    surface = storage.warptorio.warp_zone,
    index = storage.warporio.index,
  })
end

function M.starter_chest()
  if not warp_settings.starter then return end
  local container = eh.get_or_create("steel-chest", {x = 0, y = -10, surface = "nauvis"})
  for i, v in pairs(warp_settings.starter_items) do
    container.insert({name = i, count = v})
  end
end

function M.on_init_or_load()
  storage.warporio = storage.warporio or {}
  storage.warptorio = storage.warptorio or {}
  storage.warporio.index = storage.warporio.index or 0
  storage.warptorio.warp_zone = storage.warptorio.warp_zone or "nauvis"
  storage.warptorio.factory_level = storage.warptorio.factory_level or 0
  storage.warptorio.ground_level = storage.warptorio.ground_level or 0
  storage.warptorio.belt_level = storage.warptorio.belt_level or 0
  storage.warptorio.power_level = storage.warptorio.power_level or 0
  storage.warptorio.time_passed = storage.warptorio.time_passed or 0
  storage.warptorio.time_level = storage.warptorio.time_level or 0
  storage.warptorio.wave_time = storage.warptorio.wave_time or 0
  storage.warptorio.wave_index = storage.warptorio.wave_index or 0
  storage.warptorio.warp_out = storage.warptorio.warp_out or 0
  storage.warptorio.surface_name = storage.warptorio.surface_name or "nauvis"
  storage.warptorio.planet_timer = storage.warptorio.planet_timer or 0
  storage.warptorio.planet_next = storage.warptorio.planet_next or nil
  storage.warptorio.game_over = storage.warptorio.game_over or false
  sp.ensure_surface_positions()
  sp.ensure_surface_offset(storage.warptorio.warp_zone)
  M.starter_chest()
  M.restore_save_state()
  warp_constant_combinator.init()
end

return M
