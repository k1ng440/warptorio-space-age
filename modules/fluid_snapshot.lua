local M = {}

function M.update_cache()
  storage.warptorio = storage.warptorio or {}
  storage.warptorio.fluid_entity_types = {}
  for name, prototype in pairs(prototypes.entity) do
    if prototype.fluidbox_prototypes and #prototype.fluidbox_prototypes > 0 then
      storage.warptorio.fluid_entity_types[#storage.warptorio.fluid_entity_types + 1] = name
    end
  end
end

-- Snapshot the fluid contents of every fluid-bearing entity on the floor before a
-- clone, then empty them. clone_brush rebalances fluids as each entity is cloned,
-- creating duplicates; this empties the source so the clone lands empty and the
-- snapshot restores exactly one copy of each box afterwards.
function M.snapshot_fluids(surface, offset)
  storage.warptorio = storage.warptorio or {}
  if not storage.warptorio.fluid_entity_types then
    M.update_cache()
  end
  local snapshot = {}
  local entities = surface.find_entities_filtered{
    area = {
      { offset.x - 500, offset.y - 500 },
      { offset.x + 500, offset.y + 500 }
    },
    name = storage.warptorio.fluid_entity_types
  }
  for _, e in pairs(entities) do
    if e.valid and e.fluidbox and #e.fluidbox > 0 then
      local boxes = {}
      for i = 1, #e.fluidbox do
        if e.fluidbox[i] then
          boxes[i] = {
            name = e.fluidbox[i].name,
            amount = e.fluidbox[i].amount,
            temperature = e.fluidbox[i].temperature
          }
          e.fluidbox[i] = nil
        end
      end
      local rel_x = math.floor((e.position.x - offset.x) * 10 + 0.5) / 10
      local rel_y = math.floor((e.position.y - offset.y) * 10 + 0.5) / 10
      snapshot[string.format("%.1f,%.1f", rel_x, rel_y)] = boxes
    end
  end
  storage.warptorio.warp_fluid_snapshot = snapshot
end

function M.get_fluid_snapshot()
  return (storage.warptorio and storage.warptorio.warp_fluid_snapshot) or {}
end

function M.clear_fluid_snapshot()
  if storage.warptorio then storage.warptorio.warp_fluid_snapshot = nil end
end

return M