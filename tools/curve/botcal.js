// «человеческий» бот: решает раз в RT кадров (реакция), рывок — не всегда; без читов, с настоящими жизнями.
// LV=[индексы], DIFF, SEEDS=[...], RT, PAGE (файл), OUT (json)
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1100, height: 760 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.addInitScript(([k, inf, km]) => { window.__KALL = k; window.__INF = inf; window.__KMAP = km ? JSON.parse(km) : null; }, [process.env.KALL || '', !!process.env.INF, process.env.KMAP ? require('fs').readFileSync(process.env.KMAP, 'utf8') : '']);
  await p.goto('file://' + process.cwd() + '/' + (process.env.PAGE || 'wrapped.html')); await p.waitForTimeout(300);
  const levels = JSON.parse(process.env.LV);
  const seeds = process.env.SEEDS ? JSON.parse(process.env.SEEDS) : [7, 101, 4242, 9001];
  const res = await p.evaluate(([diff, levels, seeds, RT, ovr]) => {
    save.diff = diff;
    if (ovr) Object.assign((typeof DIFF_OFF !== 'undefined' ? DIFF_OFF : DIFF)[diff], ovr);
    const KALL = +(window.__KALL || 0), KMAP = window.__KMAP || null, INF = !!window.__INF;
    const res = [];
    for (const i of levels) for (const seed of seeds) {
      let x = seed; const rnd = () => { x = (x * 16807) % 2147483647; return (x - 1) / 2147483646; };
      Math.random = rnd;
      let y = seed * 7 + 3; const brnd = () => { y = (y * 48271) % 2147483647; return (y - 1) / 2147483646; };
      if (KALL) LEVELS[i].k = KALL; else if (KMAP) LEVELS[i].k = KMAP[i];
      newRun(i); const start = lives; let steps = 0, hits = 0, prevL = lives, jx = 0, jy = 0;
      while (phase === 'game' && steps < 9000) {
        if (steps % RT === 0) {
          let ax = 0, ay = 0;
          const P = player;
          let tx = null, ty = null;
          if (portal) { tx = portal.x; ty = portal.y; }
          else if (boss && emp > 0 && !boss.shield && !boss.hid) { tx = boss.x; ty = boss.y; }
          else if (data.length) { let best = 1e9; for (const d of data) { const q = Math.hypot(d.x - P.x, d.y - P.y); if (q < best) { best = q; tx = d.x; ty = d.y; } } }
          if (tx !== null) { const q = Math.hypot(tx - P.x, ty - P.y) || 1; ax += (tx - P.x) / q; ay += (ty - P.y) / q; }
          let danger = 0, near = 0;
          for (const e of enemies) { if (e.trip > 0 || e.type === 'trojan' && !e.arm) continue; const q = Math.hypot(e.x - P.x, e.y - P.y) || 1; if (q < 100) { ax -= (e.x - P.x) / q * (100 - q) / 40; ay -= (e.y - P.y) / q * (100 - q) / 40; near++; if (q < 40) danger++; } }
          for (const u of bullets) { const q = Math.hypot(u.x - P.x, u.y - P.y) || 1; if (q < 60) { const fx = -(u.vy), fy = u.vx, s = Math.sign(fx * (P.x - u.x) + fy * (P.y - u.y)) || 1; ax += fx * s / 3 * (60 - q) / 40; ay += fy * s / 3 * (60 - q) / 40; if (q < 28) danger++; } }
          if (boss) { const q = Math.hypot(boss.x - P.x, boss.y - P.y) || 1; if (q < 140 && !(emp > 0)) { ax -= (boss.x - P.x) / q * 2; ay -= (boss.y - P.y) / q * 2; } if (q < boss.r + 30) danger++; }
          for (const st of strikes) { const q = Math.hypot(st.x - P.x, st.y - P.y) || 1; if (q < STRIKE_R + 25) { ax -= (st.x - P.x) / q * 3; ay -= (st.y - P.y) / q * 3; if (st.t < 25) danger++; } }
          for (const h of holes) { const q = Math.hypot(h.x - P.x, h.y - P.y) || 1; if (q < h.r + 70) { ax -= (h.x - P.x) / q * 2.5; ay -= (h.y - P.y) / q * 2.5; if (q < h.r + 25) danger++; } }
          if (boss && boss.arms) for (let k = 0; k < 3; k++) {
            const a = boss.ang + k * TAU / 3, ux = Math.cos(a), uy = Math.sin(a), t = Math.max(boss.r * 0.6, Math.min(boss.r + KRAKEN_ARM, (P.x - boss.x) * ux + (P.y - boss.y) * uy));
            const nx = boss.x + ux * t, ny = boss.y + uy * t, q = Math.hypot(P.x - nx, P.y - ny) || 1;
            if (q < 55) { ax += (P.x - nx) / q * 3; ay += (P.y - ny) / q * 3; if (q < 26) danger++; }
          }
          // таран: игрок видит красную линию прицела и уходит с неё
          if (boss && (boss.mode === 'aim' || boss.mode === 'dash') && boss.kind !== 'traffic') {
            const vx = boss.mode === 'aim' ? boss.tx - boss.x : boss.cvx, vy = boss.mode === 'aim' ? boss.ty - boss.y : boss.cvy, vl = Math.hypot(vx, vy) || 1;
            const ux = vx / vl, uy = vy / vl, px = P.x - boss.x, py = P.y - boss.y, along = px * ux + py * uy, side = px * -uy + py * ux;
            if (along > 0 && Math.abs(side) < 70) { const sg = Math.sign(side) || 1; ax += -uy * sg * 3; ay += ux * sg * 3; }
          }
          // неточность руки: небольшой случайный поворот
          const an = (brnd() - 0.5) * 0.6, ca = Math.cos(an), sa = Math.sin(an);
          const rx = ax * ca - ay * sa, ry = ax * sa + ay * ca;
          const l = Math.hypot(rx, ry) || 1; jx = rx / l; jy = ry / l;
          if (invs.length && inInv(P.x, P.y)) { jx = -jx; jy = -jy; }
          if (danger && P.dashCd === 0 && brnd() < 0.5) pressed.dash = 8;
          if (near >= 2 && P.tripCd === 0 && brnd() < 0.5) pressed.trip = 8;
          const close = enemies.filter(e => e.type !== 'trojan' && Math.hypot(e.x - P.x, e.y - P.y) < 150).length;
          if (emp > 0 && P.empCd === 0 && (close >= 3 || (boss && bossDist(boss) < 160 && !boss.shield && !boss.hid))) pressed.emp = true;
        }
        joy.x = jx; joy.y = jy;
        step(); steps++;
        if (lives < prevL) hits += prevL - lives; prevL = lives;
        if (INF && phase === 'game') { lives = 9; prevL = 9; }
      }
      res.push({ lv: i + 1, r: phase === 'clear' || phase === 'win' ? 'ok' : (phase === 'dead' ? 'dead' : 'time'), hits, sec: Math.round(steps / 60) });
      if (phase !== 'menu') goMenu();
    }
    return res;
  }, [process.env.DIFF || 'easy', levels, seeds, +(process.env.RT || 12), process.env.OVR ? JSON.parse(process.env.OVR) : null]);
  fs.writeFileSync(process.env.OUT, JSON.stringify({ res, errs }));
  await b.close();
})();
