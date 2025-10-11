// html/app.js — Fishing Atelier prototype v1
(function(){
  const state = {
    baseStats: {
      puissance: 52,
      precision: 38,
      vitesse: 46,
      solidite: 60,
      chance: 14
    },
    inventory: [
      { id: 'fishing_reel_apex', label: 'Moulinet Apex Mk.I', qty: 1, rarity: 'Rare', slot: 'reel' },
      { id: 'fishing_reel_shadow', label: 'Moulinet Shadowline', qty: 0, rarity: 'Épique', slot: 'reel' },
      { id: 'fishing_line_softwave', label: 'Fil Softwave', qty: 3, rarity: 'Commun', slot: 'line' },
      { id: 'fishing_line_kevlar', label: 'Fil Kevlar-L', qty: 1, rarity: 'Rare', slot: 'line' },
      { id: 'fishing_hook_bronze', label: 'Hameçon Bronze #6', qty: 4, rarity: 'Commun', slot: 'hook' },
      { id: 'fishing_hook_forge', label: 'Hameçon Forgé #2', qty: 1, rarity: 'Rare', slot: 'hook' },
      { id: 'fishing_float_horizon', label: 'Flotteur Horizon', qty: 2, rarity: 'Commun', slot: 'float' },
      { id: 'fishing_handle_cork', label: 'Poignée Liège Sculptée', qty: 1, rarity: 'Commun', slot: 'handle' },
      { id: 'fishing_handle_carbon', label: 'Poignée Carbone Tressé', qty: 0, rarity: 'Épique', slot: 'handle' },
      { id: 'fishing_charm_talisman', label: 'Breloque Talisman', qty: 1, rarity: 'Rare', slot: 'charm' }
    ],
    slots: [
      {
        id: 'reel',
        label: 'Moulinet',
        description: 'Contrôle la vitesse de récupération et la tension lors des combats intenses.',
        options: [
          { id: 'apex_mk1', name: 'Moulinet Apex Mk.I', itemId: 'fishing_reel_apex', rarity: 'Rare', stats: { vitesse: 6, precision: 3 } },
          { id: 'shadowline', name: 'Moulinet Shadowline', itemId: 'fishing_reel_shadow', rarity: 'Épique', stats: { vitesse: 8, puissance: 4, chance: 2 } }
        ]
      },
      {
        id: 'line',
        label: 'Fil',
        description: 'Impacte la résistance, le contrôle des prises et les risques de rupture.',
        options: [
          { id: 'softwave', name: 'Fil Softwave', itemId: 'fishing_line_softwave', rarity: 'Commun', stats: { solidite: 6, precision: 2 } },
          { id: 'kevlar', name: 'Fil Kevlar-L', itemId: 'fishing_line_kevlar', rarity: 'Rare', stats: { solidite: 10, puissance: 3 } }
        ]
      },
      {
        id: 'hook',
        label: 'Hameçon',
        description: 'Modifie la précision du ferrage et la probabilité de conserver les prises.',
        options: [
          { id: 'bronze', name: 'Hameçon Bronze #6', itemId: 'fishing_hook_bronze', rarity: 'Commun', stats: { precision: 4, chance: 1 } },
          { id: 'forge', name: 'Hameçon Forgé #2', itemId: 'fishing_hook_forge', rarity: 'Rare', stats: { puissance: 5, precision: 6 } }
        ]
      },
      {
        id: 'float',
        label: 'Flotteur',
        description: 'Aide à visualiser les touches et modifie la rapidité des réactions.',
        options: [
          { id: 'horizon', name: 'Flotteur Horizon', itemId: 'fishing_float_horizon', rarity: 'Commun', stats: { chance: 2, precision: 2 } }
        ]
      },
      {
        id: 'handle',
        label: 'Poignée',
        description: 'Apporte du confort et de la stabilité pour les sessions prolongées.',
        options: [
          { id: 'cork', name: 'Poignée Liège Sculptée', itemId: 'fishing_handle_cork', rarity: 'Commun', stats: { solidite: 4, chance: 1 } },
          { id: 'carbon', name: 'Poignée Carbone Tressé', itemId: 'fishing_handle_carbon', rarity: 'Épique', stats: { solidite: 6, puissance: 3 } }
        ]
      },
      {
        id: 'charm',
        label: 'Breloque',
        description: 'Bonus passifs lors des lancers critiques ou des prises rares.',
        options: [
          { id: 'talisman', name: 'Breloque Talisman', itemId: 'fishing_charm_talisman', rarity: 'Rare', stats: { chance: 5 } }
        ]
      }
    ],
    equipped: {}
  };

  const elements = {
    inventory: document.getElementById('inventoryList'),
    slotList: document.getElementById('slotList'),
    statsGrid: document.getElementById('statsGrid'),
    toast: document.getElementById('toast'),
    hotspots: Array.from(document.querySelectorAll('.hotspot'))
  };

  const statMeta = {
    puissance: { label: 'Puissance', suffix: '' },
    precision: { label: 'Précision', suffix: '' },
    vitesse: { label: 'Vitesse', suffix: '' },
    solidite: { label: 'Solidité', suffix: '' },
    chance: { label: 'Chance', suffix: '%' }
  };

  const slotCards = new Map();

  function init(){
    renderInventory();
    renderSlots();
    updateStats();
  }

  function hasItem(itemId){
    const item = state.inventory.find(i => i.id === itemId);
    if(!item) return false;
    const used = usageFor(itemId);
    return item.qty - used > 0;
  }

  function usageFor(itemId){
    return Object.values(state.equipped).filter(opt => opt.itemId === itemId).length;
  }

  function renderInventory(){
    elements.inventory.innerHTML = '';
    state.inventory.forEach(item => {
      const used = usageFor(item.id);
      const available = Math.max(item.qty - used, 0);
      const el = document.createElement('div');
      el.className = 'inventory-item' + (available === 0 ? ' unavailable' : '');
      el.innerHTML = `
        <div>
          <strong>${item.label}</strong>
          <span>${item.rarity} • Slot ${item.slot}</span>
        </div>
        <div class="qty">${available}/${item.qty}</div>
      `;
      elements.inventory.appendChild(el);
    });
  }

  function renderSlots(){
    elements.slotList.innerHTML = '';
    state.slots.forEach(slot => {
      const card = document.createElement('article');
      card.className = 'slot-card';
      const header = document.createElement('header');
      const h3 = document.createElement('h3');
      h3.textContent = slot.label;
      const stateEl = document.createElement('span');
      stateEl.className = 'state';
      stateEl.textContent = 'Aucun module';
      header.appendChild(h3);
      header.appendChild(stateEl);

      const desc = document.createElement('p');
      desc.textContent = slot.description;

      const select = document.createElement('select');
      slot.options.forEach(opt => {
        const option = document.createElement('option');
        option.value = opt.id;
        option.textContent = `${opt.name} (${opt.rarity})`;
        select.appendChild(option);
      });

      const small = document.createElement('small');
      small.textContent = 'Sélectionnez un module compatible';

      const button = document.createElement('button');
      button.className = 'primary';
      button.textContent = 'Équiper';

      card.appendChild(header);
      card.appendChild(desc);
      card.appendChild(select);
      card.appendChild(button);
      card.appendChild(small);

      elements.slotList.appendChild(card);

      slotCards.set(slot.id, { card, header, stateEl, select, button, helper: small, slot });

      select.addEventListener('change', () => refreshSlotAction(slot.id));
      button.addEventListener('click', () => handleSlotAction(slot.id));

      refreshSlotAction(slot.id);
    });
  }

  function getSlotOption(slotId, optionId){
    const slot = state.slots.find(s => s.id === slotId);
    if(!slot) return null;
    return slot.options.find(o => o.id === optionId) || null;
  }

  function handleSlotAction(slotId){
    const ui = slotCards.get(slotId);
    if(!ui) return;
    const mode = ui.button.dataset.mode || 'equip';

    if(mode === 'remove'){
      unequipSlot(slotId);
      return;
    }

    const optionId = ui.select.value;
    const option = getSlotOption(slotId, optionId);
    if(!option){
      toast("Sélection invalide");
      return;
    }
    if(!hasItem(option.itemId)){
      toast("Item manquant dans l'inventaire");
      return;
    }
    equipSlot(slotId, option);
  }

  function equipSlot(slotId, option){
    state.equipped[slotId] = option;
    toast(`${option.name} équipé`);
    refreshSlot(slotId);
  }

  function unequipSlot(slotId){
    const option = state.equipped[slotId];
    if(option){
      delete state.equipped[slotId];
      toast(`${option.name} retiré`);
    }
    refreshSlot(slotId);
  }

  function refreshSlot(slotId){
    refreshSlotAction(slotId);
    renderInventory();
    updateStats();
    updateHotspots();
  }

  function refreshSlotAction(slotId){
    const ui = slotCards.get(slotId);
    if(!ui) return;
    const equipped = state.equipped[slotId] || null;

    if(equipped){
      ui.stateEl.textContent = equipped.name;
      ui.helper.textContent = `Actuellement équipé • ${equipped.rarity}`;
      ui.select.value = equipped.id;
    } else {
      ui.stateEl.textContent = 'Aucun module';
      ui.helper.textContent = 'Sélectionnez un module compatible';
    }

    const selected = getSlotOption(slotId, ui.select.value);
    if(!equipped){
      ui.button.dataset.mode = 'equip';
      ui.button.textContent = 'Équiper';
      ui.button.disabled = !selected || !hasItem(selected.itemId);
    } else if (selected && selected.id !== equipped.id){
      ui.button.dataset.mode = 'replace';
      ui.button.textContent = 'Remplacer';
      ui.button.disabled = !hasItem(selected.itemId);
    } else {
      ui.button.dataset.mode = 'remove';
      ui.button.textContent = 'Retirer';
      ui.button.disabled = false;
    }
  }

  function updateHotspots(){
    elements.hotspots.forEach(btn => {
      const slotId = btn.dataset.slot;
      if(state.equipped[slotId]){
        btn.classList.add('active');
        btn.querySelector('span').textContent = '•';
      } else {
        btn.classList.remove('active');
        btn.querySelector('span').textContent = '+';
      }
    });
  }

  function computeStats(){
    const totals = { ...state.baseStats };
    Object.values(state.equipped).forEach(opt => {
      Object.entries(opt.stats).forEach(([key, value]) => {
        totals[key] = (totals[key] || 0) + value;
      });
    });
    return totals;
  }

  function updateStats(){
    const totals = computeStats();
    elements.statsGrid.innerHTML = '';
    Object.entries(statMeta).forEach(([key, meta]) => {
      const base = state.baseStats[key] || 0;
      const value = totals[key] || base;
      const delta = value - base;
      const card = document.createElement('div');
      card.className = 'stat-card';
      const title = document.createElement('h4');
      title.textContent = meta.label;
      const valueEl = document.createElement('div');
      valueEl.className = 'value';
      valueEl.innerHTML = `${value}<span>${meta.suffix}</span>`;
      card.appendChild(title);
      card.appendChild(valueEl);
      if(delta !== 0){
        const deltaEl = document.createElement('div');
        deltaEl.className = 'delta ' + (delta > 0 ? 'positive' : 'negative');
        deltaEl.textContent = `${delta > 0 ? '+' : ''}${delta}`;
        card.appendChild(deltaEl);
      }
      elements.statsGrid.appendChild(card);
    });
  }

  let toastTimeout;
  function toast(message){
    if(!elements.toast) return;
    elements.toast.textContent = message;
    elements.toast.classList.add('show');
    clearTimeout(toastTimeout);
    toastTimeout = setTimeout(() => {
      elements.toast.classList.remove('show');
    }, 2200);
  }

  init();
})();
