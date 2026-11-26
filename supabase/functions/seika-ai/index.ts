// v1.199-c165 SEIKA＋の AI（Claude）呼び出し口
// ・アプリから呼ぶ。ログイン中の人の権限で動く（データは ai_data_v1199c165 を、その人のログインのまま読む。書き込みはしない）。
// ・使えるのは 管理者・青果社員・仕入れ担当・営業。
// ・action：summary（毎日のまとめ）／ask（聞けば答える）／photo（写真で品質評価の候補）／parse_assist（帳票の読めなかった行の候補）
// ・APIキーはシークレット ANTHROPIC_API_KEY。月の上限（ドル）は AI_MONTHLY_LIMIT_USD（なければ 80）。使った量は ai_usage_v1199c165 に残す。
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

const ROLES = new Set(['admin', 'worker', 'buyer', 'sales'])
const MODEL = 'claude-sonnet-5-5'
// 100万トークンあたりのドル（入力・出力）
const PRICE: Record<string, [number, number]> = { 'claude-sonnet-5-5': [2, 10], 'claude-haiku-5-5': [0.1, 0.5] }
const KINDS = ['stock', 'outbound', 'waste', 'plan', 'actual', 'plan_vs_actual', 'trimming', 'quality', 'gap', 'prices']
const ISSUES = ['傷み', '変色', '腐敗', 'カビ', '打撲・傷', 'しおれ', '異臭', '規格外', '温度異常', 'その他']
const ROLE_LABEL: Record<string, string> = { admin: '管理者', worker: '青果社員', buyer: '仕入れ担当', sales: '営業' }

type Usage = { input: number; output: number }
const jstToday = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Tokyo' })
const addDays = (d: string, n: number) => { const t = new Date(d + 'T00:00:00Z'); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10) }
const clean = (v: unknown, max = 500) => String(v ?? '').trim().slice(0, max)
const costOf = (model: string, u: Usage) => { const p = PRICE[model] ?? PRICE[MODEL]; return (u.input * p[0] + u.output * p[1]) / 1e6 }

function firstJson(text: string): any {
  const s = text.indexOf('{'), e = text.lastIndexOf('}')
  if (s < 0 || e <= s) throw new Error('AIの答えを読めませんでした')
  return JSON.parse(text.slice(s, e + 1))
}

async function claude(key: string, body: Record<string, unknown>, usage: Usage) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, ...body }),
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(`AIを呼び出せませんでした（${res.status}）${data?.error?.message ? '：' + data.error.message : ''}`)
  usage.input += Number(data?.usage?.input_tokens ?? 0) + Number(data?.usage?.cache_read_input_tokens ?? 0) + Number(data?.usage?.cache_creation_input_tokens ?? 0)
  usage.output += Number(data?.usage?.output_tokens ?? 0)
  return data
}
const textOf = (data: any) => (data?.content ?? []).filter((c: any) => c.type === 'text').map((c: any) => c.text).join('').trim()

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json(405, { ok: false, message: 'POST だけです' })

  const url = Deno.env.get('SUPABASE_URL'), anonKey = Deno.env.get('SUPABASE_ANON_KEY'), serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
  const limit = Number(Deno.env.get('AI_MONTHLY_LIMIT_USD') ?? '80') || 80
  if (!url || !anonKey || !serviceKey) return json(500, { ok: false, message: 'Edge Function の設定が足りません' })
  if (!apiKey) return json(503, { ok: false, code: 'no_key', message: 'AIの準備（APIキーの設定）がまだです。管理者に連絡してください。' })

  const authorization = req.headers.get('Authorization') ?? ''
  if (!authorization.startsWith('Bearer ')) return json(401, { ok: false, message: 'ログインし直してください' })
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } })
  const { data: who, error: whoErr } = await caller.auth.getUser()
  if (whoErr || !who.user) return json(401, { ok: false, message: 'ログインを確認できませんでした' })
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: me } = await admin.from('profiles').select('id,display_name,role,active').eq('id', who.user.id).maybeSingle()
  if (!me || !me.active) return json(403, { ok: false, message: 'このアカウントは使えません' })
  // c166：しばらくは管理者だけ。広げるときはシークレット AI_ALLOWED_ROLES（例：admin,worker,buyer,sales）
  const allowed = new Set((Deno.env.get('AI_ALLOWED_ROLES') ?? 'admin').split(',').map((x) => x.trim()).filter((x) => ROLES.has(x)))
  if (!ROLES.has(me.role) || !allowed.has(me.role)) return json(403, { ok: false, message: 'AIは今は管理者だけが使えます' })

  let body: Record<string, any>
  try { body = await req.json() } catch { return json(400, { ok: false, message: '送られた内容を読めません' }) }
  const action = clean(body.action, 32)
  if (!['summary', 'ask', 'photo', 'parse_assist'].includes(action)) return json(400, { ok: false, message: '知らない操作です' })
  if (action === 'parse_assist' && me.role !== 'admin') return json(403, { ok: false, message: '帳票の読み取りの補助は管理者だけです' })
  if (action === 'photo' && !['admin', 'worker'].includes(me.role)) return json(403, { ok: false, message: '品質評価は管理者・青果社員だけです' })

  // 月の上限
  const monthStart = new Date(jstToday().slice(0, 8) + '01T00:00:00+09:00').toISOString()
  const { data: spent } = await admin.from('ai_usage_v1199c165').select('cost_usd').gte('created_at', monthStart).limit(20000)
  const used = (spent ?? []).reduce((a: number, r: any) => a + Number(r.cost_usd || 0), 0)
  if (used >= limit) return json(429, { ok: false, code: 'limit', message: `今月のAIの上限（${limit}ドル）に達しました。来月まで使えません。` })

  const usage: Usage = { input: 0, output: 0 }
  const log = async (ok: boolean, note = '') => {
    await admin.from('ai_usage_v1199c165').insert({ user_id: me.id, user_name: me.display_name ?? '', role: me.role, action, model: MODEL,
      input_tokens: usage.input, output_tokens: usage.output, cost_usd: costOf(MODEL, usage), ok, note: note.slice(0, 300) })
  }
  const data = async (kind: string, from?: string, to?: string, item?: string, customer?: string) => {
    const { data: d, error } = await caller.rpc('ai_data_v1199c165', { p_kind: kind, p_from: from ?? null, p_to: to ?? null, p_item: item ?? null, p_customer: customer ?? null })
    if (error) return { kind, error: error.message }
    return d
  }
  const today = jstToday()

  try {
    if (action === 'summary') {
      const force = body.force === true && me.role === 'admin'
      const role = me.role === 'admin' && ROLES.has(clean(body.role, 16)) ? clean(body.role, 16) : me.role
      if (!force) {
        const { data: row } = await admin.from('ai_daily_summaries_v1199c165').select('body,created_at').eq('day', today).eq('role', role).maybeSingle()
        if (row) return json(200, { ok: true, cached: true, day: today, role, body: row.body, created_at: row.created_at })
      }
      const t1 = addDays(today, 1), t3 = addDays(today, 3), w = addDays(today, -7), d3 = addDays(today, -3)
      const plan: Record<string, Promise<unknown>[]> = {
        admin: [data('plan_vs_actual', w, today), data('plan', t1, t3), data('stock'), data('waste', w, today), data('quality', d3, today), data('gap')],
        buyer: [data('plan', t1, t3), data('stock'), data('prices', w, today), data('quality', d3, today), data('gap')],
        sales: [data('plan', t1, t3), data('plan_vs_actual', w, today), data('actual', addDays(today, -1), today)],
        worker: [data('plan', t1, addDays(today, 2)), data('stock'), data('trimming', w, today), data('quality', d3, today)],
      }
      const facts = await Promise.all(plan[role])
      const r = await claude(apiKey, {
        max_tokens: 4000,
        system: `あなたは青果センターの業務アプリ「SEIKA＋」のアシスタントです。今日は ${today} です。読む人は「${ROLE_LABEL[role]}」です。
渡したデータだけを使い、「今日のまとめ」を日本語で3〜5行に書きます。
・1行は40字くらいまで。行頭は「・」。結論から。品目名・客先名・数字（kg など）を入れる。
・その役割の人が今日すぐ動けること（足りない・余る・期限が近い・差が大きいなど）を先に書く。
・データにないことは書かない。推測で数字を作らない。データが空なら「該当するデータはありません」と書く。
・予定と確定：確定は産地報告書の数のこと（「実績」とは書かず「確定」と書く）。plan_vs_actual の status が「キャンセル（産地報告書にない）」の行は、未入力ではなくキャンセルとして書く。埼玉・深谷（社内）は産地報告書に入らないので、予定と確定の比べには出さない。別便（産地報告書に入れないで出荷している客先×品目。例：フジフーズのじゃが芋）も比べに出ない。予定にあって確定にないものを、別便かもしれないのに決めつけてキャンセルと強く書かない。
・難しい言葉を使わない。前置きや締めの言葉は書かない。**などの記号（マークダウン）は使わない。`,
        messages: [{ role: 'user', content: JSON.stringify(facts) }],
      }, usage)
      const text = textOf(r)
      if (!text) throw new Error(r.stop_reason === 'max_tokens' ? 'まとめが長くなりすぎて作れませんでした' : 'まとめを作れませんでした')
      await admin.from('ai_daily_summaries_v1199c165').upsert({ day: today, role, body: text, model: MODEL, created_at: new Date().toISOString() })
      await log(true, role)
      return json(200, { ok: true, cached: false, day: today, role, body: text })
    }

    if (action === 'ask') {
      const question = clean(body.question, 500)
      if (!question) return json(400, { ok: false, message: '聞きたいことを入れてください' })
      const history = (Array.isArray(body.history) ? body.history : []).slice(-3)
      const messages: any[] = []
      for (const h of history) { messages.push({ role: 'user', content: clean(h.q, 500) }); messages.push({ role: 'assistant', content: clean(h.a, 1500) || '（答えなし）' }) }
      messages.push({ role: 'user', content: question })
      const tools = [{
        name: 'get_data',
        description: `SEIKA＋のデータを読む（読むだけ）。kind：stock 今の在庫（品目ごと）／outbound 出庫（品目×出庫先、期間）／waste 廃棄（期間。廃棄記録・QR廃棄・トリミング廃棄を品目ごとに。source で区別）／plan 出荷予定（納品日×客先×品目）／actual 確定数量（産地報告書）／plan_vs_actual 予定と確定（産地報告書）の差。社外の客先だけ。status 付き／trimming 下処理（トリミング）の原料・出来高・歩留まり／quality 品質評価（要確認・不良）／gap GAP認証の期限（期限切れと90日以内）／prices 仕入れ価格（週ごと。管理者・仕入れ担当だけ）。from・to は YYYY-MM-DD（最大92日）。item・customer は名前の一部でしぼる。1回80行まで。`,
        input_schema: { type: 'object', properties: { kind: { type: 'string', enum: KINDS }, from: { type: 'string' }, to: { type: 'string' }, item: { type: 'string' }, customer: { type: 'string' } }, required: ['kind'] },
      }]
      const used: unknown[] = []
      let answer = ''
      for (let turn = 0; turn < 6; turn++) {
        const r = await claude(apiKey, {
          max_tokens: 4000, tools,
          system: `あなたは青果センターの業務アプリ「SEIKA＋」のアシスタントです。今日は ${today}（日本時間）です。聞いている人は「${ROLE_LABEL[me.role]}」です。
質問には、get_data で読んだデータだけを根拠に、日本語で短く答えます。
・結論を先に、2〜6行で。数字には単位（kg・ケースなど）と期間を付ける。必要なら「・」の箇条書き。
・データで分からないことは「SEIKA＋のデータでは分かりません」と言い、推測で数字を作らない。
・「先週」は今日の7日前から昨日まで、「今月」は今月1日から今日まで、のように日付に直して調べる。
・この会社では「廃棄」にはトリミング廃棄（下処理で出た廃棄）も含む。waste はトリミング廃棄も入った廃棄のデータなので、「廃棄」と聞かれたら waste を調べ、廃棄記録・QR廃棄・トリミング廃棄を足した合計を答え、内訳も書く（単位が違うものは足さずに分けて書く）。waste の行に source「トリミング廃棄」が1つもないときは、trimming も調べてその waste_kg をトリミング廃棄として足す。
・予定と確定：確定は産地報告書の数のこと（「実績」とは書かず「確定」と書く）。plan_vs_actual の status が「キャンセル（産地報告書にない）」の行は、未入力ではなくキャンセルとして書く。埼玉・深谷（社内）は産地報告書に入らないので、予定と確定の比べには出さない。別便（産地報告書に入れないで出荷している客先×品目。例：フジフーズのじゃが芋）も比べに出ない。予定にあって確定にないものを、別便かもしれないのに決めつけてキャンセルと強く書かない。
・**などの記号（マークダウン）は使わない。
・在庫・伝票・設定を変えることはできない。頼まれたら、アプリのどの画面でできるかだけ案内する。`,
          messages,
        }, usage)
        messages.push({ role: 'assistant', content: r.content })
        if (r.stop_reason !== 'tool_use') { answer = textOf(r); break }
        const results = []
        for (const c of r.content ?? []) {
          if (c.type !== 'tool_use') continue
          const i = c.input ?? {}
          const kind = KINDS.includes(i.kind) ? i.kind : 'stock'
          const d = await data(kind, clean(i.from, 10) || undefined, clean(i.to, 10) || undefined, clean(i.item, 40) || undefined, clean(i.customer, 40) || undefined)
          used.push({ kind, from: i.from ?? null, to: i.to ?? null, item: i.item ?? null, customer: i.customer ?? null })
          results.push({ type: 'tool_result', tool_use_id: c.id, content: JSON.stringify(d).slice(0, 30000) })
        }
        messages.push({ role: 'user', content: results })
      }
      if (!answer) answer = '答えをまとめられませんでした。聞き方を変えて、もう一度お試しください。'
      await log(true, question.slice(0, 120))
      return json(200, { ok: true, answer, used })
    }

    if (action === 'photo') {
      const image = String(body.image ?? '').replace(/^data:image\/\w+;base64,/, '')
      if (!image || image.length > 1_400_000) return json(400, { ok: false, message: '写真を読み込めませんでした（大きすぎるか、空です）' })
      const item = clean(body.item_name, 40)
      const r = await claude(apiKey, {
        max_tokens: 3000,
        system: `あなたは青果の品質を見る担当者を手伝います。写真の野菜（${item || '品目不明'}）の見た目から、品質評価の「候補」を出します。最後は人が決めます。
答えは JSON だけ：{"grade":"good|review|bad","issues":[…],"memo":"40字くらいの日本語","confidence":"high|medium|low"}
・grade：good 良好／review 要確認／bad 不良。
・issues は次から選ぶ（なければ空）：${ISSUES.join('、')}
・写真で分からないこと（におい・温度など）は判断しない。写真がぼやけている・野菜が写っていないときは confidence を low にして memo に書く。`,
        messages: [{ role: 'user', content: [{ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } }, { type: 'text', text: 'この写真の品質評価の候補を出してください。' }] }],
      }, usage)
      const out = firstJson(textOf(r))
      const grade = ['good', 'review', 'bad'].includes(out.grade) ? out.grade : 'review'
      const issues = (Array.isArray(out.issues) ? out.issues : []).filter((x: string) => ISSUES.includes(x))
      await log(true, item)
      return json(200, { ok: true, grade, issues: grade === 'good' ? [] : issues, memo: clean(out.memo, 200), confidence: ['high', 'medium', 'low'].includes(out.confidence) ? out.confidence : 'medium' })
    }

    // parse_assist：積み込み表・産地報告書で、今のルールで読めなかった行の「候補」を出す（決めるのは管理者）
    const kind = body.kind === 'actual' ? '産地報告書' : '積み込み表'
    const master = (Array.isArray(body.master_items) ? body.master_items : []).map((x: unknown) => clean(x, 40)).filter(Boolean).slice(0, 600)
    const customers = (Array.isArray(body.known_customers) ? body.known_customers : []).map((x: unknown) => clean(x, 60)).filter(Boolean).slice(0, 400)
    const ask = {
      items: (Array.isArray(body.items) ? body.items : []).slice(0, 60).map((x: any) => ({ key: clean(x.key, 120), name: clean(x.base, 80), samples: (x.samples ?? []).slice(0, 3).map((s: unknown) => clean(s, 80)) })),
      qty: (Array.isArray(body.qty) ? body.qty : []).slice(0, 80).map((x: any) => ({ key: clean(x.key, 160), item: clean(x.item, 60), qty: clean(x.qty_raw, 80), unit: clean(x.unit, 10), case_kg: Number(x.case_kg) || null, customer: clean(x.customer, 60) })),
      customers: (Array.isArray(body.customers) ? body.customers : []).slice(0, 60).map((x: any) => ({ key: clean(x.key, 160), raw: clean(x.raw, 80), note: clean(x.note, 80) })),
    }
    if (!ask.items.length && !ask.qty.length && !ask.customers.length) return json(400, { ok: false, message: '読めなかった行がありません' })
    const r = await claude(apiKey, {
      max_tokens: 8000,
      system: `あなたは青果センターの「${kind}」の読み取りを手伝います。今のルールで読めなかった行について「候補」を出します。決めるのは管理者です。
答えは JSON だけ：{"items":[{"key":"…","item":"品目マスタの名前 か null","reason":"20字まで"}],"qty":[{"key":"…","kg":数値 か null,"reason":"計算の式（例：15kg×13+5kg×1）"}],"customers":[{"key":"…","customer":"客先の一覧の名前 か null","reason":"20字まで"}]}
・item は必ず「品目マスタ」にある名前から選ぶ。自信がないときは null。「大根」とだけ書いてあるものは、カット大根・葉付き大根などと取り違えないよう、根拠がなければ null。
・kg は書き方から合計の kg を計算する（例：「15kg*13.5kg*1」→ 15kg×13箱＋5kg×1箱＝200）。ケース数だけのときは case_kg（標準ケースの重さ）を使う。分からないときは null。
・customer は「客先の一覧」から選ぶ。自信がないときは null。
品目マスタ：${master.join('、')}
客先の一覧：${customers.join('、')}`,
      messages: [{ role: 'user', content: JSON.stringify(ask) }],
    }, usage)
    const out = firstJson(textOf(r))
    const keys = (a: any[]) => new Set(a.map((x) => x.key))
    const ik = keys(ask.items), qk = keys(ask.qty), ck = keys(ask.customers)
    const items = (out.items ?? []).filter((x: any) => ik.has(x.key) && x.item && master.includes(x.item)).map((x: any) => ({ key: x.key, item: x.item, reason: clean(x.reason, 60) }))
    const qty = (out.qty ?? []).filter((x: any) => qk.has(x.key) && Number(x.kg) > 0 && Number(x.kg) < 100000).map((x: any) => ({ key: x.key, kg: Math.round(Number(x.kg) * 1000) / 1000, reason: clean(x.reason, 80) }))
    const cust = (out.customers ?? []).filter((x: any) => ck.has(x.key) && x.customer && customers.includes(x.customer)).map((x: any) => ({ key: x.key, customer: x.customer, reason: clean(x.reason, 60) }))
    await log(true, `${kind} 品目${items.length}/${ask.items.length} 数量${qty.length}/${ask.qty.length} 客先${cust.length}/${ask.customers.length}`)
    return json(200, { ok: true, items, qty, customers: cust })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    await log(false, message).catch(() => {})
    return json(500, { ok: false, message })
  }
})
