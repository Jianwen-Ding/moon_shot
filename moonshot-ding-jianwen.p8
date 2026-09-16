pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

Scene = "Title"
Latest_level = 0
Current_level = 0

-- Dispatch by the sprite ID stored in each map cell.
-- Bounds and callback coordinates are in map tiles. Defaults: base 128x32 map.
-- Each handler receives map coordinates in tiles and the sprite ID.
function scan_map(handlers, map_x, map_y, width, height)
    map_x = map_x or 0
    map_y = map_y or 0
    width = width or 128
    height = height or 32

    for y = map_y, map_y + height - 1 do
        for x = map_x, map_x + width - 1 do
            local sprite = mget(x, y)
            -- Sprite 0 represents an empty map cell.
            if sprite ~= 0 then
                local handler = handlers[sprite]
                if handler then
                    handler(x, y, sprite)
                end
            end
        end
    end
end

-- Reserved 16x16 transition artwork region, in map tile coordinates.
Transition_map = {64, 0}
Transition_duration = 0.5
Transition_time = 0
Transition_x = 128
Transition_state = "idle"
Transition_scene = nil
Transition_level = nil
Transition_started_at = 0

function transition(new_scene, level)
    if Transition_state ~= "idle" then
        return
    end

    Transition_scene = new_scene
    Transition_level = level
    Transition_time = 0
    Transition_x = 128
    Transition_started_at = time()
    Transition_state = "covering"
    Latest_level = max(Transition_level, Latest_level)
end

function transition_update()
    if Transition_state == "idle" then
        return
    end

    local phase_duration = Transition_duration / 2

    if Transition_state == "covering" then
        local progress = 1
        if phase_duration > 0 then
            progress = min((time() - Transition_started_at) / phase_duration, 1)
        end

        Transition_time = progress * phase_duration
        Transition_x = 128 - progress * 128

        if progress < 1 then
            return
        end

        -- Swap scenes only while the map covers every screen pixel.
        Transition_x = 0
        teardown_scene()
        Scene = Transition_scene

        if Transition_level ~= nil then
            Current_level = Transition_level
        end

        init_scene()
        Transition_started_at = time()
        Transition_state = "revealing"
        return
    end

    local progress = 1
    if phase_duration > 0 then
        progress = min((time() - Transition_started_at) / phase_duration, 1)
    end

    Transition_time = phase_duration + progress * phase_duration
    Transition_x = -progress * 128

    if progress >= 1 then
        Transition_state = "idle"
        Transition_scene = nil
        Transition_level = nil
        Transition_x = -128
    end
end

function transition_draw()
    if Transition_state ~= "idle" then
        camera()
        map(Transition_map[1], Transition_map[2], flr(Transition_x), 0, 16, 16)
    end
end

-- Reserved 16x16 map regions, in tile coordinates (x, y).
Background_loc = {32, 0}
Gameplay_loc = {48, 0}

-- Sprite IDs in the cartridge's starter artwork.
Id_ship_sprite = 16
Id_goal_planet_sprite = 17
Id_default_planet_sprite = 18
Id_black_hole_sprite = 80
Id_default_gravity_sprite = 5
Id_repulsive_gravity_sprite = 72
Id_destruct_base_sprite = 32
Id_repulse_planet_sprite = 81
-- Dedicated nebula rows: add frames to the right, then increase frames (up to 16).
Id_purple_nebula_sprite_base = 160
Id_purple_nebula_frames = 3
Id_blue_nebula_sprite_base = 144
Id_blue_nebula_frames = 3
Id_red_nebula_sprite_base = 128
Id_red_nebula_frames = 3

Player_entity = nil
Active_level = nil
Level_failed = false
Planet_drag = 0.98


-- Holds entities and their attached components, including position transforms.
Entities = {} 

-- holds all specific logic of the entity
-- Component lists are independent of the entity list.
-- component.entity points to its owner; entity.square_collider,
-- entity.circle_collider, etc. point back to the attached components.
-- Transforms give shape centers; rectangle width and height are full sizes.
-- Keep fractional transform coordinates for physics and collisions.
-- Convert to whole pixels only when drawing; never round the transform itself.
-- entity.collisions contains references to touching entities.
Square_colliders = {}
Circle_colliders = {}
Gravity_colliders = {}
Physics_components = {}
Gravity_components = {}
Sprite_components = {}
Countdown_components = {}
Animation_components = {}

-- Register both directions without relying on matching list indices.
function attach_component(entity, name, component, components)
    component.entity = entity
    entity[name] = component
    add(components, component)
    return component
end

-- Start or restart a lifetime measured in seconds of active gameplay.
local function start_countdown(entity, duration)
    local countdown = entity.countdown_component
    if countdown == nil then
        countdown = attach_component(entity, "countdown_component", {}, Countdown_components)
    end
    countdown.duration = max(0, duration)
    countdown.elapsed_frames = 0
    countdown.elapsed_time = 0
    return countdown
end

local function destroy_entity(entity)
    if entity == Player_entity then
        Player_entity = nil
    end
    if entity.gravity_entity then
        local gravity_entity = entity.gravity_entity
        entity.gravity_entity = nil
        destroy_entity(gravity_entity)
    end
    -- Resolve ownership through references, independently of list order.
    local component_lists = {
        Square_colliders, Circle_colliders, Physics_components,
        Gravity_components, Sprite_components, Countdown_components,
        Animation_components
    }
    for _, components in ipairs(component_lists) do
        for i = #components, 1, -1 do
            local component = components[i]
            if component.entity == entity then
                for name, attached in pairs(entity) do
                    if attached == component then
                        entity[name] = nil
                    end
                end
                del(components, component)
                component.entity = nil
            end
        end
    end

    -- Remove stale contact references before any remaining physics runs.
    for _, other in pairs(Entities) do
        if other.collisions then
            for i = #other.collisions, 1, -1 do
                if other == entity or other.collisions[i] == entity then
                    del(other.collisions, other.collisions[i])
                end
            end
        end
    end
    del(Entities, entity)
    entity.collisions = nil
    -- Detach the transform without modifying a transform shared by an owner.
    entity.transform = nil
end

local function update_countdowns()
    local expired = {}
    for _, countdown in pairs(Countdown_components) do
        -- The cartridge uses _update (30 updates per second).
        countdown.elapsed_frames = (countdown.elapsed_frames or 0) + 1
        countdown.elapsed_time = countdown.elapsed_frames / 30
        if countdown.elapsed_time >= countdown.duration then
            expired[countdown.entity] = true
        end
    end
    -- Defer deletion until every timer has been checked.
    for entity in pairs(expired) do
        if entity.expire ~= nil then
            entity:expire()
        end
        destroy_entity(entity)
    end
end

local function restart_level() 
    if Transition_state == "idle" then
        transition("Gameplay", Current_level)
    end
end
-- Spawning logic

-- x/y are center coordinates in pixels; frames use consecutive sprite IDs.
-- Defaults: four frames, 0.125 seconds per frame, then destroy after 0.5 seconds.
local function spawn_timed_animation(x, y, base_id, frames, transition_delay, duration)
    frames = max(1, flr(frames or 4))
    transition_delay = max(0, transition_delay or 0.125)
    duration = duration or frames * transition_delay

    local entity = {transform={x=x, y=y}, collisions={}}
    add(Entities, entity)
    attach_component(entity, "sprite_component",
        {id=base_id, width=8, height=8}, Sprite_components)
    attach_component(entity, "animation_component", {
        base_id = base_id,
        frames = frames,
        transition_delay = transition_delay,
        transition_time = 0,
        looped = false
    }, Animation_components)
    start_countdown(entity, duration)
    return entity
end

local function regular_collision(entity, other)
    if entity.destroy_pending then
        return
    end
    entity.destroy_pending = true
    local explosion = spawn_timed_animation(entity.transform.x, entity.transform.y, Id_destruct_base_sprite, 4, 0.05, 0.25)
    if entity.tag == "ship" or entity.tag == "goal" then
        Level_failed = true
        explosion.expire = restart_level
    end
    return explosion
end

local function goal_planet_collision(entity, other)
    -- Landing the ship on the goal is handled by the ship's win callback.
    if other.tag ~= "ship" then
        regular_collision(entity, other)
    end
end

local base_planet_spawn

-- Spawners take centered pixel coordinates; map handlers convert tile positions.
function default_planet_spawn(x, y)
    local entity = base_planet_spawn(x, y, Id_default_planet_sprite, Id_default_gravity_sprite, 4, 24, 0.10, true)
    entity.collided = regular_collision
    return entity
end 

function repulse_planet_spawn(x, y)
    local entity = base_planet_spawn(x, y, Id_repulse_planet_sprite, Id_repulsive_gravity_sprite, 4, 24, -0.05, true)
    entity.collided = regular_collision
    return entity
end

function black_hole_spawn(x, y)
    local entity = base_planet_spawn(x, y, Id_black_hole_sprite, Id_default_gravity_sprite, 4, 24, 0.15, false)
    entity.tag = "black_hole"
    return entity
end 

function goal_planet_spawn(x, y)
    local entity = base_planet_spawn(x, y, Id_goal_planet_sprite, Id_default_gravity_sprite, 7, 16, 0.10, false)
    entity.tag = "goal"
    entity.collided = goal_planet_collision
    return entity
end

base_planet_spawn = function(x, y, sprite, gravity_sprite, size, range, force, physics_enabled)
    local transform = {x=x, y=y}

    -- Set up gravity entity 
    local gravity_entity = {transform=transform, collisions={}}

    gravity_collider = {radius=range}
    attach_component(gravity_entity, "circle_collider", gravity_collider, Circle_colliders)
    attach_component(gravity_entity, "gravity_component", {force=force}, Gravity_components)

    attach_component(gravity_entity, "animation_component",
        {base_id=gravity_sprite, frames=2, frame_stride=4, transition_delay=0.5, transition_time=0, looped=true}, Animation_components)
    attach_component(gravity_entity, "sprite_component",
        {id=gravity_sprite, width=range*2, height=range*2, source_width=32, source_height=32}, Sprite_components)

    add(Entities, gravity_entity)
    add(Gravity_colliders, gravity_collider)
    gravity_entity.tag = "gravity"

    -- Set up base entity
    local base_entity = {transform=transform, collisions={}, gravity_entity=gravity_entity}

    attach_component(base_entity, "circle_collider", {radius=size/2}, Circle_colliders)
    attach_component(base_entity, "sprite_component", {id=sprite, width=8, height=8}, Sprite_components)
    if physics_enabled then
        attach_component(base_entity, "physics_component", {vel_x=0, vel_y=0, drag=Planet_drag}, Physics_components)
    end

    add(Entities, base_entity)
    base_entity.tag = "planet"

    return base_entity
end

local function goal_collision(entity, other)
    if other.tag == "goal" and not Level_failed then
        Latest_level = max(Latest_level, Current_level)
        Completed_levels[Current_level] = true
        Campaign_complete = true
        for index = 1, #Levels do
            if not Completed_levels[index] then Campaign_complete = false end
        end
        if Current_level == #Levels then
            transition("MainMenu")
        else
            transition("Gameplay", Current_level + 1)
        end
        return
    end
    regular_collision(entity, other)
end

local function planet_filter(tag)
    return tag == "planet"
end

local function ship_filter(tag)
    return tag == "ship"
end

local function body_filter(tag)
    return tag == "ship" or tag == "planet" or tag == "goal"
end

local function nebula_spawn(x, y, sprite, frames, filter)
    local entity = {transform={x=x,y=y}, collisions={}, tag="nebula"}
    add(Entities, entity)
    attach_component(entity, "square_collider", {width=8,height=8,filter=filter}, Square_colliders)
    attach_component(entity, "sprite_component", {id=sprite,width=8,height=8}, Sprite_components)
    attach_component(entity, "animation_component",
        {base_id=sprite,frames=frames,transition_delay=0.5,transition_time=0,looped=true}, Animation_components)
    return entity
end

function red_nebula_spawn(x, y)
    return nebula_spawn(x, y, Id_red_nebula_sprite_base, Id_red_nebula_frames, ship_filter)
end

function blue_nebula_spawn(x, y)
    return nebula_spawn(x, y, Id_blue_nebula_sprite_base, Id_blue_nebula_frames, planet_filter)
end

function purple_nebula_spawn(x, y)
    return nebula_spawn(x, y, Id_purple_nebula_sprite_base, Id_purple_nebula_frames, body_filter)
end

function ship_spawn(x, y)
    -- Set up base entity
    local transform = {x = x, y = y}

    local ship_entity =  {transform=transform, collisions={}}
    
    add(Entities, ship_entity)

    attach_component(ship_entity, "circle_collider", {radius=2}, Circle_colliders)
    attach_component(ship_entity, "sprite_component", {id=Id_ship_sprite, width=8, height=8}, Sprite_components)
    ship_entity.tag = "ship"
    ship_entity.collided = goal_collision
    Player_entity = ship_entity
    return ship_entity
end

Entity_spawn_handlers = {
    [Id_default_planet_sprite] = default_planet_spawn,
    [Id_goal_planet_sprite] = goal_planet_spawn,
    [Id_ship_sprite] = ship_spawn,
    [Id_black_hole_sprite] = black_hole_spawn,
    [Id_repulse_planet_sprite] = repulse_planet_spawn,
    [Id_red_nebula_sprite_base] = red_nebula_spawn,
    [Id_blue_nebula_sprite_base] = blue_nebula_spawn,
    [Id_purple_nebula_sprite_base] = purple_nebula_spawn
}

local function map_spawn_handler(spawner)
    return function(map_x, map_y)
        return spawner((map_x-Gameplay_loc[1])*8+4, (map_y-Gameplay_loc[2])*8+4)
    end
end

Gameplay_spawn_handlers = {}
for sprite, spawner in pairs(Entity_spawn_handlers) do
    Gameplay_spawn_handlers[sprite] = map_spawn_handler(spawner)
end


-- Systems

local function shapes_overlap(a, b)
    local a_transform, b_transform = a.entity.transform, b.entity.transform
    local ax, ay = a_transform.x, a_transform.y
    local bx, by = b_transform.x, b_transform.y

    if a.kind == "square" and b.kind == "square" then
        local aw, ah = a.shape.width / 2, a.shape.height / 2
        local bw, bh = b.shape.width / 2, b.shape.height / 2
        return ax - aw <= bx + bw
            and ax + aw >= bx - bw
            and ay - ah <= by + bh
            and ay + ah >= by - bh
    end

    if a.kind == "circle" and b.kind == "circle" then
        local dx, dy = ax - bx, ay - by
        local radius = a.shape.radius + b.shape.radius
        -- Bound the differences before squaring on PICO-8's fixed-point numbers.
        if abs(dx) > radius or abs(dy) > radius then return false end
        return dx * dx + dy * dy <= radius * radius
    end

    -- Find the closest point on the square to the circle's center.
    if a.kind == "circle" then
        a, b = b, a
        a_transform, b_transform = b_transform, a_transform
    end
    local half_width = a.shape.width / 2
    local half_height = a.shape.height / 2
    local x = max(a_transform.x - half_width, min(b_transform.x, a_transform.x + half_width))
    local y = max(a_transform.y - half_height, min(b_transform.y, a_transform.y + half_height))
    local dx, dy = b_transform.x - x, b_transform.y - y
    if abs(dx) > b.shape.radius or abs(dy) > b.shape.radius then return false end
    return dx * dx + dy * dy <= b.shape.radius * b.shape.radius
end

local function add_collision(entity, other)
    local contacts = entity.collisions
    -- An entity may have both shape components; report each reference once.
    for _, contact in ipairs(contacts) do
        if contact == other then
            return
        end
    end
    contacts[#contacts + 1] = other
end

local function check_collisions()
    -- Clear all contacts once per check, before collecting either shape type.
    local active_entities = {}
    for _, entity in pairs(Entities) do
        if not active_entities[entity] then
            active_entities[entity] = true
            entity.collisions = entity.collisions or {}
            for i = #entity.collisions, 1, -1 do
                entity.collisions[i] = nil
            end
        end
    end

    local shapes = {}
    for _, shape in pairs(Square_colliders) do
        local entity = shape.entity
        if entity and active_entities[entity] and entity.transform then
            shapes[#shapes + 1] = {
                entity=entity, shape=shape, kind="square"
            }
        end
    end
    for _, shape in pairs(Circle_colliders) do
        local entity = shape.entity
        if entity and active_entities[entity] and entity.transform then
            shapes[#shapes + 1] = {
                entity=entity, shape=shape, kind="circle"
            }
        end
    end

    for i = 1, #shapes - 1 do
        for j = i + 1, #shapes do
            local a, b = shapes[i], shapes[j]
            local a_filters_out = a.shape.filter ~= nil and not a.shape.filter(b.entity.tag)
            local b_filters_out = b.shape.filter ~= nil and not b.shape.filter(a.entity.tag)
            if not a_filters_out and not b_filters_out and a.entity ~= b.entity and shapes_overlap(a, b) then
                add_collision(a.entity, b.entity)
                add_collision(b.entity, a.entity)
            end
        end
    end
end

-- Contacts belong to entities, including stationary hazards without physics.
local function run_collision_callbacks()
    local processed = {}
    for _, entity in ipairs(Entities) do
        processed[entity] = true
        if not entity.gravity_component then
            for _, other in ipairs(entity.collisions) do
                if not processed[other] and not other.gravity_component
                    and not entity.destroy_pending and not other.destroy_pending
                    and entity.transform ~= other.transform then
                    if entity.collided then entity:collided(other) end
                    if Transition_state ~= "idle" then return end
                    if other.collided then other:collided(entity) end
                    if Transition_state ~= "idle" then return end
                end
            end
        end
    end
end

-- Physics applies gravity and velocity only; callbacks are dispatched above.
local function run_physics() 
    for _, physics_component in ipairs(Physics_components) do
        local under_pull = false
        local this_entity = physics_component.entity
        for _, collided_entity in ipairs(this_entity.collisions) do
            if not this_entity.destroy_pending and not collided_entity.destroy_pending
                and collided_entity.transform ~= this_entity.transform then
                -- Follow the gravity component attached to the other entity.
                if collided_entity.gravity_component ~= nil then
                    local diff_x = collided_entity.transform.x - this_entity.transform.x
                    local diff_y = collided_entity.transform.y - this_entity.transform.y

                    -- normalization of diff
                    local magnitude = sqrt(diff_x * diff_x + diff_y * diff_y)
                    if magnitude > 0 then
                        under_pull = true
                        diff_x = diff_x / magnitude
                        diff_y = diff_y / magnitude

                        local accel_x = diff_x * collided_entity.gravity_component.force
                        local accel_y = diff_y * collided_entity.gravity_component.force

                        physics_component.vel_x = physics_component.vel_x + accel_x
                        physics_component.vel_y = physics_component.vel_y + accel_y
                    end
                end
            end
        end

        if not this_entity.destroy_pending then
            local vel_mag = sqrt(physics_component.vel_x * physics_component.vel_x + physics_component.vel_y * physics_component.vel_y)
            if vel_mag > 0 then
                physics_component.vel_x = physics_component.vel_x / vel_mag
                physics_component.vel_y = physics_component.vel_y / vel_mag
            end

            local new_vel = mid(-5, vel_mag, 5)
            if physics_component.drag ~= nil and not under_pull then
                new_vel = new_vel * physics_component.drag
            end
            physics_component.vel_x = physics_component.vel_x * new_vel
            physics_component.vel_y = physics_component.vel_y * new_vel

            this_entity.transform.x = this_entity.transform.x + physics_component.vel_x
            this_entity.transform.y = this_entity.transform.y + physics_component.vel_y
            local pos = this_entity.transform
            if pos.x < -8 or pos.x > 136 or pos.y < -8 or pos.y > 136 then
                regular_collision(this_entity)
            end
        end
    end
end

local function destroy_pending_entities()
    -- Collision callbacks queue removal so physics never iterates a shrinking list.
    local pending = {}
    for _, entity in pairs(Entities) do
        if entity.destroy_pending then
            add(pending, entity)
        end
    end
    for _, entity in ipairs(pending) do
        destroy_entity(entity)
    end
end

function gameplay_init()
    gameplay_teardown()
    Current_level = mid(1, Current_level, #Levels)
    Active_level = Levels[Current_level]
    Gameplay_loc = {Active_level.map_loc[1], Active_level.map_loc[2]}
    Level_failed = false
    scan_map(Gameplay_spawn_handlers, Gameplay_loc[1], Gameplay_loc[2], 16, 16)
end

function gameplay_teardown()
    Player_entity = nil
    Active_level = nil
    Entities = {}
    Square_colliders = {}
    Circle_colliders = {}
    Physics_components = {}
    Gravity_components = {}
    Sprite_components = {}
    Countdown_components = {}
    Animation_components = {}
end

function game_systems_update()
    if Transition_state ~= nil and Transition_state ~= "idle" then
        return
    end
    update_countdowns()
    if Transition_state ~= nil and Transition_state ~= "idle" then
        return
    end
    check_collisions()
    run_collision_callbacks()
    if Transition_state == "idle" then run_physics() end
    destroy_pending_entities()
end

-- frame_stride skips across multi-tile frames; single-tile frames default to 1.
local function animation_sprite_id(animation, now, paused)
    local frames = max(1, flr(animation.frames))
    animation.current_frame = animation.current_frame or 1
    animation.transition_time = animation.transition_time or 0

    local elapsed = 0
    if animation.last_draw_time ~= nil and not paused and not animation.paused then
        elapsed = max(0, now - animation.last_draw_time)
    end
    animation.last_draw_time = now
    animation.paused = paused

    -- A nonpositive delay holds the current frame.
    if not paused and animation.transition_delay > 0 then
        animation.transition_time = animation.transition_time + elapsed
        local steps = flr(animation.transition_time / animation.transition_delay)
        animation.transition_time = animation.transition_time % animation.transition_delay

        if animation.looped then
            animation.current_frame = ((animation.current_frame - 1 + steps) % frames) + 1
        else
            animation.current_frame = min(animation.current_frame + steps, frames)
            if animation.current_frame == frames then
                animation.transition_time = 0
            end
        end
    end

    return animation.base_id + (animation.current_frame - 1) * (animation.frame_stride or 1)
end

local function draw_gameplay_sprite(sprite_component, now, paused)
    local transform = sprite_component.entity.transform
    local sprite_x = flr(transform.x - (sprite_component.width / 2))
    local sprite_y = flr(transform.y - (sprite_component.height / 2))
    local sprite_id = sprite_component.id
    local source_width = sprite_component.source_width or 8
    local source_height = sprite_component.source_height or 8
    local animation = sprite_component.entity.animation_component
    if animation then
        sprite_id = animation_sprite_id(animation, now, paused)
    end
    if source_width == 8 and source_height == 8
        and sprite_component.width == 8 and sprite_component.height == 8 then
        spr(sprite_id, sprite_x, sprite_y)
    else
        sspr((sprite_id%16)*8, flr(sprite_id/16)*8, source_width, source_height,
            sprite_x, sprite_y, sprite_component.width, sprite_component.height)
    end
end

function gameplay_draw()
    map(Background_loc[1], Background_loc[2], 0, 0, 16, 16)
    local now = time()
    local paused = Transition_state ~= nil and Transition_state ~= "idle"
    -- Draw every gravity field behind every solid sprite, including fields
    -- created by moons thrown after the goal was spawned.
    for _, sprite_component in ipairs(Sprite_components) do
        if sprite_component.entity.gravity_component then
            draw_gameplay_sprite(sprite_component, now, paused)
        end
    end
    for _, sprite_component in ipairs(Sprite_components) do
        if not sprite_component.entity.gravity_component then
            draw_gameplay_sprite(sprite_component, now, paused)
        end
    end
end
-- Each level owns a 16x16 region on the lower half of the map.
-- Inventory values are sprite IDs resolved by Entity_spawn_handlers.
Levels = {
    {name="first flight", map_loc={0,16}, inventory={}, angle=0},
    {name="red nebulae", map_loc={16,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="red stops ships, not moons"},
    {name="ring around the rosie", map_loc={32,16}, inventory={Id_default_planet_sprite}, angle=0, hint="blue stops moons, not ships."},
    {name="clearing the path", map_loc={48,16}, inventory={Id_default_planet_sprite}, angle=0.055, hint="moons can pull in other moons"},
    {name="clearing the trail", map_loc={64,16}, inventory={Id_default_planet_sprite, Id_default_planet_sprite}, angle=0},
    {name="expulsion", map_loc={80,16}, inventory={}, angle=0, hint="orange planets push back other planets"},
    {name="pool table", map_loc={96,16}, inventory={Id_repulse_planet_sprite}, angle=0.055, hint="moons can be pushed away"},
    {name="final orbit", map_loc={112,16}, inventory={Id_repulse_planet_sprite}, angle=0}
}
Campaign_complete = false
Completed_levels = {}
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
Throw_angle_speed = 0.005
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

-- Gravity-only preview: time and marker spacing are measured in updates.
Guide_Sprite_Base = 1
Guide_Sprite_Step = 10
Guide_Time = 120

local function guide_finished(x, y, radius)
    if x < 0 or x >= 128 or y < 0 or y >= 128 then return true end
    for _, collider in ipairs(Circle_colliders) do
        local entity = collider.entity
        if entity.tag == "goal" and entity.transform and not entity.destroy_pending then
            local dx, dy = x-entity.transform.x, y-entity.transform.y
            local range = radius+collider.radius
            if abs(dx) <= range and abs(dy) <= range
                and dx*dx+dy*dy <= range*range then
                return true
            end
        end
    end
    return false
end

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
    print("level "..Current_level.."  "..Active_level.name, 4, 4, 5)
    print("arrows: aim/power", 4, 13, 5)
    print("z: restart  hold z: menu", 4, 122, 5)
    if Active_level.hint then print(Active_level.hint, 4, 22, 6) end

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

    if not Thrown_self and not Level_failed and Player_entity and Player_entity.transform then
        local dx, dy = cos(Current_throw_angle), sin(Current_throw_angle)
        local throwing_ship = #Throw_inventory_ids == 0
        local launch_offset = throwing_ship and 0 or 10
        local iter_x = Player_entity.transform.x + dx*launch_offset
        local iter_y = Player_entity.transform.y + dy*launch_offset
        local iter_vel_x, iter_vel_y = dx*Current_throw_strength, dy*Current_throw_strength
        local radius = throwing_ship and Player_entity.circle_collider.radius or 2
        local tag = throwing_ship and "ship" or "planet"
        local drag = nil
        local next_id = Throw_inventory_ids[1]
        if next_id == Id_default_planet_sprite or next_id == Id_goal_planet_sprite then
            drag = Planet_drag
        elseif throwing_ship and Player_entity.physics_component then
            drag = Player_entity.physics_component.drag
        end
        local sprite_step = max(1, flr(Guide_Sprite_Step))
        for i = 1,max(0, flr(Guide_Time)) do
            if guide_finished(iter_x, iter_y, radius) then break end
            -- Read current field positions; never spawn or move live entities.
            local under_pull = false
            for _, gravity in ipairs(Gravity_components) do
                local field = gravity.entity
                local shape = field.circle_collider
                if shape and field.transform and not field.destroy_pending
                    and not (throwing_ship and field.transform == Player_entity.transform)
                    and (not shape.filter or shape.filter(tag)) then
                    local diff_x = field.transform.x - iter_x
                    local diff_y = field.transform.y - iter_y
                    local range = shape.radius + radius
                    -- Bound distances before squaring for PICO-8 fixed-point math.
                    if abs(diff_x) <= range and abs(diff_y) <= range then
                        local distance = sqrt(diff_x*diff_x + diff_y*diff_y)
                        if distance > 0 and distance <= range then
                            under_pull = true
                            iter_vel_x = iter_vel_x + diff_x/distance*gravity.force
                            iter_vel_y = iter_vel_y + diff_y/distance*gravity.force
                        end
                    end
                end
            end

            -- Match the live speed cap and drag; keep positions fractional.
            local speed = sqrt(iter_vel_x*iter_vel_x + iter_vel_y*iter_vel_y)
            if speed > 0 then
                local new_speed = min(5, speed)
                if drag and not under_pull then new_speed = new_speed*drag end
                iter_vel_x = iter_vel_x/speed*new_speed
                iter_vel_y = iter_vel_y/speed*new_speed
            end
            iter_x = iter_x + iter_vel_x
            iter_y = iter_y + iter_vel_y
            if guide_finished(iter_x, iter_y, radius) then break end

            if i % sprite_step == 0 then
                spr(Guide_Sprite_Base, flr(iter_x-4), flr(iter_y-4))
            end
        end
    end
end
-- Handles main menu input 

-- Static Options 
-- Map tile origin: reserve a 16x16 region beside the title screen.
Main_menu_background_loc = {16, 0}

Main_menu_sprite_background_id = 48
Main_menu_sprite_id_hover = 49

Main_menu_sprite_base_id = 63
Main_menu_lock_id = 96
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

    if btnp(5) and get_current_level() <= Latest_level + 1 then
        transition("Gameplay", get_current_level())
    end
end

function main_menu_draw()
    map(Main_menu_background_loc[1], Main_menu_background_loc[2], 0, 0, 16, 16)
    print("choose your level", 30, 24, 7)
    if Campaign_complete then print("all 8 levels complete!", 22, 36, 11) end
    for x = 1,Menu_bounds[1] do
        for y = 1,Menu_bounds[2] do
            local level = ((y - 1) * Menu_bounds[1]) + x
            local tile_x, tile_y = Main_menu_sprite_locs[y][x][1], Main_menu_sprite_locs[y][x][2]
            local frame = level == get_current_level() and Main_menu_sprite_id_hover or Main_menu_sprite_background_id
            spr(frame, tile_x, tile_y)
            local inner_sprite
            if Latest_level + 1 < level then
                inner_sprite = Main_menu_lock_id
            else
                inner_sprite = Main_menu_sprite_base_id + level
            end
            spr(inner_sprite, tile_x + Main_menu_base_sprite_offset[1], tile_y + Main_menu_base_sprite_offset[2])
            if Completed_levels[level] then pset(tile_x+3, tile_y+10, 11) end
        end
    end
    print("arrows: select", 36, 99, 6)
    print("x: play   z: title", 28, 109, 7)
end
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

function init_scene()
 if Scene == "Title" then
  title_screen_init()
 elseif Scene == "MainMenu" or Scene == "Main Menu" then
  main_menu_init()
 elseif Scene == "Gameplay" then
  gameplay_init()
  player_systems_init()
 end
end

function teardown_scene()
 if Scene == "Title" then
  title_screen_teardown()
 elseif Scene == "MainMenu" or Scene == "Main Menu" then
  main_menu_teardown()
 elseif Scene == "Gameplay" then
  gameplay_teardown()
 end
end

function update_scene()
 if Scene == "Title" then
  title_screen_update()
 elseif Scene == "MainMenu" or Scene == "Main Menu" then
  main_menu_update()
 elseif Scene == "Gameplay" then
  player_systems_update()
  game_systems_update()

 end
end

function draw_scene()
 if Scene == "Title" then
  title_screen_draw()
 elseif Scene == "MainMenu" or Scene == "Main Menu" then
  main_menu_draw()
 elseif Scene == "Gameplay" then
  gameplay_draw()
  player_systems_draw()
 end
end

function _init()
 init_scene()
end

function _update()
 if Transition_state == "idle" then
  update_scene()
 else
  transition_update()
 end
end

function _draw()
 if Transition_state == "covering" then
  -- Preserve the last scene frame while the wipe enters.
  transition_draw()
 elseif Transition_state == "revealing" then
  -- Reveal the initialized, frozen scene behind the wipe.
  draw_scene()
  transition_draw()
 else
  cls(1)
  draw_scene()
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000077770000000000000000000000000077000777000000000000000000000000000000000000
00000000000000000000000000000000000000000000000007700000000007700000000000000000077700000000770000000000000000000000000000000000
00700700000000000000000000000000000000000000000770000000000000077000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000
00077000000a00000000000000000000000000000000000000000000000000000000000000000700000000000000000000700000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000007000000000000000000000000700000070000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000070000000000000000000000000070000000000000000000000000000000000000000000000000000000000
0000000000cc33000000000000011000000120000070000000000000000000000000070000000000000000000000000000000700000000000000000000000000
0000000007cc33c00000000000100100002001000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000
00a00000773377330005600001000010010000200000000000000000000000000000000007000000000000000000000000000070000000000000000000000000
00a7c000377377730055560010000001200000010000000000000000000000000000000007000000000000000000000000000070000000000000000000000000
0097770033cccc770066650010000001100000027000000000000000000000000000000770000000000000000000000000000007000000000000000000000000
00900000cccc3ccc0006600001000010020000107000000000000000000000000000000770000000000000000000000000000000000000000000000000000000
0000000003373cc00000000000100100001002007000000000000000000000000000000700000000000000000000000000000000000000000000000000000000
0000000000377c000000000000011000000210007000000000000000000000000000000700000000000000000000000000000000000000000000000000000000
00000000000a00000900009000000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000
00090000080908000008000008000000000000000000000000000000000000000000000070000000000000000000000000000007000000000000000000000000
009a900000a7a0009080080900000000000000000000000000000000000000000000000070000000000000000000000000000007000000000000000000000000
09a7a900a97779a00000000000000080000000007000000000000000000000000000000770000000000000000000000000000007000000000000000000000000
009a900000a7a0000800080000800000000000000700000000000000000000000000007007000000000000000000000000000070000000000000000000000000
00090000080908000008000900000000000000000700000000000000000000000000007007000000000000000000000000000070000000000000000000000000
00000000000a00000900000000000800000000000700000000000000000000000000007000000000000000000000000000000000000000000000000000000000
00000000000000000000900000000000000000000070000000000000000000000000070000000000000000000000000000000000000000000000000000000000
066666600aaaaaa011111111dddddddd111111110000000000000000000000000000070000000000000000000000000000000000000000000000000000000000
60000006a000000a11111111ddd1dddd111111110000000000000000000000000000700000070000000000000000000000007000000000000000000000000000
60000006a000000a11111111dd111ddd111111110000000000000000000000000000000000007000000000000000000000070000000000000000000000000000
60000006a000000a11111111ddd1dddd111611110000070000000000000000000000000000000700000000000000000000700000000000000000000000000000
60000006a000000a11111111dddddddd111111110000007000000000000000000000000000000000000000000000000007000000000000000000000000000000
60000006a000000a11111111dddddddd111111110000000770000000000000077000000000000000000000000000000000000000000000000000000000000000
60000006a000000a11111111dddddddd111111110000000007000000000000700000000000000000077700000000770000000000000000000000000000000000
066666600aaaaaa011111111dddddddd111111110000000000000777777000000000000000000000000077700077000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000099990000000000000000000000000099000999000000000000
00070000007700000077000000707000007770000007700000777000007770000000000009900000000009900000000000000000099900000000990000000000
00770000000070000000700000707000007000000070000000007000007070000000000990000000000000099000000000000000000000000000000000000000
00070000000700000007000000777000007700000077700000070000007770000000000000000000000000000000000000000000000000000000000009000000
00070000007000000000700000007000000070000070700000070000007070000000000000000000000000000000000000000900000000000000000000900000
00777000007770000077000000007000007700000077700000070000007770000000000000000000000000000000000000009000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000900000090000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000090000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000090000000000000000000000000000000900
00022000000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090
002ee200009aa9000000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000090
02e00e2009a99a900000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000090
02e00e2009aaaa900000000000000000000000000000000000000000000000009000000000000000000000000000000990000000000000000000000000000009
002ee200009aa9000000000000000000000000000000000000000000000000009000000000000000000000000000000990000000000000000000000000000000
00022000000990000000000000000000000000000000000000000000000000009000000000000000000000000000000900000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000900000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009
00777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000009
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000009
07777770000000000000000000000000000000000000000000000000000000009000000000000000000000000000000990000000000000000000000000000009
07700770000000000000000000000000000000000000000000000000000000000900000000000000000000000000009009000000000000000000000000000090
07707770000000000000000000000000000000000000000000000000000000000900000000000000000000000000009009000000000000000000000000000090
07777770000000000000000000000000000000000000000000000000000000000900000000000000000000000000009000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000090000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900000090000000000000000000000009000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000090000
00000000000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000900000000000000000000900000
00000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000009000000
00000000000000000000000000000000000000000000000000000000000000000000000990000000000000099000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000009000000000000900000000000000000099900000000990000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000999999000000000000000000000000099900099000000000000
02000800020028200080028000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00008280080882880282000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
80800802828028208828800000000000000000000000000000000000000000000000000000009999999900000000000000000000000000000000000000000000
02820000080008000282002000000080000000000000000000000000000000000000099999999999999900000000000000000000000000000000000000000000
88288020000280000080008000000888000000000000000000000000000000000000999999999999990000000000000000000000000000000000000000000000
02820000800000800802028200000080000000000000000000000000000000000009999999999999900000000000000000000000000000000000000000000000
00800080008008288280882800000000000000000000000000000000000000000099999999999990000000000000000000000000000000000000000000000000
20002000000020800800028200000000000000000000000000000008000000000999999999999900000000000000000000000000000000000000000000000000
0e000c000e00ece000c00ec000000000000000000000000000000088800000009999999999999900000000000000000000000000000000000000000000000000
0000cec00c0cc7cc0ece000e00000000000000000000000000000008000000009999999999999900000000000000000000000000000000000000000000000000
c0c00c0ecec0ece0cc7cc00000000000000000000000000000000000000000099999999999999000000000000000000000000000000000000000000000000000
0ece00000c000c000ece00e000000000000000000007777777777777777777777777777777777777770000000000000000000000000000000000000000000000
cc7cc0e0000ec00000c000c000000000000000000077777777777777777777777777777777777777777800000000000000000000000000000000000000000000
0ece0000c00000c00c0e0ece00000000000000007777777777777777777777777777777777777777777000000000000000000000000000000000000000000000
00c000c000c00ceccec0cc7c0000000000000007777777777777aaaa77777aaa77777777777aaa77777000000000000000000000000000000000000000000000
e000e0000000e0c00c000ece0000000000000aaa77aaa77777aaaaaa777aaaaaa777aa7777aaaa77777000000000000000000000000000000000000000000000
0e0002000e00e2e000200e200000000000007aaa7aaaa7777aaaaaaa77aaaaaaa77aaaa7aaaaa777777000000000000000000000000000000000000000000000
00002e20020227220e2e000e000000000077aaaa7aaaa777aaaa77aa7aaa77aaa7aaaaa9aaaa7777777700000000000000000000000000000000000000000000
2020020e2e20e2e02272200000000000777aaaa7aaaa7777aaa777aaaaa777aa99aaaaaaaa777777777700000000000000000000000000000000000000000000
0e2e0000020002000e2e00e00000000000aaaaaaaaaa7777aa777aaaaaa777aa7aaa9aaaa9977777777700000000000000000000000000000000000000000000
227220e0000e200000200020000000000aaaaaaaaaaa7777aa777aa7aa777aaa7aa79aaa99997777777700000000000000000000000000000000000000000000
0e2e000020000020020e0e2e000000000aaaaaaa7aa77777aa77aaa7aa77aaa7aaa77aaa99999999777000000000000000000000000000000000000000000000
00200020002002e22e20227200000000aaa0aaa7aaa77777aa7aaa77aaaaaaa7aaa7aaa999999999770000000000000000000000000000000000000000000000
e000e0000000e02002000e2e0000000aaa00aa00aaa77777aaaaaa77aaaaa777aa77aaa777777777770000000000000000000000000000000000000000000000
000000000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa77777700000000000000000000000000000000000000000000000
000000000000000000000000800000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa77777700000000000000000000000000000000000000000000000
000000000000000000000000880000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa99900000000000000000000000000000000000000000000000000
000000000000000000000000800000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa99900000000000000000000000000000000000000000000000000
000000000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa99900000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000888000000000055555666566666699999999999900000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000080000000000055555666566666669999999999990000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000055555666666666559999999999990000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000555555666666665666999999999999000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000aaaa000000aaa655666aa66656aa999999999999990000000000000000000000000000000000000000000000
000000000000000000000000000000000000000aaaaa000000aaa55566aaa666aaaaaa9999aaaaaaa99900000000000000000000000000000000000000000000
000000000000000000000000633300000000000aaa0000000aaa65555aaaa66aaaaaaa666aaaaaaaa99990000000000000000000000000000000000000000000
000000000000000000000000633331110000000aa00000000aa565565aaa66aaaa66aa666aaaaa60000000000000000000000000000000000000000000000000
000000000000000000000000333331111110000aa0000000aaa55665aaa66aaaa666aa6566aaa660000000000000000000000000000000000000000000000000
000000000000000000000000333311111111100aaa000000aaaaaaaaaaa6aaaa666aaa6566aaa660000000000000000000000000000000000000000000000000
000000000000000000000000333111111111111aaaa00000aaaaaaaaaa56aaa6666aaa665aaa6600000000000000000000000000000000000000000000000000
0000000000000000000000001111111111111111aaa0000aaaaa55aaa55aaa6666aaa666aaa66600000080000000000000000000000000000000000000000000
0000000000000000000000001111111111111111aaa000aaa0055aaa555aaa6666aaa666aaa66600000888000000000000000000000000000000000000000000
0000000000000000000000001111111111777771aaa110aaa000aaaa555aa6666aaa666aaa666000000080000000000000000000000000000000000000000000
000000000000000000000000111111111667777aaa111aaa0000aaa5655aa555aaaa666aa6650000000000000000000000000000000000000000000000000000
0000000000000000000000001111111166777aaaaa111aaa3000aa55655aa55aaaa666aaa5550000000000000000000000000000000000000000000000000000
00000000000000000000000011111116667aaaaaa711aaa3330aaa55565aaaaaaa555aaa55500000000000000000000000000000000000000000000000000000
000000000000000000000000111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000
000000000000000000000000111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000
000000000000000000000000111133aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000
000000000000000000000000313333aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000
000000000000000000000000333333aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000000000000000000000000000000000
00000000000000000000000033333366677777711111111333333333300000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333666777777111111111133333333377700000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333666777771111111111111333336677770000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333666777771111111111111333336677777000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333366777771111111111111133366677777000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333336677771111111111111133366777777000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033333336677771111111111111133366777777700000000000000080000000000000000000000000000000000000000000000000
00000000000000000000000033333333667771111111111111133366777777700000000000000888000000000000000000000000000000000000000000000000
00000000000000000000000033333331667771111111111111133366777777700000000000000080000000000000000000000000000000000000000000000000
00000000000000000000000033333311111111111111111111333366777777700000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000033311111111111111111111111333366777777700000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000011111111111111111111111113333366677777770000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000011111111111111111111111133333666677777777000000000000000000000000000000000000000000000000000000000000000
__map__
3432323232323232323232323232323232323232323232323232323232323432323232323232323232343232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323432323232323232323232343232323232323232323234323232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232343232323232323232323234323232323232323232323232323232323232323232323232323232323234320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323232323232323232323232323232323234323232323232323232323432323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323234323232323232323232323432323232323232323232343232323232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323432323232323232323232323232323232323232323232323232323232323232323232323232323232343232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323232323432323232323232323232343232323232323232323234323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232343232323232323232323234323232323232323232323232323232323232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3234323232323232323232323232323232323232323232323232323232323234323232323232323232323432323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323234323232323232323232323432323232323232323232343232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323432323232323232323232343232323232323232323232323232323232323232323232323232323232340000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323232323232323232323232323232323232343232323232323232323234323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232343232323232323232323234323232323232323232323432323232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323234323232323232323232323232323232323232323232323232323232323232323232323232323232323432320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323232323232323232323232323232323232323432323232323232323232343232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3232323232323232323432323232323232323232343232323232323232323232323232323232323232323232323232320000000000000000000000000000000033333333333333333333333333333333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000050a000a00050000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090000000000000a000a00000000000000000000000000000000000000000000000000000000000000000000000000000a000a00000000000a000
000000000000000000000000000000000000000000000080008000000000000000000090000000000000000000000000000000000000000000000000000000000000000000900090000000120000a000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000
0000000000000000000000000000000000000000000080008000000000110000000090009000000000000000000000000000000000000000000000000000000000000000000090009000000000a000a00000000000000000000000000000000000000000000000000000000000110000000000000000800000000000a000a000
000000000000000000000000000000000000000000000080008000000000000000000090000000a0000000000000000000000000000000001200000000000000000000001000009000000000000000110000005100000000000000000000510000000000000000000000000000000000000000000000008000000000a0a00000
0000000000000000000000000000000000000000000080008000000000000000000010000000a000a000000000000000000000000000000000000000000000000000000000000000900000000000a000000000000000000000000000000000000000009000800080008000800000000000001000000080000000000000000000
000010000000001200000000001100000000000000000000000000000000000000000000000000a000000011000000000000000000000000000000000000000000000000000000000000000000a000a0000000000000000000000000000000000000900090008012800080008000800000000000000000800000000000000000
000000000000000000000000000000000000100000000000000000000000000000000000000000800000000000000000000010000000000000001200001100000000000000000000000000000000a000000000000000000000000000000000000000009000800080008000800080000000000000000050800000000000000011
0000000000000000000000000000000000000000000000000000000000000000000000000000800080500000000000000000000000000000000000000000000000000000120000000050000000a000a0000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000a000000000100000000051000000001100000000001000000000000050000000000000000000000000800000000000110000
0000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000011
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000
