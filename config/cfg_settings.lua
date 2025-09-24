Config = {}

Config.Debug = false

Config.Zone = {
    enabled  = false,
    type     = 'box', -- 'box' or 'sphere'
    coords   = vec3(-562.0995, -172.9198, 38.0707),
    size     = vec3(10.0, 10.0, 5.0),
    rotation = 200.0,
    radius   = 3.0 -- only used if type = 'sphere'
}

Config.JobRequirement = {
    enabled = false,
    jobs = {
        doj = 0,
    }
}

-- true = owner must match
-- false = job-only can change any plate
Config.OwnershipRequirement = false
Config.Command = 'changeplate'
-- set to true if you want to trigger keys:received event after plate change
-- currently set up for our UG Keys system, but may work with others
Config.UGKeysSystem = false

Config.EnableCharge = true
Config.ChargeWay = "bank"       -- "bank" or "cash"
Config.ChargeAmount = 15000
Config.ProgressDuration = 30000 -- ms

--------------------------------------------------------------------------------------
--------------------------------- Database settings ----------------------------------
--------------------------------------------------------------------------------------

-- ESX
Config.DB = {
    table = 'owned_vehicles',
    ownerCol = 'owner',
    plateCol = 'plate',
    vehicleCol = 'vehicle',   -- JSON that may also store embedded plate
    jsonPlatePath = '$.plate' -- JSON path inside vehicleCol to mirror plate
}

-- QBCore / QBOX
--[[
Config.DB = {
  table = 'player_vehicles',
  ownerCol = 'citizenid',
  plateCol = 'plate',
  vehicleCol = 'mods',      -- change to your JSON column name
  jsonPlatePath = '$.plate' -- set to your nested plate path if you keep one
}
]]
