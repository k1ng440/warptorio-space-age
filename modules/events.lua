-- Cross-mod custom events. Defined as `custom-event` prototypes in data.lua,
-- raised here at the relevant warp-lifecycle moments. Third-party mods subscribe
-- with script.on_event(defines.events["warptorio-..."], handler) — no load
-- order or remote-call handshake required.
--
-- Event data payloads:
--   warptorio-warp-started  {from_surface, target, planet, index, forced}
--   warptorio-warp-finished {surface, previous_surface, planet, index, factory_level}
--   warptorio-planet-chosen {planet, index}
--   warptorio-wave-spawned  {index, amount, boss, quality, surface}
--   warptorio-boss-spawned  {index, count, quality, surface}
--   warptorio-game-over     {surface, index}
--   warptorio-game-win      {index, factory_level}

local M = {}

function M.raise(name, data)
  local id = defines.events[name]
  if id then
    script.raise_event(id, data or {})
  end
end

return M