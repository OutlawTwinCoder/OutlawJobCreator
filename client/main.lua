-- client/main.lua
local uiOpen = false
local canManage = false
local previewState = {
  coords = nil,
  radius = 2.0,
  heading = 0.0,
  mode = 'point',
  blip = nil
}
local previewThreadActive = false
local pendingRequests = {}
local requestCounter = 0

local function simpleNotify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end

local function stopPreviewThread()
  previewState.coords = nil
  if previewState.blip then
    RemoveBlip(previewState.blip)
    previewState.blip = nil
  end
end

local function drawPreviewLoop()
  if previewThreadActive then return end
  previewThreadActive = true
  CreateThread(function()
    while previewState.coords do
      local coords = previewState.coords
      if coords then
        DrawMarker(28, coords.x, coords.y, coords.z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, previewState.heading, 0.5, 0.5, 0.5, 255, 200, 40, 200, false, true, 2, false, nil, nil, false)
        DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, previewState.radius, previewState.radius, 1.0, 40, 140, 255, 90, false, false, 2, false, nil, nil, false)
        if previewState.mode == 'zone' then
          DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, previewState.radius * 2.0, previewState.radius * 2.0, 1.0, 255, 90, 10, 60, false, false, 2, false, nil, nil, false)
        end
      end
      Wait(0)
    end
    previewThreadActive = false
  end)
end

local function setPreview(data)
  if not data then return end
  previewState.coords = vector3(data.x + 0.0, data.y + 0.0, data.z + 0.0)
  previewState.heading = data.heading or previewState.heading
  previewState.radius = data.radius or previewState.radius
  previewState.mode = data.mode or previewState.mode

  if previewState.blip then
    RemoveBlip(previewState.blip)
  end
  previewState.blip = AddBlipForCoord(previewState.coords.x, previewState.coords.y, previewState.coords.z)
  SetBlipSprite(previewState.blip, 280)
  SetBlipDisplay(previewState.blip, 6)
  SetBlipColour(previewState.blip, 5)
  SetBlipScale(previewState.blip, 0.9)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName('Prévisualisation')
  EndTextCommandSetBlipName(previewState.blip)

  drawPreviewLoop()
end

local function clearPreview()
  previewState.mode = 'point'
  previewState.radius = 2.0
  previewState.heading = 0.0
  stopPreviewThread()
end

local function captureCoords()
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local success, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)
  local coords = {
    x = pos.x + 0.0,
    y = pos.y + 0.0,
    z = pos.z + 0.0,
    heading = heading + 0.0,
    groundZ = success and groundZ or pos.z,
    altitude = pos.z + 0.0
  }
  setPreview({
    x = coords.x,
    y = coords.y,
    z = success and groundZ or coords.z,
    heading = coords.heading,
    radius = previewState.radius,
    mode = previewState.mode
  })
  SendNUIMessage({ action = 'coordsCaptured', coords = coords })
  return coords
end

local function ensureManagePermission(cb)
  if not canManage then
    if cb then cb(false) end
    return false
  end
  if cb then cb(true) end
  return true
end

local function pushPending(cb)
  requestCounter = requestCounter + 1
  pendingRequests[requestCounter] = cb
  return requestCounter
end

local function sendPermissionsToUi()
  SendNUIMessage({ action = 'permissions', canManage = canManage })
end

RegisterCommand('outlawjob', function()
  if uiOpen then return end
  uiOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open' })
  TriggerServerEvent('outlawjob:requestJobs')
  TriggerServerEvent('outlawjob:requestMigrations')
end, false)

RegisterNUICallback('close', function(_, cb)
  uiOpen = false
  SetNuiFocus(false, false)
  clearPreview()
  cb({ ok = true })
end)

RegisterNUICallback('requestJobs', function(_, cb)
  TriggerServerEvent('outlawjob:requestJobs')
  cb({ ok = true })
end)

RegisterNUICallback('createJob', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false, error = 'Permission refusée' })
    return
  end
  TriggerServerEvent('outlawjob:createJob', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('getCoords', function(_, cb)
  if not ensureManagePermission() then
    cb({ ok = false, error = 'Permission refusée' })
    return
  end
  local coords = captureCoords()
  cb({ ok = true, coords = coords })
end)

RegisterNUICallback('snapToGround', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false })
    return
  end
  if not data or not previewState.coords then
    cb({ ok = false })
    return
  end
  local success, groundZ = GetGroundZFor_3dCoord(previewState.coords.x, previewState.coords.y, previewState.coords.z + 2.0, false)
  if success then
    previewState.coords = vector3(previewState.coords.x, previewState.coords.y, groundZ)
    setPreview({
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = previewState.heading,
      radius = previewState.radius,
      mode = previewState.mode
    })
    local coords = {
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = previewState.heading
    }
    SendNUIMessage({ action = 'coordsSnapped', coords = coords })
    cb({ ok = true, coords = coords })
  else
    cb({ ok = false })
  end
end)

local function applyOffset(data)
  if not previewState.coords then return nil end
  local offset = data and data.offset or {}
  local offX = tonumber(offset.x) or 0.0
  local offY = tonumber(offset.y) or 0.0
  local offZ = tonumber(offset.z) or 0.0
  local heading = data.heading or previewState.heading
  local rad = math.rad(heading)
  local cosH = math.cos(rad)
  local sinH = math.sin(rad)
  local x = previewState.coords.x + (offX * cosH - offY * sinH)
  local y = previewState.coords.y + (offX * sinH + offY * cosH)
  local z = previewState.coords.z + offZ
  previewState.coords = vector3(x, y, z)
  previewState.heading = heading
  previewState.radius = data.radius or previewState.radius
  previewState.mode = data.mode or previewState.mode
  setPreview({
    x = x,
    y = y,
    z = z,
    heading = previewState.heading,
    radius = previewState.radius,
    mode = previewState.mode
  })
  local coords = { x = x, y = y, z = z, heading = previewState.heading }
  SendNUIMessage({ action = 'coordsAdjusted', coords = coords })
  return coords
end

RegisterNUICallback('applyOffset', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false, error = 'Permission refusée' })
    return
  end
  local coords = applyOffset(data)
  if coords then
    cb({ ok = true, coords = coords })
  else
    cb({ ok = false, error = 'Prévisualisation absente' })
  end
end)

RegisterNUICallback('updatePreviewCoords', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false })
    return
  end
  if not data then
    cb({ ok = false })
    return
  end
  local x = tonumber(data.x)
  local y = tonumber(data.y)
  local z = tonumber(data.z)
  local heading = tonumber(data.heading or data.h)
  local radius = tonumber(data.radius)
  if x and y and z then
    previewState.coords = vector3(x, y, z)
  end
  if heading then previewState.heading = heading end
  if radius then previewState.radius = radius end
  if data.mode then previewState.mode = data.mode end
  if previewState.coords then
    setPreview({
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = previewState.heading,
      radius = previewState.radius,
      mode = previewState.mode
    })
  end
  cb({ ok = true })
end)

RegisterNUICallback('rotatePreview', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false })
    return
  end
  local heading = tonumber(data and data.heading) or previewState.heading
  previewState.heading = heading
  if previewState.coords then
    setPreview({
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = heading,
      radius = previewState.radius,
      mode = previewState.mode
    })
    SendNUIMessage({ action = 'coordsAdjusted', coords = { x = previewState.coords.x, y = previewState.coords.y, z = previewState.coords.z, heading = heading } })
  end
  cb({ ok = true, heading = heading })
end)

RegisterNUICallback('setPreviewMode', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false })
    return
  end
  previewState.mode = data and data.mode or 'point'
  previewState.radius = tonumber(data and data.radius) or previewState.radius
  if previewState.coords then
    setPreview({
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = previewState.heading,
      radius = previewState.radius,
      mode = previewState.mode
    })
  end
  cb({ ok = true, mode = previewState.mode })
end)

RegisterNUICallback('clearPreview', function(_, cb)
  clearPreview()
  cb({ ok = true })
end)

RegisterNUICallback('teleportTo', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false, error = 'Permission refusée' })
    return
  end
  local coords = data and data.coords
  if not coords and previewState.coords then
    coords = {
      x = previewState.coords.x,
      y = previewState.coords.y,
      z = previewState.coords.z,
      heading = previewState.heading
    }
  end
  if not coords then
    cb({ ok = false, error = 'Aucune coordonnée' })
    return
  end
  local ped = PlayerPedId()
  SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
  if coords.heading then
    SetEntityHeading(ped, coords.heading + 0.0)
  end
  cb({ ok = true })
end)

RegisterNUICallback('savePoint', function(data, cb)
  if not ensureManagePermission() then
    cb({ ok = false, error = 'Permission refusée' })
    return
  end
  local requestId = pushPending(function(result)
    SendNUIMessage({ action = 'pointSaveResult', result = result })
  end)
  TriggerServerEvent('outlawjob:savePoint', requestId, data or {})
  cb({ ok = true, requestId = requestId })
end)

RegisterNUICallback('requestMigrations', function(_, cb)
  TriggerServerEvent('outlawjob:requestMigrations')
  cb({ ok = true })
end)

RegisterNUICallback('applyMigrations', function(_, cb)
  TriggerServerEvent('outlawjob:applyMigrations')
  cb({ ok = true })
end)

RegisterNUICallback('forceMigration', function(data, cb)
  TriggerServerEvent('outlawjob:forceReapplyMigration', data and data.name or '')
  cb({ ok = true })
end)

RegisterCommand('outlawcapture', function()
  if not uiOpen then return end
  if not canManage then
    simpleNotify('Permission refusée.')
    return
  end
  if not IsControlPressed(0, 21) then -- SHIFT
    simpleNotify('Maintiens SHIFT + G pour capturer les coords.')
    return
  end
  local coords = captureCoords()
  SendNUIMessage({ action = 'hotkeyCaptured', coords = coords })
end, false)

RegisterKeyMapping('outlawcapture', 'Capture coordonnée (Outlaw Job Creator)', 'keyboard', 'G')

RegisterNetEvent('outlawjob:client:setPermissions', function(payload)
  canManage = payload and payload.canManage or false
  sendPermissionsToUi()
end)

RegisterNetEvent('outlawjob:client:receiveJobs', function(rows)
  SendNUIMessage({ action = 'jobsList', jobs = rows or {} })
end)

RegisterNetEvent('outlawjob:client:migrationsStatus', function(status)
  SendNUIMessage({ action = 'migrationsStatus', status = status })
end)

RegisterNetEvent('outlawjob:client:validationResult', function(requestId, result)
  if requestId ~= 0 then
    local resolver = pendingRequests[requestId]
    if resolver then
      pendingRequests[requestId] = nil
      resolver(result)
    end
  else
    SendNUIMessage({ action = 'pointSaveResult', result = result })
  end
end)

RegisterNetEvent('outlawjob:client:showNotify', function(msg)
  simpleNotify(msg)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  clearPreview()
end)
