-- Throwing Logic 
Current_throw_angle = 0
Current_throw_strength = 0
Current_throw_cooldown = 0
Throw_inventory_ids = {}

Throw_cooldown = 30
Throw_angle_speed = 1
Throw_strength_speed = 1
Throw_angle_min = 0
Throw_angle_max = 0
Throw_strength_min = 0
Throw_strength_max = 0 
Thrown_self = false

Throw_inventory_level_ids = {{}} -- moon inventory per level

-- UI Logic 

Ui_frame_start_loc = {0, 0}
Ui_frame_dist_apart = 0
Ui_frame_sprite = 0
Ui_selected_frame_sprite = 0


function player_systems_init()
    Current_throw_angle = 0
    Current_throw_strength = 0
    Throw_inventory_ids = {}
end

function player_systems_update()
    if btn(4) then 
        transition("MainMenu")
    end 

    if ~Thrown_self then 
        -- Handle player input and throwing here.
        if btn(0) ~= btn(1) then 
            if btn(0) then
                Current_throw_angle = math.max(Throw_angle_min, Current_throw_angle - Throw_angle_speed)
            else 
                Current_throw_angle = math.min(Throw_angle_max, Current_throw_angle + Throw_angle_speed)
            end
        end

        if btn(2) ~= btn(3) then 
            if btn(2) then
                Current_throw_strength = math.max(Throw_strength_max, Current_throw_angle - Throw_angle_speed)
            else 
                Current_throw_strength = math.min(Throw_strength_min, Current_throw_angle + Throw_angle_speed)
            end
        end

        -- Actually throws the object 
        Current_throw_cooldown = Current_throw_cooldown - 1
        if btn(5) and Current_throw_cooldown <= 0 then 
            Current_throw_cooldown = Throw_cooldown

            local thrown_entity
            if #Throw_inventory_ids == 0 then
                -- throws self
            else 
                -- throws object using 
                thrown_entity = Gameplay_spawn_handlers[Throw_inventory_ids[0]]()
            end
            thrown_physics = thrown_entity.physics_component
        end 
    end 
end

function player_systems_draw()
    -- Draw aiming indicators and inventory UI here.
end
