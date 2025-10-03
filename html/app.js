// html/app.js
(function(){
  const state = {
    coords: null,
    lastCoords: null,
    stored: [],
    canManage: false,
    mode: 'point',
    warnings: [],
    migrations: { applied: [], pending: [] }
  }

  const NUI = (name, payload = {}) =>
    fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(payload)
    }).then(r => r.json()).catch(() => ({ ok: false }))

  const $ = (id) => document.getElementById(id)
  const qs = (sel) => document.querySelector(sel)
  const qsa = (sel) => Array.from(document.querySelectorAll(sel))

  const inputs = {
    jobId: $('point_job_id'),
    label: $('point_label'),
    type: $('point_type'),
    radius: $('coord_radius'),
    heading: $('coord_heading'),
    headingRange: $('heading_range'),
    x: $('coord_x'),
    y: $('coord_y'),
    z: $('coord_z'),
    zoneToggle: $('zone_toggle'),
    salary: $('salary')
  }

  const containers = {
    coordsPreview: $('coordsPreview'),
    stored: $('storedCoords'),
    jobs: $('jobsContainer'),
    migrations: $('migrationsList')
  }

  function showApp(){ $('app').style.display = 'block' }
  function hideApp(){ $('app').style.display = 'none' }

  function formatNumber(num){
    if (num === null || num === undefined || Number.isNaN(num)) return ''
    return Number(num).toFixed(3)
  }

  function cloneCoords(coords){
    if (!coords) return null
    return {
      x: Number(coords.x),
      y: Number(coords.y),
      z: Number(coords.z),
      heading: Number(coords.heading || 0),
      radius: Number(coords.radius || inputs.radius.value || 2),
      mode: coords.mode || state.mode
    }
  }

  function updateCoordInputs(coords){
    if (!coords){
      inputs.x.value = ''
      inputs.y.value = ''
      inputs.z.value = ''
      inputs.heading.value = ''
      inputs.headingRange.value = 0
      inputs.radius.value = 2
      return
    }
    inputs.x.value = formatNumber(coords.x)
    inputs.y.value = formatNumber(coords.y)
    inputs.z.value = formatNumber(coords.z)
    inputs.heading.value = Number(coords.heading || 0).toFixed(1)
    inputs.headingRange.value = Number(coords.heading || 0)
    inputs.radius.value = Number(coords.radius || 2).toFixed(2)
    inputs.zoneToggle.checked = (state.mode === 'zone' || coords.mode === 'zone')
  }

  function renderPreviewSummary(message){
    const payload = {
      current: state.coords,
      mode: state.mode,
      warnings: state.warnings,
      storedCount: state.stored.length,
      message: message || null
    }
    containers.coordsPreview.textContent = JSON.stringify(payload, null, 2)
  }

  function setCoords(coords, opts = {}){
    if (!coords){
      state.coords = null
      state.warnings = []
      renderPreviewSummary('Prévisualisation effacée')
      updateCoordInputs(null)
      return
    }
    const next = cloneCoords(coords)
    if (!opts.skipHistory && state.coords){
      state.lastCoords = cloneCoords(state.coords)
    }
    state.coords = next
    state.mode = opts.mode || next.mode || state.mode || 'point'
    state.warnings = opts.warnings || []
    updateCoordInputs(state.coords)
    renderPreviewSummary(opts.message)
    if (opts.syncPreview !== false){
      NUI('updatePreviewCoords', {
        x: state.coords.x,
        y: state.coords.y,
        z: state.coords.z,
        heading: state.coords.heading,
        radius: state.coords.radius,
        mode: state.mode
      })
    }
  }

  function addStoredCoord(coords){
    if (!coords) return
    state.stored.push({
      ...cloneCoords(coords),
      createdAt: Date.now()
    })
    renderStoredCoords()
  }

  function removeStoredCoord(index){
    state.stored.splice(index, 1)
    renderStoredCoords()
  }

  function renderStoredCoords(){
    containers.stored.innerHTML = ''
    if (!state.stored.length){
      containers.stored.innerHTML = '<p class="empty">Aucune coord sauvegardée.</p>'
      return
    }
    state.stored.forEach((coord, idx) => {
      const el = document.createElement('div')
      el.className = 'coord-item'
      el.dataset.index = idx
      el.innerHTML = `
        <div class="coord-meta">
          <strong>#${idx + 1}</strong>
          <span>${formatNumber(coord.x)}, ${formatNumber(coord.y)}, ${formatNumber(coord.z)}</span>
          <span>H:${Number(coord.heading).toFixed(1)} R:${Number(coord.radius).toFixed(1)}</span>
        </div>
        <div class="coord-actions">
          <button data-action="use">Utiliser</button>
          <button data-action="teleport" class="ghost">TP</button>
          <button data-action="clone" class="ghost">Clone</button>
          <button data-action="remove" class="danger">X</button>
        </div>
      `
      containers.stored.appendChild(el)
    })
  }

  containers.stored.addEventListener('click', (ev)=>{
    const btn = ev.target.closest('button[data-action]')
    if (!btn) return
    const item = ev.target.closest('.coord-item')
    if (!item) return
    const index = Number(item.dataset.index)
    const coord = state.stored[index]
    if (!coord) return
    const action = btn.dataset.action
    if (action === 'use'){
      setCoords(coord, { syncPreview: true })
    } else if (action === 'teleport'){
      NUI('teleportTo', { coords: coord })
    } else if (action === 'clone'){
      addStoredCoord(coord)
    } else if (action === 'remove'){
      removeStoredCoord(index)
    }
  })

  function requestJobs(){
    NUI('requestJobs')
  }

  function renderJobs(list){
    containers.jobs.innerHTML = ''
    (list || []).forEach(job => {
      const el = document.createElement('div')
      el.className = 'item'
      el.innerHTML = `
        <div class="title">${job.label} <small>(${job.job_name})</small></div>
        <div class="meta">ID: ${job.id} • society: ${job.society_name || '-'} • salaire: ${job.default_salary || 0}</div>
      `
      containers.jobs.appendChild(el)
    })
  }

  function syncPermissions(){
    const disabled = !state.canManage
    qsa('[data-requires-manage]').forEach(btn => {
      btn.disabled = disabled
      btn.classList.toggle('disabled', disabled)
    })
    if (!state.canManage){
      renderPreviewSummary('Permissions insuffisantes')
    }
  }

  function savePoint(){
    if (!state.coords){
      renderPreviewSummary('Capture les coordonnées avant de sauvegarder.')
      return
    }
    const payload = {
      job_id: parseInt(inputs.jobId.value, 10) || 0,
      label: inputs.label.value || '',
      type: inputs.type.value || 'collect',
      radius: Number(inputs.radius.value) || state.coords.radius || 2,
      x: state.coords.x,
      y: state.coords.y,
      z: state.coords.z,
      heading: state.coords.heading,
      meta: {
        mode: state.mode,
        stored: state.stored,
        source: 'ui'
      }
    }
    state.coords.radius = payload.radius
    renderPreviewSummary('Enregistrement en cours...')
    NUI('savePoint', payload).then(res => {
      if (!res || !res.ok){
        renderPreviewSummary('Erreur lors de l\'envoi du point (voir console).')
      }
    })
  }

  function applyOffsetPrompt(){
    if (!state.coords){
      renderPreviewSummary('Capture une coordonnée avant d\'ajouter un offset.')
      return
    }
    const raw = prompt('Offset local (x,y,z)', '0,0,0')
    if (!raw) return
    const values = raw.split(',').map(v => parseFloat(v.trim()))
    const offset = {
      x: values[0] || 0,
      y: values[1] || 0,
      z: values[2] || 0
    }
    NUI('applyOffset', {
      offset,
      heading: state.coords.heading,
      radius: state.coords.radius,
      mode: state.mode
    })
  }

  function rotatePreview(value){
    state.coords = state.coords || {}
    state.coords.heading = value
    inputs.heading.value = Number(value).toFixed(1)
    NUI('rotatePreview', { heading: value })
  }

  function setMode(isZone){
    state.mode = isZone ? 'zone' : 'point'
    NUI('setPreviewMode', { mode: state.mode, radius: Number(inputs.radius.value) || 2 })
    renderPreviewSummary(`Mode ${state.mode}`)
  }

  function updateRadius(){
    const radius = Number(inputs.radius.value)
    if (Number.isNaN(radius)) return
    if (state.coords){
      state.coords.radius = radius
    }
    NUI('setPreviewMode', { mode: state.mode, radius })
  }

  function undoCoords(){
    if (state.lastCoords){
      const prev = state.lastCoords
      state.lastCoords = null
      setCoords(prev, { syncPreview: true, message: 'Coordonnée restaurée' })
    } else {
      setCoords(null)
      NUI('clearPreview')
    }
  }

  $('btnCreateJob').addEventListener('click', ()=>{
    if (!state.canManage){
      containers.coordsPreview.textContent = 'Permissions insuffisantes pour créer un job.'
      return
    }
    const payload = {
      job_name: $('job_name').value.trim(),
      label: $('label').value.trim(),
      tag: $('tag').value.trim(),
      icon: $('icon').value.trim(),
      color: $('color').value.trim(),
      society: $('society').value.trim(),
      default_salary: parseInt(inputs.salary.value, 10) || 0
    }
    NUI('createJob', payload).then(requestJobs)
  })

  $('btnRefreshJobs').addEventListener('click', requestJobs)

  $('btnGetCoords').addEventListener('click', ()=>{
    NUI('getCoords').then(res => {
      if (!res || !res.ok){
        renderPreviewSummary(res && res.error ? res.error : 'Impossible de récupérer les coordonnées.')
      }
    })
  })

  $('btnSnapGround').addEventListener('click', ()=>{
    NUI('snapToGround', {}).then(res => {
      if (!res || !res.ok){
        renderPreviewSummary('Snap échoué — capture une coordonnée valide d\'abord.')
      }
    })
  })

  $('btnOffset').addEventListener('click', applyOffsetPrompt)

  $('btnRotatePreview').addEventListener('click', ()=>{
    const raw = prompt('Heading (0-359)', inputs.heading.value || '0')
    if (raw === null) return
    const heading = Math.max(0, Math.min(359, parseFloat(raw)))
    inputs.heading.value = heading.toFixed(1)
    inputs.headingRange.value = heading
    rotatePreview(heading)
  })

  $('btnZone').addEventListener('click', ()=>{
    inputs.zoneToggle.checked = true
    setMode(true)
  })

  $('btnPoint').addEventListener('click', ()=>{
    inputs.zoneToggle.checked = false
    setMode(false)
  })

  $('btnStoreSpawn').addEventListener('click', ()=>{
    if (!state.coords){
      renderPreviewSummary('Capture une coordonnée avant de stocker.')
      return
    }
    addStoredCoord(state.coords)
    renderPreviewSummary('Coordonnée ajoutée à la liste multi-spawn.')
  })

  $('btnClearPreview').addEventListener('click', undoCoords)

  $('btnTeleportPreview').addEventListener('click', ()=>{
    if (!state.coords){
      renderPreviewSummary('Pas de prévisualisation disponible.')
      return
    }
    NUI('teleportTo', { coords: state.coords })
  })

  $('btnConfirmPoint').addEventListener('click', savePoint)
  $('btnCancelPoint').addEventListener('click', ()=>{
    setCoords(null)
    NUI('clearPreview')
  })

  inputs.headingRange.addEventListener('input', (ev)=>{
    const value = parseFloat(ev.target.value) || 0
    inputs.heading.value = value.toFixed(1)
    rotatePreview(value)
  })

  inputs.heading.addEventListener('change', (ev)=>{
    const value = Math.max(0, Math.min(359, parseFloat(ev.target.value) || 0))
    inputs.headingRange.value = value
    rotatePreview(value)
  })

  inputs.radius.addEventListener('change', updateRadius)
  inputs.zoneToggle.addEventListener('change', (ev)=> setMode(ev.target.checked))

  qsa('.coord-input').forEach(input => {
    input.addEventListener('change', ()=>{
      if (!state.coords) state.coords = {}
      state.coords.x = parseFloat(inputs.x.value) || 0
      state.coords.y = parseFloat(inputs.y.value) || 0
      state.coords.z = parseFloat(inputs.z.value) || 0
      state.coords.heading = parseFloat(inputs.heading.value) || 0
      state.coords.radius = parseFloat(inputs.radius.value) || 2
      setCoords(state.coords, { syncPreview: true, skipHistory: true })
    })
  })

  $('btnApplyMigrations').addEventListener('click', ()=>{
    NUI('applyMigrations')
  })

  $('btnRefreshMigrations').addEventListener('click', ()=>{
    NUI('requestMigrations')
  })

  $('btnForceMigration').addEventListener('click', ()=>{
    const name = $('forceMigrationName').value.trim()
    if (!name){
      renderPreviewSummary('Saisis un nom de migration à forcer.')
      return
    }
    NUI('forceMigration', { name })
  })

  function renderMigrations(){
    const { applied, pending } = state.migrations
    containers.migrations.innerHTML = ''
    const pendingBlock = document.createElement('div')
    pendingBlock.className = 'migration-block'
    pendingBlock.innerHTML = '<h4>En attente</h4>'
    if (!pending.length){
      pendingBlock.innerHTML += '<p>Aucune migration en attente.</p>'
    } else {
      pending.forEach(row => {
        const item = document.createElement('div')
        item.className = 'migration-item pending'
        item.innerHTML = `<strong>${row.name}</strong><span>${row.checksum}</span>`
        pendingBlock.appendChild(item)
      })
    }
    const appliedBlock = document.createElement('div')
    appliedBlock.className = 'migration-block'
    appliedBlock.innerHTML = '<h4>Déjà appliquées</h4>'
    if (!applied.length){
      appliedBlock.innerHTML += '<p>Aucune migration appliquée pour le moment.</p>'
    } else {
      applied.forEach(row => {
        const item = document.createElement('div')
        item.className = 'migration-item applied'
        item.innerHTML = `<strong>${row.filename}</strong><span>${row.applied_at || ''}</span>`
        appliedBlock.appendChild(item)
      })
    }
    containers.migrations.appendChild(pendingBlock)
    containers.migrations.appendChild(appliedBlock)
  }

  qsa('.tab').forEach(btn => {
    btn.addEventListener('click', ()=>{
      qsa('.tab').forEach(b => b.classList.remove('active'))
      btn.classList.add('active')
      const tab = btn.dataset.tab
      qsa('.panel').forEach(p => p.classList.remove('active'))
      qs(`#tab-${tab}`).classList.add('active')
    })
  })

  $('close').addEventListener('click', ()=>{
    NUI('close').then(()=>hideApp())
  })

  containers.coordsPreview.textContent = 'En attente...' 
  renderStoredCoords()

  window.addEventListener('message', (ev)=>{
    const data = ev.data || {}
    if (data.action === 'open'){
      showApp()
      requestJobs()
    }
    if (data.action === 'jobsList'){
      renderJobs(data.jobs || [])
    }
    if (data.action === 'coordsCaptured' || data.action === 'hotkeyCaptured'){
      state.warnings = []
      setCoords({
        x: data.coords.x,
        y: data.coords.y,
        z: data.coords.groundZ || data.coords.z,
        heading: data.coords.heading,
        radius: state.coords ? state.coords.radius : 2
      }, { syncPreview: false, message: 'Coordonnée capturée' })
    }
    if (data.action === 'coordsSnapped' || data.action === 'coordsAdjusted'){
      setCoords({
        x: data.coords.x,
        y: data.coords.y,
        z: data.coords.z,
        heading: data.coords.heading,
        radius: state.coords ? state.coords.radius : 2
      }, { syncPreview: false, message: 'Coordonnée mise à jour' })
    }
    if (data.action === 'pointSaveResult'){
      if (data.result && data.result.ok){
        state.warnings = data.result.warnings || []
        addStoredCoord(state.coords)
        renderPreviewSummary(`Point sauvegardé (#${data.result.pointId})`)
      } else {
        renderPreviewSummary(`Erreur: ${data.result && data.result.error ? data.result.error : 'inconnue'}`)
      }
    }
    if (data.action === 'permissions'){
      state.canManage = !!data.canManage
      syncPermissions()
    }
    if (data.action === 'migrationsStatus'){
      state.migrations = data.status || { applied: [], pending: [] }
      renderMigrations()
    }
  })
})()
