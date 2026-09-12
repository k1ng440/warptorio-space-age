-- Boss spawning, boss tracking and boss loot drops.
-- Owns the full boss lifecycle: spawn check, spawn, registry of spawned
-- bosses (unit_number -> quality) and loot spilled on death.
local M = {}

local warp_settings = require("internal_settings")

local deps = {}

local function ensure_boss_registry()
  if not storage.warptorio.bosses then storage.warptorio.bosses = {} end
  return storage.warptorio.bosses
end

local module_pool_cache = nil
local function get_module_pool(tier_max)
  if not module_pool_cache then
    module_pool_cache = {normal = {}, uncommon = {}, rare = {}}
    for name, proto in pairs(game.item_prototypes) do
      if proto.type == "module" then
        local tier = tonumber(name:match("-(%d+)$")) or 1
        local bucket = tier <= 1 and "normal" or (tier == 2 and "uncommon" or "rare")
        table.insert(module_pool_cache[bucket], name)
      end
    end
  end
  return module_pool_cache[tier_max] or module_pool_cache.normal
end

local function get_science_pool()
  local packs = {}
  local force = game.forces.player
  for name, proto in pairs(game.item_prototypes) do
    if proto.type == "tool" and proto.subgroup == "science-pack" and name ~= "promethium-science-pack" then
      local recipe = force.recipes[name]
      if recipe and recipe.unlocked then table.insert(packs, name) end
    end
  end
  return packs
end

local function drop_boss_loot(entity, quality)
  if not settings.global["warptorio_boss-loot"].value then return end
  local chance = settings.global["warptorio_boss-loot-chance"].value / 100
  if math.random() > chance then return end
  local max_count = settings.global["warptorio_boss-loot-count"].value
  if max_count < 1 then return end
  local warp_index = (storage.warporio and storage.warporio.index) or 1
  local tier_max = warp_index <= 2 and "normal" or (warp_index <= 4 and "uncommon" or "rare")
  local surface = entity.surface
  local pos = entity.position
  local count = math.random(0, max_count)
  for _ = 1, count do
    local name
    if math.random(2) == 1 then
      local packs = get_science_pool()
      if #packs > 0 then name = packs[math.random(#packs)] end
    end
    if not name then
      local pool = get_module_pool(tier_max)
      if #pool > 0 then name = pool[math.random(#pool)] end
    end
    if name then
      surface.spill_item_stack(pos, {name = name, count = 1, quality = quality}, false, "player", false)
    end
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

function M.create_angry_biters(biter_type,number,surface,quality,target,is_boss)
   local target = target or {x=0,y=0}
   if surface == "space" then
      deps.create_asteroids(number,surface)
      return
   end
   local quality = quality or "normal"
   if storage.warptorio.void then return end
   local surface_player_list = {}

   -- Create attack force for platform
   local angle = math.random(0,2*math.pi)
   local level = storage.warptorio.ground_level > 0 and storage.warptorio.ground_level or 1
   local dist = warp_settings.floor.levels[level]
   local range = 300
   local offset = deps.get_surface_offset(surface)
   local center = {x = offset.x + (target.x or 0), y = offset.y + (target.y or 0)}
   local x = center.x + math.cos(angle)*(dist+range)
   local y = center.y + math.sin(angle)*(dist+range)

   local unit_group = game.surfaces[surface].create_unit_group({ position = {x=x,y=y}, force = "enemy" })

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

   for j = 1,number do

      local pos = game.surfaces[surface].find_non_colliding_position(biter_type, {x,y}, 0, 2, false) or {x,y}

      local angry_bitter = game.surfaces[surface].create_entity{
         name = biter_type,
         position = pos,
         quality = quality}
      if is_boss and angry_bitter and angry_bitter.valid then
         ensure_boss_registry()[angry_bitter.unit_number] = {quality = quality}
      end
      --angry_bitter.autopilot_destination = k.position
      unit_group.add_member(angry_bitter)
   end

   unit_group.set_command({
         type=defines.command.attack_area,
         destination={
            x=center.x,
            y=center.y
         },
         radius=dist
   })
   unit_group.start_moving()
end

function M.create_angry_boss(biter_type,number,surface,quality,target)
  local target = target or {x=0,y=0}
  local quality = quality or "normal"
  if storage.warptorio.void then return end
        local surface_player_list = {}
  for i,v in pairs(game.players) do
    -- Add players to the list
    if v.is_player() and v.connected and v.character and v.character.surface.name == surface then
      table.insert(surface_player_list,v.character)
    end
  end

  -- Create attack force for platform
  local angle = math.random(0,2*math.pi)
  local level = storage.warptorio.ground_level > 0 and storage.warptorio.ground_level or 1
  local dist = warp_settings.floor.levels[level]
  local range = 125
  local offset = deps.get_surface_offset(surface)
  local center = {x = offset.x + (target.x or 0), y = offset.y + (target.y or 0)}
   local x = center.x + math.cos(angle)*(dist+range)
   local y = center.y + math.sin(angle)*(dist+range)
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

        for j = 1,number do
          local x = center.x + math.cos(angle)*(dist+range)
          local y = center.y + math.sin(angle)*(dist+range)
                local pos = game.surfaces[surface].find_non_colliding_position(biter_type, {x,y}, 0, 2, false) or {x,y}

                local angry_bitter = game.surfaces[surface].create_entity{
                   name = biter_type,
                   position = pos,
                   direction=facing,
                   quality=quality }
                if angry_bitter and angry_bitter.valid then
                  ensure_boss_registry()[angry_bitter.unit_number] = {quality = quality}
                end
        end

  game.surfaces[surface].set_multi_command{
    command={
      type=defines.command.attack_area,
      destination={
        x=center.x + math.cos(angle)*dist,
        y=center.y + math.sin(angle)*(dist+range)
      },
      radius=dist,
    },
    unit_count=range
  }
end

-- Register an existing entity as boss (e.g. after a quality replacement
-- recreates it under a new unit number).
function M.register(entity, quality)
  if entity and entity.valid then
    ensure_boss_registry()[entity.unit_number] = {quality = quality}
  end
end

-- Called from the on_entity_died handler; drops loot if the entity was a boss.
function M.on_boss_died(entity)
  if not storage.warptorio or not storage.warptorio.bosses then return end
  local boss = storage.warptorio.bosses[entity.unit_number]
  if boss then
    storage.warptorio.bosses[entity.unit_number] = nil
    drop_boss_loot(entity, boss.quality)
  end
end

-- Called from script_raised_destroy; removes stale registry entries.
function M.unregister(entity)
  if storage.warptorio and storage.warptorio.bosses and entity.unit_number then
    storage.warptorio.bosses[entity.unit_number] = nil
  end
end

function M.init(d)
  deps = d or {}
end

return M
