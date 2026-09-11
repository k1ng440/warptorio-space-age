local shared = require("shared")
local sp = require("modules.surface_position")
local eh = require("modules.entity_helper")
local util = require("modules.util")

local M = {}

local function delete_items(bounding_box, name, surface)
  local area = sp.translate_surface_area(surface, bounding_box)
  local entities = game.surfaces[surface].find_entities_filtered{area = area, name = name}
  for i, v in ipairs(entities) do
    v.destroy()
  end
end

local function belt_pair(pos1, pos2, speed)
  local speed = speed or 15
  local belt = eh.get_or_create(shared.belt.prefix .. speed, pos1)
  local belt2 = eh.get_or_create(shared.belt.prefix .. speed, pos2)

  if belt == nil or belt2 == nil then
    return
  end

  belt.disconnect_linked_belts()
  belt2.disconnect_linked_belts()
  belt2.linked_belt_type = "output"
  belt.linked_belt_type = "input"
  belt.connect_linked_belts(belt2)
  belt.minable_flag = false
  belt2.minable_flag = false
  belt.rotatable = false
  belt2.rotatable = false
end

function M.update_belt(e)
  if storage.warptorio.belt_level == 0 and e == nil then return end
  local speed = {15, 30, 45, 60}
  local level = storage.warptorio.belt_level
  if e then
    local e_level = util.mysplit(e, "-")
    level = tonumber(e_level[#e_level])
  end

  local names = {}
  for i, v in ipairs(speed) do
    if i ~= level then
      table.insert(names, shared.belt.prefix .. v)
    end
  end

  for i, v in ipairs(names) do
    delete_items({{-1, -5}, {1, -4}}, v, "factory")
    delete_items({{-1, -5}, {1, -4}}, v, storage.warptorio.warp_zone)
    delete_items({{-1, 4}, {1, 5}}, v, "factory")
    delete_items({{-1, 4}, {1, 5}}, v, storage.warptorio.warp_zone)
  end

  belt_pair({x = 0, y = -5, dir = defines.direction.south, surface = storage.warptorio.warp_zone}, {x = 0, y = -5, dir = defines.direction.south, surface = "factory"}, speed[level])
  belt_pair({x = -1, y = -5, dir = defines.direction.south, surface = storage.warptorio.warp_zone}, {x = -1, y = -5, dir = defines.direction.south, surface = "factory"}, speed[level])
  belt_pair({x = 0, y = 4, dir = defines.direction.north, surface = "factory"}, {x = 0, y = 4, dir = defines.direction.north, surface = storage.warptorio.warp_zone}, speed[level])
  belt_pair({x = -1, y = 4, dir = defines.direction.north, surface = "factory"}, {x = -1, y = 4, dir = defines.direction.north, surface = storage.warptorio.warp_zone}, speed[level])

  storage.warptorio.belt_level = level
end

function M.update_belt_biochamber(e)
  if storage.warptorio.belt_level == 0 and e == nil then return end
  local speed = {15, 30, 45, 60}
  local level = storage.warptorio.belt_level
  if e then
    local e_level = util.mysplit(e, "-")
    level = tonumber(e_level[#e_level])
  end

  local names = {}
  for i, v in ipairs(speed) do
    if i ~= level then
      table.insert(names, shared.belt.prefix .. v)
    end
  end

  for i, v in ipairs(names) do
    delete_items({{-5, -1}, {-4, 1}}, v, "factory")
    delete_items({{-5, -1}, {-4, 1}}, v, "garden")
  end

  belt_pair({y = 0, x = -5, dir = defines.direction.east, surface = "garden"}, {y = 0, x = -5, dir = defines.direction.east, surface = "factory"}, speed[level])
  belt_pair({y = -1, x = -5, dir = defines.direction.east, surface = "garden"}, {y = -1, x = -5, dir = defines.direction.east, surface = "factory"}, speed[level])
end

return M
