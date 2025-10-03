-- client/main.lua (v2)
local uiOpen = false

-- Open UI command
RegisterCommand('outlawjob', function()
  if uiOpen then return end
  uiOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open' })
  -- ask initial jobs
  TriggerServerEvent('outlawjob:requestJobs')
end, false)

-- Optional key mapping (commented)
-- RegisterKeyMapping('outlawjob', 'Open Outlaw Job Creator', 'keyboard', 'F7')

-- NUI Callbacks
RegisterNUICallback('close', function(_, cb)
  uiOpen = false
  SetNuiFocus(false, false)
  cb({ ok = true })
end)

-- NUI wants current coords
RegisterNUICallback('getCoords', function(_, cb)
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  cb({ x = pos.x + 0.0, y = pos.y + 0.0, z = pos.z + 0.0, heading = heading + 0.0 })
end)

-- NUI asks to refresh jobs (server will send event)
RegisterNUICallback('requestJobs', function(_, cb)
  TriggerServerEvent('outlawjob:requestJobs')
  cb({ ok = true })
end)

-- NUI create job
RegisterNUICallback('createJob', function(data, cb)
  TriggerServerEvent('outlawjob:createJob', data or {})
  cb({ ok = true })
end)

-- NUI create point
RegisterNUICallback('createPoint', function(data, cb)
  TriggerServerEvent('outlawjob:createPoint', data or {})
  cb({ ok = true })
end)

-- Server pushes jobs list
RegisterNetEvent('outlawjob:client:receiveJobs', function(rows)
  SendNUIMessage({ action = 'jobsList', jobs = rows or {} })
end)

-- Server asks to refresh again
RegisterNetEvent('outlawjob:client:requestJobsRefresh', function()
  TriggerServerEvent('outlawjob:requestJobs')
end)

-- Basic notify wrapper (replace with your own)
RegisterNetEvent('outlawjob:client:showNotify', function(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end)
