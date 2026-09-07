local warp_settings = require("internal_settings")
local platform_animation = require("modules.platform_animation")

local gui_state = {}

-- Dependencies injected by control.lua after load. Kept to one delay-free
-- callback so the GUI code never re-writes its shared state.
local deps = {}

function gui_state.configure(new_deps)
  deps = new_deps
end

local function sec_to_time(time_base)
    local minutes = math.floor(time_base / 60)
    local seconds = time_base % 60
    return string.format("%02d:%02d",minutes,seconds)
end

local function warp_gui(player)
   local screen_element = player.gui.top
   if not storage.warptorio.gui then storage.warptorio.gui = {} end

   -- clear old gui if it exists
   local elements = {
      "time_passed_label",
      "number_of_warps_label",
      "number_of_waves_time",
      "number_of_waves_amount",
      "time_to_warp",
      "warp_planet"
   }
   for _,v in ipairs(elements) do
      if screen_element[v] then screen_element[v].destroy() end
   end
   
   local warp_frame_data = warp_settings.gui.data
   
   local warpFrame = screen_element.add{type = "frame", name=warp_settings.gui.holder,direction="horizontal"}
   for _,v in ipairs(warp_frame_data) do
      local frame = warpFrame.add{type = "frame",style="warptorio_frame", name=v.name,direction="vertical"}
      frame.add{type = "label", style="bold_label", name = "WarpLabel", caption = v.label}
      frame.add{type = "line", name = "WarpLine"}
      frame.add{type = "label", name = "WarpValue", caption = "  "..v.value.."  "}
   end
   
   local frame = warpFrame.add{type = "frame",style="entity_frame", name="buttons",direction="vertical"}
   local warp_button = frame.add{type = "button", name="warp_planet", style="red_button", caption={"warptorio.button-warp"}}
   if player.admin then
      warp_button.tooltip = {"warptorio.button-warp-admin"}
   elseif storage.warptorio.ground_level == 0 then
      warp_button.tooltip = {"warptorio.warp-not-available"}
   end
end

function gui_state.update_label(label_name,text,is_label)
   local is_label = is_label or false
   local gui_parent = warp_settings.gui.holder
   
   for k, v in pairs(game.players) do
      if not v.gui.top[gui_parent] then
         warp_gui(v)
      end
      local vl = warp_settings.gui.value
      local ll = warp_settings.gui.label
      if not is_label then
         v.gui.top[gui_parent][label_name][vl].caption = text
      else
         v.gui.top[gui_parent][label_name][ll].caption = text
      end
   end
end

local function update_warp_button_tooltip()
   local tip = nil
   local tip_key = "default"
   if storage.warptorio.ground_level == 0 then
      tip = {"warptorio.warp-not-available"}
      tip_key = "not-available"
   elseif storage.warptorio.warp_out > 0 then
      tip = {"warptorio.cooling-down"}
      tip_key = "cooling-down"
   elseif deps.technology_check and deps.technology_check() then
      tip = {"warptorio.technology-check"}
      tip_key = "technology-check"
   elseif platform_animation.is_active() then
      tip = {"warptorio.platform-animation-in-progress"}
      tip_key = "platform-animation"
   end
   storage.warptorio.gui_cache = storage.warptorio.gui_cache or {}
   local cache = storage.warptorio.gui_cache
   if cache.tooltip == tip_key then return end
   cache.tooltip = tip_key
   for _, player in pairs(game.players) do
      if not player.gui.top[warp_settings.gui.holder] then
         warp_gui(player)
      end
      local button = player.gui.top[warp_settings.gui.holder]["buttons"]["warp_planet"]
      if button then
         button.tooltip = tip
      end
   end
end

-- Writes a label only when its displayed value actually changed, so the GUI is
-- touched exactly on second/event boundaries instead of every tick.
local function update_label_if_changed(cache, name, value)
   local k = value
   if type(k) == "table" then
      k = "loc:" .. tostring(k[1])
   else
      k = tostring(k)
   end
   if cache[name] ~= k then
      gui_state.update_label(name, value)
      cache[name] = k
   end
end

-- Late joiners never got the frame from warp_gui; gui_state.update_label used
-- to rebuild it on every call. Create it here and remember so the
-- change-detection cache can be invalidated for the fresh player.
local function ensure_gui()
   local created = false
   for _, player in pairs(game.players) do
      if not player.gui.top[warp_settings.gui.holder] then
         warp_gui(player)
         created = true
      end
   end
   return created
end

function gui_state.update_all_labels()
  storage.warptorio.gui_cache = storage.warptorio.gui_cache or {}
  local cache = storage.warptorio.gui_cache
  if ensure_gui() then
     for k in pairs(cache) do cache[k] = nil end
  end

  local time_limit = warp_settings.time.round + (warp_settings.time.round*storage.warptorio.time_level)
  local time_passed = sec_to_time(time_limit-storage.warptorio.time_passed)
  update_label_if_changed(cache, "time", time_passed)
  local index = 0
  if storage.warporio and storage.warporio.index then
    index = storage.warporio.index
  end
  update_label_if_changed(cache, "amount", index)
  update_label_if_changed(cache, "wave-time", sec_to_time(storage.warptorio.wave_time))
  update_label_if_changed(cache, "wave-amount", storage.warptorio.wave_index)
  if storage.warptorio.transition_timer > 60 then
     update_label_if_changed(cache, "warpout-time", sec_to_time(math.floor(storage.warptorio.transition_timer/60)))
  else
     update_label_if_changed(cache, "warpout-time", sec_to_time(storage.warptorio.warp_out))
  end
  if storage.warptorio.planet_next and
     game.forces["player"].technologies[warp_settings.trigger_research].researched then
     local next_planet = storage.warptorio.planet_next
     if storage.warptorio.previous_surface_2 == storage.warptorio.planet_next then
        next_planet = "[color=red]" .. storage.warptorio.planet_next .. "[/color]"
     end
     update_label_if_changed(cache, "next-planet", next_planet)
  else
      update_label_if_changed(cache, "next-planet", {"warptorio.gui-unknown-planet"})
   end
   update_warp_button_tooltip()
end

gui_state.warp_gui = warp_gui

return gui_state