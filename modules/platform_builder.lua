local shared = require("shared")
local sp = require("modules.surface_position")
local eh = require("modules.entity_helper")
local tg = require("modules.tile_generation")
local util = require("modules.util")
local belt_system = require("modules.belt_system")
local surface_creation = require("modules.surface_creation")
local platform_animation = require("modules.platform_animation")
local teleporter_visualize = require("modules.teleporter_visualize")
local warp_settings = require("internal_settings")

local M = {}

local shape_delta_cache = {}

function M.shape_positions(shape, size)
  local key = shape .. "_" .. tostring(size)
  local positions = shape_delta_cache[key]
  if positions then
    return positions
  end
  local tiles
  if shape == "circle" then
    tiles = tg.generate_ellipse(size, size, nil, 0, 0)
  elseif shape == "hexagon" then
    tiles = tg.generate_hexagon(size * 0.62, nil, 0, 0)
  else
    tiles = tg.generate_rectangle(size, size, nil, 0, 0)
  end
  positions = {}
  for i = 1, #tiles do
    positions[i] = tiles[i].position
  end
  shape_delta_cache[key] = positions
  return positions
end

function M.generate_ground_shape(surface_name, size, tile)
  local base = sp.get_surface_offset(surface_name)
  local positions = M.shape_positions(warp_settings.floor.shape, size)
  local tiles = {}
  for i = 1, #positions do
    local p = positions[i]
    tiles[i] = {name = tile, position = {p[1] + base.x, p[2] + base.y}}
  end
  return tiles
end

function M.generate_surface_rectangle(surface_name, width, height, tile, offset_x, offset_y)
  local base = sp.get_surface_offset(surface_name)
  local x = (offset_x or 0) + base.x
  local y = (offset_y or 0) + base.y
  return tg.generate_rectangle(width, height, tile, x, y)
end

function M.set_ground_tiles(params)
  local size = params.size
  local offset = sp.get_surface_offset(params.surface)

  local minx = params.x + offset.x
  local maxx = params.x + offset.x + size
  local miny = params.y + offset.y
  local maxy = params.y + offset.y + size

  local tiles = {}
  for x = minx, maxx do
    for y = miny, maxy do
      table.insert(tiles, {name = params.tiles, position = {x, y}})
    end
  end
  game.surfaces[params.surface].set_tiles(tiles)
end

function M.refresh_power_and_teleport(dest)
  local dest = dest or storage.warptorio.warp_zone
  storage.warptorio.power_name = storage.warptorio.power_name or shared.power[1]
  local dest_obj = game.surfaces[dest]
  if not dest_obj or not dest_obj.valid then
    log("Warning: refresh_power_and_teleport skipped, surface \"" .. tostring(dest) .. "\" is missing")
    return
  end
  local power_1 = eh.get_or_create(storage.warptorio.power_name, {x = 0, y = 0, surface = dest})
  local power_2 = eh.get_or_create(storage.warptorio.power_name, {x = 0, y = 0, surface = "factory"})
  power_1.minable_flag = false
  power_2.minable_flag = false
  power_1.rotatable = false
  power_2.rotatable = false
  M.set_ground_tiles({x = -1, y = -3, tiles = "green-refined-concrete", surface = dest, size = 1})
  M.set_ground_tiles({x = -1, y = 1, tiles = "green-refined-concrete", surface = "factory", size = 1})
  M.set_ground_tiles({x = -1, y = -3, tiles = "red-refined-concrete", surface = "factory", size = 1})
  M.set_ground_tiles({x = -1, y = 1, tiles = "red-refined-concrete", surface = dest, size = 1})
  M.set_ground_tiles({x = -1, y = -1, tiles = "black-refined-concrete", surface = "factory", size = 1})
  M.set_ground_tiles({x = -1, y = -1, tiles = "black-refined-concrete", surface = dest, size = 1})
  M.set_ground_tiles({y = -1, x = -3, tiles = "hazard-concrete-left", surface = "factory", size = 1})
  M.set_ground_tiles({y = -1, x = 1, tiles = "hazard-concrete-left", surface = "factory", size = 1})

  storage.warptorio.power = storage.warptorio.power or {}
  storage.warptorio.power[1] = power_1
  storage.warptorio.power[2] = power_2
  storage.warptorio.power_unit_number = storage.warptorio.power_unit_number or {}
  storage.warptorio.power_unit_number[1] = power_1.unit_number
  storage.warptorio.power_unit_number[2] = power_2.unit_number

  if storage.warptorio.biochamber_level then
    local power_3 = eh.get_or_create(storage.warptorio.power_name, {x = 0, y = 0, surface = "garden"})
    power_3.minable_flag = false
    power_3.rotatable = false
    storage.warptorio.power[3] = power_3
    storage.warptorio.power_unit_number[3] = power_3.unit_number
    M.set_ground_tiles({y = -1, x = -3, tiles = "blue-refined-concrete", surface = "factory", size = 1})
    M.set_ground_tiles({y = -1, x = 1, tiles = "red-refined-concrete", surface = "factory", size = 1})
    M.set_ground_tiles({y = -1, x = -3, tiles = "red-refined-concrete", surface = "garden", size = 1})
    M.set_ground_tiles({y = -1, x = 1, tiles = "blue-refined-concrete", surface = "garden", size = 1})
  end

  local connects = {defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}
  for i, v in ipairs(connects) do
    local color = v
    local connector1 = storage.warptorio.power[1].get_wire_connector(v, true)
    local connector2 = storage.warptorio.power[2].get_wire_connector(v, true)
    connector1.connect_to(connector2, false, defines.wire_origin.script)
    if storage.warptorio.biochamber_level then
      local connector3 = storage.warptorio.power[3].get_wire_connector(v, true)
      connector1.connect_to(connector3, false, defines.wire_origin.script)
    end
  end

  local t_surface = game.surfaces[dest]
  if t_surface and t_surface.valid then
    for _, c in pairs(t_surface.find_entities_filtered{name = shared.container}) do
      if c.valid then c.destroy() end
    end
  end

  if storage.warptorio.container_left_enabled then
    local container = eh.get_or_create(shared.container, {x = -2, y = 0, surface = dest})
    local inventory = container.get_inventory(defines.inventory.chest)
    if inventory.get_item_count(shared.container) == 0 then
      container.insert({name = shared.container, count = 1})
    end
    container.minable_flag = false
    container.rotatable = false
  end
  if storage.warptorio.container_right_enabled then
    local container = eh.get_or_create(shared.container, {x = 2, y = 0, surface = dest})
    local inventory = container.get_inventory(defines.inventory.chest)
    if inventory.get_item_count(shared.container) == 0 then
      container.insert({name = shared.container, count = 1})
    end
    container.minable_flag = false
    container.rotatable = false
  end

  teleporter_visualize.refresh()
end

function M.create_void_platform(surface, delete_entities, tile, multiplier)
  local tile = tile or "out-of-map"
  local multiplier = multiplier or 1
  if storage.warptorio.ground_level == 0 then return end
  local level = storage.warptorio.ground_level
  local platform = warp_settings.floor.levels[level]

  local tiles = M.generate_ground_shape(surface, platform * 2 * multiplier, tile)
  game.surfaces[surface].set_tiles(tiles)

  if delete_entities then
    local area = sp.translate_surface_area(surface, nil, platform)
    local entities = game.surfaces[surface].find_entities_filtered{
      area = area, force = "player"}
    for i, v in ipairs(entities) do
      v.destroy({raise_destroy = true})
    end
  end
end

function M.set_hidden_tiles(surface, tile)
  local tile = tile or nil
  local level = storage.warptorio.ground_level
  local platform = warp_settings.floor.levels[level]

  local width = platform * 2
  local height = platform * 2
  local half_width = math.floor(width / 2)
  local half_height = math.floor(height / 2)
  local offset = sp.get_surface_offset(surface)

  for y = -half_height, math.ceil(height / 2) - 1 do
    for x = -half_width, math.ceil(width / 2) - 1 do
      game.surfaces[surface].set_hidden_tile({x + offset.x, y + offset.y}, nil)
    end
  end
end

function M.remove_resources(surface)
  if storage.warptorio.ground_level == 0 then return end
  local level = storage.warptorio.ground_level
  local platform = warp_settings.floor.levels[level]

  local area = sp.translate_surface_area(surface, nil, platform)
  local surface_obj = game.surfaces[surface]
  if not surface_obj or not surface_obj.valid then return end
  local resources = surface_obj.find_entities_filtered{area = area, type = "resource"}
  for i, v in ipairs(resources) do
    v.destroy()
  end
end

function M.remove_recipes(surface)
  if storage.warptorio.ground_level == 0 then return end
  local level = storage.warptorio.ground_level
  local platform = warp_settings.floor.levels[level]

  local area = sp.translate_surface_area(surface, nil, platform)
  local surface_obj = game.surfaces[surface]
  if not surface_obj or not surface_obj.valid then return end
  local entities = surface_obj.find_entities_filtered{area = area, type = "assembling-machine"}
  for i, v in ipairs(entities) do
    local recipe, quality = v.get_recipe()
    if recipe and recipe.prototype.surface_conditions then
      for a, b in ipairs(recipe.prototype.surface_conditions) do
        local value = game.surfaces[surface].get_property(b.property)
        if value < b.min or value > b.max then
          v.set_recipe()
        end
      end
    end
  end
end

function M.update_factory_platform(e)
  local level = storage.warptorio.ground_level
  if e then
    local parts = util.mysplit(e, "-")
    level = tonumber(parts[#parts])
  end

  local platform = warp_settings.factory.levels[level]
  local tiles = {}

  if warp_settings.factory.shape == "ellipse" then
    tiles = tg.generate_ellipse(platform.width, platform.height, shared.tiles.factory)
  elseif warp_settings.factory.shape == "hexagon" then
    tiles = tg.generate_hexagon(platform.width * 0.62, shared.tiles.factory)
  else
    tiles = tg.generate_cross(platform.width, platform.height, platform.arm)
  end

  game.surfaces["factory"].set_tiles(tiles)
  storage.warptorio.factory_level = level

  if level == 1 and platform.width == 10 then
    local tiles = tg.generate_rectangle((platform.width * 2) - 4, (platform.height * 2) - 4, "hazard-concrete-left")
    game.surfaces["factory"].set_tiles(tiles)
    local tiles = tg.generate_rectangle((platform.width * 2) - 8, (platform.height * 2) - 4, shared.tiles.factory)
    game.surfaces["factory"].set_tiles(tiles)
    local tiles = tg.generate_rectangle((platform.width * 2) - 4, (platform.height * 2) - 8, shared.tiles.factory)
    game.surfaces["factory"].set_tiles(tiles)
  elseif level == 2 then
    game.print({"warptorio.help-text-2", warp_settings.trigger_research})
  end

  M.set_ground_tiles({y = -1, x = -6, tiles = "hazard-concrete-left", surface = "factory", size = 1})
  M.set_ground_tiles({x = -1, y = -6, tiles = "hazard-concrete-left", surface = "factory", size = 1})
  M.set_ground_tiles({x = -1, y = 4, tiles = "hazard-concrete-left", surface = "factory", size = 1})

  if storage.warptorio.factory_level > 0 then
    M.refresh_power_and_teleport()
  end
end

function M.update_biochamber_platform(e)
  local level = storage.warptorio.biochamber_level or 1
  if e then
    local parts = util.mysplit(e, "-")
    level = tonumber(parts[#parts])
  end

  if level == 3 then
    level = game.forces["player"].technologies[e].level - 1
  end

  local platform = {
    width = warp_settings.garden.platform.width,
    height = warp_settings.garden.platform.height,
    offset_x = warp_settings.garden.platform.width * (level - 1),
    offset_y = 0,
    yumako = level,
    jellynut = level
  }

  if not game.surfaces["garden"] then
    local surface = surface_creation.new_random_surface("garden")
    local size = 10
    surface.create_global_electric_network()
    surface.always_day = true
    surface.request_to_generate_chunks({0, 0}, size)
    surface.force_generate_chunk_requests()
  end

  local tiles = tg.generate_rectangle(platform.width, platform.height, shared.tiles.factory, platform.offset_x, platform.offset_y)
  game.surfaces["garden"].set_tiles(tiles)

  M.set_ground_tiles({y = -1, x = -6, tiles = "hazard-concrete-left", surface = "garden", size = 1})
  storage.warptorio.biochamber_level = level

  do
    local center_y = warp_settings.garden.yumako.y + warp_settings.garden.yumako.offset
    local center_x = warp_settings.garden.yumako.x * (platform.yumako - 1)
    for _, part in ipairs(warp_settings.garden.yumako.parts) do
      local x = center_x
      local y = center_y
      x = x + (part.x and part.x or 0)
      y = y + (part.y and part.y or 0)
      local tiles = tg.generate_rectangle(part.width, part.height, part.tile, x, y)
      game.surfaces["garden"].set_tiles(tiles)
    end
  end

  do
    local center_y = warp_settings.garden.jellynut.y + warp_settings.garden.jellynut.offset
    local center_x = warp_settings.garden.jellynut.x * (platform.jellynut - 1)
    for _, part in ipairs(warp_settings.garden.jellynut.parts) do
      local x = center_x
      local y = center_y
      x = x + (part.x and part.x or 0)
      y = y + (part.y and part.y or 0)
      local tiles = tg.generate_rectangle(part.width, part.height, part.tile, x, y)
      game.surfaces["garden"].set_tiles(tiles)
    end
  end

  belt_system.update_belt_biochamber()
  M.refresh_power_and_teleport()

  if level == 1 then
    local container = eh.get_or_create(shared.container, {x = 5, y = 0, surface = "garden"})
    container.minable_flag = false
    container.rotatable = false
  end
end

function M.update_reactor_platform(e)
  local level = game.forces["player"].technologies[e].level

  local platform = {
    width = warp_settings.garden.platform.width,
    height = warp_settings.garden.platform.height,
    offset_x = warp_settings.garden.platform.width * (level - 1),
    offset_y = 0,
    yumako = level,
    jellynut = level
  }

  if not game.surfaces["garden"] then
    local surface = surface_creation.new_random_surface("garden")
    local size = 10
    surface.create_global_electric_network()
    surface.always_day = true
    surface.request_to_generate_chunks({0, 0}, size)
    surface.force_generate_chunk_requests()
  end

  local tiles = tg.generate_rectangle(platform.width, platform.height, shared.tiles.factory, -platform.offset_x, -platform.offset_y)
  game.surfaces["garden"].set_tiles(tiles)
end

function M.update_ground_platform(e)
  local previous_level = storage.warptorio.ground_level
  local level = storage.warptorio.ground_level
  local dest = storage.warptorio.warp_zone
  if storage.warptorio.teleporting then
    dest = "warp-space-transition"
  end

  if e then
    local parts = util.mysplit(e, "-")
    level = tonumber(parts[#parts])
    if level == 1 then
      M.create_void_platform(dest)
    end
  end

  local platform = warp_settings.floor.levels[level]

  storage.warptorio.ground_level = level
  storage.warptorio.ground_size = platform * 2

  local mode = (previous_level == level) and "repair" or "expand"
  local offset = sp.get_surface_offset(dest)
  local center = {x = offset.x + 0.5, y = offset.y + 0.5}

  if storage.warptorio.platform_rebuild_queue then
    storage.warptorio.platform_rebuild_queue = nil
  end

  game.print({"warptorio.platform-animation-starting"})

  if mode == "repair" then
    local new_tiles = M.generate_ground_shape(dest, platform * 2, shared.tiles.ground)
    platform_animation.start_gradual_repair(dest, new_tiles, center)
  else
    local tiles = M.generate_ground_shape(dest, platform * 2, shared.tiles.ground)
    game.surfaces[dest].set_tiles(tiles)
    local old_tiles = {}
    if previous_level and previous_level > 0 then
      local old_size = warp_settings.floor.levels[previous_level] * 2
      old_tiles = M.generate_ground_shape(dest, old_size, shared.tiles.ground)
    end
    local new_tiles = M.generate_ground_shape(dest, platform * 2, shared.tiles.ground)
    platform_animation.animate_ground_platform(
      game.surfaces[dest],
      old_tiles,
      new_tiles,
      center,
      mode
    )
  end

  M.set_ground_tiles({x = -1, y = -6, tiles = "hazard-concrete-left", surface = dest, size = 1})
  M.set_ground_tiles({x = -1, y = 4, tiles = "hazard-concrete-left", surface = dest, size = 1})

  if level == 1 then
    local tiles = M.generate_surface_rectangle(dest, 2, 6, "hazard-concrete-left")
    game.surfaces[dest].set_tiles(tiles)
  end

  if not storage.warptorio.container_left_enabled then
    local tiles = M.generate_surface_rectangle(dest, 2, 2, "hazard-concrete-left", -2)
    game.surfaces[dest].set_tiles(tiles)
  end

  if storage.warptorio.factory_level > 0 then
    M.refresh_power_and_teleport()
  end
end

return M
