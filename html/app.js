(() => {
  const nui = (action, data = {}) =>
    fetch(`https://${GetParentResourceName()}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(data)
    })
      .then((res) => res.json())
      .catch(() => ({}))

  const appEl = document.getElementById('app')
  const jobsListEl = document.getElementById('jobs-list')
  const esxInfoEl = document.getElementById('esx-info')
  const newJobBtn = document.getElementById('new-job-btn')
  const jobForm = document.getElementById('job-form')
  const jobFormTitle = document.getElementById('job-form-title')
  const jobDeleteBtn = document.getElementById('job-delete-btn')
  const jobPermissionEl = document.getElementById('job-permission')
  const refreshBtn = document.getElementById('refresh-btn')
  const closeBtn = document.getElementById('close-btn')
  const colorSelect = document.getElementById('job-color')
  const iconSelect = document.getElementById('job-icon')

  const pointsListEl = document.getElementById('points-list')
  const newPointBtn = document.getElementById('new-point-btn')
  const pointForm = document.getElementById('point-form')
  const pointFormTitle = document.getElementById('point-form-title')
  const pointDeleteBtn = document.getElementById('point-delete-btn')
  const getCoordsBtn = document.getElementById('get-coords-btn')
  const pointTypeSelect = document.getElementById('point-type')
  const pointUsageSelect = document.getElementById('point-usage')

  const state = {
    visible: false,
    canManage: false,
    jobs: [],
    esxJobs: [],
    options: {
      icons: [],
      colors: [],
      defaults: {},
      pointTypes: [],
      pointUsage: []
    },
    selectedJobId: null,
    jobForm: {},
    points: [],
    pointForm: {}
  }

  const defaultJobForm = () => {
    const defaults = (state.options && state.options.defaults) || {}
    return {
      id: null,
      job_name: '',
      label: '',
      tag: defaults.tag || '',
      color: defaults.color || '#ff9d0b',
      icon: defaults.icon || 'fa-briefcase',
      society_name: defaults.societyPrefix || 'society_',
      default_salary: defaults.salary || 0,
      whitelisted: false
    }
  }

  const defaultPointForm = () => ({
    id: null,
    job_id: state.selectedJobId,
    label: '',
    type: (state.options.pointTypes[0] && state.options.pointTypes[0].value) || 'collect',
    usage_mode: (state.options.pointUsage[0] && state.options.pointUsage[0].value) || 'point',
    radius: 0,
    x: '',
    y: '',
    z: '',
    heading: 0,
    item: '',
    reward: ''
  })

  const setVisible = (value) => {
    state.visible = value
    if (value) {
      appEl.classList.remove('hidden')
    } else {
      appEl.classList.add('hidden')
    }
  }

  const fillSelect = (el, items, selected) => {
    el.innerHTML = ''
    items.forEach((item) => {
      const option = document.createElement('option')
      option.value = item.value
      option.textContent = item.label
      if (item.value === selected) {
        option.selected = true
      }
      el.appendChild(option)
    })
  }

  const syncJobForm = () => {
    fillSelect(colorSelect, state.options.colors || [], state.jobForm.color)
    fillSelect(iconSelect, state.options.icons || [], state.jobForm.icon)

    jobForm.job_name.value = state.jobForm.job_name || ''
    jobForm.label.value = state.jobForm.label || ''
    jobForm.tag.value = state.jobForm.tag || ''
    jobForm.color.value = state.jobForm.color || ''
    jobForm.icon.value = state.jobForm.icon || ''
    jobForm.society_name.value = state.jobForm.society_name || ''
    jobForm.default_salary.value = state.jobForm.default_salary || 0
    jobForm.whitelisted.value = state.jobForm.whitelisted ? '1' : '0'

    if (state.jobForm.id) {
      jobFormTitle.textContent = `Modifier le job #${state.jobForm.id}`
      jobDeleteBtn.disabled = !state.canManage
    } else {
      jobFormTitle.textContent = 'Créer un job'
      jobDeleteBtn.disabled = true
    }

    const permissionText = state.canManage
      ? 'Vous pouvez créer ou modifier des jobs.'
      : 'Permission requise pour créer/modifier des jobs.'
    jobPermissionEl.textContent = permissionText
    jobForm.querySelectorAll('input, select, button').forEach((input) => {
      if (input === jobDeleteBtn) return
      input.disabled = !state.canManage && input.tagName !== 'BUTTON'
    })
    jobForm.querySelectorAll('button').forEach((btn) => {
      if (btn === jobDeleteBtn) return
      btn.disabled = !state.canManage
    })
    newJobBtn.disabled = !state.canManage
  }

  const renderJobs = () => {
    jobsListEl.innerHTML = ''
    if (!state.jobs.length) {
      const empty = document.createElement('p')
      empty.className = 'notice'
      empty.textContent = 'Aucun job enregistré.'
      jobsListEl.appendChild(empty)
    }

    state.jobs.forEach((job) => {
      const card = document.createElement('div')
      card.className = 'job-card' + (state.selectedJobId === job.id ? ' active' : '')
      card.innerHTML = `
        <h3>${job.label || job.job_name}</h3>
        <div class="meta">${job.job_name} · ${job.tag || 'tag non défini'}</div>
      `
      card.addEventListener('click', () => {
        state.selectedJobId = job.id
        state.jobForm = { ...defaultJobForm(), ...job, whitelisted: job.whitelisted == 1 }
        state.pointForm = defaultPointForm()
        syncJobForm()
        syncPointForm()
        renderJobs()
        requestPoints(job.id)
      })
      jobsListEl.appendChild(card)
    })

    const esxCount = state.esxJobs.length
    esxInfoEl.textContent = esxCount
      ? `${esxCount} jobs enregistrés dans la table jobs.`
      : 'Table jobs vide ou non trouvée.'
  }

  const syncPointForm = () => {
    fillSelect(pointTypeSelect, state.options.pointTypes || [], state.pointForm.type)
    fillSelect(pointUsageSelect, state.options.pointUsage || [], state.pointForm.usage_mode)

    pointForm.label.value = state.pointForm.label || ''
    pointForm.type.value = state.pointForm.type || ''
    pointForm.usage_mode.value = state.pointForm.usage_mode || ''
    pointForm.radius.value = state.pointForm.radius || 0
    pointForm.x.value = state.pointForm.x || ''
    pointForm.y.value = state.pointForm.y || ''
    pointForm.z.value = state.pointForm.z || ''
    pointForm.heading.value = state.pointForm.heading || 0
    pointForm.item.value = state.pointForm.item || ''
    pointForm.reward.value = state.pointForm.reward || ''

    if (state.pointForm.id) {
      pointFormTitle.textContent = `Modifier le point #${state.pointForm.id}`
      pointDeleteBtn.disabled = !state.canManage
    } else {
      pointFormTitle.textContent = 'Ajouter un point'
      pointDeleteBtn.disabled = true
    }

    const locked = !state.canManage || !state.selectedJobId
    pointForm.querySelectorAll('input, select, button').forEach((input) => {
      if (input === getCoordsBtn) return
      if (input === pointDeleteBtn) return
      input.disabled = locked && input.tagName !== 'BUTTON'
    })
    getCoordsBtn.disabled = locked
    newPointBtn.disabled = locked
  }

  const renderPoints = () => {
    pointsListEl.innerHTML = ''
    if (!state.points.length) {
      const empty = document.createElement('p')
      empty.className = 'notice'
      empty.textContent = 'Aucun point pour ce job.'
      pointsListEl.appendChild(empty)
    }

    state.points.forEach((point) => {
      const row = document.createElement('div')
      row.className = 'point-row'
      const coordText = `X:${Number(point.x || 0).toFixed(2)} Y:${Number(point.y || 0).toFixed(2)} Z:${Number(point.z || 0).toFixed(2)} R:${Number(point.radius || 0).toFixed(1)}`
      row.innerHTML = `
        <div class="row-top">
          <div>
            <h4>${point.label || point.type}</h4>
            <div class="coords">${point.type} · ${point.usage_mode} · ${coordText}</div>
          </div>
          <div class="row-actions">
            <button class="ghost edit">Éditer</button>
            <button class="danger delete">Supprimer</button>
          </div>
        </div>
      `
      const editBtn = row.querySelector('.edit')
      const delBtn = row.querySelector('.delete')
      editBtn.disabled = !state.canManage
      delBtn.disabled = !state.canManage
      editBtn.addEventListener('click', () => {
        state.pointForm = {
          id: point.id,
          job_id: point.job_id,
          label: point.label,
          type: point.type,
          usage_mode: point.usage_mode,
          radius: point.radius,
          x: point.x,
          y: point.y,
          z: point.z,
          heading: point.heading,
          item: (point.meta && point.meta.item) || '',
          reward: (point.meta && point.meta.reward) || ''
        }
        syncPointForm()
      })
      delBtn.addEventListener('click', () => {
        if (!state.canManage) return
        nui('creator:deletePoint', { id: point.id, job_id: point.job_id })
      })
      pointsListEl.appendChild(row)
    })
  }

  const requestPoints = (jobId) => {
    state.points = []
    renderPoints()
    nui('creator:requestPoints', { job_id: jobId })
  }

  newJobBtn.addEventListener('click', () => {
    state.selectedJobId = null
    state.jobForm = defaultJobForm()
    state.points = []
    renderJobs()
    renderPoints()
    syncJobForm()
    state.pointForm = defaultPointForm()
    syncPointForm()
  })

  jobForm.addEventListener('submit', (event) => {
    event.preventDefault()
    if (!state.canManage) return
    const formData = new FormData(jobForm)
    const payload = Object.fromEntries(formData.entries())
    payload.default_salary = Number(payload.default_salary || 0)
    payload.whitelisted = payload.whitelisted === '1'
    if (state.jobForm.id) {
      payload.id = state.jobForm.id
      nui('creator:updateJob', payload)
    } else {
      nui('creator:createJob', payload)
    }
  })

  jobDeleteBtn.addEventListener('click', () => {
    if (!state.canManage || !state.jobForm.id) return
    nui('creator:deleteJob', { id: state.jobForm.id })
  })

  newPointBtn.addEventListener('click', () => {
    if (!state.selectedJobId) return
    state.pointForm = defaultPointForm()
    syncPointForm()
  })

  pointForm.addEventListener('submit', (event) => {
    event.preventDefault()
    if (!state.canManage || !state.selectedJobId) return
    const formData = new FormData(pointForm)
    const payload = Object.fromEntries(formData.entries())
    payload.job_id = state.selectedJobId
    payload.radius = Number(payload.radius || 0)
    payload.x = Number(payload.x || 0)
    payload.y = Number(payload.y || 0)
    payload.z = Number(payload.z || 0)
    payload.heading = Number(payload.heading || 0)
    if (state.pointForm.id) {
      payload.id = state.pointForm.id
      nui('creator:updatePoint', payload)
    } else {
      nui('creator:createPoint', payload)
    }
  })

  pointDeleteBtn.addEventListener('click', () => {
    if (!state.canManage || !state.pointForm.id) return
    nui('creator:deletePoint', { id: state.pointForm.id, job_id: state.selectedJobId })
  })

  getCoordsBtn.addEventListener('click', async () => {
    if (!state.canManage) return
    const res = await nui('creator:getCoords')
    if (res && res.coords) {
      pointForm.x.value = Number(res.coords.x).toFixed(2)
      pointForm.y.value = Number(res.coords.y).toFixed(2)
      pointForm.z.value = Number(res.coords.z).toFixed(2)
      pointForm.heading.value = Number(res.coords.heading).toFixed(1)
    }
  })

  refreshBtn.addEventListener('click', () => {
    nui('creator:refresh')
  })

  closeBtn.addEventListener('click', () => {
    nui('creator:close')
  })

  window.addEventListener('message', (event) => {
    const data = event.data || {}
    if (data.action === 'open') {
      setVisible(true)
    } else if (data.action === 'close') {
      setVisible(false)
      state.selectedJobId = null
      state.jobs = []
      state.points = []
    } else if (data.action === 'state') {
      const payload = data.payload || {}
      state.canManage = !!payload.canManage
      state.jobs = payload.jobs || []
      state.esxJobs = payload.esxJobs || []
      state.options = payload.options || state.options

      if (!state.jobs.length) {
        state.selectedJobId = null
        state.jobForm = defaultJobForm()
      } else {
        if (!state.selectedJobId) {
          state.selectedJobId = state.jobs[0].id
        }
        const selected = state.jobs.find((job) => job.id === state.selectedJobId)
        if (selected) {
          state.jobForm = { ...defaultJobForm(), ...selected }
          requestPoints(selected.id)
        } else {
          state.selectedJobId = state.jobs[0].id
          const first = state.jobs[0]
          state.jobForm = { ...defaultJobForm(), ...first }
          requestPoints(first.id)
        }
      }

      state.pointForm = defaultPointForm()
      syncJobForm()
      syncPointForm()
      renderJobs()
      renderPoints()
      setVisible(true)
    } else if (data.action === 'points') {
      const payload = data.payload || {}
      if (state.selectedJobId === payload.jobId) {
        state.points = payload.points || []
        renderPoints()
        state.pointForm = defaultPointForm()
        syncPointForm()
      }
    } else if (data.action === 'notify') {
      // handled in client as well, keep optional toast here later
    }
  })
})()
