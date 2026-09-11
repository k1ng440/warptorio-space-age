local shared = require("shared")
local speech_bubbles = require("modules.speech_bubbles")
local warp_constant_combinator = require("warp_constant_combinator")
local warp_settings = require("internal_settings")

local M = {}

function M.build_entity(e)
  warp_constant_combinator.register(e.entity)
  if e.entity.type == "roboport" then
    local surface = e.entity.surface.name
    if (surface == "factory" and warp_settings.block_roboport_factory) or
       (surface == "garden" and warp_settings.block_roboport_garden) then
      if e.player_index then
        game.players[e.player_index].insert({name = e.entity.name, count = 1, quality = e.entity.quality.name})
      end
      e.entity.destroy()
      if e.player_index then
        local player = game.players[e.player_index]
        if player.character and player.character.valid then
          speech_bubbles.speak(player.character, {"warptorio.roboport-blocked"}, 4)
        else
          player.print({"warptorio.roboport-blocked"}, {color = {1, 0, 0}})
        end
      end
      return
    end
  end
  if e.entity.name == shared.container then
    if storage.warptorio.container and storage.warptorio.container.valid then
      speech_bubbles.notify(e.player_index and game.players[e.player_index], {"warptorio.container-placed-error"}, 4, {1, 0, 0})
      e.entity.destroy()
      return
    else
      speech_bubbles.notify(e.player_index and game.players[e.player_index], {"warptorio.container-placed"}, 4)
    end
    storage.warptorio.container = e.entity
  end
  if e.entity.name == "warp-asteroid-chest" then
    if storage.warptorio.collector_chest and storage.warptorio.collector_chest.valid then
      speech_bubbles.notify(e.player_index and game.players[e.player_index], {"warptorio.collector-placed-error"}, 4, {1, 0, 0})
      e.entity.destroy()
      return
    elseif e.entity.surface.name ~= "factory" and e.entity.surface.name ~= "garden" then
      speech_bubbles.notify(e.player_index and game.players[e.player_index], {"warptorio.placed-error-surface"}, 4, {1, 0, 0})
      e.entity.destroy()
      return
    else
      speech_bubbles.notify(e.player_index and game.players[e.player_index], {"warptorio.collector-placed"}, 4)
      storage.warptorio.collector_chest = e.entity
    end
  end
  if e.entity.name == "biolab" then
    local tech = game.forces.player.technologies[warp_settings.ground.biolab_research]
    local levels = tech.level - 1
    local limit = warp_settings.ground.biolab_limit + warp_settings.ground.biolab_increase * levels
    local count = #e.entity.surface.find_entities_filtered{name = "biolab"}
    if count > limit then
      if e.player_index then
        game.players[e.player_index].insert({name = e.entity.name, count = 1, quality = e.entity.quality.name})
      end
      e.entity.destroy()
      if e.player_index then
        game.players[e.player_index].print({"warptorio.biolab-limit-reached", limit}, {color = {1, 0, 0}})
      end
      return
    end
  end
end

return M
