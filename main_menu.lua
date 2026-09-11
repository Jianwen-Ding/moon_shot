-- Handles main menu input 

-- Static Options 
-- Map tile origin: reserve a 16x16 region beside the title screen.
Main_menu_background_loc = {16, 0}

Main_menu_sprite_background_id = 0
Main_menu_sprite_id_hover = 0

Main_menu_sprite_base_id = 0
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

function init_level_selector() 
end

function main_menu_init()
    
end

function main_menu_teardown()
    -- Release menu-specific resources here when needed.
end

local function get_current_level() 
    return ((Current_menu_loc[2] - 1) * Menu_bounds[1]) + Current_menu_loc[1]
end

function main_menu_update()
    if btn(0) ~= btn(1) then
        if btn(0) then
            Current_menu_loc[1] = max(Current_menu_loc[1] - 1, 1)
        else 
            Current_menu_loc[1] = min(Current_menu_loc[1] + 1, Menu_bounds[1])
        end 
    end

    if btn(2) ~= btn(3) then
        if btn(2) then
            Current_menu_loc[2] = max(Current_menu_loc[2] - 1, 1)
        else 
            Current_menu_loc[2] = min(Current_menu_loc[2] + 1, Menu_bounds[2])
        end 
    end

    if btn(4) then
        transition("Title", 0)
        return
    end

    if btn(5) then
        Current_level = get_current_level()
        transition("Gameplay", Current_level)
    end
end

function main_menu_draw()
    cls()
    map(Main_menu_background_loc[1], Main_menu_background_loc[2])
    Curr_level_idx = 1
    for x = 1,Menu_bounds[1] do
        for y = 1,Menu_bounds[2] do
            Current_level = get_current_level()
            Curr_level_idx = ((y - 1) * Menu_bounds[1]) + x
            Base_tile_x = Main_menu_sprite_locs[y][x][1]
            Base_tile_y = Main_menu_sprite_locs[y][x][2]
            if Curr_level_idx == get_current_level() then
                Inner_sprite_idx = Main_menu_sprite_id_hover
            else
                Inner_sprite_idx = Main_menu_sprite_background_id
            end
            spr(Inner_sprite_idx, Base_tile_x, Base_tile_y)
            spr(Main_menu_sprite_base_id + Curr_level_idx, Base_tile_x + Main_menu_base_sprite_offset[1], Base_tile_y + Main_menu_base_sprite_offset[2])
        end
    end
end
