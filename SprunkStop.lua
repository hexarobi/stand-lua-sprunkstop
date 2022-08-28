-- SprunkStop v1.1
-- a Lua script the Stand Mod Menu for GTA5
-- Save this file in `Stand/Lua Scripts`
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

local function get_rain_range()
    return {
        x_max=config.max_rain_distance, y_max=config.max_rain_distance, z_max=config.max_rain_height,
        x_min=config.max_rain_distance * -1, y_min=config.max_rain_distance * -1, z_min=config.min_rain_height,
    }
end

local spawned_objects = {}

local sprunk_vehicles = {
    {
        model="thrax",
        livery=8,
    },
    {
        model="tezeract",
        livery=2,
    },
    {
        model="nero2",
        livery=6
    },
    {
        model="champion",
        livery=9
    },
    {
        model="jugular",
        livery=7
    },
    {
        model="buffalo3",
        livery=-1
    },
    {
        model="gb200",
        livery=9
    },
    {
        model="paragon",
        livery=6
    },
    {
        model="issi7",
        livery=6
    },
    {
        model="imorgon",
        livery=4
    },
    {
        model="zr350",
        livery=6
    },
    {
        model="euros",
        livery=13
    },
    {
        model="brioso",
        livery=1
    },
    {
        model="asbo",
        livery=5
    },
    {
        model="faction3",
        livery=5
    },
    {
        model="buffalo4",
        livery=6
    },
    {
        model="novak",
        livery=6
    },
    {
        model="sanchez",
        livery=-1
    },
    {
        model="bf400",
        livery=1
    },
    {
        model="bati2",
        livery=2
    },
    {
        model="reever",
        livery=9
    },
    {
        model="formula",
        livery=1
    },
    {
        model="openwheel1",
        livery=7
    },
    {
        model="veto2",
        livery=0
    },
    {
        model="pony",
        livery=1
    },
}

for _, sprunk_vehicle in pairs(sprunk_vehicles) do
    sprunk_vehicle.model_hash = util.joaat(sprunk_vehicle.model)
end

local function load_hash(hash)
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        util.yield()
    end
end

local function show_busyspinner(text)
    HUD.BEGIN_TEXT_COMMAND_BUSYSPINNER_ON("STRING")
    HUD.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(text)
    HUD.END_TEXT_COMMAND_BUSYSPINNER_ON(2)
end

-- From Jackz Vehicle Options script
-- Gets the player's vehicle, attempts to request control. Returns 0 if unable to get control
local function get_player_vehicle_in_control(pid, opts)
    local my_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(players.user()) -- Needed to turn off spectating while getting control
    local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)

    -- Calculate how far away from target
    local pos1 = ENTITY.GET_ENTITY_COORDS(target_ped)
    local pos2 = ENTITY.GET_ENTITY_COORDS(my_ped)
    local dist = SYSTEM.VDIST2(pos1.x, pos1.y, 0, pos2.x, pos2.y, 0)

    local was_spectating = NETWORK.NETWORK_IS_IN_SPECTATOR_MODE() -- Needed to toggle it back on if currently spectating
    -- If they out of range (value may need tweaking), auto spectate.
    local vehicle = PED.GET_VEHICLE_PED_IS_IN(target_ped, true)
    if opts and opts.near_only and vehicle == 0 then
        return 0
    end
    if vehicle == 0 and target_ped ~= my_ped and dist > 340000 and not was_spectating then
        util.toast("Player is too far, auto-spectating for upto 3s.")
        show_busyspinner("Player is too far, auto-spectating for upto 3s.")
        NETWORK.NETWORK_SET_IN_SPECTATOR_MODE(true, target_ped)
        -- To prevent a hard 3s loop, we keep waiting upto 3s or until vehicle is acquired
        local loop = (opts and opts.loops ~= nil) and opts.loops or 30 -- 3000 / 100
        while vehicle == 0 and loop > 0 do
            util.yield(100)
            vehicle = PED.GET_VEHICLE_PED_IS_IN(target_ped, true)
            loop = loop - 1
        end
        HUD.BUSYSPINNER_OFF()
    end

    if vehicle > 0 then
        if NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(vehicle) then
            return vehicle
        end
        -- Loop until we get control
        local netid = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(vehicle)
        local has_control_ent = false
        local loops = 15
        NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netid, true)

        -- Attempts 15 times, with 8ms per attempt
        while not has_control_ent do
            has_control_ent = NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(vehicle)
            loops = loops - 1
            -- wait for control
            util.yield(15)
            if loops <= 0 then
                break
            end
        end
    end
    if not was_spectating then
        NETWORK.NETWORK_SET_IN_SPECTATOR_MODE(false, target_ped)
    end
    return vehicle
end

local function spawn_vehicle_for_player(pid, model_name)
    local model = util.joaat(model_name)
    if not STREAMING.IS_MODEL_VALID(model) or not STREAMING.IS_MODEL_A_VEHICLE(model) then
        -- util.toast("Error: Invalid vehicle name")
        return
    else
        load_hash(model)
        local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(target_ped, 0.0, 4.0, 0.5)
        local heading = ENTITY.GET_ENTITY_HEADING(target_ped)
        local vehicle = entities.create_vehicle(model, pos, heading)
        STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(model)
        return vehicle
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

local function sprunk_can_drop(position, range)
    local spawn_position = position
    if range then
        spawn_position = nearby_position(position, range)
    end
    spawn_sprunk_can(spawn_position)
end

local function sprunk_drop_player(pid, range)
    sprunk_can_drop(players.get_position(pid), range)
end

local function sprunk_drop_vehicle(vehicle, range)
    sprunk_can_drop(ENTITY.GET_ENTITY_COORDS(vehicle), range)
end

local function sprunk_raindrop_player(pid)
    sprunk_drop_player(pid, get_rain_range())
end

local function sprunk_raindrop_vehicle(vehicle)
    sprunk_drop_vehicle(vehicle, get_rain_range())
end

local function sprunkify_vehicle(vehicle)

    -- Set Primary and Secondary colors
    local color = {r=0, g=255, b=0}
    VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, color.r, color.g, color.b)
    VEHICLE.SET_VEHICLE_MOD_COLOR_1(vehicle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, color.r, color.g, color.b)
    VEHICLE.SET_VEHICLE_MOD_COLOR_2(vehicle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_MOD(vehicle, 48, -1)

    -- Green Headlights
    VEHICLE.TOGGLE_VEHICLE_MOD(vehicle, 22, true)
    VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(vehicle, 4)

    -- Green Neon Lights
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 0, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 1, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 2, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 3, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(vehicle, color.r, color.g, color.b)

    -- Set Wheel Color
    VEHICLE.SET_VEHICLE_EXTRA_COLOURS(vehicle, 0, 55)

    -- Set License Plate
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, "SPRUNK")

    -- Set Livery only if its a Sprunk livery
    local target_livery = -1
    local model_hash = entities.get_model_hash(entities.handle_to_pointer(vehicle))
    for _, sprunk_vehicle in pairs(sprunk_vehicles) do
        if sprunk_vehicle.model_hash == model_hash then
            target_livery = sprunk_vehicle.livery
        end
    end
    VEHICLE.SET_VEHICLE_MOD(vehicle, 48, target_livery)

end

menu.action(menu.my_root(), "Sprunk Drop", {"sprunkdrop"}, "Drop a single can of sprunk near you", function()
    sprunk_drop(players.user())
end)

menu.toggle_loop(menu.my_root(), "Sprunk Rain", {"sprunkrain"}, "Drop many cans of sprunk near you", function()
    sprunk_raindrop_player(players.user())
    util.yield(config.can_rain_delay)
end)

menu.action(menu.my_root(), "Sprunk", {"sprunk"}, "Sprunk!", function(click_type, pid)
    local sprunk_vehicle = sprunk_vehicles[math.random(1, #sprunk_vehicles)]
    local vehicle = spawn_vehicle_for_player(pid, sprunk_vehicle.model)
    if vehicle then
        sprunkify_vehicle(vehicle)
        for i = 1,10,1 do
            sprunk_raindrop_vehicle(vehicle)
        end
    end
end, nil, nil, COMMANDPERM_FRIENDLY)

menu.action(menu.my_root(), "Sprunkify Vehicle", {"sprunkify"}, "Sprunkify your vehicle!", function(click_type, pid)
    local vehicle = get_player_vehicle_in_control(pid)
    if vehicle then
        sprunkify_vehicle(vehicle)
    end
end, nil, nil, COMMANDPERM_FRIENDLY)

menu.action(menu.my_root(), "Sprunkart", {"sprunkmobile"}, "Spawn a sprunkified go kart!", function(click_type, pid)
    local vehicle = spawn_vehicle_for_player(pid, "veto2")
    if vehicle then
        sprunkify_vehicle(vehicle)
    end
end, nil, nil, COMMANDPERM_FRIENDLY)

--menu.action(menu.my_root(), "Sprunkffalo", {"sprunkfallo"}, "Spawn a Buffalo with the best livery ever", function()
--    menu.trigger_commands("spawn buffalo3")
--end)

player_menu_actions = function(pid)
    menu.divider(menu.player_root(pid), "SprunkStop")

    menu.action(menu.player_root(pid), "Sprunk Drop", {"sprunkdrop"}, "", function()
        sprunk_drop(pid)
    end, nil, nil, COMMANDPERM_FRIENDLY)

    menu.toggle_loop(menu.player_root(pid), "Sprunk Rain", {"sprunkrain"}, "", function()
        sprunk_raindrop_player(pid)
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
