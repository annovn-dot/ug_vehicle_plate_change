local function dprint(...)
    if Config and Config.Debug then
        print('[PlateChanger][SERVER]', ...)
    end
end

CreateThread(function()
    if not Bridge or type(Bridge.hasJobWithGrade) ~= 'function' then
        print('^1[PlateChanger] Bridge missing! Ensure server/sv_bridge.lua is loaded BEFORE sv_main.lua.^0')
    end
end)

local function normalizePlate(s)
    s = tostring(s or '')
    s = s:upper()
    s = s:gsub('%s+', '')
    s = s:gsub('[^%w]', '')
    return s:sub(1, 8)
end

local function plateExists(desired)
    local p = normalizePlate(desired)
    local sql = ('SELECT 1 FROM `%s` WHERE REPLACE(`%s`, \' \', \'\') = ? LIMIT 1')
        :format(Config.DB.table, Config.DB.plateCol)
    local row = MySQL.scalar.await(sql, { p })
    return row ~= nil
end

local function ownsPlate(identifier, oldPlate)
    local p = normalizePlate(oldPlate)
    local sql = ('SELECT `%s` FROM `%s` WHERE `%s` = ? AND REPLACE(`%s`, \' \', \'\') = ? LIMIT 1')
        :format(Config.DB.vehicleCol, Config.DB.table, Config.DB.ownerCol, Config.DB.plateCol)
    local row = MySQL.single.await(sql, { identifier, p })
    return row ~= nil
end

local function updatePlateOwner(identifier, oldPlate, newPlate)
    local oldP = normalizePlate(oldPlate)
    local newP = normalizePlate(newPlate)

    local sql = ([[UPDATE `%s`
        SET `%s` = ?, `%s` = JSON_SET(COALESCE(%s, '{}'), '%s', ?)
        WHERE `%s` = ? AND REPLACE(`%s`, ' ', '') = ? LIMIT 1]])
        :format(
            Config.DB.table,
            Config.DB.plateCol,
            Config.DB.vehicleCol, Config.DB.vehicleCol, Config.DB.jsonPlatePath or '$.plate',
            Config.DB.ownerCol, Config.DB.plateCol
        )

    local affected = MySQL.update.await(sql, { newP, newP, identifier, oldP })
    return (affected or 0) > 0
end

local function updatePlateAny(oldPlate, newPlate)
    local oldP = normalizePlate(oldPlate)
    local newP = normalizePlate(newPlate)

    local sql = ([[UPDATE `%s`
        SET `%s` = ?, `%s` = JSON_SET(COALESCE(%s, '{}'), '%s', ?)
        WHERE REPLACE(`%s`, ' ', '') = ? LIMIT 1]])
        :format(
            Config.DB.table,
            Config.DB.plateCol,
            Config.DB.vehicleCol, Config.DB.vehicleCol, Config.DB.jsonPlatePath or '$.plate',
            Config.DB.plateCol
        )

    local affected = MySQL.update.await(sql, { newP, newP, oldP })
    return (affected or 0) > 0
end

local function validateEntityIsPlayersVehicle(src, vehNet)
    if type(vehNet) ~= 'number' then return false, 'Invalid vehicle.' end
    local veh = NetworkGetEntityFromNetworkId(vehNet)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false, 'Vehicle not found.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player not found.' end
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        return false, 'You must be driving the vehicle.'
    end
    return true, veh
end

local function handlePlateChange(source, vehNet, oldPlate, desiredPlate)
    if not (Bridge and Bridge.hasJobWithGrade) then
        return false, 'Server bridge not initialized (hasJobWithGrade missing).'
    end
    local okJob, jReason = Bridge.hasJobWithGrade(source)
    if not okJob then
        return false, jReason or 'Not allowed.'
    end

    local oldNorm     = normalizePlate(oldPlate)
    local desiredNorm = normalizePlate(desiredPlate)
    if desiredNorm == '' then
        return false, 'Invalid plate.'
    end

    local okVeh, vehOrMsg = validateEntityIsPlayersVehicle(source, vehNet)
    if not okVeh then return false, vehOrMsg end
    local veh = vehOrMsg

    if plateExists(desiredNorm) then
        return false, 'That plate is already taken.'
    end

    local okDB = false
    if Config.OwnershipRequirement then
        local ident = Bridge.getIdentifier(source)
        if not ident then
            return false, 'Could not resolve your identifier.'
        end
        if not ownsPlate(ident, oldNorm) then
            return false, 'You do not own this vehicle.'
        end
        okDB = updatePlateOwner(ident, oldNorm, desiredNorm)
    else
        okDB = updatePlateAny(oldNorm, desiredNorm)
    end

    if not okDB then
        return false, 'Database update failed.'
    end

    SetVehicleNumberPlateText(veh, desiredNorm)
    dprint(('[OK] Plate changed%s: %s -> %s'):format(
        Config.OwnershipRequirement and ' (owner-validated)' or ' (job-only)',
        oldNorm, desiredNorm
    ))

    return true, nil, desiredNorm
end

lib.callback.register('ug:plate:change', function(source, vehNet, oldPlate, desiredPlate)
    local ok, r1, r2, r3 = pcall(handlePlateChange, source, vehNet, oldPlate, desiredPlate)
    if not ok then
        print('[PlateChanger][SERVER] ERROR:', r1)
        return false, ('Server error: %s'):format(r1)
    end
    return r1, r2, r3
end)
