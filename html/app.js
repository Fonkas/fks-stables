'use strict';

/* ======================================================================
   FKS Stables — NUI
   ====================================================================== */

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'fks-stables';

const S = {
    L: {}, cfg: {}, stable: null, data: null,
    view: 'home', stack: [],
    shop: { b: 0, c: 0, gender: 'male' },
    wshop: { c: 0, w: 0 },
    mine: { i: 0 }, wmine: { i: 0 },
    breed: { f: 0, m: 0 },
    custom: null,
    modal: null,
    busy: false,
};

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = (n) => Math.round(Number(n) || 0).toLocaleString('en-US');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const wrap = (v, n) => ((v % n) + n) % n;
const L = (k, ...a) => { let s = S.L[k] ?? k; a.forEach((x) => { s = s.replace('%s', x); }); return s; };

async function post(name, data = {}) {
    if (!IN_GAME) return Dev.post(name, data);
    try {
        const r = await fetch(`https://${RES}/${name}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
        });
        return await r.json();
    } catch (e) { return {}; }
}

function debounce(fn, ms) {
    let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}

/* ---------------------------------------------------------------------- visual pieces */
const icon = (id, cls = '') => `<svg class="ico ${cls}"><use href="#${id}"/></svg>`;
const RING = '<svg class="ring" viewBox="0 0 64 64"><circle class="a" cx="32" cy="32" r="28"/><circle class="b" cx="32" cy="32" r="24.5"/></svg>';

function med(act, ic, label, o = {}) {
    const attrs = Object.entries(o.data || {}).map(([k, v]) => `data-${k}="${esc(v)}"`).join(' ');
    return `<button class="med ${o.warn ? 'warn' : ''}" data-act="${act}" ${attrs} ${o.disabled ? 'disabled' : ''}>
        <span class="disc">${RING}${o.img ? `<img class="ico img" src="${esc(o.img)}" alt="" onerror="this.nextElementSibling.style.display='';this.remove()">${icon(ic).replace('<svg ', '<svg style="display:none" ')}` : icon(ic)}${o.badge != null ? `<span class="badge">${esc(o.badge)}</span>` : ''}</span>
        <span class="lbl">${esc(label)}</span>${o.sub ? `<span class="sub">${esc(o.sub)}</span>` : ''}</button>`;
}

const SEAL_PATH = (() => {
    const n = 26, pts = [];
    for (let i = 0; i < n * 2; i++) {
        const a = (i / (n * 2)) * Math.PI * 2, r = i % 2 ? 29.2 : 31.6;
        pts.push(`${(32 + Math.cos(a) * r).toFixed(2)},${(32 + Math.sin(a) * r).toFixed(2)}`);
    }
    return `M${pts.join('L')}Z`;
})();

function seal(cur, amount, act = 'buy') {
    const gold = cur === 'gold';
    return `<button class="seal ${gold ? 'gold' : 'cash'} stamp" data-act="${act}" data-cur="${cur}">
        <span class="wax"><svg viewBox="0 0 64 64"><path class="edge" d="${SEAL_PATH}"/><circle class="inner" cx="32" cy="32" r="24"/></svg>
        <b><span>${gold ? '' : '<small>$</small>'}${fmt(amount)}</span></b></span>
        <span class="cap">${esc(gold ? L('gold') : L('cash'))}</span></button>`;
}

const ticks = (n, gold) => `<div class="ticks ${gold ? 'gold' : ''}">${Array.from({ length: 10 }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('')}</div>`;
const inkbar = (pct, cls = '') => `<div class="inkbar ${cls} ${pct < 20 ? 'low' : ''}"><i style="width:${clamp(pct, 0, 100)}%"></i></div>`;
const statRow = (label, inner, val = '') => `<div class="stat"><label>${esc(label)}</label>${inner}<span class="val">${esc(val)}</span></div>`;
const carousel = (size, prev, next, label, count, extraAct = '') => `
    <div class="car ${size}">
        <button class="arr" data-act="${prev}">${icon('i-left')}</button>
        <div class="car-val"><b ${extraAct ? `data-act="${extraAct}"` : ''}>${esc(label)}</b>${count ? `<small>${esc(count)}</small>` : ''}</div>
        <button class="arr" data-act="${next}">${icon('i-right')}</button>
    </div>`;
const ROMAN = ['', 'I', 'II', 'III', 'IV'];

/* ---------------------------------------------------------------------- data */
const breeds = () => S.data?.shopHorses || [];
const wcats = () => S.data?.shopWagons || [];
const myHorses = () => S.data?.horses || [];
const myWagons = () => S.data?.wagons || [];
const svc = (k) => !!S.stable?.services?.[k];

function statsFor(breed, coat) {
    const st = { ...breed.stats };
    if (coat.fixedStats) {
        st.speed = coat.fixedStats[0]; st.accel = coat.fixedStats[1];
        st.handling = clamp(Math.ceil(coat.fixedStats[2] / 2.5), 1, 4);
    }
    return st;
}

/* ---------------------------------------------------------------------- views */
const Views = {};

Views.home = () => {
    const h = myHorses().length, w = myWagons().length, lim = S.data.limits || {};
    const items = [];
    if (svc('buyHorses')) items.push(med('go', 'i-horse', L('home_buy_horse'), { data: { view: 'shopHorse' }, img: 'horseicon.png' }));
    items.push(med('go', 'i-shoe', L('home_my_horses'), { data: { view: 'myHorses' }, sub: `${h} / ${lim.horses ?? '∞'}`, img: 'horseicon2.png' }));
    if (svc('buyWagons')) items.push(med('go', 'i-wagon', L('home_buy_wagon'), { data: { view: 'shopWagon' }, img: 'wagonicon.png' }));
    items.push(med('go', 'i-wheel', L('home_my_wagons'), { data: { view: 'myWagons' }, sub: `${w} / ${lim.wagons ?? '∞'}`, img: 'wagonicon2.png' }));
    if (svc('breeding') && S.data.isTrainer) {
        const n = (S.data.breeding || []).length;
        items.push(med('go', 'i-heart', L('home_breed'), { data: { view: 'breed' }, sub: n ? L('breed_pending', n) : '' }));
    }
    return { title: S.L.title, html: `<div class="home-grid">${items.join('')}</div>`, hints: [['ESC', L('close')]] };
};

Views.shopHorse = () => {
    const list = breeds();
    if (!list.length) return { title: L('home_buy_horse'), html: `<div class="empty">—</div>` };
    S.shop.b = clamp(S.shop.b, 0, list.length - 1);
    const b = list[S.shop.b];
    S.shop.c = clamp(S.shop.c, 0, b.coats.length - 1);
    const c = b.coats[S.shop.c], st = statsFor(b, c);
    return {
        title: L('home_buy_horse'), count: '',
        html: `
            ${carousel('big', 'breed-prev', 'breed-next', b.breed, `${S.shop.b + 1} / ${list.length}`, 'breed-list')}
            ${carousel('small', 'coat-prev', 'coat-next', c.label, `${S.shop.c + 1} / ${b.coats.length}`)}
            <div class="meta">
                <div class="tier">${esc(L('tier'))} <i><span>${ROMAN[c.tier] || c.tier}</span></i></div>
                <div class="sex">
                    <button class="${S.shop.gender === 'male' ? 'on' : ''}" data-act="gender" data-g="male" title="${esc(L('male'))}">${icon('i-male')}</button>
                    <button class="${S.shop.gender === 'female' ? 'on' : ''}" data-act="gender" data-g="female" title="${esc(L('female'))}">${icon('i-female')}</button>
                </div>
            </div>
            <div class="facts">
                <span>${icon('i-bag')} ${fmt(c.storage)}</span>
                <span>${icon('i-pelt')} ${fmt(c.pelts)}</span>
                <span>${esc(L('breeding'))}: ${esc(c.canBreed ? L('yes') : L('no'))}</span>
            </div>
            <div class="stats">
                ${statRow(L('speed'), ticks(st.speed))}
                ${statRow(L('accel'), ticks(st.accel))}
                ${statRow(L('health'), ticks(st.health))}
                ${statRow(L('stamina'), ticks(st.stamina))}
                ${statRow(L('handling'), ticks(st.handling * 2.5, true), L('handling_' + st.handling))}
            </div>
            <p class="desc">${esc(b.info || '')}</p>
            <div class="seals">${c.cash > 0 ? seal('cash', c.cash) : ''}${c.gold > 0 ? seal('gold', c.gold) : ''}</div>`,
        hints: [['← →', L('coat')], ['↑ ↓', L('breed')], ['⟲', L('hint_rotate')]],
    };
};

Views.myHorses = () => {
    const list = myHorses();
    if (!list.length) {
        return {
            title: L('home_my_horses'),
            html: `<div class="empty">${esc(L('none_owned_horse'))}${svc('buyHorses') ? med('go', 'i-horse', L('home_buy_horse'), { data: { view: 'shopHorse' } }) : ''}</div>`,
        };
    }
    S.mine.i = clamp(S.mine.i, 0, list.length - 1);
    const h = list[S.mine.i];
    const prog = clamp(h.xp / Math.max(1, h.xpMax || 1), 0, 1);
    const C = 2 * Math.PI * 26;
    const badges = [];
    if (h.active && h.spawned) badges.push(`<span class="bdg gold">${esc(L('active'))}</span>`);
    if (h.dead) badges.push(`<span class="bdg bad">${esc(L('injured'))}</span>`);
    if (h.old) badges.push(`<span class="bdg">${esc(L('old'))}</span>`);
    if (h.special) badges.push(`<span class="bdg gold">${esc(L('special'))}</span>`);
    if (h.foal) badges.push(`<span class="bdg">${esc(L('foal'))}</span>`);
    if (h.breedingUntil) badges.push(`<span class="bdg gold">${esc(L('breeding_now'))}</span>`);
    if (!h.here) badges.push(`<span class="bdg">${esc(L('elsewhere'))} · ${esc(h.stableLabel)}</span>`);
    const locked = !h.here;
    return {
        title: L('home_my_horses'), count: `${S.mine.i + 1} / ${list.length}`,
        html: `
            ${carousel('big', 'mine-prev', 'mine-next', h.name)}
            <div class="sheet-sub">${esc(h.breed)} · ${esc(h.coatLabel)}</div>
            <div class="badges">${badges.join('')}</div>
            <div class="sheet-top">
                <div class="lvl pct"><svg viewBox="0 0 64 64"><circle class="bg" cx="32" cy="32" r="26"/>
                    <circle class="fg" cx="32" cy="32" r="26" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - prog)}"/></svg>
                    <b>${Math.floor(prog * 100)}<i>%</i></b><small>${esc(L('training'))}</small></div>
                <dl class="kv">
                    <div><dt>XP</dt><dd>${fmt(h.xp)} / ${fmt(h.xpMax)}</dd></div>
                    <div><dt>${esc(L('gender'))}</dt><dd>${esc(h.gender === 'female' ? L('female') : L('male'))}</dd></div>
                    <div><dt>${esc(L('age'))}</dt><dd>${h.age != null ? `${h.age} ${esc(L('years'))}` : '—'}</dd></div>
                    <div><dt>${esc(L('at_stable'))}</dt><dd>${esc(h.stableLabel)}</dd></div>
                    <div><dt>${esc(L('bond'))}</dt><dd class="bond">${[1, 2, 3, 4].map((i) => `<svg class="ico ${i <= h.bond ? 'on' : ''}"><use href="#i-shoe"/></svg>`).join('')}</dd></div>
                </dl>
            </div>
            <div class="stats">
                ${statRow(L('health'), inkbar(h.health, 'red'), h.health)}
                ${statRow(L('stamina'), inkbar(h.stamina, 'amber'), h.stamina)}
                ${statRow(L('hunger'), inkbar(h.hunger), Math.round(h.hunger))}
                ${statRow(L('thirst'), inkbar(h.thirst, 'blue'), Math.round(h.thirst))}
                ${statRow(L('clean'), inkbar(100 - h.dirt), Math.round(100 - h.dirt))}
                ${statRow(L('hooves'), inkbar(h.hoof ?? 100, 'amber'), Math.round(h.hoof ?? 100))}
                ${statRow(L('courage'), ticks(Math.floor(h.courage || 0)), h.courage || 0)}
                ${statRow(L('affinity'), ticks(Math.floor(h.affinity || 0), true), h.affinity || 0)}
            </div>
            <div class="actions">
                ${med('h-take', 'i-take', L('a_take'), { disabled: locked || h.dead || !!h.breedingUntil })}
                ${svc('customize') ? med('h-equip', 'i-saddle', L('a_equip'), { disabled: locked }) : ''}
                ${svc('coloring') && S.data.canColor ? med('h-coat', 'i-palette', L('a_coat'), { disabled: locked }) : ''}
                ${med('h-heal', 'i-heal', L('a_heal'), { disabled: !(h.dead || h.health < 100) })}
                ${svc('transfer') ? med('h-transfer', 'i-transfer', L('a_transfer')) : ''}
                ${med('h-rename', 'i-quill', L('a_rename'))}
                ${med('h-sell', 'i-coin', L('a_sell'), { warn: true })}
            </div>`,
        hints: [['← →', L('hint_nav')], ['⟲', L('hint_rotate')]],
    };
};

const breedReason = (h) => {
    if (!h) return '';
    if (h.canBreed) return L('breed_ok');
    if (h.special) return L('breed_r_special');
    if (h.foal) return L('breed_r_young');
    if (h.breedingUntil) return L('breed_r_busy');
    if (h.breedWait > 0) return L('breed_r_wait', Math.ceil(h.breedWait / 60));
    if (h.dead) return L('injured');
    return L('breed_r_no');
};
const breedLists = () => {
    const here = myHorses().filter((h) => h.here);
    return { f: here.filter((h) => h.gender === 'female'), m: here.filter((h) => h.gender === 'male') };
};
const mmss = (s) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

Views.breed = () => {
    const { f, m } = breedLists();
    S.breed.f = clamp(S.breed.f, 0, Math.max(0, f.length - 1));
    S.breed.m = clamp(S.breed.m, 0, Math.max(0, m.length - 1));
    const a = f[S.breed.f], b = m[S.breed.m];
    const cfg = S.data.breedCfg || {};
    const ok = a && b && a.canBreed && b.canBreed;
    const result = a && b ? (a.breed === b.breed ? L('breed_same', a.breed) : L('breed_mix', a.breed, b.breed)) : '—';
    const side = (h, lbl) => `<div class="breed-side">
            <div class="section-label">${esc(lbl)}</div>
            <div class="sheet-sub">${h ? `${esc(h.breed)} · ${esc(h.coatLabel)}` : '—'}</div>
            <div class="sheet-sub">${h ? `${h.age ?? '—'} ${esc(L('years'))} · ${fmt(h.xp)} / ${fmt(h.xpMax)} XP` : ''}</div>
            <div class="bdg ${h && h.canBreed ? 'gold' : 'bad'}">${esc(breedReason(h) || L('breed_none'))}</div>
        </div>`;
    const pending = (S.data.breeding || []).map((p) => {
        const mo = myHorses().find((x) => x.id === p.mother), fa = myHorses().find((x) => x.id === p.father);
        return `<div class="breed-pend"><span>${esc(mo?.name || '?')} × ${esc(fa?.name || '?')}</span><b data-ready="${Date.now() + p.readyIn * 1000}">${mmss(p.readyIn)}</b></div>`;
    }).join('');
    return {
        title: L('home_breed'), count: '',
        html: `
            ${carousel('small', 'bf-prev', 'bf-next', a ? a.name : L('breed_no_female'), f.length ? `${S.breed.f + 1} / ${f.length}` : '')}
            ${side(a, L('female'))}
            ${carousel('small', 'bm-prev', 'bm-next', b ? b.name : L('breed_no_male'), m.length ? `${S.breed.m + 1} / ${m.length}` : '')}
            ${side(b, L('male'))}
            <dl class="kv" style="margin-top:calc(1.4*var(--u))">
                <div><dt>${esc(L('breed_result'))}</dt><dd>${esc(result)}</dd></div>
                <div><dt>${esc(L('breed_time'))}</dt><dd>${mmss(cfg.time || 0)}</dd></div>
                ${cfg.price > 0 ? `<div><dt>${esc(L('total'))}</dt><dd>$${fmt(cfg.price)}</dd></div>` : ''}
            </dl>
            <div class="actions"><button class="btn" data-act="breed-go" ${ok ? '' : 'disabled'}>${esc(L('breed_go'))}</button></div>
            ${pending ? `<div class="section-label">${esc(L('breed_pending_title'))}</div><div class="breed-list">${pending}</div>` : ''}`,
        hints: [['← →', L('female')], ['↑ ↓', L('male')], ['⟲', L('hint_rotate')]],
    };
};

// countdown of the breedings in progress
setInterval(() => {
    $$('.breed-pend b[data-ready]').forEach((el) => { el.textContent = mmss(Math.max(0, (Number(el.dataset.ready) - Date.now()) / 1000)); });
}, 1000);

Views.shopWagon = () => {
    const cats = wcats();
    if (!cats.length) return { title: L('home_buy_wagon'), html: `<div class="empty">—</div>` };
    S.wshop.c = clamp(S.wshop.c, 0, cats.length - 1);
    const cat = cats[S.wshop.c];
    S.wshop.w = clamp(S.wshop.w, 0, cat.wagons.length - 1);
    const w = cat.wagons[S.wshop.w];
    return {
        title: L('home_buy_wagon'),
        html: `
            ${carousel('big', 'wcat-prev', 'wcat-next', cat.category, `${S.wshop.c + 1} / ${cats.length}`, 'wcat-list')}
            ${carousel('small', 'wag-prev', 'wag-next', w.label, `${S.wshop.w + 1} / ${cat.wagons.length}`)}
            <div class="facts" style="margin-top:calc(2*var(--u))">
                <span>${icon('i-box')} ${fmt(w.storage)}</span>
                ${w.animals ? `<span>${icon('i-pelt')} ${fmt(w.animals)}</span>` : ''}
                ${w.work ? `<span class="bdg gold">${esc(L('work'))} · ${esc(L('work_' + w.work))}</span>` : ''}
            </div>
            <div class="stats">
                ${statRow(L('storage'), ticks(Math.ceil(clamp(w.storage / 200, 1, 10))))}
                ${statRow(L('animals'), ticks(Math.ceil(clamp(w.animals / 15, 0, 10))))}
            </div>
            <p class="desc">${esc(w.description || '')}</p>
            <div class="seals">${w.cash > 0 ? seal('cash', w.cash, 'wbuy') : ''}${w.gold > 0 ? seal('gold', w.gold, 'wbuy') : ''}</div>`,
        hints: [['← →', L('hint_nav')], ['↑ ↓', L('storage')], ['⟲', L('hint_rotate')]],
    };
};

Views.myWagons = () => {
    const list = myWagons();
    if (!list.length) {
        return {
            title: L('home_my_wagons'),
            html: `<div class="empty">${esc(L('none_owned_wagon'))}${svc('buyWagons') ? med('go', 'i-wagon', L('home_buy_wagon'), { data: { view: 'shopWagon' } }) : ''}</div>`,
        };
    }
    S.wmine.i = clamp(S.wmine.i, 0, list.length - 1);
    const w = list[S.wmine.i];
    const cond = Math.round(w.health / 10);
    const badges = [];
    if (w.active && w.spawned) badges.push(`<span class="bdg gold">${esc(L('active'))}</span>`);
    if (cond < 10) badges.push(`<span class="bdg bad">${esc(L('a_repair'))}</span>`);
    if (!w.here) badges.push(`<span class="bdg">${esc(L('elsewhere'))} · ${esc(w.stableLabel)}</span>`);
    return {
        title: L('home_my_wagons'), count: `${S.wmine.i + 1} / ${list.length}`,
        html: `
            ${carousel('big', 'wmine-prev', 'wmine-next', w.name)}
            <div class="sheet-sub">${esc(w.label)} · ${esc(w.category)}</div>
            <div class="badges">${badges.join('')}</div>
            <div class="facts">
                <span>${icon('i-box')} ${fmt(w.storage)}</span>
                ${w.animals ? `<span>${icon('i-pelt')} ${fmt(w.animals)}</span>` : ''}
                ${w.work ? `<span>${esc(L('work_' + w.work))}</span>` : ''}
            </div>
            <div class="stats">${statRow(L('condition'), inkbar(cond, 'amber'), `${cond}%`)}</div>
            <dl class="kv" style="margin-top:calc(1.4*var(--u))">
                <div><dt>${esc(L('at_stable'))}</dt><dd>${esc(w.stableLabel)}</dd></div>
                <div><dt>${esc(L('a_sell'))}</dt><dd>${w.sell.currency === 'gold' ? '' : '$'}${fmt(w.sell.amount)}</dd></div>
            </dl>
            <div class="actions">
                ${med('w-take', 'i-take', L('a_take'), { disabled: !w.here || w.broken })}
                ${svc('customizeWagons') ? med('w-custom', 'i-palette', L('a_custom'), { disabled: !w.here }) : ''}
                ${med('w-repair', 'i-hammer', L('a_repair'), { disabled: w.health >= 1000 })}
                ${svc('transfer') ? med('w-transfer', 'i-transfer', L('a_transfer')) : ''}
                ${med('w-rename', 'i-quill', L('a_rename'))}
                ${med('w-sell', 'i-coin', L('a_sell'), { warn: true })}
            </div>`,
        hints: [['← →', L('hint_nav')], ['⟲', L('hint_rotate')]],
    };
};

/* ---- dials: tack, coat and wagon share the same mechanics ---- */
function tileCaption(t, v) {
    if (t.caption) return t.caption(v);
    if (v === 0 && t.zeroLabel) return t.zeroLabel;
    return `${v} / ${t.max}`;
}

function tileHTML(t, i) {
    const v = S.custom.values[t.key];
    return `<div class="tile ${i === S.custom.sel ? 'sel' : ''}" data-tile="${i}" tabindex="-1">
        <label>${esc(t.label)}</label>
        <div class="dial" data-i="${i}">
            <svg viewBox="0 0 64 64"><g class="knob" style="transform:rotate(${v * t.step}deg)">
                <circle class="a" cx="32" cy="32" r="27"/>
                ${Array.from({ length: 12 }, (_, k) => `<line class="t" x1="32" y1="6.5" x2="32" y2="9.5" transform="rotate(${k * 30} 32 32)"/>`).join('')}
                <line class="n" x1="32" y1="4" x2="32" y2="10"/>
            </g></svg>
            <b class="${v === 0 && t.zeroLabel ? 'zero' : ''}">${v === 0 && t.zeroLabel ? '—' : v}</b>
        </div>
        <div class="dial-row">
            <button class="arr" data-act="dial-dec" data-i="${i}">${icon('i-left')}</button>
            <small>${esc(tileCaption(t, v))}</small>
            <button class="arr" data-act="dial-inc" data-i="${i}">${icon('i-right')}</button>
        </div>
    </div>`;
}

function customTotal() {
    const c = S.custom, P = S.cfg.prices || {};
    let total = 0;
    if (c.kind === 'equip') {
        for (const t of c.tiles) if (c.values[t.key] !== c.orig[t.key] && c.values[t.key] > 0) total += P.components?.[t.key] || 0;
    } else if (c.kind === 'coat') {
        if (c.tiles.some((t) => c.values[t.key] !== c.orig[t.key])) total = P.coloring || 0;
    } else if (c.kind === 'wagon') {
        for (const t of c.tiles) if (c.values[t.key] !== c.orig[t.key]) total += P.wagon?.[t.key] || 0;
        for (const e of c.extras) if (!c.origExtras.includes(e) && c.extrasOn.includes(e)) total += P.wagon?.extra || 0;
    }
    return total;
}

Views.custom = () => {
    const c = S.custom;
    const extras = c.kind === 'wagon' && c.extras.length
        ? `<div class="section-label">${esc(L('extras'))}</div><div class="chips">${c.extras.map((e) => `<button class="chip ${c.extrasOn.includes(e) ? 'on' : ''}" data-act="extra" data-e="${e}">${esc(L('extra'))} ${e}</button>`).join('')}</div>`
        : '';
    return {
        title: c.title, count: c.subtitle,
        html: `<div class="scroll"><div class="dials">${c.tiles.map(tileHTML).join('')}</div>${extras}</div>
            <div class="bar-total"><span>${esc(L('total'))}<b id="c-total">$${fmt(customTotal())}</b></span>
            <span class="btns"><button class="btn ghost" data-act="back">${esc(L('cancel'))}</button><button class="btn" data-act="custom-save">${esc(L('confirm'))}</button></span></div>`,
        hints: [['← →', L('hint_nav')], ['↑ ↓', L('hint_select')], ['⟲', L('hint_rotate')]],
    };
};

/* ---------------------------------------------------------------------- render */
function render(animate = true) {
    const v = Views[S.view]();
    $('#view-title').textContent = v.title || '';
    $('#view-count').textContent = v.count || '';
    $('.crumbs').classList.toggle('home', S.view === 'home');
    const view = $('#view');
    view.className = `view-${S.view}`;
    view.innerHTML = v.html;
    if (animate) { void view.offsetWidth; view.classList.add('view-in'); }
    $('#hints').innerHTML = [...(v.hints || []), ...(S.view === 'home' ? [] : [['ESC', L('hint_back')]])].map(([k, t]) => `<kbd>${esc(k)}</kbd>${esc(t)}`).join(' &nbsp;');
    $('#m-cash').textContent = fmt(S.data?.money?.cash);
    $('#m-gold').textContent = fmt(S.data?.money?.gold);
    if (S.view === 'custom') bindDials();
}

function flipCarousels(dir) {
    $$('.car-val').forEach((el) => { el.style.setProperty('--d', dir); el.classList.remove('flip'); void el.offsetWidth; el.classList.add('flip'); });
}

/* ---------------------------------------------------------------------- preview */
const doPreview = debounce(() => {
    switch (S.view) {
        case 'shopHorse': {
            const b = breeds()[S.shop.b]; const c = b?.coats[S.shop.c];
            if (c) post('preview', { type: 'shopHorse', id: c.id, gender: S.shop.gender });
            break;
        }
        case 'myHorses': { const h = myHorses()[S.mine.i]; post('preview', h ? { type: 'horse', id: h.id } : { type: 'none' }); break; }
        case 'shopWagon': { const w = wcats()[S.wshop.c]?.wagons[S.wshop.w]; if (w) post('preview', { type: 'shopWagon', model: w.model }); break; }
        case 'myWagons': { const w = myWagons()[S.wmine.i]; post('preview', w ? { type: 'wagon', id: w.id } : { type: 'none' }); break; }
        case 'home': post('preview', { type: 'none' }); break;
        case 'breed': {
            const { f, m } = breedLists();
            post('preview', { type: 'breed', female: f[S.breed.f]?.id, male: m[S.breed.m]?.id });
            break;
        }
        default: break;
    }
}, 140);

/* ---------------------------------------------------------------------- navigation */
function go(view, push = true) {
    if (push) S.stack.push(S.view);
    S.view = view;
    render();
    doPreview();
}

function back() {
    if (S.modal) return closeModal();
    if (S.view === 'custom') {
        S.custom = null;
        const prev = S.stack.pop() || 'home';
        S.view = prev; render(); doPreview(); return;
    }
    if (S.view === 'home' || !S.stack.length) return close();
    S.view = S.stack.pop(); render(); doPreview();
}

function close() {
    post('close');
    hide();
}

function hide() {
    $('#app').classList.add('hidden');
    $('#stage').classList.remove('on');
    closeModal();
    S.custom = null; S.stack = []; S.view = 'home';
}

/* ---------------------------------------------------------------------- modal */
function openModal(o) {
    S.modal = o;
    $('#modal-title').textContent = o.title || '';
    $('#modal-body').innerHTML = o.body || '';
    $('#modal-ok').textContent = o.ok || L('confirm');
    $('#modal-ok').className = `btn ${o.danger ? 'danger' : ''}`;
    $('#modal-ok').classList.toggle('hidden', o.noOk === true);
    $('#modal-cancel').textContent = o.cancel || L('cancel');
    $('#modal').classList.remove('hidden');
    const inp = $('#modal-body input');
    if (inp) setTimeout(() => { inp.focus(); inp.select(); }, 30);
    o.onOpen?.($('#modal-body'));
}

function closeModal() {
    S.modal = null;
    $('#modal').classList.add('hidden');
}

async function modalOk() {
    const o = S.modal; if (!o) return;
    const inp = $('#modal-body input');
    const keep = await o.onOk?.(inp ? inp.value.trim() : undefined);
    if (keep !== true && S.modal === o) closeModal();
}

function askName(title, def, onOk, note) {
    openModal({
        title, ok: L('confirm'),
        body: `<input maxlength="24" value="${esc(def || '')}" spellcheck="false">${note ? `<div class="note">${esc(note)}</div>` : ''}`,
        onOk: async (v) => { if (!v || v.length < 2) return true; await onOk(v); },
    });
}

function confirmBox(title, text, onOk, danger) {
    openModal({ title, body: `<p>${esc(text)}</p>`, danger, onOk });
}

function pickList(title, items, onPick) {
    openModal({
        title, noOk: true, cancel: L('cancel'),
        body: `<div class="list ${items.length < 8 ? 'one' : ''}">${items.map((it, i) => `<button data-pick="${i}" class="${it.on ? 'on' : ''}">${esc(it.label)}${it.sub ? `<small>${esc(it.sub)}</small>` : ''}</button>`).join('')}</div>`,
        onOpen: (body) => {
            body.querySelectorAll('[data-pick]').forEach((b) => b.addEventListener('click', () => {
                closeModal(); onPick(items[Number(b.dataset.pick)], Number(b.dataset.pick));
            }));
            body.querySelector('.on')?.scrollIntoView({ block: 'center' });
        },
    });
}

/* ---------------------------------------------------------------------- server actions */
async function act(name, payload) {
    if (S.busy) return null;
    S.busy = true; $('#panel').classList.add('busy');
    const res = await post(name, payload);
    S.busy = false; $('#panel').classList.remove('busy');
    if (res?.ok && res.data) S.data = res.data;
    return res;
}

/* ---------------------------------------------------------------------- customisation */
async function startEquip(h) {
    const res = await post('customStart', { id: h.id });
    const values = res.values || {};
    const tiles = (S.cfg.categories || []).map((cat) => ({
        key: cat, label: L(cat), max: S.cfg.componentMax?.[cat] || 0, step: 24, zeroLabel: L('off'),
    }));
    S.custom = { kind: 'equip', id: h.id, title: L('a_equip'), subtitle: h.name, tiles, values: { ...values }, orig: { ...values }, sel: 0 };
    tiles.forEach((t) => { S.custom.values[t.key] ??= 0; S.custom.orig[t.key] ??= 0; });
    go('custom');
}

function startCoat(h) {
    const co = h.coat || [0, 0, 0, 0], mt = h.maneTail || [0, 0, 0, 0];
    const pal = S.cfg.palettes || 21;
    const mk = (key, max, step, zero) => ({ key, label: L(key), max, step, zeroLabel: zero });
    const tiles = [
        mk('coat_palette', pal, 16, L('off')), mk('coat_tint0', 254, 6), mk('coat_tint1', 254, 6), mk('coat_tint2', 254, 6),
        mk('mane_palette', pal, 16, L('off')), mk('mane_tint0', 254, 6), mk('mane_tint1', 254, 6), mk('mane_tint2', 254, 6),
    ];
    const values = {
        coat_palette: co[0], coat_tint0: co[1], coat_tint1: co[2], coat_tint2: co[3],
        mane_palette: mt[0], mane_tint0: mt[1], mane_tint1: mt[2], mane_tint2: mt[3],
    };
    S.custom = { kind: 'coat', id: h.id, title: L('a_coat'), subtitle: h.name, tiles, values: { ...values }, orig: { ...values }, sel: 0, hadCoat: !!h.coat, hadMane: !!h.maneTail };
    go('custom');
}

async function startWagon(w) {
    const res = await post('wagonCustomStart', { id: w.id });
    if (!res.values) return;
    const names = res.liveryNames || [];
    const tiles = ['livery', 'tint', 'propset', 'lantern']
        .filter((k) => (res.max?.[k] || 0) > 0)
        .map((k) => ({
            key: k, label: L(k), max: res.max[k], step: 30, zeroLabel: L('off'),
            caption: k === 'livery' ? (v) => (v > 0 ? String(names[v - 1] ?? v).replace(/^\d+\s*-\s*/, '') : `0 / ${res.max[k]}`) : null,
        }));
    const v = res.values;
    S.custom = {
        kind: 'wagon', id: w.id, title: L('a_custom'), subtitle: w.name, tiles,
        values: { livery: v.livery, tint: v.tint, propset: v.propset, lantern: v.lantern },
        orig: { livery: v.livery, tint: v.tint, propset: v.propset, lantern: v.lantern },
        extras: res.extras || [], extrasOn: [...(v.extras || [])], origExtras: [...(v.extras || [])], sel: 0,
    };
    go('custom');
}

const previewCustom = debounce(() => {
    const c = S.custom; if (!c) return;
    if (c.kind === 'coat') post('coatPreview', coatPayload());
    else if (c.kind === 'wagon') post('wagonCustomPreview', { id: c.id, custom: wagonPayload() });
}, 180);

const previewEquip = {};
function previewPart(key) {
    previewEquip[key] ??= debounce((k) => post('customPreview', { cat: k, index: S.custom?.values[k] ?? 0 }), 90);
    previewEquip[key](key);
}

function coatPayload() {
    const v = S.custom.values, o = S.custom.orig;
    const coatDirty = ['coat_palette', 'coat_tint0', 'coat_tint1', 'coat_tint2'].some((k) => v[k] !== o[k]);
    const maneDirty = ['mane_palette', 'mane_tint0', 'mane_tint1', 'mane_tint2'].some((k) => v[k] !== o[k]);
    return {
        id: S.custom.id,
        coat: coatDirty || S.custom.hadCoat ? [v.coat_palette, v.coat_tint0, v.coat_tint1, v.coat_tint2] : null,
        maneTail: maneDirty || S.custom.hadMane ? [v.mane_palette, v.mane_tint0, v.mane_tint1, v.mane_tint2] : null,
    };
}

function wagonPayload() {
    const v = S.custom.values;
    return { livery: v.livery, tint: v.tint, propset: v.propset, lantern: v.lantern, extras: [...S.custom.extrasOn] };
}

function setDial(i, value) {
    const c = S.custom, t = c.tiles[i];
    const nv = wrap(value, t.max + 1);
    if (nv === c.values[t.key]) return;
    c.values[t.key] = nv;
    const tile = $(`.tile[data-tile="${i}"]`);
    if (tile) {
        const zero = nv === 0 && t.zeroLabel;
        tile.querySelector('.knob').style.transform = `rotate(${nv * t.step}deg)`;
        const b = tile.querySelector('.dial b');
        b.textContent = zero ? '—' : nv;
        b.classList.toggle('zero', !!zero);
        tile.querySelector('small').textContent = tileCaption(t, nv);
    }
    $('#c-total').textContent = `$${fmt(customTotal())}`;
    if (c.kind === 'equip') previewPart(t.key); else previewCustom();
}

function selectTile(i) {
    const c = S.custom;
    c.sel = clamp(i, 0, c.tiles.length - 1);
    $$('.tile').forEach((el) => el.classList.toggle('sel', Number(el.dataset.tile) === c.sel));
    $(`.tile[data-tile="${c.sel}"]`)?.scrollIntoView({ block: 'nearest' });
}

function bindDials() {
    $$('.dial').forEach((d) => {
        if (d._bound) return; d._bound = true;
        const i = Number(d.dataset.i);
        d.addEventListener('pointerdown', (e) => {
            selectTile(i);
            const r = d.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
            let last = Math.atan2(e.clientY - cy, e.clientX - cx), acc = 0;
            const t = S.custom.tiles[i];
            d.setPointerCapture(e.pointerId); d.classList.add('drag');
            const move = (ev) => {
                const a = Math.atan2(ev.clientY - cy, ev.clientX - cx);
                let da = (a - last) * 180 / Math.PI; last = a;
                if (da > 180) da -= 360; if (da < -180) da += 360;
                acc += da;
                const steps = Math.trunc(acc / t.step);
                if (steps) { acc -= steps * t.step; setDial(i, S.custom.values[t.key] + steps); }
            };
            const up = () => { d.classList.remove('drag'); d.removeEventListener('pointermove', move); d.removeEventListener('pointerup', up); d.removeEventListener('pointercancel', up); };
            d.addEventListener('pointermove', move); d.addEventListener('pointerup', up); d.addEventListener('pointercancel', up);
        });
    });
    $$('.tile').forEach((el) => {
        if (el._bound) return; el._bound = true;
        const i = Number(el.dataset.tile);
        el.addEventListener('wheel', (e) => { e.preventDefault(); e.stopPropagation(); selectTile(i); setDial(i, S.custom.values[S.custom.tiles[i].key] + (e.deltaY > 0 ? 1 : -1)); }, { passive: false });
        el.addEventListener('click', (e) => { if (!e.target.closest('[data-act]')) selectTile(i); });
    });
}

async function saveCustom() {
    const c = S.custom; if (!c) return;
    let res;
    if (c.kind === 'equip') res = await act('customSave', { id: c.id, values: c.values });
    else if (c.kind === 'coat') res = await act('coatSave', coatPayload());
    else res = await act('wagonCustomSave', { id: c.id, custom: wagonPayload() });
    if (res?.ok) { S.custom = null; S.view = S.stack.pop() || 'home'; render(); doPreview(); }
}

/* ---------------------------------------------------------------------- handlers */
const H = {
    back, go: (el) => go(el.dataset.view),
    'modal-cancel': closeModal, 'modal-ok': modalOk,

    'breed-prev': () => { S.shop.b = wrap(S.shop.b - 1, breeds().length); S.shop.c = 0; render(false); flipCarousels(-1); doPreview(); },
    'breed-next': () => { S.shop.b = wrap(S.shop.b + 1, breeds().length); S.shop.c = 0; render(false); flipCarousels(1); doPreview(); },
    'coat-prev': () => { const n = breeds()[S.shop.b].coats.length; S.shop.c = wrap(S.shop.c - 1, n); render(false); flipCarousels(-1); doPreview(); },
    'coat-next': () => { const n = breeds()[S.shop.b].coats.length; S.shop.c = wrap(S.shop.c + 1, n); render(false); flipCarousels(1); doPreview(); },
    'breed-list': () => pickList(L('breed'), breeds().map((b, i) => ({ label: b.breed, sub: b.coats.length, on: i === S.shop.b })), (_, i) => { S.shop.b = i; S.shop.c = 0; render(); doPreview(); }),
    gender: (el) => { S.shop.gender = el.dataset.g; render(false); doPreview(); },
    buy: (el) => {
        const b = breeds()[S.shop.b], c = b.coats[S.shop.c], cur = el.dataset.cur;
        const price = cur === 'gold' ? `${fmt(c.gold)} ${L('gold')}` : `$${fmt(c.cash)}`;
        askName(L('name_horse'), '', async (name) => {
            const res = await act('buyHorse', { coatId: c.id, currency: cur, gender: S.shop.gender, name });
            if (res?.ok) {
                const list = myHorses(); const newest = list.reduce((a, x, i) => (x.id > list[a].id ? i : a), 0);
                S.mine.i = newest; go('myHorses');
            }
        }, `${b.breed} · ${c.label} · ${price}`);
    },

    'bf-prev': () => { const n = breedLists().f.length; if (n) { S.breed.f = wrap(S.breed.f - 1, n); render(false); doPreview(); } },
    'bf-next': () => { const n = breedLists().f.length; if (n) { S.breed.f = wrap(S.breed.f + 1, n); render(false); doPreview(); } },
    'bm-prev': () => { const n = breedLists().m.length; if (n) { S.breed.m = wrap(S.breed.m - 1, n); render(false); doPreview(); } },
    'bm-next': () => { const n = breedLists().m.length; if (n) { S.breed.m = wrap(S.breed.m + 1, n); render(false); doPreview(); } },
    'breed-go': () => {
        const { f, m } = breedLists(); const a = f[S.breed.f], b = m[S.breed.m];
        if (!a || !b) return;
        confirmBox(L('home_breed'), L('breed_confirm', a.name, b.name), async () => { await act('breed', { mother: a.id, father: b.id }); render(false); });
    },
    'mine-prev': () => { S.mine.i = wrap(S.mine.i - 1, myHorses().length); render(false); flipCarousels(-1); doPreview(); },
    'mine-next': () => { S.mine.i = wrap(S.mine.i + 1, myHorses().length); render(false); flipCarousels(1); doPreview(); },
    'h-take': () => { const h = myHorses()[S.mine.i]; act('takeOut', { kind: 'horse', id: h.id }).then((r) => { if (r?.ok) hide(); }); },
    'h-equip': () => startEquip(myHorses()[S.mine.i]),
    'h-coat': () => startCoat(myHorses()[S.mine.i]),
    'h-heal': () => { const h = myHorses()[S.mine.i]; confirmBox(L('a_heal'), L('heal_confirm', h.name, fmt(h.heal)), async () => { await act('heal', { id: h.id }); render(false); }); },
    'h-transfer': () => transferFlow('horse', myHorses()[S.mine.i]),
    'h-rename': () => { const h = myHorses()[S.mine.i]; askName(L('rename_title'), h.name, async (name) => { await act('rename', { kind: 'horse', id: h.id, name }); render(false); }, priceNote(h.rename)); },
    'h-sell': () => {
        const h = myHorses()[S.mine.i];
        confirmBox(L('a_sell'), L('sell_confirm', h.name, fmt(h.sell.amount)), async () => {
            const r = await act('sell', { kind: 'horse', id: h.id }); if (r?.ok) { S.mine.i = Math.max(0, S.mine.i - 1); render(); doPreview(); }
        }, true);
    },

    'wcat-prev': () => { S.wshop.c = wrap(S.wshop.c - 1, wcats().length); S.wshop.w = 0; render(false); flipCarousels(-1); doPreview(); },
    'wcat-next': () => { S.wshop.c = wrap(S.wshop.c + 1, wcats().length); S.wshop.w = 0; render(false); flipCarousels(1); doPreview(); },
    'wag-prev': () => { const n = wcats()[S.wshop.c].wagons.length; S.wshop.w = wrap(S.wshop.w - 1, n); render(false); flipCarousels(-1); doPreview(); },
    'wag-next': () => { const n = wcats()[S.wshop.c].wagons.length; S.wshop.w = wrap(S.wshop.w + 1, n); render(false); flipCarousels(1); doPreview(); },
    'wcat-list': () => pickList(L('storage'), wcats().map((c, i) => ({ label: c.category, sub: c.wagons.length, on: i === S.wshop.c })), (_, i) => { S.wshop.c = i; S.wshop.w = 0; render(); doPreview(); }),
    wbuy: (el) => {
        const w = wcats()[S.wshop.c].wagons[S.wshop.w], cur = el.dataset.cur;
        const price = cur === 'gold' ? `${fmt(w.gold)} ${L('gold')}` : `$${fmt(w.cash)}`;
        askName(L('name_wagon'), w.label, async (name) => {
            const res = await act('buyWagon', { model: w.model, currency: cur, name });
            if (res?.ok) {
                const list = myWagons(); const newest = list.reduce((a, x, i) => (x.id > list[a].id ? i : a), 0);
                S.wmine.i = newest; go('myWagons');
            }
        }, price);
    },

    'wmine-prev': () => { S.wmine.i = wrap(S.wmine.i - 1, myWagons().length); render(false); flipCarousels(-1); doPreview(); },
    'wmine-next': () => { S.wmine.i = wrap(S.wmine.i + 1, myWagons().length); render(false); flipCarousels(1); doPreview(); },
    'w-take': () => { const w = myWagons()[S.wmine.i]; act('takeOut', { kind: 'wagon', id: w.id }).then((r) => { if (r?.ok) hide(); }); },
    'w-custom': () => startWagon(myWagons()[S.wmine.i]),
    'w-repair': () => { const w = myWagons()[S.wmine.i]; confirmBox(L('a_repair'), `${w.name} · $${fmt(w.repair)}`, async () => { await act('repair', { id: w.id }); render(false); }); },
    'w-transfer': () => transferFlow('wagon', myWagons()[S.wmine.i]),
    'w-rename': () => { const w = myWagons()[S.wmine.i]; askName(L('rename_title'), w.name, async (name) => { await act('rename', { kind: 'wagon', id: w.id, name }); render(false); }, priceNote(w.rename)); },
    'w-sell': () => {
        const w = myWagons()[S.wmine.i];
        confirmBox(L('a_sell'), L('sell_confirm', w.name, fmt(w.sell.amount)), async () => {
            const r = await act('sell', { kind: 'wagon', id: w.id }); if (r?.ok) { S.wmine.i = Math.max(0, S.wmine.i - 1); render(); doPreview(); }
        }, true);
    },

    'dial-dec': (el) => { const i = Number(el.dataset.i); selectTile(i); setDial(i, S.custom.values[S.custom.tiles[i].key] - 1); },
    'dial-inc': (el) => { const i = Number(el.dataset.i); selectTile(i); setDial(i, S.custom.values[S.custom.tiles[i].key] + 1); },
    extra: (el) => {
        const e = Number(el.dataset.e), on = S.custom.extrasOn;
        const k = on.indexOf(e); if (k >= 0) on.splice(k, 1); else on.push(e);
        el.classList.toggle('on', k < 0);
        $('#c-total').textContent = `$${fmt(customTotal())}`;
        previewCustom();
    },
    'custom-save': saveCustom,
};

function priceNote(p) { return p > 0 ? `$${fmt(p)}` : L('free'); }

function transferFlow(kind, x) {
    const items = (S.cfg.stables || []).filter((s) => s.id !== x.stable).map((s) => ({ label: s.label, id: s.id }));
    pickList(`${L('transfer_to')} ${S.cfg.transferPrice > 0 ? `· $${fmt(S.cfg.transferPrice)}` : ''}`, items, async (it) => {
        await act('transfer', { kind, id: x.id, to: it.id }); render(false);
    });
}

document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || el.disabled) return;
    const fn = H[el.dataset.act];
    if (fn) fn(el);
});

/* ---------------------------------------------------------------------- keyboard */
document.addEventListener('keydown', (e) => {
    if ($('#app').classList.contains('hidden')) return;
    const typing = e.target.tagName === 'INPUT';
    if (S.modal) {
        if (e.key === 'Escape') closeModal();
        if (e.key === 'Enter') modalOk();
        return;
    }
    if (e.key === 'Escape' || (e.key === 'Backspace' && !typing)) { e.preventDefault(); return back(); }
    const k = e.key;
    const map = {
        shopHorse: { ArrowLeft: 'coat-prev', ArrowRight: 'coat-next', ArrowUp: 'breed-prev', ArrowDown: 'breed-next' },
        myHorses: { ArrowLeft: 'mine-prev', ArrowRight: 'mine-next' },
        shopWagon: { ArrowLeft: 'wag-prev', ArrowRight: 'wag-next', ArrowUp: 'wcat-prev', ArrowDown: 'wcat-next' },
        myWagons: { ArrowLeft: 'wmine-prev', ArrowRight: 'wmine-next' },
        breed: { ArrowLeft: 'bf-prev', ArrowRight: 'bf-next', ArrowUp: 'bm-prev', ArrowDown: 'bm-next' },
    }[S.view];
    if (map?.[k]) { e.preventDefault(); return H[map[k]](); }
    if (S.view === 'custom' && S.custom) {
        const c = S.custom, t = c.tiles[c.sel], step = e.shiftKey ? 10 : 1;
        if (k === 'ArrowLeft') { e.preventDefault(); setDial(c.sel, c.values[t.key] - step); }
        if (k === 'ArrowRight') { e.preventDefault(); setDial(c.sel, c.values[t.key] + step); }
        if (k === 'ArrowUp') { e.preventDefault(); selectTile(c.sel - 3); }
        if (k === 'ArrowDown') { e.preventDefault(); selectTile(c.sel + 3); }
        if (k === 'Tab') { e.preventDefault(); selectTile(wrap(c.sel + (e.shiftKey ? -1 : 1), c.tiles.length)); }
        if (k === 'Delete' || k === '0') setDial(c.sel, 0);
        if (k === 'Enter') saveCustom();
    }
});

/* ---------------------------------------------------------------------- camera (drag / zoom) */
(() => {
    const st = $('#stage');
    let drag = false, lastX = 0, pend = 0, raf = null;
    const flush = () => { raf = null; if (pend) { post('rotate', { dx: pend }); pend = 0; } };
    st.addEventListener('pointerdown', (e) => { drag = true; lastX = e.clientX; st.classList.add('drag'); st.setPointerCapture(e.pointerId); });
    st.addEventListener('pointermove', (e) => {
        if (!drag) return;
        pend += e.clientX - lastX; lastX = e.clientX;
        if (!raf) raf = setTimeout(flush, 33);
    });
    const up = () => { drag = false; st.classList.remove('drag'); };
    st.addEventListener('pointerup', up); st.addEventListener('pointercancel', up);
    st.addEventListener('wheel', (e) => post('zoom', { dy: e.deltaY }), { passive: true });
})();

function fitTitle(text) {
    const h = $('#stable-name');
    h.textContent = text; h.style.fontSize = '';
    requestAnimationFrame(() => {
        let size = parseFloat(getComputedStyle(h).fontSize);
        while (h.scrollWidth > h.clientWidth && size > 12) { size -= 1; h.style.fontSize = `${size}px`; }
    });
}

/* ---------------------------------------------------------------------- messages from Lua */
/* ---------------------------------------------------------------------- horse sheet (Show Info) */
function renderCard(h, loc) {
    const T = (k) => loc?.[k] ?? k;
    const st = h.stats || {}, lv = h.live || {};
    const prog = clamp(h.xp / Math.max(1, h.xpMax || 1), 0, 1);
    const C = 2 * Math.PI * 26;
    const row = (label, inner, val = '') => `<div class="stat"><label>${esc(label)}</label>${inner}<span class="val">${esc(val)}</span></div>`;
    $('#card').innerHTML = `
        <header class="head">
            <div class="eyebrow">${esc(T('card_title').toUpperCase())}</div>
            <h1>${esc(h.name)}</h1>
        </header>
        <div class="sheet-sub">${esc(h.breed)} · ${esc(h.coat)}</div>
        <div class="meta">
            <div class="tier">${esc(T('tier'))} <i><span>${ROMAN[h.tier] || h.tier || '-'}</span></i></div>
            <svg class="ico sex-ico"><use href="#${h.gender === 'female' ? 'i-female' : 'i-male'}"/></svg>
            <span class="tier">${h.age != null ? `${h.age} ${esc(T('years'))}` : ''}${h.old ? ` · ${esc(T('old'))}` : ''}</span>
        </div>
        <div class="sheet-top">
            <div class="lvl pct"><svg viewBox="0 0 64 64"><circle class="bg" cx="32" cy="32" r="26"/>
                <circle class="fg" cx="32" cy="32" r="26" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - prog)}"/></svg>
                <b>${Math.floor(prog * 100)}<i>%</i></b><small>${esc(T('training'))}</small></div>
            <dl class="kv">
                <div><dt>${esc(T('bond'))}</dt><dd class="bond">${[1, 2, 3, 4].map((i) => `<svg class="ico ${i <= h.bond ? 'on' : ''}"><use href="#i-shoe"/></svg>`).join('')}</dd></div>
                <div><dt>XP</dt><dd>${fmt(h.xp)} / ${fmt(h.xpMax)}</dd></div>
                <div><dt>${esc(T('bags'))}</dt><dd>${fmt(h.storage)}</dd></div>
                <div><dt>${esc(T('pelts'))}</dt><dd>${fmt(h.pelts)}</dd></div>
                <div><dt>${esc(T('courage'))}</dt><dd>${h.courage ?? 0} / 10</dd></div>
                <div><dt>${esc(T('affinity'))}</dt><dd>${h.affinity ?? 0} / 10</dd></div>
            </dl>
        </div>
        <div class="section-label">${esc(T('card_breed_stats').toUpperCase())}</div>
        <div class="stats">
            ${row(T('speed'), ticks(st.speed || 0))}
            ${row(T('accel'), ticks(st.accel || 0))}
            ${row(T('health'), ticks(st.health || 0))}
            ${row(T('stamina'), ticks(st.stamina || 0))}
            ${row(T('handling'), ticks((st.handling || 0) * 2.5, true), T('handling_' + (st.handling || 2)))}
        </div>
        <div class="section-label">${esc(T('card_condition').toUpperCase())}</div>
        <div class="stats">
            ${row(T('health'), inkbar(lv.health, 'red'), lv.health)}
            ${row(T('stamina'), inkbar(lv.stamina, 'amber'), lv.stamina)}
            ${row(T('hunger'), inkbar(lv.hunger), lv.hunger)}
            ${row(T('thirst'), inkbar(lv.thirst, 'blue'), lv.thirst)}
            ${row(T('clean'), inkbar(lv.clean), lv.clean)}
            ${row(T('hooves'), inkbar(lv.hoof, 'amber'), lv.hoof)}
        </div>
        <div class="card-foot"><kbd>Q</kbd>${esc(T('close'))}</div>`;
}

/* ---------------------------------------------------------------------- revive: pick the horse */
const Pick = { dots: new Map() };

function pickRender(m) {
    const root = $('#pick');
    if (!m.show) {
        root.classList.add('hidden');
        Pick.dots.forEach((el) => el.remove());
        Pick.dots.clear();
        return;
    }
    root.classList.remove('hidden');
    $('#pick-hint').textContent = m.hint || '';
    const seen = new Set();
    (m.dots || []).forEach((d) => {
        const id = String(d.id);
        seen.add(id);
        let el = Pick.dots.get(id);
        if (!el) {
            el = document.createElement('button');
            el.className = 'pick-dot';
            el.dataset.id = id;
            el.innerHTML = '<span></span>';
            root.appendChild(el);
            Pick.dots.set(id, el);
        }
        el.style.left = `${(d.x * 100).toFixed(3)}%`;
        el.style.top = `${(d.y * 100).toFixed(3)}%`;
        el.querySelector('span').textContent = d.name || '';
    });
    Pick.dots.forEach((el, id) => { if (!seen.has(id)) { el.remove(); Pick.dots.delete(id); } });
}

$('#pick').addEventListener('pointerdown', (e) => {
    if (e.button === 2) { e.preventDefault(); post('pickHorse', { cancel: true }); return; }
    const dot = e.target.closest('.pick-dot');
    if (dot && e.button === 0) post('pickHorse', { id: Number(dot.dataset.id) });
});
$('#pick').addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('keydown', (e) => {
    if ($('#pick').classList.contains('hidden')) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); post('pickHorse', { cancel: true }); }
});

/* ---------------------------------------------------------------------- wild horse taming: falling letters */
const Tame = { on: false, items: [], raf: 0 };

function tameClear() {
    Tame.on = false;
    cancelAnimationFrame(Tame.raf);
    Tame.items = [];
    $('#tame').innerHTML = '';
}

function tameHide() { tameClear(); $('#tame').classList.add('hidden'); }

function tameStart(m) {
    tameClear();
    $('#tame').classList.remove('hidden');
    Object.assign(Tame, { on: true, items: [], cfg: m, start: performance.now(), next: 0 });
    Tame.raf = requestAnimationFrame(tameTick);
}

function tameEnd(ok) {
    if (!Tame.on) return;
    Tame.on = false;
    cancelAnimationFrame(Tame.raf);
    if (ok) Tame.items.forEach((it) => it.el.classList.add('hit')); // time is up: the remaining ones disappear
    post('tameResult', { ok });
    setTimeout(tameHide, ok ? 400 : 700);
}

function tameSpawn(now) {
    const c = Tame.cfg, letters = c.letters || 'ASDQWEZXC';
    const letter = letters[Math.floor(Math.random() * letters.length)];
    const el = document.createElement('div');
    el.className = 'tame-key';
    el.textContent = letter;
    el.style.left = `${5 + Math.random() * 90}%`; // anywhere on the screen
    $('#tame').appendChild(el);
    const it = { el, letter, t0: now };
    el.addEventListener('pointerdown', (e) => { e.preventDefault(); tameHit(it); });
    Tame.items.push(it);
}

function tameHit(it) {
    if (!Tame.on || !Tame.items.includes(it)) return;
    Tame.items = Tame.items.filter((x) => x !== it);
    it.el.classList.add('hit');
    setTimeout(() => it.el.remove(), 220);
}

function tameTick(now) {
    if (!Tame.on) return;
    const c = Tame.cfg, elapsed = now - Tame.start;
    if (elapsed >= c.duration) return tameEnd(true);
    if (now >= Tame.next) {
        tameSpawn(now);
        const k = elapsed / c.duration;
        Tame.next = now + c.spawnEvery + (c.spawnEveryEnd - c.spawnEvery) * k;
    }
    const H = window.innerHeight;
    for (const it of Tame.items) {
        const p = (now - it.t0) / c.fallTime;
        it.el.style.transform = `translateY(${(p * (H - it.el.offsetHeight)).toFixed(1)}px)`;
        if (p >= 1) { it.el.classList.add('miss'); return tameEnd(false); } // one got away
    }
    Tame.raf = requestAnimationFrame(tameTick);
}

document.addEventListener('keydown', (e) => {
    if (!Tame.on) return;
    e.preventDefault();
    const k = (e.key || '').toUpperCase();
    if (k.length !== 1) return;
    // the oldest (closest to the bottom) with this letter
    const it = Tame.items.filter((x) => x.letter === k).sort((a, b) => a.t0 - b.t0)[0];
    if (it) tameHit(it);
});

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'pick') { pickRender(m); return; }
    if (m.action === 'tame') { if (m.show) tameStart(m); else tameHide(); return; }
    if (m.action === 'card') {
        const card = $('#card');
        if (!m.show) { card.classList.add('hidden'); return; }
        const wasHidden = card.classList.contains('hidden');
        renderCard(m.horse, m.locale);
        if (wasHidden) { card.style.animation = 'none'; void card.offsetWidth; card.style.animation = ''; card.classList.remove('hidden'); }
        return;
    }
    if (m.action === 'open') {
        S.L = m.locale || {}; S.cfg = m.config || {}; S.stable = m.stable; S.data = m.data;
        S.view = 'home'; S.stack = []; S.custom = null;
        S.shop = { b: 0, c: 0, gender: 'male' }; S.wshop = { c: 0, w: 0 }; S.mine = { i: 0 }; S.wmine = { i: 0 };
        fitTitle(S.stable.label);
        $('#eyebrow-text').textContent = (S.L.title || '').toUpperCase();
        $('#app').classList.remove('hidden');
        $('#stage').classList.add('on');
        const p = $('#panel'); p.style.animation = 'none'; void p.offsetWidth; p.style.animation = '';
        render();
        doPreview();
    } else if (m.action === 'close') {
        hide();
    } else if (m.action === 'data') {
        S.data = m.data; render(false);
    }
});

/* ======================================================================
   Development mode (open index.html in a browser)
   ====================================================================== */
const Dev = {
    post(name, d) {
        if (name === 'customStart') return { values: { saddles: 12, blankets: 3 } };
        if (name === 'wagonCustomStart') return { values: { livery: 2, tint: 0, propset: 0, lantern: 1, extras: [1] }, max: { livery: 16, tint: 5, propset: 2, lantern: 3 }, liveryNames: ['0 - Simple Red Yellow', '1 - Tapered Yellow Cream', '2 - Squared Gold Black'], extras: [1, 2, 3] };
        if (['buyHorse', 'buyWagon', 'heal', 'rename', 'transfer', 'sell', 'repair', 'customSave', 'coatSave', 'wagonCustomSave', 'breed'].includes(name)) return { ok: true, data: S.data };
        return {};
    },
};

if (!IN_GAME) {
    const coat = (id, label, cash, gold, tier) => ({ id, label, cash, gold, tier, storage: 120, pelts: 5, canBreed: true, model: 'x' });
    window.postMessage({
        action: 'open',
        stable: { id: 'blackwater', label: 'Blackwater Stable', services: { buyHorses: true, customize: true, coloring: true, transfer: true, breeding: true, buyWagons: true, customizeWagons: true } },
        locale: {}, // (keys show as-is in the browser; in game the texts come from locales/)
        config: {
            categories: ['saddles', 'blankets', 'horns', 'stirrups', 'saddlebags', 'bedrolls', 'holsters', 'manes', 'tails', 'masks', 'mustaches'],
            componentMax: { saddles: 179, blankets: 66, horns: 67, stirrups: 54, saddlebags: 87, bedrolls: 30, holsters: 23, manes: 245, tails: 91, masks: 51, mustaches: 16 },
            palettes: 21, prices: { components: { saddles: 25, blankets: 5 }, coloring: 25, wagon: { livery: 15, tint: 10, extra: 3, propset: 20, lantern: 8 } }, transferPrice: 50,
            stables: [{ id: 'blackwater', label: 'Blackwater Stable' }, { id: 'example', label: 'Example Stable' }],
        },
        data: {
            money: { cash: 12450, gold: 32 }, limits: { horses: 5, wagons: 3 }, canColor: true, isTrainer: true, breeding: [], breedCfg: { time: 120, price: 0 },
            shopHorses: [
                { breed: 'Friesian', info: 'Black, elegant and with a full mane.', stats: { speed: 5, accel: 5, health: 6, stamina: 6, handling: 2 }, coats: [coat('a', 'Jet Black', 4500, 0, 2), coat('b', 'Brown', 4500, 0, 2), coat('c', 'Gold', 4500, 20, 3)] },
                { breed: 'Missouri Fox Trotter', info: 'Smooth gait and great top speed.', stats: { speed: 7, accel: 5, health: 6, stamina: 7, handling: 3 }, coats: [coat('d', 'Silver Dapple Pinto', 36000, 0, 4)] },
            ],
            shopWagons: [{ category: 'Hunting Wagons', wagons: [{ model: 'wagon05x', label: 'Hunting Wagon', cash: 2500, gold: 0, storage: 500, animals: 50, description: 'A good wagon for hunting and storage.' }] }],
            horses: [
                { id: 1, name: 'Thunder', breed: 'Arabian', coatLabel: 'White', xp: 520, xpMax: 3000, bond: 3, age: 7.2, old: false, gender: 'male', health: 88, stamina: 72, hunger: 64, thirst: 15, dirt: 30, dead: false, active: true, spawned: true, stable: 'blackwater', stableLabel: 'Blackwater Stable', here: true, canBreed: true, sell: { amount: 1350, currency: 'cash' }, heal: 15, rename: 5 },
                { id: 2, name: 'Cinnamon', breed: 'Mustang', coatLabel: 'Buckskin', xp: 20, xpMax: 1000, bond: 1, age: 4, gender: 'female', health: 0, stamina: 40, hunger: 90, thirst: 90, dirt: 0, dead: true, active: false, stable: 'example', stableLabel: 'Example Stable', here: false, sell: { amount: 225, currency: 'cash' }, heal: 60, rename: 5 },
            ],
            wagons: [{ id: 1, name: 'Old Betsy', label: 'Hunting Wagon', category: 'Hunting Wagons', storage: 500, animals: 50, health: 640, active: true, spawned: false, stable: 'blackwater', stableLabel: 'Blackwater Stable', here: true, sell: { amount: 100, currency: 'cash' }, repair: 40, rename: 5 }],
        },
    }, '*');
    document.body.style.background = 'radial-gradient(circle at 70% 50%, #4a4136, #16130f)';
}
