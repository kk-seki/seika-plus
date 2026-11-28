/* GLOBALG.A.P. Supply Chain Portal（https://prod.osapiens.cloud/portal/webbundle/foodplus/field-service-os/supply-chain-portal?app-route-hash=%252Fcertificates）
   を開いたタブで実行する。window.__ggap(['GGN', ...]) を定義する（ログインしない・1件ごとに間をあける）。
   使い方：window.__ggapRun(['GGN', ...]) で始め（すぐ返る）、window.__ggapState を数秒ごとに読む（done が true になったら out が結果）。
   結果：[{ggn, result:'certified'|'expired'|'not_found'|'not_searched', valid_to:'YYYY-MM-DD', group_name, producer, certs:[...]}]
   certified＝「Integrated Farm Assurance (IFA)」が Certified の行があり、その中でいちばん新しい Valid to。 */
window.__ggap = async function (ggns) {
  // 待ち時間：画面が裏（見えていない）でも遅くならないように、setTimeout ではなく MessageChannel で待つ
  const sleep = ms => new Promise(res => { const end = performance.now() + ms; const ch = new MessageChannel();
    ch.port1.onmessage = () => { if (performance.now() >= end) { ch.port1.close(); res(); } else ch.port2.postMessage(0); }; ch.port2.postMessage(0); });
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
      // 認証の行は画面の文字ではなく、表の行のデータ（validTo など）から読む（画面が狭い・裏にあると列が描かれないため）
      const rowData = () => {
        const seen = new Map();
        for (const el of d.querySelectorAll('[role=row]')) {
          const k = Object.keys(el).find(x => x.startsWith('__reactFiber'));
          let f = k ? el[k] : null;
          for (let i = 0; i < 25 && f; i++, f = f.return) {
            const r = f.memoizedProps && f.memoizedProps.row;
            if (r && r.farmAssuranceProduct) { seen.set(String(r.certificateId || seen.size), r); break; }
          }
        }
        return [...seen.values()];
      };
      let certs = [];
      for (let i = 0; i < 30; i++) {
        await sleep(500);
        certs = rowData();
        if (certs.length) { await sleep(800); certs = rowData(); break; }
      }
      const ymd = ms => ms ? new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo' }).format(new Date(ms)) : '';
      o.certs = certs.map(c => ({ product: c.farmAssuranceProduct || '', status: c.status || '', status_id: c.statusId || '',
        valid_to: ymd(c.validTo), group_ggn: c.groupGgn || c.groupGGN || '', group_name: c.groupName || '',
        cb: c.certificationBodyName || '' }));
      if (!certs.length) o.result = 'not_searched';
      else {
        const ok = o.certs.filter(c => /Integrated Farm Assurance/i.test(c.product) && (/^Certified$/i.test(c.status) || /CERTIFIED$/.test(c.status_id)) && c.valid_to)
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
window.__ggapRun = function (ggns) {
  window.__ggapState = { done: false, out: null, error: null };
  window.__ggap(ggns).then(r => { window.__ggapState = { done: true, out: r, error: null }; })
    .catch(e => { window.__ggapState = { done: true, out: null, error: String(e) }; });
  return 'started';
};
'ok';
