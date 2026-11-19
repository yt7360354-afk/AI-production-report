// 리포트 페이지 공용 헤더. data.js 다음에 불러온다.

function renderTop(active) {
  const items = [['리포트', 'B-daily.html']]
  document.querySelector('header.top').innerHTML = `
    <a class="brand" href="B-daily.html"><i data-lucide="factory"></i>라인가동현황</a>
    <nav class="nav">${items.map(([n, h]) => `<a href="${h}"${n === active ? ' class="on" aria-current="page"' : ''}>${n}</a>`).join('')}</nav>
    <div class="r">
      <span class="clock">${NOW.date}<b>${NOW.time}</b></span>
      <button class="bell" aria-label="알림 5건"><i data-lucide="bell"></i><span>5</span></button>
      <span class="me"><i data-lucide="circle-user"></i>김현수</span>
    </div>`
}
