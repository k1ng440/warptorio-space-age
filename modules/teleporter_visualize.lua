local M = {}

local env

local active = false
local render_ids = {}

local function clear_all()
  for _, id in pairs(render_ids) do
    local obj = rendering.get_object_by_id(id)
    if obj then obj:destroy() end
  end
  render_ids = {}
end

local function draw_zone(surface, pos, box, color, label)
  if not surface or not surface.valid then return end
  local sx = pos.x + (box.minx or -0.4)
  local sy = pos.y + (box.miny or -0.4)
  local ex = pos.x + (box.maxx or 2.4)
  local ey = pos.y + (box.maxy or 2.5)
  local r, g, b = color[1], color[2], color[3]

  local corners = {
    {sx, sy}, {ex, sy}, {ex, ey}, {sx, ey}, {sx, sy}
  }
  for i = 1, 4 do
    table.insert(render_ids, rendering.draw_line{
      surface = surface, from = corners[i], to = corners[i + 1],
      color = {r, g, b, 0.9}, width = 3, time_to_live = 0, draw_on_ground = true,
    })
  end

  table.insert(render_ids, rendering.draw_rectangle{
    surface = surface,
    left_top = {sx, sy}, right_bottom = {ex, ey},
    color = {r, g, b, 0.12}, filled = true, time_to_live = 0, draw_on_ground = true,
  })

  local cx = (sx + ex) / 2
  local cy = (sy + ey) / 2
  table.insert(render_ids, rendering.draw_text{
    surface = surface, target = {cx, sy - 0.8},
    text = label, color = {r, g, b, 1}, scale = 0.8,
    alignment = "center", time_to_live = 0,
  })
end

local function refresh()
  clear_all()
  if not active then return end

  local warp_zone = env.get_warp_zone and env.get_warp_zone() or storage.warptorio.warp_zone
  log("[teleporter_visualize] refresh warp_zone=" .. tostring(warp_zone) ..
      " biochamber=" .. tostring(storage.warptorio.biochamber_level))
  for name, pad in pairs(env.teleporters) do
    if not pad.biochamber or storage.warptorio.biochamber_level then
      local surface_name = pad.surface == "$warp_zone" and warp_zone or pad.surface
      local surface = game.surfaces[surface_name]
      log("[teleporter_visualize]   pad=" .. tostring(name) .. " surface=" .. tostring(surface_name) ..
          " exists=" .. tostring(surface ~= nil) .. " valid=" .. tostring(surface and surface.valid))
      if surface and surface.valid then
        draw_zone(surface, pad.position, pad.box, pad.color,
          "PAD: " .. name .. "  (walk here)")
      end
    end
  end
end

function module_init(env_table)
  env = env_table
end

function M.toggle(player)
  active = not active
  if active then
    log("[teleporter_visualize] toggle ON by " .. (player and player.name or "?") .. " on surface=" ..
        tostring(player and player.character and player.character.surface and player.character.surface.name))
    refresh()
    player.print("[color=0.3,1,0.4]Teleporter zones: VISIBLE[/color]")
  else
    clear_all()
    player.print("[color=1,0.5,0.3]Teleporter zones: HIDDEN[/color]")
  end
end

function M.refresh()
  if active then refresh() end
end

function M.is_active() return active end

M.init = module_init

return M
