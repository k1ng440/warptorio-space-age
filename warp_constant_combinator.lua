local warp_settings = require("internal_settings")

local warp_constant_combinator = {}

-- Slots 1-6 are the fixed virtual signals (T, W, V, A, J, D); the two planet signals
-- follow them at slots that never move, so each always means the same thing.

local function ensure_storage()
  storage.warptorio = storage.warptorio or {}
  storage.warptorio.constant_combinators = storage.warptorio.constant_combinators or {}
  return storage.warptorio.constant_combinators
end

local function get_warp_amount()
  if storage.warporio and storage.warporio.index then
    return storage.warporio.index
  end
  return 0
end

-- The platform counts as "in transition" from next_warp_zone_prepare() until
-- next_warp_zone_finish() lands it on the new planet. transition_timer runs down to
-- 0 across that window and then goes negative for the post-warp grace period, so
-- teleporting is what gates both signals. Returns (in_transition, seconds_left).
local function get_transition_state()
  if not storage.warptorio or not storage.warptorio.teleporting then
    return 0, 0
  end
  local ticks = storage.warptorio.transition_timer or 0
  return 1, math.max(0, math.ceil(ticks / 60))
end

-- A slot cache key that changes exactly when the slot's on-wire content changes.
-- Emptied slots are "", anything else is type:name:count.
local function slot_key(param)
  if not param.signal then
    return ""
  end
  return (param.signal.type or "") .. ":" .. (param.signal.name or "") .. ":" .. tostring(param.count)
end

local function get_planet_signal(planet_name)
  if not planet_name then
    return nil
  end
  if not game.planets[planet_name] then
    return nil
  end
  return {type = "space-location", name = planet_name}
end

local function get_parameters(state)
  local parameters = {
    {index = 1, signal = {type = "virtual", name = "signal-T"}, count = state.remaining_time},
    {index = 2, signal = {type = "virtual", name = "signal-W"}, count = state.wave_index},
    {index = 3, signal = {type = "virtual", name = "signal-V"}, count = state.wave_time},
    {index = 4, signal = {type = "virtual", name = "signal-A"}, count = state.warp_amount},
    {index = 5, signal = {type = "virtual", name = "signal-J"}, count = state.in_transition},
    {index = 6, signal = {type = "virtual", name = "signal-D"}, count = state.transition_time},
  }

  -- Fixed slots. Indexing off #parameters let the next planet slide into the current
  -- planet's slot whenever the current one had no signal (void, or mid-transition),
  -- which both changed what a slot meant and stranded the old value in the slot below.
  local current_name = storage.warptorio.surface_name
  local next_name = storage.warptorio.planet_next
  local current_planet_signal = get_planet_signal(current_name)
  local next_planet_signal = get_planet_signal(next_name)

  if current_planet_signal and current_name == next_name then
     -- Staying put (nauvis): one signal carries both roles, so 1 + 2. Comparing the
     -- signal tables here never matched — get_planet_signal builds a fresh table per
     -- call, so it was reference equality against a different table every time.
     table.insert(parameters, {index = warp_settings.combinator.slot_current_planet, signal = current_planet_signal, count = 3})
     table.insert(parameters, {index = warp_settings.combinator.slot_next_planet})
  else
     table.insert(parameters, {index = warp_settings.combinator.slot_current_planet, signal = current_planet_signal, count = 1})
     table.insert(parameters, {index = warp_settings.combinator.slot_next_planet, signal = next_planet_signal, count = 2})
  end
  return parameters
end

-- Writes only the slots whose content changed since the last refresh. Slots are
-- sticky once written, so a signal that stops applying is cleared explicitly.
local function update_entity(entity, parameters, cache_row)
  if not entity.valid then
    return false
  end

  local control_behavior = entity.get_or_create_control_behavior()

  local section = control_behavior.get_section(1)

  if not cache_row.description_done then
     entity.combinator_description = [[
  signal-T - Remaining time before forced warp
  signal-W - Wave count
  signal-V - Remaining time before next enemy wave
  signal-A - Warp count
  signal-J - 1 while the platform is warping between planets
  signal-D - Seconds remaining of the warp transition
  planet-signal - Value 1 current planet
  planet-signal - Value 2 next planet
  ]]
     cache_row.description_done = true
  end

  if not section then
     control_behavior.add_section()
     section = control_behavior.get_section(1)
  end

  if not section.is_manual then
     for _,sec in ipairs(control_behavior.sections) do
        if sec.is_manual then
           section = sec
           break
        end
     end
  end

  local slots = cache_row.slots
  for _, param in ipairs(parameters) do
    local key = slot_key(param)
    if slots[param.index] ~= key then
      if param.signal then
        param.signal.quality = "normal"
        section.set_slot(
          param.index,
          {
            value = param.signal,
            min = param.count,
            max = param.count
          }
        )
      else
        section.clear_slot(param.index)
      end
      slots[param.index] = key
    end
  end
  return true
end

local function slot_cache_cleanup(unit_number)
  if storage.warptorio and storage.warptorio.combinator_slot_cache then
    storage.warptorio.combinator_slot_cache[unit_number] = nil
  end
end

function warp_constant_combinator.register(entity)
  if not entity or not entity.valid or entity.name ~= warp_settings.combinator.name then
    return
  end

  local entities = ensure_storage()
  if entity.unit_number then
    entities[entity.unit_number] = entity
    slot_cache_cleanup(entity.unit_number)
    -- Invalidate the global gate so a combinator placed while the state key is
    -- stable is still synced on the very next tick. The per-slot diff keeps every
    -- other entity silent, so this costs one lookup pass, not a rewrite.
    storage.warptorio.combinator_cache = nil
  end
end

function warp_constant_combinator.unregister(entity)
  if not entity or not entity.unit_number then
    return
  end
  if storage.warptorio and storage.warptorio.constant_combinators then
    storage.warptorio.constant_combinators[entity.unit_number] = nil
    -- Same as register: force the next refresh through so stale slot state can't be
    -- reused if the unit number is ever recycled. Cheap.
    storage.warptorio.combinator_cache = nil
  end
  slot_cache_cleanup(entity.unit_number)
end

function warp_constant_combinator.init()
  ensure_storage()
end

function warp_constant_combinator.rescan()
  local entities = ensure_storage()
  for key in pairs(entities) do
    entities[key] = nil
  end
  storage.warptorio.combinator_slot_cache = {}

  for _, surface in pairs(game.surfaces) do
    local found = surface.find_entities_filtered({name = warp_settings.combinator.name})
    for _, entity in ipairs(found) do
      warp_constant_combinator.register(entity)
    end
  end
end

function warp_constant_combinator.refresh()
  local entities = ensure_storage()
  if not next(entities) then
    return
  end
  local time_limit = warp_settings.time.round + (warp_settings.time.round * storage.warptorio.time_level)
  local remaining_time = math.max(0, math.floor(time_limit - storage.warptorio.time_passed))
  local wave_index = storage.warptorio.wave_index or 0
  local wave_time = math.max(0, math.floor(storage.warptorio.wave_time or 0))
  local warp_amount = get_warp_amount()
  local in_transition, transition_time = get_transition_state()

  -- All signals are whole numbers or discrete planet ids, so only rewrite the
  -- slots when one of them crosses a boundary. Counting/seconds resolution is
  -- preserved exactly; the slot writes just stop happening 59 times per second.
  local current_name = storage.warptorio.surface_name or ""
  local next_name = storage.warptorio.planet_next or ""
  local key = table.concat({
    remaining_time,
    wave_index,
    wave_time,
    warp_amount,
    in_transition,
    transition_time,
    current_name,
    next_name,
  }, "|")

  storage.warptorio.combinator_cache = storage.warptorio.combinator_cache or {}
  if storage.warptorio.combinator_cache.key == key then
    return
  end
  storage.warptorio.combinator_cache.key = key

  local state = {
    remaining_time = remaining_time,
    wave_index = wave_index,
    wave_time = wave_time,
    warp_amount = warp_amount,
    in_transition = in_transition,
    transition_time = transition_time,
  }
  local parameters = get_parameters(state)

  storage.warptorio.combinator_slot_cache = storage.warptorio.combinator_slot_cache or {}
  local slot_cache = storage.warptorio.combinator_slot_cache

  for unit_number, entity in pairs(entities) do
    local row = slot_cache[unit_number]
    if not row then
      row = {description_done = false, slots = {}}
      slot_cache[unit_number] = row
    end
    local ok = update_entity(entity, parameters, row)
    if not ok then
      entities[unit_number] = nil
      slot_cache[unit_number] = nil
    end
  end
end

return warp_constant_combinator
