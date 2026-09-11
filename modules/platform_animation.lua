local shared = require("shared")

local platform_animation = {}

local function position_key(x, y)
  return x .. "," .. y
end

local warp_settings = require("internal_settings")
local repair_speed_config = warp_settings.repair.batch_configs[warp_settings.repair.speed] or warp_settings.repair.batch_configs.normal
local repair_batch_size = repair_speed_config.batch
local repair_interval = repair_speed_config.interval
local expand_lock_ticks = warp_settings.animation.expand_lock_ticks
local anim_offset_x = warp_settings.animation.build_anim_offset.x
local anim_offset_y = warp_settings.animation.build_anim_offset.y

local function platform_tile_names()
  local names = {[warp_settings.tiles.ground] = true}
  local proto = prototypes and prototypes.tile and prototypes.tile[warp_settings.tiles.ground]
  if proto then
    if proto.frozen_variant then
      names[proto.frozen_variant.name] = true
    end
    if proto.thawed_variant then
      names[proto.thawed_variant.name] = true
    end
  end
  return names
end

local neighbours = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function tile_x(tile)
  if tile.position.x ~= nil then
    return tile.position.x
  end
  return tile.position[1]
end

local function tile_y(tile)
  if tile.position.y ~= nil then
    return tile.position.y
  end
  return tile.position[2]
end

local function tile_position_ok(tile)
  return tile and tile.position and tile_x(tile) and tile_y(tile)
end

local function parse_key(key)
  local x, y = key:match("([^,]+),([^,]+)")
  return tonumber(x), tonumber(y)
end

local function is_missing(surface, x, y, names)
  return not names[surface.get_tile(x, y).name]
end

local function has_platform_neighbour(surface, x, y, names)
  for _, d in ipairs(neighbours) do
    if names[surface.get_tile(x + d[1], y + d[2]).name] then
      return true
    end
  end
  return false
end

function platform_animation.is_active()
  if not storage.warptorio then
    return false
  end
  if storage.warptorio.platform_rebuild_queue then
    return true
  end
  if storage.warptorio.platform_expand_queue then
    return true
  end
  if storage.warptorio.platform_animation_active_until and
     game.tick < storage.warptorio.platform_animation_active_until then
    return true
  end
  return false
end

function platform_animation.start_gradual_repair(surface_name, tiles, center)
  if not storage.warptorio then
    return
  end
  if type(tiles) ~= "table" or #tiles == 0 then
    return
  end

  local surface = game.surfaces[surface_name]
  if not surface or not surface.valid then
    return
  end

  local names = platform_tile_names()

  local target_set = {}
  local tile_by_key = {}
  for _, tile in ipairs(tiles) do
    if tile_position_ok(tile) then
      local x = tile_x(tile)
      local y = tile_y(tile)
      local key = position_key(x, y)
      target_set[key] = true
      tile_by_key[key] = tile
    end
  end

  local edge_set = {}
  local edge_list = {}
  for key, _ in pairs(target_set) do
    local x, y = parse_key(key)
    if is_missing(surface, x, y, names) and has_platform_neighbour(surface, x, y, names) then
      edge_set[key] = true
      table.insert(edge_list, key)
    end
  end

  if #edge_list == 0 then
    return
  end

  if storage.warptorio.platform_expand_queue then
    storage.warptorio.platform_expand_queue = nil
  end

  storage.warptorio.platform_rebuild_queue = {
    surface_name = surface_name,
    center = center,
    platform_tile_names = names,
    target_set = target_set,
    tile_by_key = tile_by_key,
    edge_set = edge_set,
    edge_list = edge_list,
  }
  game.print("Repair queued: " .. #edge_list .. " edge tiles on " .. surface_name)
end

local function process_expand_queue()
  local warptorio = storage.warptorio
  if not warptorio then
    return
  end
  local eq = warptorio.platform_expand_queue
  if not eq then
    return
  end
  local surface = game.surfaces[eq.surface_name]
  if not surface or not surface.valid then
    warptorio.platform_expand_queue = nil
    return
  end

  eq.pending = eq.pending or {}

  -- tiles whose build animation finished become visible now
  local tiles_to_place = {}
  for i = #eq.pending, 1, -1 do
    local pending = eq.pending[i]
    if not pending.entity.valid then
      tiles_to_place[#tiles_to_place + 1] = pending.pos
      table.remove(eq.pending, i)
    end
  end
  if #tiles_to_place > 0 then
    for _, pos in ipairs(tiles_to_place) do
      surface.set_tiles{{name = eq.tile_name, position = pos}}
    end
  end

  -- start new build animations on this tick
  local spawned = 0
  while eq.next <= #eq.tiles and spawned < eq.per_tick do
    local t = eq.tiles[eq.next]
    eq.next = eq.next + 1
    local anim = surface.create_entity{
      name = shared.platform_build_anim,
      position = {x = t.x + 0.5 + anim_offset_x, y = t.y + 0.5 + anim_offset_y}
    }
    if anim then
      eq.pending[#eq.pending + 1] = {entity = anim, pos = {x = t.x, y = t.y}}
    else
      surface.set_tiles{{name = eq.tile_name, position = {x = t.x, y = t.y}}}
    end
    spawned = spawned + 1
  end

  if eq.next > #eq.tiles and #eq.pending == 0 then
    -- flush any tiles skipped by the animation cap so no void remains
    if eq.rest and #eq.rest > 0 then
      for _, t in ipairs(eq.rest) do
        surface.set_tiles{{name = eq.tile_name, position = {x = t.x, y = t.y}}}
      end
      eq.rest = nil
    end
    local dest = eq.marker_dest
    local level = eq.marker_level
    warptorio.platform_expand_queue = nil
    storage.warptorio.platform_animation_active_until = game.tick + 15
    if dest and level then
      local pb = require("platform_builder")
      pb.apply_ground_markers(dest, level)
    end
  end
end

function platform_animation.on_tick()
  process_expand_queue()
  local queue = storage.warptorio and storage.warptorio.platform_rebuild_queue
  if not queue then
    return
  end

  local surface = game.surfaces[queue.surface_name]
  if not surface or not surface.valid then
    game.print("Repair aborted: surface " .. queue.surface_name .. " invalid")
    storage.warptorio.platform_rebuild_queue = nil
    return
  end

  queue.pending = queue.pending or {}
  local batch = {}
  local placed_keys = {}

  -- tiles whose build animation just finished become visible now
  local names = queue.platform_tile_names

  for i = #queue.pending, 1, -1 do
    local pending = queue.pending[i]
    if not pending.entity.valid then
      table.insert(batch, pending.tile)
      table.insert(placed_keys, pending.key)
      table.remove(queue.pending, i)
    end
  end

  if #batch > 0 then
    surface.set_tiles(batch)
  end

  -- start new build animations on this tick
  if game.tick % repair_interval == 0 then
    local spawned = 0
    while spawned < repair_batch_size and #queue.edge_list > 0 do
      local idx = math.random(#queue.edge_list)
      local key = queue.edge_list[idx]
      queue.edge_list[idx] = queue.edge_list[#queue.edge_list]
      table.remove(queue.edge_list)
      queue.edge_set[key] = nil

      local x, y = parse_key(key)
      if queue.target_set[key] and is_missing(surface, x, y, names) then
        local tile = queue.tile_by_key[key]
        local anim = surface.create_entity{
          name = shared.platform_build_anim,
          position = {x = tile_x(tile) + 0.5 + anim_offset_x, y = tile_y(tile) + 0.5 + anim_offset_y}
        }
        table.insert(queue.pending, {entity = anim, tile = tile, key = key})
        spawned = spawned + 1
      end
    end
  end

  for _, key in ipairs(placed_keys) do
    queue.target_set[key] = nil
    local x, y = parse_key(key)
    for _, d in ipairs(neighbours) do
      local nx, ny = x + d[1], y + d[2]
      local nkey = position_key(nx, ny)
      if queue.target_set[nkey] and not queue.edge_set[nkey] and
         is_missing(surface, nx, ny, names) and has_platform_neighbour(surface, nx, ny, names) then
        queue.edge_set[nkey] = true
        table.insert(queue.edge_list, nkey)
      end
    end
  end

  if #queue.edge_list == 0 and #queue.pending == 0 then
    storage.warptorio.platform_rebuild_queue = nil
  end
end

local MAX_EXPAND_ANIMS = 2200

local function ring_sort_compare(a, b)
  return a.d < b.d
end

function platform_animation.animate_ground_platform(surface, old_tiles, new_tiles, center, mode, marker_dest, marker_level)
  if not surface or not surface.valid then
    return
  end
  if not center or center.x == nil or center.y == nil then
    return
  end
  if type(new_tiles) ~= "table" then
    return
  end
  if mode ~= "expand" then
    return
  end

  if storage.warptorio.platform_expand_queue then
    storage.warptorio.platform_expand_queue = nil
  end

  local names = platform_tile_names()
  local cx, cy = center.x, center.y
  local band = {}
  for _, tile in ipairs(new_tiles) do
    if tile_position_ok(tile) then
      local x = tile_x(tile)
      local y = tile_y(tile)
      if is_missing(surface, x, y, names) then
        band[#band + 1] = {
          x = x,
          y = y,
          d = math.max(math.abs(x - cx), math.abs(y - cy)),
        }
      end
    end
  end

  table.sort(band, ring_sort_compare)

  local rest = {}
  if #band > MAX_EXPAND_ANIMS then
    local step = math.ceil(#band / MAX_EXPAND_ANIMS)
    local sampled = {}
    for i = 1, #band do
      if i % step == 1 then
        sampled[#sampled + 1] = band[i]
      else
        rest[#rest + 1] = band[i]
      end
    end
    band = sampled
  end

  if #band == 0 then
    return
  end

  storage.warptorio.platform_animation_active_until = game.tick + expand_lock_ticks

  surface.create_entity{name = shared.teleport_explosion, position = center}

  storage.warptorio.platform_expand_queue = {
    surface_name = surface.name,
    tile_name = warp_settings.tiles.ground,
    marker_dest = marker_dest,
    marker_level = marker_level,
    tiles = band,
    rest = rest,
    next = 1,
    per_tick = math.max(1, math.ceil(#band / expand_lock_ticks)),
    pending = {},
  }
end

return platform_animation
