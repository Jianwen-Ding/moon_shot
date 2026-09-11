-- Reserved 16x16 map regions, in tile coordinates (x, y).
Background_loc = {32, 0}
Gameplay_loc = {48, 0}

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
        if expired.expire ~= nil then
            expired.expire()
        end
        destroy_entity(entity)
    end
end

-- Spawning logic

-- x/y are center coordinates in pixels; frames use consecutive sprite IDs.
-- Defaults: four frames, 0.125 seconds per frame, then destroy after 0.5 seconds.
function spawn_timed_animation(x, y, base_id, frames, transition_delay, duration)
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
    return spawn_timed_animation(entity.transform.x, entity.transform.y, 0, 4, 0.05, 0.25)
end

function default_planet_spawn(map_x, map_y, sprite) 
    entity = base_planet_spawn(map_x, map_y, sprite, 0, 8, 16, 9.8)
    entity.collision = regular_collision
    return entity
end 

function goal_planet_spawn(map_x, map_y, sprite)
    entity = base_planet_spawn(map_x, map_y, sprite, 0, 8, 16, 9.8)
    entity.tag = "goal"
    return entity
end

local function base_planet_spawn(map_x, map_y, sprite, gravity_sprite, size, range, force)
    local transform = {x=map_x + (size / 2), y=map_y + (size / 2)}

    -- Set up gravity entity 
    local gravity_entity = {transform=transform, collisions={}}

    attach_component(gravity_entity, "circle_collider", {radius=range}, Circle_colliders)
    attach_component(gravity_entity, "gravity_component", {force=force}, Gravity_components)

    -- TODO: choose the gravity animation's base sprite ID.
    attach_component(gravity_entity, "animation_component",
        {base_id=0, frames=2, transition_delay=0.5, transition_time=0, looped=true}, Animation_components)
    attach_component(gravity_entity, "sprite_component",
        {id=gravity_sprite, width=8, height=8}, Sprite_components)

    add(Entities, gravity_entity)

    local base_entity = {transform=transform, collisions={}}

    attach_component(base_entity, "circle_collider", {radius=size}, Circle_colliders)
    attach_component(base_entity, "sprite_component", {id=0, width=8, height=8}, Sprite_components)
    attach_component(base_entity, "physics_component", {vel_x=0, vel_y=0}, Sprite_components)

    add(Entities, base_entity)

    return base_entity
end

local function goal_collision(entity, other)
    if other.tag == "goal" then 
        transition("GamePlay", Current_level + 1)
    end
    regular_collision(other)
end

function ship_spawn(map_x, map_y, sprite)
    entity = base_planet_spawn(map_x, map_y, sprite, 0, 8, 16, 9.8)
    entity.collision = goal_collision
    return entity
end

-- Keys are combined sprite flag values, as read by scan_map.
Gameplay_spawn_handlers = {
    [1] = default_planet_spawn,
    [2] = goal_planet_spawn,
    [3]
}


-- Systesms

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
            if a.entity ~= b.entity and shapes_overlap(a, b) then
                add_collision(a.entity, b.entity)
                add_collision(b.entity, a.entity)
            end
        end
    end
end

--- Determines objects are effected by velocity and gravity 
local function run_physics() 
    for _, physics_component in ipairs(Physics_components) do
        local this_entity = physics_component.entity
        -- entity 
        for _, collided_entity in ipairs(this_entity.collisions) do
            if collided_entity.transform ~= this_entity.transform then
                -- Follow the gravity component attached to the other entity.
                if collided_entity.gravity_component ~= nil then
                    local diff_x = collided_entity.transform.x - this_entity.transform.x
                    local diff_y = collided_entity.transform.y - this_entity.transform.y
                    
                    -- normalization of diff
                    local magnitude = sqrt(diff_x * diff_x + diff_y * diff_y)
                    if magnitude > 0 then
                        diff_x = diff_x / magnitude
                        diff_y = diff_y / magnitude

                        local accel_x = diff_x * collided_entity.gravity_component.force
                        local accel_y = diff_y * collided_entity.gravity_component.force

                        physics_component.vel_x = physics_component.vel_x + accel_x
                        physics_component.vel_y = physics_component.vel_y + accel_y
                    end
                else
                    if this_entity.collided then
                        this_entity:collided(collided_entity)
                    end 

                    if collided_entity.collided then
                        collided_entity:collided(this_entity)
                    end 
                end
            end
            -- handles 
        end

        this_entity.transform.x = this_entity.transform.x + physics_component.vel_x
        this_entity.transform.y = this_entity.transform.y + physics_component.vel_y
    end
end

function gameplay_init()
    scan_map(Gameplay_spawn_handlers, Gameplay_loc[1], Gameplay_loc[2], 16, 16)
end

function gameplay_teardown()
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
    check_collisions()
    run_physics()
end

-- Frames use consecutive sprite IDs, starting at base_id.
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

    return animation.base_id + animation.current_frame - 1
end

function gameplay_draw()
    local now = time()
    local paused = Transition_state ~= nil and Transition_state ~= "idle"
    for _, sprite_component in pairs(Sprite_components) do
        local transform = sprite_component.entity.transform
        local sprite_x = flr(transform.x - (sprite_component.width / 2))
        local sprite_y = flr(transform.y - (sprite_component.height / 2))
        local sprite_id = sprite_component.id
        local animation = sprite_component.entity.animation_component
        if animation then
            sprite_id = animation_sprite_id(animation, now, paused)
        end
        spr(sprite_id, sprite_x, sprite_y)
    end
end
