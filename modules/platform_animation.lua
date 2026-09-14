local shared = require("shared")

local platform_animation = {}

-- platform_builder requires this module back, so a top-level require here would
-- infinite-loop the loader. control.lua injects it after both modules load.
local platform_builder
function platform_animation.set_platform_builder(mod)
  platform_builder = mod
end

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

-- A build animation whose chunk is inactive (or never generated) does not tick,
-- so its explosion entity stays valid forever and the pending list never drains.
-- Treat an animation as finished after this many ticks regardless of its state.
local anim_max_ticks = warp_settings.animation.anim_max_ticks or 600

local build_anim_base = shared.platform_build_anim
local unknown_anims = {}

local function build_dir(cx, cy, x, y)
  local dx = x - cx
  local dy = y - cy
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and "east" or "west"
  end
  return dy > 0 and "south" or "north"
end

local function spawn_build_anim(surface, x, y, cx, cy)
  local name = build_anim_base .. "-" .. build_dir(cx, cy, x, y)
  if unknown_anims[name] then
    return nil
  end
  local ok, anim = pcall(function()
    return surface.create_entity{
      name = name,
      position = {x = x + 0.5 + anim_offset_x, y = y + 0.5 + anim_offset_y},
    }
  end)
  if not ok then
    unknown_anims[name] = true
    return nil
  end
  return anim
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
    elseif pending.spawned == nil or game.tick - pending.spawned > anim_max_ticks then
      -- Stale animation (inactive/ungenerated chunk). Place the tile anyway so
      -- the queue can finish and the warp engine comes back online.
      if pending.entity.valid then
        pending.entity.destroy()
      end
      tiles_to_place[#tiles_to_place + 1] = pending.pos
      table.remove(eq.pending, i)
    end
  end
  if #tiles_to_place > 0 then
    for _, pos in ipairs(tiles_to_place) do
      surface.set_tiles{{name = eq.tile_name, position = pos}}
    end
  end

  -- start new build animations on this tick (continuous outward wave, pacing
  -- driven by spawn budget instead of a fixed per-tile interval)
  if #eq.pending < (eq.max_pending or 600) then
    eq.spawn_budget = (eq.spawn_budget or 0) + (eq.tps or 1) / 60
    local spawned = 0
    while spawned < 64 and eq.spawn_budget >= 1 and eq.next <= #eq.tiles do
      local t = eq.tiles[eq.next]
      eq.next = eq.next + 1
      eq.spawn_budget = eq.spawn_budget - 1
      local anim = spawn_build_anim(surface, t.x, t.y, eq.center.x, eq.center.y)
      if anim then
        eq.pending[#eq.pending + 1] = {entity = anim, pos = {x = t.x, y = t.y}, spawned = game.tick}
      else
        surface.set_tiles{{name = eq.tile_name, position = {x = t.x, y = t.y}}}
      end
      spawned = spawned + 1
    end
  end

  if eq.next > #eq.tiles and #eq.pending == 0 then
    local dest = eq.marker_dest
    local level = eq.marker_level
    warptorio.platform_expand_queue = nil
    -- Keep the warp engine offline until the upgrade's minimum duration elapses,
    -- even when this platform finished reconstructing early.
    storage.warptorio.platform_animation_active_until = math.max(game.tick + 15, eq.lock_until or 0)
    if dest and level then
      if platform_builder then
        platform_builder.apply_ground_markers(dest, level)
      end
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
    if pending.entity == nil or not pending.entity.valid then
      table.insert(batch, pending.tile)
      table.insert(placed_keys, pending.key)
      table.remove(queue.pending, i)
    elseif pending.spawned == nil or game.tick - pending.spawned > anim_max_ticks then
      -- Stale animation (inactive/ungenerated chunk). Place the tile anyway so
      -- the queue can finish and the warp engine comes back online.
      if pending.entity and pending.entity.valid then
        pending.entity.destroy()
      end
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
        local anim = spawn_build_anim(surface, tile_x(tile), tile_y(tile), queue.center.x, queue.center.y)
        if anim then
          table.insert(queue.pending, {entity = anim, tile = tile, key = key, spawned = game.tick})
        else
          table.insert(batch, tile)
          table.insert(placed_keys, key)
        end
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

  if #band == 0 then
    return
  end

  local lock_until = game.tick + expand_lock_ticks
  storage.warptorio.platform_animation_active_until = lock_until

  surface.create_entity{name = shared.teleport_explosion, position = center}

  -- Continuous outward wave. Tiles/second scales with band size so a small
  -- upgrade reads as one smooth ripple while a huge platform streams without
  -- a stall; the entity cap only throttles how many anims are live at once.
  local band_count = math.max(1, #band)
  local min_ticks = 240
  local target_ticks = math.max(min_ticks, math.min(expand_lock_ticks, math.floor(band_count * 6)))
  local tps = band_count * 60 / target_ticks
  local max_pending = 600

  storage.warptorio.platform_expand_queue = {
    surface_name = surface.name,
    tile_name = warp_settings.tiles.ground,
    marker_dest = marker_dest,
    marker_level = marker_level,
    center = {x = cx, y = cy},
    tiles = band,
    next = 1,
    lock_until = lock_until,
    spawn_budget = 0,
    tps = tps,
    max_pending = max_pending,
    pending = {},
  }
end

return platform_animation
