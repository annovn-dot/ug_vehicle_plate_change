local inZone = false

local function dprint(...)
    if Config and Config.Debug then
        print('[PlateChanger][CLIENT]', ...)
    end
end

local function sanitizePlate(str)
    str = tostring(str or "")
    str = string.upper(str)
    str = string.gsub(str, "%s+", "")
    str = string.gsub(str, "[^%w]", "")
    return string.sub(str, 1, 8)
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

CreateThread(function()
    if not (Config.Zone and Config.Zone.enabled) then
        dprint('Zone disabled → command usable anywhere.')
        return
    end

    if not lib or not lib.zones then
        print('^1[PlateChanger] ox_lib zones not available (is ox_lib started?)^0')
        return
    end

    if Config.Zone.type == 'box' then
        lib.zones.box({
            coords   = Config.Zone.coords,
            size     = Config.Zone.size,
            rotation = Config.Zone.rotation or 0.0,
            debug    = Config.Debug or false,
            onEnter  = function() inZone = true end,
            onExit   = function() inZone = false end
        })
    else
        lib.zones.sphere({
            coords  = Config.Zone.coords,
            radius  = Config.Zone.radius,
            debug   = Config.Debug or false,
            onEnter = function() inZone = true end,
            onExit  = function() inZone = false end
        })
    end
end)

local function openDialogAndSubmit()
    if Config.Zone and Config.Zone.enabled and not inZone then
        lib.notify({ title = 'Plate', description = 'You are not in a valid area.', type = 'error' })
        return
    end

    local veh = getDriverVehicle()
    if not veh then
        lib.notify({ title = 'Plate', description = 'You must be driving a vehicle.', type = 'error' })
        return
    end

    local rawPlate = GetVehicleNumberPlateText(veh) or ''
    local oldPlate = sanitizePlate(rawPlate)
    dprint(('Current plate raw="%s" normalized="%s"'):format(rawPlate, oldPlate))

    local dialog = lib.inputDialog('Change Plate', {
        { type = 'input', label = 'New Plate (A–Z / 0–9, no spaces)', placeholder = 'e.g. MYCAR77', required = true, min = 1, max = 8 },
    })
    if not dialog then return end

    local typed = sanitizePlate(dialog[1])
    if typed == '' then
        lib.notify({ title = 'Plate', description = 'Invalid plate text.', type = 'error' })
        return
    end

    local newPlate = typed
    if newPlate == oldPlate then
        lib.notify({ title = 'Plate', description = 'New plate is the same as the current plate.', type = 'warning' })
        return
    end

    local vehNet = NetworkGetNetworkIdFromEntity(veh)
    TriggerEvent('ug:plate:attemptChange', vehNet, oldPlate, newPlate)
end

RegisterNetEvent('ug:plate:attemptChange', function(vehNet, oldPlate, desiredPlate)
    local ok, msg = lib.callback.await('ug:plate:precheck', false, vehNet, oldPlate, desiredPlate)
    if not ok then
        lib.notify({ description = msg or 'Cannot change plate.', type = 'error' })
        return
    end

    local label = ('Changing plate to %s...'):format((tostring(desiredPlate or '')):upper())
    local progressOk = lib.progressBar({
        duration = Config.ProgressDuration or 5000,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false },
    })

    if not progressOk then
        lib.notify({ description = 'Plate change canceled.', type = 'warning' })
        return
    end

    local ok2, err, finalPlate = lib.callback.await('ug:plate:change', false, vehNet, oldPlate, desiredPlate)
    if not ok2 then
        lib.notify({ description = err or 'Plate change failed.', type = 'error' })
        return
    end

    lib.notify({ description = ('Plate changed to %s'):format(finalPlate or desiredPlate), type = 'success' })

    Wait(250)

    if Config.UGKeysSystem then
        TriggerEvent('keys:received', finalPlate)
    end
end)

RegisterCommand(Config.Command or 'changeplate', openDialogAndSubmit, false)
