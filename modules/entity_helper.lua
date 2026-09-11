local shared = require("shared")
local sp = require("modules.surface_position")

local M = {}

function M.get_or_create(name, pos)
  local surface_obj = game.surfaces[pos.surface]
  if not surface_obj then
    log("Warning: get_or_create skipped, surface \"" .. tostring(pos.surface) .. "\" is missing " .. name)
    return nil
  end
  local x, y = sp.translate_surface_coordinates(pos.surface, pos.x, pos.y)
  local exist = surface_obj.find_entity(
    name,
    {
      x + (x > 0 and -0.5 or 0.5),
      y + 0.5
    }
  )
  if exist ~= nil then
    return exist
  end
  local test = game.surfaces[pos.surface].can_place_entity{name = name, position = {x, y}}
  if not test then
    for i, v in pairs(game.surfaces[pos.surface].find_entities({{x, y}, {x + 1, y + 1}})) do
      v.destroy()
    end
  end
  return game.surfaces[pos.surface].create_entity({name = name, position = {x, y}, direction = pos.dir, force = game.forces.player})
end

function M.is_protected_warp_entity(entity)
  if entity.name == shared.container then return true end
  if not storage.warptorio or not storage.warptorio.power then return false end
  if not storage.warptorio.power_unit_number then
    storage.warptorio.power_unit_number = {}
    for i, power_entity in pairs(storage.warptorio.power) do
      if power_entity and power_entity.valid then
        storage.warptorio.power_unit_number[i] = power_entity.unit_number
      end
    end
  end
  if entity.unit_number then
    for _, unit_number in pairs(storage.warptorio.power_unit_number) do
      if unit_number == entity.unit_number then return true end
    end
  end
  for _, power_entity in pairs(storage.warptorio.power) do
    if power_entity == entity then return true end
  end
  return false
end

return M
