-- Each level owns a 16x16 region on the lower half of the map.
-- Inventory values are sprite IDs resolved by Entity_spawn_handlers.
Levels = {
    {name="first flight", map_loc={0,16}, inventory={}, angle=0},
    {name="moon practice", map_loc={16,16}, inventory={Id_default_planet_sprite}, angle=0},
    {name="clear a path", map_loc={32,16}, inventory={Id_default_planet_sprite}, angle=0},
    {name="double trouble", map_loc={48,16}, inventory={Id_default_planet_sprite,Id_default_planet_sprite}, angle=0},
    {name="upward bound", map_loc={64,16}, inventory={Id_default_planet_sprite}, angle=0.09},
    {name="downward bound", map_loc={80,16}, inventory={Id_default_planet_sprite}, angle=-0.09},
    {name="gravity alley", map_loc={96,16}, inventory={Id_default_planet_sprite,Id_default_planet_sprite}, angle=0},
    {name="home stretch", map_loc={112,16}, inventory={Id_default_planet_sprite,Id_default_planet_sprite,Id_default_planet_sprite}, angle=0}
}
Campaign_complete = false
Completed_levels = {}
