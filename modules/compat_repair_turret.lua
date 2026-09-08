-- Compatibility shim for the "Repair Turret" mod (Klonan, Repair_Turret 2.1.0).
--
-- Repair Turret keeps a per-surface registry of turrets (script_data.turret_map,
-- keyed by surface INDEX) and only removes an entry when the turret is destroyed
-- via LuaEntity.destroy (its on_object_destroyed handler). When an entire surface
-- is wiped with LuaSurface.clear()/delete_surface() instead, turrets on it die
-- silently and the stale entry survives. Once the freed surface index is reused by
-- a new warp-zone surface, Repair Turret's is_valid_for_entity does
-- `assert(self.entity.valid)` on the dead entry -> non-recoverable crash.
--
-- Warptorio clears a previously-visited planet surface when you warp back to that
-- planet (new_random_surface). This shim destroys that surface's Repair Turrets
-- with raise_destroy=true first, so the mod's own cleanup removes them from its
-- registry. The proper fix belongs in Repair Turret: guard invalid entities in
-- is_valid_for_entity like update() already does.

local M = {}

local turret_names = nil

local function refresh_names()
  if not script.active_mods["Repair_Turret"] then
    turret_names = nil
    return
  end
  local names = {}
  for _, entity in pairs(prototypes.entity) do
    if entity.type == "assembling-machine" and string.find(entity.name, "repair%-turret", 1) then
      names[#names + 1] = entity.name
    end
  end
  turret_names = #names > 0 and names or nil
end

-- Destroy Repair Turrets on a surface about to be cleared/deleted, so their
-- on_object_destroyed fires (which repairs the mod's surface-index registry).
function M.destroy_before_clear(surface)
  if not turret_names or not (surface and surface.valid) then return end
  local entities = surface.find_entities_filtered({force = "player", name = turret_names})
  for _, entity in ipairs(entities) do
    if entity.valid then
      entity.destroy({raise_destroy = true})
    end
  end
end

refresh_names()

return M