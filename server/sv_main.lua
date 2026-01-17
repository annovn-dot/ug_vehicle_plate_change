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

local function isPlayerInZone(src)
    if not (Config.Zone and Config.Zone.enabled) then return true end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local p = GetEntityCoords(ped)
    local c = Config.Zone.coords

    if Config.Zone.type == 'sphere' then
        local r = tonumber(Config.Zone.radius) or 0.0
        return #(p - c) <= r
    end

    local size = Config.Zone.size or vec3(0, 0, 0)
    local rot = math.rad(tonumber(Config.Zone.rotation) or 0.0)

    local rel = p - c
    local cosr = math.cos(-rot)
    local sinr = math.sin(-rot)

    local x = rel.x * cosr - rel.y * sinr
    local y = rel.x * sinr + rel.y * cosr
    local z = rel.z

    local hx = (size.x or 0.0) / 2.0
    local hy = (size.y or 0.0) / 2.0
    local hz = (size.z or 0.0) / 2.0

    return (math.abs(x) <= hx) and (math.abs(y) <= hy) and (math.abs(z) <= hz)
end

local function _dc()
    return (Config and Config.DiscordLogs) or nil
end

local function _dcEnabled()
    local dc = _dc()
    if type(dc) ~= 'table' then return false end
    if dc.Enabled ~= true then return false end
    if type(dc.Webhook) ~= 'string' then return false end

    local wh = dc.Webhook:gsub('%s+', '')
    if wh == '' then return false end

    return true
end

local function _shouldLog(kind)
    local dc = _dc()
    if not _dcEnabled() then return false end

    if kind == 'denied' then
        return dc.LogDenied ~= false
    elseif kind == 'precheck_denied' then
        return dc.LogPrecheckDenied == true
    end
    return true
end

local function _fmtCoords(vec)
    if not vec then return 'N/A' end
    return ('%.2f, %.2f, %.2f'):format(vec.x or 0.0, vec.y or 0.0, vec.z or 0.0)
end

local function _getIdMap(src)
    local out = {}
    for _, v in ipairs(GetPlayerIdentifiers(src)) do
        local k, val = v:match('^(.-):(.*)$')
        if k and val then out[k] = v end
    end
    return out
end

local function _discordMentionFromIds(idMap)
    local d = idMap and idMap.discord
    if not d then return nil end
    local did = d:match('discord:(%d+)')
    if not did then return nil end
    return ('<@%s>'):format(did)
end

local function _sendDiscord(embed)
    if not _dcEnabled() then
        if Config and Config.Debug then
            local dc = _dc()
            local wh = (type(dc) == 'table' and dc.Webhook) or nil
            local whPreview = (type(wh) == 'string' and wh:sub(1, 30) .. '...') or 'nil'
            print(('[PlateChanger][Discord] NOT SENDING (disabled/missing). Enabled=%s webhook=%s type=%s'):format(
                tostring(type(dc) == 'table' and dc.Enabled),
                whPreview,
                type(dc)
            ))
        end
        return
    end

    local dc = _dc()
    local payload = {
        username = dc.Username or 'PlateChanger',
        avatar_url = (type(dc.Avatar) == 'string' and dc.Avatar ~= '' and dc.Avatar) or nil,
        embeds = { embed }
    }

    local webhook = dc.Webhook:gsub('%s+', '')

    PerformHttpRequest(webhook, function(code, body, headers)
        if Config and Config.Debug then
            print(('[PlateChanger][Discord] HTTP %s %s'):format(tostring(code), body and tostring(body) or ''))
        end

        if code ~= 204 and code ~= 200 then
            print(('[PlateChanger][Discord] WARNING: non-success status %s (wrong webhook? permissions? rate limit?).')
                :format(tostring(code)))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function safeLog(kind, src, vehNet, data)
    if not _shouldLog(kind) then
        if Config and Config.Debug then
            print(('[PlateChanger][Discord] skip kind=%s (disabled or filtered)'):format(tostring(kind)))
        end
        return
    end

    local ok, err = pcall(function()
        _logDiscord(kind, src, vehNet, data)
    end)

    if not ok then
        print('^1[PlateChanger] Discord log failed:^0', err)
    end
end

function _logDiscord(kind, src, vehNet, data)
    if not _shouldLog(kind) then
        if Config and Config.Debug then
            print(('[PlateChanger][Discord] _logDiscord skipped kind=%s'):format(tostring(kind)))
        end
        return
    end

    local dc = _dc()
    data = data or {}

    local name = GetPlayerName(src) or 'Unknown'
    local idMap = _getIdMap(src)
    local mention = _discordMentionFromIds(idMap)

    local bridgeIdent = (Bridge and Bridge.getIdentifier and Bridge.getIdentifier(src)) or 'N/A'

    local ped = GetPlayerPed(src)
    local pcoords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil

    local veh, modelHash, modelName, plateNow, vcoords
    if type(vehNet) == 'number' then
        veh = NetworkGetEntityFromNetworkId(vehNet)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            modelHash = GetEntityModel(veh)

            if type(GetDisplayNameFromVehicleModel) == 'function' then
                modelName = GetDisplayNameFromVehicleModel(modelHash)
            else
                modelName = tostring(modelHash)
            end

            plateNow = GetVehicleNumberPlateText(veh)
            vcoords = GetEntityCoords(veh)
        end
    end

    local color = (dc.Colors and dc.Colors.Info) or 3447003
    local title = 'ℹ️ PlateChanger'

    if kind == 'success' then
        title = '✅ Plate changed'
        color = (dc.Colors and dc.Colors.Success) or 3066993
    elseif kind == 'denied' then
        title = '❌ Plate change denied'
        color = (dc.Colors and dc.Colors.Denied) or 15158332
    elseif kind == 'error' then
        title = '💥 Plate change ERROR'
        color = (dc.Colors and dc.Colors.Error) or 15105570
    elseif kind == 'precheck_denied' then
        title = '⛔ Precheck denied'
        color = (dc.Colors and dc.Colors.Denied) or 15158332
    end

    local fields = {
        { name = 'Player',                 value = ('%s (id: %d)'):format(name, src),                                                     inline = true },
        { name = 'Discord',                value = mention or 'N/A',                                                                      inline = true },
        { name = 'Identifier',             value = tostring(bridgeIdent),                                                                 inline = false },

        { name = 'Player Coords',          value = _fmtCoords(pcoords),                                                                   inline = false },

        { name = 'Vehicle NetID',          value = tostring(vehNet),                                                                      inline = true },
        { name = 'Model',                  value = modelName and (('%s (%s)'):format(modelName, tostring(modelHash))) or 'N/A',           inline = true },
        { name = 'Current Plate (entity)', value = plateNow or 'N/A',                                                                     inline = true },
        { name = 'Vehicle Coords',         value = _fmtCoords(vcoords),                                                                   inline = false },

        { name = 'Old Plate (input)',      value = tostring(data.oldPlate or ''),                                                         inline = true },
        { name = 'Desired Plate (input)',  value = tostring(data.desiredPlate or ''),                                                     inline = true },
        { name = 'Normalized (old->new)',  value = ('%s -> %s'):format(tostring(data.oldNorm or 'N/A'), tostring(data.newNorm or 'N/A')), inline = false },

        { name = 'OwnershipRequirement',   value = tostring(Config and Config.OwnershipRequirement),                                      inline = true },
        {
            name = 'Charge',
            value = (Config and Config.EnableCharge)
                and
                (('enabled (%s %s) | charged=%s'):format(tostring(Config.ChargeWay), tostring(Config.ChargeAmount), tostring(data.charged == true)))
                or 'disabled',
            inline = true
        },

        { name = 'Reason', value = tostring(data.reason or (kind == 'success' and 'OK' or 'N/A')), inline = false },
    }

    local extras = {}
    if idMap.license then extras[#extras + 1] = idMap.license end
    if idMap.steam then extras[#extras + 1] = idMap.steam end
    if idMap.fivem then extras[#extras + 1] = idMap.fivem end
    if idMap.xbl then extras[#extras + 1] = idMap.xbl end
    if idMap.live then extras[#extras + 1] = idMap.live end
    if idMap.discord then extras[#extras + 1] = idMap.discord end
    if #extras > 0 then
        fields[#fields + 1] = { name = 'Identifiers', value = table.concat(extras, '\n'), inline = false }
    end

    _sendDiscord({
        title = title,
        color = color,
        footer = { text = 'UG PlateChanger' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        fields = fields
    })
end

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
    if not isPlayerInZone(source) then
        logData.reason = 'Not in valid area.'
        safeLog('denied', source, vehNet, logData)
        return false, 'You are not in a valid area.'
    end
    local logData = {
        oldPlate = oldPlate,
        desiredPlate = desiredPlate,
        oldNorm = normalizePlate(oldPlate),
        newNorm = normalizePlate(desiredPlate),
        charged = false
    }

    if not (Bridge and type(Bridge.hasJobWithGrade) == 'function') then
        logData.reason = 'Server bridge not initialized (hasJobWithGrade missing).'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    local okJob, jReason = Bridge.hasJobWithGrade(source)
    if not okJob then
        logData.reason = jReason or 'Not allowed.'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    if logData.newNorm == '' then
        logData.reason = 'Invalid plate.'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    if logData.newNorm == logData.oldNorm then
        logData.reason = 'New plate must be different from the current plate.'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    local okVeh, vehOrMsg = validateEntityIsPlayersVehicle(source, vehNet)
    if not okVeh then
        logData.reason = vehOrMsg
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end
    local veh = vehOrMsg

    if plateExists(logData.newNorm) then
        logData.reason = 'That plate is already taken.'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    if Config.EnableCharge then
        local paid = Bridge.chargePlayer(source, tonumber(Config.ChargeAmount) or 0, Config.ChargeWay)
        if not paid then
            local where = (Config.ChargeWay == 'cash') and 'cash' or 'bank'
            logData.reason = ('You don\'t have enough %s to pay %d.'):format(where, Config.ChargeAmount or 0)
            safeLog('denied', source, vehNet, logData)
            return false, logData.reason
        end
        logData.charged = true
    end

    local okDB = false
    if Config.OwnershipRequirement then
        local ident = Bridge.getIdentifier(source)
        if not ident then
            if logData.charged then Bridge.refundPlayer(source, Config.ChargeAmount or 0, Config.ChargeWay) end
            logData.reason = 'Could not resolve your identifier.'
            safeLog('denied', source, vehNet, logData)
            return false, logData.reason
        end

        if not ownsPlate(ident, logData.oldNorm) then
            if logData.charged then Bridge.refundPlayer(source, Config.ChargeAmount or 0, Config.ChargeWay) end
            logData.reason = 'You do not own this vehicle.'
            safeLog('denied', source, vehNet, logData)
            return false, logData.reason
        end

        okDB = updatePlateOwner(ident, logData.oldNorm, logData.newNorm)
    else
        okDB = updatePlateAny(logData.oldNorm, logData.newNorm)
    end

    if not okDB then
        if logData.charged then Bridge.refundPlayer(source, Config.ChargeAmount or 0, Config.ChargeWay) end
        logData.reason = 'Database update failed.'
        safeLog('denied', source, vehNet, logData)
        return false, logData.reason
    end

    SetVehicleNumberPlateText(veh, logData.newNorm)

    dprint(('[OK] Plate changed%s: %s -> %s'):format(
        Config.OwnershipRequirement and ' (owner-validated)' or ' (job-only)',
        logData.oldNorm, logData.newNorm
    ))

    safeLog('success', source, vehNet, logData)
    return true, nil, logData.newNorm
end

lib.callback.register('ug:plate:precheck', function(source, vehNet, oldPlate, desiredPlate)
    if not isPlayerInZone(source) then
        return false, 'You are not in a valid area.'
    end
    local function deny(msg)
        safeLog('precheck_denied', source, vehNet, {
            oldPlate = oldPlate,
            desiredPlate = desiredPlate,
            oldNorm = normalizePlate(oldPlate),
            newNorm = normalizePlate(desiredPlate),
            charged = false,
            reason = msg
        })
        return false, msg
    end

    if not (Bridge and type(Bridge.hasJobWithGrade) == 'function') then
        return deny('Server bridge not initialized.')
    end

    local okJob, jReason = Bridge.hasJobWithGrade(source)
    if not okJob then
        return deny(jReason or 'Not allowed.')
    end

    local oldNorm     = normalizePlate(oldPlate)
    local desiredNorm = normalizePlate(desiredPlate)

    if desiredNorm == '' then
        return deny('Invalid plate.')
    end
    if desiredNorm == oldNorm then
        return deny('New plate must be different from the current plate.')
    end

    local okVeh, vehOrMsg = validateEntityIsPlayersVehicle(source, vehNet)
    if not okVeh then
        return deny(vehOrMsg)
    end

    if plateExists(desiredNorm) then
        return deny('That plate is already taken.')
    end

    if Config.OwnershipRequirement then
        local ident = Bridge.getIdentifier(source)
        if not ident then
            return deny('Could not resolve your identifier.')
        end
        if not ownsPlate(ident, oldNorm) then
            return deny('You do not own this vehicle.')
        end
    end

    if Config.EnableCharge then
        local enough = Bridge.hasEnoughMoney(source, tonumber(Config.ChargeAmount) or 0, Config.ChargeWay)
        if not enough then
            local where = (Config.ChargeWay == 'cash') and 'cash' or 'bank'
            return deny(('You don\'t have enough %s to pay %d.'):format(where, Config.ChargeAmount or 0))
        end
    end

    return true
end)

lib.callback.register('ug:plate:change', function(source, vehNet, oldPlate, desiredPlate)
    local ok, r1, r2, r3 = pcall(handlePlateChange, source, vehNet, oldPlate, desiredPlate)
    if not ok then
        print('[PlateChanger][SERVER] ERROR:', r1)

        safeLog('error', source, vehNet, {
            oldPlate = oldPlate,
            desiredPlate = desiredPlate,
            oldNorm = normalizePlate(oldPlate),
            newNorm = normalizePlate(desiredPlate),
            charged = false,
            reason = ('Server error: %s'):format(r1)
        })

        return false, ('Server error: %s'):format(r1)
    end

    return r1, r2, r3
end)
