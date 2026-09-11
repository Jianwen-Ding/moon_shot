scene = "Title"
latest_level = 0
current_level = 0

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
transition_map = {64, 0}
transition_duration = 0.5
transition_time = 0
transition_x = 128
transition_state = "idle"
transition_scene = nil
transition_level = nil
transition_started_at = 0

function transition(new_scene, level)
    if transition_state ~= "idle" then
        return
    end

    transition_scene = new_scene
    transition_level = level
    transition_time = 0
    transition_x = 128
    transition_started_at = time()
    transition_state = "covering"
end

function transition_update()
    if transition_state == "idle" then
        return
    end

    local phase_duration = transition_duration / 2

    if transition_state == "covering" then
        local progress = 1
        if phase_duration > 0 then
            progress = min((time() - transition_started_at) / phase_duration, 1)
        end

        transition_time = progress * phase_duration
        transition_x = 128 - progress * 128

        if progress < 1 then
            return
        end

        -- Swap scenes only while the map covers every screen pixel.
        transition_x = 0
        teardown_scene()
        scene = transition_scene

        if transition_level ~= nil then
            if latest_level + 1 == transition_level then
                latest_level = transition_level
            end
            current_level = transition_level
        end

        init_scene()
        transition_started_at = time()
        transition_state = "revealing"
        return
    end

    local progress = 1
    if phase_duration > 0 then
        progress = min((time() - transition_started_at) / phase_duration, 1)
    end

    transition_time = phase_duration + progress * phase_duration
    transition_x = -progress * 128

    if progress >= 1 then
        transition_state = "idle"
        transition_scene = nil
        transition_level = nil
        transition_x = -128
    end
end

function transition_draw()
    if transition_state ~= "idle" then
        camera()
        map(transition_map[1], transition_map[2], flr(transition_x), 0, 16, 16)
    end
end
