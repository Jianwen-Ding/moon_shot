-- Handles main menu input 

-- Static Options 
-- Map tile origin: reserve a 16x16 region beside the title screen.
Main_menu_background_loc = {16, 0}

Main_menu_sprite_background_id = 48
Main_menu_sprite_id_hover = 49

Main_menu_sprite_base_id = 63
-- Pixel offset: align the two 8x8 sprite layers.
Main_menu_base_sprite_offset = {0, 0}


-- Pixel positions, indexed by row then column (both starting at 1).
-- Eight levels in four centered columns, with room above for a heading.
Main_menu_sprite_locs = {
    {{24, 52}, {48, 52}, {72, 52}, {96, 52}},
    {{24, 76}, {48, 76}, {72, 76}, {96, 76}}
}


-- Dynamic Options 
-- Coordinate pairs use [1] for x/column and [2] for y/row.
Current_menu_loc = {1, 1}
Menu_bounds = {4, 2}
local z_released = true

function init_level_selector() 
end

function main_menu_init()
    z_released = not btn(4)
    local selected = mid(1, Current_level, #Levels)
    Current_menu_loc = {((selected-1)%Menu_bounds[1])+1, flr((selected-1)/Menu_bounds[1])+1}
end

function main_menu_teardown()
    -- Release menu-specific resources here when needed.
end

local function get_current_level() 
    return ((Current_menu_loc[2] - 1) * Menu_bounds[1]) + Current_menu_loc[1]
end

function main_menu_update()
    -- Ignore the Z hold that brought us here until the button is released.
    if not btn(4) then z_released = true end
    if btnp(0) ~= btnp(1) then
        if btnp(0) then
            Current_menu_loc[1] = max(Current_menu_loc[1] - 1, 1)
        else 
            Current_menu_loc[1] = min(Current_menu_loc[1] + 1, Menu_bounds[1])
        end 
    end

    if btnp(2) ~= btnp(3) then
        if btnp(2) then
            Current_menu_loc[2] = max(Current_menu_loc[2] - 1, 1)
        else 
            Current_menu_loc[2] = min(Current_menu_loc[2] + 1, Menu_bounds[2])
        end 
    end

    if z_released and btnp(4) then
        transition("Title")
        return
    end

    if btnp(5) then
        transition("Gameplay", get_current_level())
    end
end

function main_menu_draw()
    map(Main_menu_background_loc[1], Main_menu_background_loc[2], 0, 0, 16, 16)
    print("choose your orbit", 30, 24, 7)
    if Campaign_complete then print("all 8 levels complete!", 22, 36, 11) end
    for x = 1,Menu_bounds[1] do
        for y = 1,Menu_bounds[2] do
            local level = ((y - 1) * Menu_bounds[1]) + x
            local tile_x, tile_y = Main_menu_sprite_locs[y][x][1], Main_menu_sprite_locs[y][x][2]
            local frame = level == get_current_level() and Main_menu_sprite_id_hover or Main_menu_sprite_background_id
            spr(frame, tile_x, tile_y)
            spr(Main_menu_sprite_base_id + level, tile_x + Main_menu_base_sprite_offset[1], tile_y + Main_menu_base_sprite_offset[2])
            if Completed_levels[level] then pset(tile_x+3, tile_y+10, 11) end
        end
    end
    print("arrows: select", 36, 99, 6)
    print("x: play   z: title", 28, 109, 7)
end
