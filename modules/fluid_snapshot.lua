local M = {}

function M.update_cache()
    storage.warptorio.fluid_entity_types = {}
    for name, prototype in pairs(prototypes.entity) do
        if prototype.fluidbox_prototypes and #prototype.fluidbox_prototypes > 0 then
            storage.warptorio.fluid_entity_types[#storage.warptorio.fluid_entity_types + 1] = name
        end
    end
end

function M.snapshot_fluids(surface, offset)
    if not storage.warptorio.fluid_entity_types then
        M.update_cache()
    end
    local snapshot = {}
    local entities = surface.find_entities_filtered{
        area = {
            {offset.x - 500, offset.y - 500},
            {offset.x + 500, offset.y + 500}
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

function M.snapshot_machine_states(surface, offset)
    local states = {}
    local entities = surface.find_entities_filtered{
        area = {
            {offset.x - 500, offset.y - 500},
            {offset.x + 500, offset.y + 500}
        }
    }
    for _, e in pairs(entities) do
        if e.valid and e.active ~= nil then
            local rel_x = math.floor((e.position.x - offset.x) * 10 + 0.5) / 10
            local rel_y = math.floor((e.position.y - offset.y) * 10 + 0.5) / 10
            states[string.format("%.1f,%.1f", rel_x, rel_y)] = e.active
            e.active = false
        end
    end
    storage.warptorio.warp_machine_states = states
end

function M.get_fluid_snapshot()
    return storage.warptorio.warp_fluid_snapshot or {}
end

function M.get_machine_states()
    return storage.warptorio.warp_machine_states or {}
end

function M.clear_fluid_snapshot()
    storage.warptorio.warp_fluid_snapshot = {}
end

function M.clear_machine_states()
    storage.warptorio.warp_machine_states = {}
end

return M
