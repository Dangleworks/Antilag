spawning_enabled = true
antilag_chat = "[ANTI-LAG]"
antilag_notify = "ANTI-LAG"
vehicle_limit_notify = "VEHICLE LIMITS"
vehicle_limit_chat = "[VEHICLE LIMITS]"
verify_port = 9006

steam_ids = {}
peer_ids = {}

tps = 0
tps_uiid = 0
vehicle_uiid = 0
ticks_time = 0
ticks = 0
tps_buff = {}

vpop_delay = 0

function onCreate(is_world_create)
    if g_savedata.antilag == nil then
        g_savedata.antilag = {}
    end
    if g_savedata.antilag.base_vehicle_limit == nil then
        g_savedata.antilag.base_vehicle_limit = 1
    end
    if g_savedata.antilag.auth_vehicle_limit == nil then
        g_savedata.antilag.auth_vehicle_limit = 3
    end
    if g_savedata.antilag.nitro_vehicle_limit == nil then
        g_savedata.antilag.nitro_vehicle_limit = 5
    end
    if g_savedata.antilag.max_mass == nil then
        g_savedata.antilag.max_mass = 70000
    end
    if g_savedata.antilag.tps_threshold == nil then
        g_savedata.antilag.tps_threshold = 45
    end
    if g_savedata.antilag.load_time_threshold == nil then
        g_savedata.antilag.load_time_threshold = 3000
    end
    if g_savedata.antilag.tps_recover_time == nil then
        g_savedata.antilag.tps_recover_time = 4000
    end
    if g_savedata.antilag.auto_despawn_vehicle_limit == nil then
        g_savedata.antilag.auto_despawn_vehicle_limit = true
    end
    if g_savedata.vehicle_limits == nil then
        g_savedata.vehicle_limits = {}
    end
    if g_savedata.user_vehicles == nil then
        g_savedata.user_vehicles = {}
    end
    if g_savedata.antilag.admin_bypass_vehicle_limit == nil then
        g_savedata.antilag.admin_bypass_vehicle_limit = false
    end
    if g_savedata.antilag.disable_vehicle_limit == nil then
        g_savedata.antilag.disable_vehicle_limit = false
    end
    if g_savedata.antilag.tps_avg_diff_threshold == nil then
        g_savedata.antilag.tps_avg_diff_threshold = 15
    end
    if g_savedata.antilag.vehicle_stabilize_chances == nil then
        g_savedata.antilag.vehicle_stabilize_chances = 1
    end
    if g_savedata.antilag.remove_objects == nil then
        g_savedata.antilag.remove_objects = true
    end
    if g_savedata.lastOID == nil then
        g_savedata.lastOID = 0
    end

    tps_uiid = server.getMapID()
    vehicle_uiid = server.getMapID()
    tps_buff = NewBuffer(g_savedata.antilag.tps_recover_time/500)

    for _, player in pairs(server.getPlayers()) do
		steam_ids[player.id] = tostring(player.steam_id)
        peer_ids[tostring(player.steam_id)] = player.id
	end
end

function onDestroy()
    for _, p in pairs(server.getPlayers()) do
        server.removePopup(p.id, tps_uiid)
        server.removePopup(p.id, vehicle_uiid)
    end
end

function onPlayerJoin(steam_id, name, peer_id, admin, auth)
    steam_ids[peer_id] = tostring(steam_id)
    peer_ids[tostring(steam_id)] = peer_id
    server.httpGet(verify_port, "/check?sid="..steam_id)
end

function httpReply(port, url, response_body)
    if port == verify_port and string.sub(url, 1, 6) == "/check" then
        local response = json.parse(response_body)
        if response == nil then 
            response = {}
            logError("Discord Auth - Failed to parse response body: "..response_body)
            return
        end

        if response.status == false then
            g_savedata.vehicle_limits[response.steam_id] = g_savedata.antilag.base_vehicle_limit
        elseif response.status == true then
            g_savedata.vehicle_limits[response.steam_id] = g_savedata.antilag.auth_vehicle_limit
        elseif response.status == "nitro" then
            g_savedata.vehicle_limits[response.steam_id] = g_savedata.antilag.nitro_vehicle_limit
        else
            logError("Discord auth check failed: "..response_body)
            g_savedata.vehicle_limits[string.sub(url, 12)] = g_savedata.antilag.base_vehicle_limit
        end
    end
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, cost)
    if peer_id == -1 then return end
    if not spawning_enabled and not isAdmin(peer_id) then
        server.despawnVehicle(vehicle_id, true)
        server.notify(peer_id, antilag_notify, "Vehicle spawning is temporarily disabled by antilag. Please try again in a minute.", 6)
        return
    end
    local owner_sid = steam_ids[peer_id]
    if g_savedata.user_vehicles[owner_sid] == nil then
        g_savedata.user_vehicles[owner_sid] = {}
    end
    local vehicles = g_savedata.user_vehicles[owner_sid]

    -- Vehicle limit logic
    -- vehicle count exceeded
    if tableLength(vehicles) >= g_savedata.vehicle_limits[owner_sid] then
        local bypass = false
        -- if player is an admin, and admin bypass is enabled
        if isAdmin(peer_id) and g_savedata.antilag.admin_bypass_vehicle_limit then
            bypass = true
        end
        if g_savedata.antilag.disable_vehicle_limit then
            bypass = true
        end

        if not bypass then
            if g_savedata.auto_despawn_vehicle_limit then
                -- TODO: Wait until new vehicle loads before despawning the last vehicle in case it's invalid for another reason
                -- despawn oldest vehicle
                local msg = "Your vehicle with ID %d has been despawned to allow ID %d to spawn."
                server.notify(peer_id, vehicle_limit_notify, string.format(msg, vehicles[1].vehicle_id, vehicle_id), 6)
                server.despawnVehicle(vehicles[1].vehicle_id, true)
            else
                server.despawnVehicle(vehicle_id, true)
                server.notify(peer_id, vehicle_limit_notify, "Your vehicle was not spawned", 6)
                local msg = string.format(
                    "You have reached your maxmimum spawned vehicle limit of %d. Please run the ?c command to clean up your old vehicles.",
                    g_savedata.vehicle_limits[owner_sid])
                server.announce(vehicle_limit_chat, msg, peer_id)
                -- return here because the vehicle was not spawned
                return
            end
        end
    end
    -- TODO: Check if another vehicle is already in the spawn zone
    -- Start tracking vehicle
    table.insert(g_savedata.user_vehicles[owner_sid], {
        peer_id=peer_id, 
        vehicle_id=vehicle_id, 
        vehicle_name="Unknown", 
        spawn_time=server.getTimeMillisec(), 
        spawn_tps=tps, 
        spawn_avg_tps=Mean(tps_buff.values), 
        loaded=false, 
        cleared=false, 
        stablize_count=0
    })
end

function onVehicleLoad(vehicle_id)
    local owner_sid = getVehicleOwnerSteamID(vehicle_id)
    if owner_sid == -1 then return end
    local peer_id = peer_ids[owner_sid]

    -- TODO: voxel data is now returned with vehicle data, maybe use this instead of mass?
    local vd = server.getVehicleData(vehicle_id)
    -- enforce vehicle mass limit
    if vd.mass >= g_savedata.antilag.max_mass then
        server.despawnVehicle(vehicle_id, true)
        local msg = string.format("Your vehicle was despawned for being an absolute chonker. (Weight Limit: %d)", g_savedata.antilag.max_mass)
        server.notify(peer_id, antilag_notify, msg, 6)
        return
    end
    -- when a vehicle is loaded, update its record to start tracking the effect it has on tps
    local vehicles = g_savedata.user_vehicles[owner_sid]
    for idx, vehicle in ipairs(vehicles) do
        if vehicle.vehicle_id == vehicle_id then
            vehicle.spawn_time = server.getTimeMillisec()
            vehicle.loaded = true
            break
        end
    end
end

function onVehicleDespawn(vehicle_id, peer_id)
    local owner_sid = getVehicleOwnerSteamID(vehicle_id)
    if owner_sid ~= -1 then
        local vehicles = g_savedata.user_vehicles[owner_sid]
        for idx, vehicle in ipairs(vehicles) do
            if vehicle.vehicle_id == vehicle_id then
                table.remove(vehicles, idx)
                return
            end
        end
    end
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, ...)
    local args = {...}
    if command == "?antilag" then
        handleAntilagCommand(full_message, user_peer_id, is_admin, is_auth, command, args)
    end
end

function onTick(game_ticks)
    calculateTPS()
    local current_time = server.getTimeMillisec()

    if tps < g_savedata.antilag.tps_threshold then
        spawning_enabled = false
        if server.getGameSettings().vehicle_spawning == true then
            server.setGameSetting("vehicle_spawning", false)
        end
    else
        spawning_enabled = true
        if server.getGameSettings().vehicle_spawning == false then
            server.setGameSetting("vehicle_spawning", true)
        end
    end

    -- a possible issue here is that the list isn't sorted by vehicle ID.. so a 
    -- vehicle that was spawned before the laggy one, may get despawned before the
    -- actual problem vehicle.
    for steam_id, vehicles in pairs(g_savedata.user_vehicles) do
        for idx, vehicle in ipairs(vehicles) do
            -- check for excessive vehicle load times
            if not vehicle.loaded then
                -- this may cause an issue for smaller vehicles spawned while the server is lagging.
                -- Vehicle mass or voxel count should like play a role in this
                if current_time - vehicle.spawn_time > g_savedata.antilag.load_time_threshold then
                    server.despawnVehicle(vehicle.vehicle_id, true)
                    local msg = string.format("Your vehicle was despawned for exceeding the maxmimum load time of %.1f seconds.", g_savedata.antilag.load_time_threshold / 1000)
                    server.notify(peer_ids[steam_id], antilag_notify, msg, 6)
                end
            elseif not vehicle.cleared and (current_time - vehicle.spawn_time > g_savedata.antilag.tps_recover_time) then
                local avg = Mean(tps_buff.values)
                local avg_ok = TPSAverageOK(vehicle.spawn_avg_tps, avg)
                local tps_ok = TPSInstantOK(vehicle.spawn_tps)
                -- if avg tps not recovered, but instant has then give the vehicle another timeout period to stabilise
                if not avg_ok and tps_ok and vehicle.stablize_count < g_savedata.antilag.vehicle_stabilize_chances then
                    vehicle.spawn_time=server.getTimeMillisec()
                    vehicle.stablize_count = vehicle.stablize_count + 1
                elseif not avg_ok and not tps_ok then
                    local msg = string.format("Vehicle %d was despawned. Server FPS did not stabilize in time (%0.2f to %0.2f)", vehicle.vehicle_id, vehicle.spawn_tps, tps)
                    server.notify(peer_ids[steam_id], antilag_notify, msg, 6)
                    notifyAdmins(vehicle)
                    server.despawnVehicle(vehicle.vehicle_id, true)
                elseif not avg_ok and tps_ok then
                    local msg = string.format("Vehicle %d was despawned. Average FPS did not recover in time (%0.2f to %0.2f)", vehicle.vehicle_id, vehicle.spawn_avg_tps, avg)
                    server.notify(peer_ids[steam_id], antilag_notify, msg, 6)
                    notifyAdmins(vehicle)
                    server.despawnVehicle(vehicle.vehicle_id, true)
                elseif avg_ok and tps_ok then
                    vehicle.cleared = true
                end
            end
        end
    end

    vpop_delay = vpop_delay + 1
    if vpop_delay > 60 then
        vpop_delay = 0
        local players = server.getPlayers()
        for idx, player in ipairs(players) do
            local sid = tostring(player.steam_id)
            local max = g_savedata.vehicle_limits[sid]
            if max == nil then
                max = g_savedata.antilag.base_vehicle_limit
            end
            local vehicles = g_savedata.user_vehicles[sid]
            if vehicles == nil then
                vehicles = {}
            end
            if g_savedata.antilag.disable_vehicle_limit == true then
                server.setPopupScreen(player.id, vehicle_uiid, "Vehicles", true, string.format("Vehicles: %d", #vehicles, max), 0.4, 0.88)
            else
                server.setPopupScreen(player.id, vehicle_uiid, "Vehicles", true, string.format("Vehicles: %d/%d", #vehicles, max), 0.4, 0.88)
            end
        end
    end

    if g_savedata.antilag.remove_objects == true then despawnObjects() end
end

function despawnObjects()
    local running = true
    local oid = g_savedata.lastOID + 1
    while running do
        local _, ok = server.getObjectPos(oid)
        if ok then
            server.despawnObject(oid, true)
            oid = oid + 1
        else
            running = false
            if g_savedata.lastOID + 1 < oid then
                g_savedata.lastOID = oid - 1
            end
        end
    end
end

function notifyAdmins(vehicle)
    local players = server.getPlayers()
    for _, player in pairs(players) do
        if player.admin == true then
            local n = server.getPlayerName(vehicle.peer_id)
            server.announce(antilag_chat, string.format("Vehicle %d owned by %s (%d) has been despawned by Antilag", vehicle.vehicle_id, n, vehicle.peer_id), player.id)
        end
    end
end

function TPSInstantOK(spawn_tps)
    if spawn_tps - tps > g_savedata.antilag.tps_threshold then
        return false
    end 
    return true
end

function TPSAverageOK(spawn_avg, avg)
    if spawn_avg - avg > g_savedata.antilag.tps_avg_diff_threshold then
        return false
    end
    return true
end

-- COMMAND LOGIC --
function handleAntilagCommand(full_message, user_peer_id, is_admin, is_auth, command, args)
    local h = "[ANTI-LAG CONFIG]"
    if command == "?antilag" and is_admin then
        if args[1] == "config" then
            if args[3] ~= nil then
                local key = args[2]
                local val = args[3]
                local cval = g_savedata.antilag[key]
                if cval == nil then
                    server.announce(h, string.format("Invalid config key: %s", key), user_peer_id)
                    return
                end
                if type(cval) == "boolean" then
                    if string.match(val, "^[yYtT]") then
                        val = true
                    elseif string.match(val, "^[nNfF]") then
                        val = false
                    else
                        server.announce(h, string.format("Invalid value \"%s\": must be true or false", val), user_peer_id)
                        return
                    end
                elseif type(cval) == "number" then
                    local n = tonumber(val)
                    if n == nil then
                        server.announce(h, string.format("Invalid value \"%s\": must be a number", val), user_peer_id)
                        return
                    end
                    val = n
                -- anything else is a string or an unknown type, which should be treated as a string anyway.
                end
                g_savedata.antilag[key] = val
                server.announce(h, string.format("%s: %s -> %s", key, tostring(cval), tostring(val)), user_peer_id)
                server.save()
                return
            end
            if #args == 1 and args[1] == "config" then
                for k, v in pairs(g_savedata.antilag) do
                    server.announce(h, k..": "..tostring(v), user_peer_id)
                end
            end
        end
    end
end

-- UTIL --
function calculateTPS()
    ticks = ticks + 1
    if server.getTimeMillisec() - ticks_time >= 500 then
        tps = ticks*2
        ticks = 0
        ticks_time = server.getTimeMillisec()
        tps_buff.Push(tps)
        for _, p in pairs(server.getPlayers()) do
            server.setPopupScreen(p.id, tps_uiid, "FPS", true, "FPS: ".. tps, 0.56, 0.88)
        end
    end
end

function NewBuffer(maxlen)
    local buffer = {}
    buffer.maxlen = maxlen
    buffer.values = {}

    function buffer.Push(item)
        table.insert(buffer.values, 1, item)
        buffer.values[buffer.maxlen + 1] = nil
    end

    function buffer.PrintAll()
        data = ""
        for i, v in pairs(buffer.values) do
            data = data .. v
            if i < #buffer.values then data = data .. "," end
        end

        print(data)
    end
    return buffer
end

function Mean(T)
    local sum = 0
    local count = 0
    if T == nil then return 0 end
    for k, v in pairs(T) do
        if type(v) == 'number' then
            sum = sum + v
            count = count + 1
        end
    end
    return (sum / count)
end

function isAdmin(peer_id)
    local players = server.getPlayers()
    for _, player in pairs(players) do
        if player.id == peer_id then
            return player.admin
        end
    end
    return false
end

function getVehicleOwnerSteamID(vehicle_id)
    for owner_sid, vehicles in pairs(g_savedata.user_vehicles) do
        for idx, record in ipairs(vehicles) do
            if record.vehicle_id == vehicle_id then
                return owner_sid
            end
        end
    end
    return -1
end

function logError(message)
    for idx, p in pairs(server.getPlayers()) do
		if p.admin == true then
			server.announce("[Error]", message, p.id)
		end
	end
    debug.log(message)
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

-- Source: https://gist.github.com/tylerneylon/59f4bcf316be525b30ab
json = {}

-- Internal functions.
local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then
      error('Expected ' .. delim .. ' near position ' .. pos)
    end
    return pos, false
  end
  return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'End of input found while parsing string.'
  if pos > #str then error(early_end_error) end
  local c = str:sub(pos, pos)
  if c == '"'  then return val, pos + 1 end
  if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
  -- We must have a \ character.
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then error(early_end_error) end
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then error('Error parsing number at position ' .. pos .. '.') end
  return val, pos + #num_str
end


-- Public values and functions.

function json.stringify(obj, as_key)
  local s = {}  -- We'll build the string as an array of strings to be concatenated.
  local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
  if kind == 'array' then
    if as_key then error('Can\'t encode array as key.') end
    s[#s + 1] = '['
    for i, val in ipairs(obj) do
      if i > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(val)
    end
    s[#s + 1] = ']'
  elseif kind == 'table' then
    if as_key then error('Can\'t encode table as key.') end
    s[#s + 1] = '{'
    for k, v in pairs(obj) do
      if #s > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(k, true)
      s[#s + 1] = ':'
      s[#s + 1] = json.stringify(v)
    end
    s[#s + 1] = '}'
  elseif kind == 'string' then
    return '"' .. escape_str(obj) .. '"'
  elseif kind == 'number' then
    if as_key then return '"' .. tostring(obj) .. '"' end
    return tostring(obj)
  elseif kind == 'boolean' then
    return tostring(obj)
  elseif kind == 'nil' then
    return 'null'
  else
    error('Unjsonifiable type: ' .. kind .. '.')
  end
  return table.concat(s)
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
  pos = pos or 1
  if pos > #str then return nil end
  local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
  local first = str:sub(pos, pos)
  if first == '{' then  -- Parse an object.
    local obj, key, delim_found = {}, true, true
    pos = pos + 1
    while true do
      key, pos = json.parse(str, pos, '}')
      if key == nil then return obj, pos end
      if not delim_found then return nil end
      pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
      obj[key], pos = json.parse(str, pos)
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '[' then  -- Parse an array.
    local arr, val, delim_found = {}, true, true
    pos = pos + 1
    while true do
      val, pos = json.parse(str, pos, ']')
      if val == nil then return arr, pos end
      if not delim_found then return nil end
      arr[#arr + 1] = val
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '"' then  -- Parse a string.
    return parse_str_val(str, pos + 1)
  elseif first == '-' or first:match('%d') then  -- Parse a number.
    return parse_num_val(str, pos)
  elseif first == end_delim then  -- End of an object or array.
    return nil, pos + 1
  else  -- Parse true, false, or null.
    local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
    for lit_str, lit_val in pairs(literals) do
      local lit_end = pos + #lit_str - 1
      if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
    end
    local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
    return nil
  end
end

function tableLength(T)
  if T == nil then
    return 0
  end
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function encode(str)
  function cth(c)
	  return string.format("%%%02X", string.byte(c))
  end
	if str == nil then
		return ""
	end
	str = string.gsub(str, "([^%w _ %- . ~])", cth)
	str = str:gsub(" ", "%%20")
	return str
end
