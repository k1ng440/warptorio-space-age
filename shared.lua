-- Shared data interface between data and script, notably prototype names.
-- Required by BOTH data.lua (data stage) and control.lua (runtime stage).
-- These are two separate Lua states, keep this file free of stage-specific
-- globals (`data`, `script`, `game`, `settings`).

local shared = {}

-- Surfaces
shared.surfaces = {
  factory = "factory",
  garden = "garden",
  space = "space",
  nauvis = "nauvis",
  void = "void",
  transition = "warp-space-transition",
}

-- Tiles
shared.tiles = {
  factory = "warp_tile_platform",
  ground = "warp_tile_world",
}

-- Containers
shared.container = "warp_2x2-container"
shared.asteroid_collector = "warp-asteroid-chest"

-- Power capacitors, index = tier (1 => warp-power)
shared.power = {
  "warp-power",
  "warp-power-2",
  "warp-power-3",
}

-- Platform linked belts
shared.belt = {
  prefix = "warp-platform-belt-",
  speeds = {15, 30, 45, 60},
}

-- Combinator
shared.combinator = "warp-constant-combinator"

-- Effects
shared.speech_bubble = "warptorio_speech_bubble"
shared.platform_build_anim = "warptorio-platform-build-anim"
shared.teleport_explosion = "warptorio-teleport-explosion"
shared.teleport_boom_sound = "warptorio-teleport-boom"
shared.teleport_ring_1 = "warptorio-teleport-ring-1"
shared.teleport_ring_2 = "warptorio-teleport-ring-2"
shared.teleport_spark_particle = "warptorio-teleport-spark"
shared.teleport_spark_effect = "warptorio-teleport-spark-fx"

-- Shortcuts / custom inputs
shared.shortcut_teleport = "warptorio-teleport"
shared.shortcut_minimap_toggle = "warptorio-ground-minimap-toggle"
shared.input_minimap_zoom_in = "warptorio-ground-minimap-zoom-in"
shared.input_minimap_zoom_out = "warptorio-ground-minimap-zoom-out"

-- Sounds
shared.sounds = {
  warp_start = "warp-start",
  warp_end = "warp-end",
  planet_change = "planet-change",
  boss_spawn = "boss-spawn",
  teleport = "warptorio-teleport",
}

-- Quality
shared.quality_warp = "warp"

-- Technologies checked at runtime
shared.techs = {
  end_prepare = "warp-end-prepare",
  end_win = "warp-end-win",
  train = "warp-train",
}

-- Custom events defined in data stage. Other mods subscribe with:
--   script.on_event(defines.events["warptorio-warp-finished"], handler)
-- Their handlers receive the data table documented in modules/events.lua.
shared.events = {
  warp_started = "warptorio-warp-started",
  warp_finished = "warptorio-warp-finished",
  planet_chosen = "warptorio-planet-chosen",
  wave_spawned = "warptorio-wave-spawned",
  boss_spawned = "warptorio-boss-spawned",
  game_over = "warptorio-game-over",
  game_win = "warptorio-game-win",
}

return shared