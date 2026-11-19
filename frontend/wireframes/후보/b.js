// 리포트 페이지 공용 헤더. data.js 다음에 불러온다.

function renderTop(active) {
  const items = [['AI 리포트', 'B-daily.html']]
  document.querySelector('header.top').innerHTML = `
    <a class="brand" href="B-daily.html"><i data-lucide="factory"></i>라인가동현황</a>
    <nav class="nav">${items.map(([n, h]) => `<a href="${h}"${n === active ? ' class="on" aria-current="page"' : ''}>${n}</a>`).join('')}</nav>
    <div class="r">
      <span class="clock">${NOW.date}<b>${NOW.time}</b></span>
      <button class="bell" aria-label="알림 5건"><i data-lucide="bell"></i><span>5</span></button>
      <span class="me"><i data-lucide="circle-user"></i>김현수</span>
    </div>`
}

// 이전 보고서 기간 검색. root 안에서 data-date 날짜 묶음 뒤에 오는 <a> 항목을 기간으로 거른다.
// 반환값 apply() 는 목록에 항목을 새로 넣은 뒤 다시 거를 때 부른다.
function initPeriodFilter(root, heading) {
  const ymd = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  const form = document.createElement('form')
  form.className = 'period-filter'
  form.setAttribute('role', 'search')
  form.setAttribute('aria-label', '이전 보고서 기간 검색')
  form.innerHTML = `
    <label><span>시작일</span><input type="date" name="from"></label>
    <span class="sep" aria-hidden="true">~</span>
    <label><span>종료일</span><input type="date" name="to"></label>
    <div class="period-bar">
      <div class="seg" role="group" aria-label="기간 빠른 선택">
        <button type="button" data-days="7">최근 7일</button><button type="button" data-days="30">최근 30일</button><button type="button" data-days="0" class="on" aria-pressed="true">전체</button>
      </div>
      <p class="period-msg" role="status" aria-live="polite"></p>
    </div>`
  heading.after(form)
  const empty = document.createElement('p')
  empty.className = 'period-empty'
  empty.textContent = '선택한 기간에 작성한 보고서가 없습니다.'
  empty.hidden = true
  root.append(empty)
  const { from, to } = form.elements
  const msg = form.querySelector('.period-msg')
  const presets = [...form.querySelectorAll('[data-days]')]
  const markPreset = btn => presets.forEach(b => { b.classList.toggle('on', b === btn); b.setAttribute('aria-pressed', String(b === btn)) })

  const apply = () => {
    const start = from.value, end = to.value
    const invalid = start && end && start > end
    to.setAttribute('aria-invalid', String(Boolean(invalid)))
    let date = '', shown = 0, group = null, groupShown = 0
    const closeGroup = () => { if (group) group.hidden = groupShown === 0 }
    for (const el of root.children) {
      if (el.dataset.date) { closeGroup(); group = el; groupShown = 0; date = el.dataset.date; continue }
      if (el.tagName !== 'A') continue
      const visible = !invalid && (!start || date >= start) && (!end || date <= end)
      el.hidden = !visible
      if (visible) { shown += 1; groupShown += 1 }
    }
    closeGroup()
    empty.hidden = invalid || shown > 0
    msg.classList.toggle('err', Boolean(invalid))
    msg.textContent = invalid ? '시작일이 종료일보다 늦습니다' : `${shown}건`
  }
  form.addEventListener('submit', e => e.preventDefault())
  form.addEventListener('input', () => { markPreset(null); apply() })
  presets.forEach(btn => btn.addEventListener('click', () => {
    const days = Number(btn.dataset.days)
    if (days) { const today = new Date(); const past = new Date(today); past.setDate(today.getDate() - (days - 1)); from.value = ymd(past); to.value = ymd(today) }
    else { from.value = ''; to.value = '' }
    markPreset(btn)
    apply()
  }))
  apply()
  return apply
}
