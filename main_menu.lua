-- Handles main menu input 

-- Static Options 
-- Map tile origin: reserve a 16x16 region beside the title screen.
main_menu_background_loc = {16, 0}

main_menu_sprite_background_id = 0
main_menu_sprite_id_hover = 0

main_menu_sprite_base_id = 0
-- Pixel offset: align the two 8x8 sprite layers.
main_menu_base_sprite_offset = {0, 0}


-- Pixel positions, indexed by row then column (both starting at 1).
-- Five columns spaced 24px apart, with room above for a heading.
main_menu_sprite_locs = {
    {
        {12, 52}, {36, 52}, {60, 52},
        {84, 52}, {108, 52}
    },
    {
        {12, 76}, {36, 76}, {60, 76},
        {84, 76}, {108, 76}
    }
}


-- Dynamic Options 
-- Coordinate pairs use [1] for x/column and [2] for y/row.
current_menu_loc = {1, 1}
menu_bounds = {5, 2}

function init_level_selector() 
end

function main_menu_init()
    
end

function main_menu_teardown()
    -- Release menu-specific resources here when needed.
end

local function get_current_level() 
    return ((current_menu_loc[2] - 1) * menu_bounds[1]) + current_menu_loc[1]
end
function main_menu_update()
    if btn(0) ~= btn(1) then
        if btn(0) then
            current_menu_loc[1] = max(current_menu_loc[1] - 1, 1)
        else 
            current_menu_loc[1] = min(current_menu_loc[1] + 1, menu_bounds[1])
        end 
    end

    if btn(2) ~= btn(3) then
        if btn(2) then
            current_menu_loc[2] = max(current_menu_loc[2] - 1, 1)
        else 
            current_menu_loc[2] = min(current_menu_loc[2] + 1, menu_bounds[2])
        end 
    end

    if btn(4) then
        transition("Title", 0)
        return
    end

    if btn(5) then
        current_level = get_current_level()
        transition("Gameplay", current_level)
    end
end

function main_menu_draw()
    cls()
    map(main_menu_background_loc[1], main_menu_background_loc[2])
    curr_level_idx = 1
    for x = 1,menu_bounds[1] do
        for y = 1,menu_bounds[2] do
            current_level = get_current_level()
            curr_level_idx = ((y - 1) * menu_bounds[1]) + x
            base_tile_x = main_menu_sprite_locs[y][x][1]
            base_tile_y = main_menu_sprite_locs[y][x][2]
            if curr_level_idx == get_current_level() then
                inner_sprite_idx = main_menu_sprite_id_hover
            else
                inner_sprite_idx = main_menu_sprite_background_id
            end
            spr(inner_sprite_idx, base_tile_x, base_tile_y)
            spr(main_menu_sprite_base_id + curr_level_idx, base_tile_x + main_menu_base_sprite_offset[1], base_tile_y + main_menu_base_sprite_offset[2])
        end
    end
end
