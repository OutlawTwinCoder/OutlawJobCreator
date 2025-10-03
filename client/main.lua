-- client/main.lua
local uiOpen = false

local function ensureHudFocus(state)
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(false)
end

local function openCreator()
  if uiOpen then
    return
  end

  uiOpen = true
  ensureHudFocus(true)
  SendNUIMessage({ action = 'open' })
end

local function closeCreator()
  if not uiOpen then
    return
  end

  uiOpen = false
  ensureHudFocus(false)
  SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.OpenCommand or 'outlawjob', function()
  TriggerServerEvent('outlawjob:server:requestState')
end, false)

if Config.KeyMapping and Config.KeyMapping.enabled then
  RegisterKeyMapping(Config.OpenCommand or 'outlawjob', 'Ouvrir Outlaw Job Creator', 'keyboard', Config.KeyMapping.defaultKey or 'F7')
end

RegisterNUICallback('creator:close', function(_, cb)
  closeCreator()
  cb({ ok = true })
end)

RegisterNUICallback('creator:refresh', function(_, cb)
  TriggerServerEvent('outlawjob:server:requestState')
  cb({ ok = true })
end)

RegisterNUICallback('creator:getCoords', function(_, cb)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  cb({
    ok = true,
    coords = {
      x = coords.x + 0.0,
      y = coords.y + 0.0,
      z = coords.z + 0.0,
      heading = heading + 0.0
    }
  })
end)

RegisterNUICallback('creator:createJob', function(data, cb)
  TriggerServerEvent('outlawjob:server:createJob', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('creator:updateJob', function(data, cb)
  TriggerServerEvent('outlawjob:server:updateJob', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('creator:deleteJob', function(data, cb)
  TriggerServerEvent('outlawjob:server:deleteJob', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('creator:requestPoints', function(data, cb)
  local jobId = data and data.job_id
  if jobId then
    TriggerServerEvent('outlawjob:server:requestPoints', jobId)
  end
  cb({ ok = true })
end)

RegisterNUICallback('creator:createPoint', function(data, cb)
  TriggerServerEvent('outlawjob:server:createPoint', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('creator:updatePoint', function(data, cb)
  TriggerServerEvent('outlawjob:server:updatePoint', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('creator:deletePoint', function(data, cb)
  TriggerServerEvent('outlawjob:server:deletePoint', data or {})
  cb({ ok = true })
end)

RegisterNetEvent('outlawjob:client:setState', function(payload)
  if not uiOpen then
    openCreator()
  end
  SendNUIMessage({ action = 'state', payload = payload or {} })
end)

RegisterNetEvent('outlawjob:client:setPoints', function(payload)
  payload = payload or {}
  if not payload.jobId then
    return
  end
  SendNUIMessage({ action = 'points', payload = payload })
end)

RegisterNetEvent('outlawjob:client:notify', function(data)
  data = data or {}
  local msg = data.message or 'Notification'
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, false)
  SendNUIMessage({ action = 'notify', payload = data })
end)

RegisterNUICallback('creator:focusGame', function(_, cb)
  ensureHudFocus(false)
  cb({ ok = true })
end)

RegisterNUICallback('creator:returnFocus', function(_, cb)
  ensureHudFocus(true)
  cb({ ok = true })
end)
