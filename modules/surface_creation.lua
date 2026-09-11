local sp = require("modules.surface_position")
local map_gens = require("map_gens")
local compat_repair_turret = require("modules.compat_repair_turret")
local warp_settings = require("internal_settings")

local M = {}

M.my_map_gen_settings = {
  default_enable_all_autoplace_controls = false,
  property_expression_names = {cliffiness = 0},
  autoplace_settings = {tile = {settings = {["out-of-map"] = {frequency = "normal", size = "normal", richness = "normal"}}}},
  starting_area = "none",
}

M.space_gen_settings = {
  default_enable_all_autoplace_controls = false,
  property_expression_names = {cliffiness = 0},
  autoplace_settings = {tile = {settings = {["empty-space"] = {frequency = "normal", size = "normal", richness = "normal"}}}},
  starting_area = "none",
}

function M.prepare_surface_spawn(surface, surface_name, allow_random)
  local size = 10
  if not allow_random then
    sp.set_surface_offset(surface_name, {x = 0, y = 0})
    surface.request_to_generate_chunks({0, 0}, size)
    return {x = 0, y = 0}, size
  end
  local level = storage.warptorio.ground_level > 0 and storage.warptorio.ground_level or 1
  local platform = warp_settings.floor.levels[level]
  local chunk_radius = math.ceil((platform * 2) / 32) + 2
  local base_range = warp_settings.random_position_offset
  local chunk_x = 0
  local chunk_y = 0
  if warp_settings.allow_random_position and storage.warptorio.allow_random_spawn then
    chunk_x = math.random(-base_range, base_range)
    chunk_y = math.random(-base_range, base_range)
  end
  local center = {x = chunk_x * 32 + 16, y = chunk_y * 32 + 16}
  sp.set_surface_offset(surface_name, center)
  local radius = math.max(chunk_radius, size)
  surface.request_to_generate_chunks(center, radius)
  return center, radius
end

function M.new_random_surface(name)
  if name == "home" then
    storage.warptorio.warp_next = "nauvis"
    game.print({"warptorio.map-home"})
    return game.planets["nauvis"].surface
  end

  local surface_name = storage.warptorio.planet_next ~= "void" and storage.warptorio.planet_next or "nauvis"
  if name == "garden" or name == "space" then
    surface_name = "nauvis"
  end
  if name ~= "garden" then
    storage.warptorio.surface_name = storage.warptorio.planet_next
  end
  local map_gen = nil
  map_gen = game.planets[surface_name].prototype.map_gen_settings
  storage.warptorio.allow_random_spawn = true

  if (storage.warptorio.planet_next == "void" and name ~= "space") or name == "garden" then
    map_gen = M.my_map_gen_settings
    if name ~= "garden" then
      storage.warptorio.void = true
    end
    storage.warptorio.allow_random_spawn = false
  elseif name == "space" then
    map_gen = M.space_gen_settings
    storage.warptorio.allow_random_spawn = false
  else
    storage.warptorio.void = false
  end
  map_gen.seed = math.random(0, math.pow(2, 16))

  map_gen.peaceful_mode = false
  map_gen.no_enemies_mode = false
  local ms = nil
  storage.warptorio.current_variant = "normal"

  if storage.warptorio.planet_next == "void" or name == "garden" or name == "space" then
    ms = map_gen
    if name == "space" then
      game.print({"warptorio.map-space"})
    elseif name == "garden" then
      -- no message, garden is an internal floor
    elseif storage.warptorio.planet_next == "void" then
      game.print({"warptorio.map-void"})
    end
  else
    local ms_i = storage.warptorio.forced_variant or map_gens.variant_list[math.random(1, #map_gens.variant_list)]
    storage.warptorio.current_variant = ms_i
    if ms_i == "rich" then
      storage.warptorio.allow_random_spawn = false
    end
    ms = map_gens.functions.generate(surface_name, ms_i, map_gen)
    game.print({"warptorio.map-gen-" .. ms_i})
  end

  ms.seed = math.random(0, math.pow(2, 32))
  if name ~= "garden" then
    storage.warptorio.warp_next = name
  end

  if surface_name == "nauvis" then
    return game.create_surface(name, ms)
  else
    if game.planets[storage.warptorio.surface_name].surface and storage.warptorio.surface_name ~= surface_name then
      compat_repair_turret.destroy_before_clear(game.planets[storage.warptorio.surface_name].surface)
      game.planets[storage.warptorio.surface_name].surface.clear()
      game.delete_surface(game.planets[storage.warptorio.surface_name].surface.name)
    end

    if game.planets[storage.warptorio.surface_name].prototype.entities_require_heating or game.planets[storage.warptorio.surface_name].surface ~= nil then
      if game.planets[storage.warptorio.surface_name].surface ~= nil then
        game.planets[storage.warptorio.surface_name].surface.map_gen_settings = ms
      end
      local surf = game.planets[storage.warptorio.surface_name].create_surface()
      surf.name = name
      return surf
    else
      local surf = game.create_surface(name, ms)
      game.planets[storage.warptorio.surface_name].associate_surface(surf)
      return surf
    end
  end
end

return M
