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
    points: [],
    pointsFilter: null,
    migrations: [],
    migrationResult: []
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
    const payload = {
      job_name: $('job_name').value.trim(),
      label: $('label').value.trim(),
      tag: $('tag').value.trim(),
      icon: $('icon').value.trim(),
      color: $('color').value.trim(),
      society: $('society').value.trim(),
      default_salary: parseInt($('salary').value,10) || 0
    }
    NUI('createJob', payload).then(()=>{
      requestJobs()
    })
  })

  $('btnRefreshJobs').addEventListener('click', requestJobs)

  function renderJobs(list){
    const c = $('jobsContainer')
    c.innerHTML = ''
    ;(list||[]).forEach(j=>{
      const el = document.createElement('div')
      el.className = 'item'
      el.innerHTML = `<div class="title">${j.label} <small>(${j.job_name})</small></div>
                      <div class="meta">id: ${j.id} • society: ${j.society_name||'-'} • salaire: ${j.default_salary||0}</div>`
      c.appendChild(el)
    })
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
    const jobId = parseInt($('points_job_filter').value,10)
    if(!jobId){ alert('ID job requis pour charger.'); return }
    state.pointsFilter = jobId
    NUI('requestPoints', { job_id: jobId })
  })

  $('btnRefreshPoints').addEventListener('click', ()=>{
    if(state.pointsFilter){
      NUI('requestPoints', { job_id: state.pointsFilter })
    }
  })

  function renderPoints(list){
    const container = $('pointsList')
    container.innerHTML = ''
    ;(list||[]).forEach(point=>{
      const x = Number(point.x) || 0
      const y = Number(point.y) || 0
      const z = Number(point.z) || 0
      const heading = Number(point.heading) || 0
      const radius = Number(point.radius) || 0
      let meta = {}
      if(point.meta){
        if(typeof point.meta === 'string'){
          try { meta = JSON.parse(point.meta) || {} } catch(e){ meta = {} }
        } else {
          meta = point.meta
        }
      }
      const item = document.createElement('div')
      item.className = 'item'
      item.innerHTML = `<div class="title">#${point.id} • ${point.label || '(sans label)'} (${point.type})</div>
                        <div class="meta">${x.toFixed(2)}, ${y.toFixed(2)}, ${z.toFixed(2)} • h ${heading.toFixed(1)} • r ${radius.toFixed(1)}</div>`
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
          mode: meta.mode || 'point',
          usage: meta.usage || 'point',
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
        addMulti({ x, y, z, heading, radius, mode: meta.mode || 'point', usage: meta.usage || 'spawn', offset: meta.offset || {x:0,y:0,z:0}, base: meta.base || {x,y,z,heading}, snapped: meta.snapped || false })
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

  ensureManageAccess()
})()
