-- Each level owns a 16x16 region on the lower half of the map.
-- Inventory values are sprite IDs resolved by Entity_spawn_handlers.
Levels = {
    {name="first flight", map_loc={0,16}, inventory={}, angle=0},
    {name="red crossing", map_loc={16,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="red stops ships, not moons"},
    {name="blue crossing", map_loc={32,16}, inventory={Id_default_planet_sprite}, angle=0, hint="blue stops moons, not ships"},
    {name="purple passage", map_loc={48,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="purple stops ships and moons"},
    {name="push apart", map_loc={64,16}, inventory={}, angle=0, hint="orange planets push away"},
    {name="black hole run", map_loc={80,16}, inventory={}, angle=0, hint="black holes pull and survive"},
    {name="cloud navigation", map_loc={96,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="thread blue, avoid red/purple"},
    {name="space sampler", map_loc={112,16}, inventory={Id_default_planet_sprite}, angle=0, hint="thread the fields and clouds"}
}
Campaign_complete = false
Completed_levels = {}
