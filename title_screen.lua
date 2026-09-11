-- Map tile origin of the title's 16x16 region.
title_screen_sprite = {0, 0}

function title_screen_init()
    cls()
    map(title_screen_sprite[1], title_screen_sprite[2])
end

function title_screen_teardown()
    -- Release title-specific resources here when needed.
end

function title_screen_update()
    if btn() then
        transition("MainMenu", 0)
    end
end

function title_screen_draw()
    cls()
    map(title_screen_sprite[1], title_screen_sprite[2])
end
