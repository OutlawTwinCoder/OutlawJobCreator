// html/app.js (v2)
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

  function showApp(){ $('app').style.display = 'block' }
  function hideApp(){ $('app').style.display = 'none' }

  // Tabs
  qsa('.tab').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      qsa('.tab').forEach(b=>b.classList.remove('active'))
      btn.classList.add('active')
      const tab = btn.dataset.tab
      qsa('.panel').forEach(p=>p.classList.remove('active'))
      qs(`#tab-${tab}`).classList.add('active')
    })
  })

  // Close
  $('close').addEventListener('click', ()=>{
    NUI('close').then(()=>hideApp())
  })

  // Jobs
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

  function requestJobs(){
    NUI('requestJobs')
  }

  function renderJobs(list){
    const c = $('jobsContainer')
    c.innerHTML = ''
    ;(list||[]).forEach(j=>{
      const el = document.createElement('div')
      el.className = 'item'
      el.innerHTML = `<div class="title">${j.label} <small>(${j.job_name})</small></div>
                      <div class="meta">id: ${j.id} • society: ${j.society_name||'-'}</div>`
      c.appendChild(el)
    })
  }

  // Points
  $('btnGetCoords').addEventListener('click', ()=>{
    NUI('getCoords').then(data=>{
      window.__coords = data
      $('coordsPreview').textContent = JSON.stringify(data, null, 2)
    })
  })

  $('btnCreatePoint').addEventListener('click', ()=>{
    if(!window.__coords){ alert('Clique Get Coords d'abord.'); return }
    const p = {
      job_id: parseInt($('point_job_id').value,10) || 0,
      label: $('point_label').value || '',
      type: $('point_type').value || 'collect',
      radius: parseFloat($('point_radius').value) || 2.0,
      x: window.__coords.x, y: window.__coords.y, z: window.__coords.z, heading: window.__coords.heading,
      meta: {}
    }
    NUI('createPoint', p).then(()=>{
      $('coordsPreview').textContent = 'Point envoyé au serveur.'
    })
  })

  // Messages from client
  window.addEventListener('message', (ev)=>{
    const d = ev.data || {}
    if (d.action === 'open'){ showApp(); requestJobs() }
    if (d.action === 'jobsList'){ renderJobs(d.jobs || []) }
  })
})()
