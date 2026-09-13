-- Each level owns a 16x16 region on the lower half of the map.
-- Inventory values are sprite IDs resolved by Entity_spawn_handlers.
Levels = {
    {name="first flight", map_loc={0,16}, inventory={}, angle=0},
    {name="red nebulae", map_loc={16,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="red stops ships, not moons"},
    {name="ring around the rosie", map_loc={32,16}, inventory={Id_default_planet_sprite}, angle=0, hint="blue stops moons, not ships. Purple stops both."},
    {name="clearing the path", map_loc={48,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="moons can pull in other moons"},
    {name="clearing the trail", map_loc={64,16}, inventory={Id_default_planet_sprite, Id_default_planet_sprite}, angle=0},
    {name="expulsion", map_loc={80,16}, inventory={}, angle=0, hint="orange planets push back other planets"},
    {name="pool table", map_loc={96,16}, inventory={Id_repulse_planet_sprite}, angle=0.055, hint="moons can be pushed away"},
    {name="final orbit", map_loc={112,16}, inventory={Id_repulse_planet_sprite}, angle=0}
}
Campaign_complete = false
Completed_levels = {}
