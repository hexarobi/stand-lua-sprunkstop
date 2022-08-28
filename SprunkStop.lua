-- SprunkStop v1.0
-- a Lua script the Stand Mod Menu for GTA5
-- by Hexarobo

util.require_natives(1651208000)

local config = {
    can_lifetime = 5000,
    can_rain_delay = 100,
    max_rain_distance = 3,
    min_rain_height = 2,
    max_rain_height = 4,
    --can_rain_range = {
    --    x_max=3, y_max=3, z_max=4,
    --    x_min=-3, y_min=-3, z_min=2,
    --}
}

local spawned_objects = {}

local function load_hash(hash)
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        util.yield()
    end
end

local function cleanup_spawned_objects()
    local current_time = util.current_time_millis()
    for _, spawned_object in pairs(spawned_objects) do
        local lifetime = current_time - spawned_object.spawn_time
        if lifetime > config.can_lifetime then
            entities.delete_by_handle(spawned_object.handle)
        end
    end
end

local function spawn_sprunk_can(pos)
    local pickup_hash = util.joaat("ng_proc_sodacan_01b")
    load_hash(pickup_hash)
    local pickup_pos = v3.new(pos.x, pos.y, pos.z)
    local pickup = entities.create_object(pickup_hash, pickup_pos)
    ENTITY.SET_ENTITY_COLLISION(pickup, true, true)
    ENTITY.APPLY_FORCE_TO_ENTITY_CENTER_OF_MASS(
        pickup, 1, 0, 0, 0,
        true, false, true, true
    )
    table.insert(spawned_objects, { handle=pickup, spawn_time=util.current_time_millis()})
end

local function nearby_position(pos, range)
    if range == nil then
        range = {
            x_max=1, y_max=1, z_max=1,
            x_min=-1, y_min=-1, z_min=0,
        }
    end
    return {
        x=pos.x + math.random(range.x_min, range.x_max),
        y=pos.y + math.random(range.y_min, range.y_max),
        z=pos.z + math.random(range.z_min, range.z_max),
    }
end

local function sprunk_drop(pid, range)
    local player_pos = players.get_position(pid)
    local pickup_pos = nearby_position(player_pos, range)
    spawn_sprunk_can(pickup_pos)
end

local function sprunk_raindrop(pid)
    local range = {
        x_max=config.max_rain_distance, y_max=config.max_rain_distance, z_max=config.max_rain_height,
        x_min=config.max_rain_distance * -1, y_min=config.max_rain_distance * -1, z_min=config.min_rain_height,
    }
    sprunk_drop(pid, range)
end

menu.action(menu.my_root(), "Sprunk Drop", {"sprunkdrop"}, "Drop a single can of sprunk near you", function()
    sprunk_drop(players.user())
end)

menu.toggle_loop(menu.my_root(), "Sprunk Rain", {"sprunkrain"}, "Drop many cans of sprunk near you", function()
    sprunk_raindrop(players.user())
    util.yield(config.can_rain_delay)
end)

--menu.action(menu.my_root(), "Sprunkffalo", {"sprunkfallo"}, "Spawn a Buffalo with the best livery ever", function()
--    menu.trigger_commands("spawn buffalo3")
--end)

player_menu_actions = function(pid)
    menu.divider(menu.player_root(pid), "SprunkStop")

    menu.action(menu.player_root(pid), "Sprunk Drop", {"sprunkdrop"}, "", function()
        sprunk_drop(pid)
    end, nil, nil, COMMANDPERM_FRIENDLY)

    menu.toggle_loop(menu.player_root(pid), "Sprunk Rain", {"sprunkrain"}, "", function()
        sprunk_raindrop(pid)
        util.yield(config.can_rain_delay)
    end)

end
players.on_join(player_menu_actions)
players.dispatch_on_join()


local options_menu = menu.list(menu.my_root(), "Options")

menu.slider(options_menu, "Rain Drop Delay", {}, "The time between each rain drop", 30, 500, config.can_rain_delay, 10, function (value)
    config.can_rain_delay = value
end)

menu.slider(options_menu, "Can Lifetime", {}, "How long a dropped can should live before being despawned", 500, 15000, config.can_lifetime, 250, function (value)
    config.can_lifetime = value
end)

menu.slider(options_menu, "Rain Distance", {}, "Max distance cans can rain from the player", 1, 20, config.max_rain_distance, 1, function (value)
    config.max_rain_distance = value
end)

util.create_tick_handler(function()
    if spawned_objects then
        cleanup_spawned_objects()
    end
    return true
end)
