local shared = require("shared")
local sp = require("modules.surface_position")
local util = require("modules.util")
local platform_animation = require("modules.platform_animation")
local warp_settings = require("internal_settings")

local M = {}

-- Resolve the far end of a captured wire as a live LuaWireConnector.
-- Prefer the partner entity's connector (survives the old wire's death);
-- fall back to the captured wire-end snapshot.
local function resolve_wire_target(w)
  if w.partner and w.partner.valid then
    local ok, pc = pcall(function()
      return w.partner.get_wire_connector(w.pcid or w.cid, true)
    end)
    if ok and pc and pc.valid then
      return pc
    end
  end
  if w.target and w.target.valid then
    return w.target
  end
  return nil
end

local function capture_capacitor_wires(entity)
  local wires = {}
  for _, connector in pairs(entity.get_wire_connectors(true)) do
    if connector.connections then
      for _, connection in ipairs(connector.connections) do
        local target = connection.target
        if target and target.valid then
          local partner = target.owner
          if partner and partner.valid then
            wires[#wires + 1] = {
              cid = connector.wire_connector_id,
              pcid = target.wire_connector_id,
              target = target,
              partner = partner,
              partner_unit = partner.unit_number,
            }
          end
        end
      end
    end
  end
  return wires
end

-- Replace one capacitor in place with a new-tier prototype, keeping its
-- position and its wire connections. Partners are never destroyed here, so
-- every captured wire is re-created from this side (the neighbor cannot
-- reconnect on its own).
local function upgrade_power_capacitor(entity, new_name)
  if not entity or not entity.valid or entity.name == new_name then
    return entity
  end
  local surface = entity.surface
  local position = entity.position
  local direction = entity.direction
  local energy = entity.energy
  local wires = capture_capacitor_wires(entity)
  entity.destroy({raise_destroy = false})
  local e = surface.create_entity{
    name = new_name,
    position = position,
    direction = direction,
    force = game.forces.player,
    snap_to_grid = false,
  }
  if not e then return nil end
  e.minable_flag = false
  e.rotatable = false
  if energy then e.energy = energy end
  for _, w in ipairs(wires) do
    local connector = e.get_wire_connector(w.cid, true)
    if connector then
      local target = resolve_wire_target(w)
      if target then
        pcall(function()
          connector.connect_to(target, false, defines.wire_origin.player)
        end)
      end
    end
  end
  return e
end

-- capacitor get_or_create that never nukes the tile: upgrades any old-tier
-- capacitor found on the spot instead of destroying it along with its wires.
function M.get_or_create_power(surface_name)
  local surface_obj = game.surfaces[surface_name]
  if not surface_obj then return nil end
  local name = storage.warptorio.power_name or shared.power[1]
  local x, y = sp.translate_surface_coordinates(surface_name, 0, 0)
  local area = {{x, y}, {x + 1, y + 1}}
  for _, tier in ipairs(shared.power) do
    local found = surface_obj.find_entities_filtered{area = area, name = tier}
    if found and #found > 0 then
      local exist = found[1]
      if exist.name == name then
        return exist
      end
      return upgrade_power_capacitor(exist, name)
    end
  end
  local function try_create()
    local e = surface_obj.create_entity{name = name, position = {x, y}, force = game.forces.player, snap_to_grid = false}
    if e then
      e.minable_flag = false
      e.rotatable = false
    end
    return e
  end
  local e = try_create()
  if e then return e end
  for _, blocker in pairs(surface_obj.find_entities{{x, y}, {x + 1, y + 1}}) do
    if blocker.valid and blocker.name ~= name then
      blocker.destroy({raise_destroy = false})
    end
  end
  return try_create()
end

-- Upgrade every existing capacitor in storage to the new tier. All old
-- entities are destroyed and recreated together so cross-surface power
-- wires (power[1] <-> power[2] <-> power[3]) are restored exactly once.
function M.upgrade_power_capacitors(new_name)
  local power_list = storage.warptorio.power
  if not power_list then return end

  local pending = {}
  local unit_to_index = {}
  for i, entity in pairs(power_list) do
    if entity and entity.valid and entity.name ~= new_name then
      unit_to_index[entity.unit_number] = i
    end
  end
  for i, entity in pairs(power_list) do
    if entity and entity.valid and entity.name ~= new_name then
      pending[i] = {
        entity = entity,
        surface = entity.surface,
        position = entity.position,
        direction = entity.direction,
        energy = entity.energy,
        wires = capture_capacitor_wires(entity),
      }
    end
  end
  if not next(pending) then return end

  for _, p in pairs(pending) do
    p.entity.destroy({raise_destroy = false})
  end

  local replacement = {}
  for i, p in pairs(pending) do
    local e = p.surface.create_entity{
      name = new_name,
      position = p.position,
      direction = p.direction,
      force = game.forces.player,
      snap_to_grid = false,
    }
    if e then
      e.minable_flag = false
      e.rotatable = false
      if p.energy then e.energy = p.energy end
      replacement[i] = e
      p.new_entity = e
    end
  end

  for i, e in pairs(replacement) do
    power_list[i] = e
  end
  storage.warptorio.power_unit_number = nil

  -- Re-wiring is deferred to the next tick so the freshly created capacitors are
  -- fully in the world before connect_to runs (and so the captured wire list
  -- survives a save in the gap). Stored in storage for that persistence.
  storage.warptorio.wt_pending_reconnect = {
    unit_to_index = unit_to_index,
    pending = {},
  }
  local pend = storage.warptorio.wt_pending_reconnect.pending
  for i, p in pairs(pending) do
    if p.new_entity then
      pend[i] = { wires = p.wires }
    end
  end
end

-- Run the queued reconnect from the tick after upgrade_power_capacitors, when
-- the freshly created capacitors are fully in the world and will draw wires.
function M.flush_pending_reconnect()
  local job = storage.warptorio and storage.warptorio.wt_pending_reconnect
  if not job then return end
  storage.warptorio.wt_pending_reconnect = nil

  local power_list = storage.warptorio.power
  local unit_to_index = job.unit_to_index or {}

  local function link(a, b)
    if not a or not a.valid or not b or not b.valid then return end
    for _, v in ipairs{defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green} do
      local ca = a.get_wire_connector(v, true)
      local cb = b.get_wire_connector(v, true)
      if ca and cb then
        pcall(function()
          ca.connect_to(cb, false, defines.wire_origin.script)
        end)
      end
    end
  end

  local function resolve_target(w)
    local partner_index = unit_to_index[w.partner_unit]
    local partner_entity = partner_index and power_list[partner_index]
    if partner_entity and partner_entity.valid then
      return partner_entity.get_wire_connector(w.cid, true)
    end
    return resolve_wire_target(w)
  end

  local function try_connect(new_entity, w, target, reach_check)
    local connector = new_entity.get_wire_connector(w.cid, true)
    if not connector then return end
    pcall(function()
      connector.connect_to(target, reach_check, defines.wire_origin.player)
    end)
  end

  local function same_surface(a, b)
    return a and b and a.surface and b.surface and a.surface == b.surface
  end

  -- Pass 1: same-surface wires are created as normal player wires (reach
  -- checked) so they render exactly like hand-placed wires.
  for i, p in pairs(job.pending) do
    local new_entity = power_list[i]
    if new_entity and new_entity.valid then
      for _, w in ipairs(p.wires) do
        local target = resolve_target(w)
        if target then
          local tobj = target.owner
          if tobj and tobj.valid and same_surface(new_entity, tobj) then
            try_connect(new_entity, w, target, true)
            w.fixed = true
          end
        end
      end
    end
  end

  -- Pass 2: cross-surface wires (and anything pass 1 could not reach) fall
  -- back to reach_check = false, the only way to wire different surfaces.
  for i, p in pairs(job.pending) do
    local new_entity = power_list[i]
    if new_entity and new_entity.valid then
      for _, w in ipairs(p.wires) do
        if not w.fixed then
          local target = resolve_target(w)
          if target then
            try_connect(new_entity, w, target, false)
          end
        end
      end
    end
  end

  link(power_list[1], power_list[2])
  link(power_list[1], power_list[3])
end

local function battery_check(index)
  return storage.warptorio.power[index] and storage.warptorio.power[index].valid
end

function M.on_tick_power()
  if storage.warptorio.power then
    if battery_check(2) and battery_check(1) then
      local ave = util.average(storage.warptorio.power[2].energy, storage.warptorio.power[1].energy)
      if battery_check(3) then
        ave = (storage.warptorio.power[1].energy + storage.warptorio.power[2].energy + storage.warptorio.power[3].energy) / 3
      end
      storage.warptorio.power[1].energy = ave
      storage.warptorio.power[2].energy = ave
      if battery_check(3) then
        storage.warptorio.power[3].energy = ave
      end
    end
  end
end

function M.update_nauvis_timer()
  if warp_settings.nauvis_timer <= 0 then return end
  if not storage.warporio or (storage.warporio.index or 0) > 0 then return end
  if storage.warptorio.warp_zone ~= "nauvis" then
    if storage.warptorio.nauvis_timer_render and storage.warptorio.nauvis_timer_render.valid then
      storage.warptorio.nauvis_timer_render.destroy()
    end
    storage.warptorio.nauvis_timer_render = nil
    return
  end
  if platform_animation.is_active() then
    return
  end

  if not storage.warptorio.nauvis_timer_remaining then
    storage.warptorio.nauvis_timer_remaining = warp_settings.nauvis_timer
  end

  storage.warptorio.nauvis_timer_remaining = storage.warptorio.nauvis_timer_remaining - 1
  local remaining = storage.warptorio.nauvis_timer_remaining

  local color
  if remaining <= 60 * 60 then
    color = {1, 0, 0}
  elseif remaining <= 60 * 60 * 5 then
    color = {1, 0.5, 0}
  else
    color = {1, 1, 0}
  end

  if remaining % 60 == 0 or not (storage.warptorio.nauvis_timer_render and storage.warptorio.nauvis_timer_render.valid) then
    local secs = math.max(math.ceil(remaining / 60), 0)
    local text = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    if storage.warptorio.nauvis_timer_render and storage.warptorio.nauvis_timer_render.valid then
      storage.warptorio.nauvis_timer_render.text = text
      storage.warptorio.nauvis_timer_render.color = color
    else
      storage.warptorio.nauvis_timer_render = rendering.draw_text{
        surface = "nauvis",
        text = text,
        scale = 4,
        target = {x = 0, y = -6},
        color = color,
        alignment = "center",
      }
    end
  end

  if remaining <= 0 then
    if storage.warptorio.nauvis_timer_render and storage.warptorio.nauvis_timer_render.valid then
      storage.warptorio.nauvis_timer_render.destroy()
    end
    storage.warptorio.nauvis_timer_render = nil
    storage.warptorio.nauvis_timer_remaining = nil
    -- Called via the deps callback from the control stage
    if M.on_nauvis_timer_expired then
      M.on_nauvis_timer_expired()
    end
  end
end

return M
