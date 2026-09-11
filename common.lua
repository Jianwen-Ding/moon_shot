Scene = "Title"
Latest_level = 0
Current_level = 0

-- Dispatch by the combined numeric sprite flags (0-255), not flag index.
-- Bounds and callback coordinates are in map tiles. Defaults: base 128x32 map.
-- Example: scan_map({[3] = spawn_planet}, 0, 0, 16, 16)
-- spawn_planet receives (map_x, map_y, sprite, tag).
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
                local tag = fget(sprite)
                local handler = handlers[tag]
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
            if Latest_level + 1 == Transition_level then
                Latest_level = Transition_level
            end
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
