-- Genuine pause for ground/repair platform research while the base is in the
-- warp transition: writes the engine-accurate progress into
-- LuaTechnology.saved_progress and vacates the current research, so labs stop
-- consuming science packs with no progress lost. Research resumes from the
-- saved progress on the warp-finished falling edge of teleporting.
local warp_settings = require("internal_settings")

local M = {}

local total_fallback = {
  ["warp-ground-platform-1"] = 25,
  ["warp-ground-platform-2"] = 100,
  ["warp-ground-platform-3"] = 100,
  ["warp-ground-platform-4"] = 250,
  ["warp-ground-platform-5"] = 500,
  ["warp-ground-platform-6"] = 1000,
  ["warp-ground-platform-7"] = 5000,
  ["warp-ground-platform-8"] = 10000,
}

function M.matches(name)
  return string.find(name, warp_settings.techs.ground) ~= nil
      or string.find(name, warp_settings.techs.repair) ~= nil
end

function M.ground_research_active()
  local tech = game.forces["player"].current_research
  return tech ~= nil and M.matches(tech.name)
end

function M.init()
  storage.warptorio.platform_research_totals = storage.warptorio.platform_research_totals or {}
end

local function total_for(tech)
  local totals = storage.warptorio.platform_research_totals or {}
  local total = totals[tech.name .. ":" .. tech.level]
  if not total then
    total = total_fallback[tech.name]
  end
  if not total and string.find(tech.name, warp_settings.techs.repair) then
    total = 100 * tech.level * tech.level
  end
  return total
end

function M.pause()
  local force = game.forces["player"]
  local tech = force.current_research
  if not tech or not M.matches(tech.name) then return end
  local total = total_for(tech)
  if total then
    local fraction = (total - tech.research_unit_count + force.research_progress) / total
    tech.saved_progress = math.max(0, math.min(0.999999, fraction))
  end
  local queue = {}
  for _, t in ipairs(force.research_queue or {}) do
    queue[#queue + 1] = type(t) == "string" and t or t.name
  end
  storage.warptorio.paused_research = { name = tech.name, queue = queue }
  force.research_queue = {}
end

function M.resume()
  local paused = storage.warptorio.paused_research
  storage.warptorio.paused_research = nil
  if not paused or not paused.name then return end
  if not M.matches(paused.name) then return end
  local queue = { paused.name }
  for _, name in ipairs(paused.queue or {}) do
    if name ~= paused.name then
      queue[#queue + 1] = name
    end
  end
  game.forces["player"].research_queue = queue
end

function M.on_research_started(research)
  local name = research.name
  if not M.matches(name) then return end
  storage.warptorio.platform_research_totals = storage.warptorio.platform_research_totals or {}
  storage.warptorio.platform_research_totals[name .. ":" .. research.level] = research.research_unit_count
  if storage.warptorio.teleporting and storage.warptorio.paused_research == nil then
    M.pause()
  end
end

return M