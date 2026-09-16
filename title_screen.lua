-- Title artwork starts at sprite 131 and fills the 128x128 screen.
Title_screen_sprite = 131

function title_screen_init()
end

function title_screen_teardown()
    -- Release title-specific resources here when needed.
end

function title_screen_update()
    if btnp(5) then
        transition("MainMenu")
    end
end

function title_screen_draw()
    cls(0)
    sspr((Title_screen_sprite%16)*8, flr(Title_screen_sprite/16)*8,
        64, 64, 0, 0, 128, 128)
    print("press x to continue", 26, 118, 10)
end
