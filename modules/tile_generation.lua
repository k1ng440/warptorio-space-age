local M = {}

local shared = require("shared")

function M.create_tile(name, x, y)
  return {name = name, position = {x, y}}
end

function M.generate_rectangle(width, height, tile, offset_x, offset_y)
  local tiles = {}
  local half_width = math.floor(width / 2)
  local half_height = math.floor(height / 2)
  offset_x = offset_x or 0
  offset_y = offset_y or 0

  for y = -half_height, math.ceil(height / 2) - 1 do
    for x = -half_width, math.ceil(width / 2) - 1 do
      if x >= -half_width and x <= half_width and y >= -half_height and y <= half_height then
        table.insert(tiles, M.create_tile(tile, x + offset_x, y + offset_y))
      end
    end
  end

  return tiles
end

function M.generate_cross(width, height, arm_width)
  local tiles = {}
  local half_width = math.floor(width / 2)
  local half_height = math.floor(height / 2)

  for y = -half_height, half_height - 1 do
    for x = -half_width, half_width - 1 do
      if (y >= -arm_width and y < arm_width) or (x >= -arm_width and x < arm_width) then
        table.insert(tiles, M.create_tile(shared.tiles.factory, x, y))
      else
        table.insert(tiles, M.create_tile("out-of-map", x, y))
      end
    end
  end

  return tiles
end

function M.generate_hexagon(radius, tile, offset_x, offset_y)
  local tiles = {}
  local sqrt3 = math.sqrt(3)
  offset_x = offset_x or 0
  offset_y = offset_y or 0

  local height = radius * sqrt3 / 2

  local min_x = math.floor(-radius)
  local max_x = math.ceil(radius)
  local min_y = math.floor(-height)
  local max_y = math.ceil(height)

  for y = min_y, max_y do
    local yy = math.abs(y + 0.5)
    for x = min_x, max_x do
      local xx = math.abs(x + 0.5)
      if yy <= height and sqrt3 * xx + yy <= sqrt3 * radius then
        tiles[#tiles + 1] = M.create_tile(tile, x + offset_x, y + offset_y)
      end
    end
  end
  return tiles
end

function M.generate_ellipse(width, height, tile, offset_x, offset_y)
  local tiles = {}
  offset_x = offset_x or 0
  offset_y = offset_y or 0

  local rx = width / 2
  local ry = height / 2

  local min_x = math.floor(-rx)
  local max_x = math.ceil(rx)
  local min_y = math.floor(-ry)
  local max_y = math.ceil(ry)

  local inv_rx2 = (rx > 0) and (1 / (rx * rx)) or 0
  local inv_ry2 = (ry > 0) and (1 / (ry * ry)) or 0

  for y = min_y, max_y do
    local yy = (y + 0.5)
    for x = min_x, max_x do
      local xx = (x + 0.5)
      if (xx * xx) * inv_rx2 + (yy * yy) * inv_ry2 <= 1 then
        tiles[#tiles + 1] = M.create_tile(tile, x + offset_x, y + offset_y)
      end
    end
  end

  return tiles
end

return M
