local M = {}

function M.average(c1c, c2c)
  local average_content = (c1c + c2c) / 2
  return average_content, average_content
end

function M.mysplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

function M.shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

function M.getPointAndVector(centerX, centerY, distance)
  local angle = math.random() * 2 * math.pi
  local px = centerX + distance * math.cos(angle)
  local py = centerY + distance * math.sin(angle)
  local vectorBackX = centerX - px
  local vectorBackY = centerY - py
  return {position = {x = px, y = py}, movement = {x = vectorBackX, y = vectorBackY}}
end

function M.clean_ground_tiles(surface_name, area, shared)
  local surface = game.surfaces[surface_name]
  local tiles = surface.find_tiles_filtered{area = area}
  local replacement = {}
  for _, t in ipairs(tiles) do
    local base_name = t.name:match("^frozen%-(.+)$")
    if base_name then
      table.insert(replacement, {name = base_name, position = t.position})
    elseif t.name:find("^lava") then
      table.insert(replacement, {name = shared.tiles.ground, position = t.position})
    end
  end
  if #replacement > 0 then
    surface.set_tiles(replacement)
  end
end

return M
