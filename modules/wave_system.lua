local shared = require("shared")
local sp = require("modules.surface_position")
local events = require("modules.events")
local warp_settings = require("internal_settings")

local M = {}

function M.get_evolution_factor()
  local settings = warp_settings.biter.evolution or {}
  local evolution = settings.base or 0
  local researches = settings.researches or {}
  local technologies = game.forces["player"].technologies

  for _, research in ipairs(researches) do
    local tech = technologies[research.name]
    if tech and tech.researched then
      evolution = research.factor or evolution
    end
  end

  if evolution < 0 then evolution = 0 end
  if evolution > 1 then evolution = 1 end
  return evolution
end

function M.choose_quality(index)
  if not script.active_mods["quality"] then
    return "normal"
  end
  if game.forces["player"].current_research and game.forces["player"].current_research.name == shared.techs.end_win then
    return "warp"
  end
  local evolution = M.get_evolution_factor()
  if evolution < warp_settings.biter.quality_evolution then
    storage.warptorio.last_normal = index
    return "normal"
  end
  local start = storage.warptorio.last_normal or 400
  local step = index - start
  step = math.ceil(step / warp_settings.biter.quality_step)
  if step < 1 then step = 1 end
  if step > #warp_settings.biter.quality then
    step = #warp_settings.biter.quality
  end
  return warp_settings.biter.quality[step]
end

function M.replace_with_high_quality(old_entity, strquality)
  local name = old_entity.name
  local surface = old_entity.surface
  local position = old_entity.position
  local force = old_entity.force
  old_entity.destroy({raise_destroy = true})
  surface.create_entity{
    name = name,
    position = position,
    force = force,
    quality = strquality
  }
end

function M.replace_common(entity)
  if entity.force.name ~= "enemy" then return end
  local evolution = M.get_evolution_factor()
  if evolution < warp_settings.biter.quality_evolution then
    return
  end
  local types = {
    "unit", "spider-unit", "turret",
  }
  local work = false
  for _, v in ipairs(types) do
    if entity.type == v then
      work = true
    end
  end
  if not work then return end
  local quality = M.choose_quality(storage.warporio.index)
  if (quality ~= "normal") then
    M.replace_with_high_quality(entity, quality)
  end
end

function M.spawn_boss_check()
  if storage.warptorio.wave_index % 10 == 0 then
    return true
  end
  if storage.warptorio.wave_index > warp_settings.biter.wave_change_max then
    return true
  end
  if storage.warptorio.wave_index > warp_settings.biter.wave_change_index then
    local rand = math.random()
    if rand > warp_settings.biter.wave_change_chance then return true end
  end
  return false
end

function M.create_angry_biters(biter_type, number, surface, quality, target)
  local target = target or {x = 0, y = 0}
  if surface == "space" then
    M.create_asteroids(number, surface)
    return
  end
  local quality = quality or "normal"
  if storage.warptorio.void then return end

  local angle = math.random(0, 2 * math.pi)
  local level = storage.warptorio.ground_level > 0 and storage.warptorio.ground_level or 1
  local dist = warp_settings.floor.levels[level]
  local range = 300
  local offset = sp.get_surface_offset(surface)
  local center = {x = offset.x + (target.x or 0), y = offset.y + (target.y or 0)}
  local x = center.x + math.cos(angle) * (dist + range)
  local y = center.y + math.sin(angle) * (dist + range)

  local unit_group = game.surfaces[surface].create_unit_group({position = {x = x, y = y}, force = "enemy"})

  for j = 1, number do
    local pos = game.surfaces[surface].find_non_colliding_position(biter_type, {x, y}, 0, 2, false) or {x, y}
    local angry_bitter = game.surfaces[surface].create_entity{
      name = biter_type,
      position = pos,
      quality = quality}
    unit_group.add_member(angry_bitter)
  end

  unit_group.set_command({
    type = defines.command.attack_area,
    destination = {
      x = center.x,
      y = center.y
    },
    radius = dist
  })
  unit_group.start_moving()
end

function M.create_angry_boss(biter_type, number, surface, quality, target)
  local target = target or {x = 0, y = 0}
  local quality = quality or "normal"
  if storage.warptorio.void then return end

  local angle = math.random(0, 2 * math.pi)
  local level = storage.warptorio.ground_level > 0 and storage.warptorio.ground_level or 1
  local dist = warp_settings.floor.levels[level]
  local range = 125
  local offset = sp.get_surface_offset(surface)
  local center = {x = offset.x + (target.x or 0), y = offset.y + (target.y or 0)}
  local x = center.x + math.cos(angle) * (dist + range)
  local y = center.y + math.sin(angle) * (dist + range)
  local dx = center.x - x
  local dy = center.y - y
  local four_directions = {
    north = defines.direction.north,
    east  = defines.direction.east,
    south = defines.direction.south,
    west  = defines.direction.west,
  }
  local facing
  if math.abs(dx) > math.abs(dy) then
    facing = dx > 0 and four_directions.east or four_directions.west
  else
    facing = dy > 0 and four_directions.south or four_directions.north
  end

  for j = 1, number do
    local x = center.x + math.cos(angle) * (dist + range)
    local y = center.y + math.sin(angle) * (dist + range)
    local pos = game.surfaces[surface].find_non_colliding_position(biter_type, {x, y}, 0, 2, false) or {x, y}
    game.surfaces[surface].create_entity{
      name = biter_type,
      position = pos,
      direction = facing,
      quality = quality}
  end

  game.surfaces[surface].set_multi_command{
    command = {
      type = defines.command.attack_area,
      destination = {
        x = center.x + math.cos(angle) * dist,
        y = center.y + math.sin(angle) * (dist + range)
      },
      radius = dist,
    },
    unit_count = range
  }
end

function M.create_asteroids(amount, surface)
  local int_amount = math.floor(amount * warp_settings.space.multiplier)
  if int_amount == 0 then
    return
  end
  local level = storage.warptorio.ground_level
  local size = warp_settings.floor.levels[level]
  local evolution = game.forces["enemy"].get_evolution_factor(storage.warptorio.warp_zone)

  local function roll_position()
    local x = 0
    local y = 0
    while x == 0 and y == 0 do
      x = math.random(size * 4, size * 8) * math.random(-1, 1)
      y = math.random(size * 4, size * 8) * math.random(-1, 1)
    end
    if x == 0 then
      x = math.random(-size * 2, size * 2)
    end
    if y == 0 then
      y = math.random(-size * 2, size * 2)
    end
    return x, y
  end

  for i, v in ipairs(warp_settings.space.tresholds) do
    if v < evolution then
      for _ = 1, int_amount do
        local x, y = roll_position()
        local length = math.sqrt(x * x + y * y)
        local speed = warp_settings.space.speed
        local velocity = {x = 0, y = 0}
        if length > 0 then
          velocity = {x = -x / length * speed, y = -y / length * speed}
        end
        local index = math.random(1, #warp_settings.space.asteroids[i])
        local asteroid = warp_settings.space.asteroids[i][index]
        game.surfaces[surface].create_entity{
          name = asteroid,
          position = {x, y},
          velocity = velocity,
          target = {0, 0},
          force = "enemy"}
      end
    end
  end
end

M.transition_asteroid_names = {}
do
  local seen = {}
  for _, tier in ipairs(warp_settings.space.asteroids) do
    for _, name in ipairs(tier) do
      if not seen[name] then
        seen[name] = true
        M.transition_asteroid_names[#M.transition_asteroid_names + 1] = name
      end
    end
  end
end

function M.clear_transition_asteroids()
  if #M.transition_asteroid_names == 0 then
    return
  end
  local surface = game.surfaces["warp-space-transition"]
  if not surface or not surface.valid then
    return
  end
  local found = surface.find_entities_filtered{name = M.transition_asteroid_names}
  for _, asteroid in ipairs(found) do
    if asteroid.valid then
      asteroid.destroy()
    end
  end
end

function M.technology_check()
  if storage.warptorio and storage.warptorio.transition_timer and storage.warptorio.transition_timer > 60 then return false end
  if not game.forces["player"].current_research then return false end
  if game.forces["player"].current_research.name == shared.techs.end_prepare or game.forces["player"].current_research.name == shared.techs.end_win then
    return true
  end
  return false
end

function M.check_wave()
  if not storage.warporio then storage.warporio = {} end
  if not storage.warporio.index then storage.warporio.index = 0 end
  if not game.forces["player"].technologies["warp-ground-platform-1"].researched
     and game.forces["player"].technologies[warp_settings.trigger_wave].researched == false
     and storage.warporio.index == 0 then
    storage.warptorio.wave_time = warp_settings.time.grace_period
  end
  local limit = storage.warptorio.wave_time

  if M.technology_check() and limit > warp_settings.biter.min then
    storage.warptorio.wave_time = warp_settings.biter.min
  end

  if not game.surfaces[storage.warptorio.warp_zone] then
    game.print("ERROR: Surface not found | " .. storage.warptorio.warp_zone)
    return
  end

  local biter_index = 1
  local evolution = game.forces["enemy"].get_evolution_factor(storage.warptorio.warp_zone)
  for i, v in ipairs(warp_settings.biter.tresholds) do
    if v < evolution then
      biter_index = i
      if game.forces["enemy"].technologies["warp-weapons-" .. biter_index] then
        if storage.warporio.index > 50 and warp_settings.dmg_research then
          game.forces["enemy"].technologies["warp-weapons-" .. biter_index].researched = true
        else
          game.forces["enemy"].technologies["warp-weapons-" .. biter_index].researched = false
        end
      end
    end
  end

  local spawn_boss = M.spawn_boss_check()
  local quality = M.choose_quality(storage.warporio.index)

  if limit <= 0 then
    local wave_index = storage.warptorio.wave_index + 1
    local amount = warp_settings.biter.wave_amount * math.floor((wave_index) * warp_settings.biter.wave_increase)
    for i = 1, amount do
      if M.technology_check() or spawn_boss then break end
      local biter_group = warp_settings.biter.entity_type["default"]
      if storage.warptorio.surface_name and warp_settings.biter.entity_type[storage.warptorio.surface_name] then
        biter_group = warp_settings.biter.entity_type[storage.warptorio.surface_name]
      end

      local biter_type = biter_group[biter_index][math.random(1, #biter_group[biter_index])]
      local angry_amount = math.random(warp_settings.biter.amount / 2, warp_settings.biter.amount)

      M.create_angry_biters(biter_type, angry_amount, storage.warptorio.warp_zone, quality)
    end
    if spawn_boss or M.technology_check() then
      if storage.warptorio.wave_index == 10 and (not M.technology_check()) then
        game.print({"warptorio.boss-warning"}, {volume_modifier = 0})
        game.play_sound({path = "boss-spawn"})
      end
      local max = math.ceil(storage.warptorio.wave_index / 10)
      local max = max < warp_settings.biter.max_bosses and max or warp_settings.biter.max_bosses
      for _ = 1, max do
        local biter_group = warp_settings.biter.entity_type["boss"][biter_index]
        local biter_type = biter_group[math.random(1, #biter_group)]
        if string.match(biter_type, "demolisher") then
          M.create_angry_boss(biter_type, math.random(1, max), storage.warptorio.warp_zone, quality)
        else
          M.create_angry_biters(biter_type, math.random(1, max), storage.warptorio.warp_zone, quality)
        end
        if not M.technology_check() then break end
      end
      events.raise(shared.events.boss_spawned, {
        index = storage.warptorio.wave_index,
        count = max,
        quality = quality,
        surface = storage.warptorio.warp_zone,
      })
    end
    storage.warptorio.wave_index = storage.warptorio.wave_index + 1
    events.raise(shared.events.wave_spawned, {
      index = storage.warptorio.wave_index,
      amount = amount,
      boss = spawn_boss,
      quality = quality,
      surface = storage.warptorio.warp_zone,
     })
    if game.forces["player"].current_research and game.forces["player"].current_research.name == shared.techs.end_win then
      if storage.warptorio.wave_index < warp_settings.biter.final_offset then
        storage.warptorio.wave_index = warp_settings.biter.final_offset
      end
    end
    storage.warptorio.wave_time = warp_settings.biter.time - (storage.warptorio.wave_index * warp_settings.biter.change)
    if M.technology_check() then
      storage.warptorio.wave_time = warp_settings.biter.min
    end
    if storage.warptorio.wave_time < warp_settings.biter.min then
      storage.warptorio.wave_time = warp_settings.biter.min
    end
  elseif not storage.warptorio.void and not storage.warptorio.teleporting then
    if not storage.warptorio.wave_paused then
      storage.warptorio.wave_time = storage.warptorio.wave_time - 1 / 60
    end
  end
end

return M
