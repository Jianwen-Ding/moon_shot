-- Reserved 16x16 map regions, in tile coordinates (x, y).
background_loc = {32, 0}
gameplay_loc = {48, 0}

-- Holds entities and their attached components, including position transforms.
entities = {} 

-- holds all specific logic of the entity
-- Component lists are independent of the entity list.
-- component.entity points to its owner; entity.square_collider,
-- entity.circle_collider, etc. point back to the attached components.
-- Transforms give shape centers; rectangle width and height are full sizes.
-- Keep fractional transform coordinates for physics and collisions.
-- Convert to whole pixels only when drawing; never round the transform itself.
-- entity.collisions contains references to touching entities.
square_colliders = {}
circle_colliders = {}
physics_components = {}
gravity_components = {}
sprite_components = {}
countdown_components = {}
animation_components = {}

-- Register both directions without relying on matching list indices.
function attach_component(entity, name, component, components)
    component.entity = entity
    entity[name] = component
    add(components, component)
    return component
end

-- Spawning logic


local function default_planet_spawn(map_x, map_y, sprite) 

end 

local function base_planet_spawn(map_x, map_y, sprite, gravity_sprite, size, range, force)
    local transform = {}
    transform.x = map_x + (size / 2)
    transform.y = map_y + (size / 2)

    -- Set up gravity entity 
    local gravity_entity = {}
    gravity_entity.transform = transform

    local gravity_collider = {}
    gravity_collider.radius = range
    gravity_collider.entity = gravity_entity
    gravity_entity.circle_collider = gravity_collider
    add(circle_colliders, gravity_collider)

    gravity_entity.collisions = {}
    
    local gravity_component = {}
    gravity_component.force = force
    gravity_component.entity = gravity_entity
    gravity_entity.gravity_component = gravity_component
    add(gravity_components, gravity_component)

    local gravity_animation = {}
    gravity_animation.base_id = 0 -- to do 
    gravity_animation.frames = 2
    gravity_animation.transition_delay = 0.5
    gravity_animation.transition_time = 0
    gravity_animation.looped = true
    attach_component(gravity_entity, "animation_component", gravity_animation, animation_components)
    attach_component(gravity_entity, "sprite_component",
        {id=gravity_sprite, width=8, height=8}, sprite_components)

    add(entities, gravity_entity)

    local base_entity = {}
    base_entity.transform = transform

    local base_collider = {}
    base_collider.radius = size
    base_collider.entity = base_entity
    base_entity.
    base_entity.collisions = {}
end

local function goal_hit(other)
    if other.tag == "goal" then 
        transition("GamePlay", current_level + 1)
    end


end

-- scan_map callback: tag 1 marks a stationary 8x8 block.
local function spawn_block(map_x, map_y, sprite, tag)
    local entity = {
        transform = {
            x = (map_x - gameplay_loc[1]) * 8 + 4,
            y = (map_y - gameplay_loc[2]) * 8 + 4
        },
        tag = tag,
        collisions = {}
    }

    add(entities, entity)
    attach_component(entity, "square_collider", {width=8, height=8}, square_colliders)
    attach_component(entity, "sprite_component", {id=sprite, width=8, height=8}, sprite_components)
    return entity
end

-- Keys are combined sprite flag values, as read by scan_map.
local gameplay_spawn_handlers = {
    [1] = spawn_block
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
    for _, entity in pairs(entities) do
        if not active_entities[entity] then
            active_entities[entity] = true
            entity.collisions = entity.collisions or {}
            for i = #entity.collisions, 1, -1 do
                entity.collisions[i] = nil
            end
        end
    end

    local shapes = {}
    for _, shape in pairs(square_colliders) do
        local entity = shape.entity
        if entity and active_entities[entity] and entity.transform then
            shapes[#shapes + 1] = {
                entity=entity, shape=shape, kind="square"
            }
        end
    end
    for _, shape in pairs(circle_colliders) do
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
    for _, physics_component in ipairs(physics_components) do
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
                        this_entity.collided(collided_entity)
                    end 

                    if collided_entity.collided then
                        collided_entity.collided(this_entity)
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
    scan_map(gameplay_spawn_handlers, gameplay_loc[1], gameplay_loc[2], 16, 16)
end

function gameplay_teardown()
    entities = {}
    square_colliders = {}
    circle_colliders = {}
    physics_components = {}
    gravity_components = {}
    sprite_components = {}
    countdown_components = {}
    animation_components = {}
end

function game_systems_update()
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
    local paused = transition_state ~= nil and transition_state ~= "idle"
    for _, sprite_component in pairs(sprite_components) do
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
