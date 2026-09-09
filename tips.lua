data:extend({
  {
    type = "tips-and-tricks-item-category",
    name = "warptorio",
    order = "a",
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio",
    category = "warptorio",
    order = "a",
    starting_status = "unlocked",
    is_title = true,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-floors",
    tag = "[entity=warp_2x2-container]",
    order = "b[floors]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-ground-platform-1"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-minimap",
    tag = "[entity=radar]",
    order = "c[minimap]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-factory-platform-1"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-derelict-platform",
    tag = "[entity=warp-power]",
    order = "d[derelict]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-ground-platform-2"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-void",
    tag = "[entity=warp-asteroid-chest]",
    order = "e[void]",
    category = "warptorio",
    starting_status = "unlocked",
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-planet-hopping",
    tag = "[planet=nauvis]",
    order = "f[planet-hopping]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "chemical-science-pack"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-evolution-scaling",
    tag = "[entity=big-biter]",
    order = "g[evolution-scaling]",
    category = "warptorio",
    trigger = {
  	  type = "or",
  	  triggers = {
  	  {
    		type = "research",
    		technology = "warp-ground-platform-3"
  	  },
  	  {
    		type = "research",
    		technology = "warp-factory-platform-2"
  	  }}
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-asteroids",
    tag = "[entity=big-carbonic-asteroid]",
    order = "h[asteroids]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-factory-platform-2"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-warp-combinator",
    tag = "[item=warp-constant-combinator]",
    order = "i[warp-combinator]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-circuit-network"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-floor-limits",
    tag = "[entity=roboport]",
    order = "j[floor-limits]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-biochamber-platform-1"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-warp-trains",
    tag = "[entity=locomotive]",
    order = "k[warp-trains]",
    category = "warptorio",
    trigger = {
      type = "research",
      technology = "warp-train"
    },
    is_title = false,
    indent = 1,
    simulation = nil,
  },
  {
    type = "tips-and-tricks-item",
    name = "warptorio-warp-vote",
    tag = "[entity=gun-turret]",
    order = "l[warp-vote]",
    category = "warptorio",
    starting_status = "unlocked",
    is_title = false,
    indent = 1,
    simulation = nil,
  },

})