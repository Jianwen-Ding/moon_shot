-- Map tile origin of the title's 16x16 region.
Title_screen_sprite = {0, 0}

function title_screen_init()
end

function title_screen_teardown()
    -- Release title-specific resources here when needed.
end

function title_screen_update()
    if btnp(4) or btnp(5) then
        transition("MainMenu")
    end
end

function title_screen_draw()
    map(Title_screen_sprite[1], Title_screen_sprite[2], 0, 0, 16, 16)
    print("moon shot", 46, 28, 7)
    spr(Id_ship_sprite, 34, 52)
    spr(Id_goal_planet_sprite, 86, 52)
    line(47, 55, 77, 55, 10)
    print("throw moons to clear a path", 12, 76, 6)
    print("then launch your ship", 24, 86, 6)
    print("press x or z", 40, 106, 10)
end
