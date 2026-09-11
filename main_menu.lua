-- Handles main menu input 

-- Static Options 
main_menu_background_loc = {0, 0}

main_menu_sprite_background_id = 0
main_menu_sprite_base_id = 0
main_menu_sprite_id_hover = 0
main_menu_sprite_locs = {{{0,0}}}


-- Dynamic Options 
current_menu_loc = {0, 0}
menu_bounds = {0, 0}



function mainMenuInit()

end

function mainMenuUpdate()
    if btn(0) ~= btn(1) then
        if btn(0) then
            current_menu_loc[1] = math.min(current_menu_loc[1] + 1, menu_bounds[1])
        else 
            current_menu_loc[1] = math.max(current_menu_loc[1] - 1, menu_bounds[1])
        end 
    end

    if btn(3) ~= btn(4) then
        if btn(3) then
            current_menu_loc[0] = math.min(current_menu_loc[0] + 1, menu_bounds[0])
        else 
            current_menu_loc[0] = math.max(current_menu_loc[0] - 1, menu_bounds[0])
        end 
    end

    if btn(4) then
        transition("Title", 0)
        return
    end

    if btn(5) then
        transition("Gameplay", (current_menu_loc[1] * menu_bounds[0]) + current_menu_loc[0])
    end
end

function mainMenuDraw()
    
end