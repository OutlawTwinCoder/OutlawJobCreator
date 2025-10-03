-- client/main.lua
local uiOpen = false
local capabilities = {
  canManage = false,
  canGetCoords = false,
  canApplyMigrations = false
}

local preview = {
  active = false,
  mode = 'point',
  usage = 'point',
  radius = 2.0,
  heading = 0.0,
  coords = nil,
  base = nil,
  offset = { x = 0.0, y = 0.0, z = 0.0 },
  snapped = false,
  groundZ = 0.0,
  altitude = 0.0,
  blip = nil,
  drawThread = nil,
  history = {}
}

local function round(value, decimals)
  decimals = decimals or 3
  local power = 10 ^ decimals
  return math.floor((value * power) + 0.5) / power
end

local function normaliseHeading(value)
  local heading = (tonumber(value) or 0.0) % 360.0
  if heading < 0.0 then heading = heading + 360.0 end
  return heading
end

local function clearPreviewBlip()
  if preview.blip and DoesBlipExist(preview.blip) then
    RemoveBlip(preview.blip)
  end
  preview.blip = nil
end

local function rebuildPreviewBlip()
  clearPreviewBlip()
  if not preview.coords then return end

  if preview.mode == 'zone' then
    local blip = AddBlipForRadius(preview.coords.x, preview.coords.y, preview.coords.z, preview.radius)
    SetBlipColour(blip, 2)
    SetBlipAlpha(blip, 120)
    preview.blip = blip
  else
    local blip = AddBlipForCoord(preview.coords.x, preview.coords.y, preview.coords.z)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 38)
    SetBlipScale(blip, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Prévisualisation point')
    EndTextCommandSetBlipName(blip)
    preview.blip = blip
  end
end

local function stopPreviewThread()
  preview.active = false
end

local function ensurePreviewThread()
  if preview.drawThread then return end
  preview.active = true
  preview.drawThread = CreateThread(function()
    while preview.active do
      if preview.coords then
        local colourInner = preview.mode == 'zone' and 0 or 120
        DrawMarker(1, preview.coords.x, preview.coords.y, preview.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          preview.radius * 2.0, preview.radius * 2.0, 1.0, 0, 120, 255, 80, false, false, 2, false, nil, nil, false)
        DrawMarker(28, preview.coords.x, preview.coords.y, preview.coords.z + 0.05, 0.0, 0.0, 0.0,
          0.0, 0.0, preview.heading, 0.35, 0.35, 0.5, 255, colourInner, 50, 120, false, true, 2, false, nil, nil, false)
        if preview.mode == 'zone' then
          DrawMarker(28, preview.coords.x, preview.coords.y, preview.coords.z + 0.1, 0.0, 0.0, 0.0,
            0.0, 0.0, preview.heading, preview.radius * 0.8, preview.radius * 0.8, 0.4, 0, 255, 128, 90, false, true, 2, false, nil, nil, false)
        end
      end
      Wait(0)
    end
    preview.drawThread = nil
  end)
end

local function sendPreviewState(extra)
  if not preview.coords then
    SendNUIMessage({ action = 'coordsPreviewState', active = false })
    return
  end
  local snapshot = {
    x = round(preview.coords.x, 3),
    y = round(preview.coords.y, 3),
    z = round(preview.coords.z, 3),
    heading = round(preview.heading, 2),
    radius = round(preview.radius, 2),
    mode = preview.mode,
    usage = preview.usage,
    offset = {
      x = round(preview.offset.x, 3),
      y = round(preview.offset.y, 3),
      z = round(preview.offset.z, 3)
    },
    base = preview.base and {
      x = round(preview.base.x, 3),
      y = round(preview.base.y, 3),
      z = round(preview.base.z, 3),
      heading = round(preview.base.heading, 2)
    } or nil,
    snapped = preview.snapped,
    groundZ = round(preview.groundZ or 0.0, 3),
    altitude = round(preview.altitude or 0.0, 3)
  }
  if extra then
    for k, v in pairs(extra) do snapshot[k] = v end
  end
  SendNUIMessage({ action = 'coordsPreviewState', active = true, snapshot = snapshot })
end

local function addHistory(snapshot)
  preview.history = preview.history or {}
  table.insert(preview.history, 1, snapshot)
  while #preview.history > 6 do
    table.remove(preview.history)
  end
  SendNUIMessage({ action = 'coordsHistory', items = preview.history })
end

local function resetPreviewState()
  stopPreviewThread()
  clearPreviewBlip()
  preview.coords = nil
  preview.base = nil
  preview.offset = { x = 0.0, y = 0.0, z = 0.0 }
  preview.snapped = false
  preview.groundZ = 0.0
  preview.altitude = 0.0
  preview.mode = 'point'
  preview.usage = 'point'
  preview.radius = 2.0
  preview.heading = 0.0
  SendNUIMessage({ action = 'coordsPreviewState', active = false })
end

local function applyOffset(offset)
  if not preview.base then return end
  local headingRad = math.rad(preview.base.heading or preview.heading)
  local cosH = math.cos(headingRad)
  local sinH = math.sin(headingRad)
  local dx = offset.x * cosH - offset.y * sinH
  local dy = offset.x * sinH + offset.y * cosH
  local dz = offset.z
  preview.coords = vector3(preview.base.x + dx, preview.base.y + dy, preview.base.z + dz)
  preview.offset = { x = offset.x, y = offset.y, z = offset.z }
end

local function computeGroundData(coords)
  local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0.0)
  if found then
    return groundZ, coords.z - groundZ
  end
  return coords.z, 0.0
end

local function captureCoords(autoSnap)
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local groundZ, altitude = computeGroundData(pos)

  preview.base = { x = pos.x + 0.0, y = pos.y + 0.0, z = pos.z + 0.0, heading = heading + 0.0 }
  preview.coords = vector3(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0)
  preview.heading = heading + 0.0
  preview.radius = preview.radius or 2.0
  preview.offset = { x = 0.0, y = 0.0, z = 0.0 }
  preview.mode = preview.mode or 'point'
  preview.usage = preview.usage or 'point'
  preview.snapped = false
  preview.groundZ = groundZ
  preview.altitude = altitude

  if autoSnap then
    local snapGround, alt = computeGroundData(preview.coords)
    preview.coords = vector3(preview.coords.x, preview.coords.y, snapGround)
    preview.altitude = alt
    preview.snapped = true
  end

  ensurePreviewThread()
  rebuildPreviewBlip()
  sendPreviewState({ captured = true })

  return {
    x = round(pos.x, 3),
    y = round(pos.y, 3),
    z = round(pos.z, 3),
    heading = round(heading, 2),
    groundZ = round(groundZ, 3),
    altitude = round(altitude, 3)
  }
end

local function updateAltitudeFromCoords()
  if preview.coords then
    local groundZ, altitude = computeGroundData(preview.coords)
    preview.groundZ = groundZ
    preview.altitude = altitude
  end
end

local function rotatePreview(delta)
  preview.heading = normaliseHeading(preview.heading + delta)
end

local function buildSnapshot()
  if not preview.coords then return nil end
  updateAltitudeFromCoords()
  return {
    x = round(preview.coords.x, 3),
    y = round(preview.coords.y, 3),
    z = round(preview.coords.z, 3),
    heading = round(preview.heading, 2),
    radius = round(preview.radius, 2),
    mode = preview.mode,
    usage = preview.usage,
    snapped = preview.snapped,
    offset = {
      x = round(preview.offset.x, 3),
      y = round(preview.offset.y, 3),
      z = round(preview.offset.z, 3)
    },
    base = preview.base and {
      x = round(preview.base.x, 3),
      y = round(preview.base.y, 3),
      z = round(preview.base.z, 3),
      heading = round(preview.base.heading, 2)
    } or nil,
    groundZ = round(preview.groundZ or 0.0, 3),
    altitude = round(preview.altitude or 0.0, 3)
  }
end

RegisterCommand('outlawjob', function()
  TriggerServerEvent('outlawjob:server:requestOpen')
end, false)

RegisterCommand('outlawjob_capture', function()
  if not uiOpen or not capabilities.canGetCoords then return end
  if not IsControlPressed(0, 21) then return end -- LSHIFT
  captureCoords()
  local snapshot = buildSnapshot()
  SendNUIMessage({ action = 'coordsQuickCapture', snapshot = snapshot })
end, false)

RegisterKeyMapping('outlawjob_capture', 'Capture coords (Outlaw Job Creator)', 'keyboard', 'G')

RegisterNUICallback('close', function(_, cb)
  uiOpen = false
  SetNuiFocus(false, false)
  resetPreviewState()
  cb({ ok = true })
end)

RegisterNUICallback('requestJobs', function(_, cb)
  TriggerServerEvent('outlawjob:requestJobs')
  cb({ ok = true })
end)

RegisterNUICallback('requestPoints', function(data, cb)
  if data and data.job_id then
    TriggerServerEvent('outlawjob:requestPoints', data.job_id)
  end
  cb({ ok = true })
end)

RegisterNUICallback('createJob', function(data, cb)
  TriggerServerEvent('outlawjob:createJob', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('createPoint', function(data, cb)
  TriggerServerEvent('outlawjob:createPoint', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('coordsCapture', function(data, cb)
  if not capabilities.canGetCoords then
    cb({ ok = false, error = 'forbidden' })
    return
  end
  local payload = captureCoords(data and data.autoSnap)
  cb({ ok = true, capture = payload })
end)

RegisterNUICallback('coordsSnapGround', function(_, cb)
  if not preview.coords then
    cb({ ok = false, error = 'no_preview' })
    return
  end
  local groundZ, altitude = computeGroundData(preview.coords)
  preview.coords = vector3(preview.coords.x, preview.coords.y, groundZ)
  preview.snapped = true
  preview.groundZ = groundZ
  preview.altitude = altitude
  rebuildPreviewBlip()
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsSetMode', function(data, cb)
  if not preview.coords then
    cb({ ok = false })
    return
  end
  local mode = data and data.mode or 'point'
  if mode ~= 'zone' then
    mode = 'point'
  end
  preview.mode = mode
  rebuildPreviewBlip()
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsSetUsage', function(data, cb)
  if data and data.usage then
    preview.usage = data.usage
    sendPreviewState()
  end
  cb({ ok = true })
end)

RegisterNUICallback('coordsSetRadius', function(data, cb)
  if not preview.coords then
    cb({ ok = false })
    return
  end
  local radius = tonumber(data and data.radius)
  if radius then
    preview.radius = math.max(0.2, radius)
    rebuildPreviewBlip()
    sendPreviewState()
  end
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsSetHeading', function(data, cb)
  if not preview.coords then
    cb({ ok = false })
    return
  end
  preview.heading = normaliseHeading(data and data.heading)
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsAddOffset', function(data, cb)
  if not preview.coords or not preview.base then
    cb({ ok = false })
    return
  end
  local offset = {
    x = tonumber(data and data.x) or 0.0,
    y = tonumber(data and data.y) or 0.0,
    z = tonumber(data and data.z) or 0.0
  }
  applyOffset(offset)
  updateAltitudeFromCoords()
  rebuildPreviewBlip()
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsRotate', function(data, cb)
  if not preview.coords then
    cb({ ok = false })
    return
  end
  local delta = tonumber(data and data.delta) or 0.0
  rotatePreview(delta)
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsUndo', function(_, cb)
  if not preview.base then
    cb({ ok = false })
    return
  end
  preview.coords = vector3(preview.base.x, preview.base.y, preview.base.z)
  preview.heading = preview.base.heading
  preview.offset = { x = 0.0, y = 0.0, z = 0.0 }
  preview.snapped = false
  updateAltitudeFromCoords()
  rebuildPreviewBlip()
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsCancel', function(_, cb)
  resetPreviewState()
  cb({ ok = true })
end)

RegisterNUICallback('coordsConfirm', function(data, cb)
  if not preview.coords then
    cb({ ok = false, error = 'no_preview' })
    return
  end
  if data then
    if data.radius then
      preview.radius = math.max(0.2, tonumber(data.radius) or preview.radius)
    end
    if data.heading then
      preview.heading = normaliseHeading(data.heading)
    end
    if data.usage then
      preview.usage = data.usage
    end
  end
  local snapshot = buildSnapshot()
  addHistory(snapshot)
  cb({ ok = true, snapshot = snapshot })
end)

RegisterNUICallback('coordsLoadSnapshot', function(data, cb)
  if not data or not data.snapshot then
    cb({ ok = false })
    return
  end
  local s = data.snapshot
  preview.base = s.base and {
    x = s.base.x,
    y = s.base.y,
    z = s.base.z,
    heading = s.base.heading
  } or {
    x = s.x,
    y = s.y,
    z = s.z,
    heading = s.heading
  }
  preview.coords = vector3(s.x, s.y, s.z)
  preview.heading = s.heading or preview.base.heading
  preview.radius = s.radius or preview.radius
  preview.mode = s.mode or 'point'
  preview.usage = s.usage or preview.usage
  preview.offset = {
    x = (s.offset and s.offset.x) or 0.0,
    y = (s.offset and s.offset.y) or 0.0,
    z = (s.offset and s.offset.z) or 0.0
  }
  preview.snapped = s.snapped or false
  preview.groundZ = s.groundZ or preview.groundZ
  preview.altitude = s.altitude or preview.altitude
  ensurePreviewThread()
  rebuildPreviewBlip()
  sendPreviewState()
  cb({ ok = true, snapshot = buildSnapshot() })
end)

RegisterNUICallback('coordsTeleport', function(data, cb)
  local x = tonumber(data and data.x)
  local y = tonumber(data and data.y)
  local z = tonumber(data and data.z)
  if not x or not y or not z then
    cb({ ok = false, error = 'invalid_coords' })
    return
  end
  local heading = tonumber(data.heading)
  local ped = PlayerPedId()
  SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.1, false, false, false)
  if heading then
    SetEntityHeading(ped, heading + 0.0)
  end
  cb({ ok = true })
end)

RegisterNUICallback('migrations:refresh', function(_, cb)
  TriggerServerEvent('outlawjob:getMigrations')
  cb({ ok = true })
end)

RegisterNUICallback('migrations:apply', function(_, cb)
  TriggerServerEvent('outlawjob:applyMigrations')
  cb({ ok = true })
end)

RegisterNUICallback('migrations:force', function(data, cb)
  TriggerServerEvent('outlawjob:forceMigration', data and data.name or nil)
  cb({ ok = true })
end)

RegisterNetEvent('outlawjob:client:openUI', function(caps)
  capabilities = caps or capabilities
  uiOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', capabilities = capabilities })
  if preview.history and #preview.history > 0 then
    SendNUIMessage({ action = 'coordsHistory', items = preview.history })
  end
  TriggerServerEvent('outlawjob:requestJobs')
  if capabilities.canApplyMigrations then
    TriggerServerEvent('outlawjob:getMigrations')
  end
end)

RegisterNetEvent('outlawjob:client:receiveJobs', function(rows)
  SendNUIMessage({ action = 'jobsList', jobs = rows or {} })
end)

RegisterNetEvent('outlawjob:client:receivePoints', function(rows)
  SendNUIMessage({ action = 'pointsList', points = rows or {} })
end)

RegisterNetEvent('outlawjob:client:requestJobsRefresh', function()
  TriggerServerEvent('outlawjob:requestJobs')
end)

RegisterNetEvent('outlawjob:client:showNotify', function(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, false)
end)

RegisterNetEvent('outlawjob:client:migrationsList', function(list)
  SendNUIMessage({ action = 'migrations:list', migrations = list or {} })
end)

RegisterNetEvent('outlawjob:client:migrationResult', function(results)
  SendNUIMessage({ action = 'migrations:result', results = results or {} })
end)

local validationCallbacks = {}

RegisterNetEvent('outlawjob:client:validationResult', function(requestId, ok, sanitized, reason)
  local resolver = validationCallbacks[requestId]
  if not resolver then return end
  validationCallbacks[requestId] = nil
  resolver(ok, sanitized, reason)
end)

local function sendValidationRequest(payload, cb)
  local requestId = ('req:%s:%s'):format(GetGameTimer(), math.random(1000, 9999))
  validationCallbacks[requestId] = cb
  TriggerServerEvent('outlawjob:validatePoint', requestId, payload)
end

RegisterNUICallback('validatePoint', function(data, cb)
  sendValidationRequest(data, function(ok, sanitized, reason)
    cb({ ok = ok, sanitized = sanitized, reason = reason })
  end)
end)

-- cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  resetPreviewState()
end)
