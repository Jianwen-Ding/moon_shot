background_loc = {0, 0}
gameplay_loc = {0, 0}

-- holds references to location of entity and components attached to entity
entities = {} 

-- holds all specific logic of the entity
-- Components are keyed by entity name:
-- entities.ship = {x=16, y=24}
-- squareCollider.ship = {width=8, height=8}
-- circleCollider.planet = {radius=12}
-- Square positions are top-left corners; circle positions are centers.
-- collider.ship contains the names of entities touching the ship.
collider = {}
squareCollider = {}
circleCollider = {}
physics = {}
gravity_object = {}

local function shapesOverlap(a, b)
    local ax, ay = a.entity.x, a.entity.y
    local bx, by = b.entity.x, b.entity.y

    if a.kind == "square" and b.kind == "square" then
        return ax <= bx + b.shape.width
            and ax + a.shape.width >= bx
            and ay <= by + b.shape.height
            and ay + a.shape.height >= by
    end

    if a.kind == "circle" and b.kind == "circle" then
        local dx, dy = ax - bx, ay - by
        local radius = a.shape.radius + b.shape.radius
        return dx * dx + dy * dy <= radius * radius
    end

    -- Find the closest point on the square to the circle's center.
    if a.kind == "circle" then
        a, b = b, a
    end
    local x = max(a.entity.x, min(b.entity.x, a.entity.x + a.shape.width))
    local y = max(a.entity.y, min(b.entity.y, a.entity.y + a.shape.height))
    local dx, dy = b.entity.x - x, b.entity.y - y
    return dx * dx + dy * dy <= b.shape.radius * b.shape.radius
end

local function addCollision(name, other)
    local contacts = collider[name]
    -- An entity may have both shape components; report each name once.
    for _, contact in ipairs(contacts) do
        if contact == other then
            return
        end
    end
    contacts[#contacts + 1] = other
end

function checkCollisions()
    -- Rebuild contacts so separated or removed entities leave no stale names.
    for name in pairs(collider) do
        collider[name] = nil
    end

    local shapes = {}
    for name, shape in pairs(squareCollider) do
        if entities[name] then
            collider[name] = {}
            shapes[#shapes + 1] = {
                name=name, entity=entities[name], shape=shape, kind="square"
            }
        end
    end
    for name, shape in pairs(circleCollider) do
        if entities[name] then
            collider[name] = {}
            shapes[#shapes + 1] = {
                name=name, entity=entities[name], shape=shape, kind="circle"
            }
        end
    end

    for i = 1, #shapes - 1 do
        for j = i + 1, #shapes do
            local a, b = shapes[i], shapes[j]
            if a.name ~= b.name and shapesOverlap(a, b) then
                addCollision(a.name, b.name)
                addCollision(b.name, a.name)
            end
        end
    end
end

function runPhysics() 
end 



function gameplayInit()
end

function gameplayUpdate()
    checkCollisions()
end

function gameplayDraw()
end
