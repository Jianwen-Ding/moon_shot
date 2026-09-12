-- Aim uses PICO-8 turns: 0 points right and 0.25 points up.
Current_throw_angle = 0
Current_throw_strength = 1
Current_throw_cooldown = 0
Throw_inventory_ids = {}
Throw_inventory_sprites = {}
Throw_inventory_level_ids = {}
Thrown_self = false

Restart_hold_duration = 1 -- seconds before a held Z returns to the main menu
local z_hold_started_at = nil
local z_hold_triggered = false

Throw_cooldown = 15
Throw_angle_speed = 0.01
Throw_strength_speed = 0.1
Throw_angle_min = -0.375
Throw_angle_max = 0.375
Throw_strength_min = 0.25
Throw_strength_max = 2

Ui_frame_start_loc = {8, 112}
Ui_frame_offset = {0, 0}
Ui_frame_dist_apart = 12
Ui_frame_sprite = 48
Ui_selected_frame_sprite = 49

function player_systems_init()
    -- Preserve a held Z across an automatic level restart or progression.
    if not btn(4) then
        z_hold_started_at = nil
        z_hold_triggered = false
    end
    Current_throw_angle = Active_level.angle or 0
    Current_throw_strength = mid(Throw_strength_min, Active_level.strength or 1, Throw_strength_max)
    Current_throw_cooldown = 0
    Thrown_self = false
    Throw_inventory_ids = {}
    Throw_inventory_sprites = {}
    -- Copy the inventory so throwing never edits the level definition.
    Throw_inventory_level_ids = {}
    for i, level in ipairs(Levels) do
        Throw_inventory_level_ids[i] = level.inventory
    end
    for _, id in ipairs(Active_level.inventory) do
        add(Throw_inventory_ids, id)
        add(Throw_inventory_sprites, id)
    end
end

function player_systems_update()
    if Transition_state ~= "idle" then return end
    if btn(4) then
        z_hold_started_at = z_hold_started_at or time()
        if not z_hold_triggered and time()-z_hold_started_at >= Restart_hold_duration then
            z_hold_triggered = true
            transition("MainMenu")
        end
        return
    elseif z_hold_started_at then
        local restart = not z_hold_triggered
        z_hold_started_at = nil
        z_hold_triggered = false
        if restart then
            transition("Gameplay", Current_level)
            return
        end
    end
    Current_throw_cooldown = max(0, Current_throw_cooldown-1)
    if Thrown_self or Level_failed or not Player_entity or not Player_entity.transform then return end

    if btn(0) ~= btn(1) then
        local direction = btn(0) and 1 or -1
        Current_throw_angle = mid(Throw_angle_min,
            Current_throw_angle + direction*Throw_angle_speed, Throw_angle_max)
    end
    if btn(2) ~= btn(3) then
        local direction = btn(2) and 1 or -1
        Current_throw_strength = mid(Throw_strength_min,
            Current_throw_strength + direction*Throw_strength_speed, Throw_strength_max)
    end

    if btnp(5) and Current_throw_cooldown == 0 then
        local dx, dy = cos(Current_throw_angle), sin(Current_throw_angle)
        local thrown_entity
        if #Throw_inventory_ids == 0 then
            thrown_entity = Player_entity
            Thrown_self = true
        else
            local id = Throw_inventory_ids[1]
            local spawner = Entity_spawn_handlers[id]
            if not spawner then return end
            -- Clear the launcher's collider before enabling projectile physics.
            local position = Player_entity.transform
            thrown_entity = spawner(position.x + dx*10, position.y + dy*10)
            deli(Throw_inventory_ids, 1)
            deli(Throw_inventory_sprites, 1)
        end
        local physics = thrown_entity.physics_component
        if not physics then
            physics = attach_component(thrown_entity, "physics_component", {vel_x=0,vel_y=0}, Physics_components)
        end
        physics.vel_x = dx*Current_throw_strength
        physics.vel_y = dy*Current_throw_strength
        Current_throw_cooldown = Throw_cooldown
    end
end

function player_systems_draw()
    print("level "..Current_level.."  "..Active_level.name, 4, 4, 7)
    print("arrows: aim/power", 4, 13, 6)
    print("z: restart  hold z: menu", 4, 122, 6)
    if Active_level.hint then print(Active_level.hint, 4, 22, 6) end

    if not Thrown_self and not Level_failed and Player_entity and Player_entity.transform then
        local pos = Player_entity.transform
        local dx, dy = cos(Current_throw_angle), sin(Current_throw_angle)
        local length = 12 + Current_throw_strength*5
        line(flr(pos.x+dx*6), flr(pos.y+dy*6), flr(pos.x+dx*length), flr(pos.y+dy*length), 10)
    end

    local start_x, start_y = Ui_frame_start_loc[1], Ui_frame_start_loc[2]
    -- The ship is the final inventory item, after all available moons.
    local count = #Throw_inventory_ids + (Thrown_self and 0 or 1)
    for index = 1, count do
        local x = start_x + (index-1)*Ui_frame_dist_apart
        local frame = index == 1 and Ui_selected_frame_sprite or Ui_frame_sprite
        local id = Throw_inventory_sprites[index] or Id_ship_sprite
        spr(frame, flr(x), flr(start_y))
        spr(id, flr(x+Ui_frame_offset[1]), flr(start_y+Ui_frame_offset[2]))
    end
    if Level_failed then
        print("try again...", 70, 113, 8)
    elseif Thrown_self then
        print("in flight", 70, 113, 11)
    else
        print("x: throw", 82, 104, 7)
        rect(82, 113, 121, 118, 6)
        local power = (Current_throw_strength-Throw_strength_min)/(Throw_strength_max-Throw_strength_min)
        rectfill(83, 114, 83+flr(power*37), 117, 10)
    end
end
