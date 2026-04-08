'use strict';

const IS_NUI = typeof GetParentResourceName === 'function';
const RESOURCE = IS_NUI ? GetParentResourceName() : 'sofapotato_gearbox';

// ── State ─────────────────────────────────────────────────
const state = {
    visible: false,
    mode: 'settings', // 'settings' | 'upgrade'
    pendingBuyKey: null,
    pendingBuyLabel: null,
    pendingBuyPrice: 0,
    defaultGearRatios: [],
};

const GEAR_NAMES = ['1檔', '2檔', '3檔', '4檔', '5檔', '6檔', '7檔', '8檔'];

// ── DOM refs ──────────────────────────────────────────────
const el = {
    app:          document.getElementById('app'),
    subtitle:     document.getElementById('gb-subtitle'),
    modePill:     document.getElementById('gb-mode-pill'),
    btnClose:     document.getElementById('btnClose'),

    // Status
    statusName:   document.getElementById('status-name'),
    statusBadges: document.getElementById('status-badges'),
    valClutch:    document.getElementById('val-clutch'),
    barClutch:    document.getElementById('bar-clutch'),
    tempBlock:    document.getElementById('temp-block'),
    valTemp:      document.getElementById('val-temp'),
    barTemp:      document.getElementById('bar-temp'),

    // Assists
    cardAssists:  document.getElementById('card-assists'),
    togAntiStall: document.getElementById('tog-antistall'),
    togRevMatch:  document.getElementById('tog-revmatch'),
    togDrift:     document.getElementById('tog-drift'),
    launchInfo:   document.getElementById('launch-info'),
    launchStatus: document.getElementById('launch-status'),

    // Actions
    btnRepair:    document.getElementById('btn-repair'),
    repairCost:   document.getElementById('repair-cost'),

    // Gear ratio editor
    cardGearRatio: document.getElementById('card-gearratio'),
    grGrid:        document.getElementById('gr-grid'),
    btnGrResetAll: document.getElementById('btn-gr-reset-all'),
    btnGrApply:    document.getElementById('btn-gr-apply'),

    // List
    listTitle:    document.getElementById('list-title'),
    listHint:     document.getElementById('list-hint'),
    transmList:   document.getElementById('transm-list'),

    // Modal
    modal:        document.getElementById('modal'),
    modalText:    document.getElementById('modal-text'),
    btnModalClose:   document.getElementById('btnModalClose'),
    btnModalCancel:  document.getElementById('btnModalCancel'),
    btnModalConfirm: document.getElementById('btnModalConfirm'),
};

// ── NUI bridge ───────────────────────────────────────────
function postNui(endpoint, payload) {
    if (!IS_NUI) return Promise.resolve();
    return fetch(`https://${RESOURCE}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload ?? {}),
    }).catch(() => {});
}

// ── Helpers ───────────────────────────────────────────────
function esc(str) {
    return String(str ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
}

function formatMoney(n) {
    return '$' + Number(n).toLocaleString();
}

function typeBadgeHtml(type) {
    if (!type) return `<span class="gb-badge gb-badge-stock">STOCK</span>`;
    const cls = { AT: 'gb-badge-at', ATMT: 'gb-badge-atmt', MT: 'gb-badge-mt' }[type] || 'gb-badge-stock';
    return `<span class="gb-badge ${cls}">${esc(type)}</span>`;
}

// ── Visibility ────────────────────────────────────────────
function show() {
    state.visible = true;
    el.app.classList.remove('gb-hidden');
    el.app.setAttribute('aria-hidden', 'false');
}

function hide() {
    state.visible = false;
    el.app.classList.add('gb-hidden');
    el.app.setAttribute('aria-hidden', 'true');
    hideModal();
}

// ── Update clutch health bar ──────────────────────────────
function updateClutchBar(health) {
    const pct = Math.max(0, Math.min(100, Number(health) || 0));
    el.valClutch.textContent = pct.toFixed(0) + '%';
    el.barClutch.style.width = pct + '%';
    el.barClutch.className = 'gb-bar-fill';
    if (pct < 15)      el.barClutch.classList.add('is-danger');
    else if (pct < 40) el.barClutch.classList.add('is-warn');
}

// ── Update temperature bar ────────────────────────────────
const TEMP_MAX = 130; // display ceiling for bar
function updateTempBar(temp) {
    const t = Number(temp) || 0;
    const pct = Math.max(0, Math.min(100, (t / TEMP_MAX) * 100));
    el.valTemp.textContent = t.toFixed(0) + '°C';
    el.barTemp.style.width = pct + '%';
    el.barTemp.className = 'gb-bar-fill';
    if (t >= 120)      el.barTemp.classList.add('is-over');
    else if (t >= 100) el.barTemp.classList.add('is-hot');
    else if (t >= 80)  el.barTemp.classList.add('is-warn');
    else               el.barTemp.classList.add('gb-bar-fill'); // green default
}

// ── Update status panel ───────────────────────────────────
function updateStatus(s) {
    el.statusName.textContent = s.transmLabel || '原廠離合器';

    el.statusBadges.innerHTML = [
        typeBadgeHtml(s.transmType),
        s.transmMaxGear > 0 ? `<span class="gb-badge gb-badge-stock">${s.transmMaxGear}速</span>` : '',
    ].join('');

    updateClutchBar(s.clutchHealth ?? 100);

    if (s.isStock || !s.transmType) {
        el.tempBlock.style.display = 'none';
    } else {
        el.tempBlock.style.display = '';
        updateTempBar(s.gearboxTemp ?? 0);
    }
}

// ── Update assist toggles ─────────────────────────────────
function updateToggles(s) {
    setToggle(el.togAntiStall, s.antiStall);
    setToggle(el.togRevMatch,  s.revMatch);

    // Drift: only show for MT
    if (s.isMT) {
        el.togDrift.classList.remove('gb-hidden');
        setToggle(el.togDrift, s.driftEnabled);
    } else {
        el.togDrift.classList.add('gb-hidden');
    }

    // Launch control info
    if (s.launchEnabled) {
        el.launchInfo.classList.remove('gb-hidden');
        el.launchStatus.textContent = s.launchPrepped ? 'Launch Control：就位 ✔' : 'Launch Control';
    } else {
        el.launchInfo.classList.add('gb-hidden');
    }
}

function setToggle(btn, isOn) {
    btn.classList.toggle('is-on', !!isOn);
    btn.setAttribute('aria-pressed', isOn ? 'true' : 'false');
}

// ── Render gear ratio editor ───────────────────────────────
function renderGearEditor(s) {
    if (state.mode !== 'settings' || s.isStock || !Array.isArray(s.gearRatios) || !s.gearRatios.length) {
        el.cardGearRatio.classList.add('gb-hidden');
        return;
    }

    state.defaultGearRatios = Array.isArray(s.defaultGearRatios) ? s.defaultGearRatios : [];

    el.grGrid.innerHTML = '';
    s.gearRatios.forEach((ratio, i) => {
        const defaultVal = state.defaultGearRatios[i] ?? ratio;
        const isModified = Math.abs(ratio - defaultVal) > 0.001;

        const row = document.createElement('div');
        row.className = 'gb-gr-row';
        row.innerHTML = `
            <span class="gb-gr-label">${esc(GEAR_NAMES[i] ?? (i + 1) + '檔')}</span>
            <input class="gb-gr-input${isModified ? ' is-modified' : ''}"
                   type="number" step="0.01" min="0.10" max="20.00"
                   value="${Number(ratio).toFixed(2)}"
                   data-default="${Number(defaultVal).toFixed(2)}" />
        `;
        el.grGrid.appendChild(row);
    });

    el.cardGearRatio.classList.remove('gb-hidden');
}

// ── Render transmission list (settings mode) ───────────────
function renderSettingsList(transmissions) {
    el.listTitle.textContent = '更換變速箱';
    el.listHint.textContent = '僅顯示已解鎖型號';
    el.transmList.innerHTML = '';

    if (!transmissions.length) {
        el.transmList.innerHTML = `<div class="gb-empty">尚無可用的變速箱</div>`;
        return;
    }

    transmissions.forEach(t => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'gb-item' + (t.isCurrent ? ' is-active' : '');
        btn.dataset.key = t.key;
        btn.setAttribute('role', 'option');
        btn.setAttribute('aria-selected', t.isCurrent ? 'true' : 'false');

        const gearsText = t.gears > 0 ? `${t.gears}速` : '';

        btn.innerHTML = `
            <div class="gb-item-left">
                <span class="gb-item-name">${esc(t.label)}</span>
                <div class="gb-item-sub">
                    ${typeBadgeHtml(t.transmType)}
                    ${gearsText ? `<span class="gb-item-desc">${esc(gearsText)}</span>` : ''}
                </div>
            </div>
            <div class="gb-item-right">
                ${t.isCurrent ? '<span class="gb-item-check">✔ 使用中</span>' : ''}
            </div>
        `;

        if (!t.isCurrent) {
            btn.addEventListener('click', () => {
                postNui('changeTransmission', { key: t.key });
                hide();
            });
        } else {
            btn.classList.add('is-disabled');
        }

        el.transmList.appendChild(btn);
    });
}

// ── Render transmission list (upgrade mode) ────────────────
function renderUpgradeList(transmissions) {
    el.listTitle.textContent = '變速箱升級商店';
    el.listHint.textContent = '依 Tier 排序';
    el.transmList.innerHTML = '';

    if (!transmissions.length) {
        el.transmList.innerHTML = `<div class="gb-empty">沒有可購買的升級項目</div>`;
        return;
    }

    transmissions.forEach(t => {
        const div = document.createElement('div');
        const classes = ['gb-upgrade-item'];
        if (t.isCurrent)  classes.push('is-current');
        if (t.unlocked && !t.isCurrent) classes.push('is-unlocked');
        div.className = classes.join(' ');

        const isFree = t.price === 0;
        const priceText = isFree ? '免費' : formatMoney(t.price);
        const priceClass = 'gb-upgrade-price' + (isFree ? ' is-free' : '');
        const gearsText = t.gears > 0 ? `${t.gears}速` : '';

        let actionHtml;
        if (t.isCurrent) {
            actionHtml = `<span class="gb-item-check">✔ 使用中</span>`;
        } else if (t.unlocked) {
            actionHtml = `<button class="gb-btn gb-btn-ghost gb-btn-sm" data-action="equip" data-key="${esc(t.key)}" type="button">裝備</button>`;
        } else {
            actionHtml = `<button class="gb-btn gb-btn-primary gb-btn-sm" data-action="buy" data-key="${esc(t.key)}" data-label="${esc(t.label)}" data-price="${Number(t.price)}" type="button">購買 ${priceText}</button>`;
        }

        div.innerHTML = `
            <div class="gb-upgrade-left">
                <span class="gb-upgrade-name">${esc(t.label)}</span>
                <div class="gb-upgrade-meta">
                    ${typeBadgeHtml(t.transmType)}
                    ${gearsText ? `<span class="gb-item-desc">${esc(gearsText)}</span>` : ''}
                    <span class="${priceClass}">${priceText}</span>
                </div>
            </div>
            <div class="gb-upgrade-right">
                ${actionHtml}
            </div>
        `;

        // Bind action buttons
        const equipBtn = div.querySelector('[data-action="equip"]');
        if (equipBtn) {
            equipBtn.addEventListener('click', () => {
                postNui('changeTransmission', { key: t.key });
                hide();
            });
        }

        const buyBtn = div.querySelector('[data-action="buy"]');
        if (buyBtn) {
            buyBtn.addEventListener('click', () => {
                state.pendingBuyKey   = t.key;
                state.pendingBuyLabel = t.label;
                state.pendingBuyPrice = t.price;
                showConfirmModal(t.label, t.price);
            });
        }

        el.transmList.appendChild(div);
    });
}

// ── Open UI ───────────────────────────────────────────────
function openUI(data) {
    const s = data.state || {};
    state.mode = data.mode || 'settings';

    // Mode pill
    if (state.mode === 'upgrade') {
        el.modePill.textContent = '升級商店';
        el.modePill.className = 'gb-mode-pill is-upgrade';
        el.modePill.classList.remove('gb-hidden');
        el.subtitle.textContent = 'Los Santos Customs';
        el.cardAssists.classList.add('gb-hidden');
    } else {
        el.modePill.textContent = '設定';
        el.modePill.className = 'gb-mode-pill';
        el.modePill.classList.remove('gb-hidden');
        el.subtitle.textContent = s.vehicleModel ? s.vehicleModel.toUpperCase() : '設定與升級';
        el.cardAssists.classList.remove('gb-hidden');
    }

    updateStatus(s);

    if (state.mode === 'settings') {
        updateToggles(s);
        renderGearEditor(s);
    } else {
        el.cardGearRatio.classList.add('gb-hidden');
    }

    // Repair button
    if (data.canRepair && state.mode === 'settings') {
        el.btnRepair.classList.remove('gb-hidden');
        el.repairCost.textContent = formatMoney(data.repairCost);
    } else {
        el.btnRepair.classList.add('gb-hidden');
    }

    // Render list
    const transmissions = Array.isArray(data.transmissions) ? data.transmissions : [];
    if (state.mode === 'upgrade') {
        renderUpgradeList(transmissions);
    } else {
        renderSettingsList(transmissions);
    }

    show();
}

// ── Update state (after toggle) ───────────────────────────
function updateState(data) {
    const s = data.state || {};
    updateStatus(s);
    if (state.mode === 'settings') {
        updateToggles(s);
    }
    if (data.canRepair && state.mode === 'settings') {
        el.btnRepair.classList.remove('gb-hidden');
        el.repairCost.textContent = formatMoney(data.repairCost);
    } else {
        el.btnRepair.classList.add('gb-hidden');
    }
}

// ── Confirm modal ─────────────────────────────────────────
function showConfirmModal(label, price) {
    el.modalText.textContent = `購買「${label}」需要 ${formatMoney(price)}，確定嗎？`;
    el.modal.classList.remove('gb-hidden');
    el.modal.setAttribute('aria-hidden', 'false');
}

function hideModal() {
    el.modal.classList.add('gb-hidden');
    el.modal.setAttribute('aria-hidden', 'true');
    state.pendingBuyKey = null;
}

// ── Close UI ──────────────────────────────────────────────
function closeUI() {
    hide();
    postNui('close');
}

// ── Event bindings ────────────────────────────────────────
el.btnClose.addEventListener('click', closeUI);

// Assist toggles
[el.togAntiStall, el.togRevMatch, el.togDrift].forEach(btn => {
    btn.addEventListener('click', () => {
        const assist = btn.dataset.assist;
        postNui('toggleAssist', { assist });
        // Optimistic toggle so UI feels instant
        setToggle(btn, !btn.classList.contains('is-on'));
    });
});

// Repair clutch
el.btnRepair.addEventListener('click', () => {
    postNui('repairClutch');
    hide();
});

// Gear ratio: highlight modified inputs on change
el.grGrid.addEventListener('input', e => {
    const inp = e.target;
    if (!inp.classList.contains('gb-gr-input')) return;
    const defaultVal = parseFloat(inp.dataset.default);
    const currentVal = parseFloat(inp.value);
    inp.classList.toggle('is-modified', Math.abs(currentVal - defaultVal) > 0.001);
});

// Gear ratio: reset all to defaults
el.btnGrResetAll.addEventListener('click', () => {
    el.grGrid.querySelectorAll('.gb-gr-input').forEach(inp => {
        inp.value = parseFloat(inp.dataset.default).toFixed(2);
        inp.classList.remove('is-modified');
    });
});

// Gear ratio: apply and save
el.btnGrApply.addEventListener('click', () => {
    const inputs = el.grGrid.querySelectorAll('.gb-gr-input');
    const ratios = Array.from(inputs).map(inp => {
        const v = parseFloat(inp.value);
        return isNaN(v) ? 1.0 : Math.max(0.10, Math.min(20.0, v));
    });
    postNui('applyGearRatios', { ratios });
});

// Modal – backdrop click
document.getElementById('modal-backdrop').addEventListener('click', hideModal);
el.btnModalClose.addEventListener('click', hideModal);
el.btnModalCancel.addEventListener('click', hideModal);
el.btnModalConfirm.addEventListener('click', () => {
    if (!state.pendingBuyKey) return;
    postNui('confirmBuy', { key: state.pendingBuyKey });
    hideModal();
    hide();
});

// Escape key
document.addEventListener('keydown', e => {
    if (!state.visible || e.key !== 'Escape') return;
    if (!el.modal.classList.contains('gb-hidden')) { hideModal(); return; }
    closeUI();
});

// ── NUI message handler ───────────────────────────────────
window.addEventListener('message', e => {
    const data = e.data || {};
    if (data.action === 'gearbox:open') {
        openUI(data);
    } else if (data.action === 'gearbox:close') {
        hide();
    } else if (data.action === 'gearbox:updateState') {
        updateState(data);
    }
});

// ── Browser dev preview ───────────────────────────────────
if (!IS_NUI) {
    window.dispatchEvent(new MessageEvent('message', {
        data: {
            action: 'gearbox:open',
            mode: 'settings',
            state: {
                transmKey: 'MT_6',
                transmLabel: '6速手排',
                transmType: 'MT',
                transmMaxGear: 6,
                clutchHealth: 67,
                gearboxTemp: 95,
                antiStall: false,
                revMatch: true,
                driftEnabled: true,
                launchPrepped: false,
                launchEnabled: false,
                isStock: false,
                isMT: true,
                vehicleModel: 'sultan',
                gearRatios:        [3.65, 2.15, 1.44, 1.07, 0.82, 0.62],
                defaultGearRatios: [3.65, 2.11, 1.44, 1.07, 0.82, 0.62],
            },
            transmissions: [
                { key: 'STOCK', label: '原廠離合器', gears: 0, transmType: '', unlocked: true, isCurrent: false, isStock: true },
                { key: 'MT_4', label: '4速手排', gears: 4, transmType: 'MT', unlocked: true, isCurrent: false, isStock: false },
                { key: 'MT_5', label: '5速手排', gears: 5, transmType: 'MT', unlocked: true, isCurrent: false, isStock: false },
                { key: 'MT_6', label: '6速手排', gears: 6, transmType: 'MT', unlocked: true, isCurrent: true,  isStock: false },
            ],
            canRepair: true,
            repairCost: 5000,
        }
    }));
}
