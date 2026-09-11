local shared = require("shared")
local sp = require("modules.surface_position")
local events = require("modules.events")
local belt_system = require("modules.belt_system")
local player_teleport = require("modules.player_teleport")
local spidertron = require("modules.spidertron")
local surface_creation = require("modules.surface_creation")
local wave_system = require("modules.wave_system")
local platform_builder = require("modules.platform_builder")
local compat_repair_turret = require("modules.compat_repair_turret")
local speech_bubbles = require("modules.speech_bubbles")
local minimap = require("modules.minimap")
local warp_constant_combinator = require("warp_constant_combinator")
local platform_code = require("platforms")
local train_code = require("train")
local game_state = require("modules.game_state")
local util = require("modules.util")
local warp_settings = require("internal_settings")
local fluid_snapshot = require("modules.fluid_snapshot")

local M = {}

function M.next_warp_zone_prepare(forced, go_home)
  storage.warptorio.teleporting = true
  if not storage.warporio then storage.warporio = {} end
  if not storage.warporio.index then storage.warporio.index = 0 end

  if storage.warptorio.container and storage.warptorio.container.destroy() then
    local player = game.players[1]
    if player and player.connected then
      speech_bubbles.notify(player, {"warptorio.container-removed"}, 3)
    end
    storage.warptorio.container = nil
  end

  if game.forces["player"].technologies[shared.techs.end_prepare].saved_progress > 0 and game.forces["player"].technologies[shared.techs.end_prepare].researched == false then
    game.print({"warptorio.technology-cheater"})
    game.forces["player"].technologies[shared.techs.end_prepare].saved_progress = 0
  end

  if game.forces["player"].technologies[shared.techs.end_win].saved_progress > 0 and game.forces["player"].technologies[shared.techs.end_win].researched == false then
    game.print({"warptorio.technology-cheater"})
    game.forces["player"].technologies[shared.techs.end_win].saved_progress = 0
  end

  if wave_system.technology_check() then
    game.forces["player"].research_progress = 0
  end

  storage.warporio.index = storage.warporio.index + 1
  storage.warptorio.time_passed = 0
  local name = "warpzone_" .. storage.warporio.index
  local surface = nil
  if forced == "nauvis" then
    if go_home then
      surface = surface_creation.new_random_surface("home")
    else
      storage.warptorio.previous_surface_2 = nil
      storage.warptorio.previous_surface_1 = nil
      surface = surface_creation.new_random_surface(name)
    end
  elseif forced == "space" then
    surface = surface_creation.new_random_surface("space")
    storage.warptorio.previous_surface_2 = nil
    storage.warptorio.previous_surface_1 = nil
  elseif forced then
    storage.warptorio.planet_next = forced
    storage.warptorio.previous_surface_2 = nil
    storage.warptorio.previous_surface_1 = nil
    surface = surface_creation.new_random_surface(name)
  else
    local num = math.random()
    if num < warp_settings.stuck_in_space_chance and not game.surfaces["space"] then
      surface = surface_creation.new_random_surface("space")
      storage.warptorio.previous_surface_2 = nil
      storage.warptorio.previous_surface_1 = nil
    elseif num > 1 - warp_settings.going_home_chance and
       storage.warptorio.surface_name ~= "nauvis" and
       storage.warptorio.warp_next ~= "nauvis" and
       storage.warptorio.void ~= true then
      surface = surface_creation.new_random_surface("home")
      storage.warptorio.previous_surface_2 = nil
      storage.warptorio.previous_surface_1 = nil
    else
      surface = surface_creation.new_random_surface(name)
    end
  end
  surface_creation.prepare_surface_spawn(surface, name, not storage.warptorio.void)
  storage.warptorio.previous_surface_wave = storage.warptorio.wave_index
  storage.warptorio.previous_surface_time = storage.warptorio.wave_time
  events.raise(shared.events.warp_started, {
    from_surface = storage.warptorio.surface_name,
    target = surface and surface.name,
    planet = storage.warptorio.planet_next,
    index = storage.warporio.index,
    forced = forced,
  })
end

local function teleport_ground(source, target)
  local level = storage.warptorio.ground_level or 0
  if level == 0 then return end

  local source_obj = game.surfaces[source]
  local target_obj = game.surfaces[target]
  if not source_obj or not source_obj.valid or not target_obj or not target_obj.valid then return end

  local platform = warp_settings.floor.levels[level]
  local source_offset = sp.get_surface_offset(source)
  local dest_offset = sp.get_surface_offset(target)
  local destination_area = sp.translate_surface_area(target, nil, platform)

  local positions = platform_builder.shape_positions(warp_settings.floor.shape, platform * 2)
  local source_ox = source_offset.x
  local source_oy = source_offset.y
  local source_positions = {}
  for i = 1, #positions do
    local p = positions[i]
    source_positions[i] = {p[1] + source_ox, p[2] + source_oy}
  end

  local captured_modes = train_code.capture_clone_states(game.surfaces[source], source_offset)
  local captured_spidertrons = spidertron.capture_spidertron_selections(source, source_offset)

  train_code.freeze_ground_bound_trains(source)

  -- Snapshot fluid contents before clone to prevent mixing and extra fluid generation.
  -- clone_brush rebalances fluids as each entity is cloned, creating duplicates.
  fluid_snapshot.snapshot_fluids(game.surfaces[source], source_offset)

  game.surfaces[source].clone_brush({
    source_offset = {source_offset.x, source_offset.y},
    destination_offset = {dest_offset.x, dest_offset.y},
    source_positions = source_positions,
    destination_surface = target,
    expand_map = true,
    clone_tiles = true,
    clone_entities = true,
    clear_destination_entities = true,
    clear_destination_decoratives = true,
    clone_decoratives = false,
  })

  -- Restore fluids on cloned entities. clone_brush emptied the source before
  -- cloning, so dest entities land empty; write back exactly one copy.
  local snap = fluid_snapshot.get_fluid_snapshot()
  if next(snap) then
    local dest_entities = game.surfaces[target].find_entities_filtered{
      area = destination_area,
      name = storage.warptorio.fluid_entity_types
    }
    for _, e in pairs(dest_entities) do
      if e.valid and e.fluidbox and #e.fluidbox > 0 then
        local rel_x = math.floor((e.position.x - dest_offset.x) * 10 + 0.5) / 10
        local rel_y = math.floor((e.position.y - dest_offset.y) * 10 + 0.5) / 10
        local key = string.format("%.1f,%.1f", rel_x, rel_y)
        local boxes = snap[key]
        if boxes then
          for i, fluid_data in pairs(boxes) do
            if e.fluidbox[i] then
              e.fluidbox[i] = fluid_data
            end
          end
        end
      end
    end
    fluid_snapshot.clear_fluid_snapshot()
  end

  train_code.restore_clone_states(game.surfaces[target], dest_offset, captured_modes)
  util.clean_ground_tiles(target, destination_area, shared)

  local surface_player_list = game.surfaces[target].find_entities_filtered{type = "character", area = destination_area}
  for i, v in ipairs(surface_player_list) do
    v.destroy({raise_destroy = true})
  end

  return captured_spidertrons
end

function M.next_warp_zone_finish()
  local name = storage.warptorio.warp_next
  local surface = game.surfaces[name]
  local keep_time = false
  if storage.warptorio.previous_surface_2 == storage.warptorio.surface_name and
     storage.warptorio.surface_name ~= "nauvis" and
     storage.warptorio.surface_name ~= nil then
    keep_time = true
    game.print({"warptorio.hopping-surfaces"}, {color = {1, 0.25, 0.25}})
  end
  storage.warptorio.previous_surface_2 = storage.warptorio.previous_surface_1
  storage.warptorio.previous_surface_1 = storage.warptorio.surface_name
  surface.force_generate_chunk_requests()

  local source = nil
  if storage.warptorio.force_direct then
    source = storage.warptorio.warp_zone
  elseif storage.warptorio.factory_level >= warp_settings.space.trigger_factory_level and
     warp_settings.space.transition then
    source = "warp-space-transition"
  else
    source = storage.warptorio.warp_zone
  end
  if source == nil then
    game.print("ERORR:Source planet is nil. Something went wrong")
    source = storage.warptorio.warp_zone
  end

  platform_builder.remove_resources(source)
  if warp_settings.reset_recipe then
    platform_builder.remove_recipes(source)
  end
  local source_surface_obj = game.surfaces[source]
  if source_surface_obj and source_surface_obj.valid then
    for _, c in pairs(source_surface_obj.find_entities_filtered{name = shared.container}) do
      if c.valid then c.destroy() end
    end
  end
  storage.warptorio.container = nil
  local captured_spidertrons = teleport_ground(source, name)

  if storage.warptorio.factory_level > 0 then
    player_teleport.teleport_players(source, "factory", true)
  else
    player_teleport.teleport_players(source, name)
  end
  spidertron.restore_spidertron_selections(name, captured_spidertrons)
  if storage.warptorio.factory_level > 0 then
    platform_builder.refresh_power_and_teleport(name)
  end
  train_code.resume_ground_bound_trains()
  train_code.realign_docked_fluid_trains()

  storage.warptorio.wave_index = 0
  storage.warptorio.wave_time = warp_settings.biter.time
  if keep_time then
    storage.warptorio.wave_index = storage.warptorio.previous_surface_wave or 0
    storage.warptorio.wave_time = storage.warptorio.previous_surface_time or warp_settings.biter.time
  end
  local extra_time = false
  for i, v in ipairs(warp_settings.biter.extra_time_planet) do
    if v == storage.warptorio.surface_name then
      extra_time = true
    end
  end
  if extra_time then storage.warptorio.wave_time = storage.warptorio.wave_time + warp_settings.biter.extra_time_amount end
  platform_builder.create_void_platform(source, true)
  if storage.warptorio.old_surface and game.surfaces[storage.warptorio.old_surface] and game.surfaces[storage.warptorio.old_surface].valid then
    compat_repair_turret.destroy_before_clear(game.surfaces[storage.warptorio.old_surface])
    game.delete_surface(storage.warptorio.old_surface)
  end
  storage.warptorio.old_surface = storage.warptorio.warp_zone
  if storage.warptorio.surface_name == "aquilo" then
    storage.warptorio.warp_out = warp_settings.time.warp_out
  else
    storage.warptorio.warp_out = warp_settings.time.warp_out + storage.warporio.index * warp_settings.time.add_per_jump
  end

  local players = game.players
  for i, v in pairs(players) do
    for _, inv_id in pairs({defines.inventory.character_main, defines.inventory.character_trash}) do
      local inventory = v.get_inventory(inv_id)
      if inventory then
        for j = 1, #inventory do
          local stack = inventory[j]
          if stack.valid_for_read and stack.name == shared.container then
            stack.clear()
          end
        end
      end
    end
  end
  game_state.pollution_settings()
  game.forces["enemy"].set_evolution_factor(wave_system.get_evolution_factor(), name)

  if script.active_mods["rso-mod"] then
    remote.call("RSO", "resetGeneration", surface)
  end

  storage.warptorio.warp_zone = surface.name
  local spawn = sp.get_surface_offset(surface.name)
  game.forces.player.set_spawn_position({x = spawn.x, y = spawn.y + 2}, surface)

  if game.forces.player.technologies["warp-biochamber-platform-1"].researched then
    belt_system.update_belt_biochamber()
  end
  belt_system.update_belt()
  if storage.warptorio.factory_level > 0 then
    platform_builder.refresh_power_and_teleport()
  end
  minimap.chart(name)
  if storage.warptorio.factory_level >= warp_settings.space.trigger_factory_level and
     warp_settings.space.transition then
    game.play_sound({path = "warp-end"})
  else
    game.play_sound({path = "warp-start"})
  end
  storage.warptorio.teleporting = false
  wave_system.clear_transition_asteroids()
  platform_code.on_warp(source, name)
  warp_constant_combinator.rescan()
  events.raise(shared.events.warp_finished, {
    surface = name,
    previous_surface = storage.warptorio.previous_surface_1,
    planet = storage.warptorio.planet_next,
    index = storage.warporio.index,
    factory_level = storage.warptorio.factory_level,
  })
end

local function next_warp_zone_space()
  local source = storage.warptorio.warp_zone
  local dest = "warp-space-transition"

  if not game.surfaces[dest] then
    local surface = game.create_surface(dest, surface_creation.space_gen_settings)
    surface.always_day = true
    surface.request_to_generate_chunks({0, 0}, 10)
    surface.force_generate_chunk_requests()
  end

  platform_builder.create_void_platform(dest, true, "empty-space")

  local space_source_surface = game.surfaces[source]
  if space_source_surface and space_source_surface.valid then
    for _, c in pairs(space_source_surface.find_entities_filtered{name = shared.container}) do
      if c.valid then c.destroy() end
    end
  end
  storage.warptorio.container = nil
  local captured_spidertrons = teleport_ground(source, dest)
  warp_constant_combinator.rescan()
  player_teleport.teleport_players(source, "factory", true)
  spidertron.restore_spidertron_selections(dest, captured_spidertrons)
  platform_builder.create_void_platform(source, true)

  local save = storage.warptorio.warp_zone
  storage.warptorio.warp_zone = dest
  platform_builder.refresh_power_and_teleport(dest)
  train_code.resume_ground_bound_trains()
  train_code.realign_docked_fluid_trains()
  belt_system.update_belt()
  storage.warptorio.warp_zone = save

  game.play_sound({path = "warp-start"})
end

function M.next_warp_zone_transition()
  if storage.warptorio.transition_timer < 60 then
    return
  end
  local dest = "warp-space-transition"
  if storage.warptorio.transition_timer % (60 * warp_settings.space.transition_spawn_timer) == 0 then
    wave_system.create_asteroids(warp_settings.space.transition_spawn_amount, dest)
  end
end

function M.force_warp(destination, go_home)
  if destination and destination ~= "nauvis" and destination ~= "void" and destination ~= "space"
     and not game.planets[destination] then
    game.print("ERORR:Unknown force warp destination: " .. tostring(destination))
    return
  end
  if destination == "space" and game.surfaces["space"] and game.surfaces["space"].valid then
    game.print("ERORR:Cannot warp to space: space surface already exists")
    return
  end
  storage.warptorio.warp_out = 0
  storage.warptorio.transition_timer = 0
  storage.warptorio.force_direct = true
  storage.warptorio.clicks_to_teleport = {}
  M.next_warp_zone_prepare(destination, go_home)
  storage.warptorio.transition_timer = -1
  M.next_warp_zone_finish()
  storage.warptorio.force_direct = nil
end

function M.next_warp_zone()
  if storage.warptorio.game_over then return end
  log("[warpcheat] next_warp_zone called")
  storage.warptorio.clicks_to_teleport = {}
  M.next_warp_zone_prepare()
  if storage.warptorio.factory_level >= warp_settings.space.trigger_factory_level and
     warp_settings.space.transition then
    storage.warptorio.transition_timer = math.floor(
      60 * warp_settings.space.time_per_warp * storage.warporio.index)
    next_warp_zone_space()
    return
  end
  storage.warptorio.transition_timer = warp_settings.space.base_time
end

return M
