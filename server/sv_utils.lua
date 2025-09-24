Bridge = {}

local ESX, QBCore

local function dprint(...)
    if Config and Config.Debug then
        print('[PlateChanger][BRIDGE]', ...)
    end
end

local function state(name) return GetResourceState(name) == 'started' end

CreateThread(function()
    if state('qbx-core') or state('qbx_core') then
        local ok, obj = pcall(function()
            if exports['qbx-core'] then return exports['qbx-core']:GetCoreObject() end
        end)
        if ok and obj then QBCore = obj end
        if not QBCore then
            local ok2, obj2 = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok2 and obj2 then QBCore = obj2 end
        end
        Bridge.name = 'qbox'
    elseif state('qb-core') then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and obj then QBCore = obj end
        Bridge.name = 'qb'
    elseif state('es_extended') then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and obj then ESX = obj end
        Bridge.name = 'esx'
    else
        Bridge.name = 'none'
    end

    dprint('Detected framework =', Bridge.name)
end)

local function getQBPlayer(src)
    if not QBCore then return nil end
    local ply
    if QBCore.Functions and QBCore.Functions.GetPlayer then
        ply = QBCore.Functions.GetPlayer(src)
    end
    if not ply and QBCore.Players then
        ply = QBCore.Players[src]
    end
    return ply
end

local function toLower(s)
    if type(s) ~= 'string' then return nil end
    return s:lower()
end

function Bridge.getIdentifier(src)
    if not src then return nil end

    if Bridge.name == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if xPlayer then
            return xPlayer.identifier
                or (xPlayer.getIdentifier and xPlayer.getIdentifier())
                or nil
        end
        for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
            if id:sub(1, 8) == 'license:' then return id end
        end
        return nil
    elseif Bridge.name == 'qb' or Bridge.name == 'qbox' then
        local Ply = getQBPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid then
            return Ply.PlayerData.citizenid
        end
        if Ply and Ply.identifier then return Ply.identifier end
        if Ply and Ply.license then return Ply.license end
        return nil
    end

    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

function Bridge.getJob(src)
    if not src then return nil end

    if Bridge.name == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local job = (xPlayer.getJob and xPlayer.getJob()) or xPlayer.job
        local name = job and job.name or nil
        local grade = 0
        if job then
            if type(job.grade) == 'number' then
                grade = job.grade
            elseif type(job.grade) == 'table' then
                grade = tonumber(job.grade.grade or job.grade.level or 0) or 0
            end
        end
        name = toLower(name)
        dprint('ESX job=', name, 'grade=', grade)
        return { name = name, grade = grade }
    elseif Bridge.name == 'qb' or Bridge.name == 'qbox' then
        local Ply = getQBPlayer(src)
        if not Ply then
            dprint('QB/QBOX: player not found'); return nil
        end

        local job = (Ply.PlayerData and Ply.PlayerData.job) or Ply.job
        if not job then
            dprint('QB/QBOX: job missing on player'); return nil
        end

        local name = job.name or job.id or job.type or job.label
        local gradeNum = 0
        if type(job.grade) == 'table' then
            gradeNum = tonumber(job.grade.level or job.grade.grade or job.grade) or 0
        elseif job.grade_level then
            gradeNum = tonumber(job.grade_level) or 0
        elseif job.grade then
            gradeNum = tonumber(job.grade) or 0
        end

        name = toLower(name)
        dprint(('QB/QBOX job=%s grade=%s'):format(tostring(name), tostring(gradeNum)))
        return { name = name, grade = gradeNum }
    end

    dprint('No framework detected; getJob nil')
    return nil
end

function Bridge.hasJobWithGrade(src)
    local JR = Config and Config.JobRequirement
    if not (JR and JR.enabled) then return true end

    local jobs = JR.jobs or {}
    local normalized = {}
    for k, v in pairs(jobs) do
        if type(k) == 'string' then
            normalized[k:lower()] = tonumber(v) or 0
        end
    end

    local j = Bridge.getJob(src)
    if not j or not j.name then
        dprint('Job check failed: no job found for src', src)
        return false, 'No job found.'
    end

    local min = normalized[j.name]
    if min == nil then
        dprint(('Job %s not in allowed list'):format(j.name))
        return false, 'Your job is not allowed to change plates here.'
    end

    if (j.grade or 0) < min then
        dprint(('Job %s grade %s < required %s'):format(j.name, tostring(j.grade or 0), tostring(min)))
        return false, ('Requires %s grade ≥ %d.'):format(j.name, min)
    end

    return true
end

function Bridge.hasEnoughMoney(src, amount, account)
    if not src or not amount or amount <= 0 then return true end
    account = (account == 'cash') and 'cash' or 'bank'

    if Bridge.name == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        if account == 'cash' then
            return (xPlayer.getMoney() or 0) >= amount
        else
            local acc = xPlayer.getAccount('bank')
            return acc and (acc.money or 0) >= amount
        end
    elseif Bridge.name == 'qb' or Bridge.name == 'qbox' then
        local Ply = (QBCore and QBCore.Functions and QBCore.Functions.GetPlayer) and QBCore.Functions.GetPlayer(src)
        if not Ply then return false end
        if account == 'cash' then
            return (Ply.Functions.GetMoney and Ply.Functions.GetMoney('cash') or 0) >= amount
        else
            return (Ply.Functions.GetMoney and Ply.Functions.GetMoney('bank') or 0) >= amount
        end
    end

    return true
end

function Bridge.chargePlayer(src, amount, account)
    if not src or not amount or amount <= 0 then return false end
    account = (account == 'cash') and 'cash' or 'bank'

    if Bridge.name == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return false end

        if account == 'cash' then
            if (xPlayer.getMoney() or 0) >= amount then
                xPlayer.removeMoney(amount)
                return true
            end
        else
            local acc = xPlayer.getAccount('bank')
            if acc and (acc.money or 0) >= amount then
                xPlayer.removeAccountMoney('bank', amount)
                return true
            end
        end
        return false
    elseif Bridge.name == 'qb' or Bridge.name == 'qbox' then
        local Ply = (QBCore and QBCore.Functions and QBCore.Functions.GetPlayer) and QBCore.Functions.GetPlayer(src)
        if not Ply then return false end

        if account == 'cash' then
            if (Ply.Functions.GetMoney and Ply.Functions.GetMoney('cash') or 0) >= amount then
                Ply.Functions.RemoveMoney('cash', amount, 'plate-change')
                return true
            end
        else
            if (Ply.Functions.GetMoney and Ply.Functions.GetMoney('bank') or 0) >= amount then
                Ply.Functions.RemoveMoney('bank', amount, 'plate-change')
                return true
            end
        end
        return false
    end

    return true
end

function Bridge.refundPlayer(src, amount, account)
    if not src or not amount or amount <= 0 then return end
    account = (account == 'cash') and 'cash' or 'bank'

    if Bridge.name == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return end
        if account == 'cash' then
            xPlayer.addMoney(amount)
        else
            xPlayer.addAccountMoney('bank', amount)
        end
    elseif Bridge.name == 'qb' or Bridge.name == 'qbox' then
        local Ply = (QBCore and QBCore.Functions and QBCore.Functions.GetPlayer) and QBCore.Functions.GetPlayer(src)
        if not Ply then return end
        if account == 'cash' then
            Ply.Functions.AddMoney('cash', amount, 'plate-change-refund')
        else
            Ply.Functions.AddMoney('bank', amount, 'plate-change-refund')
        end
    end
end
