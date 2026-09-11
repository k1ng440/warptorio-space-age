local sp = require("modules.surface_position")

local M = {}

function M.capture_spidertron_selections(source, offset)
  local captured = {}
  local source_surface = game.surfaces[source]
  if not source_surface or not source_surface.valid then return captured end

  for _, player in pairs(game.players) do
    if player.connected and player.valid then
      local slots = {}
      for page = 1, 10 do
        for slot = 1, (player.quick_bar_width or 10) do
          local qbs = player.get_quick_bar_slot(page, slot)
          if qbs and qbs.type == "remote" and qbs.selection and #qbs.selection > 0 then
            local rel = {}
            local keep = {}
            local any_on_source = false
            for _, spider in ipairs(qbs.selection) do
              if spider.valid then
                if spider.surface.name == source then
                  rel[#rel + 1] = {x = spider.position.x - offset.x, y = spider.position.y - offset.y}
                  any_on_source = true
                else
                  keep[#keep + 1] = spider
                end
              end
            end
            if any_on_source then
              slots[#slots + 1] = {page = page, slot = slot, filter = qbs.filter, rel = rel, keep = keep}
            end
          end
        end
      end
      if #slots > 0 then
        captured[player.index] = slots
      end
    end
  end
  local n = 0
  for _ in pairs(captured) do n = n + 1 end
  log("[warptorio] spidertron capture on " .. source .. ": " .. n .. " player(s)")
  return captured
end

function M.restore_spidertron_selections(target, captured)
  if not captured or next(captured) == nil then return end
  local surface = game.surfaces[target]
  if not surface or not surface.valid then return end
  local offset = sp.get_surface_offset(target)

  local function find_clone(r)
    local target_pos = {x = offset.x + r.x, y = offset.y + r.y}
    local found = surface.find_entities_filtered{
      type = "spider-vehicle",
      position = target_pos,
      radius = 1.5,
    }
    if not found then return nil end
    local best, best_d = nil, math.huge
    for _, spider in ipairs(found) do
      if spider.valid then
        local d = math.abs(spider.position.x - target_pos.x) + math.abs(spider.position.y - target_pos.y)
        if d < best_d then
          best, best_d = spider, d
        end
      end
    end
    return best
  end

  for player_index, slots in pairs(captured) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected then
      local rewritten = 0
      for _, slot_data in ipairs(slots) do
        local selection = {}
        for _, spider in ipairs(slot_data.keep or {}) do
          if spider.valid then selection[#selection + 1] = spider end
        end
        for _, r in ipairs(slot_data.rel) do
          local c = find_clone(r)
          if c then selection[#selection + 1] = c end
        end
        if #selection > 0 then
          local filter = slot_data.filter or {name = "spidertron-remote"}
          filter.quality = filter.quality or "normal"
          local ok, err = pcall(function()
            player.set_quick_bar_slot(slot_data.page, slot_data.slot, {
              type = "remote",
              filter = filter,
              selection = selection,
            })
          end)
          if ok then
            rewritten = rewritten + 1
          else
            log("[warptorio] quickbar remote rewrite failed: " .. tostring(err))
          end
        end
      end
      log("[warptorio] spidertron relink: player " .. player_index .. " slots " .. #slots .. " (" .. rewritten .. " rewritten) on " .. target)
    end
  end
end

return M
