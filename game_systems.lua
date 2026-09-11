-- Reserved 16x16 map regions, in tile coordinates (x, y).
background_loc = {32, 0}
gameplay_loc = {48, 0}

-- Holds entities and their attached components, including position transforms.
entities = {} 

-- holds all specific logic of the entity
-- Components use the same numeric index as their entity:
-- entities[1] = {transform={x=16, y=24}}
-- entities[2] = {transform={x=32, y=24}}
-- square_collider[1] = {width=8, height=8}
-- circle_collider[2] = {radius=12}
-- Transforms give shape centers; rectangle width and height are full sizes.
-- Keep fractional transform coordinates for physics and collisions.
-- Convert to whole pixels only when drawing; never round the transform itself.
-- collisions[1] contains references to entities touching entities[1].
collisions = {}
square_collider = {}
circle_collider = {}
physics_components = {}
gravity_component = {}
sprite_components = {}


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

local function add_collision(entity_index, other)
    local contacts = collisions[entity_index]
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
    for entity_index in pairs(collisions) do
        collisions[entity_index] = nil
    end

    local shapes = {}
    -- Component tables can have gaps when an entity lacks that shape.
    for entity_index, shape in pairs(square_collider) do
        if entities[entity_index] and entities[entity_index].transform then
            collisions[entity_index] = {}
            shapes[#shapes + 1] = {
                entity_index=entity_index, entity=entities[entity_index], shape=shape, kind="square"
            }
        end
    end
    for entity_index, shape in pairs(circle_collider) do
        if entities[entity_index] and entities[entity_index].transform then
            collisions[entity_index] = collisions[entity_index] or {}
            shapes[#shapes + 1] = {
                entity_index=entity_index, entity=entities[entity_index], shape=shape, kind="circle"
            }
        end
    end

    for i = 1, #shapes - 1 do
        for j = i + 1, #shapes do
            local a, b = shapes[i], shapes[j]
            if a.entity_index ~= b.entity_index and shapes_overlap(a, b) then
                add_collision(a.entity_index, b.entity)
                add_collision(b.entity_index, a.entity)
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
                -- handles gravity_component
                if collided_entity.gravity_component ~= nil then
                    local diff_x = collided_entity.transform.x - collided_entity.transform.x 
                    local diff_y = collided_entity.transform.y - collided_entity.transform.y
                    
                    -- normalization of diff
                    local magnitude = diff_x * diff_x + diff_y * diff_y
                    diff_x = diff_x/ magnitude
                    diff_y = diff_y / magnitude

                    accel_x = diff_x * collided_entity.gravity_component.force
                    accel_y = diff_y * collided_entity.gravity_component.force

                    physics_component.vel_x = physics_component.vel_x + accel_x
                    physics_component.vel_y = physics_component.vel_y + accel_y
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

-- scan_map callback: tag 1 marks a stationary 8x8 block.
local function spawn_block(map_x, map_y, sprite, tag)
    local entity_index = #entities + 1
    local entity = {
        transform = {
            x = (map_x - gameplay_loc[1]) * 8 + 4,
            y = (map_y - gameplay_loc[2]) * 8 + 4
        },
        sprite = sprite,
        tag = tag,
        square_collider = {width=8, height=8}
    }

    entities[entity_index] = entity
    square_collider[entity_index] = entity.square_collider
    return entity
end

-- Keys are combined sprite flag values, as read by scan_map.
local gameplay_spawn_handlers = {
    [1] = spawn_block
}

function gameplay_init()
    scan_map(gameplay_spawn_handlers, gameplay_loc[1], gameplay_loc[2], 16, 16)
end

function gameplay_teardown()
    entities = {}
    collisions = {}
    square_collider = {}
    circle_collider = {}
    physics_components = {}
    gravity_component = {}
end

function game_systems_update()
    check_collisions()
    run_physics()
end

function gameplay_draw()
    for _, sprite_component in pairs(sprite_components) do
        local transform = sprite_component.entity.transform
        local sprite_x = flr(transform.x - (sprite_component.width / 2))
        local sprite_y = flr(transform.y - (sprite_component.height / 2))
        spr(sprite_component.id, sprite_x, sprite_y)
    end
end
