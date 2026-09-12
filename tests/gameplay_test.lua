-- Run from the repository root: lua moon_shot/tests/gameplay_test.lua
-- Exercises the real cartridge code and map data with a minimal PICO-8 API.
local root = (arg[0]:match("^(.*[/])") or "").."../"
local function read(path)
    local file = assert(io.open(path, "r"))
    local data = file:read("*a")
    file:close()
    return data
end
local cart = read(root.."moon_shot.p8")
local map_rows, gfx_rows = {}, {}
for row in cart:match("__map__\n(.*)"):gmatch("[^\n]+") do
    assert(#row == 256, "map row width")
    map_rows[#map_rows+1] = row
end
for row in cart:match("__gfx__\n(.-)__map__"):gmatch("[^\n]+") do
    assert(#row == 128, "sprite sheet row width")
    gfx_rows[#gfx_rows+1] = row
end
-- PICO-8 omits trailing empty rows when saving cartridges.
assert(#map_rows <= 32 and #gfx_rows <= 128)
for index = #gfx_rows+1,128 do gfx_rows[index] = string.rep("0",128) end
local ticks, held, pressed, draws = 0, {}, {}, {}
local host_print = print
min, max, flr, abs, sqrt = math.min, math.max, math.floor, math.abs, math.sqrt
function mid(a, b, c) return math.max(math.min(a,c), math.min(math.max(a,c),b)) end
function cos(a) return math.cos(a*math.pi*2) end
function sin(a) return -math.sin(a*math.pi*2) end
function time() return ticks/30 end
function btn(i) return held[i] or false end
function btnp(i) return pressed[i] or false end
function add(list, value) list[#list+1] = value; return value end
function del(list, value)
    for i, item in ipairs(list) do if item == value then return table.remove(list,i) end end
end
function deli(list, index) return table.remove(list,index) end
function mget(x,y)
    local row = map_rows[y+1]
    if not row or x < 0 or x > 127 then return 0 end
    return tonumber(row:sub(x*2+1,x*2+2),16)
end
local function record(kind, ...)
    draws[#draws+1] = {kind, ...}
end
function spr(id,x,y)
    assert(id == math.floor(id) and id >= 0 and id <= 255, "invalid sprite ID")
    assert(x == math.floor(x) and y == math.floor(y), "fractional render position")
    record("spr",id,x,y)
end
function sspr(sx,sy,sw,sh,x,y,w,h)
    assert(x == math.floor(x) and y == math.floor(y), "fractional scaled render position")
    record("sspr",sx,sy,sw,sh,x,y,w,h)
end
function map(...) record("map",...) end
function cls(...) record("cls",...) end
function camera(...) record("camera",...) end
function print(...) record("print",...) end
function line(...) record("line",...) end
function rect(...) record("rect",...) end
function rectfill(...) record("rectfill",...) end
function pset(...) record("pset",...) end
local lua_code = cart:match("__lua__\n(.-)__gfx__")
lua_code = lua_code:gsub("#include ([^\n]+)", function(path)
    return read(root..path:match("^%s*(.-)%s*$"))
end)
assert(load(lua_code,"@moon_shot.p8"))()
local passed = 0
local function test(name, fn)
    fn()
    passed = passed+1
    host_print("ok - "..name)
end
local function frame(keys, edges)
    held, pressed = keys or {}, edges or {}
    ticks = ticks+1
    draws = {}
    _update()
    _draw()
end
local function frames(count) for _ = 1,count do frame() end end
local function begin_level(index)
    Transition_state = "idle"
    Scene, Current_level = "Gameplay", index
    init_scene()
    held, pressed = {}, {}
    _draw()
end
local function find_tag(tag)
    for _, entity in ipairs(Entities) do if entity.tag == tag then return entity end end
end
local function contains(list, value)
    for _, item in ipairs(list) do if item == value then return true end end
    return false
end
local function check_ownership()
    for _, name in ipairs({"Square_colliders","Circle_colliders","Physics_components","Gravity_components","Sprite_components","Countdown_components","Animation_components"}) do
        for _, component in ipairs(_G[name]) do
            assert(contains(Entities,component.entity), "orphan "..name)
            local linked = false
            for _, value in pairs(component.entity) do if value == component then linked = true end end
            assert(linked, "missing reverse reference "..name)
        end
    end
    for _, entity in ipairs(Entities) do
        for _, contact in ipairs(entity.collisions) do assert(contains(Entities,contact), "stale collision") end
    end
end
test("idle title and button-driven menu", function()
    _init()
    frames(3)
    assert(Scene == "Title" and Transition_state == "idle")
    frame({}, {[5]=true})
    assert(Transition_state == "covering" and Scene == "Title")
    for _, call in ipairs(draws) do assert(call[1] ~= "cls", "wipe cleared frozen scene") end
    frames(20)
    assert(Scene == "MainMenu" and Transition_state == "idle")
    frame({}, {[1]=true,[3]=true})
    assert(Current_menu_loc[1] == 2 and Current_menu_loc[2] == 2)
    frame({}, {[5]=true})
    assert(Transition_level == 6)
end)
test("eight distinct maps, centered colliders and copied inventories", function()
    local signatures = {}
    for index, level in ipairs(Levels) do
        begin_level(index)
        local ship, goal, signature = 0, 0, ""
        for _, entity in ipairs(Entities) do
            if entity.tag == "ship" then ship = ship+1 end
            if entity.tag == "goal" then goal = goal+1 end
            if entity.physics_component then
                assert(entity.circle_collider.radius == 4)
                assert(not entity.physics_component.enabled)
                assert(entity.transform.x%8 == 4 and entity.transform.y%8 == 4)
                signature = signature..entity.sprite_component.id..":"..entity.transform.x..","..entity.transform.y..";"
            end
        end
        assert(ship == 1 and goal == 1 and Player_entity == find_tag("ship"))
        assert(not signatures[signature], "duplicate layout")
        signatures[signature] = true
        assert(#Throw_inventory_ids == #level.inventory and Throw_inventory_ids ~= level.inventory)
        local x,y = Player_entity.transform.x,Player_entity.transform.y
        frames(10)
        assert(Player_entity.transform.x == x and Player_entity.transform.y == y)
        check_ownership()
    end
end)
test("opaque backgrounds and transition tiles, populated artwork", function()
    for _, origin in ipairs({Title_screen_sprite,Main_menu_background_loc,Background_loc,Transition_map}) do
        for y = origin[2],origin[2]+15 do for x = origin[1],origin[1]+15 do
            local id = mget(x,y)
            assert(id ~= 0)
            for py = 1,8 do
                local row = gfx_rows[math.floor(id/16)*8+py]
                assert(not row:sub(id%16*8+1,id%16*8+8):find("0"), "transparent wipe/background")
            end
        end end
    end
    for _, id in ipairs({16,17,18,19,20,32,33,34,35,48,49,64,65,66,67,68,69,70,71}) do
        local nonempty = false
        for py = 1,8 do
            local row = gfx_rows[math.floor(id/16)*8+py]
            if row:sub(id%16*8+1,id%16*8+8):find("[1-f]") then nonempty = true end
        end
        assert(nonempty, "blank sprite "..id)
    end
end)
test("throw, cooldown, fractional movement, ship launch, immutable UI", function()
    begin_level(2)
    local ship, before = Player_entity, #Entities
    frame({[0]=true,[2]=true})
    assert(Current_throw_angle > 0 and Current_throw_strength > 1.5)
    frame({}, {[5]=true})
    assert(#Throw_inventory_ids == 0 and #Levels[2].inventory == 1 and not Thrown_self)
    assert(#Entities == before+2 and Player_entity == ship)
    local projectile = Entities[#Entities]
    assert(projectile.physics_component.enabled and projectile.transform.x%1 ~= 0)
    frame({}, {[5]=true})
    assert(not Thrown_self, "cooldown ignored")
    frames(15)
    local x,y = Ui_frame_start_loc[1],Ui_frame_start_loc[2]
    local px,py = projectile.transform.x,projectile.transform.y
    _draw(); _draw()
    assert(Ui_frame_start_loc[1] == x and Ui_frame_start_loc[2] == y)
    assert(projectile.transform.x == px and projectile.transform.y == py)
    frame({}, {[5]=true})
    assert(Thrown_self and Player_entity == ship and ship.physics_component.enabled)
    local angle = Current_throw_angle
    frame({[0]=true})
    assert(Current_throw_angle == angle, "aim changed after launch")
    check_ownership()
end)
test("independent component order, centered mixed contacts and clearing", function()
    gameplay_teardown()
    Transition_state = "idle"
    local a = {transform={x=10.5,y=10.5},collisions={}}
    local b = {transform={x=18.5,y=10.5},collisions={}}
    local c = {transform={x=220,y=220},collisions={}}
    add(Entities,c); add(Entities,b); add(Entities,a)
    attach_component(a,"square_collider",{width=8,height=8},Square_colliders)
    attach_component(a,"circle_collider",{radius=4},Circle_colliders)
    attach_component(b,"circle_collider",{radius=4},Circle_colliders)
    attach_component(c,"circle_collider",{radius=4},Circle_colliders)
    game_systems_update()
    assert(#a.collisions == 1 and a.collisions[1] == b and b.collisions[1] == a)
    assert(#c.collisions == 0)
    b.transform.x = 19
    game_systems_update()
    assert(#a.collisions == 0 and #b.collisions == 0)
    check_ownership()
end)
test("gravity uses both full-size ring frames and stays centered", function()
    begin_level(1)
    local goal = find_tag("goal")
    local ring = goal.gravity_entity
    assert(ring.transform == goal.transform)
    local animation = ring.animation_component
    for frame_index = 1,2 do
        animation.current_frame = frame_index
        animation.last_draw_time = time()
        draws = {}
        gameplay_draw()
        local found = false
        for _, call in ipairs(draws) do
            if call[1] == "sspr" and call[6] == goal.transform.x-16 and call[7] == goal.transform.y-16 then
                assert(call[2] == (frame_index == 1 and 40 or 72) and call[3] == 0)
                assert(call[4] == 32 and call[5] == 32 and call[8] == 32 and call[9] == 32)
                found = true
            end
        end
        assert(found, "missing full-size ring")
    end
end)
test("gravity sprites stay behind the goal regardless of spawn order", function()
    begin_level(1)
    local goal = find_tag("goal")
    default_planet_spawn(goal.transform.x-14,goal.transform.y)
    for _, reverse in ipairs({false,true}) do
        if reverse then
            local reordered = {}
            for index = #Sprite_components,1,-1 do add(reordered,Sprite_components[index]) end
            Sprite_components = reordered
        end
        draws = {}
        gameplay_draw()
        local goal_draw, last_gravity_draw, sprite_count = nil,0,0
        for index, call in ipairs(draws) do
            if call[1] == "sspr" then last_gravity_draw = index end
            if call[1] == "spr" and call[2] == Id_goal_planet_sprite then goal_draw = index end
            if call[1] == "spr" or call[1] == "sspr" then sprite_count = sprite_count+1 end
        end
        assert(goal_draw and goal_draw > last_gravity_draw, "gravity drawn over goal")
        assert(sprite_count == #Sprite_components, "missing or repeated sprite")
    end
end)
test("animation frames, non-loop hold, countdown removal and ownership", function()
    begin_level(1)
    local count = #Entities
    local effect = spawn_timed_animation(50.25,50.75,32,4,0.05,0.25)
    _draw()
    frames(2)
    assert(effect.animation_component.current_frame == 2)
    frames(4)
    assert(effect.animation_component.current_frame == 4)
    frames(2)
    assert(#Entities == count and effect.transform == nil and effect.sprite_component == nil)
    check_ownership()
    local gravity = Player_entity.gravity_entity.animation_component
    gravity.last_draw_time, gravity.transition_time, gravity.current_frame = time(),0,1
    frames(15)
    assert(gravity.current_frame == 2)
    frames(15)
    assert(gravity.current_frame == 1)
end)
test("transition freezes physics and timers, tears down at full cover", function()
    begin_level(1)
    local ship = Player_entity
    ship.physics_component.enabled,ship.physics_component.vel_x = true,0.5
    local effect = spawn_timed_animation(50,50,32,4,0.05,1)
    frame()
    local x,timer = ship.transform.x,effect.countdown_component.elapsed_frames
    transition("Gameplay",2)
    frames(5)
    assert(Scene == "Gameplay" and Current_level == 1)
    assert(ship.transform.x == x and effect.countdown_component.elapsed_frames == timer)
    for _, call in ipairs(draws) do assert(call[1] ~= "cls") end
    frames(3)
    assert(Transition_state == "revealing" and Transition_x == 0 and Current_level == 2)
    assert(not contains(Entities,ship) and not contains(Entities,effect))
    local new_ship = Player_entity
    x = new_ship.transform.x
    frames(5)
    assert(new_ship.transform.x == x)
    frames(5)
    assert(Transition_state == "idle")
    check_ownership()
end)
test("destroyed ship and goal restart and clean up their gravity", function()
    for _, tag in ipairs({"ship","goal"}) do
        begin_level(2)
        local victim = find_tag(tag)
        local aura = victim.gravity_entity
        local other = default_planet_spawn(victim.transform.x,victim.transform.y)
        other.physics_component.enabled = true
        frame()
        assert(Level_failed and victim.transform == nil and aura.transform == nil)
        assert(not contains(Entities,victim) and not contains(Entities,aura))
        check_ownership()
        frames(8)
        assert(Transition_state == "covering" and Transition_level == 2)
        frames(20)
        assert(Current_level == 2 and not Level_failed and Player_entity)
        assert(#Throw_inventory_ids == 1)
        check_ownership()
    end
end)
test("out-of-bounds ship restarts", function()
    begin_level(1)
    Player_entity.transform.x = 137
    Player_entity.physics_component.enabled = true
    frame()
    assert(Level_failed and Player_entity == nil)
    frames(8)
    assert(Transition_level == 1)
end)
test("winning level 8 alone does not mark other levels complete", function()
    begin_level(8)
    Completed_levels, Campaign_complete, Latest_level = {},false,0
    Player_entity:collided(find_tag("goal"))
    assert(Completed_levels[8] and not Completed_levels[1] and not Campaign_complete)
    assert(Transition_scene == "MainMenu" and Transition_level == nil)
end)
test("all eight levels are playable through throwing and ship flight", function()
    Completed_levels, Campaign_complete, Latest_level = {},false,0
    for index = 1,#Levels do
        begin_level(index)
        -- Levels 2, 5 and 6 teach aiming around obstacles; discard the practice
        -- moon upward. The other levels let moons clear the straight path.
        if index == 2 or index == 5 or index == 6 then Current_throw_angle = 0.25 end
        while #Throw_inventory_ids > 0 do
            frame({}, {[5]=true})
            frames(60)
            assert(not Level_failed and Transition_state == "idle", "moon failed level "..index)
        end
        local ship = Player_entity
        Current_throw_angle = Active_level.angle
        frame({}, {[5]=true})
        assert(Thrown_self)
        for _ = 1,150 do
            if Transition_state ~= "idle" then break end
            frame()
        end
        assert(Completed_levels[index], "ship failed level "..index.." at "..tostring(ship.transform and ship.transform.x)..","..tostring(ship.transform and ship.transform.y).." failed="..tostring(Level_failed))
        assert(Transition_state == "covering")
        frames(20)
        if index < #Levels then assert(Current_level == index+1 and Scene == "Gameplay")
        else assert(Current_level == 8 and Scene == "MainMenu" and Campaign_complete) end
        check_ownership()
    end
end)
host_print(passed.." tests passed")
