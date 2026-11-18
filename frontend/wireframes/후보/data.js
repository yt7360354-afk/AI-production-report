// 데모 값: 디자인 후보 비교용으로 지어낸 값이다. 실제 데이터·명세 수치가 아니다.
// 시각 2026-11-16 14:32:08 기준 한 장면.

const STATUS = { R: '가동', S: '정지', I: '대기', D: '고장' }
const NOW = { date: '2026-11-16 (월)', time: '14:32:08' }
const EQ_NAMES = ['슬리팅', '1단', '2단', '3단', '4단', '용접']

// st: 슬리팅·프레스1~4·용접 상태, dur: D 지속시간, pdm: 예지보전 (warn 주의 / danger 위험)
const LINES = [
  { id: 'L1', st: ['R', 'R', 'R', 'R', 'R', 'R'], pdm: { 5: ['warn', '전류 84%'] }, done: 131, oee: 81.2, ng: 3 },
  { id: 'L2', st: ['R', 'R', 'R', 'D', 'I', 'I'], dur: { 3: '11:56' }, done: 108, oee: 68.9, ng: 7 },
  { id: 'L3', st: ['R', 'R', 'R', 'R', 'R', 'R'], done: 127, oee: 80.4, ng: 4 },
  { id: 'L4', st: ['S', 'R', 'R', 'R', 'R', 'R'], done: 119, oee: 76.0, ng: 2 },
  { id: 'L5', st: ['R', 'R', 'R', 'R', 'R', 'R'], pdm: { 2: ['danger', '압력 92%'] }, done: 130, oee: 79.3, ng: 3 },
  { id: 'L6', st: ['R', 'R', 'R', 'R', 'R', 'R'], done: 127, oee: 82.1, ng: 2 },
]
const LINE_PLAN = 200 // 목표 1,200 ÷ 가동 라인 6
const PAINT = [{ n: '도장 #1', s: 'R' }, { n: '도장 #2', s: 'R' }]
const PAINT_LINE = { done: 751, plan: 1200, oee: 84.0, ng: 3 }
const VISION = { n: '비전', s: 'R' }
const INBOUND = { today: 24, stock: 37 }

const PROD = { target: 1200, done: 742, rate: 61.8 }
const OEE = { oee: 78.4, a: 89.1, p: 92.0, q: 95.6 }
const QUALITY = { byProc: [['슬리팅', 4], ['프레스', 11], ['용접', 6], ['도장', 3]], ok: 742, ng: 9, rate: 1.2 }
// 시간대별 생산량 (00시~13시 1시간씩, 마지막은 14:00~14:32)
const HOURLY = [48, 50, 51, 47, 52, 50, 49, 53, 51, 46, 52, 50, 54, 51, 38]

const ALERTS = [
  { on: true, t: '14:20:12', eq: 'L2 프레스 3단', s: 'D', code: '장비고장(알람)', msg: '압력 상한 초과', dur: '11:56', report: 'view' },
  { on: true, t: '14:20:40', eq: 'L2 프레스 4단', s: 'I', code: '재공부족', msg: '앞 공정 정지', dur: '11:28' },
  { on: true, t: '14:21:05', eq: 'L2 용접', s: 'I', code: '재공부족', msg: '앞 공정 정지', dur: '11:03' },
  { on: true, t: '14:10:00', eq: 'L4 슬리팅', s: 'S', code: '계획정지(셋업)', msg: '코일 교체', dur: '22:08' },
  { on: true, t: '14:02:31', eq: 'L5 프레스 2단', s: 'P', code: '예지보전 위험', msg: '압력 92%', dur: '29:37' },
  { on: false, t: '11:42:19', eq: 'L6 용접', s: 'D', code: '안전문제', msg: '비상정지', dur: '6:12', report: true },
  { on: false, t: '10:15:03', eq: '도장 #2', s: 'D', code: '장비고장(알람)', msg: '건조로 온도 상한 초과', dur: '18:40', report: true },
  { on: false, t: '09:03:44', eq: 'L1 슬리팅', s: 'I', code: '재공부족', msg: '코일 공급 지연', dur: '4:05' },
  { on: false, t: '06:31:20', eq: 'L3 프레스 1단', s: 'S', code: '계획정지', msg: '금형 교체', dur: '25:00' },
]

const fmt = (n) => n.toLocaleString('ko-KR')
const lineState = (st) => ['D', 'I', 'S', 'R'].find((c) => st.includes(c)) // D>I>S>R

function cell(name, s, { dur, pdm } = {}) {
  const p = pdm ? ` pdm-${pdm[0]}` : ''
  const tag = pdm ? `<span class="c-pdm"><span class="c-pdm-w">${pdm[0] === 'danger' ? '위험' : '주의'} </span>${pdm[1].split(' ')[1]}</span>` : ''
  return `<div class="cell s-${s}${p}" title="${name} · ${STATUS[s]}"><span class="c-in">
    <span class="c-top"><span class="c-name">${name}</span>${tag}</span>
    <span class="c-row"><span class="c-code">${s}</span><span class="c-word">${STATUS[s]}</span>${dur ? `<span class="c-dur">${dur}</span>` : ''}</span>
  </span></div>`
}

// 후보 A·B가 쓰는 공장 배치도: 입고 → 6갈래 → 라인 → 도장 2대 → 비전
function renderMap(el) {
  const lines = LINES.map((l) => `
    <div class="m-line">
      <div class="m-lid"><b>${l.id}</b><span>${l.done} / ${LINE_PLAN}</span></div>
      <div class="m-eqs">
        <div class="m-grp">${cell(EQ_NAMES[0], l.st[0], { dur: l.dur?.[0], pdm: l.pdm?.[0] })}</div>
        <div class="m-grp">${[1, 2, 3, 4].map((i) => cell(EQ_NAMES[i], l.st[i], { dur: l.dur?.[i], pdm: l.pdm?.[i] })).join('')}</div>
        <div class="m-grp">${cell(EQ_NAMES[5], l.st[5], { dur: l.dur?.[5], pdm: l.pdm?.[5] })}</div>
      </div>
    </div>`).join('')
  el.innerHTML = `
    <div class="m-head"><span></span><span></span>
      <div class="m-heq"><span>라인</span><span>슬리팅</span><span>프레스</span><span>용접</span></div>
      <span></span><span>도장</span><span></span><span>출고</span></div>
    <div class="m-body">
      <div class="m-in"><div class="cell inb"><span class="c-in"><span class="c-name">코일입고</span><span class="c-row"><span class="c-num">${INBOUND.today}</span><span class="c-word">입고</span><span class="c-sub">재고 ${INBOUND.stock}</span></span></span></div></div>
      <div class="m-branch"></div>
      <div class="m-lines">${lines}</div>
      <div class="m-branch"></div>
      <div class="m-paint">${PAINT.map((p) => cell(p.n, p.s)).join('')}</div>
      <div class="m-branch half"></div>
      <div class="m-out">${cell(VISION.n, VISION.s)}</div>
    </div>`
}

function renderAlerts(el) {
  el.innerHTML = ALERTS.map((a) => `
    <li class="al ${a.on ? 'on' : 'off'}${a.on && a.s !== 'S' ? ' t-' + a.s : ''}">
      <span class="al-code ${a.s === 'P' ? 'pdm' : 's-' + a.s}">${a.s === 'P' ? '위험' : a.s}</span>
      <div class="al-main">
        <div class="al-eq">${a.eq}</div>
        <div class="al-msg">${a.code} · ${a.msg}</div>
        ${a.report ? `<a class="al-btn" href="B-report.html">보고서 ${a.report === 'view' ? '보기' : '만들기'}</a>` : ''}
      </div>
      <div class="al-meta"><span>${a.t}</span><span class="al-dur">${a.on ? '' : '지속 '}${a.dur}</span></div>
    </li>`).join('')
}

// 오늘 생산: 목표선 vs 누적 실적 (00~24시). el 크기에 맞춰 그림
function prodChart(el) {
  const w = el.clientWidth, h = el.clientHeight
  const pad = { l: 52, r: 16, t: 12, b: 28 }
  const X = (hr) => pad.l + (hr / 24) * (w - pad.l - pad.r)
  const Y = (v) => pad.t + (1 - v / 1200) * (h - pad.t - pad.b)
  let cum = 0
  const pts = [[0, 0], ...HOURLY.map((v, i) => [i === 14 ? 14 + 32 / 60 : i + 1, (cum += v)])]
  const path = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${X(x).toFixed(1)},${Y(y).toFixed(1)}`).join('')
  const last = pts[pts.length - 1]
  const grid = [0, 400, 800, 1200].map((v) => `<line class="ch-grid" x1="${pad.l}" x2="${w - pad.r}" y1="${Y(v)}" y2="${Y(v)}"/><text class="ch-lab" x="${pad.l - 8}" y="${Y(v) + 4}" text-anchor="end">${fmt(v)}</text>`).join('')
  const xs = [0, 6, 12, 18, 24].map((t) => `<text class="ch-lab" x="${X(t)}" y="${h - 6}" text-anchor="middle">${String(t).padStart(2, '0')}시</text>`).join('')
  return `<svg viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" style="display:block" role="img" aria-label="오늘 생산 누적 실적과 목표선">
    ${grid}${xs}
    <line class="ch-now" x1="${X(last[0])}" x2="${X(last[0])}" y1="${pad.t}" y2="${h - pad.b}"/>
    <line class="ch-target" x1="${X(0)}" y1="${Y(0)}" x2="${X(24)}" y2="${Y(1200)}"/>
    <path class="ch-actual" d="${path}"/>
    <circle class="ch-dot" cx="${X(last[0])}" cy="${Y(last[1])}" r="4"/>
  </svg>`
}

function donut(size, stroke) {
  const r = (size - stroke) / 2, c = 2 * Math.PI * r
  const ngLen = (QUALITY.ng / (QUALITY.ok + QUALITY.ng)) * c
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="출고 양품 ${QUALITY.ok}, 불량 ${QUALITY.ng}">
    <circle class="dn-ok" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${stroke}" fill="none"/>
    <circle class="dn-ng" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${stroke}" fill="none"
      stroke-dasharray="${Math.max(ngLen, 3)} ${c}" transform="rotate(-90 ${size / 2} ${size / 2})"/>
  </svg>`
}
