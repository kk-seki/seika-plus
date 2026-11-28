/* GLOBALG.A.P. Supply Chain Portal（https://prod.osapiens.cloud/portal/webbundle/foodplus/field-service-os/supply-chain-portal?app-route-hash=%252Fcertificates）
   を開いたタブで実行する。window.__ggap(['GGN', ...]) を定義する（ログインしない・1件ごとに間をあける）。
   結果：[{ggn, result:'certified'|'expired'|'not_found'|'not_searched', valid_to:'YYYY-MM-DD', group_name, producer, certs:[...]}]
   certified＝「Integrated Farm Assurance (IFA)」が Certified の行があり、その中でいちばん新しい Valid to。 */
window.__ggap = async function (ggns) {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const fr = [...document.querySelectorAll('iframe')].find(f => /supply-chain-portal/.test(f.src));
  if (!fr) throw new Error('portal iframe not found');
  const d = fr.contentDocument, w = d.defaultView;
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const out = [];
  for (const g of ggns) {
    const o = { ggn: g };
    try {
      const inp = [...d.querySelectorAll('input')].find(i => i.offsetParent && !['radio', 'checkbox', 'hidden'].includes(i.type));
      const set = Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, 'value').set;
      set.call(inp, g); inp.dispatchEvent(new w.Event('input', { bubbles: true }));
      [...d.querySelectorAll('button')].find(b => /Start Search/.test(b.innerText)).click();
      let st = '';
      for (let i = 0; i < 30; i++) {
        await sleep(500);
        if (/No results found/.test(d.body.innerText)) { st = 'none'; break; }
        if ([...d.querySelectorAll('[role=row],tr')].some(r => r.innerText.includes(g))) { st = 'found'; break; }
      }
      if (st === 'none') { o.result = 'not_found'; out.push(o); await sleep(1000); continue; }
      if (st !== 'found') { o.result = 'not_searched'; out.push(o); await sleep(1000); continue; }
      const row = [...d.querySelectorAll('[role=row],tr')].find(r => r.innerText.includes(g));
      o.producer = clean(row.innerText).replace(g, '').trim().slice(0, 120);
      const btn = row.querySelector('button'); if (btn) btn.click();
      let certs = [];
      for (let i = 0; i < 20; i++) {
        await sleep(500);
        const all = [...d.querySelectorAll('[role=row],tr')]
          .map(r => [...r.querySelectorAll('[role=cell],[role=gridcell],td')].map(c => clean(c.innerText)))
          .filter(c => c.length >= 5 && c.some(x => /^\d{2}\.\d{2}\.\d{4}$/.test(x)));
        if (all.length) { certs = all; break; }
      }
      o.certs = certs.map(c => {
        const vt = c.find(x => /^\d{2}\.\d{2}\.\d{4}$/.test(x)) || '';
        const gi = c.findIndex(x => /^40\d{11}$/.test(x));
        return { product: c[0], status: c[2], valid_to: vt ? vt.split('.').reverse().join('-') : '',
                 group_ggn: gi >= 0 ? c[gi] : '', group_name: gi >= 0 ? (c[gi + 1] || '') : '' };
      });
      if (!certs.length) o.result = 'not_searched';
      else {
        const ok = o.certs.filter(c => /Integrated Farm Assurance/i.test(c.product) && /^Certified$/i.test(c.status) && c.valid_to)
          .sort((a, b) => b.valid_to.localeCompare(a.valid_to));
        if (ok.length) { o.result = 'certified'; o.valid_to = ok[0].valid_to; o.group_name = ok[0].group_name; }
        else o.result = 'expired';
      }
    } catch (e) { o.result = 'not_searched'; o.err = String(e).slice(0, 200); }
    out.push(o);
    await sleep(1000);
  }
  return out;
};
'ok';
