-- Throwing Logic 
current_throw_angle = 0
current_throw_strength = 0
throw_inventory_ids = {}

throw_inventory_level_ids = {{}} -- moon inventory per level

-- UI Logic 
ui_frame_sprite = 0 -- Todo 
ui_selected_frame_sprite = 0 -- Todo 

function player_systems_init()
    current_throw_angle = 0
    current_throw_strength = 0
    throw_inventory_ids = {}
end

function player_systems_update()
    -- Handle player input and throwing here.
end

function player_systems_draw()
    -- Draw aiming indicators and inventory UI here.
end

