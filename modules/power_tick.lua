local util = require("modules.util")
local platform_animation = require("modules.platform_animation")
local warp_settings = require("internal_settings")

local M = {}

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
    -- This will be called from warp_system via the deps callback
    if M.on_nauvis_timer_expired then
      M.on_nauvis_timer_expired()
    end
  end
end

return M
