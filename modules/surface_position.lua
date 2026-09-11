local M = {}

local zero_offset = {x = 0, y = 0}

function M.ensure_surface_positions()
  storage.warptorio = storage.warptorio or {}
  storage.warptorio.surface_positions = storage.warptorio.surface_positions or {}
  return storage.warptorio.surface_positions
end

function M.get_surface_offset(surface_name)
  if storage.warptorio and storage.warptorio.surface_positions then
    return storage.warptorio.surface_positions[surface_name] or zero_offset
  end
  return zero_offset
end

function M.ensure_surface_offset(surface_name)
  local positions = M.ensure_surface_positions()
  if not positions[surface_name] then
    positions[surface_name] = {x = 0, y = 0}
  end
  return positions[surface_name]
end

function M.set_surface_offset(surface_name, position)
  local positions = M.ensure_surface_positions()
  positions[surface_name] = {x = position.x, y = position.y}
  return positions[surface_name]
end

function M.translate_surface_position(surface_name, position)
  local offset = M.get_surface_offset(surface_name)
  return {x = position.x + offset.x, y = position.y + offset.y}
end

function M.translate_surface_coordinates(surface_name, x, y)
  local offset = M.get_surface_offset(surface_name)
  return x + offset.x, y + offset.y
end

function M.translate_surface_area(surface_name, area, radius)
  if area then
    local offset = M.get_surface_offset(surface_name)
    return {
      {area[1][1] + offset.x, area[1][2] + offset.y},
      {area[2][1] + offset.x, area[2][2] + offset.y}
    }
  end
  if radius then
    local offset = M.get_surface_offset(surface_name)
    return {
      {offset.x - radius, offset.y - radius},
      {offset.x + radius, offset.y + radius}
    }
  end
end

return M
