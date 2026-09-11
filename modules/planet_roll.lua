local shared = require("shared")
local events = require("modules.events")
local warp_settings = require("internal_settings")

local M = {}

function M.roll_planet()
  local surfaces = {}

  table.insert(surfaces, "nauvis")

  if game.forces["player"].technologies[warp_settings.trigger_research].researched then
    for i, v in pairs(game.planets) do
      if game.forces.player.is_space_location_unlocked(i) and i ~= storage.warptorio.surface_name and not (i:match('.*%-factory%-floor') or i:match('factory%s-travel%s-surface')) then
        table.insert(surfaces, i)
      end
    end
  end

  local surface_name = surfaces[math.random(1, #surfaces)]

  if surface_name == "nauvis" and storage.warptorio.void ~= true then
    local r = math.random()
    if r > 0.75 then
      surface_name = "void"
    end
  end

  if game.forces["player"].technologies[shared.techs.end_prepare].researched then
    local r = math.random()
    if storage.warptorio.travel_to_edge then
      storage.warptorio.travel_to_edge = false
    elseif r < warp_settings.space.edge_chance then
      storage.warptorio.travel_to_edge = true
    end
  end

  storage.warptorio.planet_next = surface_name
  if game.forces["player"].technologies[warp_settings.trigger_research].researched then
    local sound = defines.print_sound.always
    if warp_settings.next_planet_text then
      game.print({"warptorio.next-planet", storage.warptorio.planet_next}, {volume_modifier = 0})
    end
    if warp_settings.next_planet_sound then
      game.play_sound({path = "planet-change", volume_modifier = 0.5})
    end
  end
  events.raise(shared.events.planet_chosen, {
    planet = surface_name,
    index = storage.warporio.index,
  })
end

return M
