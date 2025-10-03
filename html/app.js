// html/app.js (v3)
(function(){
  const NUI = (name, payload={}) =>
    fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: {'Content-Type':'application/json; charset=utf-8'},
      body: JSON.stringify(payload)
    }).then(r=>r.json()).catch(()=>({ok:false}))

  const $ = (id)=>document.getElementById(id)
  const qs = (sel)=>document.querySelector(sel)
  const qsa=(sel)=>Array.from(document.querySelectorAll(sel))

  const state = {
    capabilities: { canManage:false, canGetCoords:false, canApplyMigrations:false },
    preview: null,
    confirmed: null,
    multi: [],
    history: [],
    jobs: [],
    jobMap: {},
    jobByOutlawId: {},
    points: [],
    pointsFilter: null,
    migrations: [],
    migrationResult: [],
    bootstrap: {
      jobForm: { iconOptions: [], colorOptions: [] },
      pointOptions: { types: [], usage: [], modes: [] },
      jobConnectors: {}
    }
  }

  const jobIconInput = $('job_icon')
  const jobColorInput = $('job_color')
  const jobSocietyInput = $('job_society')
  const jobSalaryInput = $('job_salary')
  const jobWhitelistInput = $('job_whitelisted')
  const jobIconChips = $('jobIconChips')
  const jobColorChips = $('jobColorChips')
  const jobConnectorsLegend = $('jobsConnectorsLegend')
  const pointJobSelect = $('point_job_id')
  const pointsFilterSelect = $('points_job_filter')
  const pointTypeLegend = $('pointTypeLegend')
  const pointUsageLegend = $('pointUsageLegend')
  const pointModeLegend = $('pointModeLegend')

  const formatNumber = (value)=>{
    const number = Number(value) || 0
    return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(Math.round(number))
  }

  function mergeBootstrap(data){
    const incoming = data || {}
    const jobForm = Object.assign({
      iconOptions: [],
      colorOptions: [],
      defaultIcon: '',
      defaultColor: '',
      defaultTag: '',
      defaultSalary: 0,
      defaultSocietyPrefix: 'society_',
      defaultWhitelisted: false
    }, incoming.jobForm || {})
    const pointOptions = Object.assign({ types: [], usage: [], modes: [] }, incoming.pointOptions || {})
    const jobConnectors = incoming.jobConnectors || {}
    state.bootstrap = { jobForm, pointOptions, jobConnectors }
  }

  function renderJobFormChips(){
    if(jobIconChips){
      jobIconChips.innerHTML = ''
      ;(state.bootstrap.jobForm.iconOptions || []).forEach(opt=>{
        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'chip-btn'
        btn.textContent = opt.label || opt.value
        btn.addEventListener('click', ()=>{
          if(jobIconInput){ jobIconInput.value = opt.value }
        })
        jobIconChips.appendChild(btn)
      })
    }
    if(jobColorChips){
      jobColorChips.innerHTML = ''
      ;(state.bootstrap.jobForm.colorOptions || []).forEach(opt=>{
        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'chip-btn color'
        btn.style.setProperty('--chip-color', opt.value)
        btn.textContent = opt.label || opt.value
        btn.addEventListener('click', ()=>{
          if(jobColorInput){ jobColorInput.value = opt.value }
        })
        jobColorChips.appendChild(btn)
      })
    }
  }

  function renderLegend(target, items){
    if(!target) return
    target.innerHTML = ''
    ;(items || []).forEach(entry=>{
      const row = document.createElement('div')
      row.className = 'legend-item'
      row.innerHTML = `<strong>${entry.label || entry.value}</strong><span>${entry.description || ''}</span>`
      target.appendChild(row)
    })
  }

  function populatePointFormOptions(){
    if(pointJobSelect){
      pointJobSelect.innerHTML = '<option value="">Choisir un job Outlaw</option>'
    }
    if(pointsFilterSelect){
      pointsFilterSelect.innerHTML = '<option value="">Choisir un job</option>'
    }
    const pointType = $('point_type')
    if(pointType){
      pointType.innerHTML = ''
      const types = state.bootstrap.pointOptions.types || []
      if(types.length === 0){
        const opt = document.createElement('option')
        opt.value = 'generic'
        opt.textContent = 'generic'
        pointType.appendChild(opt)
      } else {
        types.forEach(opt=>{
          const option = document.createElement('option')
          option.value = opt.value
          option.textContent = opt.label || opt.value
          pointType.appendChild(option)
        })
      }
      renderLegend(pointTypeLegend, state.bootstrap.pointOptions.types)
    }
    const usageSelect = $('point_usage')
    if(usageSelect){
      usageSelect.innerHTML = ''
      const usages = state.bootstrap.pointOptions.usage || []
      if(usages.length === 0){
        const opt = document.createElement('option')
        opt.value = 'point'
        opt.textContent = 'Point unique'
        usageSelect.appendChild(opt)
      } else {
        usages.forEach(opt=>{
          const option = document.createElement('option')
          option.value = opt.value
          option.textContent = opt.label || opt.value
          usageSelect.appendChild(option)
        })
      }
      renderLegend(pointUsageLegend, usages)
    }
    renderLegend(pointModeLegend, state.bootstrap.pointOptions.modes)
  }

  function renderConnectorLegend(){
    if(!jobConnectorsLegend) return
    jobConnectorsLegend.innerHTML = ''
    const entries = Object.entries(state.bootstrap.jobConnectors || {})
    if(entries.length === 0){
      jobConnectorsLegend.innerHTML = '<p class="muted">Configure les connecteurs dans <code>config.lua</code> pour afficher les dépendances (armurerie, garage, shops...).</p>'
      return
    }
    entries.forEach(([key, meta])=>{
      const pill = document.createElement('span')
      pill.className = 'chip legend'
      pill.textContent = meta.label || key
      jobConnectorsLegend.appendChild(pill)
    })
  }

  function applyJobDefaults(force){
    const defaults = state.bootstrap.jobForm || {}
    const tagField = $('tag')
    if(tagField && (force || !tagField.value.trim())){
      tagField.value = defaults.defaultTag || ''
    }
    if(jobIconInput && (force || !jobIconInput.value.trim())){
      jobIconInput.value = defaults.defaultIcon || ''
    }
    if(jobColorInput && (force || !jobColorInput.value.trim())){
      jobColorInput.value = defaults.defaultColor || ''
    }
    if(jobSalaryInput && (force || !jobSalaryInput.value)){
      jobSalaryInput.value = defaults.defaultSalary != null ? defaults.defaultSalary : 0
    }
    if(jobWhitelistInput && (force || jobWhitelistInput.dataset.applied !== 'true')){
      jobWhitelistInput.checked = !!defaults.defaultWhitelisted
      jobWhitelistInput.dataset.applied = 'true'
    }
  }

  function autoFillSociety(force){
    if(!jobSocietyInput) return
    if(!force && jobSocietyInput.dataset.manual === 'true'){
      return
    }
    const defaults = state.bootstrap.jobForm || {}
    const prefix = defaults.defaultSocietyPrefix || 'society_'
    const rawName = ($('job_name')?.value || '').trim()
    if(rawName === ''){
      if(force){
        jobSocietyInput.value = ''
        jobSocietyInput.dataset.manual = 'false'
      }
      return
    }
    const slug = rawName.toLowerCase().replace(/\s+/g, '_')
    jobSocietyInput.value = (prefix + slug).substring(0, 64)
    if(force){
      jobSocietyInput.dataset.manual = 'false'
    }
  }

  function setSelectValue(select, value){
    if(!select) return
    const options = Array.from(select.options || [])
    const hasValue = options.some(opt => opt.value === value)
    if(hasValue){
      select.value = value
    }
  }

  function updateJobSelects(){
    if(pointJobSelect){
      const selected = pointJobSelect.value
      pointJobSelect.innerHTML = '<option value="">Choisir un job Outlaw</option>'
      Object.values(state.jobByOutlawId).forEach(job => {
        const opt = document.createElement('option')
        opt.value = job.blueprint_id
        opt.textContent = `${job.label} (${job.name})`
        pointJobSelect.appendChild(opt)
      })
      if(selected){
        setSelectValue(pointJobSelect, selected)
      }
    }
    if(pointsFilterSelect){
      const selected = pointsFilterSelect.value
      pointsFilterSelect.innerHTML = '<option value="">Choisir un job</option>'
      Object.values(state.jobByOutlawId).forEach(job => {
        const opt = document.createElement('option')
        opt.value = job.blueprint_id
        opt.textContent = `${job.label} (${job.name})`
        opt.dataset.jobName = job.name
        pointsFilterSelect.appendChild(opt)
      })
      if(selected){
        setSelectValue(pointsFilterSelect, selected)
      }
    }
  }

  function applyBootstrapData(data){
    mergeBootstrap(data)
    renderJobFormChips()
    populatePointFormOptions()
    renderConnectorLegend()
    applyJobDefaults(false)
    autoFillSociety(false)
  }

  const jobNameInput = $('job_name')
  if(jobSocietyInput){
    jobSocietyInput.dataset.manual = jobSocietyInput.value.trim() === '' ? 'false' : 'true'
    jobSocietyInput.addEventListener('input', ()=>{
      jobSocietyInput.dataset.manual = jobSocietyInput.value.trim() === '' ? 'false' : 'true'
    })
  }
  if(jobNameInput){
    jobNameInput.addEventListener('input', ()=> autoFillSociety(false))
    jobNameInput.addEventListener('blur', ()=> autoFillSociety(false))
  }

  const btnJobDefaults = $('btnJobDefaults')
  if(btnJobDefaults){
    btnJobDefaults.addEventListener('click', ()=>{
      if(!state.capabilities.canManage){ return }
      if(jobSocietyInput){
        jobSocietyInput.dataset.manual = 'false'
      }
      applyJobDefaults(true)
      autoFillSociety(true)
    })
  }

  function showApp(){ $('app').style.display = 'block' }
  function hideApp(){ $('app').style.display = 'none' }

  qsa('.tab').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      qsa('.tab').forEach(b=>b.classList.remove('active'))
      btn.classList.add('active')
      const tab = btn.dataset.tab
      qsa('.panel').forEach(p=>p.classList.remove('active'))
      qs(`#tab-${tab}`).classList.add('active')
    })
  })

  $('close').addEventListener('click', ()=>{
    NUI('close').then(()=>hideApp())
  })

  function requestJobs(){ NUI('requestJobs') }

  $('btnCreateJob').addEventListener('click', ()=>{
    if(!state.capabilities.canManage){
      alert('Permission refusée.')
      return
    }
    autoFillSociety(false)
    const payload = {
      job_name: $('job_name').value.trim(),
      label: $('label').value.trim(),
      tag: $('tag').value.trim(),
      icon: jobIconInput ? jobIconInput.value.trim() : '',
      color: jobColorInput ? jobColorInput.value.trim() : '',
      society: jobSocietyInput ? jobSocietyInput.value.trim() : '',
      default_salary: parseInt(jobSalaryInput ? jobSalaryInput.value : state.bootstrap.jobForm.defaultSalary, 10) || 0,
      whitelisted: jobWhitelistInput ? jobWhitelistInput.checked : false
    }
    if(!payload.job_name || !payload.label){
      alert('Nom interne et label sont requis.')
      return
    }
    NUI('createJob', payload).then(()=>{
      requestJobs()
    })
  })

  $('btnRefreshJobs').addEventListener('click', requestJobs)

  function renderJobs(list){
    const container = $('jobsContainer')
    state.jobs = list || []
    state.jobMap = {}
    state.jobByOutlawId = {}
    container.innerHTML = ''

    if(state.jobs.length === 0){
      container.innerHTML = '<p class="empty">Aucun job détecté. Utilise la section de gauche pour en créer un.</p>'
      updateJobSelects()
      return
    }

    const missing = state.jobs.filter(job => !job.blueprint_id).length
    if(missing > 0){
      const info = document.createElement('div')
      info.className = 'info-block'
      info.innerHTML = `<strong>${missing}</strong> job(s) n'ont pas encore de métadonnées Outlaw. Clique <em>Activer Outlaw</em> pour générer l'identifiant interne et lier les points.`
      container.appendChild(info)
    }

    state.jobs.forEach(job => {
      state.jobMap[job.name] = job
      if(job.blueprint_id){
        state.jobByOutlawId[job.blueprint_id] = job
      }

      const card = document.createElement('div')
      card.className = 'item job-card'
      card.dataset.job = job.name

      const header = document.createElement('div')
      header.className = 'title'
      const badge = job.whitelisted ? '<span class="badge">Whitelist</span>' : ''
      header.innerHTML = `<span class="job-label" style="--job-color:${job.color || '#ff9d0b'}"><span class="dot"></span>${job.label}<small>(${job.name})</small></span>${badge}`
      card.appendChild(header)

      const metaPrimary = document.createElement('div')
      metaPrimary.className = 'meta'
      const details = []
      details.push(`Employés: ${formatNumber(job.employees || 0)}`)
      details.push(`Points Outlaw: ${formatNumber(job.points || 0)}`)
      if(job.billing && (job.billing.count || job.billing.amount)){
        details.push(`Factures: ${formatNumber(job.billing.count || 0)} (${formatNumber(job.billing.amount || 0)}$)`)
      }
      metaPrimary.textContent = details.join(' • ')
      card.appendChild(metaPrimary)

      const metaSociety = document.createElement('div')
      metaSociety.className = 'meta secondary'
      const balance = job.has_society_account ? `${formatNumber(job.society_balance || 0)}$` : 'compte société manquant'
      metaSociety.textContent = `Société: ${job.society_name || '-'} • ${balance}`
      card.appendChild(metaSociety)

      const connectors = Object.entries(state.bootstrap.jobConnectors || {})
      if(connectors.length > 0){
        const wrap = document.createElement('div')
        wrap.className = 'connector-row'
        connectors.forEach(([key, meta])=>{
          const chip = document.createElement('span')
          chip.className = 'chip stat'
          const value = job.connectors && job.connectors[key] || 0
          chip.innerHTML = `<span>${meta.label || key}</span><strong>${formatNumber(value)}</strong>`
          wrap.appendChild(chip)
        })
        card.appendChild(wrap)
      }

      const actions = document.createElement('div')
      actions.className = 'actions'

      const syncBtn = document.createElement('button')
      syncBtn.className = job.blueprint_id ? 'ghost small' : 'primary small'
      syncBtn.textContent = job.blueprint_id ? 'Re-synchroniser' : 'Activer Outlaw'
      syncBtn.addEventListener('click', ()=>{
        NUI('jobs:syncOutlaw', { job_name: job.name })
      })
      actions.appendChild(syncBtn)

      if(job.blueprint_id){
        const pointsBtn = document.createElement('button')
        pointsBtn.className = 'ghost small'
        pointsBtn.textContent = 'Voir points'
        pointsBtn.addEventListener('click', ()=>{
          if(pointsFilterSelect){
            pointsFilterSelect.value = String(job.blueprint_id)
          }
          state.pointsFilter = job.blueprint_id
          NUI('requestPoints', { job_id: job.blueprint_id })
          const pointsTab = document.querySelector('.tab[data-tab="points"]')
          if(pointsTab){ pointsTab.click() }
        })
        actions.appendChild(pointsBtn)
      }

      card.appendChild(actions)
      container.appendChild(card)
    })

    updateJobSelects()
  }
  const coordsPreview = $('coordsPreview')
  const pointRadius = $('point_radius')
  const pointHeading = $('point_heading')
  const pointUsage = $('point_usage')
  const pointType = $('point_type')

  function formatSnapshot(snapshot){
    if(!snapshot) return ''
    return JSON.stringify(snapshot, null, 2)
  }

  function setSegmentMode(mode){
    qsa('#modeSegment button').forEach(btn=>{
      btn.classList.toggle('active', btn.dataset.mode === mode)
    })
  }

  function updatePreview(snapshot){
    state.preview = snapshot
    if(!snapshot){
      coordsPreview.textContent = 'Aucune prévisualisation active.'
      return
    }
    coordsPreview.textContent = formatSnapshot(snapshot)
    if(snapshot.radius != null){ pointRadius.value = snapshot.radius }
    if(snapshot.heading != null){ pointHeading.value = snapshot.heading }
    if(snapshot.usage){ pointUsage.value = snapshot.usage }
    setSegmentMode(snapshot.mode || 'point')
  }

  function updateHistory(list){
    state.history = list || []
    const container = $('coordsHistory')
    container.innerHTML = ''
    state.history.forEach((entry)=>{
      const item = document.createElement('div')
      item.className = 'item'
      item.innerHTML = `<div class="title">${entry.mode || 'point'} • ${entry.x.toFixed(2)}, ${entry.y.toFixed(2)}, ${entry.z.toFixed(2)}</div>
                        <div class="meta">heading ${entry.heading.toFixed(1)} • radius ${entry.radius.toFixed(1)}</div>`
      const actions = document.createElement('div')
      actions.className = 'actions'
      const useBtn = document.createElement('button')
      useBtn.className = 'small ghost'
      useBtn.textContent = 'Prévisualiser'
      useBtn.addEventListener('click', ()=>{
        NUI('coordsLoadSnapshot', { snapshot: entry })
      })
      const tpBtn = document.createElement('button')
      tpBtn.className = 'small ghost'
      tpBtn.textContent = 'Téléporter'
      tpBtn.addEventListener('click', ()=>{
        NUI('coordsTeleport', entry)
      })
      const addBtn = document.createElement('button')
      addBtn.className = 'small ghost'
      addBtn.textContent = 'Ajouter multi'
      addBtn.addEventListener('click', ()=>{
        addMulti(entry)
      })
      actions.append(useBtn, tpBtn, addBtn)
      item.append(actions)
      container.appendChild(item)
    })
  }

  function renderMulti(){
    const container = $('multiSpawnList')
    container.innerHTML = ''
    state.multi.forEach((entry, idx)=>{
      const item = document.createElement('div')
      item.className = 'item'
      item.innerHTML = `<div class="title">Spawn ${idx+1}</div>
                        <div class="meta">${entry.x.toFixed(2)}, ${entry.y.toFixed(2)}, ${entry.z.toFixed(2)} • h ${entry.heading.toFixed(1)}</div>`
      const actions = document.createElement('div')
      actions.className = 'actions'
      const previewBtn = document.createElement('button')
      previewBtn.className = 'small ghost'
      previewBtn.textContent = 'Prévisualiser'
      previewBtn.addEventListener('click', ()=>{
        NUI('coordsLoadSnapshot', { snapshot: entry })
      })
      const tpBtn = document.createElement('button')
      tpBtn.className = 'small ghost'
      tpBtn.textContent = 'Téléporter'
      tpBtn.addEventListener('click', ()=>{
        NUI('coordsTeleport', entry)
      })
      const cloneBtn = document.createElement('button')
      cloneBtn.className = 'small ghost'
      cloneBtn.textContent = 'Cloner'
      cloneBtn.addEventListener('click', ()=>{
        addMulti(entry)
      })
      const removeBtn = document.createElement('button')
      removeBtn.className = 'small ghost'
      removeBtn.textContent = 'Supprimer'
      removeBtn.addEventListener('click', ()=>{
        state.multi.splice(idx,1)
        renderMulti()
      })
      actions.append(previewBtn,tpBtn,cloneBtn,removeBtn)
      item.append(actions)
      container.appendChild(item)
    })
  }

  function addMulti(snapshot){
    if(!snapshot){ return }
    const copy = JSON.parse(JSON.stringify(snapshot))
    state.multi.push(copy)
    renderMulti()
  }

  $('btnMultiClear').addEventListener('click', ()=>{
    state.multi = []
    renderMulti()
  })

  $('btnHistoryClear').addEventListener('click', ()=>{
    state.history = []
    $('coordsHistory').innerHTML = ''
  })

  function buildPointPayload(snapshot){
    const jobId = parseInt($('point_job_id').value,10)
    const label = $('point_label').value.trim()
    const type = pointType.value
    return {
      job_id: jobId || 0,
      label,
      type,
      x: snapshot.x,
      y: snapshot.y,
      z: snapshot.z,
      heading: snapshot.heading,
      radius: snapshot.radius,
      mode: snapshot.mode,
      usage: snapshot.usage,
      offset: snapshot.offset,
      base: snapshot.base,
      multi: state.multi.map(entry=>({ x: entry.x, y: entry.y, z: entry.z, heading: entry.heading })),
      snap: snapshot.snapped,
      autoSnap: snapshot.snapped
    }
  }

  function ensureManageAccess(){
    const allowed = state.capabilities.canGetCoords
    qsa('[data-manage-only]').forEach(el=>{
      el.style.display = allowed ? '' : 'none'
    })
    $('btnGetCoords').disabled = !allowed
    $('btnSnapGround').disabled = !allowed
    $('btnUndoPreview').disabled = !allowed
    $('btnCancelPreview').disabled = !allowed
    $('btnPreviewTeleport').disabled = !allowed
    $('btnApplyOffset').disabled = !allowed
    $('btnRotatePreview').disabled = !allowed
    $('btnConfirmPreview').disabled = !allowed
    $('btnStoreSpawn').disabled = !allowed
    $('btnAddMulti').disabled = !allowed
    $('btnCreatePoint').disabled = !state.capabilities.canManage
    const manage = state.capabilities.canManage
    const createJobBtn = $('btnCreateJob')
    if(createJobBtn){ createJobBtn.disabled = !manage }
    if(btnJobDefaults){ btnJobDefaults.disabled = !manage }
    if(jobIconInput){ jobIconInput.disabled = !manage }
    if(jobColorInput){ jobColorInput.disabled = !manage }
    if(jobSocietyInput){ jobSocietyInput.disabled = !manage }
    if(jobSalaryInput){ jobSalaryInput.disabled = !manage }
    if(jobWhitelistInput){ jobWhitelistInput.disabled = !manage }
    if(pointJobSelect){ pointJobSelect.disabled = !manage }
    $('btnMigrationsApply').disabled = !state.capabilities.canApplyMigrations
    $('btnMigrationForce').disabled = !state.capabilities.canApplyMigrations
  }

  $('btnGetCoords').addEventListener('click', ()=>{
    if(!state.capabilities.canGetCoords){ return }
    NUI('coordsCapture', { autoSnap:false })
  })

  $('btnSnapGround').addEventListener('click', ()=>{
    NUI('coordsSnapGround')
  })

  $('btnUndoPreview').addEventListener('click', ()=>{
    NUI('coordsUndo')
  })

  $('btnCancelPreview').addEventListener('click', ()=>{
    NUI('coordsCancel')
    state.preview = null
    state.confirmed = null
    coordsPreview.textContent = 'Prévisualisation annulée.'
  })

  $('btnPreviewTeleport').addEventListener('click', ()=>{
    if(state.preview){ NUI('coordsTeleport', state.preview) }
  })

  $('btnApplyOffset').addEventListener('click', ()=>{
    const payload = {
      x: parseFloat($('offset_x').value) || 0,
      y: parseFloat($('offset_y').value) || 0,
      z: parseFloat($('offset_z').value) || 0
    }
    NUI('coordsAddOffset', payload)
  })

  $('btnRotatePreview').addEventListener('click', ()=>{
    const delta = parseFloat($('rotate_delta').value) || 0
    NUI('coordsRotate', { delta })
  })

  pointRadius.addEventListener('change', ()=>{
    const radius = parseFloat(pointRadius.value)
    if(!isNaN(radius)){
      NUI('coordsSetRadius', { radius })
    }
  })

  pointHeading.addEventListener('change', ()=>{
    const heading = parseFloat(pointHeading.value)
    if(!isNaN(heading)){
      NUI('coordsSetHeading', { heading })
    }
  })

  pointUsage.addEventListener('change', ()=>{
    NUI('coordsSetUsage', { usage: pointUsage.value })
  })

  $('btnStoreSpawn').addEventListener('click', ()=>{
    pointUsage.value = 'spawn'
    NUI('coordsSetUsage', { usage: 'spawn' })
  })

  $('btnConfirmPreview').addEventListener('click', ()=>{
    NUI('coordsConfirm', { usage: pointUsage.value }).then(res=>{
      if(res && res.ok){
        state.confirmed = res.snapshot
        coordsPreview.textContent = formatSnapshot(res.snapshot)
      }
    })
  })

  $('btnAddMulti').addEventListener('click', ()=>{
    const target = state.confirmed || state.preview
    if(!target){
      alert("Confirme la prévisualisation avant d'ajouter le multi-spawn.")
      return
    }
    addMulti(target)
  })

  $('btnCreatePoint').addEventListener('click', ()=>{
    if(!state.capabilities.canManage){
      alert('Permission refusée.')
      return
    }
    if(!state.confirmed){
      alert('Confirme la prévisualisation avant de créer le point.')
      return
    }
    const payload = buildPointPayload(state.confirmed)
    if(!payload.job_id){
      alert('Job ID requis.')
      return
    }
    if(!payload.label && !confirm('Créer sans label ?')){
      return
    }
    NUI('validatePoint', payload).then(res=>{
      if(res && res.ok){
        const sanitized = Object.assign({}, res.sanitized || {}, {
          label: payload.label,
          type: payload.type
        })
        NUI('createPoint', sanitized).then(()=>{
          if(state.pointsFilter === payload.job_id){
            NUI('requestPoints', { job_id: state.pointsFilter })
          }
        })
      } else {
        alert(`Validation échouée: ${res && res.reason ? res.reason : 'inconnue'}`)
      }
    })
  })

  qsa('#modeSegment button').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      NUI('coordsSetMode', { mode: btn.dataset.mode })
    })
  })

  $('btnLoadPoints').addEventListener('click', ()=>{
    const value = pointsFilterSelect ? pointsFilterSelect.value : ''
    const jobId = parseInt(value, 10)
    if(!jobId){
      alert('Choisis un job Outlaw pour charger les points.')
      return
    }
    state.pointsFilter = jobId
    NUI('requestPoints', { job_id: jobId })
  })

  $('btnRefreshPoints').addEventListener('click', ()=>{
    if(!state.pointsFilter && pointsFilterSelect){
      const value = parseInt(pointsFilterSelect.value, 10)
      if(value){
        state.pointsFilter = value
      }
    }
    if(state.pointsFilter){
      NUI('requestPoints', { job_id: state.pointsFilter })
    }
  })

  function renderPoints(list){
    const container = $('pointsList')
    container.innerHTML = ''
    const points = list || []
    if(points.length === 0){
      container.innerHTML = '<p class="empty">Aucun point enregistré pour ce job.</p>'
      return
    }
    points.forEach(point=>{
      const x = Number(point.x) || 0
      const y = Number(point.y) || 0
      const z = Number(point.z) || 0
      const heading = Number(point.heading) || 0
      const radius = Number(point.radius) || 0
      const job = state.jobByOutlawId[point.job_id] || null
      let meta = point.meta || {}
      if(typeof meta === 'string'){
        try { meta = JSON.parse(meta) || {} } catch(e){ meta = {} }
      }
      const mode = point.mode || meta.mode || 'point'
      const usage = point.usage || meta.usage || 'point'
      const item = document.createElement('div')
      item.className = 'item'
      const jobLabel = job ? `${job.label} (${job.name})` : `Job ${point.job_id}`
      item.innerHTML = `<div class="title">#${point.id} • ${point.label || '(sans label)'} <small>${jobLabel}</small></div>`
      const metaInfo = document.createElement('div')
      metaInfo.className = 'meta'
      metaInfo.textContent = `Type: ${point.type} • Mode: ${mode} • Usage: ${usage} • Rayon: ${radius.toFixed(1)}`
      const coordInfo = document.createElement('div')
      coordInfo.className = 'meta secondary'
      coordInfo.textContent = `${x.toFixed(2)}, ${y.toFixed(2)}, ${z.toFixed(2)} • h ${heading.toFixed(1)}`
      item.append(metaInfo, coordInfo)

      const actions = document.createElement('div')
      actions.className = 'actions'
      const previewBtn = document.createElement('button')
      previewBtn.className = 'small ghost'
      previewBtn.textContent = 'Prévisualiser'
      previewBtn.addEventListener('click', ()=>{
        const base = meta.base || { x, y, z, heading }
        const offset = meta.offset || { x: 0, y: 0, z: 0 }
        const snapshot = {
          x,
          y,
          z,
          heading,
          radius,
          mode,
          usage,
          offset,
          base,
          snapped: meta.snapped || false
        }
        NUI('coordsLoadSnapshot', { snapshot })
      })
      const tpBtn = document.createElement('button')
      tpBtn.className = 'small ghost'
      tpBtn.textContent = 'Téléporter'
      tpBtn.addEventListener('click', ()=>{
        NUI('coordsTeleport', { x, y, z, heading })
      })
      const cloneBtn = document.createElement('button')
      cloneBtn.className = 'small ghost'
      cloneBtn.textContent = 'Cloner'
      cloneBtn.addEventListener('click', ()=>{
        addMulti({ x, y, z, heading, radius, mode, usage, offset: meta.offset || {x:0,y:0,z:0}, base: meta.base || {x,y,z,heading}, snapped: meta.snapped || false })
      })
      actions.append(previewBtn,tpBtn,cloneBtn)
      item.append(actions)
      container.appendChild(item)
    })
  }
  $('btnMigrationsRefresh').addEventListener('click', ()=>{
    NUI('migrations:refresh')
  })

  $('btnMigrationsApply').addEventListener('click', ()=>{
    NUI('migrations:apply')
  })

  $('btnMigrationForce').addEventListener('click', ()=>{
    const name = $('migrationSelect').value
    if(!name){ alert('Choisis une migration.'); return }
    if(confirm(`Forcer la migration ${name} ?`)){
      NUI('migrations:force', { name })
    }
  })

  function renderMigrations(list){
    state.migrations = list || []
    const select = $('migrationSelect')
    select.innerHTML = '<option value="">Choisir une migration</option>'
    const table = $('migrationsTable')
    table.innerHTML = ''
    const header = document.createElement('div')
    header.className = 'row header'
    header.innerHTML = '<div>Migration</div><div>Statut</div><div>Appliquée</div>'
    table.appendChild(header)
    state.migrations.forEach(item=>{
      const opt = document.createElement('option')
      opt.value = item.name
      opt.textContent = item.name
      select.appendChild(opt)
      const row = document.createElement('div')
      row.className = 'row'
      let status = 'En attente'
      if(item.missing){ status = 'Fichier manquant' }
      else if(item.applied && !item.checksumMismatch){ status = 'Appliquée' }
      else if(item.checksumMismatch){ status = 'Checksum différent' }
      const applied = item.applied_at ? `${item.applied_at}<br><small>${item.applied_by||'-'}</small>` : '-'
      row.innerHTML = `<div>${item.name}</div><div>${status}</div><div>${applied}</div>`
      table.appendChild(row)
    })
  }

  function renderMigrationResult(results){
    const log = $('migrationLogs')
    log.innerHTML = ''
    ;(results||[]).forEach(res=>{
      const line = document.createElement('div')
      line.textContent = `${res.name}: ${res.status}${res.error ? ' ('+res.error+')' : ''}`
      log.appendChild(line)
    })
  }

  window.addEventListener('message', (ev)=>{
    const d = ev.data || {}
    if(d.action === 'open'){
      state.capabilities = d.capabilities || state.capabilities
      applyBootstrapData(d.bootstrap || {})
      ensureManageAccess()
      showApp()
      requestJobs()
      if(state.capabilities.canApplyMigrations){
        NUI('migrations:refresh')
      }
    }
    if(d.action === 'jobsList'){
      renderJobs(d.jobs || [])
    }
    if(d.action === 'coordsPreviewState'){
      updatePreview(d.snapshot || null)
    }
    if(d.action === 'coordsHistory'){
      updateHistory(d.items || [])
    }
    if(d.action === 'coordsQuickCapture'){
      if(d.snapshot){
        state.history.unshift(d.snapshot)
        updateHistory(state.history)
      }
    }
    if(d.action === 'pointsList'){
      renderPoints(d.points || [])
    }
    if(d.action === 'migrations:list'){
      renderMigrations(d.migrations || [])
    }
    if(d.action === 'migrations:result'){
      renderMigrationResult(d.results || [])
    }
  })

  applyBootstrapData(state.bootstrap)
  ensureManageAccess()
})()
